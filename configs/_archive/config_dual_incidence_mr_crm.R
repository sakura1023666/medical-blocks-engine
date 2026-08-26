###############################################################################
#  config_dual_incidence_mr_crm.R — 双库发病 + 孟德尔随机化（SUA/CRM）
#  文献: Han 2025 JAHA (paper_013)
###############################################################################

.batch_project_root <- "Output/Dual_Incidence_MR_CRM"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path     = "Data/smoke/D01_dual_crm_incidence.RData",
    rawdata_obj      = "DualCRM",
    outcome_column   = "Disease_Group",
    id_column        = "ID",
    strip_id_columns_after_imputation = c("ID", "SEQN", "subject_id")
  ),
  project = list(
    name = "Dual_Incidence_MR_CRM",
    disease_code = "13",
    disease = "CRM_SUA_Gout",
    literature_pmid = "e038723",
    database = "CHARLS_NHANES",
    study_type = "incidence",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),
  dual_incidence_mr = list(
    exposure_var = "SUA",
    crm_outcome_col = "CRM_count",
    time_var = "futime",
    event_var = "fustatus",
    gwas_exposure = "Data/smoke/GWAS_SUA_full.csv",
    mr_outcomes = c("CVD", "CKD", "Diabetes"),
    mr_max_snps = 176L,
    mr_f_stat_threshold = 10
  ),
  incidence = list(outcome_var = "Disease_Group", index_var = "SUA"),
  nhanes = list(
    survey_weight = "new_Weight", survey_cluster = "SDMVPSU", survey_strata = "SDMVSTRA",
    cutoff_index_var = "SUA", auto_new_weight = FALSE
  ),
  data_clean = list(missing_threshold = 1.0),
  column_mapping = list(enable = FALSE),
  imputation = list(enable = FALSE),
  dual_db = list(enable = FALSE),
  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "13_CRM_SUA_Gout_MR",
    protocol_label = "dual_incidence_mr_crm",
    project_id = "13_dual_mr_038723",
    literature_default = "JAHA 2025 CHARLS+NHANES SUA CRM MR",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B13"
  )
)

pipeline <- list(
  name = "dual_incidence_mr_crm",
  blocks = c(
    "data_clean",
    "crm_ordinal_logistic", "crm_cox_mortality", "crm_rcs_sua",
    "crm_nhanes_weighted", "crm_gout_strata",
    "mr_snp_screen", "mr_twosample", "mr_egger_presso",
    "mr_pleiotropy", "mr_sensitivity"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
