###############################################################################
#  ai_order_robustness — 信息顺序/数量鲁棒性（Python）
###############################################################################

block_ai_order_robustness <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  cases <- ai_clinical_cases_path(ctx)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "AI_Robustness")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  run_literature_python(root, "ai_order_robustness", c("--out-dir", out, "--data-path", cases))
  ctx$results$ai_robustness <- list(output_dir = out)
  cli::cli_alert_success("信息顺序鲁棒性完成")
  ctx
}

register_block("ai_order_robustness", block_ai_order_robustness, "信息顺序鲁棒性")
