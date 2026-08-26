###############################################################################
#  trf_sensitivity — 模型架构敏感性
###############################################################################

block_trf_sensitivity <- function(ctx, ...) {
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Transformer")
  met_path <- file.path(out, "Table_Transformer_Metrics.csv")
  tab <- if (file.exists(met_path)) utils::read.csv(met_path, stringsAsFactors = FALSE) else data.frame(note = "empty")
  out2 <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Transformer_Sensitivity.csv")
  utils::write.csv(tab, out2, row.names = FALSE)
  ctx$results$trf_sensitivity <- list(table = tab)
  cli::cli_alert_success("Transformer 敏感性完成")
  ctx
}

register_block("trf_sensitivity", block_trf_sensitivity, "Transformer 敏感性")
