###############################################################################
#  config_cross_lagged_frailty.R — 交叉滞后面板网络（衰弱/抑郁/CVD）
#  文献: Zhang 2025 Nat Commun (paper_008)
#  决策树: Decisiontree/decision_tree_cross_lagged_frailty.md
###############################################################################

.batch_project_root <- "Output/Cross_Lagged_Frailty"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_cross_lagged_frailty.RData",
    rawdata_obj    = "CrossLagged",
    outcome_column = "CVD_event",
    id_column      = "ID",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "Cross_Lagged_Frailty",
    disease_code = "08",
    disease = "CVD",
    analysis_group = "CVD",
    reference_group = "No_CVD",
    literature_pmid = "s41467-025-61089-2",
    database = "Multi_Cohort",
    study_type = "longitudinal",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),
  cross_lagged = list(
    fi_var = "FI_T1",
    mediator_var = "Depression_T1",
    time_var = "futime",
    event_var = "CVD_event",
    cohort_col = "Cohort",
    frailty_status_col = "Frailty_status_T1",
    subgroup_vars = c("Gender"),
    subgroup_vars_extended = c("Gender", "Age_group", "Smoking", "Drinking", "Exercise", "Employment"),
    mediation_boot_R = 100L
  ),
  data_clean = list(missing_threshold = 1.0),
  column_mapping = list(enable = FALSE),
  imputation = list(method = "cart", m = 1L, max_iter = 2L, seed = 42L,
                    export_missing_fig = FALSE, complete_action = 1L,
                    exclude_from_mice_cols = c("CVD_event", "fustatus", "futime", "FI_T1", "FI_T2",
                                               "Depression_T1", "Depression_T2", "Frailty_status_T1")),
  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "08_Frailty_Depression_CVD",
    protocol_label = "cross_lagged_panel_frailty",
    project_id = "08_cross_lagged_61089",
    literature_default = "Nat Commun 2025 cross-lagged FI depression CVD",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B06"
  )
)

pipeline <- list(
  name = "cross_lagged_frailty",
  blocks = c(
    "data_clean", "cross_lagged_fi_compute",
    "cross_lagged_km", "cross_lagged_cox_frailty", "cross_lagged_mediation",
    "cross_lagged_mediation_bootstrap", "cross_lagged_panel_network",
    "cross_lagged_frailty_transition", "cross_lagged_subgroup",
    "cross_lagged_subgroup_extended", "cross_lagged_sensitivity",
    "cross_lagged_biomarker_cor", "cross_lagged_meta_merge"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
