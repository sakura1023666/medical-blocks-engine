###############################################################################
#  ai_qa_cot_eval — Interactive / Traditional CoT 评测（Python）
#  文献: Jeon — medical QA chain-of-thought
###############################################################################

block_ai_qa_cot_eval <- function(ctx, ...) {
  bl <- ctx$config$ai_medical_qa %||% list()
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)

  qa_path <- (ctx$results$ai_qa_prepare %||% list())$prepared_path
  if (is.null(qa_path) || !file.exists(qa_path)) {
    out_prep <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "AI_QA", "qa_prepared.csv")
    raw <- bl$qa_path %||% "Data/smoke/D01_ai_medical_qa.csv"
    if (!is_absolute_path(raw)) raw <- file.path(root, raw)
    qa_path <- if (file.exists(out_prep)) out_prep else raw
  }
  if (!file.exists(qa_path)) stop("请先运行 ai_qa_prepare", call. = FALSE)

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "AI_QA_CoT")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  datasets <- paste(bl$datasets %||% c("MedQA", "MedMCQA", "EHRNoteQA"), collapse = ",")
  models <- paste(bl$models %||% c("GPT-4", "GPT-3.5", "Llama-2-70B", "Mistral-7B"), collapse = ",")
  prompts <- paste(bl$prompt_methods %||% c("Control", "Traditional_CoT", "Interactive_CoT"), collapse = ",")

  py_args <- c(
    "--out-dir", out,
    "--data-path", qa_path,
    "--datasets", datasets,
    "--genes", models,
    "--prompt-methods", prompts,
    "--outcome-col", bl$answer_col %||% "correct_option"
  )
  if (isTRUE(bl$use_literature_table4 %||% TRUE)) py_args <- c(py_args, "--use-literature")
  run_literature_python(root, "ai_medical_qa_cot", py_args, timeout_sec = 1800L)

  ctx$results$ai_qa_cot_eval <- list(output_dir = out)
  cli::cli_alert_success("CoT 医学 QA 评测完成")
  ctx
}

register_block("ai_qa_cot_eval", block_ai_qa_cot_eval, "CoT 医学 QA 评测")
