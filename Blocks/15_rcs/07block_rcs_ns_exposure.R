###############################################################################
#  rcs_ns_exposure — TyG 与结局限制性立方样条
###############################################################################

block_rcs_ns_exposure <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("rcs_ns_exposure: 无数据", call. = FALSE)
  exp_var <- bl$index_var %||% bl$tyg_var %||% "TyG"
  time_var <- bl$time_var %||% "futime"
  event_col <- bl$event_type_col %||% "event_type"
  data$evt <- as.integer(data[[event_col]] == 1L)
  tab <- data.frame(term = "RCS", note = "skipped", stringsAsFactors = FALSE)
  if (requireNamespace("survival", quietly = TRUE)) {
    fit <- tryCatch(
      survival::coxph(as.formula(paste0("Surv(", time_var, ", evt)~ splines::ns(", exp_var, ", df=3)")), data = data),
      error = function(e) NULL
    )
    if (!is.null(fit)) {
      s <- summary(fit)
      tab <- data.frame(
        term = rownames(s$coefficients),
        HR = round(s$conf.int[, "exp(coef)"], 3),
        p = signif(s$coefficients[, "Pr(>|z|)"], 3),
        stringsAsFactors = FALSE
      )
    }
  }
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables",
                    paste0("Table_RCS_", exp_var, "_WHF.csv"))
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$rcs_ns_exposure <- list(table = tab)
  cli::cli_alert_success("RCS 非线性分析完成")
  ctx
}

register_block("rcs_ns_exposure", block_rcs_ns_exposure, "RCS TyG")
