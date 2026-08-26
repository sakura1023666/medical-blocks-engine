###############################################################################
#  bayesian_bsc_aging — 器官特异性 Clock + 衰老速率（Age ~ Clock）
###############################################################################

block_bayesian_bsc_aging <- function(ctx, ...) {
  bl <- ctx$config$bayesian_comorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("bayesian_bsc_aging: 无数据", call. = FALSE)

  sys_cols <- bl$system_severity_cols %||% grep("_sev$", names(data), value = TRUE)
  age_col <- bl$age_col %||% "Age"
  if (!age_col %in% names(data)) stop("bayesian_bsc_aging: 缺少 Age 列", call. = FALSE)

  bsc_rows <- list()
  rate_rows <- list()
  for (sc in sys_cols) {
    bsc_name <- sub("_sev$", "_BSC", sc)
    data[[bsc_name]] <- as.numeric(data[[sc]]) * (data$Body_Clock %||% data$BODN)
    fit <- tryCatch(stats::lm(stats::as.formula(paste(age_col, "~", bsc_name)), data = data),
                    error = function(e) NULL)
    if (!is.null(fit)) {
      cf <- stats::coef(fit)
      if (length(cf) >= 2L) {
        rate_rows[[length(rate_rows) + 1L]] <- data.frame(
          clock = bsc_name, aging_rate = unname(cf[2L]), stringsAsFactors = FALSE
        )
      }
    }
    bsc_rows[[length(bsc_rows) + 1L]] <- data.frame(
      system = sc, mean_bsc = mean(data[[bsc_name]], na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }

  if ("Body_Clock" %in% names(data)) {
    fit_bc <- tryCatch(stats::lm(stats::as.formula(paste(age_col, "~ Body_Clock")), data = data),
                       error = function(e) NULL)
    if (!is.null(fit_bc)) {
      cf <- stats::coef(fit_bc)
      if (length(cf) >= 2L) {
        rate_rows[[length(rate_rows) + 1L]] <- data.frame(
          clock = "Body_Clock", aging_rate = unname(cf[2L]), stringsAsFactors = FALSE
        )
      }
    }
  }

  ctx$data$imputed <- data
  ctx$data$cleaned <- data
  bsc_tab <- if (length(bsc_rows)) do.call(rbind, bsc_rows) else data.frame(note = "none")
  rate_tab <- if (length(rate_rows)) do.call(rbind, rate_rows) else data.frame(note = "none")
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(bsc_tab, file.path(out_dir, "Table_BSC_Summary.csv"), row.names = FALSE)
  utils::write.csv(rate_tab, file.path(out_dir, "Table_Aging_Rate.csv"), row.names = FALSE)
  ctx$results$bayesian_bsc_aging <- list(bsc = bsc_tab, aging_rate = rate_tab)
  cli::cli_alert_success("BSC + 衰老速率回归完成")
  ctx
}

register_block("bayesian_bsc_aging", block_bayesian_bsc_aging, "器官 Clock 与衰老速率")
