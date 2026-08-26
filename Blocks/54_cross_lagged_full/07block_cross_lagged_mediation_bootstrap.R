###############################################################################
#  cross_lagged_mediation_bootstrap — 中介效应 Bootstrap 95% CI
###############################################################################

block_cross_lagged_mediation_bootstrap <- function(ctx, ...) {
  bl <- ctx$config$cross_lagged %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("cross_lagged_mediation_bootstrap: 无数据", call. = FALSE)
  x <- bl$fi_var %||% "FI_T1"
  m <- bl$mediator_var %||% "Depression_T1"
  y <- bl$event_var %||% "CVD_event"
  if (is.factor(data[[y]])) {
    case_lbl <- pipeline_outcome_case_label(ctx$config)
    data[[y]] <- as.integer(as.character(data[[y]]) == case_lbl)
  }
  n_boot <- as.integer(bl$mediation_boot_R %||% 500L)
  if (!all(c(x, m, y) %in% names(data))) return(ctx)
  d <- data[complete.cases(data[[x]], data[[m]], data[[y]]), , drop = FALSE]
  if (nrow(d) < 30L) {
    cli::cli_alert_warning("Bootstrap 中介: 样本不足")
    return(ctx)
  }
  stat_fn <- function(dat, idx) {
    dd <- dat[idx, , drop = FALSE]
    a <- tryCatch(coef(stats::lm(as.formula(paste(m, "~", x)), dd))[x], error = function(e) NA_real_)
    b <- tryCatch(coef(stats::glm(as.formula(paste(y, "~", x, "+", m)), dd, family = binomial()))[m], error = function(e) NA_real_)
    a * b
  }
  set.seed(bl$mediation_boot_seed %||% 42L)
  boots <- replicate(n_boot, stat_fn(d, sample.int(nrow(d), replace = TRUE)))
  boots <- boots[is.finite(boots)]
  tab <- data.frame(
    path = "indirect_bootstrap",
    estimate = mean(boots),
    ci_lower = stats::quantile(boots, 0.025),
    ci_upper = stats::quantile(boots, 0.975),
    n_boot = length(boots),
    stringsAsFactors = FALSE
  )
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Mediation_Bootstrap_CI.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$cross_lagged_mediation_boot <- list(table = tab)
  cli::cli_alert_success("中介 Bootstrap CI 完成 (R={n_boot})")
  ctx
}

register_block("cross_lagged_mediation_bootstrap", block_cross_lagged_mediation_bootstrap, "中介 Bootstrap CI")
