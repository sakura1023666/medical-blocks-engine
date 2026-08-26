###############################################################################
#  dcs_descriptive — 基线抑郁与认知横断面关联
###############################################################################

block_dcs_descriptive <- function(ctx, ...) {
  bl <- ctx$config$dual_change_score %||% list()
  data <- ctx$data$dcs_long %||% ctx$data$cleaned
  wave_col <- bl$wave_col %||% "Wave"
  base <- data[data[[wave_col]] == min(data[[wave_col]], na.rm = TRUE), , drop = FALSE]
  dep <- bl$depression_col %||% "CESD_total"
  mem <- bl$memory_col %||% "Memory_score"
  flu <- bl$fluency_col %||% "Verbal_fluency"
  fit_m <- tryCatch(stats::lm(stats::as.formula(paste(mem, "~", dep)), data = base), error = function(e) NULL)
  fit_f <- tryCatch(stats::lm(stats::as.formula(paste(flu, "~", dep)), data = base), error = function(e) NULL)
  tab <- data.frame(
    outcome = c("Memory", "Verbal_fluency"),
    intercept_beta = c(if (!is.null(fit_m)) coef(fit_m)[1] else NA, if (!is.null(fit_f)) coef(fit_f)[1] else NA),
    dep_beta = c(if (!is.null(fit_m)) coef(fit_m)[2] else NA, if (!is.null(fit_f)) coef(fit_f)[2] else NA),
    stringsAsFactors = FALSE
  )
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_DCS_Baseline_Cross.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$dcs_descriptive <- list(table = tab)
  cli::cli_alert_success("DCS 基线横断面完成")
  ctx
}

register_block("dcs_descriptive", block_dcs_descriptive, "DCS 描述")
