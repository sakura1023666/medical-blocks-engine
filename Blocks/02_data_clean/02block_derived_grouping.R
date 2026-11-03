###############################################################################
#  derived_grouping — 暴露三分位 × 严重度二分 → Index_HL / SOFA_bin / Index_SOFA_Q
#
#  register_block: "derived_grouping"
#  典型流水线: UV → VIF → Cox（tertile）之后；多时点 Cox / nomogram 之前
#
#  config$derived_grouping = list(
#    sofa_var        = "SOFA",          # 严重度列名
#    cutoff          = 5,               # 或 sofa_cutoff；"median" → 中位数
#    sofa_cutoff     = 5,               # 兼容旧键
#    tertile_var     = NULL,            # 已有三分位列；NULL → Group / Index_tertile / 自算
#    index_var       = NULL,            # 连续暴露；NULL → survival$index_var / project$index_var
#    high_low_mode   = "t3_vs_t1",      # T3=High, T1=Low, T2=Middle
#    q4_var          = "Index_SOFA_Q",
#    hl_var          = "Index_HL",
#    sofa_bin_var    = "SOFA_bin"
#  )
#  兼容: 缺 config$derived_grouping 时回读 config$jin_index_sofa 同名字段
#
#  读: ctx$data$imputed/cleaned；写回同表列 + ctx$results$derived_grouping
#  注: SOFA 仅作分层轴；勿把疾病泄漏列写入调整集（本块不写调整集）
#  依赖助手: R/literature_jin_index_sofa.R（jin_sofa_binary / jin_exposure_high_low / jin_index_sofa_q4）
###############################################################################

.derived_grouping_cfg <- function(cfg) {
  old <- cfg$jin_index_sofa %||% list()
  new <- cfg$derived_grouping %||% list()
  if (!length(new) && !length(old)) return(list())
  if (!length(new)) return(old)
  if (!length(old)) return(new)
  utils::modifyList(old, new)
}

.derived_grouping_source_helpers <- function(study_root = NULL) {
  cands <- unique(c(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
    as.character(study_root %||% "")[1L],
    getwd()
  ))
  cands <- cands[nzchar(as.character(cands))]
  for (r in cands) {
    lit <- file.path(r, "R", "literature_jin_index_sofa.R")
    if (file.exists(lit)) {
      source(lit, local = FALSE)
      return(invisible(lit))
    }
  }
  stop(
    "derived_grouping: 找不到 R/literature_jin_index_sofa.R（请设 MEDICAL_BLOCKS_ROOT=引擎根）",
    call. = FALSE
  )
}

block_derived_grouping <- function(ctx, ...) {
  .derived_grouping_source_helpers(ctx$config$project$root %||% getwd())
  if (!exists("jin_sofa_binary", mode = "function", inherits = TRUE)) {
    stop("derived_grouping: jin_sofa_binary 未加载", call. = FALSE)
  }

  bl <- .derived_grouping_cfg(ctx$config)
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    stop("derived_grouping: 无 imputed/cleaned 数据", call. = FALSE)
  }

  sofa_var <- as.character(bl$sofa_var %||% "SOFA")[1L]
  if (!sofa_var %in% names(data)) {
    alt <- intersect(c("sofa", "SOFA_score", "Sofa", "SOFA_Score"), names(data))
    if (length(alt)) sofa_var <- alt[[1L]]
  }
  if (!sofa_var %in% names(data)) {
    stop(
      "derived_grouping: 找不到 SOFA 列（config$derived_grouping$sofa_var）",
      call. = FALSE
    )
  }

  cutoff <- bl$cutoff %||% bl$sofa_cutoff %||% 5
  if (identical(tolower(as.character(cutoff)[1L]), "median")) {
    cutoff <- stats::median(suppressWarnings(as.numeric(data[[sofa_var]])), na.rm = TRUE)
  }
  cutoff <- as.numeric(cutoff)[1L]

  tert_var <- bl$tertile_var %||% NULL
  if (is.null(tert_var) || !nzchar(as.character(tert_var)[1L])) {
    cands <- c("Group", "Index_tertile", "index_tertile", "tertile", "Index_Group")
    hit <- cands[cands %in% names(data)]
    tert_var <- if (length(hit)) hit[[1L]] else NULL
  } else {
    tert_var <- as.character(tert_var)[1L]
  }

  index_var <- bl$index_var %||%
    ctx$config$survival$index_var %||%
    ctx$config$project$index_var %||%
    ctx$results$current_index %||% NULL
  index_var <- if (!is.null(index_var)) as.character(index_var)[1L] else NULL

  if (is.null(tert_var) || !tert_var %in% names(data)) {
    if (is.null(index_var) || !index_var %in% names(data)) {
      stop(
        "derived_grouping: 无三分位列且无连续 index_var，无法分层",
        call. = FALSE
      )
    }
    v <- suppressWarnings(as.numeric(data[[index_var]]))
    qs <- stats::quantile(v, probs = c(1 / 3, 2 / 3), na.rm = TRUE, names = FALSE, type = 7)
    tert <- cut(
      v,
      breaks = c(-Inf, qs[[1L]], qs[[2L]], Inf),
      labels = c("T1", "T2", "T3"),
      include.lowest = TRUE,
      right = FALSE
    )
    tert_var <- paste0(index_var, "_tertile")
    data[[tert_var]] <- tert
    cli::cli_alert_info(
      "derived_grouping: 自算三分位 {tert_var} @ {round(qs[[1L]], 4)} / {round(qs[[2L]], 4)}"
    )
  }

  hl_var <- as.character(bl$hl_var %||% "Index_HL")[1L]
  sofa_bin_var <- as.character(bl$sofa_bin_var %||% "SOFA_bin")[1L]
  q4_var <- as.character(bl$q4_var %||% "Index_SOFA_Q")[1L]
  mode <- as.character(bl$high_low_mode %||% "t3_vs_t1")[1L]

  data[[sofa_bin_var]] <- jin_sofa_binary(data[[sofa_var]], cutoff = cutoff)
  data[[hl_var]] <- jin_exposure_high_low(data[[tert_var]], mode = mode)
  data[[q4_var]] <- jin_index_sofa_q4(data[[hl_var]], data[[sofa_bin_var]])

  n_q <- sum(!is.na(data[[q4_var]]))
  n_mid <- sum(as.character(data[[hl_var]]) == "Middle", na.rm = TRUE)
  tab_q <- table(data[[q4_var]], useNA = "no")

  if (!is.null(ctx$data$imputed)) ctx$data$imputed <- data
  if (!is.null(ctx$data$cleaned) && nrow(ctx$data$cleaned) == nrow(data)) {
    ctx$data$cleaned <- data
  } else if (!is.null(ctx$data$cleaned)) {
    for (vn in c(sofa_bin_var, hl_var, q4_var, tert_var)) {
      if (vn %in% names(data) && nrow(ctx$data$cleaned) == nrow(data)) {
        ctx$data$cleaned[[vn]] <- data[[vn]]
      }
    }
  }

  meta <- list(
    sofa_var = sofa_var,
    sofa_cutoff = cutoff,
    cutoff = cutoff,
    tertile_var = tert_var,
    index_var = index_var,
    hl_var = hl_var,
    sofa_bin_var = sofa_bin_var,
    q4_var = q4_var,
    n_in_q4 = as.integer(n_q),
    n_middle_excluded = as.integer(n_mid),
    q4_counts = as.list(as.integer(tab_q))
  )
  names(meta$q4_counts) <- names(tab_q)
  ctx$results$derived_grouping <- meta
  # 兼容旧结果键（现有课题若仍读 jin_index_sofa_strata）
  ctx$results$jin_index_sofa_strata <- meta

  cli::cli_alert_success(
    "derived_grouping: {q4_var} 已生成（入组 n={n_q}, Middle 排除 n={n_mid}; SOFA cutoff={cutoff})"
  )
  ctx
}

register_block(
  "derived_grouping",
  block_derived_grouping,
  "暴露×严重度四组合分层（Index_SOFA_Q）"
)
