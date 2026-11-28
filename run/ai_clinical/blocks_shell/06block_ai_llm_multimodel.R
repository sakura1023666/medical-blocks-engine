###############################################################################
#  ai_llm_multimodel — Llama2/OASST/WizardLM 多模型评测（Python）
###############################################################################

block_ai_llm_multimodel <- function(ctx, ...) {
  bl <- ctx$config$ai_clinical %||% list()
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  cases <- ai_clinical_cases_path(ctx)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "AI_LLM_Models")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  models <- paste(bl$llm_models %||% c("Llama2_Chat", "OASST", "WizardLM"), collapse = ",")
  run_literature_python(root, "ai_llm_models", c(
    "--out-dir", out, "--data-path", cases,
    "--outcome-col", bl$diagnosis_col %||% "true_diagnosis",
    "--genes", models
  ), timeout_sec = 1800L)
  ctx$results$ai_llm_models <- list(output_dir = out)
  cli::cli_alert_success("多 LLM 模型评测完成")
  ctx
}

register_block("ai_llm_multimodel", block_ai_llm_multimodel, "多 LLM 评测")
