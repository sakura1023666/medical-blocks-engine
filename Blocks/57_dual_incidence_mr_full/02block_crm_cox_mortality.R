###############################################################################
#  crm_cox_mortality — SUA/高尿酸与全因死亡 Cox
###############################################################################

block_crm_cox_mortality <- function(ctx, ...) {
  bl <- ctx$config$dual_incidence_mr %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("crm_cox_mortality: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  x <- bl$exposure_var %||% "SUA"
  time_var <- bl$time_var %||% "futime"
  event_var <- bl$event_var %||% "fustatus"
  covs <- intersect(c("Age", "Gender"), names(data))
  fit <- survival::coxph(
    as.formula(paste0("Surv(", time_var, ",", event_var, ")~", x,
                      if (length(covs)) paste("+", paste(covs, collapse = "+")) else "")),
    data = data
  )
  s <- summary(fit)
  tab <- data.frame(
    term = rownames(s$coefficients), HR = round(s$conf.int[, "exp(coef)"], 3),
    lower = round(s$conf.int[, "lower .95"], 3), upper = round(s$conf.int[, "upper .95"], 3),
    p = signif(s$coefficients[, "Pr(>|z|)"], 3), stringsAsFactors = FALSE
  )
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Cox_Mortality_SUA.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$crm_cox <- list(table = tab)
  cli::cli_alert_success("Cox 全因死亡完成")
  ctx
}

register_block("crm_cox_mortality", block_crm_cox_mortality, "Cox 全因死亡")
