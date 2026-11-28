###############################################################################
#  crm_gout_strata — 痛风/无症状高尿酸分层 Cox
###############################################################################

block_crm_gout_strata <- function(ctx, ...) {
  bl <- ctx$config$dual_incidence_mr %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("crm_gout_strata: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  if (!"Gout_group" %in% names(data)) {
    data$Gout_group <- ifelse(data$Gout %in% 1, "Gout",
      ifelse(data$Hyperuricemia %in% 1, "Asymptomatic_hyperuricemia", "Normal_SUA"))
  }
  time_var <- bl$time_var %||% "futime"
  event_var <- bl$event_var %||% "fustatus"
  x <- bl$exposure_var %||% "SUA"
  rows <- list()
  for (lv in unique(data$Gout_group)) {
    sub <- data[data$Gout_group == lv, , drop = FALSE]
    if (nrow(sub) < 20L) next
    fit <- tryCatch(survival::coxph(as.formula(paste0("Surv(", time_var, ",", event_var, ")~", x)), data = sub), error = function(e) NULL)
    if (is.null(fit)) next
    s <- summary(fit)
    rows[[length(rows) + 1L]] <- data.frame(
      stratum = lv, n = nrow(sub), HR = round(s$conf.int[x, "exp(coef)"], 3),
      p = signif(s$coefficients[x, "Pr(>|z|)"], 3), stringsAsFactors = FALSE
    )
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "no strata")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Gout_Strata_Cox.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$crm_gout_strata <- list(table = tab)
  cli::cli_alert_success("痛风/高尿酸分层完成")
  ctx
}

register_block("crm_gout_strata", block_crm_gout_strata, "痛风分层")
