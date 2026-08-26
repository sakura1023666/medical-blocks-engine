###############################################################################
#  config_environment_dkd_batch.R — DKD × 环境 VOC（NHANES 批量 + 飞书）
#
#  source 后得到:
#    config, pipeline_shared, pipeline_voc_batch, pipeline_tail, pipeline
#
#  入口: run/environment/run_environment_dkd_batch.R
#  决策树: Decisiontree/decision_tree_environment_voc_batch.md
###############################################################################

.batch_project_root <- "Output/DKD_Environment_VOC_NHANES"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

# 正式全量产出见 configs/config_environment_dkd_full_batch.R

config <- list(
  data = list(
    # prepare 块启用时由 Step00 动态写入；此处为 disable 时的回退路径
    rawdata_path     = "Data/nhanes/D03_EnvResultData.RData",
    rawdata_obj      = "EnvResult",
    outcome_path     = NULL,
    outcome_column   = "Group",
    id_column        = "SEQN",
    strip_id_columns_after_imputation = c("SEQN")
  ),

  # Step00：从 Data/nhanes/ 标准 D01/D02 文件合并 EnvResult + NHANES 权重
  environment_prepare = list(
    enable              = TRUE,
    nhanes_dir          = "Data/nhanes",
    clinical_file       = "D02_data.RData",
    clinical_obj        = "data",
    environment_file    = "D02_environment_data.RData",
    environment_obj     = "environment_data",
    gender_file         = "D01_data.RData",
    gender_obj          = "data",
    baseline_pattern    = "baseline.*NHANES.*\\.RData$",
    include_tne2_in_voc = TRUE,
    save_merged         = TRUE,
    merged_file         = "D03_EnvResultData.RData",
    merged_obj          = "EnvResult",
    voc_columns_file    = "voc_columns.RData",
    # 可选：按 baseline 名单过滤分析队列（SEQN 内连接）
    cohort_filter_file  = NULL,
    cohort_filter_obj   = "data_imp",
    cohort_id_col       = "SEQN",
    cohort_exclude_seqn = c(81715L, 82257L),
    cohort_target_n     = NULL,
    # 可选：环境暴露专用权重（如 WTSA2YR）→ 写入 merged_weight_col
    env_weight_file     = NULL,
    env_weight_obj      = "df",
    env_weight_id_col   = "SEQN",
    env_weight_col      = "WTSA2YR",
    env_weight_fallback_wtmec = TRUE,
    merged_weight_col   = "new_Weight",
    kidney_disease_voc_workflow = TRUE,
    restore_all_voc_to_ugl      = TRUE,
    adjust_voc_urinary_creatinine = NULL
  ),

  project = list(
    name                         = "DKD_Environment_VOC_Batch",
    disease_code                 = "05",
    disease                      = "DKD",
    disease_cn                   = "糖尿病肾病",
    literature_pmid              = "37419158",
    database                     = "NHANES",
    database_type                = "NHANES",
    study_type                   = "environment",
    classification_mode          = "binary",
    analysis_group               = "DKD",
    reference_group              = "Never DKD",
    output_dir                   = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix           = "step",
    mirror_pub_outputs_to_root   = TRUE,
    root                         = NULL
  ),

  incidence = list(
    outcome_var        = "Group",
    index_var          = NULL,
    # NULL → 运行时按 environment$voc_col_pattern 自动识别 URX* 列
    index_exclude_vars = NULL
  ),

  # VOC 列识别（共享层协变量筛选排除用）
  environment = list(
    voc_col_pattern     = "^URX",
    voc_columns         = NULL,
    voc_exclude_fixed   = character(0),
    display_label_map   = c(AMC = "AMCC", URXAMC = "AMCC"),
    exposure_code_file  = file.path("VOC 最终", "RawData", "Envrioment_code.RData"),
    exposure_code_obj   = "Envrioment_code"
  ),

  logistic = list(
    index_var = NULL
  ),

  prediction = list(
    index_vars                          = NULL,
    keep_index_vars_in_regression_table = FALSE
  ),

  nhanes = list(
    # obj 块按 Source_File + WTMEC2YR 计算 new_Weight，再构建 svydesign（与发病 dual 一致）
    survey_weight    = "new_Weight",
    survey_cluster   = "SDMVPSU",
    survey_strata    = "SDMVSTRA",
    auto_new_weight  = TRUE,
    # 共享层无单一 VOC 暴露时，用首个 VOC 决定 WTMEC vs WTSAF；full batch 会按 voc_columns 覆盖
    cutoff_index_var = NULL,
    exclude_cols     = c(
      "ID", "SEQN", "new_Weight",
      "WTINT2YR", "WTMEC2YR", "WTMEC4YR",
      "WTSAF2YR", "WTSAF4YR", "WTSA2YR",
      "SDMVPSU", "SDMVSTRA", "Source_File", "SDDSRVYR",
      "DN"
    )
  ),

  plot = list(font_family = "Times New Roman"),

  data_clean = list(
    missing_threshold = 0.4,
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
    export_table_s1       = TRUE,
    table_s1_exclude_vars = c("DN")
  ),

  baseline_nhanes = list(
    sig_cutoff                   = 0.05,
    pause_enable                 = FALSE,
    pause_on_weighted_table_fail = FALSE,
    pause_on_min_sig_vars        = FALSE,
    pause_min_sig_vars           = 3L
  ),

  univariate_nhanes = list(
    sig_cutoff            = 0.05,
    screening_cutoff      = 0.1,
    pause_enable          = FALSE,
    pause_on_min_sig_vars = FALSE,
    pause_min_sig_vars    = 3L
  ),

  multivariate_nhanes = list(
    sig_cutoff              = 0.05,
    input_from              = "vif_screen_pass",
    demo_keywords           = c("Age", "Gender", "Race"),
    model1_candidate_names  = c("Age", "Race", "PIR", "Education"),
    pause_enable            = FALSE,
    pause_on_min_sig_vars   = FALSE,
    pause_min_sig_vars      = 3L
  ),

  multicollinearity = list(
    vif_threshold_strict    = 4,
    vif_threshold_loose     = 10,
    vif_threshold_hard_drop = 50,
    min_vars_threshold      = 0,
    exclude_vars            = c("ID", "SEQN"),
    vif_design_extra_predictors = character(0),
    vif_append_extra_to_model2_outputs = FALSE,
    export_full_vif_table   = TRUE,
    anthropometric_vif_resolution = list(
      enable = TRUE,
      vars = c("BMI", "Weight", "Height", "Waist_circumstance"),
      protect_vars = character(0),
      prefer_drop_one_order = c("Weight", "Height", "Waist_circumstance"),
      apply_in_screen_only = FALSE
    ),
    screen = list(
      table_title = "Weighted Multicollinearity Analysis (VIF, univariate p<0.1 screen, NHANES)",
      csv_name    = "VIF_check_screen_weighted.csv"
    ),
    final = list(
      table_title = "Weighted Multicollinearity Analysis (VIF, multivariate p<0.05, NHANES)",
      csv_name    = "VIF_check_final_weighted.csv"
    )
  ),

  environment_voc_log_transform = list(
    enable         = TRUE,
    apply_log      = TRUE,
    force_all_vocs = TRUE
  ),

  environment_process = list(
    id_column                     = "SEQN",
    missing_percentage_cutoff     = 0.2,
    below_limit_percentage_cutoff = 0.8,
    seed                          = 123L,
    mice_m                        = 5L,
    mice_method                   = "pmm",
    export_stats                  = TRUE,
    apply_log_transform           = FALSE,
    legacy_stats_file             = file.path("Data", "nhanes", "stats.RData"),
    legacy_stats_obj              = "stats"
  ),
  process_environment_data = list(),

  environment_voc_clinical_gate = list(
    enable                           = TRUE,
    voc_gate_mode                    = "univariate_vif",
    voc_univariate_source            = "tb1",
    voc_univariate_p_cutoff          = 0.05,
    require_pass_for_lasso           = TRUE,
    require_pass_for_lasso           = TRUE,
    voc_vif_enable                   = TRUE,
    voc_vif_threshold                = 4,
    voc_vif_min_keep                 = 2L,
    voc_cor_enable                   = TRUE,
    voc_cor_threshold                = 0.80,
    voc_cor_method                   = "pearson",
    voc_cor_mode                     = "iterative",
    voc_cor_min_keep                 = 2L,
    require_table1                   = FALSE,
    require_univariate               = TRUE,
    min_pass_vocs                    = 2L,
    table_filename                   = "Table_Environment_VOC_Clinical_Gate.csv",
    summary_table_filename           = "Table_Environment_VOC_Screen_Summary.csv",
    cor_pairs_table_filename         = "Table_Environment_VOC_Cor_Removed_Pairs.csv"
  ),

  environment_voc_recovery = list(
    min_glm_vocs = 3L
  ),

  environment_subgroup_search = list(
    enable           = TRUE,
    min_subgroup_n   = 80L,
    use_parallel     = FALSE,
    max_workers      = NULL,
    table_filename   = "Table_Environment_Subgroup_Search.csv",
    custom_filters   = list(
      list(id = "age_ge_18", label = "Age >= 18", expr = "Age >= 18"),
      list(id = "age_ge_45", label = "Age >= 45", expr = "Age >= 45"),
      list(id = "age_lt_45", label = "Age < 45", expr = "Age < 45")
    )
  ),

  environment_voc_extreme_trim = list(
    enable              = TRUE,
    min_glm_vocs        = NULL,
    drop_frac_per_wave  = 0.005,
    drop_per_wave       = NULL,
    max_waves           = 20L,
    min_sample_n        = 100L,
    log_filename        = "Table_Environment_Extreme_Trim_Log.csv"
  ),

  remove_outliers = list(
    cols       = NULL,
    data_slot  = "imputed",
    low_prob   = 0.10,
    high_prob  = 0.90,
    iqr_factor = 1.5
  ),

  environment_lod = list(
    enable              = TRUE,
    lookup_csv          = "D02_OfficialLOD_Lookup_RespiratoryCancer(1).csv",
    per_cycle_csv       = "D02_OfficialLOD_PerCycle_RespiratoryCancer(1).csv",
    cycle_col           = "Source_File",
    missing_cutoff      = 0.2,
    under_lod_cutoff    = 0.8,
    # 可选：样本×列迭代筛查（见 environment_voc_iterative_sample_column_filter）
    sample_column_filter_enable = FALSE,
    drop_analytes_by_stats      = TRUE,
    sample_miss_frac_initial    = 0.8,
    sample_miss_frac_step       = 0.05,
    sample_miss_frac_min        = 0.5,
    column_missing_cutoff       = 0.4,
    min_retained_vocs           = 10L
  ),

  environment_characteristics = list(
    stats_source        = "ctx",
    stats_id_col        = "SEQN",
    final_vocs_col      = "Process",
    final_vocs_kept_val = c("log(ln)", "already_log(ln)", "floor_at_lod", "raw(no_log)"),
    verify_against_data = TRUE,
    table_title         = "Table S1. Characteristics of Environmental Contaminants or Metabolites"
  ),

  voc_correlation = list(
    select_vocs  = NULL,
    method       = "pearson",
    sig_cutoff   = 0.05,
    fig_filename = "Figure_VOC_Correlation.pdf"
  ),

  lasso_environment = list(
    env_cols            = NULL,
    univariate_enable   = TRUE,
    require_clinical_gate = TRUE,
    univariate_p_cutoff = 0.05,
    univariate_or_min   = 1.0,
    univariate_or_max   = 10.0,
    exclude_vars        = c("URXHEM", "URXPHE"),
    min_select_vocs     = 5L,
    auto_lasso_params   = FALSE,
    lambda_multiplier   = 0.5,
    table_filename      = "Table S7. Association between Environmental Toxicants and DKD.xlsx",
    cv_times            = 1000L,
    cv_folds            = 10L,
    seed                = 123L,
    freq_cutoff_method  = "auto_floor100",
    freq_cutoff_frac    = NULL,
    freq_cutoff_n       = NULL,
    fig_heatmap_filename = "Figure 2A. Lasso heatmap.pdf",
    fig_barplot_filename = "Figure 2B. Lasso barplot.pdf",
    fig_combined_filename = "Figure 2. Selection of Environmental exposure variables for 1000 Lasso regression.pdf",
    fig_top_patterns    = 6L
  ),
  lasso_environment_voc = list(),

  glm_environment_quartile = list(
    match_lasso_vocs                 = TRUE,
    require_lasso_passed             = TRUE,
    use_final_covariates             = TRUE,
    covariate_search                 = TRUE,
    covariate_search_mode            = "fast",
    per_voc_covariates               = TRUE,
    shared_exposure_scheme           = TRUE,
    exposure_scheme                  = NULL,
    require_crude_then_m1_m2         = TRUE,
    covariate_sources                = c("vif_uni", "table1"),
    exposure_schemes_primary         = c("quartile"),
    exposure_schemes_fallback        = c("quintile", "tertile", "binary"),
    table1_clinical_prefilter_n      = 15L,
    table1_prefilter_p               = 0.20,
    clinical_forward_max             = 8L,
    demo_search_max_size             = 3L,
    demo_random_attempts             = 50L,
    full_screen_top_n                = 5L,
    clinical_search_table1           = TRUE,
    clinical_search_if_pool_gt       = 5L,
    clinical_search_max_subset       = 10L,
    require_quartile_any_significant = TRUE,
    require_trend_significant        = TRUE,
    enforce_min_after_screen         = FALSE,
    model1_factor_sets = list(
      c("Age", "Race", "PIR", "Education"),
      c("Age", "Gender", "Race", "PIR", "Education")
    ),
    model1_factors        = c("Age", "Race", "PIR", "Education"),
    model2_factors        = c(
      "Age", "Race", "PIR", "Education", "Smoking", "BMI",
      "Albumin_Urine", "Creatinine_refrigerated_serum",
      "Glucose", "HbA1c", "Uric_Acid"
    ),
    model2_factor_sets = list(
      c("Age", "Race", "PIR", "Education", "Smoking", "BMI",
        "Albumin_Urine", "Creatinine_refrigerated_serum", "Uric_Acid"),
      c("Age", "Race", "PIR", "Education", "BMI",
        "Albumin_Urine", "Creatinine_refrigerated_serum",
        "Glucose", "HbA1c", "Uric_Acid"),
      c("Age", "Gender", "Race", "PIR", "Education", "Smoking", "BMI",
        "NBPS", "NBPD", "Diabetes", "Hypertension")
    ),
    min_select_vocs       = 4L,
    screening_p_threshold = 0.05,
    random_search = list(
      enable = TRUE,
      max_attempts = 1000L,
      max_inner_attempts = 1000L,
      initial_sample_n = 1L,
      initial_clinical_n = 1L,
      max_clinical_attempts = 1000L,
      clinical_max_subset = 10L,
      p_threshold = 0.05
    ),
    table_filename        = "Table S8. Selection of Environmental exposure variables for GLM.xlsx",
    table_title           = "Table S8. Selection of Environmental exposure variables for GLM"
  ),

  wqs_environment = list(
    strict_glm_vocs   = TRUE,
    auto_select_vocs  = FALSE,
    min_select_vocs   = 1L,
    # 固定协变量（Model2）；NULL 则取 ctx$results$Model2Factors
    covariates        = NULL,
    auto_select = list(
      quick_b = 200L,
      bkmr_quick_iter = 500L,
      bkmr_quick_nchains = 2L,
      max_trials = 80L,
      max_subset_size = 12L
    ),
    q_values          = 4:6,
    validation_values = c(0.6, 0.7, 0.8),
    b                 = 1000L,
    b1_pos            = TRUE,
    family            = "binomial",
    seed              = 2025L,
    p_threshold       = 0.05,
    skip_if_vocs_lte  = 2L,
    min_select_vocs   = 2L,
    use_parallel      = TRUE,
    table_filename    = "Table S9. Associations of WQS regression index with DKD.xlsx",
    table_title       = "Table S9. Associations of WQS regression index with DKD"
  ),

  bkmr_fit = list(
    strict_glm_vocs = TRUE,
    min_select_vocs = 3L,
    auto_iter       = TRUE,
    min_iter_candidate = 100L,
    max_iter_candidate = 10000L,
    iter_candidate_step = 500L,
    iter_candidates = NULL,
    iter            = 1000L,
    family          = "binomial",
    seed            = 123L,
    seed_retries    = 3L,
    accept_relaxed  = TRUE,
    min_relaxed_score = 0,
    varsel          = TRUE,
    est_h           = TRUE
  ),

  bkmr_analysis = list(
    pip_threshold  = 0.5,
    fig_square_inches = 5,
    export_per_voc_figures = FALSE,
    table_pip_filename = "Table S10. PIP values in BKMR model in DKD.xlsx",
    table_pip_title    = "Table S10. PIP values in BKMR model in DKD"
  ),

  rcs_nhanes = list(
    index_var        = NULL,
    covariate_search = TRUE,
    require_all_models_significant = TRUE,
    p_threshold      = 0.05,
    model1_factor_sets = list(
      c("Age", "Race", "PIR", "Education"),
      c("Age", "Gender", "Race", "PIR", "Education")
    ),
    model1_factors   = c("Age", "Race", "PIR", "Education"),
    model2_factor_sets = list(
      c("Age", "Race", "PIR", "Education", "Smoking", "BMI", "Hypertension", "Diabetes"),
      c("Age", "Race", "PIR", "Education", "BMI", "Albumin_Urine", "Uric_Acid", "Hypertension"),
      c("Age", "Gender", "Race", "PIR", "Education", "Smoking", "BMI", "NBPS", "NBPD")
    ),
    model2_factors   = NULL,
    max_model1_vars  = 4L,
    knot_quantiles   = c(0.1, 0.5, 0.9),
    histper          = 25L,
    color_seed       = 123L
  ),

  qgcomp_environment = list(
    q              = 4L,
    seed           = 2023L,
    top_n          = 3L,
    covariates     = character(0),
    table_filename = "Table S19. Associations of Environmental Toxicants with DKD by using Quantile g-Computation.csv",
    table_title    = "Table S19. Associations of Environmental Toxicants with DKD by using Quantile g-Computation"
  ),

  environment_target = list(
    enable              = TRUE,
    data_dir            = "VOC 最终/Step12_Target",
    table_kegg_filename = "Table S12. Results of KEGG Enrichment Analysis.xlsx",
    table_gobp_filename = "Table S13. Results of GO-BP Enrichment Analysis.xlsx",
    table_gocc_filename = "Table S14. Results of GO-CC Enrichment Analysis.xlsx",
    table_gomf_filename = "Table S15. Results of GO-MF Enrichment Analysis.xlsx",
    fig_venn_filename   = "Figure 9A. Venn Plot.pdf",
    qvalue_cutoff       = 0.01
  ),

  mediation_ers_environment = list(
    ers_alpha      = 0.5,
    boot           = FALSE,
    sims           = 1000L,
    seed           = 123L,
    p_threshold    = 0.05,
    compute_fi_lab = FALSE,
    export_mediator_figures = FALSE,
    auto_covariate_search = FALSE,
    require_positive_indirect = TRUE,
    fig_filename_prefix = "Figure 9. Mediation plot for ",
    table_filename = "Table S11. Mediation effects in the associations of Environmental Toxicants with DKD.xlsx",
    table_title    = "Table S11. Mediation effects in the associations of Environmental Toxicants with DKD"
  ),

  subgroup_environment_or = list(
    allow_empty_strata = TRUE,
    stratify_col   = "Gender",
    strata_levels  = c("Male", "Female"),
    table_filename = "Table_S8_Subgroup_Gender_DKD.xlsx",
    table_title    = "Table S8. Subgroup analysis stratified by Gender"
  ),

  table1_summary = list(file_path = NULL, start_row = 3L),

  feishu = list(
    enable                = TRUE,
    app_id                = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret            = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token             = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id              = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    literature_default    = "DKD × 环境 VOC（NHANES, Ren 2024, PMID 37419158）",
    project_id            = "05_DKD_environment_37419158",
    owner_default         = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    disease_label         = "DKD_VOC",
    protocol_label        = "DKD_Environment_VOC_NHANES",
    table_success_id      = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id      = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", "")
  ),

  environment_batch = list(
    voc_vars          = NULL,
    parallel_workers  = NULL,
    skip_existing     = TRUE,
    output_base       = .batch_project_root,
    shared_ck_base    = file.path(.batch_ck_root, "_shared", "main"),
    project_root      = NULL,
    ram_per_worker_gb = 2.5,
    cpu_headroom      = 2L,
    ram_headroom_gb   = 4.0,
    max_workers       = NULL,
    strict_glm_vocs   = TRUE,
    skip_clinical_multivariate = TRUE,
    include_vocs_in_clinical_screen = TRUE,
    exclude_vocs_from_clinical_vif = FALSE,
    collect_results_summary = TRUE,
    covariate_fallback = list(
      enable = TRUE,
      model1 = c("Age", "Race", "PIR", "Education"),
      model2 = c("Age", "Race", "PIR", "Education",
                 "Smoking", "BMI", "NBPS", "NBPD", "Diabetes", "Hypertension")
    ),
    subgroup_strata = list(
      list(
        stratify_col   = "Gender",
        strata_levels  = c("Male", "Female"),
        table_filename = "Table_S8_Subgroup_Gender_DKD.xlsx",
        table_title    = "Table S8. Subgroup analysis stratified by Gender"
      ),
      list(
        stratify_col   = "Race",
        strata_levels  = c(
          "Mexican American", "Non-Hispanic Black",
          "Non-Hispanic White", "Other Hispanic", "Other Race"
        ),
        table_filename = "Table_S9_Subgroup_Race_DKD.xlsx",
        table_title    = "Table S9. Subgroup analysis stratified by Race"
      ),
      list(
        stratify_col   = "PIR",
        strata_levels  = c("> 3.5", "1.3-3.5", "\u2264 1.3"),
        table_filename = "Table_S10_Subgroup_PIR_DKD.xlsx",
        table_title    = "Table S10. Subgroup analysis stratified by PIR"
      ),
      list(
        stratify_col   = "Smoking",
        strata_levels  = NULL,
        table_filename = "Table_S11_Subgroup_Smoked_DKD.xlsx",
        table_title    = "Table S11. Subgroup analysis stratified by Smoking"
      )
    )
  )
)

# ── Step01–06 + Step11 共享层（跑 1 次）──────────────────────────────────────
pipeline_shared <- list(
  name   = "dkd_env_shared",
  blocks = c(
    "prepare_environment_dkd_data",
    "data_clean",
    "column_mapping",
    "environment_lod_screen",
    "imputation",
    "environment_voc_log_transform",
    "obj",
    "baseline_nhanes",
    "univariate_nhanes",
    "environment_voc_clinical_gate",
    "multicollinearity_nhanes_screen",
    "process_environment_data",
    "remove_outliers",
    "lasso_environment_voc",
    "glm_environment_quartile",
    "environment_subgroup_search",
    "environment_voc_extreme_trim",
    "wqs_environment",
    "bkmr_fit",
    "bkmr_analysis",
    "environment_characteristics",
    "voc_correlation"
  ),
    render_tables_after = c(
    "environment_lod_screen", "imputation", "baseline_nhanes",
    "univariate_nhanes", "environment_voc_clinical_gate",
    "multicollinearity_nhanes_screen",
    "environment_characteristics",
    "glm_environment_quartile", "wqs_environment", "bkmr_analysis"
  ),
  render_figures_after = c(
    "imputation", "voc_correlation", "lasso_environment_voc",
    "wqs_environment", "bkmr_analysis"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "_shared", "main"))
)

# ── Step07 每 VOC 并行 worker ────────────────────────────────────────────────
pipeline_voc_batch <- list(
  name   = "dkd_env_voc_rcs",
  blocks = c("rcs_nhanes"),
  render_figures_after = c("rcs_nhanes"),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

# ── Step08–10 尾段（主进程续跑）────────────────────────────────────────────
pipeline_tail <- list(
  name   = "dkd_env_tail",
  blocks = c(
    "qgcomp_environment",
    "mediation_ers_environment",
    "subgroup_environment_or",
    "environment_target_enrichment"
  ),
  render_tables_after = c(
    "qgcomp_environment", "mediation_ers_environment", "subgroup_environment_or",
    "environment_target_enrichment"
  ),
  render_figures_after = c("qgcomp_environment", "mediation_ers_environment", "environment_target_enrichment"),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "_shared", "main"))
)

# ── 全流程单跑（调试 / smoke test）──────────────────────────────────────────
pipeline <- list(
  name   = "dkd_environment_voc_nhanes_full",
  blocks = c(
    pipeline_shared$blocks,
    "rcs_nhanes",
    pipeline_tail$blocks
  ),
  render_tables_after = unique(c(
    pipeline_shared$render_tables_after,
    pipeline_tail$render_tables_after
  )),
  render_figures_after = unique(c(
    pipeline_shared$render_figures_after,
    "rcs_nhanes",
    pipeline_tail$render_figures_after
  )),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "full_run"))
)
