###############################################################################
#  config_incidence_prepost_charls.R — 发病前后认知轨迹（CHARLS 糖尿病）
#  文献: Chen 2024 Neurology — cognitive before/after diabetes onset
#  决策树: Decisiontree/decision_tree_incidence_prepost_charls.md
###############################################################################

.batch_project_root <- "Output/Incidence_PrePost_CHARLS"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_incidence_prepost_charls.RData",
    rawdata_obj    = "PrePostCHARLS",
    outcome_column = "Diabetes",
    id_column      = "ID",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "Incidence_PrePost_CHARLS",
    disease_code = "18",
    disease = "Diabetes_Cognitive_PrePost",
    literature_pmid = "10.1212/WNL.0000000000209165",
    database = "CHARLS",
    study_type = "longitudinal",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/"),
    analysis_group = "Diabetes",
    reference_group = "No_diabetes"
  ),
  incidence_prepost = list(
    id_col = "ID", wave_col = "Wave", time_col = "Years_from_baseline",
    onset_wave_col = "Diabetes_onset_wave", ever_diabetes_col = "Diabetes_group",
    global_cog_col = "Global_cognition_z",
    domain_cols = c("Episodic_memory_z", "Visuospatial_z", "Attention_calc_z", "Orientation_z"),
    age_col = "Age", sex_col = "Sex", min_age = 45L,
    covariates = c(
      "Age", "Sex", "Education", "Marital_status", "Residential_area",
      "Smoking", "Drinking", "IADL_score", "Hypertension", "Hypercholesterol",
      "Lung_disease", "Heart_problem", "Cancer", "Depressive_symptoms"
    ),
    literature_tol_pct = 60,
    literature_targets = list(
      global_post_slope = -0.023, visuospatial_post_slope = -0.036,
      episodic_post_slope = -0.018, attention_post_slope = -0.017
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
    disease_label = "18_Incidence_PrePost_CHARLS",
    protocol_label = "incidence_prepost_diabetes_cognition",
    project_id = "18_prepost_charls_2024",
    literature_default = "Neurology 2024 Chen cognitive before/after diabetes",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B18"
  )
)

pipeline <- list(
  name = "incidence_prepost_charls",
  blocks = c(
    "data_clean", "imputation",
    "prepost_data_prep", "prepost_descriptive", "prepost_lmm_fit",
    "prepost_domain_slopes", "prepost_subgroup_age", "prepost_sensitivity",
    "prepost_visualize", "prepost_literature_validate"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
