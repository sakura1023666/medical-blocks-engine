###############################################################################
#  tte_pooled_logistic — pooled logistic + sandwich 聚类 SE
###############################################################################

block_tte_pooled_logistic <- function(ctx, ...) {
  bl <- ctx$config$target_trial %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_tte_nie.R"), local = FALSE)
  data <- ctx$data$tte_weighted %||% ctx$data$tte_trials %||% ctx$data$cleaned
  unit <- (ctx$config$study_batch$active_unit %||% "Overall")
  outcome <- if (unit == "Death_180d") ".tte_out180" else ".tte_out"
  if (unit == "Death_180d" && "Death_180d" %in% names(data)) data$`.tte_out180` <- as.integer(data$Death_180d)
  if (!outcome %in% names(data)) outcome <- ".tte_out"
  covs <- intersect(tte_nie_full_covariates(), names(data))
  res <- tte_nie_pooled_logistic(data, outcome, ".tte_trt", covs, "sw", "Patient_ID")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_TTE_Pooled_Logistic.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(res$table, out, row.names = FALSE)
  ctx$results$tte_pooled_logistic <- list(table = res$table, outcome = outcome)
  cli::cli_alert_success("Pooled logistic + sandwich SE 完成")
  ctx
}

register_block("tte_pooled_logistic", block_tte_pooled_logistic, "TTE pooled logistic")
