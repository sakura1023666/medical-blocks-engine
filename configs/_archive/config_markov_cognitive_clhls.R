###############################################################################
#  config_markov_cognitive_clhls.R — CLHLS 三状态 Markov 认知
#  文献: Ren 2025 Alzheimers Dement e70090
###############################################################################

.batch_project_root <- "Output/Markov_Cognitive_CLHLS"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_markov_cognitive_clhls.RData",
    rawdata_obj    = "MarkovCLHLS",
    outcome_column = "Cognitive_state",
    id_column      = "ID",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "Markov_Cognitive_CLHLS",
    disease_code = "31",
    disease = "Cognitive_Aging",
    literature_pmid = "alz.70090",
    database = "CLHLS",
    study_type = "longitudinal",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),
  markov_cognitive = list(
    mmse_col = "MMSE",
    death_col = "Death",
    ci_cutoff = 18L,
    id_col = "ID",
    time_col = "Followup_years",
    state_col = "Cognitive_state",
    apoe_col = "APOE_carrier",
    lifestyle_col = "Healthy_lifestyle",
    lifestyle_vars = c("Exercise", "Diet", "Social", "Cognitive_activity", "Smoking_reverse"),
    lifestyle_cutoff = 4L,
    bootstrap_R = 100L
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
    disease_label = "31_Cognitive_Markov_CLHLS",
    protocol_label = "markov_cognitive_apoe_lifestyle",
    project_id = "31_markov_clhls_70090",
    literature_default = "Alzheimers Dement 2025 CLHLS 3-state Markov",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B31"
  )
)

pipeline <- list(
  name = "markov_cognitive_clhls",
  blocks = c(
    "data_clean", "markov_state_prep", "markov_msm_fit",
    "markov_msm_bootstrap", "markov_life_expectancy",
    "markov_life_table_figure", "markov_apoe_le_difference",
    "markov_apoe_lifestyle", "markov_sensitivity_glmm"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
