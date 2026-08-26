###############################################################################
#  config_batch.R — 复合指标 × ARDS 双普通库（eICU + MIMIC）发病批量配置
#
#  基础: config_incidence_dual_batch.template.R（v5 三层 batch）
#  双引擎: primary/secondary 均为普通库（db_type=regular）→ 两库都跑普通 GLM 流水线
#          （引擎按 db_type 选流水线，本 config 不跑 NHANES 加权块）
#
#  source 后产物: config, pipeline_shared_*, pipeline_nhanes_batch, pipeline_regular_batch
#
#  暴露: dual_safe 复合指标批量（index_vars=NULL → composite_index_vars.R）
#  额外排除: Hemoglobin（via base_exclude_vars）
#
#  产出根目录: G:/02block_result/{疾病编码}_{疾病}/{study_type}_{PubMedID}/
###############################################################################

.batch_project_root <- "G:/02block_result/01_ARDS/incidence_38341157"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")
.batch_data_root    <- file.path(.batch_project_root, "Data")

config <- list(

  # ── 数据 ──────────────────────────────────────────────────────────────────
  data = list(
    rawdata_path     = file.path(.batch_data_root, "eicu/D01_eicu.RData"),
    rawdata_obj      = "eicu",
    outcome_path     = NULL,
    outcome_column   = "Disease_Group",
    id_column        = "ID",
    strip_id_columns_after_imputation = c("ID", "subject_id", "SEQN")
  ),

  # ── 项目 ──────────────────────────────────────────────────────────────────
  project = list(
    name                = "ARDS_dual_batch",
    disease_code        = "01",
    disease             = "ARDS",
    literature_pmid     = "38341157",
    database            = "eICU",
    database_type       = "regular",
    study_type          = "incidence",
    classification_mode = "binary",
    analysis_group      = "ARDS",
    reference_group     = "Non_ARDS",
    output_dir          = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root  = TRUE,
    root                = NULL
  ),

  # ── 发病（index_var 由 batch runner patch）────────────────────────────────
  incidence = list(
    outcome_var          = "Disease_Group",
    index_var            = NULL,
    index_component_vars = NULL,
    index_exclude_vars   = NULL
  ),

  logistic = list(
    index_var = NULL
  ),

  # ── 复合指标（批量多指标须 enable=TRUE；仅跑单个原生列时可设 FALSE）────────
  index = list(
    enable = TRUE,
    only   = NULL,
    skip   = NULL,
    digits = 4L
  ),

  # ── NHANES 复杂抽样权重 ──────────────────────────────────────────────────
  nhanes = list(
    survey_weight    = "new_Weight",
    survey_cluster   = "SDMVPSU",
    survey_strata    = "SDMVSTRA",
    cutoff_index_var = NULL,
    auto_new_weight  = TRUE,
    exclude_cols     = c(
      "ID", "SEQN", "new_Weight",
      "WTINT2YR", "WTMEC2YR", "WTMEC4YR",
      "WTSAF2YR", "WTSAF4YR", "SDMVPSU", "SDMVSTRA", "Source_File"
    )
  ),

  prediction = list(
    index_vars                          = NULL,
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
    m                     = 1L,
    max_iter              = 5L,
    seed                  = 1234L,
    complete_action       = 1L,
    export_missing_fig    = TRUE,
    export_table_s1       = TRUE
  ),

  dual_db = list(
    enable            = TRUE,
    mirror_aggregate  = TRUE,
    checkpoint_base   = .batch_ck_root,
    harmonization_dir = file.path(.batch_ck_root, "_global_harmonization"),
    current_db        = NULL,
    primary = list(
      name                = "eICU",
      db_type             = "regular",
      rawdata_path        = file.path(.batch_data_root, "eicu/D01_eicu.RData"),
      rawdata_obj         = "eicu",
      id_column           = "ID",
      column_mapping_type = "eICU"
    ),
    secondary = list(
      name                = "MIMIC",
      db_type             = "regular",
      rawdata_path        = file.path(.batch_data_root, "mimic/D01_mimic.RData"),
      rawdata_obj         = "mimic",
      id_column           = "ID",
      column_mapping_type = "MIMIC"
    ),
    harmonization = list(
      index_component_vars       = NULL,
      demo_keywords = c(
        "Age", "Gender", "Sex", "Race", "ethnicity",
        "Education", "edu", "Marital", "marriage",
        "Income", "PIR", "poverty", "Smoking", "Smoke",
        "Insurance", "Language", "Alcohol"
      ),
      common_non_demo_cols       = NULL,
      demo_cols_nhanes           = NULL,
      demo_cols_mimic            = NULL,
      column_keep_nhanes         = NULL,
      column_keep_mimic          = NULL,
      common_model_factors       = NULL,
      harmonized_model1_nhanes   = NULL,
      harmonized_model2_nhanes   = NULL,
      harmonized_model1_mimic    = NULL,
      harmonized_model2_mimic    = NULL,
      require_same_clinical_cols = TRUE,
      sync_after_vif_final       = TRUE,
      covariate_source           = "vif_screen",
      sync_logistic_branch       = TRUE,
      subgroup_var_aliases = list(
        Gender  = c("Gender", "Sex"),
        Smoking = c("Smoking", "Smoke"),
        Smoke   = c("Smoking", "Smoke")
      )
    )
  ),

  # ── 飞书结果管理表 ────────────────────────────────────────────────────────
  feishu = list(
    enable             = TRUE,
    app_id             = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret         = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token          = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id           = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    literature_default = "eICU + MIMIC 发病双普通库（01 ARDS, PMID 38341157）",
    project_id         = "01_ARDS_incidence_38341157",
    owner_default      = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    disease_label  = "01_ARDS",
    protocol_label = "01_ARDS_incidence_38341157",
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", "")
  ),

  # ── 批量控制 ──────────────────────────────────────────────────────────────
  incidence_batch = list(
    index_vars       = NULL,
    index_group      = "dual_safe",
    parallel_workers = NULL,
    fail_policy      = "continue",
    skip_existing    = TRUE,
    db_mode          = "both",
    output_base      = .batch_project_root,
    shared_ck_base   = file.path(.batch_ck_root, "_shared"),
    index_ck_base    = file.path(.batch_ck_root, "by_index"),
    ram_per_worker_gb = 2.0,
    cpu_headroom      = 2L,
    ram_headroom_gb   = 4.0,
    max_workers       = NULL,
    gate_a_missing_threshold    = 1.0,
    min_valid_per_db            = 50L,
    nhanes_imputation_threshold = 0.40,
    mimic_imputation_threshold  = 0.40,
    base_exclude_vars = c(
      "ID", "SEQN", "subject_id", "Hemoglobin",
      "new_Weight",
      "WTINT2YR", "WTMEC2YR", "WTMEC4YR",
      "WTSAF2YR", "WTSAF4YR", "SDMVPSU", "SDMVSTRA", "Source_File"
    ),
    extra_index_exclude_vars = c("Hemoglobin"),
    base_subgroup_vars = c("Age", "Gender", "Race", "Hypertension", "T2DM",
                           "COPD", "Heart_Failure", "CKD", "Pneumonia")
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
    response_vars           = NULL,
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
    vif_threshold_strict      = 4,
    vif_threshold_loose       = 10,
    vif_threshold_hard_drop   = 50,
    min_vars_threshold        = 0,
    exclude_vars              = NULL,
    vif_design_extra_predictors = character(0),
    vif_append_extra_to_model2_outputs = FALSE,
    export_full_vif_table     = TRUE,
    anthropometric_vif_resolution = list(enable = FALSE),
    screen = list(
      table_title = "Weighted Multicollinearity Analysis (VIF, univariate p<0.1 screen, NHANES)",
      csv_name    = "VIF_check_screen_weighted.csv"
    ),
    final = list(
      table_title = "Weighted Multicollinearity Analysis (VIF, multivariate p<0.05, NHANES)",
      csv_name    = "VIF_check_final_weighted.csv"
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
    exclude_from_models = NULL,
    random_search = list(
      enable                   = TRUE,
      max_attempts             = 100L,
      max_inner_attempts       = 20L,
      initial_sample_n         = 1L,
      p_threshold              = NULL,
      require_highest_group_or_gt1 = FALSE,
      require_all_six_p        = FALSE,
      pause_on_search_fail     = FALSE,
      require_triple_model_sig = TRUE,
      m1_to_m2_fallback        = TRUE
    ),
    model1_factors = NULL,
    model2_factors = NULL
  ),

  logistic_quartile_nhanes_weighted = list(
    index_var = NULL, include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_all_ns = FALSE,
    extend_branch = "extend_quartile", degrade_branch = "degrade_tertile",
    p_threshold = 0.05, phase = "screen", pause_enable = FALSE,
    pause_on_missing_design = TRUE
  ),
  logistic_tertile_nhanes_weighted = list(
    index_var = NULL, include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_all_ns = FALSE,
    extend_branch = "extend_tertile", degrade_branch = "degrade_binary",
    p_threshold = 0.05, phase = "screen", pause_enable = FALSE,
    pause_on_missing_design = TRUE
  ),
  logistic_binary_nhanes_weighted = list(
    index_var = NULL, include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_highest_ns = TRUE,
    extend_branch = "extend_binary", degrade_branch = character(0),
    p_threshold = 0.05, phase = "screen", pause_enable = FALSE,
    pause_on_missing_design = TRUE
  ),

  rcs_nhanes = list(
    index_var = NULL, max_model1_vars = 4L,
    knot_quantiles = c(0.1, 0.5, 0.9), histper = 25L
  ),

  subgroup = list(
    min_n = 20,
    var_source = "table1_categorical",
    required_subgroup_vars = NULL,
    forbid_subgroup_vars = c(
      "Index_Group", "Index_Group_Tertile", "Index_Group_Quartile", "MCV_RCS_Group"
    ),
    forest_xlim = c(0, 4)
  ),

  mediation_nhanes_weighted = list(
    exposure = NULL, lab_indicator_vars = NULL, mediators = NULL, covariates = NULL,
    bootstrap_iter = 100L, standardize_mediator = FALSE,
    dual_library_lm_screen = TRUE, lm_screen_alpha = 0.05,
    lm_screen_require_nonneg_beta = TRUE,
    fallback_single_library_model2 = TRUE, auto_covariate_search = TRUE,
    mediation_path_alpha = 0.05, diagram_enable = TRUE, pause_enable = FALSE
  ),

  # ── MIMIC / 普通库块 ───────────────────────────────────────────────────────
  roc_simple = list(
    enable = TRUE, write_cutoff_value = TRUE, export_table = FALSE,
    figure_width = 8, figure_height = 7
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

  univariate_incidence_binary = list(
    sig_cutoff = 0.05, screening_cutoff = 0.1,
    excluded_predictors = NULL,
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
    excluded_predictors = NULL,
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

  logistic_quartile_glm = list(
    index_var = NULL, include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_all_ns = FALSE,
    extend_branch = "extend_quartile", degrade_branch = "degrade_tertile",
    p_threshold = 0.05, phase = "screen",
    random_search = list(
      max_outer_attempts = 100L, max_inner_attempts = 10L,
      initial_factors_n = 1L, p_threshold = 0.05, seed = NULL,
      require_triple_model_sig = TRUE, m1_to_m2_fallback = TRUE
    ),
    pause_enable = FALSE, pause_on_search_fail = FALSE
  ),
  logistic_tertile_glm = list(
    index_var = NULL, include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_all_ns = FALSE,
    extend_branch = "extend_tertile", degrade_branch = "degrade_binary",
    p_threshold = 0.05, phase = "screen",
    random_search = list(
      max_outer_attempts = 100L, max_inner_attempts = 10L,
      initial_factors_n = 1L, p_threshold = 0.05, seed = NULL,
      require_triple_model_sig = TRUE, m1_to_m2_fallback = TRUE
    ),
    pause_enable = FALSE, pause_on_search_fail = FALSE
  ),
  logistic_binary_glm = list(
    index_var = NULL, include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_highest_ns = TRUE,
    extend_branch = "extend_binary", degrade_branch = character(0),
    p_threshold = 0.05, phase = "screen",
    random_search = list(
      max_outer_attempts = 100L, max_inner_attempts = 10L,
      initial_factors_n = 1L, p_threshold = 0.05, seed = NULL,
      require_triple_model_sig = TRUE, m1_to_m2_fallback = TRUE
    ),
    pause_enable = FALSE, pause_on_search_fail = FALSE
  ),

  rcs_incidence = list(
    index_var = NULL, nk_range = 3:5, histbin = 1, color_seed = 123
  ),

  mediation_incidence = list(
    exposure = NULL, mediators = NULL, outcome = NULL,
    bootstrap_iter = 100L, auto_covariate_search = TRUE,
    dual_library_lm_screen = TRUE,
    lm_screen_exclude_vars = c(
      "ID", "subject_id", "Group", "Disease", "Disease_Group",
      "Age", "Gender", "Education", "Smoke", "Hemoglobin",
      "Hypertension", "Diabetes"
    ),
    diagram_enable = TRUE, pause_enable = FALSE
  ),

  feature_selection = list(enable = FALSE)
)

# ── 共享层流水线（每库 1 次）───────────────────────────────────────────────
pipeline_shared_nhanes <- list(
  name   = "mcv_ui_dual_batch_shared_nhanes",
  blocks = c("data_clean", "column_mapping", "dual_db_column_harmonize", "index"),
  logistic_gate = list(enable = FALSE),
  render_tables_after  = character(0),
  render_figures_after = character(0),
  dual_db    = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    dir    = file.path(.batch_ck_root, "_shared", "nhanes")
  )
)

pipeline_shared_regular <- list(
  name   = "mcv_ui_dual_batch_shared_mimic",
  blocks = c("data_clean", "column_mapping", "dual_db_column_harmonize", "index"),
  logistic_gate = list(enable = FALSE),
  render_tables_after  = character(0),
  render_figures_after = character(0),
  dual_db    = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    dir    = file.path(.batch_ck_root, "_shared", "mimic")
  )
)

# ── 每指标 NHANES 分析流水线 ────────────────────────────────────────────────
pipeline_nhanes_batch <- list(
  name = "mcv_ui_dual_batch_nhanes",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "index",
    "imputation", "trim_index_extreme",
    "cutoff", "obj", "baseline_nhanes", "boxplot",
    "univariate_nhanes", "multicollinearity_nhanes_screen",
    "multivariate_nhanes", "multivariate_covariate_resolve", "multicollinearity_nhanes_final",
    "dual_db_covariate_harmonize",
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
    "imputation",
    "baseline_nhanes", "univariate_nhanes",
    "multicollinearity_nhanes_screen", "multivariate_nhanes",
    "multivariate_covariate_resolve", "multicollinearity_nhanes_final",
    "dual_db_covariate_harmonize",
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
    "cutoff", "boxplot", "rcs_nhanes", "subgroup_nhanes_weighted",
    "mediation_nhanes_weighted"
  ),
  dual_db    = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

# ── 每指标 MIMIC 分析流水线 ─────────────────────────────────────────────────
pipeline_regular_batch <- list(
  name = "mcv_ui_dual_batch_mimic",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "index",
    "imputation", "trim_index_extreme",
    "baseline_binary", "simple_ROC", "boxplot",
    "univariate_incidence_binary", "multicollinearity_screen",
    "multivariate_incidence_binary", "multivariate_covariate_resolve", "multicollinearity_final",
    "dual_db_covariate_harmonize",
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "dual_db_logistic_scheme_harmonize", "dual_db_logistic_main_table_realign",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
    "subgroup_incidence", "mediation_incidence"
  ),
  logistic_gate = list(enable = TRUE),
  render_tables_after = c(
    "imputation",
    "baseline_binary", "simple_ROC", "boxplot",
    "univariate_incidence_binary", "multicollinearity_screen",
    "multivariate_incidence_binary", "multivariate_covariate_resolve", "multicollinearity_final",
    "dual_db_covariate_harmonize",
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "dual_db_logistic_scheme_harmonize", "dual_db_logistic_main_table_realign",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
    "subgroup_incidence", "mediation_incidence"
  ),
  render_figures_after = c(
    "simple_ROC", "boxplot", "rcs_incidence", "subgroup_incidence"
  ),
  dual_db    = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline <- pipeline_nhanes_batch
