###############################################################################
#  ai_multiround_sim — 多轮信息收集式临床决策模拟（Python）
###############################################################################

block_ai_multiround_sim <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  cases <- ai_clinical_cases_path(ctx)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "AI_Multiround")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  run_literature_python(root, "ai_multiround_cdm", c("--out-dir", out, "--data-path", cases), timeout_sec = 900L)
  ctx$results$ai_multiround <- list(output_dir = out)
  cli::cli_alert_success("多轮临床决策模拟完成")
  ctx
}

register_block("ai_multiround_sim", block_ai_multiround_sim, "多轮 CDM 模拟")
