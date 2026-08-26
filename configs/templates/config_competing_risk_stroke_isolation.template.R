###############################################################################
#  config_competing_risk_stroke_batch.template.R — 竞争风险（MIMIC · by_unit）
#  （5006 程序员隔离模式：产出写在本研究文件夹）
#
#  复制 studies/_template_competing/ 后改 <TO_CONFIRM*>；勿改 pipeline_* blocks。
#  入口: run/competing_risk/run_competing_risk_chf_batch.R
#  决策树: docs/Decisiontree/decision_tree_competing_risk_stroke.md
#
#  默认主事件：AKI（KDIGO 简化）。糖尿病版把 derive_competing_aki_28d=FALSE
#  且 derive_competing_diabetes_28d=TRUE，并改 disease_exclusion_vars。
#
#  CLI:
#    run_study.bat <研究名> --shared-only
#    run_study.bat <研究名> --workers 4 --only-unit NLR
###############################################################################

.mb_root <- {
  env <- Sys.getenv("MEDICAL_BLOCKS_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env else normalizePath(getwd(), winslash = "/", mustWork = FALSE)
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
.lab_csv        <- file.path(.batch_data_root, "mimic/<TO_CONFIRM_LAB_CSV>")
.index_data_dir <- file.path(.batch_data_root, "mimic")

# AKI 终点：排除肌酐/尿素氮泄漏；糖尿病版改为 T1DM/T2DM/Diabetes/HbA1c
.disease_exclusion_vars <- c("Creatinine", "BUN", "UreaNitrogen")  # <TO_CONFIRM_DISEASE_VARS>
.disease_related_index_units <- pipeline_indices_using_vars(
  .disease_exclusion_vars,
  .composite_index_vars
)
.test_units <- setdiff(.composite_index_vars, .disease_related_index_units)
# 冒烟可改为 .test_units <- c("NLR")

message(sprintf(
  "[analysis_exclusion] 候选 %d → 剔除 %d → 单元 %d: %s",
  length(.composite_index_vars),
  length(.disease_related_index_units),
  length(.test_units),
  paste(.disease_related_index_units, collapse = ", ")
))

config <- list(
  project = list(
    name = "<TO_CONFIRM_PROJECT_NAME>",          # ❓ Competing_Risk_Stroke_AKI_MIMIC
    disease = "<TO_CONFIRM_DISEASE>",             # ❓ ischemic_stroke_aki_competing_risk
    disease_code = "<TO_CONFIRM_CODE>",           # ❓ 11
    study_type = "prognosis",
    literature_pmid = "<TO_CONFIRM_PMID>",        # ❓
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
    derive_competing_diabetes_28d = FALSE,
    derive_competing_aki_28d = TRUE,
    min_n_after_cohort = 200L
  ),

  column_mapping = list(enable = TRUE, database_type = "MIMIC"),
  dual_db = list(enable = FALSE),
  index = list(enable = TRUE, only = .test_units),

  imputation = list(
    missing_col_threshold = 0.5,
    method = "cart", m = 5L, max_iter = 5L, seed = 1234L,
    complete_action = 1L,
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
    aki_lab_csv_path = .lab_csv,
    aki_lab_id_column = "subject_id",
    aki_lab_prefix = "labcreatinine",
    aki_baseline_day = 1L,
    aki_delta_abs = 0.3,
    aki_ratio = 1.5,
    primary_event_label = "AKI",
    followup_days = 28L,
    time_var = "competing_time_28d",
    event_type_col = "competing_status_28d",
    primary_cause = 1L,
    death_cause = 2L,
    cif_cause = 2L,
    cif_horizon = 28,
    index_data_dir = .index_data_dir,
    index_visit_days = 1:28,
    early_stop_if_index_ns = TRUE,
    table3_sig_cutoff = 0.05,
    model_horizons = c(7L, 14L, 28L),
    trajectory_min_class_prop = 0.05,
    trajectory_allow_tercile_fallback = FALSE,
    demographic_vars = c("Age", "Gender", "Race", "BMI"),
    baseline_vars = c("Age", "Gender", "Race", "BMI", "Hypertension", "CHD",
                      "Smoking", "Drinking"),
    trim_quantile = 0.01,
    model3_sig_search = TRUE,
    model3_sig_horizon = 28L,
    model3_sig_cutoff = 0.05,
    model3_sig_max_trials = 300L,
    model3_sig_seed = 1234L
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
    parallel_workers = 4L,
    skip_existing = TRUE,
    rename_on_finish = TRUE,
    worker_script = "run/study/run_study_batch_worker.R",
    shared_ck_alias = "trajectory_calc_28d_index",
    trim_quantile = 0.01
  ),

  feishu = list(enable = FALSE)
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
