###############################################################################
#  cross_lagged_frailty_transition — 衰弱状态转换与 CVD（T1→T2）
###############################################################################

block_cross_lagged_frailty_transition <- function(ctx, ...) {
  bl <- ctx$config$cross_lagged %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("cross_lagged_frailty_transition: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  thr <- bl$fi_frailty_threshold %||% 0.25
  if ("FI_T1" %in% names(data) && "FI_T2" %in% names(data)) {
    s1 <- ifelse(data$FI_T1 >= thr, "Frail", "Non-frail")
    s2 <- ifelse(data$FI_T2 >= thr, "Frail", "Non-frail")
    data$Frailty_transition <- paste0(s1, "_to_", s2)
  }
  time_var <- bl$time_var %||% "futime"
  event_var <- bl$event_var %||% "CVD_event"
  if (is.factor(data[[event_var]])) {
    data[[event_var]] <- as.integer(as.character(data[[event_var]]) == pipeline_outcome_case_label(ctx$config))
  }
  rows <- list()
  for (tr in unique(data$Frailty_transition)) {
    sub <- data[data$Frailty_transition == tr, , drop = FALSE]
    if (nrow(sub) < 20L) next
    fit <- tryCatch(
      survival::coxph(as.formula(paste0("Surv(", time_var, ",", event_var, ")~ FI_T1")), data = sub),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    s <- summary(fit)
    rows[[length(rows) + 1L]] <- data.frame(
      transition = tr, n = nrow(sub),
      HR = round(s$conf.int["FI_T1", "exp(coef)"], 3),
      p = signif(s$coefficients["FI_T1", "Pr(>|z|)"], 3),
      stringsAsFactors = FALSE
    )
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "no transitions")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Frailty_Transition_Cox.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$cross_lagged_transition <- list(table = tab)
  cli::cli_alert_success("衰弱状态转换 Cox 完成")
  ctx
}

register_block("cross_lagged_frailty_transition", block_cross_lagged_frailty_transition, "衰弱状态转换")
