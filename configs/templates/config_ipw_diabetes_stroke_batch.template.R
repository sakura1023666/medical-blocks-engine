###############################################################################
#  config_ipw_diabetes_stroke_batch.template.R — 用药IPW（Jin · MIMIC · unit=main）
#  （程序员隔离模式：产出写在本研究文件夹）
#
#  复制 studies/_template_ipw_diabetes/ 后改 <TO_CONFIRM*>；勿改 pipeline_* blocks。
#  入口: run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R
#  决策树: docs/Decisiontree/decision_tree_ipw_diabetes_stroke.md
#  规格: docs/superpowers/specs/2026-07-23-ipw-jin-composite-risk-no-index-design.md
#
#  暴露：Diabetes_HbA1c（HbA1c≥6.5）；结局：28天全因死亡
#  无实验室复合指标并行；STEPP 横轴 = Jin 式 composite_risk（VIF 后 Cox LP）
#
#  CLI:
#    run_study.bat <研究名> --routine ipw --shared-only
#    run_study.bat <研究名> --routine ipw --only-unit main --no-skip
###############################################################################

.mb_root <- {
  env <- Sys.getenv("MEDICAL_BLOCKS_ROOT", "")
  if (nzchar(env) && dir.exists(env)) {
    env
  } else {
    env2 <- Sys.getenv("BLOCK_REPO_ROOT", "")
    if (nzchar(env2) && dir.exists(env2)) env2 else {
      cands <- c("E:/01block/01Block-new-Final", "/mnt/e/01block/01Block-new-Final")
      hit <- cands[dir.exists(cands)]
      if (length(hit)) hit[[1]] else normalizePath(getwd(), winslash = "/", mustWork = FALSE)
    }
  }
}
source(file.path(.mb_root, "configs/indices/composite_index_vars.R"))
source(file.path(.mb_root, "Blocks/00_index/01block_index.R"))

.study_config_file <- {
  ca <- commandArgs(trailingOnly = TRUE)
  i  <- match("--config", ca)
  if (!is.na(i) && i < length(ca))
    normalizePath(ca[[i + 1L]], winslash = "/", mustWork = TRUE)
  else
    NA_character_
}
.batch_project_root <- if (!is.na(.study_config_file)) {
  dirname(.study_config_file)
} else {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}
.batch_data_root <- file.path(.batch_project_root, "Data")
.batch_ck_root   <- file.path(.batch_project_root, "checkpoints")

# <TO_CONFIRM_DATA>：相对 Data/mimic/ 的文件名
.baseline_rdata <- file.path(.batch_data_root, "mimic/<TO_CONFIRM_BASELINE_RDATA>")
.dabiao_csv     <- file.path(.batch_data_root, "mimic/<TO_CONFIRM_DABIAO_CSV>")
.prognosis_csv  <- file.path(.batch_data_root, "mimic/<TO_CONFIRM_PROGNOSIS_CSV>")

.disease_exclusion_vars <- c("T1DM", "T2DM", "Diabetes", "HbA1c")

config <- list(
  project = list(
    name = "<TO_CONFIRM_PROJECT_NAME>",          # ❓ IPW_Diabetes_Stroke_MIMIC
    disease = "<TO_CONFIRM_DISEASE>",             # ❓ ischemic_stroke_ipw_diabetes
    disease_code = "<TO_CONFIRM_CODE>",           # ❓ 11
    study_type = "prognosis",
    literature_pmid = "<TO_CONFIRM_PMID>",        # ❓ 42118193
    analysis_group = "1",
    reference_group = "0",
    database = "MIMIC",
    root = .mb_root,
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),

  data = list(
    rawdata_path   = .baseline_rdata,
    rawdata_obj    = "<TO_CONFIRM_RAWDATA_OBJ>",  # ❓ baseline
    id_column      = "ID",
    outcome_column = "surv_event_28d"
  ),

  data_clean = list(
    missing_threshold = 1.0,
    cohort_id_path = .dabiao_csv,
    cohort_id_column = "subject_id",
    supplement_merge_path = .prognosis_csv,
    supplement_merge_id_column = "subject_id",
    supplement_merge_columns = c(
      "hosp_day", "is_hosp_dead", "hosp_survival_day", "death_within_hosp_28days"
    ),
    min_n_after_cohort = 200L
  ),

  column_mapping = list(enable = TRUE, database_type = "MIMIC"),

  index = list(enable = FALSE, only = character(0)),

  imputation = list(
    missing_col_threshold = 0.5,
    method = "cart", m = 5L, max_iter = 5L, seed = 1234L,
    missing_as_supp_figure = TRUE,
    missing_fig_caption = "Missing value overview",
    force_keep_columns = c(
      "HbA1c",
      "hosp_survival_day", "death_within_hosp_28days", "hosp_day", "is_hosp_dead"
    ),
    exclude_from_mice_cols = c(
      "hosp_survival_day", "death_within_hosp_28days", "hosp_day", "is_hosp_dead",
      "surv_time_28d", "surv_event_28d", "Diabetes_HbA1c", "composite_risk"
    ),
    pause_enable = FALSE
  ),

  ipw_diabetes = list(
    hba1c_var = "HbA1c",
    hba1c_threshold = 6.5,
    exposure_var = "Diabetes_HbA1c",
    followup_days = 28L,
    time_source = "hosp_survival_day",
    event_source = "death_within_hosp_28days",
    time_var = "surv_time_28d",
    event_var = "surv_event_28d",
    severity_var = "SOFA",
    pause_enable = FALSE
  ),

  analysis_exclusion = list(
    allow_no_index = TRUE,
    disease_vars = .disease_exclusion_vars,
    component_scope = "none",
    exclude_other_composite_indices = TRUE,
    exclude_exposure_if_uses_disease_var = TRUE,
    composite_index_vars = .composite_index_vars,
    protect_vars = c("Diabetes_HbA1c", "surv_time_28d", "surv_event_28d", "composite_risk")
  ),

  survival = list(
    time_var = "surv_time_28d",
    event_var = "surv_event_28d",
    event_value = 1L,
    index_var = NULL
  ),

  univariate_prognosis = list(
    sig_cutoff = 0.10,
    pause_enable = FALSE,
    excluded_predictors = c(
      "surv_time_28d", "surv_event_28d",
      "hosp_survival_day", "hosp_day", "death_within_hosp_28days", "is_hosp_dead",
      "in-hospital mortality", "Diabetes_HbA1c", "HbA1c", "composite_risk",
      "ID", "subject_id"
    )
  ),

  feature_selection = list(enable = FALSE),

  multicollinearity = list(
    vif_threshold_strict = 4,
    vif_threshold_loose = 10,
    min_vars_threshold = 0,
    pause_enable = FALSE,
    exclude_vars = c(
      "ID", "subject_id", "surv_time_28d", "surv_event_28d",
      "hosp_survival_day", "hosp_day", "death_within_hosp_28days", "is_hosp_dead",
      "Diabetes_HbA1c", "HbA1c", "weight", "composite_risk"
    ),
    screen = list(csv_name = "VIF_check_screen.csv")
  ),

  ipw_jin_composite_risk = list(
    factors = "from_model2",
    exclude_vars = c("Diabetes_HbA1c"),
    time_var = "surv_time_28d",
    event_var = "surv_event_28d",
    out_var = "composite_risk",
    table_caption = "Definition of the composite risk",
    pause_enable = FALSE
  ),

  iptw_balance = list(
    enable = TRUE,
    exposure_var = "Diabetes_HbA1c",
    index_var = "Diabetes_HbA1c",
    exposure_level_labels = list(`0` = "Non-diabetes", `1` = "Diabetes"),
    ps_covariates = "from_model2",
    use_selected_covariates = FALSE,
    use_model2_covariates = TRUE,
    smd_threshold = 0.1,
    supp_balance_fig_style = "jin",
    love_plot_vars = "ps_covariates",
    ps_hist_legend_title = "Diabetes",
    ps_smd_figure_caption = "The distribution of propensity score and standardized mean difference before and after weighting",
    table_style = "jin",
    table_pub_role = "main_table",
    table_caption = "Baseline characteristics before and after sIPTW",
    pause_enable = FALSE
  ),
  iptw_association = list(
    enable = TRUE,
    table_var = "Diabetes_HbA1c",
    outcome_strata = "surv_event_28d",
    pause_enable = FALSE
  ),
  ipw_weighted_km_pub = list(
    level_low = "No",
    level_high = "Yes",
    legend_title = "Diabetes",
    legend_inset = c(0.98, 0.98),
    legend_justification = c(1, 1),
    # NULL → R/color_palettes.R 统一双色；需要强对比时可写 group2 或显式向量
    palette = NULL,
    xlim = c(0, 28),
    ylim = c(0.28, 1.00),
    break_time_by = 7,
    xlab = "Follow-up time (days)",
    ylab = "Survival Probability",
    landmark_day = 28,
    annot_x = 0.5,
    annot_y = 0.295,
    annot_size = 3.3,
    risk_table = TRUE,
    risk_table_height = 0.18,
    risk_table_fontsize = 3.7,
    conf_int = TRUE,
    conf_int_alpha = 0.15,
    plot_width = 7.5,
    plot_height = 7.0,
    pause_enable = FALSE
  ),
  subgroup_iptw_weighted = list(
    enable = TRUE,
    exposure_var = "Diabetes_HbA1c",
    age_cutoff = 65,
    pause_enable = FALSE
  ),
  ipw_subgroup_km_pub = list(
    stratum_var = "Age",
    age_cutoff = 65,
    level_low_label = "< 65",
    level_high_label = "\u2265 65",
    figure_number = 4,
    figure_caption = "Subgroup Kaplan\u2013Meier curves of 28-day mortality by age",
    plot_width = 14,
    plot_height = 7.2,
    pause_enable = FALSE
  ),
  subgroup_treatment_forest = list(
    enable = TRUE,
    treatment_var = "Diabetes_HbA1c",
    reference_level = "0",
    subgroup_vars = c("Gender", "Hypertension", "Heart_Failure", "CKD", "COPD"),
    pause_enable = FALSE
  ),

  stepp_prognosis = list(
    index_var = "composite_risk",
    plot_style = "jin_treatment",
    eval_time_months = 28,
    y_axis_label = "28-Day Survival (%)",
    x_axis_label = "Subpopulations by median composite risk",
    overall = list(window_size = 500L, step_size = 130L),
    by_group = list(
      stratum_var = "Diabetes_HbA1c",
      stratum_levels = c("0", "1"),
      stratum_labels = c("No", "Yes"),
      legend_title = "Diabetes",
      stratum_colors = list(`0` = "#4C72B0", `1` = "#E17C39"),
      window_size = 500L,
      step_size = 130L
    ),
    figure_width = 8,
    figure_height = 5.5,
    figure_caption = "STEPP of 28-day survival by Diabetes across composite risk",
    pause_enable = FALSE
  ),

  cox_binary = list(
    index_var = "Diabetes_HbA1c",
    group_var = "Diabetes_HbA1c",
    group_levels = c("0", "1"),
    covariate_search = list(enable = FALSE),
    require_both_models_sig = FALSE,
    table_caption = "Sensitivity analysis: Multivariable Cox for Diabetes_HbA1c and 28-day mortality",
    table_filename = "Table_Sens_Multivariable_Cox.xlsx",
    pause_enable = FALSE
  ),

  ipw_surv_calibration_roc = list(
    eval_time_days = 28,
    n_cal_groups = 3L,
    covariates = "from_model2",
    include_index = FALSE,
    exclude_exposure = TRUE,
    figure_caption = "Calibration and receiver operating characteristic curves of the prediction model at 28-day",
    figure_width = 10,
    figure_height = 5,
    pause_enable = FALSE
  ),

  study_batch = list(
    output_base = .batch_project_root,
    units = "main",
    unit_mode = "fixed",
    parallel_workers = 1L,
    skip_existing = TRUE,
    worker_script = "run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch_worker.R",
    shared_ck_alias = "column_mapping"
  ),

  feishu = list(
    enable = FALSE,
    app_token = ""
  )
)

pipeline_shared <- list(
  name = "ipw_diabetes_shared",
  blocks = c("data_clean", "column_mapping"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "_shared", "main"))
)

pipeline_unit <- list(
  name = "ipw_diabetes_unit",
  blocks = c(
    "imputation",
    "ipw_diabetes_exposure",
    "analysis_exclusion",
    "univariate_prognosis",
    "multicollinearity_screen",
    "ipw_jin_composite_risk",
    "iptw_balance",
    "iptw_association",
    "ipw_diabetes_flowchart",
    "ipw_weighted_km_pub",
    "subgroup_iptw_weighted",
    "subgroup_treatment_forest",
    "ipw_subgroup_km_pub",
    "stepp_prognosis",
    "cox_binary",
    "ipw_overlap_weights",
    "ipw_surv_calibration_roc",
    "ipw_literature_targets",
    "ipw_pub_export"
  ),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
