###############################################################################
#  trajectory_prognosis_batch_runner.R — 轨迹预后多指标并行编排引擎 v1
#
#  架构（三层，仿发病 batch 子进程池派发）：
#
#    共享层（每库各跑一次）：
#      data_clean → column_mapping → index → trajectory_calc_28d_index
#
#    指标层 worker（双库）：
#      阶段1：每库独立跑预后前缀至 VIF final
#      对齐：取两库 Model2Factors 交集 → 按主库单因素 P 选 ≤5 个 JLCM survival 协变量
#      阶段2：两库共用该协变量列表跑 JLCM + 全部图表/表格
#
#    汇总层：由 study_batch_dispatch_unit_workers 自带的状态轮询 + 日志完成。
###############################################################################

source(file.path(getwd(), "R", "study_batch_runner.R"), local = FALSE)
traj_util_path <- file.path(getwd(), "R", "trajectory_survival_utils.R")
if (file.exists(traj_util_path)) source(traj_util_path, local = FALSE)
if (file.exists(file.path(getwd(), "configs/indices/composite_index_vars.R"))) {
  source(file.path(getwd(), "configs/indices/composite_index_vars.R"), local = FALSE)
}

# ── 指标列表解析（与 incidence_batch_resolve_index_vars 相同约定）──────────────
trajectory_batch_resolve_index_vars <- function(config) {
  tb  <- config$trajectory_batch %||% list()
  ivs <- tb$index_vars
  grp <- tb$index_group %||% "dual_safe"
  if (!is.null(ivs) && length(ivs)) return(as.character(ivs))
  all_vars <- get0(".composite_index_vars", inherits = TRUE)
  if (!is.null(all_vars) && length(all_vars)) {
    if (identical(grp, "dual_safe"))
      return(get0(".composite_index_vars_dual_safe", inherits = TRUE) %||% all_vars)
    grp_sym <- switch(grp, A = ".idx_group_A", B = ".idx_group_B",
                      C = ".idx_group_C", D = ".idx_group_D", NULL)
    if (!is.null(grp_sym)) return(get0(grp_sym, inherits = TRUE) %||% all_vars)
    return(all_vars)
  }
  stop("找不到复合指标名单，请先 source configs/indices/composite_index_vars.R", call. = FALSE)
}

# ── 路径工具 ─────────────────────────────────────────────────────────────────

trajectory_batch_shared_ck_dir <- function(config, db) {
  tb   <- config$trajectory_batch %||% list()
  base <- tb$shared_ck_base %||% file.path(
    tb$output_base %||% config$project$output_dir, "checkpoints", "_shared"
  )
  file.path(base, db)
}

trajectory_batch_index_ck_dir <- function(config, ix, db) {
  tb <- config$trajectory_batch %||% list()
  base <- tb$index_ck_base %||% file.path(
    tb$output_base %||% config$project$output_dir, "checkpoints", "by_index"
  )
  file.path(base, ix, db)
}

trajectory_batch_index_output_dir <- function(config, ix) {
  tb <- config$trajectory_batch %||% list()
  file.path(tb$output_base %||% config$project$output_dir, "by_index", ix)
}

# 派发器（study_batch_dispatch_unit_workers）按其自身约定轮询状态的目录，
# 与真实产出目录 by_index/<ix>/ 分开，避免污染发表产出。
trajectory_batch_status_output_dir <- function(config, ix) {
  tb <- config$trajectory_batch %||% list()
  file.path(tb$output_base %||% config$project$output_dir, "by_unit", ix)
}

# ── 共享层：单库跑 data_clean → column_mapping → index → trajectory_calc_28d_index ──

trajectory_batch_run_shared_layer <- function(root, config, db, pipeline_shared, skip_existing = TRUE) {
  ck_dir <- trajectory_batch_shared_ck_dir(config, db)
  if (skip_existing && file.exists(file.path(ck_dir, "trajectory_calc_28d_index.rds"))) {
    cli::cli_alert_info("[{toupper(db)}] 共享层 checkpoint 已存在，跳过（删目录可强制重跑）")
    return(invisible(ck_dir))
  }

  db_cfg <- if (identical(db, "eicu")) config$dual_db$primary else config$dual_db$secondary
  if (is.null(db_cfg)) {
    stop("trajectory_batch_run_shared_layer: config$dual_db$",
         if (identical(db, "eicu")) "primary" else "secondary", " 未配置", call. = FALSE)
  }

  cfg <- config
  cfg$data <- c(config$data)
  cfg$data$rawdata_path <- db_cfg$rawdata_path
  cfg$data$rawdata_obj  <- db_cfg$rawdata_obj %||% cfg$data$rawdata_obj
  cfg$data$id_column    <- db_cfg$id_column   %||% cfg$data$id_column
  cfg$project$database  <- db_cfg$name %||% toupper(db)
  cfg$project$root      <- root

  if (is.null(cfg$trajectory_calc_28d_index)) cfg$trajectory_calc_28d_index <- list()
  cfg$trajectory_calc_28d_index$lab_sources <- db_cfg$lab_sources %||% cfg$trajectory_calc_28d_index$lab_sources
  cfg$trajectory_calc_28d_index$lab_id_column <- db_cfg$lab_id_column %||% cfg$trajectory_calc_28d_index$lab_id_column
  cfg$trajectory_calc_28d_index$db_type <- db_cfg$db_type %||% db
  cfg$trajectory_calc_28d_index$output_dir <- db_cfg$output_subdir %||% cfg$trajectory_calc_28d_index$output_dir

  tb <- config$trajectory_batch %||% list()
  cfg$project$output_dir <- file.path(tb$output_base %||% config$project$output_dir, "_shared", db)

  pl <- pipeline_shared
  pl$checkpoint <- list(enable = TRUE, dir = ck_dir)

  cli::cli_h2("共享层 [{toupper(db)}] — {paste(pl$blocks, collapse = ' -> ')}")
  run_pipeline(root, config = cfg, pipeline = pl)
  invisible(ck_dir)
}

# ── 单指标 config patch：把全量指标 config 收窄成只暴露一个 Index ───────────
#  - survival$index_var / trajectory*$index_vars 全部指向该 Index
#  - multicollinearity$exclude_vars 追加其余 Index_All 成员，避免自相关

trajectory_batch_patch_config_for_index <- function(config, ix) {
  tb      <- config$trajectory_batch %||% list()
  all_ix  <- as.character(tb$index_vars %||% character(0))
  if (!length(all_ix)) all_ix <- trajectory_batch_resolve_index_vars(config)

  cfg <- config
  cfg$survival$index_var <- ix
  # Shared trajectory setup may allow analysis_exclusion to run without an
  # active index. A unit worker always has one, so re-enable transitive
  # component exclusion before UV/VIF/Cox/JLCM covariate selection.
  if (is.null(cfg$analysis_exclusion)) cfg$analysis_exclusion <- list()
  cfg$analysis_exclusion$allow_no_index <- FALSE
  cfg$analysis_exclusion$index_var <- ix
  cfg$analysis_exclusion$current_index_vars <- ix
  if (is.null(cfg$prediction)) cfg$prediction <- list()
  cfg$prediction$index_vars <- c(ix)
  cfg$incidence <- cfg$incidence %||% list()
  cfg$incidence$index_var <- ix

  other_ix <- trajectory_batch_other_index_vars(cfg, ix)

  for (blk in c(
    "trajectory_jlcm", "trajectory_prepare_wide_rdata", "trajectory_plot_jlcm",
    "trajectory_baseline_by_class",
    "trajectory_km_class", "trajectory_piecewise_cox", "trajectory_weibull_compare",
    "trajectory_dynpred_individual", "trajectory_subgroup_class", "trajectory_chisq",
    "trajectory_dynpred"
  )) {
    if (!is.null(cfg[[blk]])) cfg[[blk]]$index_vars <- c(ix)
  }

  # Batch scan: block-level "PAUSE_FOR_USER_DECISION" on empty / all-negative
  # results is meant for interactive single-index runs. In a full-index sweep a
  # given trajectory may legitimately be non-informative; aborting the worker
  # then loses the code bundle and downstream figures and mislabels it failed.
  # Disable those pauses for batch workers only (engine defaults untouched).
  .pause_keys <- c(
    "pause_enable", "pause_on_no_output", "pause_on_missing_survival",
    "pause_on_all_negative", "pause_on_min_sig_vars", "pause_enable_if_index_ns",
    "pause_on_no_output_after", "pause_on_all_ns"
  )
  for (blk in ls(cfg)[grepl("^trajectory", ls(cfg))]) {
    node <- cfg[[blk]]
    if (is.list(node)) {
      # Set unconditionally: block helpers default missing pause keys to TRUE.
      for (k in .pause_keys) node[[k]] <- FALSE
      cfg[[blk]] <- node
    }
  }
  if (!is.null(cfg$trajectory)) cfg$trajectory$index_vars <- c(ix)
  else {
    cfg$trajectory <- list(
      index_vars = c(ix),
      class_for_test = cfg$trajectory_chisq$class_for_test %||% NULL,
      use_optimal_class_ng = cfg$trajectory_chisq$use_optimal_class_ng %||% TRUE,
      outcome_vars = cfg$trajectory_chisq$outcome_vars %||% c("survival_28d"),
      p_threshold = cfg$trajectory_chisq$p_threshold %||% 1.0,
      pause_on_all_ns = cfg$trajectory_chisq$pause_on_all_ns %||% TRUE,
      cycle = cfg$trajectory_dynpred$cycle %||% 28L,
      jlcm = cfg$trajectory_dynpred$jlcm %||% list(prefer_ng = NULL)
    )
  }

  if (is.null(cfg$multicollinearity)) cfg$multicollinearity <- list()
  cfg$multicollinearity$exclude_vars <- unique(c(
    as.character(cfg$multicollinearity$exclude_vars %||% character(0)), other_ix
  ))

  # Table 1 / 插补表 / UV / MV：仅保留当前暴露指标，排除其它复合指标 + 潜类别列
  # 潜类别列名在数据写出后才确定，这里预置裸名；block 内再按 ^trajectory_class 兜底剔除
  traj_class_excl <- c("trajectory_class", paste0("trajectory_class_", ix))
  for (blk in c("baseline_binary", "baseline_multiclass")) {
    if (is.null(cfg[[blk]])) cfg[[blk]] <- list()
    cfg[[blk]]$exclude_vars <- unique(c(
      as.character(cfg[[blk]]$exclude_vars %||% character(0)), other_ix, traj_class_excl
    ))
  }
  if (is.null(cfg$imputation)) cfg$imputation <- list()
  # 插补表：排除其它复合指标，但保留当前暴露 ix
  s1_excl <- as.character(cfg$imputation$table_s1_exclude_vars %||% character(0))
  cfg$imputation$table_s1_exclude_vars <- unique(c(
    setdiff(s1_excl, ix), other_ix, traj_class_excl
  ))
  if (is.null(cfg$univariate_prognosis)) cfg$univariate_prognosis <- list()
  cfg$univariate_prognosis$excluded_predictors <- unique(c(
    as.character(cfg$univariate_prognosis$excluded_predictors %||% character(0)),
    other_ix, traj_class_excl
  ))
  if (is.null(cfg$multivariate_prognosis)) cfg$multivariate_prognosis <- list()
  cfg$multivariate_prognosis$excluded_predictors <- unique(c(
    as.character(cfg$multivariate_prognosis$excluded_predictors %||% character(0)),
    other_ix, traj_class_excl
  ))
  cfg$multicollinearity$exclude_vars <- unique(c(
    as.character(cfg$multicollinearity$exclude_vars %||% character(0)),
    traj_class_excl
  ))
  if (exists("pipeline_apply_index_exclude_patch", mode = "function")) {
    cfg <- pipeline_apply_index_exclude_patch(cfg)
  }

  # 按类基线表默认与 Table 1 变量一致
  if (is.null(cfg$trajectory_baseline_by_class)) cfg$trajectory_baseline_by_class <- list()
  if (is.null(cfg$trajectory_baseline_by_class$vars_from)) {
    cfg$trajectory_baseline_by_class$vars_from <- "table1"
  }

  # 每个 by_index 单元：仅计算/保留当前暴露指标（宽表 day1 合并 + index block）
  cfg$index$only <- c(ix)
  cfg$imputation$force_keep_columns <- c(ix)
  # 多因素不显著不早停（显式强制，避免被 trajectory_batch$fail_on_index_ns 语义混淆）
  if (!is.null(cfg$multivariate_prognosis)) {
    cfg$multivariate_prognosis$fail_on_index_ns <- FALSE
    cfg$multivariate_prognosis$pause_enable <- FALSE
  }
  fail_on_ix_ns <- isTRUE((tb$fail_on_index_ns %||% config$trajectory_batch$fail_on_index_ns %||% FALSE))
  if (!fail_on_ix_ns) {
    cfg$univariate_prognosis$required_predictors <- c(ix)
    cfg$multivariate_prognosis$required_predictors <- c(ix)
  }
  mice_excl <- as.character(cfg$imputation$exclude_from_mice_cols %||% character(0))
  cfg$imputation$exclude_from_mice_cols <- unique(c(
    setdiff(mice_excl, c(.composite_index_vars_trajectory_apri, other_ix, ix)),
    ix
  ))

  cfg$project$output_dir <- trajectory_batch_index_output_dir(config, ix)
  cfg
}

trajectory_batch_enforce_index_min_n <- function(config, ix) {
  tb <- config$trajectory_batch %||% list()
  bl <- config$trajectory_calc_28d_index %||% list()
  min_n_ix <- suppressWarnings(as.integer(bl$min_n_after_index %||% bl$min_n %||% tb$min_n_after_index %||% 0L)[1L])
  if (!is.finite(min_n_ix) || min_n_ix <= 0L) return(invisible(NULL))
  db_seq <- as.character(tb$db_seq %||% c("mimic"))
  for (db in db_seq) {
    shared_ck <- trajectory_batch_shared_ck_dir(config, db)
    ctx <- tryCatch(
      study_batch_load_checkpoint_ctx(shared_ck, "trajectory_calc_28d_index"),
      error = function(e) NULL
    )
    if (is.null(ctx)) next
    ix_info <- (ctx$results$trajectory_28d_index %||% list())[[ix]]
    n_ix <- as.integer(ix_info$n %||% 0L)
    if (n_ix <= min_n_ix) {
      stop(
        "INDEX_MIN_N_STOP: 指标 ", ix, "（", toupper(db), "）合并纵向宽表后样本量 ", n_ix,
        " ≤ 阈值 ", min_n_ix, "，终止该指标 pipeline。",
        call. = FALSE
      )
    }
  }
  invisible(NULL)
}

# ── 单指标 × 单库：从共享 checkpoint 续跑完整"预后前缀 + 轨迹"链条 ──────────

trajectory_batch_run_index_db <- function(root, config_ix, ix, db, pipeline_unit,
                                          shared_jlcm_covariates = NULL,
                                          resume_from_block = NULL) {
  cfg_db <- config_ix
  if (length(shared_jlcm_covariates)) {
    if (is.null(cfg_db$trajectory_jlcm)) cfg_db$trajectory_jlcm <- list()
    cfg_db$trajectory_jlcm$covariate_vars <- as.character(shared_jlcm_covariates)
    cfg_db$trajectory_jlcm$covariate_vars_from_vif <- FALSE
    cfg_db$trajectory_jlcm$dual_db_shared_covariates <- TRUE
  }

  if (!is.null(resume_from_block) && nzchar(as.character(resume_from_block)[1L])) {
    ck_dir <- trajectory_batch_index_ck_dir(config_ix, ix, db)
    ctx <- study_batch_load_checkpoint_ctx(ck_dir, as.character(resume_from_block)[1L])
    db_cfg <- if (identical(db, "eicu")) config_ix$dual_db$primary else config_ix$dual_db$secondary
    cfg_db$project$database   <- db_cfg$name %||% toupper(db)
    cfg_db$project$output_dir <- file.path(config_ix$project$output_dir, db)
    if (!is.null(cfg_db$trajectory_jlcm$rawdata_path_template)) {
      cfg_db$trajectory_jlcm$rawdata_path_template <- gsub(
        "\\{db\\}", db, cfg_db$trajectory_jlcm$rawdata_path_template
      )
    }
    ctx$config <- cfg_db
    ctx$root_output_dir <- cfg_db$project$output_dir
    pl <- pipeline_unit
    pl$checkpoint <- list(enable = TRUE, dir = ck_dir)
    return(run_pipeline(root, config = cfg_db, pipeline = pl, run_opts = list(initial_ctx = ctx)))
  }

  shared_ck <- trajectory_batch_shared_ck_dir(config_ix, db)
  ctx <- tryCatch(
    study_batch_load_checkpoint_ctx(shared_ck, "trajectory_calc_28d_index"),
    error = function(e) {
      cli::cli_alert_danger("[{ix}/{toupper(db)}] 无法加载共享 checkpoint: {conditionMessage(e)}")
      NULL
    }
  )
  if (is.null(ctx)) return(NULL)

  db_cfg <- if (identical(db, "eicu")) config_ix$dual_db$primary else config_ix$dual_db$secondary
  cfg_db <- config_ix
  cfg_db$project$database   <- db_cfg$name %||% toupper(db)
  cfg_db$project$output_dir <- file.path(config_ix$project$output_dir, db)
  # 每指标宽表 RData 路径模板支持 {db} 占位（如 Data/{db}/12_{Index}.RData）
  if (!is.null(cfg_db$trajectory_jlcm$rawdata_path_template)) {
    cfg_db$trajectory_jlcm$rawdata_path_template <- gsub(
      "\\{db\\}", db, cfg_db$trajectory_jlcm$rawdata_path_template
    )
  }
  ctx$config <- cfg_db
  ctx$root_output_dir <- cfg_db$project$output_dir

  traj_util <- file.path(root, "R/trajectory_survival_utils.R")
  if (file.exists(traj_util)) {
    source(traj_util, local = FALSE)
    id_col <- cfg_db$data$id_column %||% "subject_id"
    wide_tpl <- cfg_db$trajectory_jlcm$rawdata_path_template %||% NULL
    wide_path <- if (!is.null(wide_tpl)) gsub("\\{Index\\}", ix, gsub("\\{db\\}", db, wide_tpl)) else NULL
    for (slot in c("cleaned", "mapped", "imputed")) {
      if (is.null(ctx$data[[slot]])) next
      d <- ctx$data[[slot]]
      if (exists("trajectory_coerce_vital_numeric", mode = "function"))
        d <- trajectory_coerce_vital_numeric(d)
      if (!is.null(wide_path) && exists("trajectory_merge_wide_baseline_index", mode = "function"))
        d <- trajectory_merge_wide_baseline_index(d, wide_path, ix, id_col, day = 1L)
      if (exists("trajectory_filter_to_index_cohort", mode = "function"))
        d <- trajectory_filter_to_index_cohort(d, ix, id_col)
      ctx$data[[slot]] <- d
    }
    if (exists("trajectory_apply_index_cohort_to_ctx", mode = "function")) {
      ctx <- trajectory_apply_index_cohort_to_ctx(ctx, ix, id_col)
    }
  }

  pl <- pipeline_unit
  pl$checkpoint <- list(enable = TRUE, dir = trajectory_batch_index_ck_dir(config_ix, ix, db))

  run_pipeline(root, config = cfg_db, pipeline = pl, run_opts = list(initial_ctx = ctx))
}

# ── by_index / by_unit 打标：【success】<ix> / 【failed】<ix>（与发病 batch 一致）──

trajectory_batch_rename_unit_folders <- function(config, ix, status) {
  tb <- config$trajectory_batch %||% list()
  output_base <- tb$output_base %||% config$project$output_dir
  label_status <- if (identical(as.character(status), "success")) "success" else "failed"
  new_name <- incidence_batch_output_dir_name(ix, label_status)

  for (subdir in c("by_index", "by_unit")) {
    old_path <- file.path(output_base, subdir, ix)
    if (!dir.exists(old_path)) next
    new_path <- file.path(output_base, subdir, new_name)
    if (dir.exists(new_path)) next
    ok <- tryCatch({ file.rename(old_path, new_path); TRUE }, error = function(e) {
      cli::cli_alert_warning("重命名失败 {subdir}/{ix}: {e$message}")
      FALSE
    })
    if (ok) cli::cli_alert_info("  📁 {subdir}/{ix} → {new_name}")
  }
  invisible(new_name)
}

trajectory_batch_read_all_status <- function(config, index_vars) {
  tb <- config$trajectory_batch %||% list()
  output_base <- tb$output_base %||% config$project$output_dir
  study_batch_read_all_status(output_base, index_vars)
}

trajectory_batch_write_summary <- function(config, index_vars) {
  tb <- config$trajectory_batch %||% list()
  output_base <- tb$output_base %||% config$project$output_dir
  statuses <- trajectory_batch_read_all_status(config, index_vars)
  statuses$index <- statuses$unit
  cli::cli_h2("轨迹预后批量汇总（{length(index_vars)} 指标）")
  cli::cli_alert_success("成功: {sum(statuses$status == 'success', na.rm = TRUE)}")
  cli::cli_alert_danger("失败: {sum(statuses$status %in% c('error','failed','partial'), na.rm = TRUE)}")

  out_dir <- file.path(output_base, "Tables")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  csv_path <- file.path(out_dir, "Batch_summary_all_indices.csv")
  tryCatch(
    utils::write.csv(statuses, csv_path, row.names = FALSE, fileEncoding = "UTF-8"),
    error = function(e) cli::cli_alert_warning("汇总 CSV 写入失败: {e$message}")
  )
  cli::cli_alert_success("汇总表: {.file {csv_path}}")
  invisible(statuses)
}

# ── 子进程池派发（轮询完成后重命名 by_index/by_unit）────────────────────────

trajectory_batch_dispatch_workers <- function(root, config, index_vars,
                                              workers = "auto",
                                              only_index = NULL,
                                              skip_existing = TRUE,
                                              config_path = NULL,
                                              worker_script = NULL) {
  tb <- config$trajectory_batch %||% list()
  output_base <- tb$output_base %||% config$project$output_dir
  worker_script <- worker_script %||% tb$worker_script %||%
    "run/trajectory_prognosis/run_trajectory_prognosis_apri_batch_worker.R"
  log_dir <- file.path(output_base, "logs")
  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)

  if (!is.null(only_index) && length(only_index))
    index_vars <- index_vars[index_vars %in% only_index]

  workers_n <- if (identical(workers, "auto") || is.null(workers)) {
    incidence_batch_auto_workers(length(index_vars))
  } else {
    max(1L, as.integer(workers))
  }

  worker_path <- file.path(root, worker_script)
  if (!file.exists(worker_path)) stop("Worker 脚本不存在: ", worker_path, call. = FALSE)
  rscript_bin <- if (exists("study_rscript_bin", mode = "function")) {
    study_rscript_bin()
  } else {
    file.path(R.home("bin"), "Rscript")
  }
  use_processx <- .Platform$OS.type == "windows" || requireNamespace("processx", quietly = TRUE)

  .status_ok <- function(unit) {
    p <- study_batch_status_path(output_base, unit)
    if (!file.exists(p)) return(FALSE)
    st <- tryCatch(jsonlite::fromJSON(p), error = function(e) NULL)
    identical(st$status, "success")
  }

  .launch <- function(unit) {
    if (skip_existing && .status_ok(unit)) {
      cli::cli_alert_info("跳过 {.field {unit}}（已完成）")
      return(NULL)
    }
    log_path <- file.path(log_dir, paste0(unit, ".log"))
    config_args <- if (!is.null(config_path) && nzchar(config_path)) {
      c("--config", normalizePath(config_path, winslash = "/", mustWork = FALSE))
    } else character(0)
    args <- c(
      normalizePath(worker_path, winslash = "/", mustWork = TRUE),
      "--unit", unit,
      config_args,
      normalizePath(root, winslash = "/", mustWork = TRUE)
    )
    if (use_processx) {
      if (!requireNamespace("processx", quietly = TRUE))
        stop("批量派发需要 processx", call. = FALSE)
      processx::process$new(
        normalizePath(rscript_bin, winslash = "/", mustWork = TRUE),
        args, stdout = log_path, stderr = log_path, cleanup = FALSE
      )
    } else {
      system2(normalizePath(rscript_bin, winslash = "/", mustWork = TRUE),
              args, stdout = log_path, stderr = log_path, wait = FALSE)
    }
    cli::cli_alert_success("启动 worker [{.field {unit}}] → {.file {basename(log_path)}}")
    list(unit = unit, log = log_path, started_at = Sys.time())
  }

  .on_worker_done <- function(unit) {
    sp <- study_batch_status_path(output_base, unit)
    if (!file.exists(sp)) return(invisible(NULL))
    st <- tryCatch(jsonlite::fromJSON(sp), error = function(e) list(status = "unknown"))
    trajectory_batch_rename_unit_folders(config, unit, st$status %||% "unknown")
    invisible(st)
  }

  total <- length(index_vars)
  done <- 0L
  active <- list()
  for (unit in index_vars) {
    while (length(active) >= workers_n) {
      Sys.sleep(8)
      still <- list()
      for (p in active) {
        sp <- study_batch_status_path(output_base, p$unit)
        if (file.exists(sp)) {
          done <- done + 1L
          st <- .on_worker_done(p$unit)
          cli::cli_alert_success("[{done}/{total}] {.field {p$unit}} 完成 (status={st$status})")
        } else {
          still[[length(still) + 1L]] <- p
        }
      }
      active <- still
    }
    proc <- .launch(unit)
    if (!is.null(proc)) active[[length(active) + 1L]] <- proc
  }

  cli::cli_alert_info("等待最后 {length(active)} 个 worker…")
  t0 <- Sys.time()
  while (length(active) > 0 && as.numeric(difftime(Sys.time(), t0, units = "secs")) < 7200) {
    Sys.sleep(15)
    still <- list()
    for (p in active) {
      sp <- study_batch_status_path(output_base, p$unit)
      if (file.exists(sp)) {
        done <- done + 1L
        st <- .on_worker_done(p$unit)
        cli::cli_alert_success("[{done}/{total}] {.field {p$unit}} 完成 (status={st$status})")
      } else {
        still[[length(still) + 1L]] <- p
      }
    }
    active <- still
  }

  trajectory_batch_write_summary(config, index_vars)
  invisible(index_vars)
}
