###############################################################################
#  cross_lagged_km — Kaplan-Meier 按衰弱分层
###############################################################################

block_cross_lagged_km <- function(ctx, ...) {
  bl <- ctx$config$cross_lagged %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("cross_lagged_km: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  strata_col <- bl$frailty_status_col %||% "Frailty_status_T1"
  if (!strata_col %in% names(data) && "FI_T1" %in% names(data))
    data[[strata_col]] <- ifelse(data$FI_T1 >= 0.25, "Frail", "Non-frail")
  time_var <- bl$time_var %||% "futime"
  event_var <- bl$event_var %||% "CVD_event"
  if (!event_var %in% names(data) && "fustatus" %in% names(data)) event_var <- "fustatus"
  data[[time_var]] <- as.numeric(data[[time_var]])
  if (is.factor(data[[event_var]])) {
    case_lbl <- pipeline_outcome_case_label(ctx$config)
    data[[event_var]] <- as.integer(as.character(data[[event_var]]) == case_lbl)
  } else {
    data[[event_var]] <- as.integer(as.character(data[[event_var]]))
  }
  keep <- complete.cases(data[[time_var]], data[[event_var]])
  data <- data[keep, , drop = FALSE]
  fit <- NULL
  if (!nrow(data)) {
    cli::cli_alert_warning("KM: 无有效生存观测，写占位表")
    tab <- data.frame(note = "no valid observations", stringsAsFactors = FALSE)
  } else {
    fit <- survival::survfit(as.formula(paste0("Surv(", time_var, ",", event_var, ")~", strata_col)), data = data)
    sm <- summary(fit)
    strata_names <- names(sm$strata)
    if (length(strata_names)) {
      tab <- data.frame(
        strata = strata_names,
        n = as.integer(sm$strata),
        median_survival = if (length(sm$median)) sm$median else NA_real_,
        stringsAsFactors = FALSE
      )
    } else {
      tab <- data.frame(strata = "All", n = nrow(data), median_survival = NA_real_, stringsAsFactors = FALSE)
    }
  }
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_KM_Frailty_Strata.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  if (!is.null(fit)) {
    fig_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Figures")
    dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
    pdf(file.path(fig_dir, "KM_Frailty_CVD.pdf"), width = 6, height = 5)
    plot(fit, main = "KM by Frailty", xlab = "Years", ylab = "CVD-free survival")
    dev.off()
  }
  ctx$results$cross_lagged_km <- list(table = tab)
  cli::cli_alert_success("KM 曲线完成")
  ctx
}

register_block("cross_lagged_km", block_cross_lagged_km, "KM 衰弱分层")
