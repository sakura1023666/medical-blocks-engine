###############################################################################
#  config_incidence_single.template.R — 单库发病 Logistic 流水线配置模板
#
#  使用步骤:
#    1. 复制本文件到研究输出目录
#    2. 修改下方【必改】键：data$rawdata_path/obj/id_column、暴露/结局、output_dir
#    3. 运行: Rscript run_incidence_single.R --config "<your_config_path>"
#
#  【不要改】: pipeline blocks 列表、VIF 阈值
#  source 后得到: config, pipeline
#  用法: 由 run_incidence_single.R 加载
#
#  结局: Disease（stroke vs Normal）；暴露: CLR
#  变量筛选: 单因素 p<0.1 → VIF(screen) → 多因素 p<0.05 → VIF(final)
###############################################################################

config <- list(
  data = list(
    rawdata_path     = "Data/D01_CHARLS.RData",
    rawdata_obj      = "CHARLS",
    outcome_path     = NULL,
    outcome_column   = "Disease",
    id_column        = "ID",
    strip_id_columns_after_imputation = c("ID", "SEQN")
  ),

  project = list(
    name                = "Circadian Rhythm",
    disease             = "Circadian Rhythm",
    database            = "MIMIC",
    study_type          = "incidence",
    classification_mode = "binary",
    analysis_group      = "Circadian_Rhythm",
    reference_group     = "Non_Circadian_Rhythm",
    output_dir          = "Output/D05_Circadian_Rhythm",
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root = TRUE
  ),

  incidence = list(
    outcome_var = "Disease",
    index_var   = "MCMI"
  ),

  logistic = list(
    index_var = "MCMI"
  ),

  prediction = list(
    index_vars                          = c("MCMI"),
    keep_index_vars_in_regression_table = TRUE
  ),

  plot = list(
    font_family = "Times New Roman"
    # 分类色默认走 R/color_palettes.R；可选覆盖：
    # , palette_group = 1L          # 同 n 下 group1/group2
    # , colors = c("#CE4844", "#2A73BA")  # 显式色向量（优先于色板）
  ),

  attrition = list(
    enable = TRUE,
    title = NULL,
    db_label = NULL,
    steps = list(),
    # CONSORT Figure 1：主列纳入、右侧 Exclude、底部分叉（发病=病例/对照）
    outcome_breakdown = TRUE,
    auto_append = TRUE,
    draw_pdf = TRUE,
    csv_name = "Flowchart_attrition.csv",
    figure_name = "Figure 1. Inclusion exclusion flowchart.pdf",
    specialty_figure_mode = "skip_if_generic"
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

  baseline_binary = list(
    sig_cutoff            = 0.05,
    strata                = NULL,
    include_vars          = NULL,
    exclude_vars          = c("ID", "SEQN", "Age_Group"),
    pause_enable          = TRUE,
    pause_on_table1_fail  = TRUE,
    pause_on_min_sig_vars = FALSE,
    pause_min_sig_vars    = 3L
  ),

  roc_simple = list(
    enable             = TRUE,
    mode               = "multivariable",
    covariate_source   = "locked",
    export_table       = FALSE,
    write_cutoff_value = FALSE,
    figure_width       = 8,
    figure_height      = 7
  ),

  boxplot = list(
    group_var            = NULL,
    response_vars        = c("MCMI", "Age", "BMI", "SBP", "DBP", "PP", "CRP",
                             "Fasting_Glucose", "HbA1C", "HDL", "LDL",
                             "Hemoglobin", "Total_Cholesterol",
                             "White_blood_cell_count", "Triglycerides",
                             "Waist_circumstance"),
    overall_method       = "kruskal.test",
    pairwise_method      = "wilcox.test",
    brewer_palette       = "block",
    relabel_binary_group = TRUE,
    figure_width         = 8,
    figure_height        = 6
  ),

  univariate_incidence_binary = list(
    sig_cutoff           = 0.05,
    screening_cutoff     = 0.1,
    # 若 baseline_binary$include_vars 非空，默认只对 Table 1 特征做单因素（设 FALSE 可关闭）
    univariate_from_baseline_table1 = NULL,
    include_predictors   = character(0),
    excluded_predictors  = character(0),
    required_predictors  = character(0),
    demo_keywords        = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital_Status", "marriage",
      "Income", "PIR", "poverty", "Smoking",
      "BMI", "weight", "height", "Alcohol",
      "Smoke", "Alcohol_drinking"
    ),
    index_transform      = "none",
    pause_enable         = TRUE,
    pause_on_min_sig_vars = FALSE
  ),

  multivariate_incidence_binary = list(
    sig_cutoff           = 0.05,
    input_from           = "vif_screen_pass",
    write_model_factors  = TRUE,
    excluded_predictors  = character(0),
    required_predictors  = character(0),
    demo_keywords        = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital_Status", "marriage",
      "Income", "PIR", "poverty", "Smoking",
      "BMI", "weight", "height", "Alcohol",
      "Smoke", "Alcohol_drinking"
    ),
    pause_enable         = TRUE,
    pause_on_min_sig_vars = FALSE
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

  logistic_quartile_glm = list(
    index_var              = "MCMI",
    include_continuous_row = TRUE,
    gate_enable            = TRUE,
    stop_if_crude_all_ns   = FALSE,
    extend_branch          = "extend_quartile",
    degrade_branch         = "degrade_tertile",
    p_threshold            = 0.05,
    phase                  = "screen",
    random_search = list(
      max_outer_attempts = 100L,
      max_inner_attempts = 10L,
      initial_factors_n  = 1L,
      p_threshold        = 0.05,
      seed               = NULL
    ),
    pause_enable           = FALSE,
    pause_on_search_fail   = FALSE
  ),

  logistic_tertile_glm = list(
    index_var              = "MCMI",
    include_continuous_row = TRUE,
    gate_enable            = TRUE,
    stop_if_crude_all_ns   = FALSE,
    extend_branch          = "extend_tertile",
    degrade_branch         = "degrade_binary",
    p_threshold            = 0.05,
    phase                  = "screen",
    random_search = list(
      max_outer_attempts = 100L,
      max_inner_attempts = 10L,
      initial_factors_n  = 1L,
      p_threshold        = 0.05,
      seed               = NULL
    ),
    pause_enable           = FALSE,
    pause_on_search_fail   = FALSE
  ),

  logistic_binary_glm = list(
    index_var              = "MCMI",
    include_continuous_row = TRUE,
    gate_enable            = TRUE,
    # 二分失败（不显著/分离）→ 五分位末招；无 quintile 块时再 stop
    stop_if_crude_highest_ns = FALSE,
    extend_branch          = "extend_binary",
    degrade_branch         = "degrade_quintile",
    p_threshold            = 0.05,
    phase                  = "screen",
    random_search = list(
      max_outer_attempts = 100L,
      max_inner_attempts = 10L,
      initial_factors_n  = 1L,
      p_threshold        = 0.05,
      seed               = NULL
    ),
    pause_enable           = FALSE,
    pause_on_search_fail   = FALSE
  ),

  logistic_quintile_glm = list(
    index_var              = "MCMI",
    include_continuous_row = TRUE,
    gate_enable            = TRUE,
    stop_if_separation     = TRUE,
    stop_if_crude_all_ns   = TRUE,
    extend_branch          = "extend_quintile",
    degrade_branch         = character(0),
    p_threshold            = 0.05,
    phase                  = "screen",
    random_search = list(
      max_outer_attempts = 100L,
      max_inner_attempts = 10L,
      initial_factors_n  = 1L,
      p_threshold        = 0.05,
      seed               = NULL
    ),
    pause_enable           = FALSE,
    pause_on_search_fail   = FALSE
  ),

  rcs_incidence = list(
    index_var          = "MCMI",
    nk_range           = 3:5,
    histbin            = 1,
    color_seed         = 123,
    # Table S-XX / logistic_*_glm_rcs：只用主 cutoff 二分；图仍可标全部交点（rcs_cutoffs_all）
    group_cutoffs      = "primary"
  ),

  subgroup = list(
    min_n                    = 20,
    required_subgroup_vars   = c(
      "Age_Group", "Gender", "BMI",
      "Smoking", "Hypertension", "Diabetes"
    ),
    forest_xlim              = c(0, 8)
  ),

  mediation_incidence = list(
    exposure                = "MCMI",
    mediators               = NULL,
    outcome                 = NULL,
    bootstrap_iter          = 100L,
    standardize_mediator    = TRUE,
    auto_covariate_search = FALSE,
    dual_library_lm_screen  = TRUE,
    lm_screen_exclude_vars  = c(
      "ID", "Group", "Disease",
      "Age", "Gender", "Residence", "Marital_Status", "Education",
      "Smoke", "Alcohol_drinking",
      "Height", "Weight", "BMI",
      "Hypertension", "Diabetes"
    ),
    diagram_enable          = TRUE,
    pause_enable            = FALSE
  ),

  feature_selection = list(
    enable = FALSE
  )
)

pipeline <- list(
  name   = "incidence_d05_clr_stroke_full",
  blocks = c(
    "data_clean",
    "column_mapping",
    "imputation",
    "baseline_binary",
    "boxplot",
    "univariate_incidence_binary",
    "multicollinearity_screen",
    "multivariate_incidence_binary",
    "multicollinearity_final",
    "multivariate_incidence_harmonized",
    "simple_ROC",
    "logistic_quartile_glm",
    "logistic_tertile_glm",
    "logistic_binary_glm",
    "logistic_quintile_glm",
    "rcs_incidence",
    "logistic_quartile_glm_rcs",
    "logistic_tertile_glm_rcs",
    "logistic_binary_glm_rcs",
    "logistic_quintile_glm_rcs",
    "subgroup_incidence",
    "mediation_incidence"
  ),
  logistic_gate = list(
    enable = TRUE
  ),
  render_tables_after  = c(
    "imputation", "baseline_binary",
    "boxplot",
    "univariate_incidence_binary", "multicollinearity_screen",
    "multivariate_incidence_binary", "multicollinearity_final",
    "multivariate_incidence_harmonized",
    "simple_ROC",
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "logistic_quintile_glm",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
    "logistic_quintile_glm_rcs",
    "subgroup_incidence", "mediation_incidence"
  ),
  render_figures_after = character(0),
  dual_db = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    dir    = "checkpoints/D05_Circadian_Rhythm"
  )
)
