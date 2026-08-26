###############################################################################
#  cits_sensitivity — Dobbs 截断日期敏感性
###############################################################################

block_cits_sensitivity <- function(ctx, ...) {
  bl <- ctx$config$cdc_wonder %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) stop("cits_sensitivity: 无数据", call. = FALSE)

  cutoffs <- bl$sensitivity_cutoffs %||% c("2022-09-01", "2022-10-01", "2022-11-01")
  date_col <- bl$date_col %||% "Birth_month"
  outcome <- bl$primary_outcome %||% "Congenital_anomaly"
  group_col <- bl$group_col %||% "Ban_state"

  rows <- list()
  for (cut in cutoffs) {
    d <- data
    d$month <- as.Date(paste0(d[[date_col]], "-01"))
    d$post <- as.integer(d$month >= as.Date(cut))
    d$ban <- as.integer(as.character(d[[group_col]]) %in% c("Ban", "1", "Yes"))
    if (!outcome %in% names(d)) next
    d$rate <- suppressWarnings(as.numeric(d[[outcome]]))
    fit <- tryCatch(stats::lm(rate ~ ban * post, data = d), error = function(e) NULL)
    if (is.null(fit)) next
    cf <- summary(fit)$coefficients
    if ("ban:post" %in% rownames(cf)) {
      rows[[length(rows) + 1L]] <- data.frame(
        cutoff = cut, term = "ban:post",
        estimate = cf["ban:post", 1], p_value = cf["ban:post", 4],
        stringsAsFactors = FALSE
      )
    }
  }
  sens_df <- if (length(rows)) do.call(rbind, rows) else data.frame()

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(sens_df, file.path(out_dir, "Table_CITS_Sensitivity_Cutoffs.csv"), row.names = FALSE)

  ctx$results$cits_sensitivity <- list(n_cutoffs = nrow(sens_df))
  cli::cli_alert_success("CITS 敏感性分析完成")
  ctx
}

register_block("cits_sensitivity", block_cits_sensitivity, "CITS 截断日期敏感性")
