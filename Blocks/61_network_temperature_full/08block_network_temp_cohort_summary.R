###############################################################################
#  network_temp_cohort_summary — ABCD + ALSPAC + MCS 三队列温度趋势汇总
###############################################################################

block_network_temp_cohort_summary <- function(ctx, ...) {
  bl <- ctx$config$network_temperature %||% list()
  out_dir <- (ctx$results$network_temp_compute %||% list())$output_dir
  if (is.null(out_dir) || !dir.exists(out_dir))
    stop("network_temp_cohort_summary: 请先运行 network_temp_compute", call. = FALSE)

  ising_path <- file.path(out_dir, "Table_Network_Temperature_Ising_by_Wave.csv")
  if (!file.exists(ising_path)) stop("network_temp_cohort_summary: 缺少 Ising 温度表", call. = FALSE)
  temp_df <- utils::read.csv(ising_path, stringsAsFactors = FALSE)
  if (!"Cohort" %in% names(temp_df)) temp_df$Cohort <- "All"

  cohorts <- unique(temp_df$Cohort)
  rows <- list()
  for (co in cohorts) {
    sub <- temp_df[temp_df$Cohort == co & (is.na(temp_df$Subgroup) | temp_df$Subgroup == ""), , drop = FALSE]
    if (nrow(sub) < 2L) next
    fit <- stats::lm(network_temperature ~ Wave, data = sub)
    cf <- summary(fit)$coefficients
    rows[[length(rows) + 1L]] <- data.frame(
      Cohort = co, n_waves = nrow(sub),
      slope = cf["Wave", "Estimate"],
      slope_se = cf["Wave", "Std. Error"],
      slope_p = cf["Wave", "Pr(>|t|)"],
      T_wave1 = sub$network_temperature[sub$Wave == min(sub$Wave)][1L],
      T_wave_last = sub$network_temperature[sub$Wave == max(sub$Wave)][1L],
      delta_T = sub$network_temperature[sub$Wave == max(sub$Wave)][1L] -
        sub$network_temperature[sub$Wave == min(sub$Wave)][1L],
      stringsAsFactors = FALSE
    )
  }
  out_df <- if (length(rows)) do.call(rbind, rows) else data.frame()

  out_tab <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(out_df, file.path(out_tab, "Table_Network_Temperature_Cohort_Trends.csv"), row.names = FALSE)

  ctx$results$network_temp_cohort_summary <- out_df
  cli::cli_alert_success(paste0("三队列网络温度趋势汇总完成 (", nrow(out_df), " 队列)"))
  ctx
}

register_block("network_temp_cohort_summary", block_network_temp_cohort_summary, "三队列温度趋势")
