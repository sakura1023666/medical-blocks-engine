###############################################################################
#  config_incidence_dual.R — MCV × Urinary_Incontinence 双库发病（NHANES 加权 + MIMIC 普通）
#  暴露: MCV（单因素/多因素/VIF 纳入 index；Model1/Model2 不含 index，由 pipeline 按 index_var 动态排除）
#  额外协变量排除写在 incidence$index_exclude_vars（仅非暴露列，如 Hemoglobin）
#  source 后得到: config, pipeline_nhanes, pipeline_regular
#  用法: run_incidence_dual.R --db nhanes|mimic|both
#
#  闸门 A: column_mapping 后 dual_db_column_harmonize（插补前列对齐）
#  闸门 B: VIF 终后 dual_db_covariate_harmonize（Model1/Model2 临床协变量对齐）
###############################################################################

config <- list(
  data = list(
    rawdata_path     = "Data/nhanes/D04_dabiao_OK.RData",
    rawdata_obj      = "dabiao",
    outcome_path     = NULL,
    outcome_column   = "Disease_Group",
    id_column        = "SEQN",
    strip_id_columns_after_imputation = c("SEQN", "subject_id")
  ),

  project = list(
    name                = "UI_dual",
    disease             = "Urinary_Incontinence",
    database            = "NHANES",
    database_type       = "nhanes",
    study_type          = "incidence",
    classification_mode = "binary",
    analysis_group      = "Urinary_Incontinence",
    reference_group     = "Continent",
    output_dir          = "Output/MCV_Urinary_Incontinence_dual",
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root = TRUE,
    root                = NULL
  ),

  incidence = list(
    outcome_var = "Disease_Group",
    index_var   = "MCV",
    index_component_vars = c("MCV"),
    index_exclude_vars   = c("Hemoglobin")
  ),

  logistic = list(
    index_var = "MCV"
  ),

  index = list(
    enable = FALSE
  ),

  nhanes = list(
    # new_Weight 不在原始数据中：obj block 按 Source_File + 暴露变量自动计算（见 R/nhanes_survey_weight.R）
    survey_weight    = "new_Weight",
    survey_cluster   = "SDMVPSU",
    survey_strata    = "SDMVSTRA",
    cutoff_index_var = "MCV",
    auto_new_weight  = TRUE,
    exclude_cols     = c(
      "ID", "SEQN", "new_Weight",
      "WTINT2YR", "WTMEC2YR", "WTMEC4YR",
      "WTSAF2YR", "WTSAF4YR", "SDMVPSU", "SDMVSTRA", "Source_File"
    )
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
    database_type = "NHANES"
  ),

  imputation = list(
    missing_col_threshold = 0.4,
    method                = "cart",
    m                     = 5L,
    max_iter              = 5L,
    seed                  = 1234L,
    complete_action       = 1L,
    export_missing_fig    = TRUE,
    export_table_s1       = TRUE
  ),

  dual_db = list(
    enable = TRUE,
    mirror_aggregate = TRUE,
    checkpoint_base = "checkpoints/MCV_Urinary_Incontinence_dual",
    harmonization_dir = "checkpoints/MCV_Urinary_Incontinence_dual/harmonization",
    current_db = NULL,
    primary = list(
      name = "NHANES",
      db_type = "nhanes",
      rawdata_path = "Data/nhanes/D04_dabiao_OK.RData",
      rawdata_obj = "dabiao",
      id_column = "SEQN",
      column_mapping_type = "NHANES"
    ),
    secondary = list(
      name = "MIMIC",
      db_type = "regular",
      rawdata_path = "Data/mimic/D04_dabiao.RData",
      rawdata_obj = "dabiao",
      id_column = "subject_id",
      column_mapping_type = "MIMIC"
    ),
    harmonization = list(
      index_component_vars = c("MCV"),
      demo_keywords = c(
        "Age", "Gender", "Sex", "Race", "ethnicity",
        "Education", "edu", "Marital", "marriage",
        "Income", "PIR", "poverty", "Smoking", "Smoke",
        "Insurance", "Language", "Alcohol"
      ),
      common_non_demo_cols = NULL,
      demo_cols_nhanes = NULL,
      demo_cols_mimic = NULL,
      column_keep_nhanes = NULL,
      column_keep_mimic = NULL,
      common_model_factors = NULL,
      harmonized_model1_nhanes = NULL,
      harmonized_model2_nhanes = NULL,
      harmonized_model1_mimic = NULL,
      harmonized_model2_mimic = NULL,
      require_same_clinical_cols = TRUE,
      sync_after_vif_final = TRUE,
      # 闸门 B 协变量来源：单因素 VIF screen（非多因素 VIF final）
      covariate_source = "vif_screen",
      sync_logistic_branch = TRUE,
      subgroup_var_aliases = list(
        Gender = c("Gender", "Sex"),
        Smoking = c("Smoking", "Smoke"),
        Smoke = c("Smoking", "Smoke")
      )
    )
  ),

  # ── NHANES 块 ─────────────────────────────────────────────────────────────
  baseline_nhanes = list(
    sig_cutoff                   = 0.05,
    pause_enable                 = FALSE,
    pause_on_weighted_table_fail = FALSE,
    pause_on_min_sig_vars        = FALSE,
    pause_min_sig_vars           = 3L
  ),

  boxplot = list(
    group_var               = "Disease_Group",
    response_vars           = c("MCV"),
    overall_method          = "kruskal.test",
    pairwise_method         = "wilcox.test",
    pause_enable            = FALSE,
    pause_if_all_overall_ns = FALSE
  ),

  univariate_nhanes = list(
    sig_cutoff            = 0.05,
    screening_cutoff      = 0.1,
    excluded_predictors   = NULL,
    pause_enable          = FALSE,
    pause_on_min_sig_vars = FALSE,
    pause_min_sig_vars    = 3L
  ),

  multivariate_nhanes = list(
    sig_cutoff              = 0.05,
    input_from              = "vif_screen_pass",
    excluded_predictors     = NULL,
    demo_keywords           = c("Age", "Gender", "Race", "Smoking", "Education", "Income"),
    model1_candidate_names  = c("Age", "Gender", "Race"),
    pause_enable            = FALSE,
    pause_on_min_sig_vars   = FALSE,
    pause_min_sig_vars      = 3L
  ),

  multivariate_covariate_resolve = list(
    enable = TRUE,
    fallback_from = "vif_screen_pass"
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
      enable = FALSE
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
    covariate_source = "vif_final_pass",
    demo_factor_names = c(
      "Age", "Gender", "Race", "Smoking", "Education", "Income", "Marital_Status"
    ),
    clinical_factor_names = c(
      "HDL", "Hypertension", "Diabetes", "Lipid_lowering_agents",
      "Hyperlipidemia", "Heart_Failure", "CKD", "COPD"
    ),
    exclude_from_models = c("ID", "SEQN"),
    random_search = list(
      enable               = TRUE,
      max_attempts         = 100L,
      max_inner_attempts   = 20L,
      initial_sample_n     = 1L,
      p_threshold          = NULL,
      require_highest_group_or_gt1 = FALSE,
      require_all_six_p      = FALSE,
      pause_on_search_fail   = FALSE,
      # Crude 显著时要求 Crude + Model1 + Model2 的 p for trend 均 < 阈值
      require_triple_model_sig = TRUE,
      m1_to_m2_fallback    = TRUE
    ),
    model1_factors = NULL,
    model2_factors = NULL
  ),

  logistic_quartile_nhanes_weighted = list(
    index_var = "MCV", include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_all_ns = FALSE,
    extend_branch = "extend_quartile", degrade_branch = "degrade_tertile",
    p_threshold = 0.05, phase = "screen", pause_enable = FALSE,
    pause_on_missing_design = TRUE
  ),
  logistic_tertile_nhanes_weighted = list(
    index_var = "MCV", include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_all_ns = FALSE,
    extend_branch = "extend_tertile", degrade_branch = "degrade_binary",
    p_threshold = 0.05, phase = "screen", pause_enable = FALSE,
    pause_on_missing_design = TRUE
  ),
  logistic_binary_nhanes_weighted = list(
    index_var = "MCV", include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_highest_ns = TRUE,
    extend_branch = "extend_binary", degrade_branch = character(0),
    p_threshold = 0.05, phase = "screen", pause_enable = FALSE,
    pause_on_missing_design = TRUE
  ),

  baseline_binary = list(
    sig_cutoff = 0.05, strata = "Disease_Group",
    include_vars = NULL,
    exclude_vars = c(
      "SEQN", "subject_id", "new_Weight",
      "WTINT2YR", "WTMEC2YR", "WTMEC4YR",
      "WTSAF2YR", "WTSAF4YR", "SDMVPSU", "SDMVSTRA", "Source_File"
    ),
    pause_enable = FALSE, pause_on_table1_fail = FALSE,
    pause_on_min_sig_vars = FALSE, pause_min_sig_vars = 3L
  ),

  logistic_quartile_glm = list(
    index_var = "MCV", include_continuous_row = TRUE,
    pause_enable = FALSE, pause_on_search_fail = FALSE
  ),
  logistic_tertile_glm = list(
    index_var = "MCV", include_continuous_row = TRUE,
    pause_enable = FALSE, pause_on_search_fail = FALSE
  ),
  logistic_binary_glm = list(
    index_var = "MCV", include_continuous_row = TRUE,
    pause_enable = FALSE, pause_on_search_fail = FALSE
  ),

  rcs_nhanes = list(
    index_var = "MCV", max_model1_vars = 4L,
    knot_quantiles = c(0.1, 0.5, 0.9), histper = 25L,
    plot_x_quantiles = c(0.01, 0.99)
  ),

  subgroup = list(
    min_n = 20,
    # 年龄切点依据：写 config 前查本疾病常用界值；默认二分类（age_subgroup_binary 铁律）
    age_cutoff = 65L,
    var_source = "table1_categorical",
    required_subgroup_vars = character(0),
    forbid_subgroup_vars = c(
      "Index_Group", "Index_Group_Tertile", "Index_Group_Quartile", "MCV_RCS_Group"
    ),
    forest_xlim = c(0, 4),
    level_order = list(
      Age_Group = c("< 65", "\u2265 65")
    )
  ),

  # ── 失败指标亚组补救重跑（批量模式功能，详见 R/incidence_subgroup_fallback.R）────
  #  说明：本块为「亚组目录」的统一定义处。自动触发仅在批量流程
  #  (run_incidence_dual_batch.R) 中生效——某指标失败后按亚组剔除人群、重跑整个
  #  发病流程。单库 dual (run_incidence_dual.R) 无 per-index 失败概念，此处 enable=FALSE
  #  仅作声明；把本 config 用于批量时，把 enable 改 TRUE 即生效。
  #  占位符 {age_cutoff} {age_mid_lower} {obesity_cut} 由接口值替换；某库缺所需列则静默跳过。
  incidence_batch = list(
    subgroup_fallback = list(
      enable             = FALSE,
      try_all            = TRUE,     # TRUE=所有亚组都跑、分别报告；FALSE=首个成功即停
      min_n_per_subgroup = 30L,
      sep                = "|",
      age_cutoff         = 65L,      # 老年切点（年龄口径接口）
      age_mid_lower      = 45L,      # 中年段下界
      obesity_standard   = "chinese",# "chinese"(BMI>=28) | "western"(BMI>=30)（肥胖口径接口）
      subgroups = list(
        list(label = "Age_{age_cutoff}",                  expr = "Age >= {age_cutoff}"),
        list(label = "Age_{age_mid_lower}_{age_cutoff}",  expr = "Age >= {age_mid_lower} & Age < {age_cutoff}"),
        list(label = "Hypertension",                      expr = 'Hypertension == "Yes"'),
        list(label = "Diabetes",                          expr = 'Diabetes == "Yes"'),
        list(label = "Obesity_BMI{obesity_cut}",          expr = "BMI >= {obesity_cut}"),
        list(label = "Male",                              expr = 'Gender == "Male"'),       # 当前 dabiao 无 Gender 列 → 自动跳过
        list(label = "Female",                            expr = 'Gender == "Female"'),     # 同上
        list(label = "Non_smoker",                        expr = 'Smoke == "never"'),
        list(label = "Smoker",                            expr = 'Smoke %in% c("current", "former")')
      )
    )
  ),

  mediation_nhanes_weighted = list(
    exposure = "MCV", lab_indicator_vars = NULL, mediators = NULL, covariates = NULL,
    bootstrap_iter = 100L, standardize_mediator = TRUE,
    dual_library_lm_screen = TRUE, lm_screen_alpha = 0.05,
    lm_screen_require_nonneg_beta = TRUE,
    fallback_single_library_model2 = TRUE, auto_covariate_search = FALSE,
    mediation_path_alpha = 0.05, diagram_enable = TRUE, pause_enable = FALSE
  ),

  # ── MIMIC / 普通库块 ───────────────────────────────────────────────────────
  roc_simple = list(
    enable = TRUE,
    mode = "multivariable",
    covariate_source = "locked",
    export_table = FALSE,
    write_cutoff_value = FALSE,
    figure_kind = "supp_figure",
    figure_number = 2L,
    bump_counter = TRUE,
    figure_width = 8, figure_height = 7
  ),

  cutoff = list(
    export_roc_figure = FALSE
  ),

  univariate_incidence_binary = list(
    sig_cutoff = 0.05, screening_cutoff = 0.1,
    excluded_predictors   = NULL,
    required_predictors = character(0),
    include_predictors = NULL,
    demo_keywords = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital", "marriage",
      "Income", "PIR", "poverty", "Smoking", "Smoke",
      "Insurance", "Language", "Alcohol"
    ),
    index_transform = "none",
    pause_enable = FALSE, pause_on_min_sig_vars = FALSE
  ),

  multivariate_incidence_binary = list(
    sig_cutoff = 0.05, input_from = "vif_screen_pass", write_model_factors = TRUE,
    excluded_predictors   = NULL,
    required_predictors = character(0),
    include_predictors = NULL,
    demo_keywords = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital", "marriage",
      "Income", "PIR", "poverty", "Smoking", "Smoke",
      "Insurance", "Language", "Alcohol"
    ),
    pause_enable = FALSE, pause_on_min_sig_vars = FALSE
  ),

  logistic_quartile_glm_mimic = list(
    index_var = "MCV", include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_all_ns = FALSE,
    extend_branch = "extend_quartile", degrade_branch = "degrade_tertile",
    p_threshold = 0.05, phase = "screen",
    random_search = list(
      max_outer_attempts = 100L, max_inner_attempts = 10L,
      initial_factors_n = 1L, p_threshold = 0.05, seed = NULL,
      require_triple_model_sig = TRUE,
      m1_to_m2_fallback = TRUE
    ),
    pause_enable = FALSE, pause_on_search_fail = FALSE
  ),

  rcs_incidence = list(
    index_var = "MCV", nk_range = 3:5, histbin = 1, color_seed = 123,
    group_cutoffs = "primary"
  ),

  mediation_incidence = list(
    exposure = "MCV", mediators = NULL, outcome = NULL,
    bootstrap_iter = 100L, standardize_mediator = TRUE,
    auto_covariate_search = FALSE,
    dual_library_lm_screen = TRUE,
    lm_screen_exclude_vars = c(
      "ID", "subject_id", "Group", "Disease", "Disease_Group",
      "Age", "Gender", "Education", "Smoke", "MCV", "Hemoglobin",
      "Hypertension", "Diabetes"
    ),
    diagram_enable = TRUE, pause_enable = FALSE
  ),

  feature_selection = list(enable = FALSE)
)

# MIMIC logistic 块与单库命名一致（覆盖 index=MCV + gate）
config$logistic_quartile_glm <- modifyList(
  config$logistic_quartile_glm_mimic,
  list(
    index_var = "MCV", gate_enable = TRUE, stop_if_crude_all_ns = FALSE,
    extend_branch = "extend_quartile", degrade_branch = "degrade_tertile",
    p_threshold = 0.05, phase = "screen",
    random_search = list(
      max_outer_attempts = 100L, max_inner_attempts = 10L,
      initial_factors_n = 1L, p_threshold = 0.05, seed = NULL,
      require_triple_model_sig = TRUE,
      m1_to_m2_fallback = TRUE
    ),
    pause_enable = FALSE, pause_on_search_fail = FALSE
  )
)
config$logistic_tertile_glm <- modifyList(
  config$logistic_tertile_glm,
  list(
    index_var = "MCV", gate_enable = TRUE, stop_if_crude_all_ns = FALSE,
    extend_branch = "extend_tertile", degrade_branch = "degrade_binary",
    p_threshold = 0.05, phase = "screen",
    random_search = list(
      max_outer_attempts = 100L, max_inner_attempts = 10L,
      initial_factors_n = 1L, p_threshold = 0.05, seed = NULL,
      require_triple_model_sig = TRUE,
      m1_to_m2_fallback = TRUE
    ),
    pause_enable = FALSE, pause_on_search_fail = FALSE
  )
)
config$logistic_binary_glm <- modifyList(
  config$logistic_binary_glm,
  list(
    index_var = "MCV", gate_enable = TRUE, stop_if_crude_highest_ns = TRUE,
    extend_branch = "extend_binary", degrade_branch = character(0),
    p_threshold = 0.05, phase = "screen",
    random_search = list(
      max_outer_attempts = 100L, max_inner_attempts = 10L,
      initial_factors_n = 1L, p_threshold = 0.05, seed = NULL,
      require_triple_model_sig = TRUE,
      m1_to_m2_fallback = TRUE
    ),
    pause_enable = FALSE, pause_on_search_fail = FALSE
  )
)

pipeline_nhanes <- list(
  name = "incidence_mcv_urinary_incontinence_nhanes_dual",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "imputation",
    "cutoff", "obj", "baseline_nhanes", "boxplot",
    "univariate_nhanes", "multicollinearity_nhanes_screen",
    "multivariate_nhanes", "multivariate_covariate_resolve", "multicollinearity_nhanes_final",
    "dual_db_covariate_harmonize",
    "multivariate_nhanes_harmonized",
    "simple_ROC",
    "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted",
    "dual_db_logistic_scheme_harmonize", "dual_db_logistic_main_table_realign",
    "rcs_nhanes",
    "logistic_quartile_nhanes_weighted_rcs", "logistic_tertile_nhanes_weighted_rcs",
    "logistic_binary_nhanes_weighted_rcs",
    "subgroup_nhanes_weighted", "mediation_nhanes_weighted",
    "baseline_binary", "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm"
  ),
  logistic_gate = list(enable = TRUE, weighted = TRUE),
  render_tables_after = c(
    "imputation", "baseline_nhanes", "univariate_nhanes",
    "multicollinearity_nhanes_screen", "multivariate_nhanes", "multivariate_covariate_resolve",
    "multicollinearity_nhanes_final",
    "dual_db_covariate_harmonize",
    "multivariate_nhanes_harmonized",
    "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted",
    "dual_db_logistic_scheme_harmonize", "dual_db_logistic_main_table_realign",
    "rcs_nhanes",
    "logistic_quartile_nhanes_weighted_rcs", "logistic_tertile_nhanes_weighted_rcs",
    "logistic_binary_nhanes_weighted_rcs",
    "subgroup_nhanes_weighted", "mediation_nhanes_weighted",
    "baseline_binary", "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm"
  ),
  render_figures_after = c(
    "imputation", "cutoff", "boxplot", "simple_ROC", "rcs_nhanes",
    "subgroup_nhanes_weighted", "mediation_nhanes_weighted"
  ),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = "checkpoints/MCV_Urinary_Incontinence_dual/nhanes")
)

pipeline_regular <- list(
  name = "incidence_mcv_urinary_incontinence_mimic_dual",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "imputation",
    "baseline_binary", "boxplot",
    "univariate_incidence_binary", "multicollinearity_screen",
    "multivariate_incidence_binary", "multivariate_covariate_resolve", "multicollinearity_final",
    "dual_db_covariate_harmonize",
    "multivariate_incidence_harmonized",
    "simple_ROC",
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "dual_db_logistic_scheme_harmonize", "dual_db_logistic_main_table_realign",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
    "subgroup_incidence", "mediation_incidence"
  ),
  logistic_gate = list(enable = TRUE),
  render_tables_after = c(
    "imputation", "baseline_binary", "boxplot",
    "univariate_incidence_binary", "multicollinearity_screen",
    "multivariate_incidence_binary", "multivariate_covariate_resolve", "multicollinearity_final",
    "dual_db_covariate_harmonize",
    "multivariate_incidence_harmonized",
    "simple_ROC",
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "dual_db_logistic_scheme_harmonize", "dual_db_logistic_main_table_realign",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
    "subgroup_incidence", "mediation_incidence"
  ),
  render_figures_after = c("simple_ROC", "boxplot", "rcs_incidence", "subgroup_incidence"),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = "checkpoints/MCV_Urinary_Incontinence_dual/mimic")
)

# 兼容仅 source 本文件时期望 pipeline 变量名
pipeline <- pipeline_nhanes
