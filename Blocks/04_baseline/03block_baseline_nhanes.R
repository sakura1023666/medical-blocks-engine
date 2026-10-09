###############################################################################
#  baseline_nhanes — NHANES 加权 Table 1 + 正态性检验补充表（Table S）。
#
#  非加权敏感性基线由 pipeline 中的 baseline_binary 负责，本块不再生成 Table S8。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data          = ctx$results$nhanes_design  # 须先 run_block(obj)
#  requires_blocks   = c("obj"),
#  requires_packages = c("survey", "gtsummary"),
#
#  baseline_nhanes = list(
#    sig_cutoff   = 0.05,              # 加权 Table 1 组间比较筛选阈值
#    p_threshold  = 0.05,
#    normality_table_title = NULL,     # NULL → 默认正态性补充表标题
#    table1_label_overrides      = list(),
#    table1_sections             = NULL,
#    table1_sections_disable_default = FALSE,
#    table1_append_units_from_dictionary = NULL,  # FALSE → 标签不加字典单位
#    table1_factor_recode = list(),               # 列名 → c(原水平 = 新水平)，如 Health→No
#    table1_xlsx_center_first_col = character(0),
#    table1_xlsx_footnotes       = NULL,
#    pause_enable                  = TRUE,
#    pause_on_missing_design       = TRUE,   # 无 nhanes_design 时暂停
#    pause_on_missing_packages     = TRUE,   # 缺 survey/gtsummary
#    pause_on_weighted_table_fail  = TRUE,
#    pause_on_min_sig_vars         = TRUE,
#    pause_min_sig_vars            = 3L
#  ),
#  # 全局：config$analysis_var_policy$min_categorical_n=20（任一层级 n<20 的分类列在表/图前删除）
#
#  register_block: "baseline_nhanes"
#  典型流水线: obj 之后；读 ctx$results$nhanes_design（加权 Table 1 + 正态性 Table S）
#  写: sig_vars（加权筛选）、NHANES 专用表路径；须 survey、gtsummary
#  块内读取 config$baseline_nhanes；权重列见 config$nhanes
###############################################################################

.bb03_resolve_table1_footnotes <- function(bl_cfg, ...) {
  ft_cfg <- bl_cfg$table1_xlsx_footnotes %||% NULL
  if (!is.null(ft_cfg) && length(ft_cfg) > 0L) {
    out <- as.character(unlist(ft_cfg, use.names = FALSE))
    return(out[nzchar(trimws(out))])
  }
  do.call(table1_baseline_xlsx_footnotes, list(...))
}

.bb03_drop_gt_missing_rows <- function(tbl) {
  if (is.null(tbl) || !inherits(tbl, "gtsummary")) return(tbl)
  bdy <- tbl$table_body
  if (is.null(bdy) || !is.data.frame(bdy) || !"row_type" %in% names(bdy)) return(tbl)
  drop_types <- c("missing", "missing_level")
  keep <- !(as.character(bdy$row_type) %in% drop_types)
  if (all(keep)) return(tbl)
  tbl$table_body <- bdy[keep, , drop = FALSE]
  tbl
}

.bb03_apply_table1_label_overrides_to_gt <- function(tbl, lbl_ov) {
  if (is.null(tbl) || !inherits(tbl, "gtsummary")) return(tbl)
  lbl_ov <- lbl_ov %||% NULL
  if (!is.list(lbl_ov) || length(lbl_ov) == 0L) return(tbl)
  bdy <- tbl$table_body
  if (!is.data.frame(bdy) || nrow(bdy) == 0L) return(tbl)
  if (!all(c("variable", "label", "row_type") %in% names(bdy))) return(tbl)
  keys <- names(lbl_ov)
  keys <- keys[nzchar(keys)]
  if (!length(keys)) return(tbl)
  v_low <- tolower(as.character(bdy$variable))
  k_low <- tolower(keys)
  for (i in seq_along(keys)) {
    hit <- which(v_low == k_low[i] & bdy$row_type == "label")
    if (length(hit)) {
      bdy$label[hit] <- as.character(lbl_ov[[keys[i]]])[1L]
    }
  }
  tbl$table_body <- bdy
  tbl
}

.bb03_ensure_baseline_dictionary_labels <- function(root = NULL) {
  if (exists("baseline_merge_table1_unit_label_overrides", mode = "function"))
    return(invisible(TRUE))
  roots <- c(
    if (!is.null(root) && nzchar(as.character(root)[1L])) as.character(root)[1L],
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
    getwd()
  )
  roots <- unique(roots[nzchar(as.character(roots))])
  for (r in roots) {
    p <- file.path(r, "R", "baseline_dictionary_labels.R")
    if (file.exists(p)) {
      source(p, local = FALSE)
      break
    }
  }
  invisible(exists("baseline_merge_table1_unit_label_overrides", mode = "function"))
}

.bb03_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  val <- bl_cfg[[key]]
  if (is.null(val)) return(isTRUE(default))
  isTRUE(val)
}

.bb03_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- data_snapshot
  if (is.null(snap)) {
    snap <- data.frame(note = "no snapshot")
  } else if (!is.data.frame(snap)) {
    snap <- utils::head(as.data.frame(snap), 5L)
  } else {
    snap <- utils::head(snap, 5L)
  }
  ctx$results$pause_point <- list(
    block         = "baseline_nhanes",
    reason        = reason,
    suggestion    = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: Negative result or anomaly detected. See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.bb03_test_normality <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 3) return(FALSE)
  pv <- tryCatch({
    if (n > 5000) {
      ks.test(scale(x), "pnorm")$p.value
    } else {
      shapiro.test(x)$p.value
    }
  }, error = function(e) 0)
  pv >= 0.05
}

.bb03_resolve_sig_cutoff <- function(bl_cfg, ctx) {
  cutoff <- bl_cfg$sig_cutoff
  if (is.null(cutoff)) cutoff <- bl_cfg$p_threshold
  if (is.null(cutoff)) {
    .bb03_pause(
      ctx,
      "未配置 config$baseline_nhanes$sig_cutoff（或 legacy p_threshold）。",
      "在 config$baseline_nhanes 中设置 sig_cutoff，或设 pause_enable = FALSE 后自行处理。",
      NULL
    )
  }
  as.numeric(cutoff)[1L]
}

.bb03_extract_sig_vars <- function(tbl, cutoff) {
  if (is.null(tbl)) return(character(0))
  test_col <- NULL
  if ("p.value" %in% names(tbl$table_body)) {
    test_col <- tbl$table_body$p.value
  } else if ("p_value" %in% names(tbl$table_body)) {
    test_col <- tbl$table_body$p_value
  }
  if (is.null(test_col)) {
    cli::cli_alert_warning("Comparison column not found in table_body")
    return(character(0))
  }
  test_num <- suppressWarnings(as.numeric(gsub("[<>]", "", test_col)))
  sig_rows <- !is.na(test_num) & test_num < cutoff
  unique(tbl$table_body$variable[sig_rows])
}

.bb03_apply_table1_factor_recodes <- function(design_tbl, bl_cfg) {
  rec <- bl_cfg$table1_factor_recode
  if (is.null(rec) || !length(rec)) return(design_tbl)
  for (v in names(rec)) {
    if (!v %in% names(design_tbl$variables)) next
    mp <- rec[[v]]
    if (is.null(mp) || !length(mp)) next
    x <- as.character(design_tbl$variables[[v]])
    for (from in names(mp)) {
      x[x == from] <- as.character(mp[[from]])
    }
    levs <- unique(unname(as.character(mp)))
    if (all(c("No", "Yes") %in% levs)) levs <- c("No", "Yes")
    design_tbl$variables[[v]] <- factor(x, levels = levs)
  }
  design_tbl
}

.bb03_export_nhanes_table <- function(ctx, tb, bl_cfg, data_imp, n_rows, cont_v,
                                      non_normal_v, outcome_col, disease_lbl,
                                      title_str, out_name, label_mode) {
  if (is.null(tb)) return(invisible(NULL))

  tb <- .bb03_drop_gt_missing_rows(tb)
  root_lbl <- (ctx$config$project %||% list())$root %||%
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "") %||% getwd()
  if (.bb03_ensure_baseline_dictionary_labels(root_lbl) &&
      exists("baseline_merge_table1_unit_label_overrides", mode = "function")) {
    vars_tbl <- if (is.data.frame(tb$table_body) && "variable" %in% names(tb$table_body)) {
      unique(as.character(tb$table_body$variable))
    } else {
      character(0)
    }
    bl_cfg <- baseline_merge_table1_unit_label_overrides(
      ctx$config, bl_cfg, vars_tbl, root_lbl
    )
  }
  tb <- .bb03_apply_table1_label_overrides_to_gt(tb, bl_cfg$table1_label_overrides %||% NULL)
  tbl_df <- as.data.frame(tb)
  sec_cfg <- bl_cfg$table1_sections
  if (!is.null(sec_cfg) && length(sec_cfg) == 0L) sec_cfg <- NULL
  section_rows <- NULL
  if (exists("table1_resolve_sections", mode = "function")) {
    sec_use <- table1_resolve_sections(ctx$config, bl_cfg)
    section_rows <- table1_section_insert_rows_from_gtsummary(tb, sec_use)
  } else if (!is.null(sec_cfg) && length(sec_cfg) > 0L) {
    section_rows <- table1_section_insert_rows_from_gtsummary(tb, sec_cfg)
  }
  if (is.null(section_rows) || length(section_rows) == 0L) {
    if (!isTRUE(bl_cfg$table1_sections_disable_default)) {
      section_rows <- table1_section_insert_rows_from_gtsummary(tb, .default_table1_sections())
    }
  }
  center_labs <- as.character(bl_cfg$table1_xlsx_center_first_col %||% character(0))
  center_labs <- center_labs[nzchar(center_labs)]
  n_groups <- length(unique(stats::na.omit(data_imp[[outcome_col]])))
  xlsx_footnotes <- .bb03_resolve_table1_footnotes(
    bl_cfg,
    n_obs                 = n_rows,
    n_groups              = n_groups,
    has_normal_continuous = length(setdiff(cont_v, non_normal_v)) > 0L,
    has_skewed_continuous = length(non_normal_v) > 0L,
    has_categorical       = TRUE,
    use_fisher_any        = FALSE,
    weighted              = TRUE   # tbl_svysummary + add_p → 加权检验脚注
  )
  built <- table1_build_display_df(
    tbl_df,
    section_insert_rows = if (!is.null(section_rows) && length(section_rows) > 0L) section_rows else NULL,
    section_anchors     = NULL,
    gtsummary_tbl       = tb,
    center_first_col_values = center_labs,
    strip_underscores   = !isTRUE(bl_cfg$table1_preserve_underscores)
  )
  fp <- .inject_db_into_pub_filepath(file.path(ctx$output_dir_tables, out_name))
  styled <- FALSE
  tryCatch({
    write_table1_xlsx_guan_style(tbl_df, fp, title_str,
                                 footnotes = xlsx_footnotes, prebuilt = built)
    styled <- TRUE
    cli::cli_alert_success("NHANES {label_mode} table saved: {.file {basename(fp)}}")
  }, error = function(e) {
    cli::cli_alert_warning("NHANES {label_mode} xlsx export failed: {e$message}")
  })
  export_sci_table(
    tbl_df, fp, title = title_str, skip_excel = styled,
    latex_include_colnames = FALSE,
    table1_render_spec = list(
      df = built$df, footnotes = xlsx_footnotes,
      insert_map = built$insert_map, level_row_idx = built$level_row_idx
    )
  )
  invisible(list(tbl_df = tbl_df, tb = tb))
}

block_baseline_nhanes <- function(ctx, ...) {
  cfg        <- ctx$config
  nhanes_cfg <- cfg$nhanes %||% list()
  proj_cfg   <- cfg$project %||% list()
  bl_cfg     <- cfg$baseline_nhanes %||% list()
  sig_cutoff <- .bb03_resolve_sig_cutoff(bl_cfg, ctx)
  pause_min_sig <- as.integer(bl_cfg$pause_min_sig_vars %||% 3L)

  design <- ctx$results$nhanes_design
  if (is.null(design)) {
    if (.bb03_should_pause(bl_cfg, "pause_on_missing_design", TRUE)) {
      .bb03_pause(
        ctx,
        "ctx$results$nhanes_design 为空，无法生成 NHANES 加权基线表。",
        "请先运行 run_block(ctx, 'obj') 构建 svydesign。",
        NULL
      )
    }
    cli::cli_alert_warning("baseline_nhanes: nhanes_design empty; skipped.")
    return(ctx)
  }

  # 表/图前：删除任一层级 n<20 的分类列（同步 design$variables 与 imputed）
  if (exists("pipeline_drop_sparse_categorical_cols", mode = "function") &&
      !is.null(design$variables) && is.data.frame(design$variables)) {
    dv <- pipeline_drop_sparse_categorical_cols(design$variables, cfg)
    dropped <- attr(dv, "sparse_categorical_dropped") %||% character(0)
    attr(dv, "sparse_categorical_dropped") <- NULL
    design$variables <- dv
    ctx$results$nhanes_design <- design
    if (length(dropped)) {
      ctx$results$sparse_categorical_dropped <- unique(c(
        as.character(ctx$results$sparse_categorical_dropped %||% character(0)), dropped
      ))
    }
    if (exists("pipeline_apply_sparse_categorical_drop_to_ctx", mode = "function")) {
      ctx <- pipeline_apply_sparse_categorical_drop_to_ctx(ctx, slots = c("imputed", "cleaned"))
      cfg <- ctx$config
    }
  }

  if (!requireNamespace("survey", quietly = TRUE) || !requireNamespace("gtsummary", quietly = TRUE)) {
    if (.bb03_should_pause(bl_cfg, "pause_on_missing_packages", TRUE)) {
      .bb03_pause(
        ctx,
        "缺少 R 包 survey 或 gtsummary，无法运行 baseline_nhanes。",
        "安装 survey、gtsummary 后重试，或设 pause_on_missing_packages = FALSE。",
        NULL
      )
    }
    cli::cli_alert_warning("baseline_nhanes: requires survey + gtsummary; skipped.")
    return(ctx)
  }
  suppressPackageStartupMessages({
    library(survey, warn.conflicts = FALSE)
    library(gtsummary)
    library(dplyr)
  })

  outcome_col <- cfg$data$outcome_column %||% "Disease"
  disease_lbl <- pipeline_outcome_case_label(cfg)

  wt_col     <- as.character(nhanes_cfg$survey_weight  %||% "new_Weight")[1L]
  psu_col    <- as.character(nhanes_cfg$survey_cluster %||% "SDMVPSU")[1L]
  str_col    <- as.character(nhanes_cfg$survey_strata  %||% "SDMVSTRA")[1L]
  data_imp   <- design$variables
  excl_bl    <- as.character(bl_cfg$exclude_vars %||% character(0))
  excl_bl    <- excl_bl[nzchar(excl_bl)]
  excl_cols  <- if (exists("pipeline_nhanes_survey_design_exclude_cols", mode = "function")) {
    unique(c(
      pipeline_nhanes_survey_design_exclude_cols(names(data_imp), cfg),
      excl_bl
    ))
  } else {
    extra_excl <- as.character(nhanes_cfg$exclude_cols %||% c(
      "WTINT2YR", "WTMEC2YR", "WTINT4YR", "WTMEC4YR", "WTSAF2YR", "WTSAF4YR",
      "WTDRD1", "WTDR2D", "WTSOG2YR", "WTSA2YR", "WTSB2YR", "WTSC2YR", "WTSVOC2YR"
    ))
    excl_cols <- unique(c(wt_col, psu_col, str_col, extra_excl, excl_bl, cfg$data$id_column %||% "SEQN"))
    auto_wt <- grep("^(WT[A-Z]|SDMV|Source_File)", names(data_imp), value = TRUE, ignore.case = TRUE)
    unique(c(excl_cols, setdiff(auto_wt, wt_col)))
  }
  if (exists("environment_patch_table1_sections", mode = "function")) {
    cfg <- environment_patch_table1_sections(cfg, data_imp)
    ctx$config <- cfg
  }
  root <- proj_cfg$root %||% getwd()
  if (exists("environment_patch_baseline_table1_labels", mode = "function")) {
    cfg <- environment_patch_baseline_table1_labels(cfg, data_imp, root)
    ctx$config <- cfg
    bl_cfg <- cfg$baseline_nhanes %||% bl_cfg
    excl_bl2 <- as.character(bl_cfg$exclude_vars %||% character(0))
    excl_bl2 <- excl_bl2[nzchar(excl_bl2)]
    excl_cols <- unique(c(excl_cols, excl_bl2))
  }
  if (length(excl_bl) || length(as.character(bl_cfg$exclude_vars %||% character(0)))) {
    wt_meta <- if (exists("pipeline_nhanes_survey_design_exclude_cols", mode = "function")) {
      pipeline_nhanes_survey_design_exclude_cols(names(data_imp), cfg)
    } else {
      c(wt_col, psu_col, str_col)
    }
    dropped_bl <- intersect(names(data_imp), setdiff(excl_cols, wt_meta))
    if (length(dropped_bl)) {
      cli::cli_alert_info(
        "baseline_nhanes exclude_vars: dropped {length(dropped_bl)} vars from Table 1 pool"
      )
    }
  }
  df_sw    <- data_imp[, setdiff(names(data_imp), excl_cols), drop = FALSE]
  force_cont <- as.character(bl_cfg$force_continuous_vars %||% character(0))
  disc_th <- as.integer(bl_cfg$discrete_threshold %||% 5L)[1L]
  if (!is.finite(disc_th) || disc_th < 2L) disc_th <- 5L
  design_tbl <- design
  if (exists("pipeline_coerce_discrete_numeric", mode = "function")) {
    co <- pipeline_coerce_discrete_numeric(
      df_sw,
      vars = names(df_sw),
      threshold = disc_th,
      force_continuous = force_cont,
      outcome_col = outcome_col
    )
    df_sw <- co$data
    if (length(co$discrete)) {
      cli::cli_alert_info(
        "Variable(s) as categorical (discrete numeric): {paste(co$discrete, collapse = ', ')}"
      )
      for (v in co$discrete) {
        if (v %in% names(design_tbl$variables)) design_tbl$variables[[v]] <- df_sw[[v]]
      }
    }
  }
  cont_v   <- names(Filter(is.numeric, df_sw))
  cont_v   <- setdiff(cont_v, c(names(Filter(is.factor, df_sw)), outcome_col))
  n_rows   <- nrow(df_sw)

  continuous_vars  <- cont_v
  categorical_vars <- setdiff(names(df_sw), c(cont_v, outcome_col))

  cli::cli_h2("baseline_nhanes: normality (n={n_rows})")
  normality_result <- sapply(continuous_vars, function(v) .bb03_test_normality(df_sw[[v]]))
  normality_pvals  <- sapply(continuous_vars, function(v) {
    x <- df_sw[[v]][!is.na(df_sw[[v]])]
    n <- length(x)
    if (n < 3) return(NA_real_)
    tryCatch({
      if (n > 5000) stats::ks.test(scale(x), "pnorm")$p.value
      else stats::shapiro.test(x)$p.value
    }, error = function(e) 0)
  })
  normal_vars <- continuous_vars[normality_result]
  skewed_vars <- continuous_vars[!normality_result]
  cli::cli_alert_info(
    "Normal: {length(normal_vars)}, Skewed: {length(skewed_vars)}, Categorical: {length(categorical_vars)}"
  )

  normality_df <- data.frame(
    variable  = continuous_vars,
    method    = ifelse(n_rows > 5000, "Kolmogorov-Smirnov", "Shapiro-Wilk"),
    p_value   = normality_pvals,
    is_normal = normality_result,
    statistic = ifelse(normality_result, "Mean (SD)", "Median (Q1, Q3)"),
    stringsAsFactors = FALSE
  )
  ctx <- save_result(ctx, "normality_test_nhanes", normality_df, "normality_test_nhanes.csv")
  ctx$results$normality_test_nhanes <- normality_df

  if (nrow(normality_df) > 0L) {
    normality_pub <- normality_df
    normality_pub$variable  <- if (exists("environment_display_label", mode = "function")) {
      environment_display_label(
        normality_pub$variable,
        if (exists("environment_resolve_label_map", mode = "function")) environment_resolve_label_map(cfg) else NULL
      )
    } else gsub("_", " ", normality_pub$variable, fixed = TRUE)
    normality_pub$p_value   <- fmt_pval(normality_pub$p_value)
    normality_pub$is_normal <- ifelse(normality_pub$is_normal, "Normal", "Skewed")
    names(normality_pub) <- c(
      "Variable", "Test Method", "P Value",
      "Distribution", "Descriptive Statistic"
    )
    cap_norm <- bl_cfg$normality_table_title %||%
      paste0("Normality test results for continuous variables (n=", n_rows, ")")
    cap_norm <- sub("^Table S\\d+\\.\\s*", "", cap_norm)
    paths_norm <- pub_paths(ctx, ctx$output_dir_tables, "supp_table", cap_norm, "xlsx")
    export_sci_table(normality_pub, paths_norm$filepath, title = paths_norm$title)
    ctx$results$table_normality_nhanes <- normality_pub
    cli::cli_alert_success(
      "Normality test supplementary table saved: {.file {basename(paths_norm$filepath)}}"
    )
  }

  tb_weighted  <- NULL
  tbl_df_w     <- NULL
  weighted_err <- NULL

  cli::cli_h2("baseline_nhanes: weighted Table 1")
  options(survey.lonely.psu = "adjust")
  tryCatch({
    w_cap <- paste0(
      "Weighted Baseline Characteristics of Participants Categorized by - ",
      disease_lbl, " Status"
    )
    paths_w <- pub_paths(ctx, ctx$output_dir_tables, "main_table", w_cap, "xlsx")
    skewed_hit <- intersect(skewed_vars, names(design_tbl$variables))
    if (exists("pipeline_median_stat_vars", mode = "function")) {
      skewed_hit <- pipeline_median_stat_vars(design_tbl$variables, skewed_hit)
    }
    stat_w <- list(
      all_continuous() ~ "{mean} ({sd})",
      all_categorical() ~ "{n_unweighted} ({p}%)"
    )
    if (length(skewed_hit)) {
      stat_w <- c(
        stat_w,
        stats::setNames(
          rep(list("{median} ({p25}, {p75})"), length(skewed_hit)),
          skewed_hit
        )
      )
    }
    nhanes_include_vars <- setdiff(names(design_tbl$variables), c(excl_cols, outcome_col))
    # 与 baseline_binary 一致：非空 include_vars 时仅保留所列变量（顺序保留）
    inc_cfg <- bl_cfg$include_vars
    if (!is.null(inc_cfg) && length(as.character(inc_cfg))) {
      inc_want <- unique(as.character(inc_cfg))
      inc_miss <- setdiff(inc_want, nhanes_include_vars)
      if (length(inc_miss)) {
        cli::cli_alert_warning(
          "baseline_nhanes$include_vars not in data (ignored): {paste(inc_miss, collapse = ', ')}"
        )
      }
      nhanes_include_vars <- intersect(inc_want, nhanes_include_vars)
      if (!length(nhanes_include_vars)) {
        stop(
          "baseline_nhanes$include_vars 与候选变量交集为空。",
          "检查 include_vars 列名与 exclude_cols。",
          call. = FALSE
        )
      }
      cli::cli_alert_info("Table 1 variables (include_vars): {length(nhanes_include_vars)}")
    } else if (exists("environment_sort_analysis_vars", mode = "function")) {
      nhanes_include_vars <- environment_sort_analysis_vars(nhanes_include_vars, cfg, data_imp)
    } else if (exists("sort_vars_by_table1_sections", mode = "function")) {
      nhanes_include_vars <- sort_vars_by_table1_sections(nhanes_include_vars, cfg)
    }
    nhanes_include_vars <- intersect(nhanes_include_vars, names(design_tbl$variables))
    ctx$results$table1_var_order <- nhanes_include_vars
    design_tbl <- .bb03_apply_table1_factor_recodes(design_tbl, bl_cfg)
    if (length(bl_cfg$table1_factor_recode %||% list())) {
      data_imp <- design_tbl$variables
      df_sw <- data_imp[, setdiff(names(data_imp), excl_cols), drop = FALSE]
      categorical_vars <- setdiff(names(df_sw), c(cont_v, outcome_col))
    }
    # 环境毒物代码 → 真实名（gtsummary 读取 attr(x,"label")）
    if (exists("environment_resolve_label_map", mode = "function")) {
      env_lmap <- environment_resolve_label_map(cfg)
      if (length(env_lmap)) {
        for (v in intersect(names(env_lmap), names(design_tbl$variables))) {
          new_lbl <- as.character(env_lmap[[v]])
          if (length(new_lbl) && nzchar(new_lbl) && !identical(new_lbl, v)) {
            attr(design_tbl$variables[[v]], "label") <- new_lbl
          }
        }
      }
    }
    if (isTRUE(bl_cfg$table1_preserve_underscores)) {
      lbl_ov <- bl_cfg$table1_label_overrides %||% list()
      for (v in nhanes_include_vars) {
        if (!v %in% names(design_tbl$variables)) next
        ov <- lbl_ov[[v]]
        lbl <- if (!is.null(ov) && nzchar(as.character(ov)[1L])) as.character(ov)[1L] else v
        attr(design_tbl$variables[[v]], "label") <- lbl
      }
    }
    # 二分类强制 categorical：Yes/No 各出一行（默认 dichotomous 会把 Yes 合并进标签行）
    bin_force_cat <- intersect(
      unique(categorical_vars, names(design_tbl$variables)),
      nhanes_include_vars
    )
    bin_force_cat <- Filter(function(v) {
      x <- design_tbl$variables[[v]]
      is.factor(x) || is.character(x)
    }, bin_force_cat)
    bin_force_cat <- Filter(function(v) {
      length(unique(stats::na.omit(as.character(design_tbl$variables[[v]])))) <= 2L
    }, bin_force_cat)
    # 少水平数值（如 CONUT_score 0–8）易被 gtsummary 自动判为 categorical，
    # 再叠 median 统计会报 “Statistic median/p25/p75 is not available”
    cont_force <- intersect(continuous_vars, nhanes_include_vars)
    cont_force <- setdiff(cont_force, bin_force_cat)
    type_arg <- NULL
    if (length(bin_force_cat) || length(cont_force)) {
      type_parts <- list()
      if (length(bin_force_cat)) {
        for (v in bin_force_cat) type_parts[[v]] <- "categorical"
      }
      if (length(cont_force)) {
        for (v in cont_force) type_parts[[v]] <- "continuous"
      }
      type_arg <- type_parts
    }
    tb_weighted <- design_tbl %>%
      gtsummary::tbl_svysummary(
        by        = dplyr::all_of(outcome_col),
        include   = dplyr::all_of(nhanes_include_vars),
        digits    = list(all_continuous() ~ 2, all_categorical() ~ 2),
        statistic = stat_w,
        type      = type_arg
      ) %>%
      gtsummary::add_p(pvalue_fun = ~gtsummary::style_pvalue(.x, digits = 2)) %>%
      gtsummary::add_overall() %>%
      gtsummary::modify_header(
        all_stat_cols() ~ "**{level}** \n (Unweighted N = {n_unweighted})"
      ) %>%
      gtsummary::modify_caption(
        paste0("**", paths_w$title, "**")
      )
    if (!isTRUE(bl_cfg$table1_preserve_underscores)) {
      tb_weighted <- tb_weighted %>% gtsummary::bold_labels()
    }

    out_w <- .bb03_export_nhanes_table(
      ctx, tb_weighted, bl_cfg, data_imp, n_rows, cont_v, skewed_vars,
      outcome_col, disease_lbl,
      paths_w$title,
      basename(paths_w$filepath),
      "Weighted"
    )
    if (!is.null(out_w)) {
      tbl_df_w <- out_w$tbl_df
      tb_weighted <- out_w$tb
      ctx$results$table_1_nhanes_weighted <- tbl_df_w
    }
  }, error = function(e) {
    weighted_err <<- conditionMessage(e)
    cli::cli_alert_warning("baseline_nhanes weighted table failed: {e$message}")
  })

  if (is.null(tb_weighted) && .bb03_should_pause(bl_cfg, "pause_on_weighted_table_fail", TRUE)) {
    .bb03_pause(
      ctx,
      paste0(
        "NHANES 加权 Table 1 生成失败",
        if (nzchar(weighted_err %||% "")) paste0(": ", weighted_err) else "。"
      ),
      "检查 nhanes_design、结局列、exclude_cols 与 gtsummary/survey 报错；确认已运行 block_obj。",
      utils::head(data_imp, 5L)
    )
  }

  if (!is.null(tbl_df_w)) {
    ctx$results$table_1    <- tbl_df_w
    ctx$results$table_1_gt <- tb_weighted
  }

  # dev_internal_ext：加权 train-vs-internal 基线附表（对齐 14_肌少症 S12 口径）。
  # 默认关闭；ml_dual_dev_ext overrides 置 TRUE，仅发病双库 dev_ext 触发。
  if (isTRUE(bl_cfg$export_train_val_baseline %||% FALSE) &&
      !is.null(tb_weighted)) {
    tryCatch({
      tr <- ctx$data$train
      va <- ctx$data$test %||% ctx$data$validation
      idc <- cfg$data$id_column %||% "ID"
      dv0 <- design_tbl$variables
      if (!is.null(tr) && !is.null(va) && is.data.frame(tr) && is.data.frame(va) &&
          idc %in% names(dv0) && wt_col %in% names(dv0)) {
        tr_ids <- unique(as.character(tr[[idc]]))
        va_ids <- setdiff(unique(as.character(va[[idc]])), tr_ids)
        dv <- dv0
        dv$.Split_Set <- factor(
          ifelse(as.character(dv[[idc]]) %in% tr_ids, "Training",
                 ifelse(as.character(dv[[idc]]) %in% va_ids, "Validation", NA_character_)),
          levels = c("Training", "Validation")
        )
        dv_keep <- !is.na(dv$.Split_Set) & !is.na(dv[[wt_col]]) & dv[[wt_col]] > 0
        des_tv <- survey::svydesign(
          ids = stats::as.formula(paste0("~", psu_col)),
          strata = stats::as.formula(paste0("~", str_col)),
          weights = stats::as.formula(paste0("~", wt_col)),
          data = dv[dv_keep, , drop = FALSE], nest = TRUE
        )
        tv_include <- intersect(nhanes_include_vars, names(dv))
        skewed_hit_tv <- intersect(skewed_vars, names(dv))
        if (exists("pipeline_median_stat_vars", mode = "function")) {
          skewed_hit_tv <- pipeline_median_stat_vars(dv, skewed_hit_tv)
        }
        stat_tv <- list(
          all_continuous() ~ "{mean} ({sd})",
          all_categorical() ~ "{n_unweighted} ({p}%)"
        )
        if (length(skewed_hit_tv)) {
          stat_tv <- c(
            stat_tv,
            stats::setNames(
              rep(list("{median} ({p25}, {p75})"), length(skewed_hit_tv)),
              skewed_hit_tv
            )
          )
        }
        tv_args <- list(
          des_tv,
          by = dplyr::all_of(".Split_Set"),
          include = dplyr::all_of(tv_include),
          digits = list(all_continuous() ~ 2, all_categorical() ~ 2),
          statistic = stat_tv
        )
        if (!is.null(type_arg) && length(type_arg)) tv_args$type <- type_arg
        tb_tv <- do.call(gtsummary::tbl_svysummary, tv_args) %>%
          gtsummary::add_p(pvalue_fun = ~gtsummary::style_pvalue(.x, digits = 2)) %>%
          gtsummary::add_overall() %>%
          gtsummary::modify_header(
            all_stat_cols() ~ "**{level}** \n (Unweighted N = {n_unweighted})"
          )
        cap_tv <- bl_cfg$train_val_table_title %||%
          "Baseline characteristics by training and internal validation sets (after multiple imputation)"
        cap_tv <- sub("^Table S\\d+\\.\\s*", "", cap_tv)
        paths_tv <- pub_paths(ctx, ctx$output_dir_tables, "supp_table", cap_tv, "xlsx")
        tb_tv <- tb_tv %>% gtsummary::modify_caption(paste0("**", paths_tv$title, "**"))
        out_tv <- .bb03_export_nhanes_table(
          ctx, tb_tv, bl_cfg, dv[dv_keep, , drop = FALSE], sum(dv_keep),
          cont_v, skewed_vars, ".Split_Set", "Training vs Validation",
          paths_tv$title, basename(paths_tv$filepath), "TrainVal"
        )
        if (!is.null(out_tv)) ctx$results$table_train_val_baseline <- out_tv$tbl_df
        cli::cli_alert_success(
          "dev_ext 加权 train-vs-internal 基线表已导出: {.file {basename(paths_tv$filepath)}}"
        )
      }
    }, error = function(e) {
      cli::cli_alert_warning("baseline_nhanes train-vs-internal 基线表失败（跳过）: {e$message}")
    })
  }

  cli::cli_h2("baseline_nhanes: filtering variables from weighted table")
  sig_vars <- tryCatch(
    .bb03_extract_sig_vars(tb_weighted, sig_cutoff),
    error = function(e) {
      cli::cli_alert_warning("Significance filter failed: {e$message}")
      character(0)
    }
  )
  sig_continuous  <- intersect(sig_vars, continuous_vars)
  sig_categorical <- intersect(sig_vars, categorical_vars)
  cli::cli_alert_success(
    "Selected {length(sig_vars)} variables ({length(sig_continuous)} continuous, {length(sig_categorical)} categorical)"
  )
  ctx$results$sig_vars         <- sig_vars
  ctx$results$continuous_vars  <- continuous_vars
  ctx$results$categorical_vars <- categorical_vars
  ctx$results$normal_vars      <- normal_vars
  ctx$results$skewed_vars      <- skewed_vars
  ctx$results$sig_continuous   <- sig_continuous
  ctx$results$sig_categorical  <- sig_categorical
  ctx$results$baseline_mode    <- "nhanes"
  ctx$results$baseline_nhanes_done <- TRUE
  ctx$results$nhanes_baseline_table <- !is.null(tbl_df_w)

  # 暴露指标(index_var)组间比较不显著 → 早停整条 pipeline（基于加权 Table 1 的 p 值）。
  # 默认开启（开关写死在代码：bl_cfg$early_stop_if_index_ns %||% TRUE），
  # config$baseline_nhanes 设 early_stop_if_index_ns = FALSE 可临时关闭。
  if (isTRUE(bl_cfg$early_stop_if_index_ns %||% TRUE)) {
    index_var <- as.character(
      cfg$incidence$index_var %||% cfg$survival$index_var %||%
      cfg$project$index_var   %||% cfg$logistic$index_var %||%
      bl_cfg$index_var %||% NA_character_
    )[1L]
    if (!is.na(index_var) && nzchar(index_var)) {
      pv_col <- tb_weighted$table_body[[
        if ("p.value" %in% names(tb_weighted$table_body)) "p.value" else "p_value"
      ]]
      idx_p <- suppressWarnings(as.numeric(
        gsub("[<>]", "", pv_col[which(tb_weighted$table_body$variable == index_var)])
      ))[1L]
      if (!index_var %in% unique(tb_weighted$table_body$variable) || is.na(idx_p)) {
        cli::cli_alert_warning(
          "early_stop: 暴露指标 {index_var} 不在加权 Table 1 或组间 p 值缺失，跳过早停判定。"
        )
      } else if (idx_p >= sig_cutoff) {
        stop(
          "BASELINE_INDEX_NS_STOP: 暴露指标 ", index_var,
          " 加权组间比较 P = ", fmt_pval(idx_p),
          " >= ", sig_cutoff, "，按 early_stop_if_index_ns 早停 pipeline。",
          call. = FALSE
        )
      }
    }
  }

  writeLines(continuous_vars,  file.path(ctx$output_dir, "continuous_vars.txt"))
  writeLines(categorical_vars, file.path(ctx$output_dir, "categorical_vars.txt"))
  writeLines(normal_vars,      file.path(ctx$output_dir, "normal_vars.txt"))
  writeLines(skewed_vars,      file.path(ctx$output_dir, "skewed_vars.txt"))
  writeLines(sig_vars,         file.path(ctx$output_dir, "sig_vars.txt"))

  if (length(sig_vars) < pause_min_sig &&
      .bb03_should_pause(bl_cfg, "pause_on_min_sig_vars", TRUE)) {
    .bb03_pause(
      ctx,
      paste0(
        "加权 Table 1 组间比较后通过 sig_cutoff 的变量仅 ", length(sig_vars), " 个",
        "（阈值要求至少 ", pause_min_sig, " 个）。"
      ),
      paste0(
        "放宽 config$baseline_nhanes$sig_cutoff、调整 pause_min_sig_vars，",
        "或设 pause_on_min_sig_vars = FALSE 后继续下游。"
      ),
      data.frame(
        sig_vars = sig_vars,
        sig_cutoff = sig_cutoff,
        stringsAsFactors = FALSE
      )
    )
  }

  ctx
}

register_block(
  "baseline_nhanes",
  block_baseline_nhanes,
  "NHANES: weighted Table 1 + normality supp table; sig_vars from weighted table"
)
