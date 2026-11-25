###############################################################################
#  competing_ph_calibration — PH 检验与校准（十分位）
###############################################################################

block_competing_ph_calibration <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) stop("competing_ph_calibration: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  time_var <- bl$time_var %||% "futime"
  event_col <- bl$event_type_col %||% "event_type"
  exp_var <- bl$index_var %||% bl$tyg_var %||% "TyG"
  need <- c(exp_var, time_var, event_col)
  if (!all(need %in% names(data))) {
    cli::cli_alert_warning(
      "competing_ph_calibration: 缺列 {paste(setdiff(need, names(data)), collapse=', ')}，跳过"
    )
    return(ctx)
  }
  cc <- stats::complete.cases(data[need])
  data <- data[cc, , drop = FALSE]
  if (nrow(data) < 30L) {
    cli::cli_alert_warning("competing_ph_calibration: 完整病例过少（n={nrow(data)}），跳过")
    return(ctx)
  }
  primary <- as.integer(bl$primary_cause %||% 1L)[1L]
  data$evt_primary <- as.integer(data[[event_col]] == primary)
  if (sum(data$evt_primary, na.rm = TRUE) < 5L) {
    cli::cli_alert_warning("competing_ph_calibration: 主事件过少，跳过")
    return(ctx)
  }
  fit <- tryCatch(
    survival::coxph(
      stats::as.formula(paste0("Surv(", time_var, ", evt_primary)~", exp_var)),
      data = data
    ),
    error = function(e) NULL
  )
  if (is.null(fit)) {
    cli::cli_alert_warning("competing_ph_calibration: coxph 失败，跳过")
    return(ctx)
  }
  ph <- tryCatch(survival::cox.zph(fit), error = function(e) NULL)
  tab_ph <- if (!is.null(ph)) {
    data.frame(
      term = rownames(ph$table),
      chisq = round(ph$table[, 1], 3),
      p = signif(ph$table[, 3], 3),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(term = character(0), chisq = numeric(0), p = numeric(0))
  }

  risk <- as.numeric(stats::predict(fit, type = "risk"))
  # 十分位：risk 并列时 quantile 断点会重复 → cut 报 subscript out of bounds
  br <- unique(as.numeric(stats::quantile(risk, probs = seq(0, 1, by = 0.1), na.rm = TRUE, type = 7)))
  cal <- NULL
  if (length(br) >= 3L) {
    n_bin <- length(br) - 1L
    data$risk_decile <- cut(
      risk, breaks = br, include.lowest = TRUE,
      labels = paste0("D", seq_len(n_bin))
    )
    cal <- stats::aggregate(
      cbind(predicted = risk, observed = data$evt_primary) ~ risk_decile,
      data = data, FUN = mean
    )
  } else {
    cli::cli_alert_warning("competing_ph_calibration: 风险分层不足（并列过多），跳过校准表")
  }

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab_ph, file.path(out_dir, paste0("Table_PH_Test_", exp_var, ".csv")), row.names = FALSE)
  if (!is.null(cal)) {
    utils::write.csv(cal, file.path(out_dir, paste0("Table_Calibration_Deciles_", exp_var, ".csv")), row.names = FALSE)
  }
  ctx$results$competing_ph_cal <- list(ph = tab_ph, calibration = cal)
  cli::cli_alert_success("PH 检验与校准完成")
  ctx
}

register_block("competing_ph_calibration", block_competing_ph_calibration, "PH 检验与校准")
