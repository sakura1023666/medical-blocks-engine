###############################################################################
#  competing_ph_calibration — PH 检验与校准（十分位）
###############################################################################

block_competing_ph_calibration <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("competing_ph_calibration: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  time_var <- bl$time_var %||% "futime"
  event_col <- bl$event_type_col %||% "event_type"
  exp_var <- bl$index_var %||% bl$tyg_var %||% "TyG"
  cc <- stats::complete.cases(data[c(exp_var, time_var, event_col)])
  data <- data[cc, , drop = FALSE]
  data$evt_whf <- as.integer(data[[event_col]] == 1L)
  fit <- survival::coxph(as.formula(paste0("Surv(", time_var, ", evt_whf)~", exp_var)), data = data)
  ph <- survival::cox.zph(fit)
  tab_ph <- data.frame(term = rownames(ph$table), chisq = round(ph$table[, 1], 3),
                       p = signif(ph$table[, 3], 3), stringsAsFactors = FALSE)
  risk <- predict(fit, type = "risk")
  data$risk_decile <- cut(risk, breaks = stats::quantile(risk, 0:10 / 10, na.rm = TRUE),
                          include.lowest = TRUE, labels = paste0("D", 1:10))
  cal <- aggregate(cbind(predicted = risk, observed = data$evt_whf) ~ risk_decile, data = data, mean)
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab_ph, file.path(out_dir, paste0("Table_PH_Test_", exp_var, ".csv")), row.names = FALSE)
  utils::write.csv(cal, file.path(out_dir, paste0("Table_Calibration_Deciles_", exp_var, ".csv")), row.names = FALSE)
  ctx$results$competing_ph_cal <- list(ph = tab_ph, calibration = cal)
  cli::cli_alert_success("PH 检验与校准完成")
  ctx
}

register_block("competing_ph_calibration", block_competing_ph_calibration, "PH 检验与校准")
