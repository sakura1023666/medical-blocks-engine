###############################################################################
#  COPD 复合指标轨迹预后（对齐 fcimb-16-1871653 方法；暴露=dual_safe）
#  决策树: Decisiontree/decision_tree_trajectory_prognosis_copd_jlcm.md
#  发现 MIMIC → 外验 eICU（固定参数 predictClass）+ PAMM（P5/P95 锁定）
###############################################################################

source("configs/indices/composite_index_vars.R")

.block_result_root <- {
  env <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  # Windows R：忽略 .env 里的 /mnt/g（dir.exists 常为 TRUE 但 normalizePath 读不到文件）
  is_win <- identical(.Platform$OS.type, "windows")
  env_ok <- nzchar(env) && dir.exists(env) &&
    !(is_win && grepl("^/mnt/", env))
  if (env_ok) env
  else if (is_win) "G:/02block_result"
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else if (dir.exists("G:/02block_result")) "G:/02block_result"
  else "G:/02block_result"
}
.batch_project_root <- file.path(.block_result_root, "55_COPD/Prognosis_Trajectory_v2_42558177")
.batch_data_root    <- file.path(.batch_project_root, "data")

.leak_admin_vars <- c(
  "hospitaldischargestatus", "hospitaldischargestatus_28d", "Mortality_28d",
  "discharge_status", "discharge_status_28d", "icu_los", "hospital_los",
  "los_icu", "los_hospital", "duration_icu", "duration_hospital",
  "admission_age_group", "readmission", "readmit",
  "death_within_hosp_28days", "death_within_icu_28days",
  "hosp_survival_day", "icu_survival_day", "is_dead", "is_hosp_dead", "is_icu_dead"
)

.vital_sign_vars <- c(
  "SBP", "DBP", "MAP", "HR", "RR", "SpO2", "Temperature", "Weight", "Height", "BMI",
  "NBPS", "NBPD", "NBPM", "ABPS", "ABPD", "ABPM"
)

# 年龄切点依据：ICU 老年常用 65（无病种特异文献强制时用默认 65）
config <- list(
  project = list(
    name = "Prognosis_Trajectory_v2_42558177",
    disease = "COPD",
    disease_code = "55",
    analysis_group = "Non-survivor",
    reference_group = "Survivor",
    classification_mode = "binary",
    study_type = "prognosis",
    database = "MIMIC+eICU",
    root = normalizePath(getwd(), winslash = "/", mustWork = FALSE),
    output_dir = .batch_project_root,
    mirror_pub_outputs_to_root = TRUE
  ),

  data = list(
    rawdata_path = file.path(.batch_data_root, "mimic/D02_COPD_MIMIC_surv28.RData"),
    rawdata_obj = "data_imp",
    id_column = "subject_id",
    outcome_column = "survival_28d"
  ),

  survival = list(
    time_var = "survival_time_28d",
    event_var = "survival_28d",
    index_var = "NLR"
  ),

  data_clean = list(missing_threshold = 0.3),
  column_mapping = list(enable = FALSE),

  analysis_exclusion = list(
    disease_vars = c("COPD"),
    component_scope = "current_transitive",
    allow_no_index = TRUE,
    exclude_other_composite_indices = FALSE,
    exclude_exposure_if_uses_disease_var = TRUE,
    protect_vars = character(0)
  ),

  imputation = list(
    missing_col_threshold = 0.3,
    method = "cart", m = 5L, max_iter = 5L, seed = 42558177L,
    complete_action = 1L,
    rubin_pool = TRUE, export_missing_fig = TRUE, export_table_s1 = TRUE,
    exclude_from_mice_cols = character(0),
    table_s1_exclude_vars = character(0)
  ),

  baseline_binary = list(
    sig_cutoff = 0.05, pause_enable = FALSE, early_stop_if_index_ns = FALSE,
    force_continuous_vars = .vital_sign_vars,
    median_iqr_vars = .vital_sign_vars,
    exclude_vars = .leak_admin_vars,
    always_include_vars = c("survival_time_28d", "survival_28d")
  ),

  univariate_prognosis = list(sig_cutoff = 0.1, pause_enable = FALSE, excluded_predictors = .leak_admin_vars),
  multivariate_prognosis = list(
    sig_cutoff = 0.05, pause_enable = FALSE, pause_on_min_sig_vars = FALSE, input_from = "tb1"
  ),
  multivariate_covariate_resolve = list(
    enable = TRUE, never_stop = TRUE,
    fallback_from = c("tb_screen", "tb1", "vif_screen_pass", "univar_features")
  ),
  multicollinearity = list(
    vif_threshold_strict = 4, vif_threshold_loose = 10, min_vars_threshold = 0,
    # 批跑：VIF final 空池回退 Age+Gender，勿 PAUSE 整指标
    pause_on_empty_final = FALSE,
    exclude_vars = c("subject_id", "survival_time_28d", "survival_28d", .leak_admin_vars),
    screen = list(csv_name = "VIF_check_screen.csv"),
    final = list(csv_name = "VIF_check_final.csv")
  ),

  # 发现/外验
  discovery_validate = list(
    enable = TRUE,
    discovery_db = "mimic",
    validation_db = "eicu"
  ),

  trajectory_jlcm = list(
    index_vars = NULL,
    class_range = 2:6,
    rawdata_path_template = file.path(.batch_data_root, "{db}/12_{Index}.RData"),
    output_dir_template = file.path(.batch_data_root, "{db}"),
    rawdata_obj = "index_df",
    id_column = "subject_id",
    non_na_col = "non_na_count",
    time_col_start = 2L, time_col_end = 29L, time_col_sep = "_",
    outlier_quantiles = c(0.01, 0.99),
    value_transform = "none",
    survival_time_var = "survival_time_28d",
    survival_event_var = "survival_28d",
    max_followup = 28,
    covariate_vars = character(0),
    covariate_vars_from_vif = TRUE,
    dual_db_harmonize_survival_covariates = FALSE,
    survival_covariate_max = 5L,
    survival_covariate_continuous_only = TRUE,
    spline_df = 2L,
    hazard = "Weibull", hazardtype = "Specific",
    gridsearch_rep = 50L, gridsearch_maxiter = 10L,
    adaptive_class_cap = TRUE,
    adaptive_class_cap_n_threshold = 1000L,
    adaptive_class_cap_ng_low = 4L, adaptive_class_cap_ng_high = 6L,
    # NULL=读发现集 Tables/Summary/optimal_ng_<Index>.txt；禁止静默用最大 ng
    prefer_final_ng = NULL, assign_class_ng = NULL,
    auto_select_class_ng = TRUE,
    min_class_proportion_pct = 5, min_entropy_for_selection = 0.3,
    stop_on_ng1_fail = TRUE, stop_on_ng2_fail = TRUE, stop_on_no_output = TRUE,
    pause_enable = FALSE
  ),

  trajectory_lcmm_external_validate = list(
    discovery_db = "mimic",
    # 课题默认读发现集 optimal；GPR 锁定 3（禁止 max-ng=6）
    prefer_ng = 3L,
    require_predictClass = TRUE
  ),

  trajectory_plot_jlcm = list(index_vars = NULL, use_optimal_class_ng = TRUE, cycle = 28L, pause_enable = FALSE),
  trajectory_km_class = list(index_vars = NULL),
  # 对齐 fcimb Fig3/4：landmark 2/5/7/12；副轴 mortality；prefer_ng 跟发现集 optimal
  trajectory_dynpred = list(
    index_vars = NULL, cycle = 28L,
    pred_scale = "mortality",
    # day2 在 ICU 日索引从 1 起 + ns(df=2) 下不可估；最早稳定 landmark=3（对齐 fcimb 4 面板）
    jlcm = list(prefer_ng = 3L, assessment_times = c(3, 5, 7, 12), ndraws = 200L)
  ),
  trajectory_dynpred_individual = list(index_vars = NULL, jlcm_ng = NULL),
  trajectory_piecewise_cox = list(index_vars = NULL, max_followup = 28L),
  trajectory_weibull_compare = list(index_vars = NULL, landmarks = 4:14, jlcm_ng = NULL),
  trajectory_subgroup_class = list(
    index_vars = NULL, age_var = "Age", age_cutoff = 65L,
    auto_scan_categorical = FALSE,
    subgroup_vars = c("Gender", "Race", "Ventilation")
  ),
  trajectory_baseline_by_class = list(index_vars = NULL, vars_from = "table1"),
  trajectory_chisq = list(
    index_vars = NULL, use_optimal_class_ng = TRUE,
    outcome_vars = c("survival_28d"), p_threshold = 1.0,
    # 批跑：无有效结果/全阴性不 PAUSE（外验 ID 修好后应有结果；全阴为正当阴性）
    pause_on_no_results = FALSE,
    pause_on_all_ns = FALSE
  ),

  trajectory_pamm = list(
    index_vars = NULL,
    discovery_db = "mimic",
    threshold_probs = c(0.05, 0.95),
    threshold_fallback_probs = c(0.10, 0.90),
    min_abnormal_person_days = 50L,
    max_followup = 28L,
    lock_thresholds_from_discovery = TRUE,
    validation_apply_locked = TRUE,
    export_figures = TRUE,
    plot_landmarks = c(2, 5, 12)
  ),

  trajectory_pub = list(
    enable = TRUE,
    fig1_consort = TRUE,
    combine_figures = TRUE,
    skip_class_swap = TRUE,
    shared_piecewise_cut = list(enable = TRUE, mode = "min_best", root_keep_db = "mimic"),
    export_formats = TRUE,
    fix_tables = TRUE
  ),

  feishu = list(
    enable = TRUE,
    disease_label = "55_COPD_Trajectory_JLCM_PAMM",
    protocol_label = "trajectory_prognosis_copd_jlcm",
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE
  ),

  attrition = list(
    outcome_breakdown = TRUE,
    steps = list(
      list(label = "COPD ICU extract", n_source = "raw"),
      list(label = "After survival merge", n_source = "cleaned"),
      list(label = "Included", n_source = "analytic")
    )
  )
)

config$imputation$exclude_from_mice_cols <- unique(c(
  as.character(config$imputation$exclude_from_mice_cols %||% character(0)),
  .composite_index_vars
))
config$imputation$table_s1_exclude_vars <- unique(c(
  as.character(config$imputation$table_s1_exclude_vars %||% character(0)),
  .composite_index_vars
))

config$dual_db <- list(
  # 保持引擎约定：primary=eicu, secondary=mimic；发现/外验由 discovery_validate + worker 控制
  primary = list(
    name = "eICU", db_type = "eicu",
    rawdata_path = file.path(.batch_data_root, "eicu/D02_COPD_EICU_surv28.RData"),
    rawdata_obj = "data_imp", id_column = "subject_id",
    lab_id_column = "subject_id",
    output_subdir = file.path(.batch_data_root, "eicu"),
    lab_sources = list(path = file.path(.batch_data_root, "eicu/COPD_lab_daily_wide_d1-30.csv"))
  ),
  secondary = list(
    name = "MIMIC", db_type = "mimic",
    rawdata_path = file.path(.batch_data_root, "mimic/D02_COPD_MIMIC_surv28.RData"),
    rawdata_obj = "data_imp", id_column = "subject_id",
    lab_id_column = "subject_id",
    output_subdir = file.path(.batch_data_root, "mimic"),
    lab_sources = list(
      files = list.files(file.path(.batch_data_root, "mimic/mimic-实验室指标-all-30天"),
                         pattern = "\\.csv$", full.names = TRUE)
    )
  )
)

config$trajectory_calc_28d_index <- list(
  index_vars = NULL, index_group = "dual_safe",
  days = 1:28, min_non_na_days = 2L, restrict_to_baseline_ids = TRUE
)

config$trajectory_batch <- list(
  output_base = .batch_project_root,
  shared_ck_base = file.path(.batch_project_root, "checkpoints", "_shared"),
  index_ck_base = file.path(.batch_project_root, "checkpoints", "by_index"),
  db_seq = c("mimic", "eicu"),  # 发现先于外验
  index_vars = NULL, index_group = "dual_safe",
  # 纵向宽表可算人数过少（如 PHR n=5）直接 INDEX_MIN_N，勿拖到 baseline PAUSE
  min_n_after_index = 50L,
  # 查重（方法=COPD ICU JLCM+PAMM 轨迹；结局=28天院内死亡）：未见同构发表 → exclude_published 空
  # 见 reports/pubmed_novelty_copd_jlcm_pamm_2026-11-19.md
  exclude_published = character(0),
  # 原则性失败：JLCM ng=1 不收敛 / 样本量门控 / 发现集 PAUSE — 不再入队重跑
  exclude_principle_fail = c("SII", "PLR", "GLR", "LactAlb", "PHR"),
  parallel_workers = "auto",
  worker_script = "run/trajectory_prognosis/run_trajectory_prognosis_copd_jlcm_batch_worker.R",
  discovery_first = TRUE
)

pipeline_shared <- list(
  name = "trajectory_prognosis_shared",
  blocks = c("data_clean", "column_mapping", "index", "analysis_exclusion", "trajectory_calc_28d_index"),
  checkpoint = list(enable = TRUE)
)

pipeline_unit_prefix <- list(
  name = "trajectory_prognosis_unit_prefix",
  blocks = c(
    "imputation", "analysis_exclusion", "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final"
  ),
  render_tables_after = c(
    "imputation", "analysis_exclusion", "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final"
  ),
  checkpoint = list(enable = TRUE)
)

# 发现集 suffix = 轨迹基线 + PAMM（末尾扩展，过 pipeline_extension_guard）
pipeline_unit_suffix_discovery <- list(
  name = "trajectory_prognosis_unit_suffix_discovery",
  blocks = c(
    "trajectory_jlcm", "trajectory_baseline_by_class", "trajectory_plot_jlcm",
    "trajectory_km_class", "trajectory_dynpred", "trajectory_dynpred_individual",
    "trajectory_piecewise_cox", "trajectory_weibull_compare",
    "trajectory_subgroup_class", "trajectory_chisq",
    "attrition_flowchart",
    "trajectory_pamm"
  ),
  checkpoint = list(enable = TRUE)
)

# 外验 suffix：用 external_validate 替换 jlcm（worker 专用；不经 guard 基线比对）
pipeline_unit_suffix_validation <- list(
  name = "trajectory_prognosis_unit_suffix_validation",
  blocks = c(
    "trajectory_lcmm_external_validate", "trajectory_baseline_by_class", "trajectory_plot_jlcm",
    "trajectory_km_class", "trajectory_dynpred", "trajectory_dynpred_individual",
    "trajectory_piecewise_cox", "trajectory_weibull_compare",
    "trajectory_subgroup_class", "trajectory_chisq",
    "attrition_flowchart",
    "trajectory_pamm"
  ),
  checkpoint = list(enable = TRUE)
)

pipeline_unit_suffix <- pipeline_unit_suffix_discovery
pipeline_unit <- list(
  name = "trajectory_prognosis_unit",
  blocks = c(pipeline_unit_prefix$blocks, pipeline_unit_suffix$blocks),
  render_tables_after = pipeline_unit_prefix$render_tables_after,
  checkpoint = list(enable = TRUE)
)

config$trajectory_batch$pipeline_unit_prefix <- pipeline_unit_prefix
config$trajectory_batch$pipeline_unit_suffix <- pipeline_unit_suffix
config$trajectory_batch$pipeline_unit_suffix_discovery <- pipeline_unit_suffix_discovery
config$trajectory_batch$pipeline_unit_suffix_validation <- pipeline_unit_suffix_validation

pipeline <- pipeline_shared
