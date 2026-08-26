###############################################################################
#  study_batch_runner.R — 四套文献流水线通用批量编排（共享层 + 并行 worker）
#
#  复用 incidence_batch_auto_workers / processx 派发模式。
#  config$study_batch:
#    output_base, units, unit_mode (cohort|branch|modality),
#    unit_col, parallel_workers, worker_script, shared_ck_alias
###############################################################################

source(file.path(getwd(), "R", "incidence_dual_batch_runner.R"), local = FALSE)

study_batch_shared_ck_dir <- function(config) {
  sb <- config$study_batch %||% list()
  base <- sb$shared_ck_base %||% file.path(
    sb$output_base %||% config$project$output_dir,
    "checkpoints", "_shared", "main"
  )
  if (!is_absolute_path(base)) file.path(getwd(), base) else base
}

study_batch_unit_output_dir <- function(config, unit) {
  sb <- config$study_batch %||% list()
  file.path(sb$output_base %||% config$project$output_dir, "by_unit", as.character(unit)[1L])
}

study_batch_unit_ck_dir <- function(config, unit) {
  file.path(study_batch_unit_output_dir(config, unit), "checkpoints")
}

.study_batch_unit_block_names <- function(config) {
  pu <- config$pipeline_unit
  if (is.null(pu) && exists("pipeline_unit", envir = .GlobalEnv, inherits = FALSE))
    pu <- get("pipeline_unit", envir = .GlobalEnv)
  as.character((pu %||% list())$blocks %||% character(0))
}

study_batch_status_path <- function(output_base, unit) {
  # 与 incidence_batch_output_dir_name 一致：【success】/【failed】
  candidates <- c(
    file.path(output_base, "by_unit", unit, "_batch_status.json"),
    file.path(output_base, "by_unit", paste0("\u3010success\u3011", unit), "_batch_status.json"),
    file.path(output_base, "by_unit", paste0("\u3010failed\u3011", unit), "_batch_status.json"),
    # 兼容旧「成功」「失败」命名
    file.path(output_base, "by_unit", paste0(unit, "\u300c\u6210\u529f\u300d"), "_batch_status.json"),
    file.path(output_base, "by_unit", paste0(unit, "\u300c\u5931\u8d25\u300d"), "_batch_status.json")
  )
  hit <- candidates[file.exists(candidates)]
  if (length(hit)) hit[1L] else candidates[1L]
}

study_batch_write_status <- function(unit_output_dir, fields) {
  if (!dir.exists(unit_output_dir)) dir.create(unit_output_dir, recursive = TRUE)
  fields$finished_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  json_path <- file.path(unit_output_dir, "_batch_status.json")
  if (!requireNamespace("jsonlite", quietly = TRUE)) return(invisible(NULL))
  tryCatch(
    writeLines(jsonlite::toJSON(fields, auto_unbox = TRUE, pretty = TRUE), json_path),
    error = function(e) message("无法写入 _batch_status.json: ", e$message)
  )
  invisible(json_path)
}

study_batch_load_checkpoint_ctx <- function(ck_dir, prefer_block = NULL) {
  ck_dir <- normalizePath(ck_dir, winslash = "/", mustWork = FALSE)
  if (!dir.exists(ck_dir)) stop("检查点目录不存在: ", ck_dir, call. = FALSE)
  prefer <- as.character(prefer_block %||% character(0))
  prefer <- prefer[nzchar(prefer)]
  candidates <- character(0)
  for (pb in prefer) candidates <- c(candidates, file.path(ck_dir, paste0(pb, ".rds")))
  candidates <- c(candidates, file.path(ck_dir, "index.rds"))
  candidates <- unique(candidates[file.exists(candidates)])
  if (!length(candidates)) stop("检查点目录内无可用 .rds: ", ck_dir, call. = FALSE)
  obj <- tryCatch(readRDS(candidates[[1L]]), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$ctx)) stop("无法读取检查点 ctx: ", candidates[[1L]], call. = FALSE)
  if (!is.null(obj$pub_counters)) {
    .pub_counters_restore(obj$pub_counters)
  } else if (!is.null(obj$ctx$log$pub_counters)) {
    .pub_counters_restore(obj$ctx$log$pub_counters)
  }
  obj$ctx
}

study_batch_copy_shared_ck <- function(shared_ck_dir, unit_ck_dir, alias = "index") {
  if (!dir.exists(unit_ck_dir)) dir.create(unit_ck_dir, recursive = TRUE)
  src <- file.path(shared_ck_dir, paste0(alias, ".rds"))
  if (!file.exists(src)) src <- file.path(shared_ck_dir, "index.rds")
  if (!file.exists(src)) {
    cli::cli_alert_warning("共享检查点缺失: {.file {src}}")
    return(FALSE)
  }
  dst <- file.path(unit_ck_dir, "index.rds")
  file.copy(src, dst, overwrite = TRUE)
  invisible(TRUE)
}

study_batch_apply_row_filter <- function(ctx, config) {
  flt <- (config$study_batch %||% list())$row_filter
  if (is.null(flt) || !nzchar(flt)) return(ctx)
  for (slot in c("imputed", "cleaned", "raw")) {
    d <- ctx$data[[slot]]
    if (is.null(d) || !is.data.frame(d) || !nrow(d)) next
    keep <- tryCatch(
      with(d, eval(parse(text = flt))),
      error = function(e) rep(TRUE, nrow(d))
    )
    if (length(keep) != nrow(d)) next
    ctx$data[[slot]] <- d[keep, , drop = FALSE]
  }
  ctx
}

study_batch_patch_config_for_unit <- function(config, unit) {
  unit <- as.character(unit)[1L]
  sb   <- config$study_batch %||% list()
  cfg  <- config
  cfg$project$output_dir <- study_batch_unit_output_dir(config, unit)
  cfg$project$root       <- sb$project_root %||% cfg$project$root
  cfg$study_batch$active_unit <- unit
  cfg$study_batch$row_filter  <- NULL
  cfg$study_batch$worker_blocks <- NULL

  mode <- sb$unit_mode %||% "generic"
  if (mode == "cohort") {
    col <- sb$unit_col %||% "Cohort"
    cfg$study_batch$row_filter <- sprintf("%s == '%s'", col, unit)
    cfg$study_batch$worker_blocks <- as.character(sb$cohort_worker_blocks %||% character(0))
    if (!length(cfg$study_batch$worker_blocks)) {
      cfg$study_batch$worker_blocks <- .study_batch_unit_block_names(config)
    }
  } else if (mode == "branch") {
    branches <- sb$branch_map %||% list()
    if (!is.null(branches[[unit]])) {
      bm <- branches[[unit]]
      if (!is.null(bm$row_filter) && nzchar(bm$row_filter))
        cfg$study_batch$row_filter <- bm$row_filter
      if (!is.null(bm$mediator) && !is.null(cfg$mediation_nhanes_weighted)) {
        cfg$mediation_nhanes_weighted$mediators <- bm$mediator
      }
      unit_blocks <- .study_batch_unit_block_names(config)
      cfg$study_batch$worker_blocks <- as.character(bm$blocks %||% unit_blocks)
      if (!length(cfg$study_batch$worker_blocks)) cfg$study_batch$worker_blocks <- unit
    } else {
      unit_blocks <- .study_batch_unit_block_names(config)
      cfg$study_batch$worker_blocks <- if (length(unit_blocks)) unit_blocks else unit
    }
  } else if (mode == "modality") {
    if (!is.null(cfg$multimodal)) cfg$multimodal$batch_mode <- unit
    cfg$study_batch$worker_blocks <- "multimodal_early_fusion"
  } else if (mode == "index") {
    # unit = 复合指标名（如 "TyG"/"NLR"/...）；同一套 pipeline_unit blocks 对所有 unit 一致，
    # 仅通过 config$competing_risk$index_var 等字段切换当前循环到的指标。
    # 可选 unit_index_map：目录名与指标名分离，如 list(`GPR[new]` = "GPR")
    umap <- sb$unit_index_map %||% list()
    index_name <- as.character(umap[[unit]] %||% unit)[1L]
    if (!nzchar(index_name)) index_name <- unit
    cfg$competing_risk <- cfg$competing_risk %||% list()
    cfg$competing_risk$index_var      <- index_name
    cfg$competing_risk$exposure_var   <- paste0(index_name, "_quartile")
    cfg$competing_risk$trajectory_var <- paste0(index_name, "_trajectory")
    cfg$competing_risk$tyg_var        <- index_name
    # 供 trim_index_extreme / imputation force_keep 识别当前指标
    cfg$incidence <- cfg$incidence %||% list()
    cfg$incidence$index_var <- index_name
    cfg$survival <- cfg$survival %||% list()
    cfg$survival$index_var <- index_name
    cfg$imputation <- cfg$imputation %||% list()
    cfg$imputation$force_keep_columns <- unique(c(
      as.character(cfg$imputation$force_keep_columns %||% character(0)),
      index_name
    ))
    # 特征筛选排除当前暴露及相关泄漏列
    cfg$univariate_prognosis <- cfg$univariate_prognosis %||% list()
    cfg$univariate_prognosis$excluded_predictors <- unique(c(
      as.character(cfg$univariate_prognosis$excluded_predictors %||% character(0)),
      index_name,
      paste0(index_name, "_quartile"),
      paste0(index_name, "_trajectory")
    ))
    # 疾病相关变量 + 当前指标组成变量：尽早进入表级/单因素排除名单
    if (length(cfg$analysis_exclusion %||% list())) {
      if (!exists("pipeline_analysis_exclusion_manifest", mode = "function")) {
        excl_src <- file.path(
          cfg$project$root %||% getwd(),
          "Blocks/03_imputation/03block_analysis_exclusion.R"
        )
        if (file.exists(excl_src)) source(excl_src, local = FALSE)
      }
      if (exists("pipeline_analysis_exclusion_manifest", mode = "function")) {
        man <- tryCatch(
          pipeline_analysis_exclusion_manifest(cfg),
          error = function(e) NULL
        )
        if (!is.null(man)) {
          drop_vars <- as.character(man$drop_vars %||% character(0))
          cfg$imputation$table_s1_exclude_vars <- unique(c(
            as.character(cfg$imputation$table_s1_exclude_vars %||% character(0)),
            drop_vars
          ))
          cfg$univariate_prognosis$excluded_predictors <- unique(c(
            as.character(cfg$univariate_prognosis$excluded_predictors %||% character(0)),
            drop_vars
          ))
          cfg$analysis_exclusion$resolved_drop_vars <- drop_vars
        }
      }
    }
    cfg$study_batch$worker_blocks     <- .study_batch_unit_block_names(config)
  } else if (mode == "dynamic_cohort") {
    # unit 形如 CHARLS_baseline / ELSA_change / CHARLS_rcs
    parts <- strsplit(unit, "_", fixed = TRUE)[[1L]]
    cohort <- parts[1L]
    analysis <- if (length(parts) > 1L) paste(parts[-1L], collapse = "_") else "change"
    col <- sb$unit_col %||% "Cohort"
    cfg$study_batch$row_filter <- sprintf("%s == '%s'", col, cohort)
    cfg$dynamic_causal$analysis_type <- if (analysis == "baseline") "baseline" else "change"
    cfg$study_batch$worker_blocks <- switch(analysis,
      baseline = "dynamic_causal_cox_baseline",
      rcs = "dynamic_causal_rcs_change",
      change = "dynamic_causal_cox_total",
      "dynamic_causal_cox_total"
    )
    if (analysis == "rcs" && cohort == "ELSA") {
      cfg$rcs_prognosis$nk_range <- 3L
    }
  }
  cfg
}

study_batch_run_shared_layer <- function(root, config, pipeline_shared) {
  ck_dir <- study_batch_shared_ck_dir(config)
  alias  <- (config$study_batch %||% list())$shared_ck_alias %||% "index"
  if (file.exists(file.path(ck_dir, paste0(alias, ".rds"))) ||
      file.exists(file.path(ck_dir, "index.rds"))) {
    cli::cli_alert_info("共享层 checkpoint 已存在，跳过（删目录可强制重跑）")
    return(invisible(ck_dir))
  }
  sb  <- config$study_batch %||% list()
  cfg <- config
  cfg$project$root <- sb$project_root %||% root
  cfg$project$output_dir <- file.path(sb$output_base %||% config$project$output_dir, "_shared")
  pl <- pipeline_shared
  pl$checkpoint$enable <- TRUE
  pl$checkpoint$dir    <- ck_dir
  cli::cli_h2("共享层 — {paste(pl$blocks, collapse = ' → ')}")
  run_pipeline(root, config = cfg, pipeline = pl)
  invisible(ck_dir)
}

.study_batch_filter_units <- function(units, only_unit, sb = list()) {
  units <- as.character(units %||% character(0))
  only_unit <- as.character(only_unit %||% character(0))
  only_unit <- only_unit[nzchar(only_unit)]
  if (!length(only_unit)) return(units)
  umap <- sb$unit_index_map %||% list()
  # 允许 --only-unit 使用 unit_index_map 别名（不必事先写进 units 主名单）
  extra <- intersect(only_unit, names(umap))
  units <- unique(c(units, extra))
  units <- units[units %in% only_unit]
  units
}

study_batch_dispatch_unit_workers <- function(root, config, units,
                                              workers = 4L,
                                              log_dir = NULL,
                                              only_unit = NULL,
                                              skip_existing = TRUE,
                                              config_path = NULL,
                                              worker_script = NULL,
                                              rscript_bin = NULL) {
  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop("请先安装 jsonlite", call. = FALSE)

  sb          <- config$study_batch %||% list()
  output_base <- sb$output_base %||% config$project$output_dir
  workers     <- max(1L, as.integer(workers))
  worker_script <- worker_script %||% sb$worker_script %||% "run/study/run_study_batch_worker.R"

  units <- .study_batch_filter_units(units, only_unit, sb)

  if (is.null(log_dir)) log_dir <- file.path(output_base, "logs")
  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)

  worker_path <- file.path(root, worker_script)
  if (!file.exists(worker_path)) stop("Worker 脚本不存在: ", worker_path, call. = FALSE)

  if (exists("study_rscript_bin", mode = "function")) {
    rscript_bin <- rscript_bin %||% study_rscript_bin()
  } else {
    rscript_bin <- rscript_bin %||% file.path(R.home("bin"), "Rscript")
  }

  is_windows_r <- .Platform$OS.type == "windows" ||
    grepl("Rscript\\.exe$", rscript_bin, ignore.case = TRUE)
  use_processx <- is_windows_r || requireNamespace("processx", quietly = TRUE)

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
        stop("批量派发需要 processx: install.packages('processx')", call. = FALSE)
      processx::process$new(
        normalizePath(rscript_bin, winslash = "/", mustWork = TRUE),
        args,
        stdout = log_path, stderr = log_path, cleanup = FALSE
      )
    } else {
      system2(
        normalizePath(rscript_bin, winslash = "/", mustWork = TRUE),
        args, stdout = log_path, stderr = log_path, wait = FALSE
      )
    }
    cli::cli_alert_success("启动 worker [{.field {unit}}] → {.file {basename(log_path)}}")
    list(unit = unit, log = log_path, started_at = Sys.time())
  }

  total  <- length(units)
  done   <- 0L
  active <- list()
  for (unit in units) {
    while (length(active) >= workers) {
      Sys.sleep(8)
      still <- list()
      for (p in active) {
        sp <- study_batch_status_path(output_base, p$unit)
        if (file.exists(sp)) {
          done <- done + 1L
          st   <- tryCatch(jsonlite::fromJSON(sp), error = function(e) list(status = "unknown"))
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
        st   <- tryCatch(jsonlite::fromJSON(sp), error = function(e) list(status = "unknown"))
        cli::cli_alert_success("[{done}/{total}] {.field {p$unit}} 完成 (status={st$status})")
      } else {
        still[[length(still) + 1L]] <- p
      }
    }
    active <- still
  }
  invisible(units)
}

study_batch_infer_failed_stage <- function(error_message) {
  msg <- paste(as.character(error_message %||% ""), collapse = " ")
  if (!nzchar(msg)) return(NA_character_)
  keys <- c(
    "TRAJECTORY_CLUSTER_FAIL",
    "BASELINE_INDEX_NS_STOP",
    "MODEL_COVARIATE_INSUFFICIENT",
    "PAUSE_FOR_USER_DECISION: feature_selection_lasso",
    "PAUSE_FOR_USER_DECISION: feature_selection_random_forest",
    "feature_selection_lasso:",
    "feature_selection_random_forest:",
    "univariate_prognosis"
  )
  stages <- c(
    "TRAJECTORY_CLUSTER_FAIL",
    "BASELINE_INDEX_NS_STOP",
    "MODEL_COVARIATE_INSUFFICIENT",
    "feature_selection_lasso",
    "feature_selection_random_forest",
    "feature_selection_lasso",
    "feature_selection_random_forest",
    "univariate_prognosis"
  )
  for (i in seq_along(keys)) {
    if (grepl(keys[[i]], msg, fixed = TRUE)) return(stages[[i]])
  }
  NA_character_
}

study_batch_read_all_status <- function(output_base, units) {
  rows <- lapply(units, function(u) {
    p <- study_batch_status_path(output_base, u)
    if (!file.exists(p)) {
      return(data.frame(
        unit = u, status = "pending",
        elapsed_sec = NA_real_, error_message = "",
        failed_stage = NA_character_,
        trajectory_k = NA_character_,
        model2_covariates = NA_character_,
        model3_covariates = NA_character_,
        final_covariates = NA_character_,
        stringsAsFactors = FALSE
      ))
    }
    st <- tryCatch(jsonlite::fromJSON(p), error = function(e) list(status = "parse_error"))
    err <- paste(as.character(st$error_message %||% ""), collapse = "; ")
    failed_stage <- as.character(st$failed_stage %||% NA_character_)[1L]
    if (!nzchar(failed_stage) || is.na(failed_stage)) {
      failed_stage <- study_batch_infer_failed_stage(err)
    }
    data.frame(
      unit = u,
      status = as.character(st$status %||% "unknown")[1L],
      elapsed_sec = suppressWarnings(as.numeric(st$elapsed_sec %||% NA_real_))[1L],
      error_message = err,
      failed_stage = failed_stage,
      trajectory_k = paste(as.character(st$trajectory_k %||% ""), collapse = ","),
      model2_covariates = paste(as.character(st$model2_covariates %||% ""), collapse = ","),
      model3_covariates = paste(as.character(st$model3_covariates %||% ""), collapse = ","),
      final_covariates = paste(as.character(st$final_covariates %||% ""), collapse = ","),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

study_batch_write_indicator_availability <- function(output_base, statuses) {
  if (is.null(statuses) || !nrow(statuses)) return(invisible(NULL))
  avail <- data.frame(
    index = as.character(statuses$unit),
    status_cn = ifelse(as.character(statuses$status) == "success", "可用", "失败"),
    status = as.character(statuses$status),
    failed_stage = as.character(statuses$failed_stage %||% ""),
    error_message = as.character(statuses$error_message %||% ""),
    trajectory_k = as.character(statuses$trajectory_k %||% ""),
    model2_covariates = as.character(statuses$model2_covariates %||% ""),
    model3_covariates = as.character(statuses$model3_covariates %||% ""),
    final_covariates = as.character(statuses$final_covariates %||% ""),
    elapsed_sec = suppressWarnings(as.numeric(statuses$elapsed_sec)),
    stringsAsFactors = FALSE
  )
  out_dir <- file.path(output_base, "Tables")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  csv_path <- file.path(out_dir, "Indicator_availability.csv")
  tryCatch(
    utils::write.csv(avail, csv_path, row.names = FALSE, fileEncoding = "UTF-8"),
    error = function(e) cli::cli_alert_warning("Indicator_availability CSV 失败: {e$message}")
  )
  if (requireNamespace("openxlsx", quietly = TRUE)) {
    tryCatch(
      openxlsx::write.xlsx(avail, file.path(out_dir, "Indicator_availability.xlsx"), overwrite = TRUE),
      error = function(e) NULL
    )
  }
  cli::cli_alert_success("可用性汇总: {.file {csv_path}}")
  invisible(avail)
}

study_batch_run_finalize_layer <- function(root, config, finalize_blocks, pipeline_unit = NULL) {
  finalize_blocks <- as.character(finalize_blocks %||% character(0))
  if (!length(finalize_blocks)) return(invisible(NULL))

  sb <- config$study_batch %||% list()
  output_base <- sb$output_base %||% config$project$output_dir
  shared_ck <- study_batch_shared_ck_dir(config)
  alias <- sb$shared_ck_alias %||% "index"

  cfg_fin <- config
  cfg_fin$project$output_dir <- output_base
  cfg_fin$project$root <- sb$project_root %||% cfg_fin$project$root %||% root

  cli::cli_h2("Batch 尾段 — {paste(finalize_blocks, collapse = ' → ')}")
  ctx <- tryCatch(
    study_batch_load_checkpoint_ctx(shared_ck, alias),
    error = function(e) {
      cli::cli_alert_warning("Batch 尾段: 无法加载共享 checkpoint — {conditionMessage(e)}")
      list(config = cfg_fin, data = list(), results = list())
    }
  )
  ctx$config <- cfg_fin

  pl <- list(
    name = paste0((pipeline_unit$name %||% "batch"), "_finalize"),
    blocks = finalize_blocks,
    checkpoint = list(enable = FALSE)
  )
  tryCatch({
    run_pipeline(
      root,
      config   = cfg_fin,
      pipeline = pl,
      run_opts = list(initial_ctx = ctx, only = finalize_blocks)
    )
    cli::cli_alert_success("Batch 尾段完成")
  }, error = function(e) cli::cli_alert_warning("Batch 尾段失败: {conditionMessage(e)}"))
  invisible(NULL)
}

run_study_batch <- function(root, config, pipeline_shared, pipeline_unit = NULL,
                            run_opts = list(), config_path = NULL) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (!is.null(pipeline_unit)) config$pipeline_unit <- pipeline_unit
  sb   <- config$study_batch %||% list()
  units <- as.character(sb$units %||% character(0))
  if (!length(units)) stop("study_batch$units 为空", call. = FALSE)

  shared_only <- isTRUE(run_opts$shared_only)
  units_only  <- isTRUE(run_opts$units_only)
  skip_exist  <- isTRUE(run_opts$skip_existing %||% sb$skip_existing %||% TRUE)
  only_unit   <- run_opts$only_unit %||% NULL

  workers_raw  <- run_opts$workers %||% sb$parallel_workers
  auto_workers <- is.null(workers_raw) ||
    identical(tolower(trimws(as.character(workers_raw))), "auto")
  workers <- if (!auto_workers) max(1L, as.integer(workers_raw)) else NA_integer_

  if (!units_only) {
    study_batch_run_shared_layer(root, config, pipeline_shared)
  }
  if (shared_only) {
    cli::cli_alert_success("--shared-only 完成，units: {paste(units, collapse = ', ')}")
    return(invisible(units))
  }

  if (!is.null(only_unit) && length(only_unit)) {
    units <- .study_batch_filter_units(units, only_unit, sb)
  }
  effective_n <- length(units)
  if (!effective_n) stop("only_unit 过滤后 units 为空；检查 unit_index_map / --only-unit", call. = FALSE)
  if (auto_workers) {
    workers <- incidence_batch_auto_workers(
      n_indices       = effective_n,
      ram_per_worker  = sb$ram_per_worker_gb %||% 2.0,
      cpu_headroom    = sb$cpu_headroom %||% 2L,
      ram_headroom_gb = sb$ram_headroom_gb %||% 4.0,
      max_workers     = sb$max_workers %||% NULL
    )
  } else {
    cli::cli_alert_info("Worker 数: {workers}（手动）| units: {effective_n}")
  }

  study_batch_dispatch_unit_workers(
    root          = root,
    config        = config,
    units         = units,
    workers       = workers,
    only_unit     = only_unit,
    skip_existing = skip_exist,
    config_path   = config_path,
    worker_script = sb$worker_script
  )

  output_base <- sb$output_base %||% config$project$output_dir
  statuses    <- study_batch_read_all_status(output_base, units)

  # 打标：by_unit/{unit} → by_unit/【success|failed】{unit}（与发病/轨迹 batch 一致）
  if (isTRUE(sb$rename_on_finish %||% TRUE) &&
      exists("incidence_batch_output_dir_name", mode = "function")) {
    for (i in seq_len(nrow(statuses))) {
      u <- as.character(statuses$unit[i])
      st <- as.character(statuses$status[i])
      label_status <- if (identical(st, "success")) "success" else "failed"
      new_name <- incidence_batch_output_dir_name(u, label_status)
      for (subdir in c("by_unit", "by_index")) {
        old_path <- file.path(output_base, subdir, u)
        if (!dir.exists(old_path)) next
        new_path <- file.path(output_base, subdir, new_name)
        if (dir.exists(new_path)) next
        ok <- tryCatch({ file.rename(old_path, new_path); TRUE }, error = function(e) {
          cli::cli_alert_warning("重命名失败 {subdir}/{u}: {e$message}")
          FALSE
        })
        if (ok) cli::cli_alert_info("  📁 {subdir}/{u} → {new_name}")
      }
    }
  }

  # 汇总表加编号列
  statuses$no <- seq_len(nrow(statuses))
  statuses <- statuses[, c("no", setdiff(names(statuses), "no")), drop = FALSE]

  cli::cli_h2("Study Batch 汇总（{effective_n} units）")
  cli::cli_alert_success("成功: {sum(statuses$status == 'success', na.rm = TRUE)}")
  cli::cli_alert_danger("失败: {sum(statuses$status %in% c('error','failed'), na.rm = TRUE)}")

  out_dir <- file.path(output_base, "Tables")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  csv_path <- file.path(out_dir, "Batch_summary_all_units.csv")
  tryCatch(
    utils::write.csv(statuses, csv_path, row.names = FALSE, fileEncoding = "UTF-8"),
    error = function(e) cli::cli_alert_warning("汇总 CSV 写入失败: {e$message}")
  )
  if (requireNamespace("openxlsx", quietly = TRUE)) {
    tryCatch(
      openxlsx::write.xlsx(statuses, file.path(out_dir, "Batch_summary_all_units.xlsx"), overwrite = TRUE),
      error = function(e) NULL
    )
  }
  cli::cli_alert_success("汇总表: {.file {csv_path}}")
  study_batch_write_indicator_availability(output_base, statuses)

  fs <- config$feishu %||% list()
  if (isTRUE(fs$push_on_batch_summary) &&
      exists("incidence_batch_feishu_update_summary", mode = "function")) {
    statuses$index <- statuses$unit
    tryCatch(
      incidence_batch_feishu_update_summary(config, statuses),
      error = function(e) cli::cli_alert_warning("飞书汇总行更新失败: {e$message}")
    )
  }

  finalize_blocks <- as.character(sb$finalize_blocks %||% character(0))
  if (length(finalize_blocks) && sum(statuses$status == "success", na.rm = TRUE) > 0L) {
    study_batch_run_finalize_layer(root, config, finalize_blocks, pipeline_unit = pipeline_unit)
  }

  if (isTRUE(sb$run_meta_after)) {
    if (!exists("block_dynamic_causal_meta_merge", mode = "function") &&
        file.exists(file.path(root, "R/pipeline_runner.R"))) {
      source(file.path(root, "R/pipeline_runner.R"), local = FALSE)
    }
    if (exists("block_dynamic_causal_meta_merge", mode = "function")) {
      cli::cli_h2("尾段 — 双库 meta 合并")
      cfg_meta <- config
      cfg_meta$project$root <- sb$project_root %||% root
      cfg_meta$project$output_dir <- file.path(output_base, "_meta")
      ctx_meta <- list(config = cfg_meta, data = list(), results = list())
      tryCatch({
        ctx_meta <- block_dynamic_causal_meta_merge(ctx_meta)
        cli::cli_alert_success("meta 尾段完成")
      }, error = function(e) cli::cli_alert_warning("meta 尾段: {conditionMessage(e)}"))
    }
  }

  n_fail <- sum(statuses$status %in% c("error", "failed"), na.rm = TRUE)
  if (n_fail > 0L) quit(save = "no", status = 1L)

  invisible(statuses)
}
