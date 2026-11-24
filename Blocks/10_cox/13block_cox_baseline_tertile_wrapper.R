###############################################################################
#  cox_tertile_baseline_wrapper — baseline CMI 三分位 Cox（复用 total 逻辑）
###############################################################################

block_cox_tertile_baseline_wrapper <- function(ctx, ...) {
  ctx$config$dynamic_causal$analysis_type <- "baseline"
  if (!exists("block_dynamic_causal_analysis_filter", mode = "function")) {
    source(file.path(ctx$config$project$root %||% getwd(),
                     "Blocks/43_dynamic_causal/01block_dynamic_causal_analysis_filter.R"), local = TRUE)
  }
  ctx <- block_dynamic_causal_analysis_filter(ctx)
  if (!exists("block_cox_tertile_continuous", mode = "function")) {
    root <- ctx$config$project$root %||% getwd()
    source(file.path(root, "Blocks/10_cox/12block_cox_tertile_continuous.R"), local = TRUE)
  }
  ctx <- block_cox_tertile_continuous(ctx)
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  src <- file.path(out_dir, "Table_Cox_Total_CMI.csv")
  dst <- file.path(out_dir, "Table_Cox_Baseline_CMI.csv")
  if (file.exists(src)) file.copy(src, dst, overwrite = TRUE)
  ctx$results$cox_tertile_baseline_wrapper <- ctx$results$dynamic_causal_cox
  cli::cli_alert_success("Baseline CMI Cox 完成")
  ctx
}

register_block(
  "cox_tertile_baseline_wrapper",
  block_cox_tertile_baseline_wrapper,
  "Baseline CMI Cox 三分位"
)
