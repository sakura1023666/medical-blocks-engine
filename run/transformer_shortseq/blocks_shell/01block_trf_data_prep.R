###############################################################################
#  trf_data_prep — 短序列时序数据整理（患者×小时）
###############################################################################

block_trf_data_prep <- function(ctx, ...) {
  bl <- ctx$config$transformer_aki %||% list()
  data <- ctx$data$cleaned %||% ctx$data$imputed %||% ctx$data$raw
  id_col <- bl$id_col %||% "Patient_ID"
  time_col <- bl$time_col %||% "Hour"
  feats <- intersect(bl$feature_cols %||% names(data), names(data))
  label <- bl$label_col %||% "CSA_AKI"
  agg <- aggregate(data[feats], by = list(ID = data[[id_col]], Hour = data[[time_col]]), FUN = mean, na.rm = TRUE)
  agg$label <- data[[label]][match(paste(agg$ID, agg$Hour), paste(data[[id_col]], data[[time_col]]))]
  cen_col <- bl$center_col %||% "Center"
  if (cen_col %in% names(data)) {
    cen_map <- tapply(data[[cen_col]], data[[id_col]], function(x) x[1L])
    agg$Center <- cen_map[as.character(agg$ID)]
  }
  if (all(is.na(agg$label))) {
    pat_lab <- tapply(data[[label]], data[[id_col]], function(x) x[1L])
    agg$label <- pat_lab[as.character(agg$ID)]
  }
  event_lbl <- ctx$config$project$analysis_group %||% "CSA_AKI"
  if (!is.numeric(agg$label)) {
    agg$label <- as.integer(as.character(agg$label) == as.character(event_lbl))
  }
  ctx$data$trf_seq <- agg
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "_transformer_seq_input.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(agg, out, row.names = FALSE)
  ctx$results$trf_data_prep <- list(n_rows = nrow(agg), n_patients = length(unique(agg$ID)))
  cli::cli_alert_success("Transformer 序列数据准备完成")
  ctx
}

register_block("trf_data_prep", block_trf_data_prep, "Transformer 数据准备")
