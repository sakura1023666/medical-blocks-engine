###############################################################################
#  config_trajectory_incidence_aki.R — 轨迹发病（脓毒症 AKI 肌酐 LCMM）
#  文献: Takkavatakarn 2024 Critical Care
#  决策树: Decisiontree/decision_tree_trajectory_incidence_aki.md
#  入口: run/trajectory_incidence/run_trajectory_incidence_aki.R
###############################################################################

.batch_project_root <- "Output/Trajectory_Incidence_AKI_Sepsis"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_trajectory_incidence_aki.RData",
    rawdata_obj    = "TrajectoryAKI",
    outcome_column = "Cohort",
    id_column      = "ID",
    strip_id_columns_after_imputation = character(0)
  ),

  project = list(
    name = "Trajectory_Incidence_AKI",
    disease_code = "08",
    disease = "AKI_Sepsis_Trajectory",
    literature_pmid = "28_156",
    database = "MIMIC+eICU",
    study_type = "prognosis",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),

  trajectory = list(
    index_vars = c("CreatininePct"),
    id_column = "ID",
    time_col_prefix = "CrePct_",
    use_creatinine_pct = TRUE,
    raw_creatinine_prefix = "Cre_",
    baseline_creatinine_col = "baseline_creatinine",
    cohort_col = "Cohort",
    dev_cohort = "MIMIC",
    validate_cohort = "eICU",
    lcmm_ng_min = 2L,
    lcmm_ng_max = 6L,
    gridsearch_rep = 3L,
    gridsearch_maxiter = 3L,
    class_for_test = 4L,
    prefer_ng = 4L,
    outcome_vars = c("AKD", "Mortality_7d", "Mortality_28d"),
    outcome_covariates = c("Age", "Gender", "baseline_creatinine", "SOFA"),
    p_threshold = 1.0
  ),

  survival = list(time_var = "futime", event_var = "Mortality_28d"),

  data_clean = list(missing_threshold = 0.5, skip_outcome_row_filter = TRUE),
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
    disease_label = "08_AKI_Trajectory_Incidence",
    protocol_label = "trajectory_incidence_lcmm_aki",
    project_id = "08_trajectory_incidence_156",
    literature_default = "Sepsis AKI creatinine LCMM (Takkavatakarn 2024 Crit Care)",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B08"
  )
)

pipeline <- list(
  name = "trajectory_incidence_aki",
  blocks = c(
    "data_clean", "imputation",
    "trajectory_creatinine_pct",
    "trajectory_wide_to_long",
    "trajectory_lcmm_fit",
    "trajectory_lcmm_mpcmp_plot",
    "trajectory_lcmm_external_validate",
    "trajectory_outcome_models",
    "trajectory_outcome_adjusted"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
