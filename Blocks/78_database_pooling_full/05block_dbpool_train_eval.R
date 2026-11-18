# dbpool_train_eval — 调用公开 BlendedLoS（经 python/database_pooling/run_dbpool_experiment.py）

block_dbpool_train_eval <- function(ctx) {
  if (!exists(".dbpool_data_root", mode = "function")) {
    root <- ctx$config$project$root %||% getwd()
    source(file.path(root, "Blocks/78_database_pooling_full/00dbpool_common.R"), local = FALSE)
  }
  cfg <- .dbpool_cfg(ctx)
  unit <- as.character(ctx$dbpool_unit %||% cfg$default_unit %||% "expD_pooled_mimic_amumc")[1L]
  blended <- ctx$results$dbpool_blended_out %||% .dbpool_blended_out(ctx)
  data_dir <- ctx$output_dir_data %||% file.path(ctx$output_dir, "Data")
  work <- file.path(data_dir, paste0("unit_", unit))
  dir.create(work, recursive = TRUE, showWarnings = FALSE)
  args <- c(
    "--unit", unit,
    "--blended-out", blended,
    "--work-dir", work
  )
  if (isTRUE(cfg$dry_run %||% FALSE) || identical(Sys.getenv("DBPOOL_DRY_RUN", ""), "1")) {
    args <- c(args, "--dry-run")
  }
  run_py <- file.path(.dbpool_scripts_dir(ctx), "run_dbpool_experiment.py")
  .dbpool_run_py(
    ctx,
    run_py,
    args = args,
    timeout_sec = as.integer(cfg$train_timeout_sec %||% 172800L)
  )
  ctx$results$dbpool_last_unit <- unit
  ctx$results$dbpool_unit_work <- work
  ctx
}

register_block(
  "dbpool_train_eval", block_dbpool_train_eval,
  "数据库池化：封装公开 BlendedLoS 训练/评估一个实验单元"
)
