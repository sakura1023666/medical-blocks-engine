###############################################################################
#  ai_lab_interpret — 化验解读评测（Python）
###############################################################################

block_ai_lab_interpret <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  cases <- ai_clinical_cases_path(ctx)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "AI_Lab")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  run_literature_python(root, "ai_lab_interpret", c("--out-dir", out, "--data-path", cases))
  ctx$results$ai_lab <- list(output_dir = out)
  cli::cli_alert_success("化验解读评测完成")
  ctx
}

register_block("ai_lab_interpret", block_ai_lab_interpret, "化验解读")
