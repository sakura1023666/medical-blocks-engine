# dbpool_preprocess — clip / forward-fill+mask / q5-q95 归一化（对齐原文 + 适配器落盘）

block_dbpool_preprocess <- function(ctx) {
  if (!exists(".dbpool_data_root", mode = "function")) {
    root <- ctx$config$project$root %||% getwd()
    source(file.path(root, "Blocks/78_database_pooling_full/00dbpool_common.R"), local = FALSE)
  }
  cfg <- .dbpool_cfg(ctx)
  data_root <- ctx$results$dbpool_data_root %||% .dbpool_data_root(ctx)
  blended_out <- .dbpool_blended_out(ctx)
  # 已用 Aiya-Linux 上的 BlendedICU 协调库时，不再用 RealExtraction 覆盖标签和时序。
  if (isTRUE(cfg$skip_realextraction_adapt %||% FALSE)) {
    ctx$results$dbpool_blended_out <- blended_out
    cli::cli_alert_success("dbpool_preprocess: use existing BlendedICU ready tree {blended_out}")
    return(ctx)
  }
  max_stays <- cfg$smoke_max_stays_per_db %||% NULL
  args <- c(
    "--data-root", data_root,
    "--out", blended_out,
    "--selected-only"
  )
  if (!is.null(max_stays) && is.finite(as.numeric(max_stays)) && as.numeric(max_stays) > 0) {
    args <- c(args, "--max-stays-per-db", as.character(as.integer(max_stays)))
  }
  if (isTRUE(cfg$all_stays %||% FALSE)) {
    args <- c(args, "--all-stays")
  }
  adapt_py <- file.path(.dbpool_scripts_dir(ctx), "adapt_realextraction_to_blendedlos.py")
  # Timeseries already on disk: refresh labels/flat with BlendedICU v0.3.2 rules
  # (Amsterdam lengthofstay as hours; age/height/weight bin left edge). Do not
  # rebuild 66k hourly files. A full rebuild still runs when the tree is missing.
  if (dir.exists(file.path(blended_out, "preprocessed_timeseries"))) {
    args <- c(args, "--labels-flat-only")
  }
  .dbpool_run_py(
    ctx,
    adapt_py,
    args = args,
    timeout_sec = as.integer(cfg$adapt_timeout_sec %||% 86400L)
  )
  # copy preprocessing yaml for Table S1 methods trail
  delivery <- ctx$results$dbpool_delivery %||% file.path(data_root, "out", "delivery")
  yml <- file.path(delivery, "07_preprocessing_config.yaml")
  if (file.exists(yml)) {
    file.copy(yml, file.path(ctx$output_dir_tables, "Methods_preprocessing_config.yaml"), overwrite = TRUE)
  }
  ctx$results$dbpool_blended_out <- blended_out
  cli::cli_alert_success("dbpool_preprocess: blended_out={blended_out}")
  ctx
}

register_block(
  "dbpool_preprocess", block_dbpool_preprocess,
  "数据库池化：RealExtraction→BlendedLoS 适配（clip/归一化在训练侧对齐原文）"
)
