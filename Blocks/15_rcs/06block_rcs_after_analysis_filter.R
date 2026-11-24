###############################################################################
#  rcs_after_analysis_filter — change 队列 RCS（预后 Cox 样条）
###############################################################################

block_rcs_after_analysis_filter <- function(ctx, ...) {
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
  "rcs_after_analysis_filter",
  block_rcs_after_analysis_filter,
  "Total/baseline CMI change 队列 RCS"
)
