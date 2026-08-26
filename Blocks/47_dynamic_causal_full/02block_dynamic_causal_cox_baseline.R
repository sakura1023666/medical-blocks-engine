###############################################################################
#  dynamic_causal_cox_baseline — baseline CMI 三分位 Cox（复用 total 逻辑）
###############################################################################

block_dynamic_causal_cox_baseline <- function(ctx, ...) {
  ctx$config$dynamic_causal$analysis_type <- "baseline"
  if (!exists("block_dynamic_causal_analysis_filter", mode = "function")) {
    source(file.path(ctx$config$project$root %||% getwd(),
                     "Blocks/47_dynamic_causal_full/01block_dynamic_causal_analysis_filter.R"), local = TRUE)
  }
  ctx <- block_dynamic_causal_analysis_filter(ctx)
  if (!exists("block_dynamic_causal_cox_total", mode = "function")) {
    root <- ctx$config$project$root %||% getwd()
    source(file.path(root, "Blocks/43_dynamic_causal/02block_dynamic_causal_cox_total.R"), local = TRUE)
  }
  ctx <- block_dynamic_causal_cox_total(ctx)
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  src <- file.path(out_dir, "Table_Cox_Total_CMI.csv")
  dst <- file.path(out_dir, "Table_Cox_Baseline_CMI.csv")
  if (file.exists(src)) file.copy(src, dst, overwrite = TRUE)
  ctx$results$dynamic_causal_cox_baseline <- ctx$results$dynamic_causal_cox
  cli::cli_alert_success("Baseline CMI Cox 完成")
  ctx
}

register_block(
  "dynamic_causal_cox_baseline",
  block_dynamic_causal_cox_baseline,
  "Baseline CMI Cox 三分位"
)
