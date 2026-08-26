###############################################################################
#  config_cftraj_charls.R — CHARLS CircS + LCMM 认知轨迹 + causal forest CATE
#  文献: Ma 2026 Alzheimers Dement
###############################################################################

.batch_project_root <- "Output/Causal_Forest_Trajectory_CHARLS"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_cftraj_charls.RData",
    rawdata_obj    = "CfTrajCHARLS",
    outcome_column = "Sex",
    id_column      = "ID",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "Causal_Forest_Trajectory_CHARLS",
    disease_code = "32",
    disease = "Cognitive_Trajectory_CircS",
    literature_pmid = "alz.2026.ma",
    database = "CHARLS",
    study_type = "longitudinal",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),
  cftraj = list(
    id_column = "ID",
    circs_components = list(
      BMI = list(col = "BMI", rule = "ge", cut = 24),
      BP = list(col = "SBP", rule = "ge", cut = 140),
      Glucose = list(col = "Glucose", rule = "ge", cut = 5.6),
      Lipids = list(col = "TC", rule = "ge", cut = 5.2),
      Sleep = list(col = "Sleep_hours", rule = "le", cut = 6),
      Depression = list(col = "CESD10", rule = "ge", cut = 10),
      Waist = list(col = "Waist", rule = "ge", cut = 90)
    ),
    circs_score_col = "CircS",
    circs_binary_col = "CircS_high",
    circs_threshold = 4L,
    cognitive_wave_prefix = "CogGlobal_",
    cognitive_episodic_prefix = "CogEpisodic_",
    cognitive_waves = c(2011, 2013, 2015, 2018),
    n_classes = 3L,
    trajectory_class_labels = c("high", "moderate", "low"),
    trajectory_reference = "high",
    covariates = c("Age", "Sex", "Education"),
    treatment_col = "CircS_high",
    cate_domains = c("global", "episodic"),
    trajectory_low_label = "low",
    literature_trajectory_pct = c(high = 40.29, moderate = 43.78, low = 15.93),
    literature_or_targets = list(
      global_low = list(OR = 1.27, lo = 1.06, hi = 1.52),
      episodic_low = list(OR = 1.28, lo = 1.06, hi = 1.55)
    ),
    literature_tol_pct = 15,
    cate_covariates = c("Age", "Sex", "Education", "BMI", "Anemia"),
    cate_num_trees = 2000L,
    subgroup_vars = c("Age_young", "Anemia", "BMI_group"),
    younger_age_cut = 65L,
    anemia_col = "Anemia",
    anemia_hb_cut = 12,
    sensitivity_thresholds = c(3L, 4L, 5L),
    gridsearch_rep = 5L,
    gridsearch_maxiter = 5L
  ),
  data_clean = list(missing_threshold = 0.5, skip_outcome_row_filter = TRUE),
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
    disease_label = "32_CfTraj_CircS_CHARLS",
    protocol_label = "cftraj_circs_lcmm_cate",
    project_id = "32_cftraj_charls_ma2026",
    literature_default = "Alzheimers Dement 2026 Ma CHARLS CircS LCMM causal forest",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B28"
  )
)

pipeline <- list(
  name = "cftraj_charls",
  blocks = c(
    "data_clean", "imputation",
    "cftraj_circs_compute", "cftraj_wide_to_long", "cftraj_lcmm_fit", "cftraj_lcmm_episodic",
    "cftraj_multinomial", "cftraj_causal_forest",
    "cftraj_subgroup_viz", "cftraj_sensitivity", "cftraj_trajectory_validate"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
