###############################################################################
#  ai_qa_dataset_summary — MedQA / MedMCQA / EHRNoteQA 分数据集汇总
#  文献: Jeon — medical QA chain-of-thought
###############################################################################

block_ai_qa_dataset_summary <- function(ctx, ...) {
  bl <- ctx$config$ai_medical_qa %||% list()
  eval_dir <- (ctx$results$ai_qa_cot_eval %||% list())$output_dir
  if (is.null(eval_dir))
    eval_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "AI_QA_CoT")

  datasets <- bl$datasets %||% c("MedQA", "MedMCQA", "EHRNoteQA")
  prompt_methods <- bl$prompt_methods %||% c("Control", "Traditional_CoT", "Interactive_CoT")

  cmp <- (ctx$results$ai_qa_prompt_compare %||% list())$table
  if (is.null(cmp) || !nrow(cmp)) {
    root <- ctx$config$project$root %||% getwd()
    if (file.exists(file.path(root, "R/literature_validation.R")))
      source(file.path(root, "R/literature_validation.R"), local = FALSE)
    out_base <- if (exists("literature_batch_output_base")) literature_batch_output_base(ctx) else (ctx$config$project$output_dir %||% "Output")
    cmp <- if (exists("literature_read_batch_csvs")) literature_read_batch_csvs(out_base, "Table_AI_QA_Prompt_Compare.csv") else data.frame()
    if (nrow(cmp) && ".source_path" %in% names(cmp)) cmp$.source_path <- NULL
  }
  if (is.null(cmp) || !nrow(cmp)) {
    cmp_path <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_AI_QA_Prompt_Compare.csv")
    if (file.exists(cmp_path)) cmp <- utils::read.csv(cmp_path, stringsAsFactors = FALSE)
  }

  detail_path <- file.path(eval_dir, "Table_CoT_Eval_Results.csv")
  det <- if (file.exists(detail_path)) utils::read.csv(detail_path, stringsAsFactors = FALSE) else data.frame()
  if (!nrow(det)) {
    root <- ctx$config$project$root %||% getwd()
    if (file.exists(file.path(root, "R/literature_validation.R")))
      source(file.path(root, "R/literature_validation.R"), local = FALSE)
    out_base <- if (exists("literature_batch_output_base")) literature_batch_output_base(ctx) else (ctx$config$project$output_dir %||% "Output")
    det <- if (exists("literature_read_batch_csvs")) literature_read_batch_csvs(out_base, "Table_CoT_Eval_Results.csv") else data.frame()
    if (nrow(det) && ".source_path" %in% names(det)) det$.source_path <- NULL
  }

  rows <- list()
  for (ds in datasets) {
    sub_cmp <- if (!is.null(cmp) && nrow(cmp)) cmp[cmp$dataset == ds, , drop = FALSE] else data.frame()
    sub_det <- if (nrow(det) && "dataset" %in% names(det)) det[det$dataset == ds, , drop = FALSE] else data.frame()

    n_questions <- if (nrow(sub_det) && "question_id" %in% names(sub_det)) {
      length(unique(sub_det$question_id))
    } else if (nrow(sub_cmp) && "n" %in% names(sub_cmp)) {
      max(sub_cmp$n, na.rm = TRUE)
    } else {
      NA_integer_
    }

    acc_ctrl <- suppressWarnings(as.numeric(sub_cmp$accuracy[sub_cmp$prompt_method == "Control"][1L]))
    acc_trad <- suppressWarnings(as.numeric(sub_cmp$accuracy[sub_cmp$prompt_method == "Traditional_CoT"][1L]))
    acc_int <- suppressWarnings(as.numeric(sub_cmp$accuracy[sub_cmp$prompt_method == "Interactive_CoT"][1L]))
    best_pm <- prompt_methods[which.max(sub_cmp$accuracy[match(prompt_methods, sub_cmp$prompt_method)])]

    if (all(is.na(c(acc_ctrl, acc_trad, acc_int))) && nrow(sub_det) && "correct" %in% names(sub_det)) {
      acc_ctrl <- mean(sub_det$correct[sub_det$prompt_method == "Control"], na.rm = TRUE)
      acc_trad <- mean(sub_det$correct[sub_det$prompt_method == "Traditional_CoT"], na.rm = TRUE)
      acc_int <- mean(sub_det$correct[sub_det$prompt_method == "Interactive_CoT"], na.rm = TRUE)
    }

    rows[[length(rows) + 1L]] <- data.frame(
      dataset = ds,
      n_questions = n_questions,
      n_models = if (nrow(sub_det) && "model" %in% names(sub_det)) length(unique(sub_det$model)) else length(bl$models %||% character(0)),
      accuracy_control = round(acc_ctrl, 4),
      accuracy_traditional_cot = round(acc_trad, 4),
      accuracy_interactive_cot = round(acc_int, 4),
      best_prompt_method = best_pm %||% NA_character_,
      interactive_gain_vs_control = round(acc_int - acc_ctrl, 4),
      stringsAsFactors = FALSE
    )
  }

  summary_df <- do.call(rbind, rows)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_AI_QA_Dataset_Summary.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(summary_df, out, row.names = FALSE)

  ctx$results$ai_qa_dataset_summary <- list(table = summary_df, output_path = out)
  cli::cli_alert_success("分数据集 QA 汇总完成 ({length(datasets)} 数据集)")
  ctx
}

register_block("ai_qa_dataset_summary", block_ai_qa_dataset_summary, "医学 QA 分数据集汇总")
