###############################################################################
#  tte_sensitivity — Nie 2025 七项敏感性分析
###############################################################################

block_tte_sensitivity <- function(ctx, ...) {
  bl <- ctx$config$target_trial %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_tte_nie.R"), local = FALSE)
  data <- ctx$data$tte_weighted %||% ctx$data$tte_trials %||% ctx$data$cleaned
  tab <- tte_nie_sensitivity_suite(data, bl)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_TTE_Sensitivity.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$tte_sensitivity <- list(table = tab)
  cli::cli_alert_success("TTE 七项敏感性完成")
  ctx
}

register_block("tte_sensitivity", block_tte_sensitivity, "TTE 七项敏感性")
