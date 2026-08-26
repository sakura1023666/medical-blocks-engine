#!/usr/bin/env Rscript
# phase_sensitivity.R — 发病敏感性（S8 之后：S9–S17.1）
# 场景：exclude_chronic_ge2 | complete_case | exclude_event_le_2y
# 跳过 competing_risk（无死亡变量；配置占位 competing_risk=FALSE）
# Usage:
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase sensitivity --study-root ...
#   Rscript Blocks/54_cross_lagged_full/phases/phase_sensitivity.R --study-root ... [--only CHARLS] [--scenario exclude_chronic_ge2]

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) return(normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/"))
  normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
root <- {
  if (basename(script_path) == "phases" &&
      grepl("54_cross_lagged", basename(dirname(script_path)), fixed = TRUE))
    normalizePath(file.path(script_path, "..", "..", ".."), winslash = "/")
  else if (basename(script_path) == "cross_lagged" && basename(dirname(script_path)) == "run")
    normalizePath(file.path(script_path, "..", ".."), winslash = "/")
  else if (nzchar(Sys.getenv("MEDICAL_BLOCKS_ROOT", "")))
    normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT"), winslash = "/")
  else
    normalizePath(getwd(), winslash = "/")
}
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
study_root <- Sys.getenv(
  "CROSS_LAGGED_STUDY_ROOT",
  unset = "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747"
)
only_dbs <- NULL
only_scen <- NULL
no_sync <- FALSE
baseline_only <- FALSE
change_only <- FALSE
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--study-root" && i < length(args)) {
    j <- i + 1L; parts <- character(0)
    while (j <= length(args) && !startsWith(args[[j]], "--")) {
      parts <- c(parts, args[[j]]); j <- j + 1L
    }
    study_root <- paste(parts, collapse = " "); i <- j
  } else if (args[[i]] == "--only" && i < length(args)) {
    only_dbs <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
  } else if (args[[i]] == "--scenario" && i < length(args)) {
    only_scen <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
  } else if (args[[i]] %in% c("--no-sync")) {
    no_sync <- TRUE; i <- i + 1L
  } else if (args[[i]] %in% c("--baseline-only")) {
    baseline_only <- TRUE; i <- i + 1L
  } else if (args[[i]] %in% c("--change-only")) {
    change_only <- TRUE; i <- i + 1L
  } else i <- i + 1L
}
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)

suppressPackageStartupMessages({
  if (!requireNamespace("cli", quietly = TRUE)) stop("需要 cli")
})
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/baseline_dictionary_labels.R"), local = FALSE)
source(file.path(root, "R/cross_lagged_table1_harmonize.R"), local = FALSE)
source(file.path(root, "R/cross_lagged_covariate_lock.R"), local = FALSE)
source(file.path(root, "R/cross_lagged_study_meta.R"), local = FALSE)
source(file.path(root, "R/cross_lagged_sensitivity.R"), local = FALSE)
if (file.exists(file.path(root, "R/sci_xlsx_utils.R")))
  source(file.path(root, "R/sci_xlsx_utils.R"), local = FALSE)
if (file.exists(file.path(root, "R/model3_required.R")))
  source(file.path(root, "R/model3_required.R"), local = FALSE)
if (file.exists(file.path(root, "R/logistic_gate.R")))
  source(file.path(root, "R/logistic_gate.R"), local = FALSE)
# blocks（register 可空）
register_block <- function(...) invisible(NULL)
source(file.path(root, "Blocks/04_baseline/01block_baseline_binary.R"), local = FALSE)
# logistic 依赖 common
if (file.exists(file.path(root, "Blocks/11_logistic/00logistic_nhanes_weighted_common.R")))
  source(file.path(root, "Blocks/11_logistic/00logistic_nhanes_weighted_common.R"), local = FALSE)
if (file.exists(file.path(root, "Blocks/11_logistic/00logistic_glm_common.R")))
  source(file.path(root, "Blocks/11_logistic/00logistic_glm_common.R"), local = FALSE)
source(file.path(root, "Blocks/11_logistic/05block_logistic_tertile_glm.R"), local = FALSE)
source(file.path(root, "Blocks/11_logistic/01block_logistic_quartile_glm.R"), local = FALSE)
source(file.path(root, "Blocks/54_cross_lagged_full/20block_cross_lagged_change_logistic.R"), local = FALSE)

.meta <- cross_lagged_study_meta(study_root)
.is_dementia <- identical(.meta$kind, "dementia")
.is_circadian <- identical(.meta$kind, "circadian")

options(warn = 1, cli.hyperlink = FALSE)
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
}

.lock <- cross_lagged_sens_read_lock(study_root)
.M1 <- .lock$model1
.M2 <- .lock$model2
cli::cli_h1(paste0(
  "敏感性分析 [", .meta$disease_display, "/", .meta$index_display, "/", .meta$grouping,
  "] — Model1=", paste(.M1, collapse = "+"),
  " | Model2=", paste(.M2, collapse = "+")
))

.cohorts <- .meta$cohorts_xs
.cohorts_long <- .meta$cohorts_long
.validation_cohorts <- if (.is_circadian) cross_lagged_validation_cohorts(.meta) else character(0)
.sens_xs_cohorts <- if (length(.validation_cohorts)) setdiff(.cohorts, .validation_cohorts) else .cohorts
if (!is.null(only_dbs) && length(only_dbs)) {
  .cohorts <- intersect(.cohorts, only_dbs)
  .cohorts_long <- intersect(.cohorts_long, only_dbs)
  .validation_cohorts <- intersect(.validation_cohorts, only_dbs)
  .sens_xs_cohorts <- intersect(.sens_xs_cohorts, only_dbs)
}
.scenarios <- c("exclude_chronic_ge2", "complete_case", "exclude_event_le_2y")
if (.is_circadian && length(.validation_cohorts)) {
  .scenarios <- c(.scenarios, "external_validation")
}
if (!is.null(only_scen) && length(only_scen)) .scenarios <- intersect(.scenarios, only_scen)

.sens_cfg <- list(
  competing_risk = FALSE,
  chronic_min_count = 2L,
  chronic_stems = cross_lagged_sens_default_chronic_stems(),
  exclude_event_within_years = 2L
)

.out_root <- file.path(study_root, "sensitivity")
.summary_tab <- file.path(study_root, "summary_result", "table")
dir.create(.out_root, recursive = TRUE, showWarnings = FALSE)
dir.create(.summary_tab, recursive = TRUE, showWarnings = FALSE)

.make_base_config <- function(db, out_dir, scenario_tag) {
  idx_disp <- if (.is_dementia) .meta$index_display else if (.is_circadian) "ePWV" else "Frailty Index"
  grp <- as.character(.meta$grouping %||% "tertile")[1L]
  cfg <- list(
    project = list(
      name = paste0(.meta$project_prefix, db),
      disease_code = .meta$disease_code,
      disease = .meta$disease,
      database = db,
      database_type = "regular",
      study_type = "incidence",
      classification_mode = "binary",
      analysis_group = .meta$analysis_group,
      reference_group = .meta$reference_group,
      output_dir = out_dir
    ),
    data = list(outcome_column = "Disease_Group", id_column = "ID"),
    incidence = list(
      outcome_var = "Disease_Group",
      index_var = .meta$index_var,
      index_var_display_name = idx_disp,
      model2_max_covariates = 9999L
    ),
    logistic = list(
      index_var = .meta$index_var,
      index_var_display_name = idx_disp,
      model2_max_covariates = 9999L
    ),
    prediction = list(
      index_vars = .meta$index_var,
      keep_index_vars_in_regression_table = TRUE
    ),
    cross_lagged = list(table1_harmonize = isTRUE(.meta$table1_harmonize)),
    baseline_binary = list(
      strata = "Disease_Group",
      sig_cutoff = 0.05,
      pause_enable = FALSE,
      pause_on_table1_fail = FALSE,
      pause_on_min_sig_vars = FALSE,
      use_cross_lagged_table1_harmonized = isTRUE(.meta$table1_harmonize),
      table_kind = "supp_table",
      export_train_val_baseline = FALSE
    ),
    logistic_tertile_glm = list(
      pause_enable = FALSE,
      pause_on_search_fail = FALSE,
      gate_enable = FALSE,
      force_export = TRUE,
      index_var = .meta$index_var,
      tertile_right = isTRUE(.meta$tertile_right %||% TRUE),
      tertile_labels = if (length(.meta$grouping_labels) == 3L) .meta$grouping_labels else c("Q1", "Q2", "Q3"),
      model1_factors = .M1,
      model2_factors = .M2,
      random_search = list(enable = FALSE),
      table_filename = NULL
    ),
    logistic_quartile_glm = list(
      pause_enable = FALSE,
      pause_on_search_fail = FALSE,
      gate_enable = FALSE,
      force_export = TRUE,
      index_var = .meta$index_var,
      model1_factors = .M1,
      model2_factors = .M2,
      random_search = list(enable = FALSE),
      table_filename = NULL
    ),
    logistic_covariates = list(
      model1_factors = .M1,
      model2_factors = .M2,
      random_search = list(enable = FALSE)
    ),
    covariate_policy = list(
      force_age = "Age" %in% .M2 || "Age" %in% .M1,
      force_sex = any(c("Gender", "Sex") %in% .M2),
      force_sex_to_model1 = FALSE
    )
  )
  cfg$.sens_grouping <- grp
  if (isTRUE(.meta$table1_harmonize) &&
      exists("cross_lagged_apply_table1_harmonized", mode = "function")) {
    cfg <- tryCatch(cross_lagged_apply_table1_harmonized(cfg), error = function(e) cfg)
  }
  if (isTRUE(.is_circadian)) {
    common_f <- file.path(study_root, "config_phase1_common.R")
    if (file.exists(common_f)) {
      e <- new.env(parent = baseenv())
      e$`%||%` <- `%||%`
      tryCatch(sys.source(common_f, envir = e), error = function(err) NULL)
      if (exists(".CIRCADIAN_TABLE1_INCLUDE", envir = e, inherits = FALSE)) {
        cfg$baseline_binary$include_vars <- get(".CIRCADIAN_TABLE1_INCLUDE", envir = e)
      }
      if (exists(".CIRCADIAN_TABLE1_EXCLUDE", envir = e, inherits = FALSE)) {
        cfg$baseline_binary$exclude_vars <- get(".CIRCADIAN_TABLE1_EXCLUDE", envir = e)
      }
      if (exists(".CIRCADIAN_TABLE1_LABELS", envir = e, inherits = FALSE)) {
        cfg$baseline_binary$table1_label_overrides <- get(".CIRCADIAN_TABLE1_LABELS", envir = e)
      }
      cfg$baseline_binary$table1_append_units_from_dictionary <- FALSE
    }
  }
  if (isTRUE(.is_dementia)) {
    # 与交付 Table 1-*. Baseline characteristics of Dementia Before PSM 变量对齐
    # （含暴露指标 Leisure_activities；缺列的库由 baseline_binary 自动跳过）
    .t1_vars <- c(
      "Age", "Gender", "Education", "Marital_status",
      "Hypertension", "Diabetes", "Cancer",
      "Height", "Weight", "BMI",
      "Alcohol_drinking", "Smoken",
      "Leisure_activities"
    )
    .t1_labs <- list(
      Age = "Age",
      Gender = "Gender",
      Education = "Education",
      Marital_status = "Marital status",
      Hypertension = "Hypertension",
      Diabetes = "Diabetes",
      Cancer = "Cancer",
      Height = "Height",
      Weight = "Weight",
      BMI = "BMI",
      Alcohol_drinking = "Alcohol drinking",
      Smoken = "Smoken",
      Leisure_activities = "Leisure activities"
    )
    cfg$baseline_binary$include_vars <- .t1_vars
    cfg$baseline_binary$table1_label_overrides <- .t1_labs
    cfg$baseline_binary$table1_append_units_from_dictionary <- FALSE
    cfg$incidence$index_var_display_name <- "Leisure activities"
    cfg$logistic$index_var_display_name <- "Leisure activities"
  }
  cfg
}

.init_ctx <- function(config, data_df, m1, m2) {
  out_dir <- config$project$output_dir
  tab <- file.path(out_dir, "Tables")
  fig <- file.path(out_dir, "Figures")
  dir.create(tab, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig, recursive = TRUE, showWarnings = FALSE)
  list(
    config = config,
    data = list(imputed = data_df, cleaned = data_df, raw = data_df),
    results = list(
      Model1Factors = m1,
      Model2Factors = m2,
      vif_final_pass = m2
    ),
    output_dir_tables = tab,
    output_dir_figures = fig,
    current_block = NULL
  )
}

.copy_to_summary <- function(src, dest_name) {
  if (!file.exists(src)) return(invisible(FALSE))
  # 先把源表内标题对齐文件名，再拷到 summary（两边一致）
  if (exists("cross_lagged_sens_relabel_xlsx_title", mode = "function")) {
    tryCatch(cross_lagged_sens_relabel_xlsx_title(src), error = function(e) NULL)
  }
  dest <- file.path(.summary_tab, dest_name)
  file.copy(src, dest, overwrite = TRUE)
  if (exists("cross_lagged_sens_relabel_xlsx_title", mode = "function")) {
    tryCatch(cross_lagged_sens_relabel_xlsx_title(dest), error = function(e) NULL)
  }
  cli::cli_alert_success("summary ← {dest_name}")
  invisible(TRUE)
}

.run_baseline_logistic <- function(scenario, db, data_df, filter_note, n_before = NULL) {
  out_dir <- file.path(.out_root, scenario, db)
  if (is.null(n_before)) n_before <- nrow(data_df)
  cfg <- .make_base_config(db, out_dir, scenario)
  base_name <- cross_lagged_sens_table_basename(
    scenario, "baseline", db,
    index_display = .meta$index_display,
    disease_display = .meta$disease_display
  )
  log_name <- cross_lagged_sens_table_basename(
    scenario, "logistic", db,
    index_display = .meta$index_display,
    disease_display = .meta$disease_display,
    grouping = .meta$grouping %||% "tertile"
  )
  use_q <- identical(as.character(.meta$grouping %||% "tertile")[1L], "quartile")
  if (use_q) {
    cfg$logistic_quartile_glm$table_filename <- log_name
  } else {
    cfg$logistic_tertile_glm$table_filename <- log_name
  }
  options(pipeline.database_name = db)

  ctx <- .init_ctx(cfg, data_df, .M1, .M2)
  writeLines(
    c(paste0("scenario=", scenario), paste0("db=", db), filter_note,
      paste0("n_before=", n_before),
      paste0("n_after=", nrow(data_df)),
      paste0("n_excluded=", as.integer(n_before) - nrow(data_df)),
      paste0("n=", nrow(data_df)),
      paste0("Model1=", paste(.M1, collapse = "+")),
      paste0("Model2=", paste(.M2, collapse = "+")),
      if (identical(scenario, "complete_case")) {
        "definition=unimputed dabiao + listwise complete.cases(index+outcome+Model2); Change keeps these IDs"
      } else {
        character(0)
      },
      paste0("time=", format(Sys.time(), "%F %T"))),
    file.path(out_dir, "FILTER_NOTE.txt")
  )

  cli::cli_h2("{scenario} / {db} — Table 1 (n={nrow(data_df)})")
  ctx <- tryCatch(block_baseline_binary(ctx), error = function(e) {
    cli::cli_alert_warning("baseline_binary 失败: {e$message}")
    ctx
  })
  if (exists("flush_pub_output_queues", mode = "function")) {
    ctx <- tryCatch(flush_pub_output_queues(ctx), error = function(e) ctx)
  }
  # 提升为固定 S 编号
  t1_dest <- file.path(ctx$output_dir_tables, base_name)
  if (!cross_lagged_sens_promote_table1(ctx$output_dir_tables, t1_dest)) {
    cli::cli_alert_warning("未找到 Table 1 产出，跳过 promote")
  } else {
    .copy_to_summary(t1_dest, base_name)
  }

  if (isTRUE(baseline_only)) return(invisible(TRUE))

  use_q <- identical(as.character(.meta$grouping %||% "tertile")[1L], "quartile")
  if (use_q) {
    cli::cli_h2("{scenario} / {db} — logistic quartile")
    ctx$current_block <- "logistic_quartile_glm"
    ctx <- tryCatch(block_logistic_quartile_glm(ctx), error = function(e) {
      cli::cli_alert_warning("logistic_quartile_glm 失败: {e$message}")
      ctx
    })
  } else {
    cli::cli_h2("{scenario} / {db} — logistic tertile")
    ctx$current_block <- "logistic_tertile_glm"
    ctx <- tryCatch(block_logistic_tertile_glm(ctx), error = function(e) {
      cli::cli_alert_warning("logistic_tertile_glm 失败: {e$message}")
      ctx
    })
  }
  if (exists("flush_pub_output_queues", mode = "function")) {
    ctx <- tryCatch(flush_pub_output_queues(ctx), error = function(e) ctx)
  }
  log_src <- file.path(ctx$output_dir_tables, log_name)
  # export 可能截断文件名；兜底搜索后拷到固定 S 编号
  if (!file.exists(log_src)) {
    hits <- list.files(
      ctx$output_dir_tables,
      pattern = "tertile.*GLM.*\\.xlsx$|quartile.*GLM.*\\.xlsx$|Sensitivity.*Logistic.*\\.xlsx$",
      full.names = TRUE, ignore.case = TRUE
    )
    if (!length(hits)) {
      hits <- list.files(ctx$output_dir_tables, pattern = "Sensitivity.*\\.xlsx$", full.names = TRUE)
      hits <- hits[!grepl("Normality|Baseline characteristics|Change analysis",
                          basename(hits), ignore.case = TRUE)]
    }
    if (length(hits)) {
      hits <- hits[order(file.info(hits)$mtime, decreasing = TRUE)]
      file.copy(hits[[1]], log_src, overwrite = TRUE)
    }
  }
  if (file.exists(log_src)) {
    if (exists("cross_lagged_sens_relabel_xlsx_title", mode = "function")) {
      tryCatch(cross_lagged_sens_relabel_xlsx_title(log_src), error = function(e) NULL)
    }
    .copy_to_summary(log_src, log_name)
  }
  invisible(TRUE)
}

.run_change_for_scenario <- function(scenario, id_keep_by_db) {
  # 每库过滤 long/wide → change block → 收集 rds → build S11/S14/S17
  rds_auto <- character(0)
  rds_two <- character(0)
  cohorts_ok <- character(0)
  for (db in .cohorts_long) {
    long_pack <- tryCatch(cross_lagged_sens_load_long(study_root, db), error = function(e) {
      cli::cli_alert_warning("{db} long 加载失败: {e$message}"); NULL
    })
    if (is.null(long_pack) || is.null(long_pack$wide)) next
    ids_keep <- id_keep_by_db[[db]]
    if (is.null(ids_keep)) next
    w <- long_pack$wide
    if (!"ID" %in% names(w)) {
      cli::cli_alert_warning("{db} wide 无 ID"); next
    }
    w2 <- w[as.character(w$ID) %in% as.character(ids_keep), , drop = FALSE]
    long2 <- long_pack$long_all
    if (!is.null(long2) && "ID" %in% names(long2)) {
      long2 <- long2[as.character(long2$ID) %in% as.character(ids_keep), , drop = FALSE]
    }
    out_dir <- file.path(.out_root, scenario, db)
    cfg <- .make_base_config(db, out_dir, scenario)
    # Dementia：强制 two_wave（three_plus 硬编码 FI）；结局/时间来自 wide2 补齐列
    outcome_t2 <- if (.is_dementia) {
      if ("T2_Disease_Group" %in% names(w2)) "T2_Disease_Group" else "T2_Disease"
    } else {
      "T2_Disease_Group"
    }
    time_col <- if (.is_dementia) {
      if ("T2_time" %in% names(w2)) "T2_time" else "T1_time"
    } else {
      "T2_time"
    }
    # Dementia Change：对齐主分析 C02.3 真实代码（非脚注）
    #   Mean: mean_Index_q3 + T2_Age + T2_Alcohol_drinking
    #   Change: Index_change_q3 不调整
    #   三分位：用 Step05 预计算 *_q3（C01.1 ntile）
    cfg$cross_lagged_change_logistic <- list(
      outcome_event_level = .meta$analysis_group,
      covariates = if (.is_dementia) c("Age", "Alcohol_drinking") else .M2,
      mean_covariates = if (.is_dementia) c("Age", "Alcohol_drinking") else NULL,
      change_covariates = if (.is_dementia) character(0) else NULL,
      covariate_wave = if (.is_dementia) "T2" else "T1",
      scheme = if (.is_dementia) "tertile" else as.character(.meta$grouping %||% "tertile")[1L],
      grouping_method = if (.is_dementia) "ntile" else "quantile",
      use_precomputed_q3 = isTRUE(.is_dementia),
      index_stem = .meta$change_index_stem %||% (if (.is_dementia) "Leisure_activities" else "FI"),
      fi_t1 = .meta$fi_t1,
      fi_t2 = .meta$fi_t2,
      outcome_t2 = outcome_t2,
      time_col = time_col,
      output_suffix = ""
    )
    # Dementia 始终 two_wave（auto + twowave 两次跑都走 pair；避开 three_plus 硬编码 FI）
    if (.is_dementia) cfg$cross_lagged_change_logistic$design <- "two_wave"
    ctx <- .init_ctx(cfg, w2, .M1, .M2)
    ctx$data$longitudinal_wide <- w2
    ctx$data$longitudinal <- long2
    cli::cli_h2("{scenario} / {db} — Change S5-style (n={nrow(w2)})")
    ctx <- tryCatch(block_cross_lagged_change_logistic(ctx), error = function(e) {
      cli::cli_alert_warning("change auto 失败: {e$message}"); ctx
    })
    r_auto <- file.path(out_dir, "Tables", "Table_Change_FI_mean_and_change_pub.rds")
    # twowave（显式 suffix；Dementia 已在上表强制 design=two_wave）
    cfg$cross_lagged_change_logistic$output_suffix <- "_twowave"
    cfg$cross_lagged_change_logistic$design <- "two_wave"
    ctx2 <- .init_ctx(cfg, w2, .M1, .M2)
    ctx2$data$longitudinal_wide <- w2
    ctx2$data$longitudinal <- long2
    ctx2$config$cross_lagged_change_logistic <- cfg$cross_lagged_change_logistic
    ctx2 <- tryCatch(block_cross_lagged_change_logistic(ctx2), error = function(e) {
      cli::cli_alert_warning("change twowave 失败: {e$message}"); ctx2
    })
    r_two <- file.path(out_dir, "Tables", "Table_Change_FI_mean_and_change_twowave_pub.rds")
    if (file.exists(r_auto)) {
      rds_auto <- c(rds_auto, r_auto)
      cohorts_ok <- c(cohorts_ok, db)
    }
    if (file.exists(r_two)) rds_two <- c(rds_two, r_two)
  }
  if (!length(rds_auto) || !exists("cross_lagged_change_build_table_s5", mode = "function")) {
    cli::cli_alert_warning("{scenario}: 无法合并 Change 表")
    return(invisible(NULL))
  }
  # 对齐路径向量到 cohorts
  # builder 期望与 cohorts 等长的路径向量
  cohorts_use <- unique(cohorts_ok)
  paths_auto <- file.path(.out_root, scenario, cohorts_use, "Tables",
                          "Table_Change_FI_mean_and_change_pub.rds")
  paths_two <- file.path(.out_root, scenario, cohorts_use, "Tables",
                         "Table_Change_FI_mean_and_change_twowave_pub.rds")
  out_change <- file.path(
    .out_root, scenario,
    cross_lagged_sens_table_basename(
      scenario, "change",
      index_display = .meta$index_display,
      disease_display = .meta$disease_display,
      change_index_display = .meta$change_index_display %||% .meta$index_display
    )
  )
  out_two <- file.path(
    .out_root, scenario,
    cross_lagged_sens_table_basename(
      scenario, "change_twowave",
      index_display = .meta$index_display,
      disease_display = .meta$disease_display,
      change_index_display = .meta$change_index_display %||% .meta$index_display
    )
  )
  dir.create(dirname(out_change), recursive = TRUE, showWarnings = FALSE)
  tryCatch({
    cross_lagged_change_build_table_s5(
      paths_auto, out_change, cohorts = cohorts_use,
      title = sub("\\.xlsx$", "", basename(out_change))
    )
    .copy_to_summary(out_change, basename(out_change))
  }, error = function(e) cli::cli_alert_warning("build change: {e$message}"))
  tryCatch({
    cross_lagged_change_build_table_s5(
      paths_two, out_two, cohorts = cohorts_use,
      title = sub("\\.xlsx$", "", basename(out_two))
    )
    .copy_to_summary(out_two, basename(out_two))
  }, error = function(e) cli::cli_alert_warning("build change twowave: {e$message}"))
  invisible(TRUE)
}

.sens_early_event <- function(long_all, db) {
  baseline_yr <- NULL
  if (.is_dementia) {
    wy <- cross_lagged_sens_dementia_wave_years(db)
    baseline_yr <- wy$baseline
  }
  cross_lagged_sens_ids_early_event(
    long_all,
    within_years = .sens_cfg$exclude_event_within_years,
    baseline_year = baseline_yr
  )
}

.sens_long_source_note <- function(long_all) {
  if (is.null(long_all) || !nrow(long_all)) return("long_all missing")
  bits <- "D05_long"
  if (!any(c("year", "Year") %in% names(long_all))) bits <- paste(bits, "WARN:no_year", sep = ";")
  if (!any(c("Disease", "Disease01", "Disease_Group") %in% names(long_all)))
    bits <- paste(bits, "WARN:no_Disease", sep = ";")
  bits
}

# ── 主循环 ──────────────────────────────────────────────────────────────────
for (sc in .scenarios) {
  cli::cli_h1("Scenario: {sc}")
  id_keep <- list()
  notes <- list()
  xs_loop <- if (identical(sc, "external_validation")) .validation_cohorts else .sens_xs_cohorts
  if (!length(xs_loop)) {
    cli::cli_alert_info("{sc}: 无横断面队列，跳过")
    next
  }

  for (db in xs_loop) {
    if (identical(sc, "external_validation")) {
      raw <- cross_lagged_sens_load_imputed(study_root, db)
      n_before <- nrow(raw)
      note <- sprintf(
        paste0(
          "external_validation=AfterMI; locked Model1/2 from CHARLS+ELSA VIF screen intersect; ",
          "no NHANES re-screen; n=%s"
        ),
        n_before
      )
      fr <- list(
        data = raw,
        rule = "locked_covariates_no_rescreen",
        n_before = n_before,
        n_after = n_before,
        n_excluded = 0L
      )
    } else if (identical(sc, "complete_case")) {
      # 组 B：插补前 dabiao + 仅对分析变量 listwise；N 允许 < AfterMI
      raw <- cross_lagged_sens_load_dabiao(study_root, db)
      raw <- cross_lagged_sens_attach_index_from_imputed(
        raw, study_root, db, .meta$index_var
      )
      n_before <- nrow(raw)
      n_aftermi <- tryCatch(
        nrow(cross_lagged_sens_load_imputed(study_root, db)),
        error = function(e) NA_integer_
      )
      fr <- cross_lagged_sens_filter_complete_case(raw, .M2, index_var = .meta$index_var)
      note <- sprintf(
        paste0(
          "complete_case=unimputed dabiao + listwise on analysis vars ",
          "(NOT force same-N as AfterMI); rule=%s; vars=%s; ",
          "n_before=%s; n_after=%s; n_excluded=%s; n_AfterMI_ref=%s"
        ),
        fr$rule %||% "listwise_on_analysis_vars_unimputed",
        paste(fr$vars, collapse = ","),
        fr$n_before, fr$n_after, fr$n_excluded, n_aftermi
      )
    } else if (identical(sc, "exclude_chronic_ge2")) {
      raw <- cross_lagged_sens_load_imputed(study_root, db)
      n_before <- nrow(raw)
      fr <- cross_lagged_sens_filter_exclude_chronic(
        raw, stems = .sens_cfg$chronic_stems, min_count = .sens_cfg$chronic_min_count
      )
      note <- sprintf("exclude_chronic cols=%s min=%s; n_before=%s; n %s→%s (excl %s)",
                      paste(fr$comorbid_cols, collapse = ","), fr$min_count, n_before,
                      fr$n_before, fr$n_after, fr$n_excluded)
    } else if (identical(sc, "exclude_event_le_2y")) {
      if (!db %in% .cohorts_long) {
        cli::cli_alert_info("{db}: 无纵向，跳过 exclude_event_le_2y（S15/S16）")
        next
      }
      # 横断面 Table1/logistic：用插补表，但只保留「非两年内发病」ID
      raw <- cross_lagged_sens_load_imputed(study_root, db)
      n_before <- nrow(raw)
      long_pack <- cross_lagged_sens_load_long(study_root, db)
      long_src <- .sens_long_source_note(long_pack$long_all)
      baseline_note <- if (.is_dementia) {
        wy <- cross_lagged_sens_dementia_wave_years(db)
        sprintf("baseline_year=%s fu=%s", wy$baseline, paste(wy$fu, collapse = ","))
      } else {
        "baseline_year=min_year_per_id"
      }
      early <- character(0)
      if (!is.null(long_pack$long_all)) {
        early <- .sens_early_event(long_pack$long_all, db)
      }
      fr <- cross_lagged_sens_filter_exclude_early_event(raw, early)
      note <- sprintf(
        "exclude_event_le_%sy early_ids=%s long_src=%s; %s; n_before=%s; n %s→%s (excl %s)",
        .sens_cfg$exclude_event_within_years, length(early), long_src, baseline_note, n_before,
        fr$n_before, fr$n_after, fr$n_excluded
      )
    } else {
      next
    }
    cli::cli_alert_info("{db}: {note}")
    notes[[db]] <- note
    if (!nrow(fr$data)) {
      cli::cli_alert_warning("{db} / {sc}: 过滤后 n=0，跳过")
      next
    }
    if (!"ID" %in% names(fr$data)) {
      # AfterMI 可能无 ID？检查
      if ("id" %in% names(fr$data)) names(fr$data)[names(fr$data) == "id"] <- "ID"
    }
    id_keep[[db]] <- if ("ID" %in% names(fr$data)) as.character(fr$data$ID) else character(0)
    # 若横断面无 ID，用行名占位并在 change 侧用 long 过滤逻辑另算
    if (!length(id_keep[[db]]) && identical(sc, "exclude_event_le_2y")) {
      long_pack <- cross_lagged_sens_load_long(study_root, db)
      if (!is.null(long_pack$wide) && "ID" %in% names(long_pack$wide)) {
        early <- if (!is.null(long_pack$long_all)) {
          .sens_early_event(long_pack$long_all, db)
        } else character(0)
        id_keep[[db]] <- setdiff(as.character(long_pack$wide$ID), early)
      }
    }
    if (!length(id_keep[[db]]) && "ID" %in% names(fr$data))
      id_keep[[db]] <- as.character(fr$data$ID)

    if (!isTRUE(change_only)) {
      .run_baseline_logistic(sc, db, fr$data, note, n_before = n_before)
    } else {
      # change-only：仍写 FILTER_NOTE，跳过 Table1/logistic
      out_dir <- file.path(.out_root, sc, db)
      dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
      writeLines(
        c(paste0("scenario=", sc), paste0("db=", db), note,
          paste0("n_before=", n_before),
          paste0("n_after=", nrow(fr$data)),
          paste0("n_excluded=", as.integer(n_before) - nrow(fr$data)),
          "mode=change_only",
          paste0("time=", format(Sys.time(), "%F %T"))),
        file.path(out_dir, "FILTER_NOTE.txt")
      )
    }
  }

  if (identical(sc, "complete_case") && length(notes)) {
    cc_dir <- file.path(.out_root, "complete_case")
    dir.create(cc_dir, recursive = TRUE, showWarnings = FALSE)
    writeLines(
      c(
        "definition=unimputed dabiao + listwise complete.cases(index+outcome+Model2); no MI",
        "N may be smaller than AfterMI; do NOT force same-N-as-AfterMI",
        "Change keeps only listwise IDs from dabiao filter",
        paste0("time=", format(Sys.time(), "%F %T")),
        "",
        vapply(names(notes), function(nm) paste0(nm, ": ", notes[[nm]]), character(1))
      ),
      file.path(cc_dir, "COMPLETE_CASE_N.txt")
    )
  }

  if (isTRUE(baseline_only)) next

  if (identical(sc, "external_validation")) next

  # Change：对 chronic / complete_case，用横断面保留 ID；对 early_event 用 long 口径
  if (identical(sc, "exclude_chronic_ge2") || identical(sc, "complete_case")) {
    # 若横断面无 ID，从 long 按同样规则重算 keep
    for (db in .cohorts_long) {
      if (length(id_keep[[db]])) next
      long_pack <- tryCatch(cross_lagged_sens_load_long(study_root, db), error = function(e) NULL)
      if (is.null(long_pack$wide) || !"ID" %in% names(long_pack$wide)) next
      w <- long_pack$wide
      if (identical(sc, "exclude_chronic_ge2")) {
        frw <- cross_lagged_sens_filter_exclude_chronic(
          w, stems = .sens_cfg$chronic_stems, min_count = .sens_cfg$chronic_min_count
        )
        id_keep[[db]] <- as.character(frw$data$ID)
      } else {
        # complete case on T1 index + T1_covars + outcome if present
        need <- c(.meta$fi_t1, paste0("T1_", .M2))
        need <- need[need %in% names(w)]
        ok <- if (length(need)) stats::complete.cases(w[, need, drop = FALSE]) else rep(TRUE, nrow(w))
        id_keep[[db]] <- as.character(w$ID[ok])
      }
    }
  }
  if (identical(sc, "exclude_event_le_2y")) {
    for (db in .cohorts_long) {
      long_pack <- tryCatch(cross_lagged_sens_load_long(study_root, db), error = function(e) NULL)
      if (is.null(long_pack$wide) || is.null(long_pack$long_all)) next
      early <- .sens_early_event(long_pack$long_all, db)
      id_keep[[db]] <- setdiff(as.character(long_pack$wide$ID), early)
    }
  }

  .run_change_for_scenario(sc, id_keep)
}

# README
writeLines(c(
  paste0("time=", format(Sys.time(), "%F %T")),
  paste0("study=", .meta$kind, "/", .meta$index_display, "/", .meta$disease_display),
  paste0("cohorts_xs=", paste(.meta$cohorts_xs, collapse = ",")),
  paste0("cohorts_long=", paste(.meta$cohorts_long, collapse = ",")),
  paste0("logistic_grouping=", .meta$grouping),
  "Sensitivity tables continue after Table S8 (CLPN). Required for every cross-lagged study.",
  "S9–S11.1: exclude baseline chronic comorbidities >=2 (lit-aligned).",
  sprintf(
    paste0(
      "S12–S14.1 (group B): UNIMPUTED dabiao + listwise complete.cases on ",
      "%s+Disease_Group+Model2; no MI; N may be < AfterMI; ",
      "Change keeps listwise IDs only; FILTER_NOTE has n_before/n_after/n_excluded."
    ),
    .meta$index_var
  ),
  "S15–S17.1: exclude incident event within 2 years of baseline survey year (longitudinal cohorts only).",
  if (.is_circadian && length(.validation_cohorts)) {
    paste0(
      "S18–S19: external_validation — ",
      paste(.validation_cohorts, collapse = ","),
      " AfterMI with locked Model2 from CHARLS+ELSA (no re-screen)."
    )
  } else {
    character(0)
  },
  "competing_risk: SKIPPED (no death variable; config placeholder competing_risk=FALSE).",
  paste0("Model1=", paste(.M1, collapse = "+")),
  paste0("Model2=", paste(.M2, collapse = "+")),
  if (.is_dementia) {
    paste0(
      "NOTE: Dementia Change forces design=two_wave (T1/T2 pair; NOT three_plus). ",
      "Change aligns C02.3 actual code: Mean adjusts T2_Age+T2_Alcohol_drinking; ",
      "Change tertile unadjusted; uses Step05 precomputed mean_Index_q3/Index_change_q3. ",
      "wide prep: ID from D05_long wave1 + T2_* from *_wide2. ",
      "early-event: D05_long year+Disease; C00 years HRS 2010; SHARE 2015; CLHLS/ELSA 2008."
    )
  } else {
    character(0)
  }
), file.path(.out_root, "README_sensitivity.txt"))
file.copy(file.path(.out_root, "README_sensitivity.txt"),
          file.path(.summary_tab, "README_sensitivity.txt"), overwrite = TRUE)

cli::cli_alert_success("敏感性分析完成 → {(.out_root)}")
source(file.path(root, "Blocks/54_cross_lagged_full/phases/auto_collect_summary.inc.R"), local = FALSE)
if (!isTRUE(no_sync) && exists("cross_lagged_sync_to_project_disk", mode = "function")) {
  # optional; study already on G
}
invisible(TRUE)
