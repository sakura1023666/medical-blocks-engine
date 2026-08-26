###############################################################################
#  ai_guideline_audit — 指南依从性审计（Python）
###############################################################################

block_ai_guideline_audit <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  cases <- ai_clinical_cases_path(ctx)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "AI_Guideline")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  run_literature_python(root, "ai_guideline_audit", c("--out-dir", out, "--data-path", cases))
  ctx$results$ai_guideline <- list(output_dir = out)
  cli::cli_alert_success("指南依从性审计完成")
  ctx
}

register_block("ai_guideline_audit", block_ai_guideline_audit, "指南依从审计")
