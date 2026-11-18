###############################################################################
#  multimorbidity_cognition_zscore — 队内认知原始分 → z-score
#
#  register_block: "multimorbidity_cognition_zscore"
#  config$multimorbidity$cognition_zscore$enable = FALSE 可跳过（非认知结局）
###############################################################################

block_multimorbidity_cognition_zscore <- function(ctx, ...) {
  bl <- ctx$config$multimorbidity %||% list()
  zcfg <- bl$cognition_zscore %||% list()
  if (isFALSE(zcfg$enable %||% TRUE)) {
    cli::cli_alert_info("cognition_zscore: enable=FALSE，跳过")
    return(ctx)
  }

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_cognition_zscore: 无数据", call. = FALSE)

  raw_col <- as.character(bl$cognition_raw_col %||% zcfg$raw_col %||% "Cognition")[1L]
  z_col <- as.character(bl$cognition_z_col %||% zcfg$z_col %||% "Cognition_z")[1L]

  if (z_col %in% names(data) && isTRUE(zcfg$keep_existing %||% TRUE) &&
      !raw_col %in% names(data)) {
    cli::cli_alert_info("已有 {z_col}，无原始列，跳过重算")
    return(ctx)
  }
  if (!raw_col %in% names(data)) {
    if (z_col %in% names(data)) {
      cli::cli_alert_info("无 {raw_col}，沿用已有 {z_col}")
      return(ctx)
    }
    stop("multimorbidity_cognition_zscore: 缺列 ", raw_col, call. = FALSE)
  }

  x <- suppressWarnings(as.numeric(data[[raw_col]]))
  mu <- mean(x, na.rm = TRUE)
  sdv <- stats::sd(x, na.rm = TRUE)
  if (!is.finite(sdv) || sdv < 1e-12) {
    data[[z_col]] <- 0
  } else {
    data[[z_col]] <- (x - mu) / sdv
  }

  ctx$data$cleaned <- data
  ctx$data$imputed <- data
  # GEE 默认结局列
  ctx$config$multimorbidity_gee <- ctx$config$multimorbidity_gee %||% list()
  if (is.null(ctx$config$multimorbidity_gee$outcome_col) &&
      is.null(ctx$config$multimorbidity_gee$cognition_col)) {
    ctx$config$multimorbidity_gee$cognition_col <- z_col
    ctx$config$multimorbidity_gee$outcome_col <- z_col
  }
  cli::cli_alert_success("认知 z-score 完成 → {z_col}（mean={round(mu,2)}, sd={round(sdv,2)}）")
  ctx
}

register_block(
  "multimorbidity_cognition_zscore",
  block_multimorbidity_cognition_zscore,
  "认知得分队内标准化"
)
