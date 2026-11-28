###############################################################################
#  trf_feature_reduce — 因果因子降维（6 个核心变量）
###############################################################################

block_trf_feature_reduce <- function(ctx, ...) {
  bl <- ctx$config$transformer_aki %||% list()
  data <- ctx$data$trf_seq %||% ctx$data$cleaned
  feats <- intersect(bl$feature_cols %||% c("Heart_rate", "MAP", "Creatinine", "Urine_output", "Lactate", "Hemoglobin"), names(data))
  if (length(feats) > 6L) {
    cors <- sapply(feats, function(f) abs(stats::cor(data[[f]], data$label, use = "complete.obs")))
    feats <- names(sort(cors, decreasing = TRUE))[seq_len(6L)]
  }
  tab <- data.frame(selected_feature = feats, rank = seq_along(feats), stringsAsFactors = FALSE)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Transformer_Features.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$config$transformer_aki$selected_features <- feats
  ctx$results$trf_feature_reduce <- list(features = feats)
  cli::cli_alert_success("特征降维: {length(feats)} 个因果因子")
  ctx
}

register_block("trf_feature_reduce", block_trf_feature_reduce, "Transformer 特征降维")
