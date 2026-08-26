###############################################################################
#  cross_lagged_mediation — 抑郁症状中介（FI → Depression → CVD）
###############################################################################

block_cross_lagged_mediation <- function(ctx, ...) {
  bl <- ctx$config$cross_lagged %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("cross_lagged_mediation: 无数据", call. = FALSE)
  x <- bl$fi_var %||% "FI_T1"
  m <- bl$mediator_var %||% "Depression_T1"
  y <- bl$event_var %||% "CVD_event"
  if (!all(c(x, m, y) %in% names(data))) {
    cli::cli_alert_warning("中介变量缺失，跳过")
    return(ctx)
  }
  a_fit <- stats::lm(as.formula(paste(m, "~", x)), data = data)
  b_fit <- stats::glm(as.formula(paste(y, "~", x, "+", m)), data = data, family = binomial())
  a <- coef(a_fit)[x]
  b <- coef(b_fit)[m]
  indirect <- a * b
  tab <- data.frame(
    path = c("a: FI→Depression", "b: Depression→CVD|FI", "indirect"),
    estimate = c(a, b, indirect),
    stringsAsFactors = FALSE
  )
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Mediation_FI_Depression_CVD.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$cross_lagged_mediation <- list(table = tab)
  cli::cli_alert_success("中介分析完成")
  ctx
}

register_block("cross_lagged_mediation", block_cross_lagged_mediation, "抑郁中介 FI-CVD")
