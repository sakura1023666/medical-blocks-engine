###############################################################################
#  cross_lagged_meta_merge — 队列间 HR Meta 合并（逆方差加权）
###############################################################################

block_cross_lagged_meta_merge <- function(ctx, ...) {
  bl <- ctx$config$cross_lagged %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("cross_lagged_meta_merge: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  cohort_col <- bl$cohort_col %||% "Cohort"
  fi_var <- bl$fi_var %||% "FI_T1"
  time_var <- bl$time_var %||% "futime"
  event_var <- bl$event_var %||% "CVD_event"
  if (is.factor(data[[event_var]])) {
    data[[event_var]] <- as.integer(as.character(data[[event_var]]) == pipeline_outcome_case_label(ctx$config))
  }
  est <- se <- cohort <- character(0)
  for (co in unique(data[[cohort_col]])) {
    sub <- data[data[[cohort_col]] == co, , drop = FALSE]
    if (nrow(sub) < 30L) next
    fit <- tryCatch(
      survival::coxph(as.formula(paste0("Surv(", time_var, ",", event_var, ")~", fi_var)), data = sub),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    s <- summary(fit)
    est <- c(est, s$coefficients[fi_var, "coef"])
    se <- c(se, s$coefficients[fi_var, "se(coef)"])
    cohort <- c(cohort, co)
  }
  tab_cohort <- data.frame(cohort = cohort, logHR = est, se = se, HR = round(exp(est), 3), stringsAsFactors = FALSE)
  pooled <- NA_real_
  if (length(est) >= 2L) {
    w <- 1 / se^2
    pooled <- sum(w * est) / sum(w)
    se_pooled <- sqrt(1 / sum(w))
    tab_pool <- data.frame(
      cohort = "Pooled_IVW", logHR = pooled, se = se_pooled,
      HR = round(exp(pooled), 3), ci_lower = round(exp(pooled - 1.96 * se_pooled), 3),
      ci_upper = round(exp(pooled + 1.96 * se_pooled), 3), stringsAsFactors = FALSE
    )
    tab_cohort <- rbind(tab_cohort, tab_pool)
  }
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Meta_Cohort_Pooled.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab_cohort, out, row.names = FALSE)
  ctx$results$cross_lagged_meta <- list(table = tab_cohort)
  cli::cli_alert_success("队列 Meta 合并完成")
  ctx
}

register_block("cross_lagged_meta_merge", block_cross_lagged_meta_merge, "队列 Meta 合并")
