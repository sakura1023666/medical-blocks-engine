###############################################################################
#  config_target_trial_rasi_aki.R — 目标试验模拟 RASi 停药 × AKI 死亡
#  文献: Nie 2025 JASN — sequential target trial emulation
###############################################################################

.batch_project_root <- "Output/Target_Trial_RASi_AKI"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_target_trial_rasi_aki.RData",
    rawdata_obj    = "TteRasiAKI",
    outcome_column = "Death_30d",
    id_column      = "Trial_id",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "Target_Trial_RASi_AKI",
    disease_code = "19",
    disease = "AKI_RASi_Discontinuation",
    literature_pmid = "10.1681/ASN.0000000775",
    database = "CRDS_MIMIC",
    study_type = "target_trial_emulation",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/"),
    analysis_group = "Death",
    reference_group = "Survival"
  ),
  target_trial = list(
    patient_id_col = "Patient_ID",
    treatment_col = "Treatment_discontinue",
    outcome_30d = "Death_30d", outcome_180d = "Death_180d",
    database_col = "Database",
    covariates = NULL,
    grace_days = 2L, min_rasi_days = 90L, bootstrap_R = 200L, seed = 42L,
    real_data_paths = list(
      CRDS = "Data/smoke/D01_target_trial_rasi_aki.RData",
      MIMIC = "Data/smoke/D01_target_trial_rasi_aki.RData"
    ),
    literature_tol_pct = 10,
    literature_targets = list(
      mortality_disc_30d = 0.0436, mortality_cont_30d = 0.0591,
      risk_diff_pct = -21.55
    )
  ),
  data_clean = list(missing_threshold = 0.3, skip_outcome_row_filter = TRUE),
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
    disease_label = "19_Target_Trial_RASi_AKI",
    protocol_label = "target_trial_rasi_aki_mortality",
    project_id = "19_tte_rasi_2025",
    literature_default = "JASN 2025 Nie RASi discontinuation TTE",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B19"
  )
)

pipeline <- list(
  name = "target_trial_rasi_aki",
  blocks = c(
    "data_clean", "imputation",
    "tte_data_prep", "tte_descriptive", "tte_weighting",
    "tte_pooled_logistic", "tte_risk_difference", "tte_bootstrap_ci",
    "tte_stratified", "tte_sensitivity", "tte_literature_validate"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
