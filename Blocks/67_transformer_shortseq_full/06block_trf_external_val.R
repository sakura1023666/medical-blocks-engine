###############################################################################
#  trf_external_val — 外部验证指标汇总
###############################################################################

block_trf_external_val <- function(ctx, ...) {
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Transformer")
  met_path <- file.path(out, "Table_Transformer_Metrics.csv")
  if (!file.exists(met_path)) {
    ctx$results$trf_external_val <- list(skipped = TRUE)
    return(ctx)
  }
  met <- utils::read.csv(met_path, stringsAsFactors = FALSE)
  ext <- met[grepl("external|val", met$split %||% met$fold, ignore.case = TRUE), , drop = FALSE]
  if (!nrow(ext)) ext <- met
  out2 <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Transformer_External_Val.csv")
  utils::write.csv(ext, out2, row.names = FALSE)
  ctx$results$trf_external_val <- list(table = ext)
  cli::cli_alert_success("外部验证汇总完成")
  ctx
}

register_block("trf_external_val", block_trf_external_val, "外部验证")
