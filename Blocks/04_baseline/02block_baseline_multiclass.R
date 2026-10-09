###############################################################################
#  baseline_multiclass — 多分类分层 Table 1（ANOVA / Kruskal-Wallis）+ 显著变量筛选。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data          = ctx$data$imputed %||% ctx$data$cleaned
#  require_strata_levels_min = 3L,   # 分层列水平数 >= 3，否则 pause / stop
#
#  baseline_multiclass = list(
#    sig_cutoff   = 0.05,              # 组间比较筛选；优先于 p_threshold
#    p_threshold  = 0.05,              # sig_cutoff 别名
#    strata       = NULL,              # 分层列；NULL 由 data/project 推断
#    include_vars = NULL,              # 非空时仅保留所列变量
#    exclude_vars = character(0),
#    table1_label_overrides      = list(),   # 列名 → 展示标签
#    table1_sections             = NULL,   # Table 1 小节
#    table1_sections_disable_default = FALSE,
#    table1_xlsx_section_anchors = NULL,
#    table1_xlsx_center_first_col = character(0),
#    table1_xlsx_footnotes       = NULL,
#    pause_enable                = TRUE,
#    pause_on_table1_fail        = TRUE,
#    pause_on_min_sig_vars       = TRUE,
#    pause_min_sig_vars          = 3L      # 显著变量数不足时暂停
#  ),
#  # 全局：config$analysis_var_policy$min_categorical_n=20（任一层级 n<20 的分类列在表/图前删除）
#
#  register_block: "baseline_multiclass"
#  典型流水线: imputation 后；strata 水平数 >= 3（ANOVA / Kruskal-Wallis）
#  写: sig_vars、Table 1；pause 规则同 baseline_binary
#  块内读取 config$baseline_multiclass
###############################################################################

.bb02_resolve_table1_footnotes <- function(bl_cfg, ...) {
  ft_cfg <- bl_cfg$table1_xlsx_footnotes %||% NULL
  if (!is.null(ft_cfg) && length(ft_cfg) > 0L) {
    out <- as.character(unlist(ft_cfg, use.names = FALSE))
    return(out[nzchar(trimws(out))])
  }
  do.call(table1_baseline_xlsx_footnotes, list(...))
}

.bb02_test_normality <- function(x) {
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

.bb02_apply_table1_label_overrides_to_gt <- function(tbl, lbl_ov) {
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

.bb02_ensure_baseline_dictionary_labels <- function(root = NULL) {
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

.bb02_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  val <- bl_cfg[[key]]
  if (is.null(val)) return(isTRUE(default))
  isTRUE(val)
}

.bb02_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- data_snapshot
  if (is.null(snap)) {
    snap <- data.frame(note = "no snapshot")
  } else if (!is.data.frame(snap)) {
    snap <- utils::head(as.data.frame(snap), 5L)
  } else {
    snap <- utils::head(snap, 5L)
  }
  ctx$results$pause_point <- list(
    block         = "baseline_multiclass",
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

.bb02_resolve_sig_cutoff <- function(bl_cfg, ctx) {
  cutoff <- bl_cfg$sig_cutoff
  if (is.null(cutoff)) cutoff <- bl_cfg$p_threshold
  if (is.null(cutoff)) {
    .bb02_pause(
      ctx,
      "未配置 config$baseline_multiclass$sig_cutoff（或 legacy p_threshold）。",
      "在 config$baseline_multiclass 中设置 sig_cutoff，或设 pause_enable = FALSE 后自行处理。",
      NULL
    )
  }
  as.numeric(cutoff)[1L]
}

.bb02_extract_sig_vars <- function(tbl, cutoff) {
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

.bb02_export_table1 <- function(ctx, tbl, bl_cfg, cfg, data, n_groups,
                                normal_vars, skewed_vars, categorical_vars,
                                fisher_vars, title_t1) {
  if (is.null(tbl)) return(ctx)

  bdy <- tbl$table_body
  if (is.data.frame(bdy) && nrow(bdy) > 0L && "variable" %in% names(bdy)) {
    vn <- as.character(bdy$variable)
    hit_var <- grepl("futime", vn, ignore.case = TRUE)
    if (any(hit_var)) {
      if ("row_type" %in% names(bdy)) {
        rt <- as.character(bdy$row_type)
        idx <- hit_var & rt == "label"
      } else {
        idx <- hit_var & !duplicated(vn)
      }
      if ("label" %in% names(bdy) && any(idx)) {
        bdy$label[idx] <- "Follow-up time"
        tbl$table_body <- bdy
      }
    }
  }

  lbl_ov <- bl_cfg$table1_label_overrides %||% NULL
  root_lbl <- (cfg$project %||% list())$root %||%
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "") %||% getwd()
  if (.bb02_ensure_baseline_dictionary_labels(root_lbl) &&
      exists("baseline_merge_table1_unit_label_overrides", mode = "function")) {
    vars_tbl <- if (is.data.frame(tbl$table_body) && "variable" %in% names(tbl$table_body)) {
      unique(as.character(tbl$table_body$variable))
    } else {
      character(0)
    }
    bl_cfg <- baseline_merge_table1_unit_label_overrides(cfg, bl_cfg, vars_tbl, root_lbl)
    lbl_ov <- bl_cfg$table1_label_overrides %||% NULL
  }
  tbl <- .bb02_apply_table1_label_overrides_to_gt(tbl, lbl_ov)
  tbl_df <- as.data.frame(tbl)
  filepath <- .inject_db_into_pub_filepath(
    file.path(ctx$output_dir_tables, paste0(title_t1, ".xlsx"))
  )

  sec_cfg <- bl_cfg$table1_sections
  if (!is.null(sec_cfg) && length(sec_cfg) == 0L) sec_cfg <- NULL
  section_rows <- NULL
  if (!is.null(sec_cfg) && length(sec_cfg) > 0L) {
    section_rows <- table1_section_insert_rows_from_gtsummary(tbl, sec_cfg)
  }
  if (is.null(section_rows) || length(section_rows) == 0L) {
    if (!isTRUE(bl_cfg$table1_sections_disable_default)) {
      section_rows <- table1_section_insert_rows_from_gtsummary(tbl, .default_table1_sections())
    }
  }
  anchors <- bl_cfg$table1_xlsx_section_anchors %||% NULL
  use_section_rows <- !is.null(section_rows) && length(section_rows) > 0L
  center_labs <- as.character(bl_cfg$table1_xlsx_center_first_col %||% character(0))
  center_labs <- center_labs[nzchar(center_labs)]
  xlsx_footnotes <- .bb02_resolve_table1_footnotes(
    bl_cfg,
    n_obs = nrow(data),
    n_groups = n_groups,
    has_normal_continuous = length(normal_vars) > 0L,
    has_skewed_continuous = length(skewed_vars) > 0L,
    has_categorical = length(categorical_vars) > 0L,
    use_fisher_any = length(fisher_vars) > 0L
  )
  built <- table1_build_display_df(
    tbl_df,
    section_insert_rows = if (use_section_rows) section_rows else NULL,
    section_anchors = if (use_section_rows) NULL else anchors,
    gtsummary_tbl = tbl,
    center_first_col_values = center_labs
  )
  table1_xlsx_styled <- FALSE
  tryCatch({
    write_table1_xlsx_guan_style(
      tbl_df,
      filepath,
      title_t1,
      footnotes = xlsx_footnotes,
      prebuilt = built
    )
    table1_xlsx_styled <- TRUE
    cli::cli_alert_success("Excel Table 1 (openxlsx) saved: {.file {basename(filepath)}}")
  }, error = function(e) {
    cli::cli_alert_warning("Table 1 Excel styled export failed: {e$message}")
  })
  export_sci_table(
    tbl_df,
    filepath,
    title = title_t1,
    skip_excel = table1_xlsx_styled,
    latex_include_colnames = FALSE,
    table1_render_spec = list(
      df = built$df,
      footnotes = xlsx_footnotes,
      insert_map = built$insert_map,
      level_row_idx = built$level_row_idx
    )
  )
  ctx$results$table_1    <- tbl_df
  ctx$results$table_1_gt <- tbl
  cli::cli_alert_success("Table 1 saved (multiclass strata)")
  ctx
}

block_baseline_multiclass <- function(ctx, strata_var = NULL, ...) {
  suppressPackageStartupMessages({
    library(gtsummary)
    library(dplyr)
  })

  cfg  <- ctx$config
  bl_cfg <- cfg$baseline_multiclass %||% list()
  if (exists("pipeline_apply_sparse_categorical_drop_to_ctx", mode = "function")) {
    ctx <- pipeline_apply_sparse_categorical_drop_to_ctx(ctx, slots = c("imputed", "cleaned"))
    cfg <- ctx$config
  }
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) {
    .bb02_pause(
      ctx,
      "未找到分析数据（ctx$data$imputed 与 cleaned 均为空）。",
      "请先运行 data_clean、column_mapping、imputation。",
      NULL
    )
  }

  outcome_col   <- cfg$data$outcome_column %||% "Disease"
  study_type    <- tolower(cfg$project$study_type %||% "incidence")
  analysis_grp  <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
  reference_grp <- cfg$project$reference_group %||% "Control"
  strata <- strata_var %||% bl_cfg$strata %||%
    if (identical(study_type, "prognosis")) (cfg$survival$event_var %||% outcome_col) else outcome_col
  id_col <- cfg$data$id_column %||% "SEQN"
  sig_cutoff <- .bb02_resolve_sig_cutoff(bl_cfg, ctx)
  pause_min_sig <- as.integer(bl_cfg$pause_min_sig_vars %||% 3L)

  if (!strata %in% names(data)) {
    .bb02_pause(
      ctx,
      paste0("分层列不在数据中: ", strata, " (study_type=", study_type, ")"),
      "检查 config$baseline_multiclass$strata、study_type 或 run_block 的 strata_var 参数。",
      utils::head(data, 5L)
    )
  }

  strata_vals <- na.omit(unique(data[[strata]]))
  if (is.numeric(data[[strata]]) && all(strata_vals %in% c(0, 1))) {
    data[[strata]] <- ifelse(data[[strata]] == 1, analysis_grp, reference_grp)
  }

  n_groups <- length(unique(na.omit(data[[strata]])))
  if (n_groups < 3L) {
    .bb02_pause(
      ctx,
      paste0("baseline_multiclass 要求分层列至少 3 个水平，当前为 ", n_groups, " 个。"),
      "请改用 baseline_binary，或调整 strata / 数据分组。",
      utils::head(data[, c(strata, outcome_col), drop = FALSE], 5L)
    )
  }

  cli::cli_h2("baseline_multiclass: classifying variables")

  id_strip <- unique(c(
    as.character(id_col %||% character(0)),
    as.character((cfg$data %||% list())$strip_id_columns_after_imputation %||% character(0)),
    "ID"
  ))
  id_strip <- id_strip[nzchar(id_strip)]
  non_vars <- unique(c(outcome_col, id_strip, strata))
  candidates <- setdiff(names(data), non_vars)

  excl_cfg <- as.character(bl_cfg$exclude_vars %||% character(0))
  excl_cfg <- excl_cfg[nzchar(excl_cfg)]
  excl_hit <- intersect(excl_cfg, candidates)
  excl_miss <- setdiff(excl_cfg, names(data))
  if (length(excl_miss) > 0L) {
    cli::cli_alert_warning(
      "baseline$exclude_vars not in data (ignored): {paste(excl_miss, collapse = ', ')}"
    )
  }
  candidates <- setdiff(candidates, excl_hit)
  if (length(excl_hit) > 0L) {
    cli::cli_alert_info("Excluded from Table 1: {paste(excl_hit, collapse = ', ')}")
  }

  inc_cfg <- bl_cfg$include_vars
  if (!is.null(inc_cfg) && length(as.character(inc_cfg)) > 0L) {
    inc_cfg <- as.character(inc_cfg)
    inc_cfg <- inc_cfg[nzchar(inc_cfg)]
    inc_miss <- setdiff(inc_cfg, names(data))
    if (length(inc_miss) > 0L) {
      cli::cli_alert_warning(
        "baseline$include_vars not in data (ignored): {paste(inc_miss, collapse = ', ')}"
      )
    }
    analysis_vars <- inc_cfg[inc_cfg %in% candidates]
    inc_dropped <- setdiff(inc_cfg, candidates)
    inc_dropped <- setdiff(inc_dropped, inc_miss)
    if (length(inc_dropped) > 0L) {
      cli::cli_alert_info(
        "include_vars dropped (outcome/ID/strata/exclude): {paste(inc_dropped, collapse = ', ')}"
      )
    }
    if (length(analysis_vars) == 0L) {
      .bb02_pause(
        ctx,
        "baseline$include_vars 与候选变量交集为空。",
        "检查 include_vars 列名、exclude_vars 及结局/ID/分层列设置。",
        utils::head(data, 5L)
      )
    }
    cli::cli_alert_info("Table 1 variables (include_vars): {length(analysis_vars)}")
  } else {
    analysis_vars <- candidates
  }

  if (exists("sort_vars_by_table1_sections", mode = "function")) {
    analysis_vars <- sort_vars_by_table1_sections(analysis_vars, cfg)
  }
  ctx$results$table1_var_order <- analysis_vars

  force_continuous <- cfg$force_continuous_vars %||% c()
  all_numeric <- analysis_vars[sapply(data[, analysis_vars, drop = FALSE], is.numeric)]
  discrete_threshold <- 5
  is_discrete <- sapply(all_numeric, function(v) {
    if (v %in% force_continuous) {
      cli::cli_alert_info("Variable '{v}' forced continuous (force_continuous_vars)")
      FALSE
    } else {
      length(unique(na.omit(data[[v]]))) <= discrete_threshold
    }
  })
  continuous_vars <- all_numeric[!is_discrete]
  discrete_numeric <- all_numeric[is_discrete]
  for (v in discrete_numeric) {
    data[[v]] <- as.factor(data[[v]])
    cli::cli_alert_info("Variable '{v}' as categorical (n_unique={length(unique(na.omit(data[[v]])))})")
  }
  categorical_vars <- c(setdiff(analysis_vars, all_numeric), discrete_numeric)

  cli::cli_h2("baseline_multiclass: normality (n={nrow(data)})")
  normality_result <- sapply(continuous_vars, function(v) .bb02_test_normality(data[[v]]))
  normal_vars <- continuous_vars[normality_result]
  skewed_vars <- continuous_vars[!normality_result]
  cli::cli_alert_info(
    "Normal: {length(normal_vars)}, Skewed: {length(skewed_vars)}, Categorical: {length(categorical_vars)}"
  )

  normality_df <- data.frame(
    variable  = continuous_vars,
    method    = ifelse(nrow(data) > 5000, "Kolmogorov-Smirnov", "Shapiro-Wilk"),
    is_normal = normality_result,
    statistic = ifelse(normality_result, "Mean (SD)", "Median (Q1, Q3)"),
    stringsAsFactors = FALSE
  )
  ctx <- save_result(ctx, "normality_test", normality_df, "normality_test.csv")

  cli::cli_h2("baseline_multiclass: Table 1 (strata={strata}, {n_groups} groups)")

  stat_list <- c(
    setNames(rep(list("{mean} \u00b1 {sd}"), length(normal_vars)), normal_vars),
    setNames(rep(list("{median} ({p25}, {p75})"), length(skewed_vars)), skewed_vars),
    setNames(rep(list("{n} ({p}%)"), length(categorical_vars)), categorical_vars)
  )
  force_cont_in_data <- intersect(force_continuous, analysis_vars)
  type_list <- if (length(force_cont_in_data) > 0) {
    setNames(rep(list("continuous"), length(force_cont_in_data)), force_cont_in_data)
  } else {
    NULL
  }

  fisher_vars <- categorical_vars[sapply(categorical_vars, function(v) {
    tbl_v <- table(data[[v]], data[[strata]])
    any(tbl_v < 5)
  })]

  test_list <- c(
    setNames(lapply(normal_vars, function(v) "aov"), normal_vars),
    setNames(lapply(skewed_vars, function(v) "kruskal.test"), skewed_vars),
    setNames(
      lapply(categorical_vars, function(v) {
        if (v %in% fisher_vars) "fisher.test" else "chisq.test"
      }),
      categorical_vars
    )
  )

  fisher_test_args <- if (length(fisher_vars) > 0L) {
    stats::setNames(
      rep(list(list(workspace = 2e8, simulate.p.value = TRUE, B = 2000)), length(fisher_vars)),
      fisher_vars
    )
  } else {
    NULL
  }

  tbl_err <- NULL
  tbl <- tryCatch({
    tbl_args <- list(
      data      = data %>% dplyr::select(dplyr::all_of(c(strata, analysis_vars))),
      by        = strata,
      statistic = stat_list,
      digits    = list(
        all_continuous()  ~ 2,
        all_categorical() ~ c(0, 2)
      ),
      missing = "no"
    )
    if (!is.null(type_list)) tbl_args$type <- type_list
    do.call(tbl_summary, tbl_args) %>%
      add_p(
        test = test_list,
        pvalue_fun = function(x) fmt_pval(x),
        test.args = fisher_test_args
      ) %>%
      add_overall() %>%
      bold_p(t = sig_cutoff)
  }, error = function(e) {
    tbl_err <<- conditionMessage(e)
    NULL
  })

  if (is.null(tbl) && .bb02_should_pause(bl_cfg, "pause_on_table1_fail", TRUE)) {
    .bb02_pause(
      ctx,
      paste0("Table 1 生成失败", if (nzchar(tbl_err %||% "")) paste0(": ", tbl_err) else "."),
      "检查变量类型、分层列水平、样本量或 gtsummary 报错信息；可调整 include_vars / exclude_vars。",
      utils::head(data[, c(strata, analysis_vars[seq_len(min(3L, length(analysis_vars)))]), drop = FALSE], 5L)
    )
  }

  dis_t1 <- gsub("_", " ", cfg$project$disease %||% "", fixed = TRUE)
  title_t1 <- pub_title(ctx, "main_table", paste0("Baseline characteristics of ", dis_t1))
  ctx <- .bb02_export_table1(
    ctx, tbl, bl_cfg, cfg, data, n_groups,
    normal_vars, skewed_vars, categorical_vars, fisher_vars, title_t1
  )

  cli::cli_h2("baseline_multiclass: filtering variables by table comparison column")
  sig_vars <- tryCatch(
    .bb02_extract_sig_vars(tbl, sig_cutoff),
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
  ctx$results$baseline_mode    <- "multiclass"

  # 暴露指标(index_var)组间比较不显著 → 早停整条 pipeline。
  # 默认开启（开关写死在代码：bl_cfg$early_stop_if_index_ns %||% TRUE），
  # config$baseline_multiclass 设 early_stop_if_index_ns = FALSE 可临时关闭。
  if (isTRUE(bl_cfg$early_stop_if_index_ns %||% TRUE)) {
    index_var <- as.character(
      cfg$incidence$index_var %||% cfg$survival$index_var %||%
      cfg$project$index_var   %||% cfg$logistic$index_var %||%
      bl_cfg$index_var %||% NA_character_
    )[1L]
    if (!is.na(index_var) && nzchar(index_var)) {
      pv_col <- tbl$table_body[[
        if ("p.value" %in% names(tbl$table_body)) "p.value" else "p_value"
      ]]
      idx_p <- suppressWarnings(as.numeric(
        gsub("[<>]", "", pv_col[which(tbl$table_body$variable == index_var)])
      ))[1L]
      if (!index_var %in% unique(tbl$table_body$variable) || is.na(idx_p)) {
        cli::cli_alert_warning(
          "early_stop: 暴露指标 {index_var} 不在 Table 1 或组间 p 值缺失，跳过早停判定。"
        )
      } else if (idx_p >= sig_cutoff) {
        stop(
          "BASELINE_INDEX_NS_STOP: 暴露指标 ", index_var,
          " 组间比较 P = ", fmt_pval(idx_p),
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
      .bb02_should_pause(bl_cfg, "pause_on_min_sig_vars", TRUE)) {
    .bb02_pause(
      ctx,
      paste0(
        "组间比较后通过 sig_cutoff 的变量仅 ", length(sig_vars), " 个",
        "（阈值要求至少 ", pause_min_sig, " 个）。"
      ),
      paste0(
        "放宽 config$baseline_multiclass$sig_cutoff、调整 pause_min_sig_vars，",
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
  "baseline_multiclass",
  block_baseline_multiclass,
  "Table 1 (>=3 strata): aov / kruskal + sig_vars from config$baseline_multiclass"
)
