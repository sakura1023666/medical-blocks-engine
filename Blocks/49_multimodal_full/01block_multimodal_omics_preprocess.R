###############################################################################
#  multimodal_omics_preprocess — 组学 z-score / 方差过滤 / 缺失填补
###############################################################################

block_multimodal_omics_preprocess <- function(ctx, ...) {
  bl <- ctx$config$multimodal %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) stop("multimodal_omics_preprocess: 无数据", call. = FALSE)

  omics <- intersect(bl$omics_vars %||% grep("^Omics_", names(data), value = TRUE), names(data))
  if (!length(omics)) stop("multimodal_omics_preprocess: 无组学列", call. = FALSE)
  min_var <- as.numeric(bl$min_variance %||% 1e-4)
  keep <- character(0)
  for (col in omics) {
    x <- as.numeric(data[[col]])
    if (stats::var(x, na.rm = TRUE) >= min_var) keep <- c(keep, col)
  }
  if (!length(keep)) keep <- omics
  for (col in keep) {
    x <- as.numeric(data[[col]])
    x[is.na(x)] <- stats::median(x, na.rm = TRUE)
    data[[col]] <- as.numeric(scale(x))
  }
  data$.omics_preprocessed <- TRUE
  ctx$data$imputed <- data
  ctx$data$cleaned <- data
  ctx$config$multimodal$omics_vars <- keep
  ctx$results$multimodal_preprocess <- list(n_omics = length(keep), omics_vars = keep)
  cli::cli_alert_success("组学预处理完成（保留 {length(keep)} 特征）")
  ctx
}

register_block(
  "multimodal_omics_preprocess",
  block_multimodal_omics_preprocess,
  "组学标准化与方差过滤"
)
