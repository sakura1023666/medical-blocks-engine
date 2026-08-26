###############################################################################
#  config_incidence_iptw.R — 单库 MIMIC 发病 Logistic + IPTW 主分析
#  source 后得到: config, pipeline
#  用法: run_incidence_iptw.R
#
#  暴露: MCV；结局: Disease_Group（Urinary_Incontinence vs Continent）
#  数据: Data/mimic/D04_dabiao.RData（对象 dabiao）
#
#  流水线: 插补 → ROC → 单因素/VIF/多因素 → IPTW → IPTW 主分析
###############################################################################

config <- list(
  data = list(
    rawdata_path     = "Data/mimic/D04_dabiao.RData",
    rawdata_obj      = "dabiao",
    outcome_path     = NULL,
    outcome_column   = "Disease_Group",
    id_column        = "subject_id",
    strip_id_columns_after_imputation = c("subject_id", "SEQN", "ID")
  ),

  project = list(
    name                = "MCV Urinary Incontinence IPTW",
    disease             = "Urinary_Incontinence",
    database            = "MIMIC",
    database_type       = "regular",
    study_type          = "incidence",
    classification_mode = "binary",
    analysis_group      = "Urinary_Incontinence",
    reference_group     = "Continent",
    output_dir          = "Output/MCV_Urinary_Incontinence_IPTW",
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root = TRUE
  ),

  incidence = list(
    outcome_var          = "Disease_Group",
    index_var            = "MCV",
    index_component_vars = c("MCV"),
    index_exclude_vars   = c("MCV", "Hemoglobin")
  ),

  logistic = list(
    index_var = "MCV"
  ),

  prediction = list(
    index_vars                          = c("MCV"),
    keep_index_vars_in_regression_table = TRUE
  ),

  plot = list(
    font_family = "Times New Roman"
  ),

  data_clean = list(
    missing_threshold = 0.3,
    age_filter        = NULL,
    drop_columns      = NULL
  ),

  column_mapping = list(
    enable        = TRUE,
    database_type = "MIMIC"
  ),

  imputation = list(
    missing_col_threshold = 0.4,
    method                = "cart",
    m                     = 1L,
    max_iter              = 5L,
    seed                  = 1234L,
    complete_action       = 1L,
    export_missing_fig    = TRUE,
    export_table_s1       = TRUE
  ),

  baseline_binary = list(
    sig_cutoff            = 0.05,
    strata                = "Disease_Group",
    include_vars          = NULL,
    exclude_vars          = c("subject_id", "SEQN"),
    pause_enable          = FALSE,
    pause_on_table1_fail  = FALSE,
    pause_on_min_sig_vars = FALSE,
    pause_min_sig_vars    = 3L
  ),

  roc_simple = list(
    enable             = TRUE,
    write_cutoff_value = TRUE,
    index_var          = "MCV",
    figure_width       = 8,
    figure_height      = 7
  ),

  boxplot = list(
    group_var               = "Disease_Group",
    response_vars           = c("MCV"),
    overall_method          = "kruskal.test",
    pairwise_method         = "wilcox.test",
    brewer_palette          = "Set2",
    relabel_binary_group    = TRUE,
    figure_width            = 8,
    figure_height           = 6,
    pause_enable            = FALSE,
    pause_if_all_overall_ns = FALSE
  ),

  univariate_incidence_binary = list(
    sig_cutoff            = 0.05,
    screening_cutoff      = 0.1,
    excluded_predictors   = c("MCV", "Hemoglobin"),
    required_predictors   = character(0),
    demo_keywords         = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital", "marriage",
      "Income", "PIR", "poverty", "Smoking", "Smoke",
      "Insurance", "Language", "Alcohol"
    ),
    index_transform       = "none",
    pause_enable          = FALSE,
    pause_on_min_sig_vars = FALSE
  ),

  multivariate_incidence_binary = list(
    sig_cutoff            = 0.05,
    input_from            = "vif_screen_pass",
    write_model_factors   = TRUE,
    excluded_predictors   = c("MCV", "Hemoglobin"),
    required_predictors   = character(0),
    demo_keywords         = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital", "marriage",
      "Income", "PIR", "poverty", "Smoking", "Smoke",
      "Insurance", "Language", "Alcohol"
    ),
    pause_enable          = FALSE,
    pause_on_min_sig_vars = FALSE
  ),

  multicollinearity = list(
    vif_threshold_strict = 4,
    vif_threshold_loose  = 10,
    min_vars_threshold   = 0,
    exclude_vars         = c("subject_id", "SEQN", "MCV", "Hemoglobin"),
    vif_design_extra_predictors = character(0),
    vif_append_extra_to_model2_outputs = FALSE,
    export_full_vif_table = TRUE,
    anthropometric_vif_resolution = list(
      enable = FALSE
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

  iptw_balance = list(
    enable            = TRUE,
    exposure_var      = "Index_Group",
    index_var         = "MCV",
    weight_col        = "weight",
    smd_threshold     = 0.1,
    ps_covariates     = NULL,
    exclude_vars      = character(0),
    include_vars      = NULL,
    pause_enable      = TRUE,
    pause_on_ipw_fail = TRUE
  ),

  iptw_association = list(
    enable       = TRUE,
    table_var    = "Index_Group",
    pause_enable = FALSE
  ),

  logistic_quartile_iptw_weighted = list(
    enable       = TRUE,
    index_var    = "MCV",
    group_mode   = "quantile",
    pause_enable = FALSE
  ),

  logistic_tertile_iptw_weighted = list(
    enable       = TRUE,
    index_var    = "MCV",
    group_mode   = "quantile",
    pause_enable = FALSE
  ),

  logistic_binary_iptw_weighted = list(
    enable       = TRUE,
    index_var    = "MCV",
    group_mode   = "predefined",
    group_var    = "Index_Group",
    pause_enable = FALSE
  ),

  rcs_iptw_weighted = list(
    enable                = TRUE,
    index_var             = "MCV",
    knot_quantiles        = c(0.1, 0.5, 0.9),
    histper               = 50,
    lrm_plot_nk           = 3,
    color_seed            = 123,
    pause_enable          = TRUE,
    pause_on_empty_models = TRUE
  ),

  subgroup = list(
    min_n                  = 20,
    age_cutoff             = 75,
    var_source             = "table1_categorical",
    required_subgroup_vars = character(0),
    forbid_subgroup_vars   = c(
      "Index_Group", "Index_Group_Tertile", "Index_Group_Quartile", "MCV_RCS_Group"
    ),
    forest_xlim            = c(0, 5),
    forest_ticks_at        = c(0, 1, 2, 3, 4, 5)
  ),

  subgroup_iptw_weighted = list(
    enable            = TRUE,
    index_var         = "MCV",
    exposure_var      = "Index_Group",
    age_cutoff        = 75,
    forest_xlim       = c(0, 5),
    extra_forbid_vars = c(
      "Language", "Tuberculosis", "Myocardial_Infarction",
      "Hepatitis", "COPD", "Liver_Cirrhosis", "T1DM"
    ),
    pause_enable      = FALSE
  ),

  feature_selection = list(
    enable = FALSE
  )
)

pipeline <- list(
  name   = "incidence_mcv_urinary_incontinence_mimic_iptw",
  blocks = c(
    "data_clean",
    "column_mapping",
    "imputation",
    "baseline_binary",
    "simple_ROC",
    "boxplot",
    "univariate_incidence_binary",
    "multicollinearity_screen",
    "multivariate_incidence_binary",
    "multicollinearity_final",
    "iptw_balance",
    "iptw_association",
    "logistic_quartile_iptw_weighted",
    "logistic_tertile_iptw_weighted",
    "logistic_binary_iptw_weighted",
    "rcs_iptw_weighted",
    "subgroup_iptw_weighted"
  ),
  logistic_gate = list(
    enable = FALSE
  ),
  render_tables_after = c(
    "imputation", "baseline_binary",
    "simple_ROC", "boxplot",
    "univariate_incidence_binary", "multicollinearity_screen",
    "multivariate_incidence_binary", "multicollinearity_final",
    "iptw_balance", "iptw_association",
    "logistic_quartile_iptw_weighted",
    "logistic_tertile_iptw_weighted",
    "logistic_binary_iptw_weighted",
    "rcs_iptw_weighted",
    "subgroup_iptw_weighted"
  ),
  render_figures_after = c(
    "simple_ROC", "boxplot",
    "rcs_iptw_weighted", "subgroup_iptw_weighted"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    dir    = "checkpoints/MCV_Urinary_Incontinence_IPTW"
  )
)
