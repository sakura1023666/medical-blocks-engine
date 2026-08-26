###############################################################################
#  cross_lagged_sensitivity — 敏感性（竞争风险/重算FI/排除高血压糖尿病）
###############################################################################

block_cross_lagged_sensitivity <- function(ctx, ...) {
  bl <- ctx$config$cross_lagged %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("cross_lagged_sensitivity: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  fi_var <- bl$fi_var %||% "FI_T1"
  time_var <- bl$time_var %||% "futime"
  event_var <- bl$event_var %||% "CVD_event"
  if (is.factor(data[[event_var]])) {
    data[[event_var]] <- as.integer(as.character(data[[event_var]]) == pipeline_outcome_case_label(ctx$config))
  }
  .cox_hr <- function(d, ev = event_var) {
    d <- d[complete.cases(d[[time_var]], d[[ev]], d[[fi_var]]), , drop = FALSE]
    if (nrow(d) < 20L) return(NA_real_)
    fit <- tryCatch(survival::coxph(as.formula(paste0("Surv(", time_var, ",", ev, ")~", fi_var)), data = d), error = function(e) NULL)
    if (is.null(fit)) return(NA_real_)
  round(summary(fit)$conf.int[fi_var, "exp(coef)"], 3)
  }
  scenarios <- list(
    primary = data,
    exclude_htn_dm = data[!(data$Hypertension_T1 %in% 1) & !(data$Diabetes_T1 %in% 1), , drop = FALSE],
    recalc_fi_no_comorb = {
      d <- data
      if (all(c("Mobility_T1") %in% names(d))) d$FI_T1 <- as.integer(d$Mobility_T1 >= 4) / 1
      d
    }
  )
  if ("Death_competing" %in% names(data)) {
    d <- data; d$CVD_only <- as.integer(d[[event_var]] == 1L & (is.na(d$Death_competing) | d$Death_competing == 0))
    scenarios$competing_risk <- d
  }
  tab <- do.call(rbind, lapply(names(scenarios), function(nm) {
    hr <- if (nm == "competing_risk") .cox_hr(scenarios[[nm]], "CVD_only") else .cox_hr(scenarios[[nm]])
    data.frame(scenario = nm, HR = hr, n = nrow(scenarios[[nm]]), stringsAsFactors = FALSE)
  }))
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Sensitivity_Frailty_CVD.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$cross_lagged_sensitivity <- list(table = tab)
  cli::cli_alert_success("敏感性分析完成")
  ctx
}

register_block("cross_lagged_sensitivity", block_cross_lagged_sensitivity, "敏感性分析")
