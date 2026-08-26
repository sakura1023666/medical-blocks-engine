###############################################################################
#  config_competing_risk_chf.R — 竞争风险（TyG 轨迹 / WHF vs 死亡）
#  文献: Lai 2025 Cardiovasc Diabetol (paper_018)
###############################################################################

.batch_project_root <- "Output/Competing_Risk_CHF"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_competing_risk_chf.RData",
    rawdata_obj    = "CompetingRiskCHF",
    outcome_column = "event_type",
    id_column      = "ID",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "Competing_Risk_CHF",
    disease_code = "22",
    disease = "CHF_T2DM_TyG",
    literature_pmid = "s12933-025-02687-8",
    database = "Single_Center",
    study_type = "prognosis",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),
  competing_risk = list(
    tyg_var = "TyG",
    tyg_visit_cols = c("TyG_V1", "TyG_V2", "TyG_V3"),
    exposure_var = "TyG_quartile",
    time_var = "futime",
    event_type_col = "event_type",
    cif_strata = "TyG_quartile",
    rcs_knots = 3L,
    lasso_candidates = c("Age", "Gender", "BMI", "Hypertension", "CHD", "Smoking", "Drinking", "TyG"),
    model1_covars = c("Age", "Gender"),
    model2_covars = c("Age", "Gender", "BMI", "Hypertension", "CHD", "Smoking", "Drinking"),
    model3_covars = c("Age", "Gender", "BMI", "Hypertension", "CHD", "Smoking", "Drinking", "HbA1c", "EF", "NYHA")
  ),
  data_clean = list(missing_threshold = 0.5),
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
    disease_label = "22_CHF_T2DM_TyG",
    protocol_label = "competing_risk_tyg_trajectory",
    project_id = "22_competing_risk_02687",
    literature_default = "Cardiovasc Diabetol 2025 TyG competing risk",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B22"
  )
)

pipeline <- list(
  name = "competing_risk_chf",
  blocks = c(
    "data_clean", "competing_tyg_compute",
    "competing_lmm_trajectory", "competing_lasso_screen", "competing_rf_screen",
    "competing_finegray", "competing_mixed_cox", "competing_models_123",
    "competing_stratified", "competing_rcs", "competing_cif_plot",
    "competing_cox_sensitivity", "competing_ph_calibration"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
