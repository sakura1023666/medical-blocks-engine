###############################################################################
#  ai_llm_evaluate — LLM 诊断评测（Python 规则/轻量模型 smoke）
###############################################################################

block_ai_llm_evaluate <- function(ctx, ...) {
  bl <- ctx$config$ai_clinical %||% list()
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  cases <- ai_clinical_cases_path(ctx)
  if (!file.exists(cases)) stop("请先运行 ai_cases_prepare", call. = FALSE)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "AI_Eval")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  run_literature_python(root, "ai_clinical_eval", c(
    "--out-dir", out, "--data-path", cases,
    "--outcome-col", bl$diagnosis_col %||% "true_diagnosis"
  ), timeout_sec = 900L)
  ctx$results$ai_llm_eval <- list(output_dir = out)
  cli::cli_alert_success("LLM 诊断评测完成")
  ctx
}

register_block("ai_llm_evaluate", block_ai_llm_evaluate, "LLM 诊断评测")
