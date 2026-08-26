###############################################################################
#  tte_risk_difference — 累积发病率与风险差
###############################################################################

block_tte_risk_difference <- function(ctx, ...) {
  bl <- ctx$config$target_trial %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_tte_nie.R"), local = FALSE)
  data <- ctx$data$tte_weighted %||% ctx$data$tte_trials %||% ctx$data$cleaned
  unit <- (ctx$config$study_batch$active_unit %||% "Overall")
  outcome <- if (unit == "Death_180d" && "Death_180d" %in% names(data)) {
    data$`.tte_out180` <- as.integer(data$Death_180d); ".tte_out180"
  } else ".tte_out"
  tab <- tte_nie_risk_difference(data, outcome, ".tte_trt", "sw")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_TTE_Risk_Difference.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$tte_risk_difference <- list(table = tab, disc_inc = tab$cumulative_incidence[2], cont_inc = tab$cumulative_incidence[1])
  cli::cli_alert_success("TTE 风险差估计完成")
  ctx
}

register_block("tte_risk_difference", block_tte_risk_difference, "TTE 风险差")
