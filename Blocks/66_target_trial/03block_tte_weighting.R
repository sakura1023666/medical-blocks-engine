###############################################################################
#  tte_weighting — stabilized IPTW + IPCW（MSM 权重）
###############################################################################

block_tte_weighting <- function(ctx, ...) {
  bl <- ctx$config$target_trial %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_tte_nie.R"), local = FALSE)
  data <- ctx$data$tte_trials %||% ctx$data$cleaned
  if (!"Trial_id" %in% names(data)) {
    if ("Database" %in% names(data)) {
      data <- tte_nie_harmonize_columns(data, bl$database_col %||% "Database")
    }
    data <- tte_nie_sequential_clone(data, bl)
    data$`.tte_out` <- as.integer(data$Death_30d)
    data$`.tte_trt` <- as.integer(data$Treatment_discontinue)
  }
  treat <- ".tte_trt"
  covs <- intersect(tte_nie_full_covariates(), names(data))
  if (!length(covs)) covs <- intersect(bl$covariates %||% character(0), names(data))
  data <- tte_nie_stabilized_weights(data, treat, covs, time_col = "Trial_day")
  ctx$data$tte_weighted <- data

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_TTE_MSM_Weights.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  out_cols <- intersect(c("Trial_id", "Trial_day", treat, "ps", "sw", "ipcw"), names(data))
  utils::write.csv(data[, out_cols, drop = FALSE], out, row.names = FALSE)
  ctx$results$tte_weighting <- list(mean_sw = mean(data$sw, na.rm = TRUE))
  cli::cli_alert_success("IPTW+IPCW 权重完成")
  ctx
}

register_block("tte_weighting", block_tte_weighting, "TTE MSM 加权")
