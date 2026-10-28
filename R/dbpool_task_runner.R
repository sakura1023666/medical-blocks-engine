# 数据库池化 batch runner（预后地基 + BlendedLoS 后缀）
# 入口：run/database_pooling/run_database_pooling_batch.R

dbpool_default_units <- function() {
  c(
    "expA_amumc_solo",
    "expB_mimic_solo",
    "expC_mimic2amumc_transfer",
    "expD_pooled_mimic_amumc",
    "model_benchmark",
    "dataset_benchmark",
    "training_size_study"
  )
}

dbpool_shared_blocks <- function() {
  c(
    "dbpool_cohort_ingest",
    "dbpool_preprocess",
    "dbpool_split",
    "dbpool_labels"
  )
}

dbpool_tail_blocks <- function() {
  c(
    "dbpool_metrics",
    "dbpool_pub_tables",
    "dbpool_pub_figures",
    "dbpool_batch_finalize"
  )
}

dbpool_source_blocks <- function(root) {
  common <- file.path(root, "Blocks/78_database_pooling_full/00dbpool_common.R")
  if (file.exists(common)) source(common, local = FALSE)
  files <- sort(list.files(
    file.path(root, "Blocks/78_database_pooling_full"),
    pattern = "^[0-9].*\\.R$",
    full.names = TRUE
  ))
  for (f in files) source(f, local = FALSE)
}

.dbpool_make_ctx <- function(config, root, out_root, unit = NULL) {
  list(
    config = config,
    root_output_dir = out_root,
    output_dir = out_root,
    dbpool_unit = unit,
    results = list(),
    log = list(block_step_counter = 0L, block_output_dirs = list())
  )
}

dbpool_run_shared <- function(root, config, out_root) {
  dbpool_source_blocks(root)
  ctx <- .dbpool_make_ctx(config, root, file.path(out_root, "_shared"))
  for (b in dbpool_shared_blocks()) {
    ctx <- run_block(ctx, b)
  }
  # persist shared results pointer
  saveRDS(ctx$results, file.path(out_root, "_shared", "shared_results.rds"))
  invisible(ctx)
}

dbpool_run_unit <- function(root, config, out_root, unit, shared_results = NULL) {
  dbpool_source_blocks(root)
  unit_out <- file.path(out_root, "by_unit", unit)
  dir.create(unit_out, recursive = TRUE, showWarnings = FALSE)
  ctx <- .dbpool_make_ctx(config, root, unit_out, unit = unit)
  if (!is.null(shared_results)) ctx$results <- shared_results
  # reload shared paths if needed
  shared_rds <- file.path(out_root, "_shared", "shared_results.rds")
  if (is.null(shared_results) && file.exists(shared_rds)) {
    ctx$results <- readRDS(shared_rds)
  }
  ctx <- run_block(ctx, "dbpool_train_eval")
  ctx <- run_block(ctx, "dbpool_metrics")
  saveRDS(ctx$results, file.path(unit_out, "unit_results.rds"))
  invisible(ctx)
}

dbpool_run_tail <- function(root, config, out_root) {
  dbpool_source_blocks(root)
  ctx <- .dbpool_make_ctx(config, root, file.path(out_root, "summary_results"))
  shared_rds <- file.path(out_root, "_shared", "shared_results.rds")
  if (file.exists(shared_rds)) ctx$results <- readRDS(shared_rds)
  ctx$results$dbpool_pub_root <- file.path(out_root, "summary_results")
  for (b in dbpool_tail_blocks()) {
    ctx <- run_block(ctx, b)
  }
  invisible(ctx)
}

dbpool_run_task_parallel <- function(root, config, units = NULL, workers = 1L,
                                     shared_only = FALSE, skip_existing = TRUE,
                                     skip_shared = NULL) {
  out_root <- config$project$output_dir %||% file.path(root, "Output", "database_pooling")
  dir.create(out_root, recursive = TRUE, showWarnings = FALSE)
  units <- units %||% dbpool_default_units()
  workers <- if (identical(workers, "auto")) max(1L, parallel::detectCores() - 1L) else as.integer(workers)

  shared_rds <- file.path(out_root, "_shared", "shared_results.rds")
  if (is.null(skip_shared)) {
    skip_shared <- isTRUE(skip_existing) && file.exists(shared_rds)
  }
  cli::cli_h1("dbpool shared")
  if (isTRUE(skip_shared)) {
    cli::cli_alert_info("skip shared (exists): {shared_rds}")
  } else {
    dbpool_run_shared(root, config, out_root)
  }
  if (isTRUE(shared_only)) {
    cli::cli_alert_success("shared-only 完成: {out_root}")
    return(invisible(out_root))
  }

  shared_rds <- file.path(out_root, "_shared", "shared_results.rds")
  shared_results <- if (file.exists(shared_rds)) readRDS(shared_rds) else NULL

  run_one <- function(u) {
    done_flag <- file.path(out_root, "by_unit", u, "_SUCCESS")
    fail_flag <- file.path(out_root, "by_unit", u, "_FAILED")
    if (isTRUE(skip_existing) && file.exists(done_flag)) {
      message("skip existing: ", u)
      return(u)
    }
    ok <- tryCatch({
      dbpool_run_unit(root, config, out_root, u, shared_results = shared_results)
      TRUE
    }, error = function(e) {
      message("UNIT FAILED: ", u, " — ", conditionMessage(e))
      dir.create(dirname(fail_flag), recursive = TRUE, showWarnings = FALSE)
      writeLines(conditionMessage(e), fail_flag)
      FALSE
    })
    if (isTRUE(ok)) {
      writeLines(as.character(Sys.time()), done_flag)
      if (file.exists(fail_flag)) unlink(fail_flag)
    }
    u
  }

  cli::cli_h1("dbpool workers = {workers}; units = {length(units)}")
  if (workers <= 1L) {
    lapply(units, run_one)
  } else {
    # processx / parallel fallback
    if (requireNamespace("parallel", quietly = TRUE)) {
      cl <- parallel::makeCluster(workers)
      on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
      parallel::clusterExport(cl, c("root", "config", "out_root", "shared_results", "skip_existing"),
                              envir = environment())
      parallel::clusterEvalQ(cl, {
        source(file.path(root, "R/utils.R"))
        source(file.path(root, "R/dbpool_task_runner.R"))
        TRUE
      })
      parallel::parLapply(cl, units, run_one)
    } else {
      lapply(units, run_one)
    }
  }

  cli::cli_h1("dbpool finalize")
  dbpool_run_tail(root, config, out_root)
  invisible(out_root)
}
