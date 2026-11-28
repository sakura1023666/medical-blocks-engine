###############################################################################
#  trf_multicenter_val — 多中心外部验证汇总
###############################################################################

block_trf_multicenter_val <- function(ctx, ...) {
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Transformer")
  met_path <- file.path(out, "Table_REACT_MultiCenter_Metrics.csv")
  if (!file.exists(met_path)) {
    int_path <- file.path(out, "Table_Transformer_Metrics.csv")
    if (file.exists(int_path)) {
      met <- utils::read.csv(int_path, stringsAsFactors = FALSE)
      met$center <- "Internal"
      utils::write.csv(met, met_path, row.names = FALSE)
    }
  }
  tab <- if (file.exists(met_path)) utils::read.csv(met_path, stringsAsFactors = FALSE) else data.frame(note = "empty")
  out2 <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Transformer_MultiCenter_Val.csv")
  utils::write.csv(tab, out2, row.names = FALSE)
  ctx$results$trf_multicenter_val <- list(table = tab)
  cli::cli_alert_success("多中心验证汇总完成")
  ctx
}

register_block("trf_multicenter_val", block_trf_multicenter_val, "多中心验证")
