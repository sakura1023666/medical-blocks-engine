###############################################################################
#  config_ai_clinical_cdm.R — LLM 临床决策评测（MIMIC-CDM）
#  文献: Hager 2024 Nat Med (paper_009)
###############################################################################

.batch_project_root <- "Output/AI_Clinical_CDM"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_ai_clinical_cases.RData",
    rawdata_obj    = "AICases",
    outcome_column = "true_diagnosis",
    id_column      = "case_id",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "AI_Clinical_CDM",
    disease_code = "24",
    disease = "Abdominal_Pathology_LLM",
    literature_pmid = "s41591-024-03097-1",
    database = "MIMIC_IV",
    study_type = "diagnostic_accuracy",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),
  ai_clinical = list(
    cases_path = "Data/smoke/D01_ai_clinical_cases.csv",
    diagnosis_col = "true_diagnosis",
    pathologies = c("appendicitis", "cholecystitis", "diverticulitis", "pancreatitis"),
    llm_models = c("Llama2", "OASST", "WizardLM", "GPT4_baseline")
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
    disease_label = "24_Abdominal_LLM_CDM",
    protocol_label = "ai_clinical_decision_mimic",
    project_id = "24_ai_clinical_03097",
    literature_default = "Nat Med 2024 LLM clinical decision-making",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B24"
  )
)

pipeline <- list(
  name = "ai_clinical_cdm",
  blocks = c(
    "ai_cases_prepare", "ai_llm_evaluate", "ai_llm_multimodel",
    "ai_multiround_sim", "ai_guideline_audit", "ai_reader_comparison",
    "ai_reader_study", "ai_lab_interpret", "ai_order_robustness"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
