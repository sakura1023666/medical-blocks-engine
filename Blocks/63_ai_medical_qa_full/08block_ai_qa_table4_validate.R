###############################################################################
#  ai_qa_table4_validate — 复现 Jeon Table 4 并对照 FDR 校正后 p 值
###############################################################################

block_ai_qa_table4_validate <- function(ctx, ...) {
  bl <- ctx$config$ai_medical_qa %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_validation.R"), local = FALSE)
  out_base <- literature_batch_output_base(ctx)

  lit <- bl$table4_literature %||% list(
    list(dataset = "MedQA", model = "o1-mini", prompt_method = "Traditional_CoT", accuracy = 0.724),
    list(dataset = "MedQA", model = "GPT-4o-mini", prompt_method = "Traditional_CoT", accuracy = 0.680),
    list(dataset = "MedMCQA", model = "o1-mini", prompt_method = "Traditional_CoT", accuracy = 0.617),
    list(dataset = "MedMCQA", model = "o1-mini", prompt_method = "Interactive_CoT", accuracy = 0.617),
    list(dataset = "MedMCQA", model = "GPT-4o-mini", prompt_method = "Interactive_CoT", accuracy = 0.617),
    list(dataset = "EHRNoteQA", model = "o1-mini", prompt_method = "Control", accuracy = 0.884),
    list(dataset = "EHRNoteQA", model = "o1-mini", prompt_method = "Interactive_CoT", accuracy = 0.835),
    list(dataset = "EHRNoteQA", model = "GPT-4o-mini", prompt_method = "Interactive_CoT", accuracy = 0.835)
  )
  lit_df <- do.call(rbind, lapply(lit, function(x) as.data.frame(x, stringsAsFactors = FALSE)))

  comp <- literature_read_batch_csvs(out_base, "Table_CoT_Accuracy_Summary.csv")
  if (!nrow(comp)) {
    eval_dir <- (ctx$results$ai_qa_cot_eval %||% list())$output_dir
    if (!is.null(eval_dir) && file.exists(file.path(eval_dir, "Table_CoT_Accuracy_Summary.csv")))
      comp <- utils::read.csv(file.path(eval_dir, "Table_CoT_Accuracy_Summary.csv"), stringsAsFactors = FALSE)
  }
  if (nrow(comp) && ".source_path" %in% names(comp)) comp$.source_path <- NULL

  rows <- list()
  for (i in seq_len(nrow(lit_df))) {
    r <- lit_df[i, , drop = FALSE]
    hit <- comp
    if (nrow(comp)) {
      hit <- comp[comp$dataset == r$dataset & comp$model == r$model &
                    comp$prompt_method == r$prompt_method, , drop = FALSE]
    }
    comp_acc <- if (nrow(hit)) hit$accuracy[1L] else NA_real_
    rows[[length(rows) + 1L]] <- cbind(
      r,
      computed_accuracy = comp_acc,
      abs_diff = abs(comp_acc - r$accuracy),
      within_5pct = is.finite(comp_acc) && abs(comp_acc - r$accuracy) <= 0.05
    )
  }
  table4 <- do.call(rbind, rows)

  stat_paths <- literature_find_table(out_base, "Table_AI_QA_CoT_Statistics.csv")
  stat_df <- if (length(stat_paths)) utils::read.csv(stat_paths[1L], stringsAsFactors = FALSE) else data.frame()
  if (!nrow(stat_df)) {
    stat_path <- file.path(out_base, "Tables", "Table_AI_QA_CoT_Statistics.csv")
    if (file.exists(stat_path)) stat_df <- utils::read.csv(stat_path, stringsAsFactors = FALSE)
  }
  if (nrow(stat_df) && "p_overall" %in% names(stat_df)) {
    stat_df$p_fdr_BH <- literature_fdr_adjust(stat_df$p_overall, bl$fdr_method %||% "BH")
    stat_df$sig_fdr_05 <- stat_df$p_fdr_BH < 0.05
    stat_out <- file.path(out_base, "Tables", "Table_AI_QA_CoT_Statistics.csv")
    dir.create(dirname(stat_out), recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(stat_df, stat_out, row.names = FALSE)
  }

  out <- file.path(out_base, "Tables", "Table_AI_QA_Table4_Literature_Validation.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(table4, out, row.names = FALSE)

  n_match <- sum(table4$within_5pct %in% TRUE, na.rm = TRUE)
  ctx$results$ai_qa_table4_validate <- list(
    table = table4, n_match = n_match, n_total = nrow(table4),
    data_mode = if (isTRUE(bl$use_literature_table4)) "literature_simulated" else "smoke_random"
  )
  cli::cli_alert_success("Table 4 文献对照 ({n_match}/{nrow(table4)} ±5%；smoke 非原文复现)")
  ctx
}

register_block("ai_qa_table4_validate", block_ai_qa_table4_validate, "Table 4 原文对照")
