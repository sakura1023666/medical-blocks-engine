###############################################################################
#  config_network_temperature_adolescent.R — 青少年抑郁网络温度
#  文献: Grimes 2025 Nat Mental Health
###############################################################################

.batch_project_root <- "Output/Network_Temperature_Adolescent"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_network_temperature_adolescent.RData",
    rawdata_obj    = "NetworkTempAdolescent",
    outcome_column = "Depression_Outcome",
    id_column      = "ID",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "Network_Temperature_Adolescent",
    disease_code = "29",
    disease = "Adolescent_Depression_Network",
    literature_pmid = "s44220-025-00415-5",
    database = "ABCD_ALSPAC",
    study_type = "longitudinal",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),
  network_temperature = list(
    id_col = "ID",
    subgroup_col = "Sex",
    cohort_col = "Cohort",
    outcome_col = "Depression_dx",
    temp_subject_col = "Network_temperature",
    symptom_wave_prefix = "DEP_",
    n_boot = 100L,
    literature_tol_pct = 25,
    literature_targets = list(age_main_beta = -0.08, age_sex_interaction = -0.04)
  ),
  data_clean = list(missing_threshold = 0.3),
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
    disease_label = "29_Network_Temperature",
    protocol_label = "network_temperature_adolescence",
    project_id = "29_network_temp_00415",
    literature_default = "Nat Mental Health 2025 network temperature adolescence",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B29"
  )
)

pipeline <- list(
  name = "network_temperature_adolescent",
  blocks = c(
    "data_clean", "imputation",
    "network_temp_prepare_long", "network_temp_compute",
    "network_temp_ggm_fit", "network_temp_mixed_model",
    "network_temp_centrality", "network_temp_trajectory",
    "network_temp_cohort_summary", "network_temp_outcome_assoc",
    "network_temp_literature_validate"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
