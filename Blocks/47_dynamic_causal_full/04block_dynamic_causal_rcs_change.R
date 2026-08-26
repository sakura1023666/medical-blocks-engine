###############################################################################
#  dynamic_causal_rcs_change — change 队列 RCS（预后 Cox 样条）
###############################################################################

block_dynamic_causal_rcs_change <- function(ctx, ...) {
  ctx$config$dynamic_causal$analysis_type <- "change"
  if (exists("block_dynamic_causal_analysis_filter", mode = "function")) {
    ctx <- block_dynamic_causal_analysis_filter(ctx)
  }
  if (!exists("block_rcs_prognosis", mode = "function")) {
    root <- ctx$config$project$root %||% getwd()
    source(file.path(root, "Blocks/15_rcs/01block_rcs_prognosis.R"), local = TRUE)
  }
  block_rcs_prognosis(ctx, ...)
}

register_block(
  "dynamic_causal_rcs_change",
  block_dynamic_causal_rcs_change,
  "Total/baseline CMI change 队列 RCS"
)
