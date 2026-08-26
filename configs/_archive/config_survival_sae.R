###############################################################################
#  config_survival_sae.R — SAE 人群 + RAR 预后（Cox 闸门 v2，方案 B）
#  决策树: Decisiontree/01decision_tree_survival.md
#  用法: run_survival_sae.R
###############################################################################

config <- list(
  data = list(
    rawdata_path     = "Data/D04_rt_CleanData.RData",
    rawdata_obj      = "rt",
    outcome_path     = NULL,
    outcome_column   = "fustatus",
    id_column        = "subject_id",
    strip_id_columns_after_imputation = c("ID", "subject_id")
  ),

  project = list(
    name             = "SAE",
    disease          = "SAE",
    database         = "MIMIC",
    study_type       = "prognosis",
    classification_mode = "binary",
    analysis_group   = "Non-survivor",
    reference_group  = "Survivor",
    output_dir       = "Output/D04_sae_rar",
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),

  survival = list(
    time_var      = "futime",
    event_var     = "fustatus",
    index_var     = "RAR",
    time_unit     = "days",
    time_divisor  = 1
  ),

  # futime 为天；Cox/KM 均用原始天，不除以 12/365
  km = list(
    xlab          = "Follow-up time (days)",
    ylab          = "Survival probability (%)",
    xlim          = c(0, 180),
    break_time_by = 14,
    summary_time  = 28
  ),

  logistic = list(
    index_var = "RAR"
  ),

  plot = list(
    font_family = "sans"
  ),

  data_clean = list(
    missing_threshold = 0.2,
    age_filter        = NULL,
    drop_columns      = NULL
  ),

  column_mapping = list(
    enable        = TRUE,
    database_type = "MIMIC"
  ),

  imputation = list(
    missing_col_threshold = 0.2,
    method                = "cart",
    m                     = 5L,
    max_iter              = 5L,
    seed                  = 1234L,
    complete_action       = 1L,
    export_missing_fig    = TRUE,
    export_table_s1       = TRUE
  ),

  baseline_binary = list(
    sig_cutoff            = 0.05,
    strata                = NULL,
    include_vars          = NULL,
    exclude_vars          = c("futime", "subject_id", "Micu_Code", "Language"),
    pause_enable          = TRUE,
    pause_on_table1_fail  = TRUE,
    pause_on_min_sig_vars = FALSE,
    pause_min_sig_vars    = 3L
  ),

  force_continuous_vars = c("SIRS"),

  univariate_prognosis = list(
    sig_cutoff           = 0.05,
    screening_cutoff     = 0.1,
    excluded_predictors  = c("Micu_Code", "SIRS"),
    required_predictors  = character(0),
    demo_keywords        = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital_Status", "marriage",
      "income", "Income", "pir", "poverty", "Smoking",
      "BMI", "weight", "height", "Alcohol",
      "Smoke", "Alcohol_drinking", "Language"
    ),
    index_transform      = "none",
    pause_enable         = FALSE
  ),

  multivariate_prognosis = list(
    sig_cutoff           = 0.05,
    input_from           = "vif_screen_pass",
    write_model_factors  = FALSE,
    excluded_predictors  = c("Micu_Code", "SIRS"),
    required_predictors  = character(0),
    demo_keywords        = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital_Status", "marriage",
      "income", "Income", "pir", "poverty", "Smoking",
      "BMI", "weight", "height", "Alcohol",
      "Smoke", "Alcohol_drinking", "Language"
    ),
    pause_enable         = FALSE
  ),

  multicollinearity = list(
    vif_threshold_strict = 4,
    vif_threshold_loose  = 10,
    min_vars_threshold   = 0,
    vif_design_extra_predictors = character(0),
    vif_append_extra_to_model2_outputs = FALSE,
    export_full_vif_table = TRUE,
    anthropometric_vif_resolution = list(
      enable = TRUE,
      vars = c("BMI", "Weight", "Height"),
      prefer_drop_one_order = c("Weight", "Height"),
      apply_in_screen_only = TRUE
    ),
    screen = list(
      table_title = "Multicollinearity Analysis (VIF, univariate p<0.1 screen)",
      csv_name = "VIF_check_screen.csv"
    ),
    final = list(
      table_title = "Multicollinearity Analysis (VIF, multivariate p<0.05)",
      csv_name = "VIF_check_final.csv"
    )
  ),

  cox_quartile = list(
    gate_enable              = TRUE,
    stop_if_crude_highest_ns   = TRUE,
    extend_branch              = "extend_quartile",
    degrade_branch             = "degrade_tertile",
    p_threshold                = 0.05,
    model1_factors             = NULL,
    model2_factors             = NULL,
    covariate_search           = list(
      enable                 = TRUE,
      max_model1_attempts    = 1000L,
      max_model2_attempts    = 1000L,
      on_search_fail         = "degrade"
    ),
    pause_enable               = FALSE,
    pause_on_fit_fail          = TRUE
  ),

  cox_tertile = list(
    gate_enable              = TRUE,
    stop_if_crude_highest_ns   = TRUE,
    extend_branch              = "extend_tertile",
    degrade_branch             = "degrade_binary",
    p_threshold                = 0.05,
    model1_factors             = NULL,
    model2_factors             = NULL,
    covariate_search           = list(
      enable                 = TRUE,
      max_model1_attempts    = 1000L,
      max_model2_attempts    = 1000L,
      on_search_fail         = "degrade"
    ),
    pause_enable               = FALSE,
    pause_on_fit_fail          = TRUE
  ),

  plot_cutoff = list(
    minprop      = 0.2,
    pause_enable = FALSE,
    pause_on_no_output = TRUE
  ),

  cox_binary = list(
    gate_enable              = TRUE,
    stop_if_crude_highest_ns   = TRUE,
    extend_branch              = "extend_binary",
    degrade_branch             = character(0),
    p_threshold                = 0.05,
    group_levels               = c("low", "high"),
    model1_factors             = NULL,
    model2_factors             = NULL,
    covariate_search           = list(
      enable                 = TRUE,
      max_model1_attempts    = 1000L,
      max_model2_attempts    = 1000L,
      on_search_fail         = "stop"
    ),
    cutoff                     = NULL,
    pause_enable               = FALSE,
    pause_on_fit_fail          = TRUE
  ),

  rcs_prognosis = list(
    nk_range = 3:5,
    pause_enable = FALSE
  ),

  km_strata = list(
    time_var      = "futime",
    event_var     = "fustatus",
    event_value   = 1,
    time_divisor  = 1,
    xlab          = NULL,
    ylab          = NULL,
    summary_time  = NULL,
    id_column     = "subject_id",
    single_filename_template = "KM Plot {strata}.pdf",
    # 仅 strata_vars 出图；strata_defs 只派生对应列（不再自动并入 plot_vars）
    strata_vars   = c("RAR_quartile"),
    strata_vars_by_branch = list(
      extend_quartile = c("RAR_quartile"),
      extend_tertile  = c("RAR_tertile")
    ),
    strata_defs   = list(
      RAR_quartile = list(
        source = "RAR",
        type   = "cut_quantile",
        probs  = c(0, 0.25, 0.5, 0.75, 1),
        labels = c("Q1", "Q2", "Q3", "Q4"),
        levels = c("Q1", "Q2", "Q3", "Q4")
      ),
      RAR_tertile = list(
        source = "RAR",
        type   = "cut_quantile",
        probs  = c(0, 1 / 3, 2 / 3, 1),
        labels = c("T1", "T2", "T3"),
        levels = c("T1", "T2", "T3")
      )
    ),
    export_combined = FALSE,
    font_family = "sans",
    pause_enable = FALSE,
    pause_on_no_figures = TRUE
  ),

  segmented_cox_quartile = list(
    pause_enable = FALSE
  ),

  segmented_cox_tertile = list(
    pause_enable = FALSE
  ),

  km_binary = list(
    time_divisor  = 1,
    xlab          = NULL,
    xlim          = NULL,
    break_time_by = NULL,
    pause_enable = FALSE,
    pause_on_no_output = FALSE
  ),

  segmented_cox_binary = list(
    random_covariate_search = list(enable = FALSE),
    pause_enable = FALSE
  ),

  subgroup = list(
    min_n    = 20,
    age_cutoff = 65,
    pause_enable = FALSE
  ),

  feature_selection = list(
    enable = FALSE
  )
)

pipeline <- list(
  name   = "survival_sae_rar_v2",
  blocks = c(
    "data_clean",
    "column_mapping",
    "imputation",
    "baseline_binary",
    "univariate_prognosis",
    "multicollinearity_screen",
    "multivariate_prognosis",
    "multicollinearity_final",
    "cox_quartile",
    "cox_tertile",
    "plot_cutoff",
    "cox_binary",
    "rcs_prognosis",
    "km_strata",
    "segmented_cox_quartile",
    "segmented_cox_tertile",
    "km_binary",
    "segmented_cox_binary",
    "subgroup_prognosis"
  ),
  cox_gate = list(
    enable = TRUE
  ),
  render_tables_after  = c(
    "imputation", "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multicollinearity_final",
    "cox_quartile", "cox_tertile", "cox_binary",
    "segmented_cox_quartile", "subgroup_prognosis"
  ),
  render_figures_after = character(0),
  dual_db = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    dir    = "checkpoints"
  )
)
