###############################################################################
#  data_clean — 加载原始数据、合并结局、衍生指标、行/列过滤与缺失列剔除。
#
#  register_block: "data_clean"
#  典型流水线: 第一步或 column_mapping 之后；产出 cleaned 供 imputation
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_config = config$data$rawdata_path（.RData/.rds/.csv 等）或上游 ctx$data$mapped
#
#  # ── 配置 config$data_clean ─────────────────────────────────────────────────
#  data_clean = list(
#    missing_threshold     = 0.3,   # 列缺失率超过此阈值则删除该列（插补前）
#    row_missing_threshold = NULL,  # 行缺失率超过此阈值则删人；NULL 不筛；建议 ≤0.4
#    row_missing_vars      = NULL,  # 计算行缺失的列；NULL=除 ID/结局外全部数值列
#    age_filter            = NULL,   # 行过滤表达式字符串，如 "Age >= 18"；NULL 不筛行
#    drop_columns          = NULL,   # 额外强制删除的列名向量
#    implausible_ranges    = NULL    # 列→list(min,max,only_if_median_below)；超范围置 NA，不删人
#  ),
#  另读: config$data（outcome_column、id_column、outcome_path）、config$computed_indices、
#        config$project（analysis_group、reference_group、disease）
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$data$raw、ctx$data$cleaned；data_quality_report.csv（缺失与决策日志）
#  源: Blocks/block_data_clean.R（父块保留；Blocks/02_data_clean 为目录化副本）
###############################################################################

block_data_clean <- function(ctx, ...) {
  cfg         <- ctx$config
  outcome_col <- cfg$data$outcome_column   %||% "Disease"
  id_col      <- cfg$data$id_column        %||% "SEQN"
  outcome_lbl <- pipeline_resolve_outcome_display_labels(cfg)
  analysis_grp  <- outcome_lbl$analysis
  reference_grp <- outcome_lbl$reference
  threshold     <- cfg$data_clean$missing_threshold %||% 0.3
  env_threshold <- cfg$data_clean$env_missing_threshold %||% threshold

  rawdata_path <- cfg$data$rawdata_path
  rawdata_obj  <- cfg$data$rawdata_obj  %||% NULL

  cli::cli_h2("Loading raw data")

  if (isTRUE(ctx$results$environment_dkd_prepared %||% FALSE) && !is.null(ctx$data$raw)) {
    data <- ctx$data$raw
    cli::cli_alert_info(
      "Using EnvResult from prepare_environment_dkd_data ({nrow(data)} rows x {ncol(data)} cols)"
    )
  } else if (isTRUE(ctx$results$ip_cohort_prepared %||% FALSE) && !is.null(ctx$data$raw)) {
    data <- ctx$data$raw
    cli::cli_alert_info(
      "Using SLE∩baseline cohort from ip_cohort_sle_aki ({nrow(data)} rows x {ncol(data)} cols)"
    )
  } else if (!is.null(ctx$data$mapped)) {
    data <- ctx$data$mapped
    cli::cli_alert_info("Using mapped data from column_mapping block")
  } else if (!is.null(ctx$data$raw)) {
    data <- ctx$data$raw
    cli::cli_alert_info(
      "Using preloaded ctx$data$raw ({nrow(data)} rows x {ncol(data)} cols)"
    )
  } else {
    # 规范为绝对路径并打印，便于双库对比：若两库此处路径/字节数相同，则读的是同一文件
    abs_raw <- normalizePath(rawdata_path, winslash = "/", mustWork = TRUE)
    fi      <- file.info(abs_raw)
    cli::cli_alert_info("Raw data file (absolute): {.file {abs_raw}}")
    cli::cli_alert_info("File size: {fi$size[[1]]} bytes")
    rawdata_path <- abs_raw

    if (!is.null(rawdata_obj)) {
      env <- new.env()
      load(rawdata_path, envir = env)
      # 优先使用 config 指定的 rawdata_obj；旧逻辑取「第一个 data.frame」会在多对象 RData 中读错表
      if (exists(rawdata_obj, envir = env, inherits = FALSE)) {
        cand <- get(rawdata_obj, envir = env)
        if (is.data.frame(cand)) {
          data <- cand
          cli::cli_alert_info("Loaded object '{rawdata_obj}' from RData (as configured)")
        } else {
          stop("Object '", rawdata_obj, "' in ", rawdata_path, " is not a data.frame")
        }
      } else {
        objs <- ls(env)
        df_objs <- objs[sapply(objs, function(o) is.data.frame(get(o, envir = env)))]
        if (length(df_objs) == 0) stop("No data.frame found in: ", rawdata_path)
        if (length(df_objs) > 1)
          cli::cli_alert_warning("Object '{rawdata_obj}' not found; multiple data.frames in file, using first: {df_objs[1]}")
        data <- get(df_objs[1], envir = env)
        cli::cli_alert_info("Loaded object '{df_objs[1]}' from RData")
      }
    } else {
      data <- load_rawdata(rawdata_path)
    }
  }
  cli::cli_alert_info("Loaded: {nrow(data)} rows x {ncol(data)} cols")
  data <- as.data.frame(data)
  if (exists("pipeline_normalize_yes_no_factors", mode = "function")) {
    data <- pipeline_normalize_yes_no_factors(data)
  }
  if (exists("pipeline_data_clean_rename_columns", mode = "function")) {
    data <- pipeline_data_clean_rename_columns(data, cfg)
  }
  if (exists("pipeline_data_clean_merge_supplement", mode = "function")) {
    data <- pipeline_data_clean_merge_supplement(data, cfg)
  }
  if (exists("pipeline_derive_mimic_survival_28d", mode = "function")) {
    data <- pipeline_derive_mimic_survival_28d(data, cfg)
  }
  if (exists("pipeline_data_clean_apply_cohort_filter", mode = "function")) {
    data <- pipeline_data_clean_apply_cohort_filter(data, cfg)
  }
  if (exists("pipeline_derive_competing_diabetes_28d", mode = "function")) {
    data <- pipeline_derive_competing_diabetes_28d(data, cfg)
  }
  if (exists("pipeline_derive_competing_aki_28d", mode = "function")) {
    data <- pipeline_derive_competing_aki_28d(data, cfg)
  }
  if (exists("pipeline_data_clean_enforce_min_n", mode = "function")) {
    pipeline_data_clean_enforce_min_n(data, cfg, stage = "cohort_merge")
  }
  data <- pipeline_ensure_outcome_group_column(data, cfg)

  subsample_n <- suppressWarnings(as.integer(cfg$data_clean$subsample_n %||% 0L)[1L])
  if (is.finite(subsample_n) && subsample_n > 0L && nrow(data) > subsample_n) {
    subsample_seed <- suppressWarnings(as.integer(cfg$data_clean$subsample_seed %||% 1234L)[1L])
    if (!is.finite(subsample_seed)) subsample_seed <- 1234L
    set.seed(subsample_seed)
    data <- data[sample.int(nrow(data), subsample_n), , drop = FALSE]
    cli::cli_alert_info(
      "随机下采样至 {subsample_n} 行（seed={subsample_seed}，{id_col} 唯一数 {length(unique(data[[id_col]]))}）"
    )
  }

  if ("Disease_Group" %in% names(data) && !"Disease_Group" %in% names(ctx$data$raw %||% list())) {
    cli::cli_alert_info("data_clean: 已确保 outcome 列 Disease_Group（由 Disease 复制）")
  }
  ctx$data$raw <- data

  voc_cols <- cfg$environment$voc_columns %||% character(0)
  if (!length(voc_cols)) {
    env_pat <- cfg$environment$voc_col_pattern %||% "^URX"
    voc_cols <- grep(env_pat, names(data), value = TRUE)
  }
  voc_cols <- intersect(as.character(voc_cols), names(data))

  if (!is.null(cfg$data$outcome_path) && nzchar(cfg$data$outcome_path %||% "")) {
    outcome_data <- load_rawdata(cfg$data$outcome_path)
    data <- merge(data, outcome_data, by = id_col)
    cli::cli_alert_info("Merged outcome file: now {nrow(data)} rows")
  }

  indices <- cfg$computed_indices
  if (!is.null(indices) || length(indices) == 0) {
    if (isTRUE(indices$enable)) {
      indices_list <- indices$indices %||% list()
      cli::cli_h2("Computing derived indices")
      for (idx in indices_list) {
        tryCatch({
          data[[idx$name]] <- with(data, eval(parse(text = idx$formula)))
          cli::cli_alert_success("Computed: {idx$name}")
        }, error = function(e) {
          cli::cli_alert_warning("Failed to compute {idx$name}: {e$message}")
        })
      }
    } else {
      cli::cli_alert_info("Derived indices computation disabled (enable = FALSE)")
    }
  }

  if (outcome_col %in% names(data)) {
    vals <- na.omit(unique(data[[outcome_col]]))
    cli::cli_alert_info("Outcome '{outcome_col}' values: {paste(vals, collapse = ', ')}")
    # 预后研究：若 outcome_column 即 survival$event_var，保持 0/1 数值供 Cox/LASSO，不做病例标签化
    study_type <- tolower(trimws(as.character(cfg$project$study_type %||% "")[1L]))
    ev_col <- as.character((cfg$survival %||% list())$event_var %||% "")[1L]
    keep_numeric_event <- identical(study_type, "prognosis") &&
      nzchar(ev_col) && identical(outcome_col, ev_col)
    if (!keep_numeric_event) {
      if (exists("pipeline_relabel_binary_outcome_column", mode = "function")) {
        data <- pipeline_relabel_binary_outcome_column(data, cfg, col = outcome_col)
      } else if (is.numeric(data[[outcome_col]]) && all(vals %in% c(0, 1))) {
        data[[outcome_col]] <- ifelse(data[[outcome_col]] == 1, analysis_grp, reference_grp)
        cli::cli_alert_info("Converted 0/1 -> '{reference_grp}'/'{analysis_grp}'")
      }
    } else {
      cli::cli_alert_info(
        "prognosis: 保留数值结局列 {outcome_col}（= survival$event_var）为 0/1，跳过标签化"
      )
    }
  }

  row_filter <- cfg$data_clean$age_filter
  if (!is.null(row_filter) && nzchar(row_filter %||% "")) {
    n_before <- nrow(data)
    if (exists("attrition_record", mode = "function") &&
        !any(vapply(
          ((ctx$results$attrition %||% list())$log %||% list()),
          function(e) identical(as.character(e$step_id %||% "")[1L], "starting_cohort"),
          logical(1L)
        ))) {
      ctx <- attrition_record(
        ctx, "starting_cohort", "Starting cohort",
        as.integer(n_before), meta = list(block = "data_clean", source = "pre_age_filter")
      )
    }
    data <- data[with(data, eval(parse(text = row_filter))), ]
    n_after_age <- as.integer(nrow(data))
    n_excl_age <- as.integer(n_before - n_after_age)
    cli::cli_alert_info("Row filter '{row_filter}': {n_before} -> {n_after_age} rows")
    if (exists("attrition_record", mode = "function")) {
      age_lab <- if (grepl("Age\\s*>=\\s*50", row_filter, ignore.case = TRUE, perl = TRUE)) {
        sprintf("Age \u2265 50 (excluded Age < 50: %s)", format(n_excl_age, big.mark = ","))
      } else if (grepl("Age\\s*>=\\s*40", row_filter, ignore.case = TRUE, perl = TRUE)) {
        sprintf("Age \u2265 40 (excluded Age < 40: %s)", format(n_excl_age, big.mark = ","))
      } else {
        sprintf("Age filter (%s; excluded %s)", row_filter, format(n_excl_age, big.mark = ","))
      }
      ctx <- attrition_record(
        ctx, "after_age_filter", age_lab, n_after_age,
        meta = list(
          block = "data_clean", n_before = as.integer(n_before),
          n_excluded = n_excl_age, filter = as.character(row_filter)[1L]
        )
      )
    }
  }

  if (exists("pipeline_data_clean_apply_implausible_ranges", mode = "function")) {
    data <- pipeline_data_clean_apply_implausible_ranges(data, cfg)
  }

  ## 按行缺失率删人（共享层也会执行；列阈在共享层常被强制为 1.0，不删列）
  row_miss_thr <- suppressWarnings(as.numeric(cfg$data_clean$row_missing_threshold %||% NA_real_)[1L])
  if (is.finite(row_miss_thr) && row_miss_thr >= 0 && row_miss_thr < 1) {
    score_cols <- as.character(cfg$data_clean$row_missing_vars %||% character(0))
    score_cols <- score_cols[nzchar(score_cols)]
    if (!length(score_cols)) {
      score_cols <- names(data)[vapply(data, is.numeric, logical(1L))]
    }
    score_cols <- setdiff(
      intersect(score_cols, names(data)),
      unique(c(id_col, outcome_col, "Disease_Group", "Disease", "Group"))
    )
    if (length(score_cols) >= 2L) {
      n_before <- nrow(data)
      miss_row <- rowMeans(is.na(data[, score_cols, drop = FALSE]))
      keep_rows <- which(is.finite(miss_row) & miss_row <= row_miss_thr)
      data <- data[keep_rows, , drop = FALSE]
      cli::cli_alert_info(
        "Row missing filter (threshold={row_miss_thr}, vars={length(score_cols)}): {n_before} -> {nrow(data)} rows (dropped {n_before - nrow(data)})"
      )
    } else {
      cli::cli_alert_warning(
        "row_missing_threshold={row_miss_thr} 已配置，但可用评分列 < 2，跳过行缺失过滤"
      )
    }
  }

  drop_cols <- cfg$data_clean$drop_columns
  if (!is.null(drop_cols) && length(drop_cols) > 0) {
    to_drop <- intersect(drop_cols, names(data))
    data <- data[, !names(data) %in% to_drop, drop = FALSE]
    cli::cli_alert_info("Dropped columns: {paste(to_drop, collapse = ', ')}")
  }

  # Inf/NaN/-Inf → NA，避免下游 MICE eigen 失败
  if (exists("pipeline_sanitize_numeric_for_mice", mode = "function")) {
    san <- pipeline_sanitize_numeric_for_mice(data, cfg)
    data <- san$data
    if (san$n_nonfinite > 0L) {
      cli::cli_alert_warning(
        "数值列非有限值 → NA: {san$n_nonfinite} 个单元格"
      )
    }
    if (san$n_pp_filled > 0L) {
      cli::cli_alert_info("SBP/DBP: 由 SBP-DBP 回填 PP {san$n_pp_filled} 行")
    }
  } else {
    num_cols <- names(data)[vapply(data, is.numeric, logical(1L))]
    n_inf <- 0L
    for (col in num_cols) {
      x <- data[[col]]
      bad <- !is.finite(x)
      if (any(bad, na.rm = TRUE)) {
        n_inf <- n_inf + sum(bad, na.rm = TRUE)
        x[bad] <- NA_real_
        data[[col]] <- x
      }
    }
    if (n_inf > 0L) {
      cli::cli_alert_warning("数值列非有限值 → NA: {n_inf} 个单元格")
    }
  }

  never_drop <- unique(c(
    outcome_col,
    id_col,
    as.character(cfg$data_clean$never_drop_columns %||% character(0))
  ))
  never_drop <- intersect(never_drop, names(data))

  cli::cli_h2("Missing value check (threshold = {threshold * 100}% for all columns)")

  lod_sample_col_filter <- isTRUE((cfg$environment_lod %||% list())$sample_column_filter_enable %||% FALSE)
  missing_pct <- colMeans(is.na(data))
  col_threshold <- ifelse(
    names(missing_pct) %in% never_drop,
    1.0,
    ifelse(
      lod_sample_col_filter & (names(missing_pct) %in% voc_cols),
      1.0,
      ifelse(names(missing_pct) %in% voc_cols, env_threshold, threshold)
    )
  )
  if (lod_sample_col_filter && length(voc_cols)) {
    cli::cli_alert_info(
      "data_clean: VOC 列缺失剔除由 environment_lod_screen 样本×列迭代筛查负责，此处跳过"
    )
  }
  missing_df  <- data.frame(
    column      = names(missing_pct),
    missing_n   = colSums(is.na(data)),
    missing_pct = round(missing_pct * 100, 1),
    is_env      = names(missing_pct) %in% voc_cols,
    threshold_pct = round(col_threshold * 100, 1),
    action      = ifelse(missing_pct > col_threshold, "DROPPED", "KEPT"),
    stringsAsFactors = FALSE
  )
  missing_df <- missing_df[order(-missing_df$missing_pct), ]

  dropped_cols <- missing_df$column[missing_df$action == "DROPPED"]
  kept_missing <- missing_df[missing_df$action == "KEPT" & missing_df$missing_pct > 0, ]

  if (length(dropped_cols) > 0) {
    cli::cli_alert_warning("Dropping {length(dropped_cols)} column(s) over missing threshold:")
    for (col in dropped_cols) {
      pct <- missing_df$missing_pct[missing_df$column == col]
      env_tag <- if (missing_df$is_env[missing_df$column == col]) " [env]" else ""
      thr <- missing_df$threshold_pct[missing_df$column == col]
      cli::cli_li("{col}{env_tag}: {pct}% missing (threshold {thr}%)")
    }
    data <- data[, names(missing_pct)[missing_pct <= col_threshold], drop = FALSE]
    voc_cols <- intersect(voc_cols, names(data))
  } else {
    cli::cli_alert_success("No columns exceed missing threshold")
  }

  if (nrow(kept_missing) > 0) {
    cli::cli_alert_info("{nrow(kept_missing)} column(s) kept with partial missing (will be handled by imputation)")
  }

  if (!isTRUE(cfg$data_clean$skip_outcome_row_filter) &&
      outcome_col %in% names(data)) {
    n_before <- nrow(data)
    outcome_vals <- data[[outcome_col]]
    if (is.data.frame(outcome_vals)) outcome_vals <- outcome_vals[[1L]]
    else if (is.matrix(outcome_vals)) outcome_vals <- outcome_vals[, 1L]
    keep_rows <- which(!is.na(outcome_vals))
    data <- data[keep_rows, , drop = FALSE]
    if (nrow(data) < n_before)
      cli::cli_alert_info("Removed {n_before - nrow(data)} rows with missing outcome")
  }

  # 血小板等血细胞单位统一（K/uL）；避免 Platelet med≈0.2 误留
  if (!isTRUE(cfg$data_clean$skip_hematology_scale) &&
      exists("scale_hematology_dataframe", mode = "function")) {
    data <- scale_hematology_dataframe(data, verbose = TRUE)
  }

  cli::cli_alert_success("Cleaned data: {nrow(data)} rows x {ncol(data)} cols")
  cli::cli_alert_info("Outcome distribution:")
  print(table(data[[outcome_col]]))

  ctx$data$cleaned <- data
  if (exists("attrition_record", mode = "function")) {
    ctx <- attrition_record(
      ctx, "after_data_clean", "After data cleaning",
      as.integer(nrow(data)), meta = list(block = "data_clean")
    )
  }
  if (length(voc_cols)) {
    ctx$config$environment <- ctx$config$environment %||% list()
    ctx$config$environment$voc_columns <- voc_cols
    if (exists("environment_patch_voc_exclude", mode = "function")) {
      ctx$config <- environment_patch_voc_exclude(ctx$config, data)
    } else {
      ctx$config$incidence <- ctx$config$incidence %||% list()
      ctx$config$incidence$index_exclude_vars <- voc_cols
    }
  }
  ctx <- save_result(ctx, "missing_summary", missing_df, "data_quality_report.csv")
  ctx
}

register_block("data_clean", block_data_clean,
               "Load raw data, compute indices, filter rows/cols, handle missing values")
