###############################################################################
#  ai_qa_prompt_templates — 导出 Jeon 原文三种 CoT prompt 模板
###############################################################################

block_ai_qa_prompt_templates <- function(ctx, ...) {
  bl <- ctx$config$ai_medical_qa %||% list()
  root <- ctx$config$project$root %||% getwd()
  tpl_path <- bl$prompt_template_file %||% "prompts/ai_medical_qa_cot_templates.md"
  if (!is_absolute_path(tpl_path)) tpl_path <- file.path(root, tpl_path)

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "AI_QA")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  if (file.exists(tpl_path)) {
    txt <- paste(readLines(tpl_path, warn = FALSE), collapse = "\n")
    writeLines(txt, file.path(out_dir, "Prompt_Templates_CoT.md"))
  }

  methods <- bl$prompt_methods %||% c("Control", "Traditional_CoT", "Interactive_CoT")
  rows <- lapply(methods, function(pm) {
    body <- switch(pm,
      Control = "Answer the MCQ directly; output one letter.",
      Traditional_CoT = "Step-by-step clinical reasoning then one letter.",
      Interactive_CoT = "Multi-turn clarify → reason → final letter.",
      "Custom prompt"
    )
    data.frame(prompt_method = pm, template_body = body, stringsAsFactors = FALSE)
  })
  tab <- do.call(rbind, rows)
  utils::write.csv(tab, file.path(out_dir, "Table_CoT_Prompt_Templates.csv"), row.names = FALSE)

  ctx$results$ai_qa_prompt_templates <- list(output_dir = out_dir, table = tab)
  cli::cli_alert_success("CoT prompt 模板已导出 ({nrow(tab)} 种)")
  ctx
}

register_block("ai_qa_prompt_templates", block_ai_qa_prompt_templates, "CoT prompt 模板导出")
