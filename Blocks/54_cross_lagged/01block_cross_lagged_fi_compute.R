###############################################################################
#  cross_lagged_fi_compute — 衰弱指数 FI 计算（缺陷比例法）
#  文献: Zhang 2025 Nat Commun — 五队列 FI / 抑郁 / CVD
###############################################################################

.cl_ctx_data <- function(ctx) {
  ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
}

block_cross_lagged_fi_compute <- function(ctx, ...) {
  bl <- ctx$config$cross_lagged %||% list()
  data <- .cl_ctx_data(ctx)
  if (is.null(data)) stop("cross_lagged_fi_compute: 无数据", call. = FALSE)
  deficit_cols <- bl$deficit_cols %||% grep("_(T1|T2)$", names(data), value = TRUE)
  deficit_cols <- deficit_cols[!grepl("^(FI_|Depression_)", deficit_cols)]
  if (!length(deficit_cols) && all(c("Hypertension_T1", "Diabetes_T1", "Mobility_T1") %in% names(data))) {
    for (w in c("T1", "T2")) {
      d1 <- as.integer(data[[paste0("Hypertension_", w)]] %in% c(1, "1", TRUE))
      d2 <- as.integer(data[[paste0("Diabetes_", w)]] %in% c(1, "1", TRUE))
      d3 <- as.integer(as.numeric(data[[paste0("Mobility_", w)]]) >= 4)
      data[[paste0("FI_", w)]] <- (d1 + d2 + d3) / 3
    }
  }
  ctx$data$imputed <- data
  ctx$data$cleaned <- data
  ctx$results$cross_lagged_fi <- list(deficit_cols = deficit_cols)
  cli::cli_alert_success("FI 计算完成")
  ctx
}

register_block("cross_lagged_fi_compute", block_cross_lagged_fi_compute, "衰弱指数 FI")
