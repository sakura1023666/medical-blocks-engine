###############################################################################
#  config_survival_dual_batch.R — 复合指标 × 消化道出血 双普通库（eICU + MIMIC）预后批量
#
#  决策树: Decisiontree_commen/06decision_tree_survival_dual_batch.md
#  运行:   run/survival/run_survival_dual_batch.R --config "<本文件路径>"
#
#  本地冒烟（数据在 111/eicu、111/mimic）:
#    将 .batch_project_root 改为 normalizePath("111") 且 .batch_data_root <- .batch_project_root
###############################################################################

.batch_project_root <- "G:/02block_result/06_Gastrointestinal_Bleeding/prognosis_38902748"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")
.batch_data_root    <- file.path(.batch_project_root, "Data")

config <- list(

  data = list(
    rawdata_path     = file.path(.batch_data_root, "eicu/D04_rt_CleanData.RData"),
    rawdata_obj      = "rt",
    outcome_path     = NULL,
    outcome_column   = "fustatus",
    id_column        = "subject_id",
    strip_id_columns_after_imputation = c("ID", "subject_id", "SEQN")
  ),

  project = list(
    name                = "GIB_dual_survival_batch",
    disease_code        = "06",
    disease             = "Gastrointestinal_Bleeding",
    literature_pmid     = "38902748",
    database            = "eICU",
    database_type       = "regular",
    study_type          = "prognosis",
    classification_mode = "binary",
    analysis_group      = "Non-survivor",
    reference_group     = "Survivor",
    output_dir          = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root  = TRUE,
    root                = NULL
  ),

  survival = list(
    time_var      = "futime",
    event_var     = "fustatus",
    index_var     = NULL,
    time_unit     = "days",
    time_divisor  = 1
  ),

  logistic = list(
    index_var = NULL
  ),

  index = list(
    enable = TRUE,
    only   = NULL,
    skip   = NULL,
    digits = 4L
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
    database_type = "eICU"
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
      rawdata_path        = file.path(.batch_data_root, "eicu/D04_rt_CleanData.RData"),
      rawdata_obj         = "rt",
      id_column           = "subject_id",
      column_mapping_type = "eICU"
    ),
    secondary = list(
      name                = "MIMIC",
      db_type             = "regular",
      rawdata_path        = file.path(.batch_data_root, "mimic/D04_rt_CleanData.RData"),
      rawdata_obj         = "rt",
      id_column           = "subject_id",
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
      stop_on_empty_common_clinical = TRUE,
      sync_after_vif_final       = TRUE,
      covariate_source           = "vif_final",
      sync_logistic_branch       = FALSE,
      sync_cox_branch            = TRUE,
      subgroup_var_aliases = list(
        Gender  = c("Gender", "Sex"),
        Smoking = c("Smoking", "Smoke"),
        Smoke   = c("Smoking", "Smoke")
      )
    )
  ),

  feishu = list(
    enable             = TRUE,
    app_id             = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret         = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token          = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id           = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    literature_default = "eICU + MIMIC 预后双普通库（06 消化道出血, PMID 38902748, Xu 2024 CMI）",
    project_id         = "06_GIB_prognosis_38902748",
    owner_default      = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    disease_label  = "06_GIB",
    protocol_label = "06_GIB_prognosis_38902748",
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", "")
  ),

  survival_batch = list(
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
      "ID", "SEQN", "subject_id", "Hemoglobin", "futime", "fustatus",
      "new_Weight",
      "WTINT2YR", "WTMEC2YR", "WTMEC4YR",
      "WTSAF2YR", "WTSAF4YR", "SDMVPSU", "SDMVSTRA", "Source_File"
    ),
    extra_index_exclude_vars = c("Hemoglobin"),
    base_subgroup_vars = c("Age", "Gender", "Race", "Hypertension", "T2DM",
                           "COPD", "Heart_Failure", "CKD", "Pneumonia"),

    sensitivity_suite = list(
      enable       = TRUE,
      age_cutoff   = 65L,
      min_n_per_db = 50L,
      scenarios = list(
        list(label = "SA_no_hypertension", expr = 'is.na(Hypertension) | Hypertension != "Yes"'),
        list(label = "SA_no_diabetes",     expr = 'is.na(T2DM) | T2DM != "Yes"'),
        list(label = "SA_age_ge_{age_cutoff}", expr = "Age >= {age_cutoff}"),
        list(label = "SA_age_lt_{age_cutoff}", expr = "Age < {age_cutoff}")
      )
    ),

    subgroup_fallback = list(
      enable             = TRUE,
      try_all            = TRUE,
      min_n_per_subgroup = 30L,
      sep                = "|",
      age_cutoff         = 65L,
      age_mid_lower      = 45L,
      obesity_standard   = "chinese",
      subgroups = list(
        list(label = "Age_{age_cutoff}",                 expr = "Age >= {age_cutoff}"),
        list(label = "Age_{age_mid_lower}_{age_cutoff}", expr = "Age >= {age_mid_lower} & Age < {age_cutoff}"),
        list(label = "Hypertension",                     expr = 'Hypertension == "Yes"'),
        list(label = "Diabetes",                         expr = 'Diabetes == "Yes"'),
        list(label = "Obesity_BMI{obesity_cut}",         expr = "BMI >= {obesity_cut}"),
        list(label = "Non_smoker",                       expr = 'Smoke == "never"'),
        list(label = "Smoker",                           expr = 'Smoke %in% c("current", "former")')
      )
    )
  ),

  km = list(
    xlab          = "Follow-up time (days)",
    ylab          = "Survival probability (%)",
    xlim          = NULL,
    auto_xlim     = TRUE,
    auto_break_time = TRUE,
    break_time_by = NULL,
    summary_time  = 28
  ),

  baseline_binary = list(
    sig_cutoff            = 0.05,
    strata                = NULL,
    include_vars          = NULL,
    exclude_vars          = c("futime", "fustatus", "subject_id", "Micu_Code", "Language"),
    pause_enable          = FALSE,
    pause_on_table1_fail  = FALSE,
    pause_on_min_sig_vars = FALSE,
    pause_min_sig_vars    = 3L
  ),

  univariate_prognosis = list(
    sig_cutoff           = 0.05,
    screening_cutoff     = 0.1,
    excluded_predictors  = c("Micu_Code", "futime", "fustatus"),
    required_predictors  = character(0),
    demo_keywords        = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital_Status", "marriage",
      "Income", "PIR", "poverty", "Smoking", "Smoke",
      "Insurance", "Language", "Alcohol"
    ),
    index_transform      = "none",
    pause_enable         = FALSE,
    pause_on_min_sig_vars = FALSE
  ),

  multivariate_prognosis = list(
    sig_cutoff           = 0.05,
    input_from           = "vif_screen_pass",
    write_model_factors  = TRUE,
    excluded_predictors  = c("Micu_Code", "futime", "fustatus"),
    required_predictors  = character(0),
    demo_keywords        = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital_Status", "marriage",
      "Income", "PIR", "poverty", "Smoking", "Smoke",
      "Insurance", "Language", "Alcohol"
    ),
    pause_enable         = FALSE,
    pause_on_min_sig_vars = FALSE
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
      table_title = "Multicollinearity Analysis (VIF, univariate p<0.1 screen)",
      csv_name    = "VIF_check_screen.csv"
    ),
    final = list(
      table_title = "Multicollinearity Analysis (VIF, multivariate p<0.05)",
      csv_name    = "VIF_check_final.csv"
    )
  ),

  cox_quartile = list(
    index_var                  = NULL,
    gate_enable                = TRUE,
    require_both_models_sig    = TRUE,
    stop_if_crude_highest_ns   = TRUE,
    extend_branch              = "extend_quartile",
    degrade_branch             = "degrade_tertile",
    p_threshold                = 0.05,
    model1_factors             = NULL,
    model2_factors             = NULL,
    covariate_search           = list(
      enable              = TRUE,
      max_model1_attempts = 1000L,
      max_model2_attempts = 1000L,
      on_search_fail      = "degrade"
    ),
    pause_enable               = FALSE,
    pause_on_fit_fail          = FALSE
  ),

  cox_tertile = list(
    index_var                  = NULL,
    gate_enable                = TRUE,
    require_both_models_sig    = TRUE,
    stop_if_crude_highest_ns   = TRUE,
    extend_branch              = "extend_tertile",
    degrade_branch             = "degrade_binary",
    p_threshold                = 0.05,
    model1_factors             = NULL,
    model2_factors             = NULL,
    covariate_search           = list(
      enable              = TRUE,
      max_model1_attempts = 1000L,
      max_model2_attempts = 1000L,
      on_search_fail      = "degrade"
    ),
    pause_enable               = FALSE,
    pause_on_fit_fail          = FALSE
  ),

  plot_cutoff = list(
    minprop        = 0.2,
    auto_fallback  = TRUE,
    figure_kind    = "main_figure",
    figure_number  = 3L,
    bump_counter   = TRUE,
    pause_enable   = FALSE,
    pause_on_no_output = FALSE
  ),

  roc_simple = list(
    enable = TRUE, write_cutoff_value = TRUE,
    figure_kind = "main_figure", figure_number = 6L, bump_counter = FALSE,
    figure_width = 8, figure_height = 7
  ),

  boxplot = list(
    group_var = NULL, response_vars = NULL,
    overall_method = "kruskal.test", pairwise_method = "wilcox.test",
    figure_kind = "main_figure", figure_number = 7L, bump_counter = FALSE,
    pause_enable = FALSE, pause_if_all_overall_ns = FALSE
  ),

  mediation_prognosis = list(
    exposure = NULL, mediators = NULL,
    bootstrap_iter = 100L,
    auto_covariate_search = TRUE,
    dual_library_lm_screen = TRUE,
    lm_screen_alpha = 0.05,
    lm_screen_require_nonneg_beta = TRUE,
    fallback_single_library_model2 = TRUE,
    mediation_path_alpha = 0.05,
    diagram_enable = TRUE,
    figure_number = 8L, bump_counter = TRUE,
    pause_enable = FALSE
  ),

  cox_binary = list(
    index_var                  = NULL,
    gate_enable                = TRUE,
    require_both_models_sig    = TRUE,
    stop_if_crude_highest_ns   = TRUE,
    extend_branch              = "extend_binary",
    degrade_branch             = character(0),
    p_threshold                = 0.05,
    group_levels               = c("low", "high"),
    model1_factors             = NULL,
    model2_factors             = NULL,
    covariate_search           = list(
      enable              = TRUE,
      max_model1_attempts = 1000L,
      max_model2_attempts = 1000L,
      on_search_fail      = "stop"
    ),
    cutoff                     = NULL,
    pause_enable               = FALSE,
    pause_on_fit_fail          = FALSE
  ),

  rcs_prognosis = list(
    index_var    = NULL,
    nk_range     = 3:5,
    pause_enable = FALSE
  ),

  km_strata = list(
    time_var      = "futime",
    event_var     = "fustatus",
    event_value   = 1,
    time_divisor  = 1,
    auto_xlim     = TRUE,
    auto_break_time = TRUE,
    id_column     = "subject_id",
    figure_number = 4L,
    figure_caption_template = "Kaplan-Meier curves of {index} {method} and mortality in {disease}",
    single_filename_template = NULL,
    single_use_main_figure = FALSE,
    strata_vars   = NULL,
    strata_vars_by_branch = list(
      extend_quartile = NULL,
      extend_tertile  = NULL
    ),
    strata_defs   = list(),
    export_combined = FALSE,
    font_family = "Times New Roman",
    pause_enable = FALSE,
    pause_on_no_figures = FALSE
  ),

  segmented_cox_quartile = list(pause_enable = FALSE),
  segmented_cox_tertile  = list(pause_enable = FALSE),

  km_binary = list(
    time_divisor  = 1,
    auto_xlim     = TRUE,
    auto_break_time = TRUE,
    figure_number = 4L,
    figure_caption_template = "Kaplan-Meier curves of {index} {method} and mortality in {disease}",
    pause_enable  = FALSE,
    pause_on_no_output = FALSE
  ),

  segmented_cox_binary = list(
    random_covariate_search = list(enable = FALSE),
    pause_enable = FALSE
  ),

  subgroup = list(
    min_n    = 20,
    age_cutoff = 65,
    var_source = "table1_categorical",
    required_subgroup_vars = NULL,
    forbid_subgroup_vars = character(0),
    forest_xlim = c(0, 4),
    pause_enable = FALSE
  ),

  subgroup_prognosis = list(
    index_var    = NULL,
    pause_enable = FALSE
  ),

  feature_selection = list(enable = FALSE)
)

# ── 共享层（每库 1 次：算指标，不插补）────────────────────────────────────────
pipeline_shared_regular <- list(
  name   = "survival_dual_batch_shared",
  blocks = c("data_clean", "column_mapping", "dual_db_column_harmonize", "index"),
  logistic_gate = list(enable = FALSE),
  render_tables_after  = character(0),
  render_figures_after = character(0),
  dual_db    = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    dir    = file.path(.batch_ck_root, "_shared", "eICU")
  )
)

# ── 每指标分析流水线（eICU + MIMIC 均为 regular）────────────────────────────
pipeline_regular_batch <- list(
  name = "survival_dual_batch_regular",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "index",
    "imputation", "trim_index_extreme",
    "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final",
    "dual_db_covariate_harmonize",
    "cox_quartile", "cox_tertile", "cox_binary",
    "rcs_prognosis", "plot_cutoff", "km_strata",
    "segmented_cox_quartile", "segmented_cox_tertile",
    "km_binary", "segmented_cox_binary",
    "subgroup_prognosis"
  ),
  cox_gate = list(enable = TRUE),
  render_tables_after = c(
    "imputation", "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final",
    "dual_db_covariate_harmonize",
    "cox_quartile", "cox_tertile", "cox_binary",
    "segmented_cox_quartile", "subgroup_prognosis"
  ),
  render_figures_after = c(
    "rcs_prognosis", "plot_cutoff", "km_strata", "km_binary", "subgroup_prognosis"
  ),
  dual_db    = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline <- pipeline_regular_batch
