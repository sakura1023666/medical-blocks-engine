###############################################################################
#  config_bayesian_comorbidity.R — 共病贝叶斯 Health Octo / BODN / Body Clock
#  文献: Salimi 2025 Nat Commun
#  决策树: Decisiontree/decision_tree_bayesian_comorbidity.md
#  入口: run/bayesian_comorbidity/run_bayesian_comorbidity.R
###############################################################################

.batch_project_root <- "Output/Bayesian_Comorbidity_HealthOcto"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

.sys_cols <- c(
  "CV_sev", "Renal_sev", "Metabolic_sev", "GI_sev", "Resp_sev",
  "Thyroid_sev", "Heme_sev", "Oral_sev", "MSK_sev", "Sensory_sev", "CNS_sev"
)

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_bayesian_comorbidity.RData",
    rawdata_obj    = "HealthOcto",
    outcome_column = "Mortality",
    id_column      = "ID",
    strip_id_columns_after_imputation = character(0)
  ),

  project = list(
    name = "Bayesian_Comorbidity_HealthOcto",
    disease_code = "10",
    disease = "Multimorbidity_Aging",
    literature_pmid = "58819",
    database = "BLSA+InCHIANTI+NHANES",
    database_type = "regular",
    study_type = "longitudinal",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),

  bayesian_comorbidity = list(
    system_severity_cols = .sys_cols,
    age_col = "Age",
    outcome_cols = c("Disability", "Walk_speed", "Mortality", "SPPB"),
    train_cohort = "BLSA",
    validate_cohorts = c("InCHIANTI", "NHANES"),
    brms_iter = 400L,
    brms_chains = 2L,
    roc_predictor = "Body_Clock",
    roc_outcome = "Mortality"
  ),

  data_clean = list(missing_threshold = 0.4),
  column_mapping = list(enable = FALSE),
  imputation = list(method = "cart", m = 1L, max_iter = 2L, seed = 42L, complete_action = 1L),

  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "10_Bayesian_Multimorbidity_Octo",
    protocol_label = "bayesian_comorbidity_health_octo",
    project_id = "10_bayesian_comorbidity_58819",
    literature_default = "Health Octo Tool BODN/Body Clock (Salimi 2025 Nat Commun)",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B10"
  )
)

pipeline <- list(
  name = "bayesian_comorbidity",
  blocks = c(
    "data_clean", "imputation",
    "bayesian_bodn",
    "bayesian_body_clock",
    "bayesian_bsc_clocks",
    "bayesian_health_octo_suite",
    "bayesian_bsc_aging",
    "bayesian_outcome_validate",
    "bayesian_roc_calibration"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
