###############################################################################
#  competing_cox_sensitivity — 标准 Cox 敏感性（全因死亡）
###############################################################################

block_competing_cox_sensitivity <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("competing_cox_sensitivity: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  time_var <- bl$time_var %||% "futime"
  event_col <- bl$event_type_col %||% "event_type"
  exp_var <- bl$exposure_var %||% "TyG_quartile"
  death_cause <- as.integer(bl$death_cause %||% 2L)[1L]
  death_fallback <- if ("Death" %in% names(data)) (data$Death %in% 1) else rep(FALSE, nrow(data))
  data$evt_death <- as.integer(data[[event_col]] == death_cause | death_fallback)
  fit <- survival::coxph(as.formula(paste0("Surv(", time_var, ", evt_death)~", exp_var)), data = data)
  s <- summary(fit)
  tab <- data.frame(
    analysis = "standard_cox_mortality_sensitivity",
    term = rownames(s$coefficients), HR = round(s$conf.int[, "exp(coef)"], 3),
    p = signif(s$coefficients[, "Pr(>|z|)"], 3), stringsAsFactors = FALSE
  )
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables",
                    paste0("Table_Cox_Sensitivity_Mortality_", bl$index_var %||% "TyG", ".csv"))
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$competing_cox_sens <- list(table = tab)
  cli::cli_alert_success("标准 Cox 敏感性完成")
  ctx
}

register_block("competing_cox_sensitivity", block_competing_cox_sensitivity, "Cox 敏感性")
