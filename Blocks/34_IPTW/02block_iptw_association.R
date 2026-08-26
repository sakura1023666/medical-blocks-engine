###############################################################################
#  iptw_association — IPTW 前后暴露与结局分布表（Index_Group × Disease_Group）
#
#  register_block: "iptw_association"
#  典型流水线: iptw_balance → iptw_association
#
#  config: config$iptw_association（table_var、outcome_strata、pause；不含 data_source）
#  读: before = ctx$data$imputed %||% ctx$data$cleaned
#      after  = ctx$data$iptw_weighted（须先 iptw_balance）
#  写: ctx$results$iptw_association_table
#
#  产出:
#    - [supp_table] Table Sn.*  IPTW 前后 Index–Outcome 关联  → pub_paths + export_sci_table
#
#  NHANES 加权路径跳过。
#  pause: config$iptw_association$pause_enable
###############################################################################

.ia02_is_nhanes_db <- function(cfg) {
  dt <- tolower(trimws(as.character(cfg$project$database_type %||% "")))
  db <- tolower(trimws(as.character(cfg$project$database %||% "")))
  grepl("nhanes|nhance", dt) || grepl("nhanes|nhance", db)
}

.ia02_should_run <- function(cfg) {
  ia_cfg <- cfg$iptw_association %||% list()
  if (isFALSE(ia_cfg$enable %||% TRUE)) return(FALSE)
  !.ia02_is_nhanes_db(cfg)
}

.ia02_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- data_snapshot
  if (is.null(snap)) {
    snap <- data.frame(note = "no snapshot")
  } else if (!is.data.frame(snap)) {
    snap <- utils::head(as.data.frame(snap), 5L)
  } else {
    snap <- utils::head(snap, 5L)
  }
  ctx$results$pause_point <- list(
    block         = "iptw_association",
    reason        = reason,
    suggestion    = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: IPTW association table anomaly. See ctx$results$pause_point. / ",
    "IPTW 关联表异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.ia02_resolve_index_var <- function(cfg) {
  inc_cfg <- cfg$incidence %||% list()
  log_cfg <- cfg$logistic %||% list()
  as.character(inc_cfg$index_var %||% log_cfg$index_var %||% "")[1L]
}

.ia02_format_assoc_side <- function(tab_matrix, normal_lbl, disease_lbl, index_var) {
  tab_df <- as.data.frame(tab_matrix)
  if ("level" %in% names(tab_df)) names(tab_df)[names(tab_df) == "level"] <- " "
  if ("p" %in% names(tab_df)) names(tab_df)[names(tab_df) == "p"] <- "P-value"
  tab_df <- tab_df[, !colnames(tab_df) %in% c("test"), drop = FALSE]

  n_normal <- tab_df["n", normal_lbl]
  n_disease <- tab_df["n", disease_lbl]
  if (normal_lbl %in% colnames(tab_df)) {
    colnames(tab_df)[colnames(tab_df) == normal_lbl] <- paste0(
      normal_lbl, " (N=", n_normal, ")"
    )
  }
  if (disease_lbl %in% colnames(tab_df)) {
    colnames(tab_df)[colnames(tab_df) == disease_lbl] <- paste0(
      disease_lbl, " (N=", n_disease, ")"
    )
  }

  tab_df <- tab_df[-1, , drop = FALSE]
  tab_df <- cbind(Variable = c(index_var, " "), tab_df)
  tab_df <- rbind(Variable = colnames(tab_df), tab_df)
  tab_df
}

.ia02_build_wide_table <- function(tab_before, tab_after, before_lab, after_lab) {
  hdr_before <- c("", "", "", before_lab, "")
  hdr_before <- hdr_before[seq_len(ncol(tab_before))]
  tab_before <- rbind(hdr_before, tab_before)
  hdr_after <- c("", after_lab, "")
  hdr_after <- hdr_after[seq_len(ncol(tab_after))]
  tab_after <- rbind(hdr_after, tab_after)
  tab <- cbind(tab_before, tab_after)
  keep <- c(
    seq_len(min(5L, ncol(tab_before))),
    if (ncol(tab) > 5L) (ncol(tab_before) + 2L):ncol(tab) else integer(0)
  )
  keep <- keep[keep >= 1L & keep <= ncol(tab)]
  tab <- tab[, keep, drop = FALSE]
  rownames(tab) <- NULL
  as.data.frame(tab, stringsAsFactors = FALSE)
}

block_iptw_association <- function(ctx, ...) {
  cfg <- ctx$config
  if (!.ia02_should_run(cfg)) {
    cli::cli_alert_info("iptw_association: 已跳过（NHANES 或 enable=FALSE）。")
    return(ctx)
  }

  ia_cfg <- cfg$iptw_association %||% list()
  suppressPackageStartupMessages({
    if (!requireNamespace("tableone", quietly = TRUE)) {
      stop("iptw_association: 需要 tableone 包。", call. = FALSE)
    }
    if (!requireNamespace("survey", quietly = TRUE)) {
      stop("iptw_association: 需要 survey 包。", call. = FALSE)
    }
    library(tableone, warn.conflicts = FALSE)
    library(survey, warn.conflicts = FALSE)
  })

  before <- ctx$data$imputed %||% ctx$data$cleaned
  after <- ctx$data$iptw_weighted
  if (is.null(before) || !is.data.frame(before)) {
    msg <- "未找到 IPTW 前数据（ctx$data$imputed / cleaned 为空）。"
    if (isTRUE(ia_cfg$pause_enable %||% FALSE)) {
      .ia02_pause(ctx, msg, "请先运行 imputation。", NULL)
    }
    stop("iptw_association: ", msg, call. = FALSE)
  }
  if (is.null(after) || !is.data.frame(after)) {
    msg <- "未找到 IPTW 加权数据（ctx$data$iptw_weighted 为空）。"
    if (isTRUE(ia_cfg$pause_enable %||% FALSE)) {
      .ia02_pause(ctx, msg, "请先运行 iptw_balance。", NULL)
    }
    stop("iptw_association: ", msg, call. = FALSE)
  }

  before <- as.data.frame(before)
  after <- as.data.frame(after)

  table_var <- as.character(ia_cfg$table_var %||% "Index_Group")[1L]
  strata_var <- as.character(
    ia_cfg$outcome_strata %||% cfg$data$outcome_column %||% "Disease_Group"
  )[1L]
  index_var <- .ia02_resolve_index_var(cfg)
  if (!nzchar(index_var)) index_var <- table_var

  for (nm in c(table_var, strata_var)) {
    if (!nm %in% names(before)) {
      stop("iptw_association: 列 '", nm, "' 不在 IPTW 前数据中。", call. = FALSE)
    }
    if (!nm %in% names(after)) {
      stop("iptw_association: 列 '", nm, "' 不在 IPTW 加权数据中。", call. = FALSE)
    }
  }

  weight_col <- ctx$results$iptw_weight_col %||%
    (cfg$iptw_balance %||% list())$weight_col %||% "weight"
  if (!weight_col %in% names(after)) {
    stop("iptw_association: 加权列 '", weight_col, "' 不在 iptw_weighted 数据中。", call. = FALSE)
  }

  proj <- cfg$project %||% list()
  ref_lbl <- as.character(proj$reference_group %||% "Control")[1L]
  case_lbl <- as.character(proj$analysis_group %||% proj$disease %||% "Case")[1L]

  strata_levs <- levels(factor(before[[strata_var]]))
  if (length(strata_levs) < 2L) {
    strata_levs <- unique(as.character(before[[strata_var]]))
    strata_levs <- strata_levs[!is.na(strata_levs)]
  }
  if (ref_lbl %in% strata_levs && case_lbl %in% strata_levs) {
    normal_lbl <- ref_lbl
    disease_lbl <- case_lbl
  } else {
    normal_lbl <- strata_levs[1L]
    disease_lbl <- strata_levs[2L]
  }

  cli::cli_alert_info(
    "iptw_association: {table_var} × {strata_var}（{normal_lbl} vs {disease_lbl}）"
  )

  tab1 <- tableone::CreateTableOne(
    vars = table_var, strata = strata_var, data = before, test = TRUE
  )
  tab_matrix1 <- print(
    tab1,
    showAllLevels = TRUE,
    smd = TRUE,
    printToggle = FALSE,
    quote = FALSE,
    noSpaces = TRUE
  )
  tab_before <- .ia02_format_assoc_side(tab_matrix1, normal_lbl, disease_lbl, index_var)

  dt_iptw <- survey::svydesign(
    ids = ~1,
    data = after,
    weights = stats::as.formula(paste0("~", weight_col))
  )
  tab1_iptw <- tableone::svyCreateTableOne(
    vars = table_var, strata = strata_var, data = dt_iptw, test = TRUE
  )
  tab_matrix2 <- print(
    tab1_iptw,
    showAllLevels = TRUE,
    smd = TRUE,
    printToggle = FALSE,
    quote = FALSE,
    noSpaces = TRUE
  )
  tab_after_raw <- as.data.frame(tab_matrix2)
  if ("p" %in% names(tab_after_raw)) names(tab_after_raw)[names(tab_after_raw) == "p"] <- "P-value"
  tab_after_raw <- tab_after_raw[, !colnames(tab_after_raw) %in% c("level", "test"), drop = FALSE]
  n_normal <- tab_after_raw["n", normal_lbl]
  n_disease <- tab_after_raw["n", disease_lbl]
  if (normal_lbl %in% colnames(tab_after_raw)) {
    colnames(tab_after_raw)[colnames(tab_after_raw) == normal_lbl] <- paste0(
      normal_lbl, " (N=", n_normal, ")"
    )
  }
  if (disease_lbl %in% colnames(tab_after_raw)) {
    colnames(tab_after_raw)[colnames(tab_after_raw) == disease_lbl] <- paste0(
      disease_lbl, " (N=", n_disease, ")"
    )
  }
  tab_after_raw <- tab_after_raw[-1, , drop = FALSE]
  tab_after <- rbind(Variable = colnames(tab_after_raw), tab_after_raw)
  rownames(tab_after) <- NULL
  tab_after <- as.data.frame(tab_after, stringsAsFactors = FALSE)

  before_lab <- ia_cfg$before_section_label %||% "Before IPTW"
  after_lab <- ia_cfg$after_section_label %||% "After IPTW"
  tab_wide <- .ia02_build_wide_table(tab_before, tab_after, before_lab, after_lab)

  disease_name <- proj$disease %||% proj$analysis_group %||% "outcome"
  cap <- ia_cfg$table_caption %||% paste0(
    "Association between ", index_var, " and ", disease_name,
    " before and after IPTW adjustment"
  )
  cap <- sub("^Table S\\d+[a-z]?\\.\\s*", "", cap)
  paths <- pub_paths(ctx, ctx$output_dir_tables, "supp_table", cap, "xlsx")
  export_sci_table(
    tab_wide,
    paths$filepath,
    title = paths$title,
    latex_include_colnames = FALSE,
    excel_use_prepared = FALSE
  )
  ctx$results$iptw_association_table <- tab_wide
  cli::cli_alert_success(
    "iptw_association 完成（Table queued: {.file {basename(paths$filepath)}}）"
  )
  ctx
}

register_block(
  "iptw_association",
  block_iptw_association,
  "Before/after IPTW table for index exposure vs disease outcome"
)
