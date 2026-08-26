###############################################################################
#  baseline_binary — 二分类分层 Table 1（t / Wilcoxon）+ 显著变量筛选。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data          = ctx$data$imputed %||% ctx$data$cleaned
#  require_strata_levels = 2L,   # 分层列水平数必须恰好为 2，否则 pause / stop
#
#  baseline_binary = list(
#    sig_cutoff   = 0.05,              # 显著性筛选阈值；优先于 p_threshold
#    p_threshold  = 0.05,              # legacy 别名，sig_cutoff 为空时使用
#    strata       = NULL,              # 分层列名；NULL → 由 data / project / survival 推断
#    include_vars = NULL,              # 非空时仅保留所列变量（顺序保留）
#    exclude_vars = character(0),      # 从候选列中剔除
#    table1_label_overrides      = list(),   # 列名 → 表内展示标签
#    table1_sections             = NULL,   # 命名 list，Table 1 小节标题
#    table1_sections_disable_default = FALSE,
#    table1_xlsx_section_anchors = NULL,
#    table1_xlsx_center_first_col = character(0),
#    table1_xlsx_footnotes       = NULL,   # NULL → utils 默认脚注
#    pause_enable                = TRUE,   # FALSE = 不触发 pause_point
#    pause_on_table1_fail        = TRUE,
#    pause_on_min_sig_vars       = TRUE,
#    pause_min_sig_vars          = 3L      # 通过 sig_cutoff 的变量数少于此值时暂停
#  ),
#  # 全局：config$analysis_var_policy$min_categorical_n=20（任一层级 n<20 的分类列在表/图前删除）
#
#  register_block: "baseline_binary"
#  典型流水线: imputation 后；strata 列须恰好 2 水平（low/high 或 Case/Control）
#  写: ctx$results$sig_vars、continuous_vars、table1_*；Table 1 xlsx/tex；Table S* 正态性检验表
#  块内读取 config$baseline_binary；分层列/结局见 project、data、baseline$strata
###############################################################################

.bb01_resolve_table1_footnotes <- function(bl_cfg, ...) {
  ft_cfg <- bl_cfg$table1_xlsx_footnotes %||% NULL
  if (!is.null(ft_cfg) && length(ft_cfg) > 0L) {
    out <- as.character(unlist(ft_cfg, use.names = FALSE))
    return(out[nzchar(trimws(out))])
  }
  do.call(table1_baseline_xlsx_footnotes, list(...))
}

.bb01_test_normality <- function(x) {
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

.bb01_apply_table1_label_overrides_to_gt <- function(tbl, lbl_ov) {
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

.bb01_ensure_baseline_dictionary_labels <- function(root = NULL) {
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

.bb01_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  val <- bl_cfg[[key]]
  if (is.null(val)) return(isTRUE(default))
  isTRUE(val)
}

.bb01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- data_snapshot
  if (is.null(snap)) {
    snap <- data.frame(note = "no snapshot")
  } else if (!is.data.frame(snap)) {
    snap <- utils::head(as.data.frame(snap), 5L)
  } else {
    snap <- utils::head(snap, 5L)
  }
  ctx$results$pause_point <- list(
    block         = "baseline_binary",
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

.bb01_resolve_sig_cutoff <- function(bl_cfg, ctx) {
  cutoff <- bl_cfg$sig_cutoff
  if (is.null(cutoff)) cutoff <- bl_cfg$p_threshold
  if (is.null(cutoff)) {
    .bb01_pause(
      ctx,
      "未配置 config$baseline_binary$sig_cutoff（或 legacy p_threshold）。",
      "在 config$baseline_binary 中设置 sig_cutoff，或设 pause_enable = FALSE 后自行处理。",
      NULL
    )
  }
  as.numeric(cutoff)[1L]
}

.bb01_extract_sig_vars <- function(tbl, cutoff) {
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
  test_chr <- as.character(test_col)
  test_num <- suppressWarnings(as.numeric(gsub("[<>]", "", test_chr)))
  lt <- grepl("^\\s*<\\s*", test_chr)
  test_num[lt] <- pmax(0, suppressWarnings(as.numeric(gsub("[^0-9.]", "", test_chr[lt]))) - 1e-6)
  sig_rows <- !is.na(test_num) & test_num < cutoff
  unique(tbl$table_body$variable[sig_rows])
}

.bb01_export_table1 <- function(ctx, tbl, bl_cfg, cfg, data, n_groups,
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
  vars_tbl <- if (is.data.frame(tbl$table_body) && "variable" %in% names(tbl$table_body)) {
    unique(as.character(tbl$table_body$variable))
  } else {
    character(0)
  }
  # 字典单位可选；内置展示名（FI→Frailty Index）在 merge 内始终写入
  invisible(.bb01_ensure_baseline_dictionary_labels(root_lbl))
  if (exists("baseline_merge_table1_unit_label_overrides", mode = "function")) {
    bl_cfg <- baseline_merge_table1_unit_label_overrides(cfg, bl_cfg, vars_tbl, root_lbl)
    lbl_ov <- bl_cfg$table1_label_overrides %||% NULL
  } else if (exists("pipeline_builtin_var_display_names", mode = "function") && length(vars_tbl)) {
    bn <- pipeline_builtin_var_display_names()
    keys <- intersect(names(bn), vars_tbl)
    if (length(keys))
      lbl_ov <- utils::modifyList(as.list(bn[keys]), as.list(lbl_ov %||% list()))
  }
  tbl <- .bb01_apply_table1_label_overrides_to_gt(tbl, lbl_ov)
  tbl_df <- as.data.frame(tbl)
  # 暴露指标 Overall IQR 与 Cox 切点同源（quantile type=7 + 两位小数）
  ix_t1 <- as.character(
    cfg$survival$index_var %||% cfg$incidence$index_var %||% NA_character_
  )[1L]
  if (is.finite(match(ix_t1, names(data))) && exists("fmt_continuous", mode = "function")) {
    ix_vec <- data[[ix_t1]]
    # baseline_binary 里离散数值暴露可能被转成 factor（如 Periodontitis 0-3）；
    # 此时按数值可逆转换后再算 IQR，避免 quantile(factor) 报错。
    if (is.factor(ix_vec)) {
      ix_num <- suppressWarnings(as.numeric(as.character(ix_vec)))
      if (all(is.na(ix_num) == is.na(ix_vec))) {
        ix_vec <- ix_num
      }
    }
    if (is.numeric(ix_vec)) {
      iqr_ix <- fmt_continuous(ix_vec, is_normal = FALSE)
      lab_ix <- if (exists("pipeline_var_display_name", mode = "function")) {
        pipeline_var_display_name(ix_t1, cfg)
      } else gsub("_", " ", ix_t1)
      c1 <- as.character(tbl_df[[1L]])
      hit <- which(c1 %in% c(ix_t1, lab_ix, gsub("_", " ", ix_t1)))
      if (length(hit) && ncol(tbl_df) >= 2L) {
        # Overall 通常是第 2 列（stat_0）
        tbl_df[[2L]][hit[1L]] <- iqr_ix
      }
    }
  }
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
  xlsx_footnotes <- .bb01_resolve_table1_footnotes(
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
  cli::cli_alert_success("Table 1 saved (binary strata)")
  ctx
}

block_baseline_binary <- function(ctx, strata_var = NULL, ...) {
  suppressPackageStartupMessages({
    library(gtsummary)
    library(dplyr)
  })

  cfg  <- ctx$config
  bl_cfg <- cfg$baseline_binary %||% list()
  # 表/图前兜底：删除任一层级 n<20 的分类列（与 imputation finalize 同一规则）
  if (exists("pipeline_apply_sparse_categorical_drop_to_ctx", mode = "function")) {
    ctx <- pipeline_apply_sparse_categorical_drop_to_ctx(ctx, slots = c("imputed", "cleaned"))
    cfg <- ctx$config
  }
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) {
    .bb01_pause(
      ctx,
      "未找到分析数据（ctx$data$imputed 与 cleaned 均为空）。",
      "请先运行 data_clean、column_mapping、imputation。",
      NULL
    )
  }

  outcome_col   <- cfg$data$outcome_column %||% "Disease"
  study_type    <- tolower(cfg$project$study_type %||% "incidence")
  outcome_lbl   <- pipeline_resolve_outcome_display_labels(cfg)
  analysis_grp  <- outcome_lbl$analysis
  reference_grp <- outcome_lbl$reference
  strata <- strata_var %||% bl_cfg$strata %||%
    if (identical(study_type, "prognosis")) (cfg$survival$event_var %||% outcome_col) else outcome_col
  id_col <- cfg$data$id_column %||% "SEQN"
  sig_cutoff <- .bb01_resolve_sig_cutoff(bl_cfg, ctx)
  pause_min_sig <- as.integer(bl_cfg$pause_min_sig_vars %||% 3L)

  if (!strata %in% names(data)) {
    .bb01_pause(
      ctx,
      paste0("分层列不在数据中: ", strata, " (study_type=", study_type, ")"),
      "检查 config$baseline_binary$strata、study_type 或 run_block 的 strata_var 参数。",
      utils::head(data, 5L)
    )
  }

  strata_vals <- na.omit(unique(data[[strata]]))
  # 预后 Table 1 已按死/活分层，不再衍生 Mortality_28d（否则会与分层列重复）
  ev_raw <- cfg$survival$event_var %||% strata
  strata_lvl_lab <- bl_cfg$strata_level_labels %||% NULL
  if (is.list(strata_lvl_lab) && length(strata_lvl_lab)) {
    # 显式分层标签（如 Diabetes_HbA1c：Non-diabetes / Diabetes），勿套用结局 Case 标签
    x <- as.character(data[[strata]])
    for (nm in names(strata_lvl_lab)) {
      x[x == as.character(nm)] <- as.character(strata_lvl_lab[[nm]])[1L]
    }
    data[[strata]] <- factor(x, levels = unique(as.character(unlist(strata_lvl_lab, use.names = FALSE))))
  } else if (identical(as.character(strata)[1L], as.character(ev_raw)[1L]) ||
             identical(as.character(strata)[1L], as.character(outcome_col)[1L])) {
    if (exists("pipeline_relabel_binary_outcome_column", mode = "function")) {
      data <- pipeline_relabel_binary_outcome_column(data, cfg, col = strata)
    } else if (is.numeric(data[[strata]]) && all(strata_vals %in% c(0, 1))) {
      data[[strata]] <- ifelse(data[[strata]] == 1, analysis_grp, reference_grp)
    }
  } else if (is.numeric(data[[strata]]) && all(strata_vals %in% c(0, 1))) {
    data[[strata]] <- factor(
      ifelse(data[[strata]] == 1, "1", "0"),
      levels = c("0", "1")
    )
  }

  n_groups <- length(unique(na.omit(data[[strata]])))
  if (n_groups != 2L) {
    .bb01_pause(
      ctx,
      paste0("baseline_binary 要求分层列恰好 2 个水平，当前为 ", n_groups, " 个。"),
      "请改用 baseline_multiclass，或调整 strata / 数据分组。",
      utils::head(data[, c(strata, outcome_col), drop = FALSE], 5L)
    )
  }

  cli::cli_h2("baseline_binary: classifying variables")

  id_strip <- unique(c(
    as.character(id_col %||% character(0)),
    as.character((cfg$data %||% list())$strip_id_columns_after_imputation %||% character(0)),
    "ID"
  ))
  id_strip <- id_strip[nzchar(id_strip)]
  inc_pad <- as.character(bl_cfg$include_vars %||% character(0))
  if (isTRUE(bl_cfg$pad_missing_include_vars %||% FALSE) && length(inc_pad)) {
    for (v in unique(inc_pad[nzchar(inc_pad)])) {
      if (!v %in% names(data)) {
        data[[v]] <- NA
        cli::cli_alert_info("Table 1 对齐补空列: {v}")
      }
    }
  }
  non_vars <- unique(c(outcome_col, id_strip, strata))
  candidates <- setdiff(names(data), non_vars)

  excl_cfg <- as.character(bl_cfg$exclude_vars %||% character(0))
  excl_cfg <- excl_cfg[nzchar(excl_cfg)]
  # 分层结局列的别名 / 死亡相关列不应再进发病 Table 1 行
  excl_cfg <- unique(c(
    excl_cfg,
    "Mortality_28d", "Mortality28d", "Mortality_28", "mortality_28d",
    "fustatus", "futime", "death", "Death", "Dead", "dead",
    "in-hospital mortality", "in_hospital_mortality", "inhospital_mortality",
    "is_hosp_dead", "hospdischargestatus", "hospital_expire_flag",
    "expire_flag", "hospitalexpireflag", "dod", "dod_hosp", "dod_ssn",
    as.character(cfg$survival$event_var %||% character(0))
  ))
  # 名称模糊匹配：含 mortality / 28.?day.?mort 的列也排除
  mort_like <- candidates[grepl(
    "mortality|28.?day.?mort|hosp.?dead|expire.?flag|fustatus",
    candidates, ignore.case = TRUE
  )]
  if (length(mort_like)) excl_cfg <- unique(c(excl_cfg, mort_like))
  # JLCM 潜类别列（trajectory_class / trajectory_class_{Index}）不得进 Table 1
  traj_class_cols <- candidates[grepl("^trajectory_class(\\b|_)", candidates, ignore.case = TRUE) |
                                  grepl("^trajectory_class$", candidates, ignore.case = TRUE)]
  if (length(traj_class_cols)) excl_cfg <- unique(c(excl_cfg, traj_class_cols))
  # 时间戳 / 唯一时刻列：若当分类进 Table 1 会「一行一个时刻」暴涨（如 tst_time_zero）
  time_like_names <- candidates[grepl(
    paste0(
      "(^|_)(admit|disch|icu_?in|icu_?out|out|in)_?time$|",
      "(^|_)tst_?time_?zero$|(^|_)time_?zero$|",
      "(^|_)(charttime|storetime|starttime|endtime|deathtime)$"
    ),
    candidates,
    ignore.case = TRUE
  )]
  posix_like <- candidates[vapply(candidates, function(v) {
    inherits(data[[v]], c("POSIXt", "Date", "difftime"))
  }, logical(1L))]
  # 高基数“伪分类”时间/ID（>50 水平且看起来像时间戳字符串）
  high_card_time <- character(0)
  for (v in setdiff(candidates, c(time_like_names, posix_like))) {
    x <- data[[v]]
    if (is.numeric(x) || is.logical(x)) next
    u <- unique(stats::na.omit(as.character(x)))
    if (length(u) <= 50L) next
    sample_u <- utils::head(u, 20L)
    if (mean(grepl(
      "^\\d{1,4}[-/]\\d{1,2}([-/]\\d{1,4})?([ T]\\d|:)",
      sample_u
    )) >= 0.5) {
      high_card_time <- c(high_card_time, v)
    }
  }
  id_like_names <- candidates[grepl(
    paste0(
      "(^|_)(subject_?id|hadm_?id|stay_?id|patient_?id|tst_?patient_?id|",
      "visit_?id|encounter_?id)$"
    ),
    candidates,
    ignore.case = TRUE
  )]
  auto_excl <- unique(c(time_like_names, posix_like, high_card_time, id_like_names))
  if (length(auto_excl)) {
    excl_cfg <- unique(c(excl_cfg, auto_excl))
    cli::cli_alert_info(
      "Auto-excluded time/ID cols from Table 1: {paste(auto_excl, collapse = ', ')}"
    )
  }
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

  always_inc <- as.character(bl_cfg$always_include_vars %||% character(0))
  always_inc <- unique(always_inc[nzchar(always_inc)])
  always_inc <- intersect(always_inc, names(data))
  if (length(always_inc)) {
    candidates <- unique(c(candidates, always_inc))
    cli::cli_alert_info("Table 1 强制纳入: {paste(always_inc, collapse = ', ')}")
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
      .bb01_pause(
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

  force_continuous <- cfg$force_continuous_vars %||% character(0)
  all_numeric <- if (!length(analysis_vars)) {
    character(0)
  } else {
    analysis_vars[vapply(
      analysis_vars,
      function(v) is.numeric(data[[v]]),
      logical(1L)
    )]
  }
  discrete_threshold <- 5
  if (!length(all_numeric)) {
    is_discrete <- logical(0)
    continuous_vars <- character(0)
    discrete_numeric <- character(0)
  } else {
    is_discrete <- vapply(all_numeric, function(v) {
      if (v %in% force_continuous) {
        cli::cli_alert_info("Variable '{v}' forced continuous (force_continuous_vars)")
        FALSE
      } else {
        length(unique(na.omit(data[[v]]))) <= discrete_threshold
      }
    }, logical(1L))
    continuous_vars <- all_numeric[!is_discrete]
    discrete_numeric <- all_numeric[is_discrete]
  }
  for (v in discrete_numeric) {
    data[[v]] <- as.factor(data[[v]])
    cli::cli_alert_info("Variable '{v}' as categorical (n_unique={length(unique(na.omit(data[[v]])))})")
  }
  categorical_vars <- c(setdiff(analysis_vars, all_numeric), discrete_numeric)

  cli::cli_h2("baseline_binary: normality (n={nrow(data)})")
  normality_pvals <- sapply(continuous_vars, function(v) {
    x <- data[[v]][!is.na(data[[v]])]
    n <- length(x)
    if (n < 3) return(NA_real_)
    tryCatch({
      if (n > 5000) stats::ks.test(scale(x), "pnorm")$p.value
      else stats::shapiro.test(x)$p.value
    }, error = function(e) 0)
  })
  normality_result <- sapply(continuous_vars, function(v) .bb01_test_normality(data[[v]]))
  normal_vars <- continuous_vars[normality_result]
  skewed_vars <- continuous_vars[!normality_result]
  median_iqr_cfg <- intersect(as.character(bl_cfg$median_iqr_vars %||% character(0)), continuous_vars)
  if (length(median_iqr_cfg)) {
    normal_vars <- setdiff(normal_vars, median_iqr_cfg)
    skewed_vars <- unique(c(skewed_vars, median_iqr_cfg))
    cli::cli_alert_info(
      "强制 median (IQR) 展示: {paste(median_iqr_cfg, collapse = ', ')}"
    )
  }
  # 非数值型“连续”列改入分类，避免 gtsummary median 统计量报错
  skewed_num <- skewed_vars[sapply(skewed_vars, function(v) is.numeric(data[[v]]))]
  skewed_nonnum <- setdiff(skewed_vars, skewed_num)
  if (length(skewed_nonnum)) {
    for (v in skewed_nonnum) {
      if (!v %in% categorical_vars) data[[v]] <- as.factor(data[[v]])
    }
    categorical_vars <- unique(c(categorical_vars, skewed_nonnum))
  }
  skewed_vars <- skewed_num
  cli::cli_alert_info(
    "Normal: {length(normal_vars)}, Skewed: {length(skewed_vars)}, Categorical: {length(categorical_vars)}"
  )

  normality_df <- data.frame(
    variable  = continuous_vars,
    method    = ifelse(nrow(data) > 5000, "Kolmogorov-Smirnov", "Shapiro-Wilk"),
    p_value   = normality_pvals,
    is_normal = normality_result,
    statistic = ifelse(normality_result, "Mean (SD)", "Median (Q1, Q3)"),
    stringsAsFactors = FALSE
  )
  ctx <- save_result(ctx, "normality_test", normality_df, "normality_test.csv")
  ctx$results$normality_test <- normality_df

  if (nrow(normality_df) > 0L) {
    # NHANES 加权基线已导出正态性时，敏感性 baseline_binary 不再重复占 S 号
    skip_norm <- isTRUE(bl_cfg$skip_normality_export) ||
      isTRUE(ctx$results$baseline_nhanes_done) ||
      !is.null(ctx$results$table_normality_nhanes) ||
      !is.null(ctx$results$table_normality)
    if (isTRUE(skip_norm)) {
      cli::cli_alert_info("baseline_binary: 跳过重复正态性附表导出")
    } else {
      normality_pub <- normality_df
      normality_pub$variable  <- gsub("_", " ", normality_pub$variable, fixed = TRUE)
      normality_pub$p_value   <- fmt_pval(normality_pub$p_value)
      normality_pub$is_normal <- ifelse(normality_pub$is_normal, "Normal", "Skewed")
      names(normality_pub) <- c(
        "Variable", "Test Method", "P Value",
        "Distribution", "Descriptive Statistic"
      )
      cap_norm <- bl_cfg$normality_table_title %||%
        "Normality test results for continuous variables"
      cap_norm <- sub("^Table S\\d+\\.\\s*", "", cap_norm)
      paths_norm <- pub_paths(ctx, ctx$output_dir_tables, "supp_table", cap_norm, "xlsx")
      export_sci_table(normality_pub, paths_norm$filepath, title = paths_norm$title)
      ctx$results$table_normality <- normality_pub
      cli::cli_alert_success(
        "Normality test supplementary table saved: {.file {basename(paths_norm$filepath)}}"
      )
    }
  }

  cli::cli_h2("baseline_binary: Table 1 (strata={strata}, 2 groups)")

  stat_list <- c(
    setNames(rep(list("{mean} \u00b1 {sd}"), length(normal_vars)), normal_vars),
    setNames(rep(list("{median} ({p25}, {p75})"), length(skewed_vars)), skewed_vars)
  )
  cat_stat <- if (length(categorical_vars) > 0L) {
    list(gtsummary::all_categorical() ~ "{n} ({p}%)")
  } else {
    list()
  }
  force_cont_in_data <- intersect(force_continuous, analysis_vars)
  cont_for_type <- unique(c(normal_vars, skewed_vars, force_cont_in_data))
  cont_for_type <- cont_for_type[cont_for_type %in% analysis_vars]
  type_list <- c(
    lapply(cont_for_type, function(v) {
      stats::as.formula(paste0("`", v, "` ~ \"continuous\""))
    }),
    lapply(categorical_vars, function(v) {
      stats::as.formula(paste0("`", v, "` ~ \"categorical\""))
    })
  )

  fisher_vars <- if (length(categorical_vars) > 0L) {
    categorical_vars[vapply(categorical_vars, function(v) {
      tbl_v <- table(data[[v]], data[[strata]])
      any(tbl_v < 5, na.rm = TRUE)
    }, logical(1))]
  } else {
    character(0)
  }

  test_list <- c(
    setNames(lapply(normal_vars, function(v) "t.test"), normal_vars),
    setNames(lapply(skewed_vars, function(v) "wilcox.test"), skewed_vars),
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
      statistic = c(stat_list, cat_stat),
      digits    = list(
        all_continuous()  ~ 2,
        all_categorical() ~ c(0, 2)
      ),
      missing = "no"
    )
    if (length(type_list)) tbl_args$type <- type_list
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

  if (is.null(tbl) && nzchar(tbl_err %||% "")) {
    cli::cli_alert_warning("Table 1 生成失败: {tbl_err}")
  }
  if (is.null(tbl) && .bb01_should_pause(bl_cfg, "pause_on_table1_fail", TRUE)) {
    .bb01_pause(
      ctx,
      paste0("Table 1 生成失败", if (nzchar(tbl_err %||% "")) paste0(": ", tbl_err) else "."),
      "检查变量类型、分层列水平、样本量或 gtsummary 报错信息；可调整 include_vars / exclude_vars。",
      utils::head(data[, c(strata, analysis_vars[seq_len(min(3L, length(analysis_vars)))]), drop = FALSE], 5L)
    )
  }

  dis_t1 <- gsub("_", " ", cfg$project$disease %||% "", fixed = TRUE)
  # NHANES 加权基线已出主文 Table 1 时，本块为敏感性 → 附表
  has_weighted_baseline <- if (exists("pipeline_has_weighted_table1", mode = "function")) {
    pipeline_has_weighted_table1(ctx$results)
  } else {
    !is.null(ctx$results$baseline_table_weighted) ||
      isTRUE(ctx$results$nhanes_baseline_table) ||
      !is.null(ctx$results$table_1_nhanes_weighted)
  }
  tbl_kind <- as.character(bl_cfg$table_kind %||% "")[1L]
  if (!nzchar(tbl_kind)) {
    tbl_kind <- if (has_weighted_baseline) "supp_table" else "main_table"
  }
  # S11 敏感性 caption 需要库名（.attrition_db_label 是 attrition block 内部函数，此处内联取）
  db_lab_s11 <- as.character(
    ((cfg$dual_db %||% list())$current_db %||%
       (cfg$project %||% list())$database %||% "")[1L]
  )
  cap_t1 <- as.character(bl_cfg$table_title %||% "")[1L]
  if (!nzchar(cap_t1)) {
    cap_t1 <- if (isTRUE(has_weighted_baseline)) {
      paste0(
        "Sensitivity analysis: Unweighted baseline characteristics of ",
        "participants with ", dis_t1,
        if (nzchar(db_lab_s11)) paste0(" in ", db_lab_s11) else ""
      )
    } else {
      paste0("Baseline characteristics of ", dis_t1)
    }
  }
  title_t1 <- pub_title(ctx, tbl_kind, cap_t1)
  ctx <- .bb01_export_table1(
    ctx, tbl, bl_cfg, cfg, data, n_groups,
    normal_vars, skewed_vars, categorical_vars, fisher_vars, title_t1
  )

  if (exists("pipeline_population_audit", mode = "function")) {
    ctx <- pipeline_population_audit(
      ctx, "baseline_binary_outcome_strata", data,
      note = paste0("Table 1 by ", strata, " on imputed data (post-MI quality gate if any)")
    )
  }

  # 训练集 vs 验证集基线表（不覆盖结局分层 Table 1）
  export_tv <- isTRUE(bl_cfg$export_train_val_baseline %||% TRUE)
  tr <- ctx$data$train
  va <- ctx$data$test %||% ctx$data$validation
  if (export_tv && !is.null(tr) && is.data.frame(tr) && nrow(tr) > 0L &&
      !is.null(va) && is.data.frame(va) && nrow(va) > 0L) {
    cli::cli_h2("baseline_binary: Table 1 by train/validation (imputed)")
    d_tv <- rbind(
      cbind(tr[, intersect(names(tr), names(data)), drop = FALSE],
            .Split_Set = "Training"),
      cbind(va[, intersect(names(va), names(data)), drop = FALSE],
            .Split_Set = "Validation")
    )
    d_tv$.Split_Set <- factor(d_tv$.Split_Set, levels = c("Training", "Validation"))
    # 与主表使用同一套 analysis_vars（在候选中且在 d_tv）
    av_tv <- intersect(analysis_vars, names(d_tv))
    av_tv <- setdiff(av_tv, c(".Split_Set", strata))
    if (length(av_tv) >= 1L) {
      # 仅对 train/val 表重建 type，避免沿用主表 type_list（变量集合不同）导致报错
      av_num <- av_tv[vapply(av_tv, function(v) is.numeric(d_tv[[v]]), logical(1L))]
      av_cat <- setdiff(av_tv, av_num)
      type_tv <- c(
        lapply(intersect(av_num, c(normal_vars, skewed_vars)), function(v) {
          stats::as.formula(paste0("`", v, "` ~ \"continuous\""))
        }),
        lapply(av_cat, function(v) {
          stats::as.formula(paste0("`", v, "` ~ \"categorical\""))
        })
      )
      stat_tv <- c(
        stat_list[intersect(names(stat_list), av_tv)],
        if (length(av_cat)) list(gtsummary::all_categorical() ~ "{n} ({p}%)") else list()
      )
      tbl_tv <- tryCatch({
        tbl_args_tv <- list(
          data = d_tv %>% dplyr::select(dplyr::all_of(c(".Split_Set", av_tv))),
          by = ".Split_Set",
          statistic = stat_tv,
          digits = list(all_continuous() ~ 2, all_categorical() ~ c(0, 2)),
          missing = "no"
        )
        if (length(type_tv)) tbl_args_tv$type <- type_tv
        do.call(tbl_summary, tbl_args_tv) %>%
          add_p(pvalue_fun = function(x) fmt_pval(x)) %>%
          add_overall() %>%
          bold_p(t = sig_cutoff)
      }, error = function(e) {
        cli::cli_alert_warning("train/validation Table 1 失败: {e$message}")
        NULL
      })
      if (!is.null(tbl_tv)) {
        title_tv <- bl_cfg$train_val_table_title %||%
          paste0(
            "Baseline characteristics by training and validation sets ",
            "(after multiple imputation; n_train=", nrow(tr),
            ", n_validation=", nrow(va), ")"
          )
        # 使用独立文件名，避免覆盖结局分层 Table 1
        paths_tv <- pub_paths(
          ctx, ctx$output_dir_tables, "supp_table",
          sub("^Table S\\d+\\.\\s*", "", title_tv), "xlsx"
        )
        # 脚注明确数据来源
        ft_tv <- c(
          paste0(
            "Population: imputed analysis cohort stratified by train/validation split ",
            "(does not replace the outcome-stratified Table 1)."
          )
        )
        bdy_tv <- tryCatch(as.data.frame(tbl_tv), error = function(e) NULL)
        if (!is.null(bdy_tv)) {
          export_sci_table(
            bdy_tv, paths_tv$filepath, title = paths_tv$title,
            table_footnotes = ft_tv
          )
          ctx$results$table_1_train_validation <- bdy_tv
          cli::cli_alert_success(
            "Train/validation baseline table saved: {.file {basename(paths_tv$filepath)}}"
          )
        }
        if (exists("pipeline_population_audit", mode = "function")) {
          ctx <- pipeline_population_audit(
            ctx, "baseline_binary_train_val", d_tv,
            note = "Supplementary baseline by train/validation split"
          )
        }
      }
    }
  }

  cli::cli_h2("baseline_binary: filtering variables by table comparison column")
  sig_vars <- tryCatch(
    .bb01_extract_sig_vars(tbl, sig_cutoff),
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
  ctx$results$baseline_mode    <- "binary"

  # 暴露指标(index_var)组间比较不显著 → 早停整条 pipeline。
  # 默认开启（开关写死在代码：bl_cfg$early_stop_if_index_ns %||% TRUE），
  # config$baseline_binary 设 early_stop_if_index_ns = FALSE 可临时关闭。
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
          " 组间比较 P = ", format(round(idx_p, 4), scientific = FALSE),
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
      .bb01_should_pause(bl_cfg, "pause_on_min_sig_vars", TRUE)) {
    .bb01_pause(
      ctx,
      paste0(
        "组间比较后通过 sig_cutoff 的变量仅 ", length(sig_vars), " 个",
        "（阈值要求至少 ", pause_min_sig, " 个）。"
      ),
      paste0(
        "放宽 config$baseline_binary$sig_cutoff、调整 pause_min_sig_vars，",
        "或设 pause_on_min_sig_vars = FALSE 后继续下游。"
      ),
      data.frame(
        sig_vars = sig_vars,
        sig_cutoff = sig_cutoff,
        stringsAsFactors = FALSE
      )
    )
  }

  imp_cfg <- cfg$imputation %||% list()
  # 插补块已导出 Table S1；此处再导会占 S3 且标题相同、P 值因变量序/分层不同而看起来冲突
  if (isTRUE(imp_cfg$export_table_s1 %||% TRUE) &&
      !isTRUE(ctx$results$table_s1_exported) &&
      isTRUE(bl_cfg$reexport_table_s1 %||% FALSE) &&
      !is.null(ctx$results$data_before_mi) &&
      !is.null(ctx$data$imputed) &&
      exists(".imp01_build_table_s1", mode = "function")) {
    table_strata <- cfg$baseline$table_strata %||% cfg$survival$exposure %||% outcome_col
    analysis_grp <- cfg$baseline$analysis_group %||% "Case"
    reference_grp <- cfg$baseline$reference_group %||% "Control"
    ctx <- .imp01_build_table_s1(
      ctx, cfg, ctx$results$data_before_mi, ctx$data$imputed,
      table_strata, analysis_grp, reference_grp, imp_cfg
    )
    cli::cli_alert_info("Table S1 已按 Table 1 变量顺序重排导出")
  }

  ctx
}

register_block(
  "baseline_binary",
  block_baseline_binary,
  "Table 1 (2 strata): t.test / wilcox + sig_vars from config$baseline_binary"
)
