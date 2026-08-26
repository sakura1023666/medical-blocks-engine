###############################################################################
#  config_incidence_nhanes.R — D04 BMI × OA（NHANES 加权发病）
#  source 后得到: config, pipeline
#  用法: 由 run_incidence_nhanes.R 加载
#
#  主分析（加权 + logistic_gate，对齐 03 发病单库）:
#    单因素 P<0.1 → VIF<4 → 多因素 P<0.05 → VIF<4
#    → logistic_*_nhanes_weighted（gate）→ rcs_nhanes → *_nhanes_weighted_rcs
#    → 亚组 → 中介
#  敏感性（非加权，主分析后）:
#    baseline_binary + logistic_*_glm
#
#  相对 config_incidence_stroke.R:
#    + nhanes / cutoff / obj / baseline_nhanes / univariate_nhanes / multivariate_nhanes
#    + rcs_nhanes / subgroup_nhanes_weighted / mediation_nhanes_weighted / boxplot
###############################################################################

config <- list(
  data = list(
    rawdata_path     = "Data/nhanes/D04_dabiao_NHANES_2000.RData",
    rawdata_obj      = "dabiao_sample",
    outcome_path     = NULL,
    outcome_column   = "Disease_Group",
    id_column        = "SEQN",
    strip_id_columns_after_imputation = c("SEQN")
  ),

  project = list(
    name                = "OA",
    disease             = "OA",
    database            = "NHANES",
    study_type          = "incidence",
    classification_mode = "binary",
    analysis_group      = "OA",
    reference_group     = "No_OA",
    output_dir          = "Output/D04_BMI_OA_NHANES",
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root = TRUE
  ),

  incidence = list(
    outcome_var = "Disease_Group",
    index_var   = "BMI"
  ),

  logistic = list(
    index_var = "BMI"
  ),

  nhanes = list(
    survey_weight    = "WTMEC2YR",
    survey_cluster   = "SDMVPSU",
    survey_strata    = "SDMVSTRA",
    cutoff_index_var = "BMI",
    exclude_cols     = c(
      "ID", "SEQN", "WTINT2YR", "WTMEC2YR", "SDMVPSU", "SDMVSTRA", "Source_File"
    )
  ),

  prediction = list(
    index_vars                          = c("BMI"),
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
    database_type = "NHANES"
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

  baseline_nhanes = list(
    sig_cutoff                  = 0.05,
    pause_enable                = TRUE,
    pause_on_weighted_table_fail = TRUE,
    pause_on_min_sig_vars       = FALSE,
    pause_min_sig_vars          = 3L
  ),

  boxplot = list(
    group_var               = "Disease_Group",
    response_vars           = c("BMI"),
    overall_method          = "kruskal.test",
    pairwise_method         = "wilcox.test",
    pause_enable            = FALSE,
    pause_if_all_overall_ns = FALSE
  ),

  univariate_nhanes = list(
    sig_cutoff            = 0.05,
    screening_cutoff      = 0.1,
    pause_enable          = TRUE,
    pause_on_min_sig_vars = FALSE,
    pause_min_sig_vars    = 3L
  ),

  multivariate_nhanes = list(
    sig_cutoff              = 0.05,
    input_from              = "vif_screen_pass",
    demo_keywords           = c("Age", "Gender", "Race"),
    model1_candidate_names  = c("Age", "Gender", "Race"),
    pause_enable            = TRUE,
    pause_on_min_sig_vars   = FALSE,
    pause_min_sig_vars      = 3L
  ),

  multicollinearity = list(
    vif_threshold_strict = 4,
    vif_threshold_loose  = 10,
    vif_threshold_hard_drop = 50,
    min_vars_threshold   = 0,
    exclude_vars = c("ID", "SEQN"),
    vif_design_extra_predictors = character(0),
    vif_append_extra_to_model2_outputs = FALSE,
    export_full_vif_table = TRUE,
    anthropometric_vif_resolution = list(
      enable = TRUE,
      vars = c("BMI", "Weight", "Height"),
      protect_vars = c("BMI"),
      prefer_drop_one_order = c("Weight", "Height"),
      apply_in_screen_only = FALSE
    ),
    screen = list(
      table_title = "Weighted Multicollinearity Analysis (VIF, univariate p<0.1 screen, NHANES)",
      csv_name = "VIF_check_screen_weighted.csv"
    ),
    final = list(
      table_title = "Weighted Multicollinearity Analysis (VIF, multivariate p<0.05, NHANES)",
      csv_name = "VIF_check_final_weighted.csv"
    )
  ),

  logistic_nhanes_weighted = list(
    cascade = list(
      crude_p_threshold = 0.05,
      crude_sig_method  = "trend_or_any_group"
    ),
    # 全 Blocks/11_logistic 共用：协变量池 = multicollinearity_nhanes_final (vif_final_pass)
    # Model 1 = 人口学；Model 2 = Model 1 + 临床（均在终筛池内）
    covariate_source = "vif_final_pass",
    demo_factor_names = c(
      "Age", "Gender", "Race", "Smoking", "Education", "Income", "Marital_Status"
    ),
    clinical_factor_names = c(
      "HDL", "Hypertension", "Diabetes", "Lipid_lowering_agents",
      "Hyperlipidemia", "Heart_Failure", "CKD", "COPD"
    ),
    exclude_from_models = c("ID", "SEQN"),
    # crude 显著但 Model1/2 不显著时，从 VIF final 池随机搜索协变量
    random_search = list(
      enable               = TRUE,
      max_attempts         = 1000L,
      max_inner_attempts   = 1000L,
      initial_sample_n     = 1L,
      p_threshold          = NULL,
      require_highest_group_or_gt1 = FALSE,
      require_all_six_p      = FALSE,
      pause_on_search_fail   = FALSE
    ),
    model1_factors = NULL,
    model2_factors = NULL
  ),

  analysis_models = list(
    model3_required_factors = character(0)
  ),

  logistic_quartile_nhanes_weighted = list(
    index_var                = "BMI",
    include_continuous_row   = TRUE,
    gate_enable              = TRUE,
    stop_if_crude_all_ns     = FALSE,
    extend_branch            = "extend_quartile",
    degrade_branch           = "degrade_tertile",
    p_threshold              = 0.05,
    phase                    = "screen",
    group_var                = NULL,
    pause_enable             = FALSE,
    pause_on_missing_design  = TRUE
  ),

  logistic_tertile_nhanes_weighted = list(
    index_var                = "BMI",
    include_continuous_row   = TRUE,
    gate_enable              = TRUE,
    stop_if_crude_all_ns     = FALSE,
    extend_branch            = "extend_tertile",
    degrade_branch           = "degrade_binary",
    p_threshold              = 0.05,
    phase                    = "screen",
    pause_enable             = FALSE,
    pause_on_missing_design  = TRUE
  ),

  logistic_binary_nhanes_weighted = list(
    index_var                  = "BMI",
    include_continuous_row     = TRUE,
    gate_enable                = TRUE,
    stop_if_crude_highest_ns   = TRUE,
    extend_branch              = "extend_binary",
    degrade_branch             = character(0),
    p_threshold                = 0.05,
    phase                      = "screen",
    pause_enable               = FALSE,
    pause_on_missing_design    = TRUE
  ),

  # 敏感性分析：非加权 Table 1（baseline_nhanes 块内另有 Table S8）
  baseline_binary = list(
    sig_cutoff            = 0.05,
    strata                = "Disease_Group",
    include_vars          = NULL,
    exclude_vars          = c(
      "SEQN", "WTINT2YR", "WTMEC2YR", "SDMVPSU", "SDMVSTRA", "Source_File"
    ),
    pause_enable          = TRUE,
    pause_on_table1_fail  = TRUE,
    pause_on_min_sig_vars = FALSE,
    pause_min_sig_vars    = 3L
  ),

  # 敏感性分析：非加权 Logistic；分位方案与加权 cascade 一致（见 pipeline 中 logistic_*_glm 三选一）
  logistic_quartile_glm = list(
    index_var              = "BMI",
    include_continuous_row = TRUE,
    pause_enable           = FALSE,
    pause_on_search_fail   = FALSE
  ),

  logistic_tertile_glm = list(
    index_var              = "BMI",
    include_continuous_row = TRUE,
    pause_enable           = FALSE,
    pause_on_search_fail   = FALSE
  ),

  logistic_binary_glm = list(
    index_var              = "BMI",
    include_continuous_row = TRUE,
    pause_enable           = FALSE,
    pause_on_search_fail   = FALSE
  ),

  rcs_nhanes = list(
    index_var       = "BMI",
    max_model1_vars = 4L,
    knot_quantiles  = c(0.1, 0.5, 0.9),
    histper         = 25L,
    plot_x_quantiles = c(0.01, 0.99)
  ),

  subgroup = list(
    min_n                  = 20,
    # 年龄切点依据：写 config 前查本疾病常用界值；默认二分类（age_subgroup_binary 铁律）
    age_cutoff             = 65L,
    required_subgroup_vars = c(
      "Age", "Gender", "Race", "BMI",
      "Smoke", "Hypertension", "Diabetes"
    ),
    forest_xlim            = c(0, 4),
    level_order = list(
      Age_Group = c("< 65", "\u2265 65")
    )
  ),

  feature_selection = list(
    enable = FALSE
  ),

  mediation_nhanes_weighted = list(
    exposure                   = "BMI",
    lab_indicator_vars         = NULL,
    mediators                  = NULL,
    covariates                 = NULL,
    bootstrap_iter             = 100L,
    standardize_mediator       = FALSE,
    dual_library_lm_screen     = TRUE,
    lm_screen_alpha            = 0.05,
    lm_screen_require_nonneg_beta = TRUE,
    fallback_single_library_model2 = TRUE,
    auto_covariate_search = FALSE,
    mediation_path_alpha       = 0.05,
    diagram_enable             = TRUE,
    pause_enable               = FALSE
  ),

  # 发表 ROC：锁定多因素协变量（simple_ROC 在 multivariate_nhanes_harmonized 之后）
  roc_simple = list(
    enable = TRUE,
    mode = "multivariable",
    covariate_source = "locked",
    export_table = FALSE,
    figure_kind = "supp_figure",
    figure_number = 2L,
    bump_counter = TRUE
  ),

  # Youden 截断仍计算；发表 ROC 图默认关闭（避免与 simple_ROC 抢 Figure S1）
  cutoff = list(
    export_roc_figure = FALSE
  )
)

pipeline <- list(
  name   = "incidence_d04_bmi_oa_nhanes",
  blocks = c(
    "data_clean",
    "column_mapping",
    "imputation",
    "cutoff",
    "obj",
    "baseline_nhanes",
    "boxplot",
    "univariate_nhanes",
    "multicollinearity_nhanes_screen",
    "multivariate_nhanes",
    "multicollinearity_nhanes_final",
    "multivariate_nhanes_harmonized",
    "simple_ROC",
    "logistic_quartile_nhanes_weighted",
    "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted",
    "rcs_nhanes",
    "logistic_quartile_nhanes_weighted_rcs",
    "logistic_tertile_nhanes_weighted_rcs",
    "logistic_binary_nhanes_weighted_rcs",
    "subgroup_nhanes_weighted",
    "mediation_nhanes_weighted",
    "baseline_binary",
    "logistic_quartile_glm",
    "logistic_tertile_glm",
    "logistic_binary_glm"
  ),
  logistic_gate = list(
    enable   = TRUE,
    weighted = TRUE
  ),
  render_tables_after = c(
    "imputation",
    "baseline_nhanes",
    "univariate_nhanes",
    "multicollinearity_nhanes_screen",
    "multivariate_nhanes",
    "multicollinearity_nhanes_final",
    "multivariate_nhanes_harmonized",
    "logistic_quartile_nhanes_weighted",
    "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted",
    "rcs_nhanes",
    "logistic_quartile_nhanes_weighted_rcs",
    "logistic_tertile_nhanes_weighted_rcs",
    "logistic_binary_nhanes_weighted_rcs",
    "subgroup_nhanes_weighted",
    "mediation_nhanes_weighted",
    "baseline_binary",
    "logistic_quartile_glm",
    "logistic_tertile_glm",
    "logistic_binary_glm"
  ),
  render_figures_after = c(
    "imputation",
    "cutoff",
    "boxplot",
    "simple_ROC",
    "rcs_nhanes",
    "subgroup_nhanes_weighted",
    "mediation_nhanes_weighted"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    dir    = "checkpoints/D04_BMI_OA_NHANES"
  )
)
