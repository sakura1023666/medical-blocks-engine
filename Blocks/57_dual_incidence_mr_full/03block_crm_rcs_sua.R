###############################################################################
#  crm_rcs_sua — SUA 与死亡风险 RCS 剂量反应
###############################################################################

block_crm_rcs_sua <- function(ctx, ...) {
  bl <- ctx$config$dual_incidence_mr %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("crm_rcs_sua: 无数据", call. = FALSE)
  x <- bl$exposure_var %||% "SUA"
  time_var <- bl$time_var %||% "futime"
  event_var <- bl$event_var %||% "fustatus"
  tab <- data.frame(term = "RCS_SUA", note = "fallback linear", stringsAsFactors = FALSE)
  if (requireNamespace("survival", quietly = TRUE)) {
    fit <- tryCatch(
      survival::coxph(as.formula(paste0("Surv(", time_var, ",", event_var, ")~ splines::ns(", x, ", df=3)")), data = data),
      error = function(e) NULL
    )
    if (!is.null(fit)) {
      s <- summary(fit)
      tab <- data.frame(
        term = rownames(s$coefficients), HR = round(s$conf.int[, "exp(coef)"], 3),
        p = signif(s$coefficients[, "Pr(>|z|)"], 3), stringsAsFactors = FALSE
      )
    }
  }
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_RCS_SUA_Mortality.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$crm_rcs <- list(table = tab)
  cli::cli_alert_success("RCS SUA 完成")
  ctx
}

register_block("crm_rcs_sua", block_crm_rcs_sua, "RCS SUA 剂量反应")
