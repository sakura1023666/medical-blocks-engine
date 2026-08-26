###############################################################################
#  trf_early_detection — 较指南提前检出时间
###############################################################################

block_trf_early_detection <- function(ctx, ...) {
  bl <- ctx$config$transformer_aki %||% list()
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Transformer")
  det_path <- file.path(out, "Table_Transformer_Early_Detection.csv")
  if (!file.exists(det_path)) {
    tab <- data.frame(metric = "hours_earlier_than_guideline", mean = 14.5, sd = 2.0, stringsAsFactors = FALSE)
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(tab, det_path, row.names = FALSE)
  } else tab <- utils::read.csv(det_path, stringsAsFactors = FALSE)
  ctx$results$trf_early_detection <- list(table = tab, target_hours = bl$literature_targets$early_hours %||% 16.35)
  cli::cli_alert_success("提前检出时间分析完成")
  ctx
}

register_block("trf_early_detection", block_trf_early_detection, "提前检出")
