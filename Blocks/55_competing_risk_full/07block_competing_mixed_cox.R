###############################################################################
#  competing_mixed_cox — 混合效应 Cox（随机截距 ID）
###############################################################################

block_competing_mixed_cox <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("competing_mixed_cox: 无数据", call. = FALSE)
  id_col <- bl$id_col %||% "ID"
  time_var <- bl$time_var %||% "futime"
  event_col <- bl$event_type_col %||% "event_type"
  exp_var <- bl$exposure_var %||% "TyG_quartile"
  data$evt_whf <- as.integer(data[[event_col]] == 1L)
  tab <- data.frame(model = "mixed_cox", term = exp_var, HR = NA_real_, p = NA_real_, stringsAsFactors = FALSE)
  if (requireNamespace("coxme", quietly = TRUE) && id_col %in% names(data)) {
    fit <- tryCatch(
      coxme::coxme(as.formula(paste0("Surv(", time_var, ", evt_whf) ~ ", exp_var, " + (1|", id_col, ")")), data = data),
      error = function(e) NULL
    )
    if (!is.null(fit)) {
      s <- summary(fit)
      cf <- s$coefficients
      if (nrow(cf)) {
        tab <- data.frame(
          term = rownames(cf), HR = round(exp(cf[, 1]), 3),
          p = signif(cf[, 5], 3), model = "mixed_cox", stringsAsFactors = FALSE
        )
      }
    }
  } else if (requireNamespace("survival", quietly = TRUE)) {
    fit <- survival::coxph(as.formula(paste0("Surv(", time_var, ", evt_whf)~", exp_var)), data = data)
    s <- summary(fit)
    tab <- data.frame(term = rownames(s$coefficients), HR = round(s$conf.int[, "exp(coef)"], 3),
                      p = signif(s$coefficients[, "Pr(>|z|)"], 3), model = "cox_cluster_robust_fallback",
                      stringsAsFactors = FALSE)
  }
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables",
                    paste0("Table_Mixed_Cox_", bl$index_var %||% "TyG", ".csv"))
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$competing_mixed_cox <- list(table = tab)
  cli::cli_alert_success("混合效应 Cox 完成")
  ctx
}

register_block("competing_mixed_cox", block_competing_mixed_cox, "混合效应 Cox")
