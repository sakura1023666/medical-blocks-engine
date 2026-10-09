###############################################################################
#  tst_stroke_task_runner.R — 缺血性脑卒中两阶段 Transformer 任务并行编排
#
#  复用 study_batch_* 共享层 / worker 派发；unit 来自 config$tst_stroke$branch_map。
#  API:
#    tst_stroke_expand_unit_matrix(config)
#    tst_stroke_resolve_task_units(config, explicit_units = NULL)
#    tst_stroke_run_task_parallel(root, config, pipeline_shared, units, workers, ...)
#    tst_stroke_run_unit(root, config, unit, pipeline_shared = NULL)
###############################################################################

.tst_stroke_model_family_specs <- function() {
  # DL 主模型：训练后接校准/DCA + SHAP，保证全文图表面齐
  dl_tail <- c("tst_calibration_dca", "tst_shap")
  list(
    A1 = list(
      suffix = "A1_repo",
      blocks = c("tst_repo_a1", dl_tail),
      python_mode = "tst_train_a1"
    ),
    A2 = list(
      suffix = "A2_single",
      blocks = c("tst_train_eval", dl_tail),
      python_mode = "tst_train_a2"
    ),
    B = list(
      suffix = "B_twostage",
      blocks = c("tst_train_eval", dl_tail),
      python_mode = "tst_train_b"
    ),
    logistic = list(
      suffix = "logistic", blocks = c("tst_train_eval"),
      python_mode = "tst_baselines", model = "logistic"
    ),
    xgb = list(
      suffix = "xgb", blocks = c("tst_train_eval"),
      python_mode = "tst_baselines", model = "xgboost"
    ),
    mlp = list(
      suffix = "mlp", blocks = c("tst_train_eval"),
      python_mode = "tst_baselines", model = "mlp"
    ),
    lstm = list(
      suffix = "lstm", blocks = c("tst_train_eval"),
      python_mode = "tst_baselines", model = "lstm"
    )
  )
}

.tst_stroke_special_unit_defs <- function() {
  list(
    temporal_holdout = list(
      blocks = c("tst_split", "tst_train_eval"),
      python_mode = "tst_train_b", temporal = TRUE
    ),
    external_synthetic = list(
      blocks = c("tst_external"), python_mode = "tst_external_synthetic"
    )
  )
}

.tst_stroke_branch_entry <- function(spec, landmark = NULL) {
  entry <- list(
    blocks = as.character(spec$blocks),
    python_mode = as.character(spec$python_mode)[1L]
  )
  if (!is.null(landmark)) entry$landmark <- as.integer(landmark)[1L]
  if (!is.null(spec$model)) entry$model <- as.character(spec$model)[1L]
  if (!is.null(spec$ablation)) entry$ablation <- as.character(spec$ablation)[1L]
  if (isTRUE(spec$temporal)) entry$temporal <- TRUE
  entry
}

#' 展开 landmark × model_families 笛卡尔积 + ablation / temporal / external
tst_stroke_expand_unit_matrix <- function(config) {
  ts <- config$tst_stroke %||% list()
  landmarks <- as.integer(ts$landmarks %||% c(24L, 48L, 72L, 96L, 120L))
  families  <- as.character(ts$model_families %||%
    c("A1", "A2", "B", "logistic", "xgb", "mlp", "lstm"))
  family_spec <- .tst_stroke_model_family_specs()
  ablations   <- as.character(ts$ablation_variants %||% c("mask", "structure"))

  branch_map <- ts$branch_map %||% list()
  units <- character(0)

  for (lm in landmarks) {
    for (fam in families) {
      spec <- family_spec[[fam]]
      if (is.null(spec)) next
      uname <- sprintf("L%d_%s", lm, spec$suffix)
      units <- c(units, uname)
      branch_map[[uname]] <- .tst_stroke_branch_entry(spec, landmark = lm)
    }
  }

  for (lm in landmarks) {
    for (abl in ablations) {
      uname <- sprintf("L%d_ablation_%s", lm, abl)
      units <- c(units, uname)
      branch_map[[uname]] <- .tst_stroke_branch_entry(
        list(
          blocks = c("tst_train_eval"), python_mode = "tst_ablation",
          ablation = abl
        ),
        landmark = lm
      )
    }
  }

  special <- .tst_stroke_special_unit_defs()
  force_skip_temporal <- isTRUE(ts$temporal_force_skip %||% TRUE)
  for (uname in names(special)) {
    if (force_skip_temporal && identical(uname, "temporal_holdout")) {
      cli::cli_alert_info("expand_unit_matrix: 跳过 temporal_holdout（temporal_force_skip=TRUE）")
      next
    }
    if (is.null(branch_map[[uname]])) {
      branch_map[[uname]] <- special[[uname]]
    }
    units <- c(units, uname)
  }

  list(units = unique(units), branch_map = branch_map)
}

#' config$tst_stroke$expand_full_matrix=TRUE 时展开全矩阵；否则尊重显式 task_units
tst_stroke_resolve_task_units <- function(config, explicit_units = NULL) {
  ts <- config$tst_stroke %||% list()
  bm <- ts$branch_map %||% list()

  if (isTRUE(ts$expand_full_matrix %||% TRUE)) {
    out <- tst_stroke_expand_unit_matrix(config)
    config$tst_stroke$branch_map <- out$branch_map
    return(out)
  }

  u <- as.character(explicit_units %||% names(bm))
  missing <- setdiff(u, names(bm))
  if (length(missing)) {
    stop(
      "task_units 含 branch_map 未定义项: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  list(units = u, branch_map = bm[u])
}

source(file.path(getwd(), "R", "study_batch_runner.R"), local = FALSE)

.tst_stroke_resolve_config_units <- function(config, explicit_units = NULL) {
  resolved <- tst_stroke_resolve_task_units(config, explicit_units = explicit_units)
  config$tst_stroke$branch_map <- resolved$branch_map
  list(config = config, units = resolved$units)
}

.tst_stroke_all_units <- function(config) {
  explicit <- if (exists("task_units", envir = .GlobalEnv, inherits = FALSE)) {
    get("task_units", envir = .GlobalEnv)
  } else {
    NULL
  }
  .tst_stroke_resolve_config_units(config, explicit_units = explicit)$units
}

.tst_stroke_branch_map_for_study_batch <- function(config) {
  bm <- (config$tst_stroke %||% list())$branch_map %||% list()
  lapply(bm, function(x) list(blocks = as.character(x$blocks %||% character(0))))
}

.tst_stroke_inject_study_batch <- function(config, units, config_path = NULL) {
  output_base <- config$project$output_dir
  ts <- config$tst_stroke %||% list()
  finalize_blocks <- as.character(
    ts$finalize_blocks %||% c("tst_literature_validate", "tst_pub_export", "tst_summary_results")
  )
  cfg <- config
  cfg$study_batch <- list(
    output_base     = output_base,
    project_root    = cfg$project$root,
    units           = as.character(units),
    unit_mode       = "branch",
    branch_map      = .tst_stroke_branch_map_for_study_batch(cfg),
    parallel_workers = "auto",
    skip_existing   = TRUE,
    worker_script   = "run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_worker.R",
    # A2 顺序：split → imputation → timeseries → landmark；workers 必须拿末段共享态
    # （含 hourly_long_path）。旧默认 tst_split 会在 timeseries 之前截断，训练全挂。
    shared_ck_alias = as.character(ts$shared_ck_alias %||% "tst_landmark")[1L],
    shared_ck_base  = file.path(output_base, "checkpoints", "_shared", "main"),
    rename_on_finish = isTRUE(ts$rename_unit_on_finish %||% TRUE),
    finalize_blocks = finalize_blocks,
    max_workers     = ts$max_workers %||% 4L,
    ram_per_worker_gb = ts$ram_per_worker_gb %||% 4.0
  )
  if (!is.null(config_path) && nzchar(config_path))
    cfg$study_batch$config_path <- normalizePath(config_path, winslash = "/", mustWork = FALSE)
  cfg
}

.tst_stroke_units_need_shared <- function(units) {
  units <- as.character(units)
  !length(units) || !all(units %in% "external_synthetic")
}

.tst_stroke_extract_status_metrics <- function(ctx, unit, config_unit) {
  bm <- (config_unit$tst_stroke %||% list())$branch_map %||% list()
  branch <- bm[[unit]] %||% list()
  out <- list(
    python_mode  = as.character(branch$python_mode %||% "")[1L],
    landmark     = suppressWarnings(as.integer(branch$landmark %||% NA_integer_))[1L],
    is_synthetic = FALSE,
    auroc        = NA_real_,
    n_cohort     = NA_integer_
  )
  if (is.null(ctx)) return(out)

  cohort <- ctx$results$tst_cohort %||% list()
  if (!is.na(suppressWarnings(as.integer(cohort$n %||% NA_integer_))[1L]))
    out$n_cohort <- as.integer(cohort$n)[1L]

  for (key in c("tst_train_eval", "tst_repo_a1", "tst_external")) {
    res <- ctx$results[[key]] %||% list()
    if (isTRUE(res$is_synthetic)) out$is_synthetic <- TRUE
    mp <- res$metrics
    if (is.data.frame(mp) && nrow(mp)) {
      auroc_col <- intersect(c("AUROC", "auroc", "AUC", "auc"), names(mp))
      if (length(auroc_col)) {
        val <- suppressWarnings(as.numeric(mp[[auroc_col[[1L]]]][1L]))
        if (!is.na(val)) out$auroc <- val
      }
    }
  }
  out
}

#' 单 unit worker 逻辑（由 run_two_stage_transformer_stroke_worker.R 调用）
tst_stroke_run_unit <- function(root, config, unit, pipeline_shared = NULL, t_start = NULL,
                                config_path = NULL) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  unit <- as.character(unit)[1L]
  if (is.null(t_start)) t_start <- proc.time()

  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop("请先安装 jsonlite", call. = FALSE)

  if (!is.null(pipeline_shared) && is.null(config$pipeline_unit) &&
      exists("pipeline_unit", envir = .GlobalEnv, inherits = FALSE)) {
    config$pipeline_unit <- get("pipeline_unit", envir = .GlobalEnv)
  }

  resolved_all <- .tst_stroke_resolve_config_units(config)
  config <- resolved_all$config
  all_units <- resolved_all$units
  config <- .tst_stroke_inject_study_batch(config, all_units, config_path = config_path)

  sb          <- config$study_batch
  output_base <- sb$output_base
  shared_ck   <- study_batch_shared_ck_dir(config)
  unit_ck     <- study_batch_unit_ck_dir(config, unit)
  alias       <- sb$shared_ck_alias %||% "tst_split"

  config_unit <- study_batch_patch_config_for_unit(config, unit)
  # 确保 unit 侧也能读到展开后的 tst_stroke$branch_map（python_mode / landmark）
  config_unit$tst_stroke$branch_map <- config$tst_stroke$branch_map
  output_unit <- study_batch_unit_output_dir(config, unit)
  pipeline_unit <- config$pipeline_unit %||%
    (if (exists("pipeline_unit", envir = .GlobalEnv, inherits = FALSE))
      get("pipeline_unit", envir = .GlobalEnv) else list(blocks = character(0)))

  .write_status <- function(status, error_message = NULL, ctx = NULL) {
    elapsed <- round(as.numeric((proc.time() - t_start)["elapsed"]), 1)
    failed_stage <- if (!identical(status, "success")) {
      study_batch_infer_failed_stage(error_message)
    } else {
      NA_character_
    }
    met <- .tst_stroke_extract_status_metrics(ctx, unit, config_unit)
    fields <- list(
      unit           = unit,
      index          = unit,
      status         = status,
      db_mode        = "MIMIC",
      error_message  = error_message,
      failed_stage   = failed_stage,
      elapsed_sec    = elapsed,
      disease        = (config_unit$feishu %||% list())$disease_label %||%
        config_unit$project$disease %||% "",
      protocol       = (config_unit$feishu %||% list())$protocol_label %||% "",
      python_mode    = met$python_mode,
      landmark       = met$landmark,
      is_synthetic   = met$is_synthetic,
      auroc          = met$auroc,
      n_mimic_after  = met$n_cohort,
      mimic_branch   = unit
    )
    study_batch_write_status(output_unit, fields)
    if (isTRUE((config_unit$feishu %||% list())$enable) &&
        exists("incidence_batch_feishu_push_result", mode = "function")) {
      tryCatch(
        incidence_batch_feishu_push_result(config_unit, fields),
        error = function(e) cli::cli_alert_warning("飞书推送异常: {e$message}")
      )
    }
    fields
  }

  cli::cli_h1("TST Stroke Worker: {unit}")

  shared_ok <- study_batch_copy_shared_ck(shared_ck, unit_ck, alias)
  if (!shared_ok && identical(unit, "external_synthetic")) {
    cli::cli_alert_warning("external_synthetic: 共享 checkpoint 缺失，使用空 ctx 继续")
    initial_ctx <- list(config = config_unit, data = list(), results = list())
  } else if (!shared_ok) {
    .write_status("failed", paste0("复制共享 checkpoint 失败 (alias=", alias, ")"))
    stop("复制共享 checkpoint 失败", call. = FALSE)
  } else {
    initial_ctx <- tryCatch(
      study_batch_load_checkpoint_ctx(unit_ck, alias),
      error = function(e) {
        tryCatch(
          study_batch_load_checkpoint_ctx(unit_ck, "index"),
          error = function(e2) {
            .write_status("failed", conditionMessage(e2))
            stop(conditionMessage(e2), call. = FALSE)
          }
        )
      }
    )
    initial_ctx <- study_batch_apply_row_filter(initial_ctx, config_unit)
  }

  worker_blocks <- as.character(config_unit$study_batch$worker_blocks %||% character(0))
  # 兜底：优先用展开后的 tst_stroke$branch_map；禁止把 unit 名当成 block
  if (!length(worker_blocks) || identical(worker_blocks, unit)) {
    bm <- (config_unit$tst_stroke %||% list())$branch_map %||% list()
    worker_blocks <- as.character((bm[[unit]] %||% list())$blocks %||% character(0))
  }
  worker_blocks <- setdiff(worker_blocks, unit)
  if (!length(worker_blocks)) stop("未配置 worker_blocks（检查 tst_stroke$branch_map）", call. = FALSE)
  cli::cli_alert_info("{unit}: blocks = {paste(worker_blocks, collapse = ' → ')}")

  pl <- pipeline_unit
  if (is.null(pl) || !is.list(pl)) pl <- list(name = "tst_stroke_unit", blocks = worker_blocks)
  pl$blocks <- worker_blocks
  pl$name   <- paste0(pl$name %||% "tst_stroke_unit", "_", unit)
  pl$checkpoint <- list(enable = TRUE, dir = unit_ck)

  tryCatch({
    final_ctx <- run_pipeline(
      root,
      config   = config_unit,
      pipeline = pl,
      run_opts = list(initial_ctx = initial_ctx, only = worker_blocks)
    )
    .write_status("success", ctx = final_ctx)
    cli::cli_alert_success("{unit}: 完成")
    invisible(final_ctx)
  }, error = function(e) {
    failed_ctx <- tryCatch({
      ck_files <- list.files(unit_ck, pattern = "\\.rds$", full.names = TRUE)
      if (!length(ck_files)) NULL else {
        ck_files <- ck_files[order(file.info(ck_files)$mtime, decreasing = TRUE)]
        obj <- readRDS(ck_files[[1L]])
        obj$ctx %||% obj
      }
    }, error = function(e2) NULL)
    .write_status("failed", conditionMessage(e), ctx = failed_ctx)
    stop(conditionMessage(e), call. = FALSE)
  })
}

#' 任务并行总入口（由 run_two_stage_transformer_stroke_task_parallel.R 调用）
tst_stroke_run_task_parallel <- function(root, config, pipeline_shared, units, workers = "auto",
                                         config_path = NULL, skip_existing = TRUE,
                                         pipeline_unit = NULL) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop("请先安装 jsonlite", call. = FALSE)

  if (!exists("incidence_batch_feishu_push_result", mode = "function")) {
    fb <- file.path(root, "R", "feishu_bitable.R")
    if (file.exists(fb)) source(fb, local = FALSE)
  }

  resolved_all <- .tst_stroke_resolve_config_units(
    config,
    explicit_units = if (exists("task_units", envir = .GlobalEnv, inherits = FALSE)) {
      get("task_units", envir = .GlobalEnv)
    } else {
      NULL
    }
  )
  config <- resolved_all$config
  all_units <- resolved_all$units
  units     <- as.character(units %||% all_units)

  if (!is.null(pipeline_unit)) config$pipeline_unit <- pipeline_unit
  else if (exists("pipeline_unit", envir = .GlobalEnv, inherits = FALSE))
    config$pipeline_unit <- get("pipeline_unit", envir = .GlobalEnv)

  config <- .tst_stroke_inject_study_batch(config, all_units, config_path = config_path)
  sb <- config$study_batch

  # A2 铁律：tst_split → imputation(fit_on=train)；禁止划分前全量 MICE
  common_r <- file.path(root, "Blocks/71_two_stage_transformer_stroke/00tst_common.R")
  if (file.exists(common_r)) {
    sys.source(common_r, envir = environment())
  }
  if (exists(".tst71_assert_shared_mi_split_order", mode = "function")) {
    .tst71_assert_shared_mi_split_order(pipeline_shared, config)
  }

  if (length(units) == 0L) {
    if (.tst_stroke_units_need_shared(character(0))) {
      study_batch_run_shared_layer(root, config, pipeline_shared)
    }
    cli::cli_alert_success("--shared-only 完成，units: {paste(all_units, collapse = ', ')}")
    return(invisible(all_units))
  }

  if (.tst_stroke_units_need_shared(units)) {
    study_batch_run_shared_layer(root, config, pipeline_shared)
  } else {
    cli::cli_alert_info("仅 external_synthetic：跳过共享层（无需 MIMIC 长表 checkpoint）")
  }

  workers_raw  <- workers
  auto_workers <- is.null(workers_raw) ||
    identical(tolower(trimws(as.character(workers_raw))), "auto")
  effective_n  <- length(units)
  if (auto_workers) {
    workers_n <- incidence_batch_auto_workers(
      n_indices       = effective_n,
      ram_per_worker  = sb$ram_per_worker_gb %||% 2.0,
      cpu_headroom    = sb$cpu_headroom %||% 2L,
      ram_headroom_gb = sb$ram_headroom_gb %||% 4.0,
      max_workers     = sb$max_workers %||% NULL
    )
  } else {
    workers_n <- max(1L, as.integer(workers_raw))
    cli::cli_alert_info("Worker 数: {workers_n}（手动）| units: {effective_n}")
  }

  cfg_path <- config_path %||% sb$config_path %||% NULL
  study_batch_dispatch_unit_workers(
    root          = root,
    config        = config,
    units         = all_units,
    workers       = workers_n,
    only_unit     = units,
    skip_existing = isTRUE(skip_existing),
    config_path   = cfg_path,
    worker_script = sb$worker_script
  )

  output_base <- sb$output_base
  statuses    <- study_batch_read_all_status(output_base, units)

  if (isTRUE(sb$rename_on_finish %||% TRUE) &&
      exists("incidence_batch_output_dir_name", mode = "function")) {
    for (i in seq_len(nrow(statuses))) {
      u  <- as.character(statuses$unit[i])
      st <- as.character(statuses$status[i])
      label_status <- if (identical(st, "success")) "success" else "failed"
      new_name <- incidence_batch_output_dir_name(u, label_status)
      old_path <- file.path(output_base, "by_unit", u)
      if (!dir.exists(old_path)) next
      new_path <- file.path(output_base, "by_unit", new_name)
      if (dir.exists(new_path)) next
      ok <- tryCatch({ file.rename(old_path, new_path); TRUE }, error = function(e) {
        cli::cli_alert_warning("重命名失败 by_unit/{u}: {e$message}")
        FALSE
      })
      if (ok) cli::cli_alert_info("  by_unit/{u} -> {new_name}")
    }
  }

  statuses$no <- seq_len(nrow(statuses))
  statuses <- statuses[, c("no", setdiff(names(statuses), "no")), drop = FALSE]

  cli::cli_h2("TST Stroke Batch 汇总（{effective_n} units）")
  cli::cli_alert_success("成功: {sum(statuses$status == 'success', na.rm = TRUE)}")
  cli::cli_alert_danger("失败: {sum(statuses$status %in% c('error','failed'), na.rm = TRUE)}")

  out_dir <- file.path(output_base, "Tables")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  csv_path <- file.path(out_dir, "Batch_summary_all_units.csv")
  tryCatch(
    utils::write.csv(statuses, csv_path, row.names = FALSE, fileEncoding = "UTF-8"),
    error = function(e) cli::cli_alert_warning("汇总 CSV 写入失败: {e$message}")
  )
  cli::cli_alert_success("汇总表: {.file {csv_path}}")
  study_batch_write_indicator_availability(output_base, statuses)

  finalize_blocks <- as.character(sb$finalize_blocks %||% character(0))
  if (length(finalize_blocks) && sum(statuses$status == "success", na.rm = TRUE) > 0L) {
    tryCatch(
      study_batch_run_finalize_layer(
        root, config, finalize_blocks,
        pipeline_unit = config$pipeline_unit
      ),
      error = function(e) cli::cli_alert_warning("尾段 finalize 失败: {e$message}")
    )
  }

  fs <- config$feishu %||% list()
  if (isTRUE(fs$push_on_batch_summary) &&
      exists("incidence_batch_feishu_update_summary", mode = "function")) {
    statuses$index <- statuses$unit
    tryCatch(
      incidence_batch_feishu_update_summary(config, statuses),
      error = function(e) cli::cli_alert_warning("飞书汇总行更新失败: {e$message}")
    )
  }

  n_fail <- sum(statuses$status %in% c("error", "failed"), na.rm = TRUE)
  if (n_fail > 0L) quit(save = "no", status = 1L)

  invisible(statuses)
}
