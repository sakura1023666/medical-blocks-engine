###############################################################################
#  config_ai_medical_qa_cot.R — 医学 QA CoT 提示工程评测
#  文献: Jeon — Chain-of-Thought medical question answering
#  决策树: Decisiontree/decision_tree_ai_medical_qa_cot.md
#  入口: run/ai_medical_qa/run_ai_medical_qa_cot.R
###############################################################################

.batch_project_root <- "Output/AI_Medical_QA_CoT"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_ai_medical_qa.RData",
    rawdata_obj    = "MedicalQA",
    outcome_column = "correct_option",
    id_column      = "question_id",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "AI_Medical_QA_CoT",
    disease_code = "26",
    disease = "Medical_QA_CoT",
    literature_pmid = "jeon_cot_medical_qa",
    database = "MedQA+MedMCQA+EHRNoteQA",
    study_type = "diagnostic_accuracy",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),
  ai_medical_qa = list(
    qa_path = "Data/smoke/D01_ai_medical_qa.csv",
    datasets = c("MedQA", "MedMCQA", "EHRNoteQA"),
    models = c("GPT-4o-mini", "GPT-3.5-turbo", "o1-mini", "Gemini-1.5-Flash"),
    prompt_methods = c("Control", "Traditional_CoT", "Interactive_CoT"),
    answer_col = "correct_option",
    use_literature_table4 = TRUE,
    fdr_method = "BH",
    prompt_template_file = "prompts/ai_medical_qa_cot_templates.md"
  ),
  data_clean = list(missing_threshold = 1.0),
  column_mapping = list(enable = FALSE),
  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "26_Medical_QA_CoT",
    protocol_label = "ai_medical_qa_cot_eval",
    project_id = "26_ai_qa_cot_jeon",
    literature_default = "Jeon CoT medical QA comparative evaluation",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B26"
  )
)

pipeline <- list(
  name = "ai_medical_qa_cot",
  blocks = c(
    "ai_qa_prepare", "ai_qa_prompt_templates", "ai_qa_cot_eval", "ai_qa_prompt_compare",
    "ai_qa_statistics", "ai_qa_dataset_summary", "ai_qa_model_ranking", "ai_qa_table4_validate"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
