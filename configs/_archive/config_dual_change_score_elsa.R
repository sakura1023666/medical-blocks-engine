###############################################################################
#  config_dual_change_score_elsa.R — 双向变化分数模型（抑郁↔认知）
#  文献: Yin 2024 JAMA Network Open — bivariate dual change score ELSA
###############################################################################

.batch_project_root <- "Output/Dual_Change_Score_ELSA"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_dual_change_score_elsa.RData",
    rawdata_obj    = "DualChangeELSA",
    outcome_column = "Memory_score",
    id_column      = "ID",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "Dual_Change_Score_ELSA",
    disease_code = "25b",
    disease = "Depression_Cognition_DCSM",
    literature_pmid = "10.1001/jamanetworkopen.2024.16305",
    database = "ELSA",
    study_type = "longitudinal",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/"),
    analysis_group = "High_depression",
    reference_group = "Low_depression"
  ),
  dual_change_score = list(
    id_col = "ID", wave_col = "Wave",
    depression_col = "CESD_total", memory_col = "Memory_score", fluency_col = "Verbal_fluency",
    covariates = c("Age_c", "Sex", "Education", "Wealth", "Limiting_illness",
                   "Self_rated_health", "Smoking", "Alcohol", "Physical_activity"),
    sem_estimator = "MLR",
    literature_tol_pct = 15,
    literature_targets = list(
      dep_to_mem_intercept = -0.253, mem_to_dep_intercept = 0.016,
      dep_cross_mem = -0.018, dep_cross_flu = -0.009
    )
  ),
  data_clean = list(missing_threshold = 0.4, skip_outcome_row_filter = TRUE),
  column_mapping = list(enable = FALSE),
  imputation = list(method = "cart", m = 1L, max_iter = 2L, seed = 42L,
                    export_missing_fig = FALSE, complete_action = 1L),
  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "25b_Dual_Change_Score_ELSA",
    protocol_label = "dual_change_score_depression_cognition",
    project_id = "25b_dcs_elsa_2024",
    literature_default = "JAMA Netw Open 2024 Yin dual change score ELSA",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B25"
  )
)

pipeline <- list(
  name = "dual_change_score_elsa",
  blocks = c(
    "data_clean", "imputation",
    "dcs_data_prep", "dcs_descriptive", "dcs_bivariate_dcsm",
    "dcs_depression_to_memory", "dcs_memory_to_depression",
    "dcs_verbal_fluency", "dcs_sensitivity", "dcs_literature_validate"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
