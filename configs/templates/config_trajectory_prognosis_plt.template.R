###############################################################################
#  config_trajectory_prognosis_plt.template.R — 轨迹预后 PLT 单库模板
###############################################################################

###############################################################################
#  config_trajectory_prognosis_plt.R — 轨迹预后（脓毒症血小板 JLCM + 动态预测）
#  文献: Ye 2024 Burns & Trauma — JLCM platelet trajectory
#  决策树: Decisiontree/decision_tree_trajectory_prognosis_plt.md
#  入口: run/trajectory_prognosis/run_trajectory_prognosis_plt.R
###############################################################################

.batch_project_root <- "Output/Trajectory_Prognosis_Platelet_Sepsis"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_trajectory_prognosis_plt.RData",
    rawdata_obj    = "TrajectoryPlatelet",
    outcome_column = "Mortality_28d",
    id_column      = "ID",
    strip_id_columns_after_imputation = character(0)
  ),

  project = list(
    name = "Trajectory_Prognosis_Platelet",
    disease_code = "07",
    disease = "Sepsis_Platelet_Trajectory",
    literature_pmid = "tkae016",
    database = "eICU+MIMIC",
    study_type = "prognosis",
    classification_mode = "binary",
    analysis_group = "Dead",
    reference_group = "Alive",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),

  survival = list(
    time_var  = "futime",
    event_var = "Mortality_28d",
    index_var = "PLT_0"
  ),

  trajectory = list(
    index_vars = c("Platelet"),
    id_column = "ID",
    time_col_prefix = "PLT_",
    cohort_col = "Cohort",
    discovery_validate = list(discovery_cohort = "eICU", validation_cohort = "MIMIC"),
    survival_time_var = "futime",
    survival_event_var = "Mortality_28d",
    landmark_times = c(1, 7, 14),
    rawdata_obj = "index_df",
    class_for_test = 4L,
    class_for_plot = 4L,
    outcome_vars = c("Mortality_28d"),
    p_threshold = 1.0,
    pause_on_no_results = FALSE,
    cycle = 28L,
    jlcm = list(
      prefer_ng = 4L,
      assessment_times = c(1, 7, 14),
      ndraws = 200L,
      pause_enable = FALSE
    )
  ),

  trajectory_jlcm = list(
    index_vars = c("Platelet"),
    class_range = 2:4,
    rawdata_path_template = "Data/smoke/D02_trajectory_Platelet.RData",
    rawdata_obj = "index_df",
    id_column = "ID",
    time_col_start = 2L,
    time_col_end = 9L,
    time_col_sep = "_",
    survival_time_var = "futime",
    survival_event_var = "Mortality_28d",
    max_followup = 28,
    gridsearch_rep = 5L,
    gridsearch_maxiter = 3L,
    pause_enable = FALSE,
    pause_on_no_output = FALSE,
    pause_on_missing_survival = FALSE
  ),

  trajectory_plot_jlcm = list(
    index_vars = c("Platelet"),
    class_for_plot = 4L,
    cycle = 28L,
    pause_enable = FALSE,
    pause_on_no_figures = FALSE
  ),

  data_clean = list(missing_threshold = 0.5),
  column_mapping = list(enable = FALSE),
  imputation = list(
    missing_col_threshold = 0.5,
    method = "cart",
    m = 5L,
    max_iter = 2L,
    seed = 42L,
    complete_action = 1L,
    export_missing_fig = FALSE
  ),

  baseline_binary = list(
    sig_cutoff = 0.05,
    pause_enable = FALSE,
    early_stop_if_index_ns = FALSE
  ),

  univariate_prognosis = list(
    sig_cutoff = 0.1,
    pause_enable = FALSE
  ),

  multivariate_prognosis = list(
    sig_cutoff = 0.05,
    pause_enable = FALSE,
    pause_on_min_sig_vars = FALSE,
    input_from = "tb1"
  ),

  multicollinearity = list(
    vif_threshold_strict = 4,
    vif_threshold_loose  = 10,
    min_vars_threshold   = 0,
    exclude_vars = c(
      "ID", "Cohort", "futime", "Mortality_28d",
      paste0("PLT_", 0:7)
    ),
    screen = list(csv_name = "VIF_check_screen.csv"),
    final  = list(csv_name = "VIF_check_final.csv")
  ),

  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "07_Sepsis_Platelet_Trajectory",
    protocol_label = "trajectory_prognosis_jlcm_plt",
    project_id = "07_trajectory_prognosis_tkae016",
    literature_default = "Sepsis platelet JLCM prognosis (Ye 2024 Burns Trauma)",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B07"
  )
)

pipeline <- list(
  name = "trajectory_prognosis_plt",
  blocks = c(
    "data_clean", "column_mapping", "imputation",
    "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multicollinearity_final",
    "trajectory_jlcm_discovery_validate",
    "trajectory_prepare_wide_rdata",
    "trajectory_jlcm",
    "trajectory_plot_jlcm",
    "trajectory_chisq",
    "trajectory_piecewise_cox",
    "trajectory_dynpred",
    "trajectory_weibull_compare"
  ),
  render_tables_after = c(
    "imputation", "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multicollinearity_final"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
