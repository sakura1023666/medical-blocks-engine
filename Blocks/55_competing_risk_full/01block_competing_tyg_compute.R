###############################################################################
#  competing_tyg_compute — TyG 指数计算
#  文献: Lai 2025 Cardiovasc Diabetol — TyG 轨迹与竞争风险
###############################################################################

block_competing_tyg_compute <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("competing_tyg_compute: 无数据", call. = FALSE)
  if ("TyG_baseline" %in% names(data)) {
    data$TyG <- data$TyG_baseline
  } else if (all(c("FBG", "TG") %in% names(data))) {
    data$TyG <- log(as.numeric(data$FBG) * as.numeric(data$TG) / 2)
  }
  visit_cols <- bl$tyg_visit_cols %||% grep("^TyG_V", names(data), value = TRUE)
  if (length(visit_cols) >= 2L) {
    mat <- as.matrix(data[visit_cols])
    slope <- apply(mat, 1, function(x) if (sum(!is.na(x)) >= 2) coef(lm(x ~ seq_along(x)))[2] else NA_real_)
    data$TyG_slope <- slope
    q <- stats::quantile(data$TyG_slope, c(0.33, 0.67), na.rm = TRUE)
    data$TyG_trajectory <- cut(data$TyG_slope, breaks = c(-Inf, q[1], q[2], Inf),
                               labels = c("low_decreasing", "stable", "high_decreasing"))
  }
  data$TyG_quartile <- cut(data$TyG, breaks = stats::quantile(data$TyG, probs = 0:4 / 4, na.rm = TRUE),
                           include.lowest = TRUE, labels = paste0("Q", 1:4))
  ctx$data$imputed <- data
  ctx$data$cleaned <- data
  ctx$results$competing_tyg <- list(visit_cols = visit_cols)
  cli::cli_alert_success("TyG 指数与轨迹分组完成")
  ctx
}

register_block("competing_tyg_compute", block_competing_tyg_compute, "TyG 指数计算")
