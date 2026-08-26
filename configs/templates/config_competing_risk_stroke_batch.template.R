###############################################################################
#  缺血性脑卒中 × 竞争风险模型（HbA1c 糖尿病 vs 死亡/出院，28天窗口）
#  方法学移植自 Lai et al. 2025 Cardiovasc Diabetol (PMID 40119388)
#
#  共享层:
#    data_clean → column_mapping → dual_db_column_harmonize → index → trajectory_calc_28d_index
#
#  指标层:
#    imputation → competing_index_exposure → analysis_exclusion → competing_trajectory_cluster → …
#    Table3 暴露指标不显著 → BASELINE_INDEX_NS_STOP（记失败）
#
#  运行:
#    Rscript run/competing_risk/run_competing_risk_chf_batch.R \
#      --config ".../config_competing_risk_stroke_batch.R" --shared-only
#    Rscript run/competing_risk/run_competing_risk_chf_batch.R \
#      --config "..." --only-unit NLR --workers 1 --no-skip
###############################################################################

.block_repo_root <- {
  env <- Sys.getenv("BLOCK_REPO_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env else "/mnt/e/01block/01Block-new-Final"
}
source(file.path(.block_repo_root, "configs/indices/composite_index_vars.R"))
source(file.path(.block_repo_root, "Blocks/00_index/01block_index.R"))

.block_result_root <- {
  env <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}

.batch_project_root <- file.path(.block_result_root, "11_ischemic stroke/Competing_risk_model_40119388")
.batch_data_root    <- file.path(.batch_project_root, "data")
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

.baseline_rdata <- file.path(.batch_data_root, "D01_baseline_MIMIC_ICU_frist_0626 (1).RData")
.dabiao_csv     <- file.path(.batch_data_root, "dabiao.csv")
.prognosis_csv  <- file.path(.batch_data_root, "mimic\u9884\u540e\u6570\u636e-all.csv")
.lab_csv        <- file.path(.batch_data_root, "mimic-\u5b9e\u9a8c\u5ba4\u6307\u6807-all-1~30\u5929.csv")
.index_data_dir <- file.path(.batch_data_root, "mimic")

# 疾病相关变量：结局定义/诊断泄漏，不进入任何分析表与协变量筛选
.disease_exclusion_vars <- c("T1DM", "T2DM", "Diabetes", "HbA1c")
.disease_related_index_units <- pipeline_indices_using_vars(
  .disease_exclusion_vars,
  .composite_index_vars
)
# 过滤后的复合指标；冒烟可临时改为 c("NLR")
.test_units <- setdiff(.composite_index_vars, .disease_related_index_units)

config <- list(
  project = list(
    name = "Competing_Risk_Stroke_Diabetes_MIMIC",
    disease = "ischemic_stroke_diabetes_competing_risk",
    disease_code = "11",
    study_type = "prognosis",
    literature_pmid = "40119388",
    database = "MIMIC",
    root = .block_repo_root,
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),

  data = list(
    rawdata_path   = .baseline_rdata,
    rawdata_obj    = "baseline",
    id_column      = "ID",
    outcome_column = "competing_primary_event",
    strip_id_columns_after_imputation = character(0)
  ),

  data_clean = list(
    missing_threshold = 0.5,
    cohort_id_path = .dabiao_csv,
    cohort_id_column = "subject_id",
    supplement_merge_path = .prognosis_csv,
    supplement_merge_id_column = "subject_id",
    supplement_merge_columns = c("hosp_day", "is_hosp_dead"),
    derive_competing_diabetes_28d = TRUE,
    min_n_after_cohort = 200L
  ),

  column_mapping = list(
    enable = TRUE,
    database_type = "MIMIC"
  ),

  dual_db = list(
    enable = FALSE
  ),

  index = list(
    enable = TRUE,
    only = .test_units
  ),

  imputation = list(
    missing_col_threshold = 0.5,
    method = "cart", m = 5L, max_iter = 5L, seed = 1234L,
    complete_action = 1L,
    rubin_pool = TRUE,
    export_missing_fig = TRUE,
    export_table_s1 = TRUE,
    force_keep_columns = .test_units,
    exclude_from_mice_cols = c("competing_time_28d", "competing_status_28d",
                               "hosp_day", "is_hosp_dead"),
    table_s1_exclude_vars = c("competing_time_28d", "competing_status_28d",
                              "hosp_day", "is_hosp_dead")
  ),

  incidence = list(index_var = "NLR"),
  survival = list(
    time_var = "competing_time_28d",
    event_var = "competing_primary_event",
    index_var = "NLR"
  ),
  incidence_batch = list(trim_quantile = 0.01),

  univariate_prognosis = list(
    sig_cutoff = 0.05,
    screening_cutoff = 0.10,
    pause_enable = FALSE,
    fail_on_index_ns = FALSE,
    excluded_predictors = c(
      .composite_index_vars,
      "competing_time_28d", "competing_status_28d", "competing_primary_event",
      "hosp_day", "is_hosp_dead", "in-hospital mortality", "ID", "subject_id"
    )
  ),

  feature_selection = list(
    restrict_to_train = FALSE,
    target_n_features_min = 1L,
    target_n_features_max = 8L
  ),
  feature_selection_lasso = list(
    candidate_source = "univariate",
    lasso_use_cox = TRUE,
    lasso_cv_times = 100L,
    target_n_features_min = 1L,
    target_n_features_max = 8L,
    pause_enable = FALSE
  ),
  feature_selection_random_forest = list(
    candidate_source = "lasso",
    target_n_features_min = 1L,
    target_n_features_max = 8L,
    pause_enable = FALSE
  ),

  analysis_exclusion = list(
    disease_vars = .disease_exclusion_vars,
    component_scope = "current_transitive",
    exclude_other_composite_indices = TRUE,
    exclude_exposure_if_uses_disease_var = TRUE,
    composite_index_vars = .composite_index_vars
  ),

  competing_risk = list(
    hba1c_lab_csv_path = .lab_csv,
    hba1c_lab_id_column = "subject_id",
    hba1c_threshold = 6.5,
    followup_days = 28L,
    time_var = "competing_time_28d",
    event_type_col = "competing_status_28d",
    primary_cause = 1L,
    death_cause = 2L,
    cif_cause = 2L,
    cif_horizon = 28,
    index_data_dir = .index_data_dir,
    index_visit_days = 1:28,
    # Table3 暴露不显著早停；冒烟先关以便出全套 Figure，正式跑改 TRUE
    early_stop_if_index_ns = TRUE,
    table3_sig_cutoff = 0.05,
    model_horizons = c(7L, 14L, 28L),
    # 轨迹：LMM+mclust 自动 K；类占比过小不回退，记失败
    trajectory_min_class_prop = 0.05,
    trajectory_allow_tercile_fallback = FALSE,
    demographic_vars = c("Age", "Gender", "Race", "BMI"),
    baseline_vars = c("Age", "Gender", "Race", "BMI", "Hypertension", "CHD",
                      "Smoking", "Drinking"),
    trim_quantile = 0.01,
    discharge_as_censor = TRUE,
    trajectory_censor_at_event = TRUE,
    # 默认关闭 Q4 导向搜索；需要固定协变量时再设 force_model2/force_model3（仅该课题）
    model3_sig_search = FALSE,
    sensitivity_crrt = TRUE
  ),

  trajectory_calc_28d_index = list(
    lab_sources = list(path = .lab_csv),
    lab_id_column = "subject_id",
    db_type = "mimic",
    output_dir = .index_data_dir,
    index_vars = .test_units,
    days = 1:28,
    min_non_na_days = 2L,
    restrict_to_baseline_ids = TRUE
  ),

  study_batch = list(
    output_base = .batch_project_root,
    units = .test_units,
    unit_mode = "index",
    parallel_workers = 1L,
    skip_existing = TRUE,
    rename_on_finish = TRUE,
    worker_script = "run/study/run_study_batch_worker.R",
    shared_ck_alias = "trajectory_calc_28d_index",
    trim_quantile = 0.01
  ),

  feishu = list(
    enable = FALSE
  )
)

pipeline_shared <- list(
  name = "competing_stroke_shared",
  blocks = c(
    "data_clean",
    "column_mapping",
    "dual_db_column_harmonize",
    "index",
    "trajectory_calc_28d_index"
  ),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "_shared", "main"))
)

pipeline_unit <- list(
  name = "competing_stroke_unit",
  blocks = c(
    "imputation",
    "competing_index_exposure",
    "analysis_exclusion",
    # 预后竞争风险：不修剪指标极端值（不挂 trim_index_extreme）
    "competing_trajectory_cluster",
    "competing_flowchart",
    "competing_baseline_quartile",
    "competing_lmm_trajectory",
    "competing_baseline_trajectory",
    "univariate_prognosis",
    "feature_selection_lasso",
    "feature_selection_random_forest",
    "competing_finegray",
    "competing_mixed_cox",
    "competing_models_123",
    "competing_models_123_death",
    "competing_stratified",
    "competing_rcs",
    "competing_cif_plot",
    "competing_cox_sensitivity",
    "competing_ph_calibration",
    "competing_supp_tables",
    "competing_pub_export"
  ),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
