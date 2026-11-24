###############################################################################
#  prepost_lmm_fit — Chen 2024 完整 piecewise LMM（参照无糖尿病组 + 聚类 SE）
###############################################################################

block_prepost_lmm_fit <- function(ctx, ...) {
  bl <- ctx$config$incidence_prepost %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_prepost_chen.R"), local = FALSE)
  data <- ctx$data$prepost_long %||% ctx$data$cleaned
  if (!"diabetes_grp" %in% names(data)) {
    data <- prepost_chen_build_composite(data, bl)
    data <- prepost_chen_piecewise_vars(data, bl)
    ctx$data$prepost_long <- data
  }
  outcome <- bl$global_cog_col %||% "Global_cognition_z"
  if (!outcome %in% names(data)) outcome <- "Global_cognition"

  res <- prepost_chen_fit_lmm(data, outcome, bl)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_PrePost_LMM_Global.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(res$table, out, row.names = FALSE)

  pred <- tryCatch(prepost_chen_predict_trajectory(data, res$fit, bl), error = function(e) NULL)
  if (!is.null(pred)) {
    utils::write.csv(pred, file.path(dirname(out), "Table_PrePost_Predicted_Trajectory.csv"), row.names = FALSE)
  }

  ctx$results$prepost_lmm_fit <- list(
    table = res$table, post_slope_change = res$post_slope, method = res$method
  )
  cli::cli_alert_success("Chen piecewise LMM ({res$method})")
  ctx
}

register_block("prepost_lmm_fit", block_prepost_lmm_fit, "Chen piecewise LMM")
