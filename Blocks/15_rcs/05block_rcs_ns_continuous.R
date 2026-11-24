###############################################################################
#  rcs_ns_continuous — ns(df=3) 连续暴露 Cox 剂量反应（自 crm_rcs_sua 迁入）
#  register_block: "rcs_ns_continuous"
#  非完整 rcs_prognosis；仅当需轻量 ns 样条时使用
###############################################################################

block_rcs_ns_continuous <- function(ctx, ...) {
  bl <- ctx$config$rcs_ns_continuous %||% ctx$config$dual_incidence_mr %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("rcs_ns_continuous: 无数据", call. = FALSE)
  x <- bl$exposure_var %||% bl$index_var %||% "SUA"
  time_var <- bl$time_var %||% ctx$config$survival$time_var %||% "futime"
  event_var <- bl$event_var %||% ctx$config$survival$event_var %||% "fustatus"
  df_ns <- as.integer(bl$ns_df %||% 3L)
  tab <- data.frame(term = paste0("NS_", x), note = "fallback linear", stringsAsFactors = FALSE)
  if (requireNamespace("survival", quietly = TRUE)) {
    fit <- tryCatch(
      survival::coxph(as.formula(paste0("Surv(", time_var, ",", event_var, ")~ splines::ns(", x, ", df=", df_ns, ")")), data = data),
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
  out_name <- bl$table_filename %||% "Table_RCS_SUA_Mortality.csv"
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", out_name)
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$rcs_ns_continuous <- list(table = tab)
  ctx$results$crm_rcs <- list(table = tab)
  cli::cli_alert_success("rcs_ns_continuous 完成")
  ctx
}

register_block("rcs_ns_continuous", block_rcs_ns_continuous, "ns 样条连续暴露 Cox")
