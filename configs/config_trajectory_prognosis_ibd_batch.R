###############################################################################
#  config_trajectory_prognosis_ibd_batch.R — IBD 双库轨迹预后（JLCM）
#
#  本课题例外（仅此项目）:
#    - 不挂 dual_db_column_harmonize（Table1 两库各自列，关 Gate A）
#    - disease_vars 仅 IBD_subtype（CRP 等保留）
#
#  用法:
#    Rscript run/trajectory_prognosis/prepare_ibd_surv28_data.R
#    Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R \
#      --config configs/config_trajectory_prognosis_ibd_batch.R
#    # 冒烟: --only-index NLR --workers 1
###############################################################################

source("configs/indices/composite_index_vars.R")

.block_result_root <- {
  env <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}
.batch_project_root <- file.path(.block_result_root, "28_IBD/Prognosis_Trajectory_38882552")
.batch_data_root    <- file.path(.batch_project_root, "data")
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

.leak_admin_vars <- c(
  "hospitaldischargestatus", "hospitaldischargestatus_28d", "Mortality_28d",
  "discharge_status", "discharge_status_28d", "icu_los", "hospital_los",
  "los_icu", "los_hospital", "duration_icu", "duration_hospital",
  "admission_age_group", "readmission", "readmit", "DN"
)

.vital_sign_vars <- c(
  "SBP", "DBP", "MAP", "HR", "RR", "SpO2", "Temperature", "Weight", "Height", "BMI",
  "NBPS", "NBPD", "NBPM", "ABPS", "ABPD", "ABPM"
)

# 本课题：仅纳排键；CRP 保留（见 Data/_column_review.md）
.disease_exclusion_vars <- c("IBD_subtype")

# 本课题 Table1 强制保留共病（不受 min_categorical_n 稀疏删除）
.comorbidity_protect_vars <- c(
  "Hypertension", "T1DM", "T2DM", "Diabetes",
  "Heart_Failure", "Myocardial_Infarction",
  "Malignant_Tumor", "Cancer",
  "CKD", "Acute_Renal_Failure",
  "Liver_cirrhosis", "Hepatitis",
  "Pneumonia", "Stroke", "Hyperlipidemia", "COPD",
  "Tuberculosis", "Ventilation"
)

config <- list(
  project = list(
    name = "Prognosis_Trajectory_38882552_IBD",
    disease = "IBD",
    disease_code = "28",
    analysis_group = "Non-survivor",
    reference_group = "Survivor",
    classification_mode = "binary",
    study_type = "prognosis",
    database = "eICU+MIMIC",
    root = normalizePath(getwd(), winslash = "/", mustWork = FALSE),
    output_dir = .batch_project_root,
    mirror_pub_outputs_to_root = TRUE
  ),

  data = list(
    rawdata_path = file.path(.batch_data_root, "eicu/D04_rt_IBD_surv28.RData"),
    rawdata_obj = "rt",
    # column_mapping 将 subject_id/ID 统一为 ID；实验室过滤用 dual_db$lab_id_column
    id_column = "ID",
    outcome_column = "survival_28d"
  ),

  survival = list(
    time_var = "survival_time_28d",
    event_var = "survival_28d",
    index_var = NULL
  ),

  # 全量 IBD；共享层不按 30% 删列（小样本高缺失），交给插补阈值
  data_clean = list(missing_threshold = 1.0),
  column_mapping = list(enable = TRUE),

  analysis_exclusion = list(
    disease_vars = .disease_exclusion_vars,
    component_scope = "current_transitive",
    # 共享层无当前 index：只删 disease_vars；指标层 worker 会再跑完整排除
    allow_no_index = TRUE,
    exclude_other_composite_indices = FALSE,
    exclude_exposure_if_uses_disease_var = TRUE
  ),

  imputation = list(
    missing_col_threshold = 0.5,
    method = "cart", m = 5L, max_iter = 5L, seed = 1234L,
    complete_action = 1L, export_missing_fig = TRUE, export_table_s1 = TRUE,
    exclude_from_mice_cols = character(0),
    table_s1_exclude_vars = character(0)
  ),

  baseline_binary = list(
    sig_cutoff = 0.05, pause_enable = FALSE, early_stop_if_index_ns = FALSE,
    force_continuous_vars = .vital_sign_vars,
    median_iqr_vars = .vital_sign_vars,
    exclude_vars = .leak_admin_vars,
    always_include_vars = c(
      "survival_time_28d", "Mortality_28d",
      .comorbidity_protect_vars
    )
  ),

  univariate_prognosis = list(
    sig_cutoff = 0.1, pause_enable = FALSE,
    excluded_predictors = .leak_admin_vars
  ),

  multivariate_prognosis = list(
    sig_cutoff = 0.05, pause_enable = FALSE, pause_on_min_sig_vars = FALSE, input_from = "tb1"
  ),

  multivariate_covariate_resolve = list(
    enable = TRUE, never_stop = TRUE,
    fallback_from = c("tb_screen", "tb1", "vif_screen_pass", "univar_features")
  ),

  multicollinearity = list(
    vif_threshold_strict = 4, vif_threshold_loose = 10, min_vars_threshold = 0,
    exclude_vars = c("subject_id", "ID", "survival_time_28d", "survival_28d", .leak_admin_vars),
    screen = list(csv_name = "VIF_check_screen.csv"),
    final = list(csv_name = "VIF_check_final.csv")
  ),

  # 年龄切点：无更强 IBD-ICU 亚组文献，用默认 65 二分类
  subgroup = list(
    age_cutoff = 65L,
    level_order = list(
      Age_Group = c("< 65", "\u2265 65")
    )
  ),

  # 本课题：两库 Table1 各自独立，不做 Gate A 列交集
  # 共病列一律保护，不因 min_categorical_n 被删（仅本项目）
  analysis_var_policy = list(
    drop_sparse_categorical = TRUE,
    min_categorical_n = 20L,
    discrete_unique_max = 5L,
    dual_db_lock = FALSE,
    protect_categorical_vars = .comorbidity_protect_vars
  ),

  trajectory_jlcm = list(
    index_vars = NULL,
    class_range = 1:6,
    rawdata_path_template = file.path(.batch_project_root, "data/{db}/12_{Index}.RData"),
    output_dir_template = file.path(.batch_data_root, "{db}"),
    rawdata_obj = "index_df",
    id_column = "ID",
    non_na_col = "non_na_count",
    time_col_start = 2L, time_col_end = 29L, time_col_sep = "_",
    outlier_quantiles = c(0.01, 0.99),
    value_transform = "none",
    survival_time_var = "survival_time_28d",
    survival_event_var = "survival_28d",
    max_followup = 28,
    covariate_vars = character(0),
    covariate_vars_from_vif = TRUE,
    # 协变量在库内选；非 Gate A。两库可不强制同一协变量集（小样本）
    dual_db_harmonize_survival_covariates = FALSE,
    survival_covariate_max = 5L,
    survival_covariate_continuous_only = TRUE,
    spline_df = 2L,
    hazard = "Weibull", hazardtype = "Specific",
    gridsearch_rep = 50L, gridsearch_maxiter = 10L,
    adaptive_class_cap = TRUE,
    adaptive_class_cap_n_threshold = 1000L,
    adaptive_class_cap_ng_low = 4L, adaptive_class_cap_ng_high = 6L,
    prefer_final_ng = NULL, assign_class_ng = NULL,
    auto_select_class_ng = TRUE,
    min_class_proportion_pct = 5, min_entropy_for_selection = 0.3,
    stop_on_ng1_fail = TRUE,
    stop_on_ng2_fail = TRUE,
    stop_on_no_output = TRUE,
    pause_enable = FALSE, pause_on_no_output = TRUE, pause_on_missing_survival = TRUE
  ),

  trajectory_plot_jlcm = list(
    index_vars = NULL,
    class_for_plot = NULL,
    use_optimal_class_ng = TRUE,
    cycle = 28L,
    pause_enable = FALSE
  ),
  trajectory_km_class = list(index_vars = NULL),
  trajectory_dynpred = list(
    index_vars = NULL,
    cycle = 28L,
    jlcm = list(prefer_ng = NULL, assessment_times = c(4, 7, 14, 21))
  ),
  trajectory_dynpred_individual = list(
    index_vars = NULL,
    jlcm_ng = NULL,
    require_survivor_dyn_better = TRUE,
    survivor_dyn_better_min_margin = 0.02
  ),
  trajectory_piecewise_cox = list(index_vars = NULL),
  trajectory_weibull_compare = list(
    index_vars = NULL, landmarks = 4:14, jlcm_ng = NULL,
    class_metric = "youden", include_youden_metrics = TRUE, top_prop = 0.2
  ),
  trajectory_subgroup_class = list(index_vars = NULL),
  trajectory_baseline_by_class = list(
    index_vars = NULL,
    vars_from = "table1",
    filename_template = "Table_S5_Baseline_By_Class_{Index}.xlsx"
  ),
  trajectory_chisq = list(
    index_vars = NULL,
    class_for_test = NULL,
    use_optimal_class_ng = TRUE,
    outcome_vars = c("survival_28d"), p_threshold = 1.0
  ),

  attrition = list(
    enable = TRUE,
    title = "Inclusion / exclusion flowchart — IBD trajectory prognosis",
    csv_name = "Flowchart_attrition.csv",
    figure_name = "Figure 1. Inclusion exclusion flowchart.pdf",
    draw_pdf = TRUE,
    auto_append = TRUE
  ),

  feishu = list(
    enable = TRUE,
    disease_label = "28_IBD_Trajectory",
    protocol_label = "trajectory_prognosis_jlcm_ibd",
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE
  )
)

config$imputation$exclude_from_mice_cols <- unique(c(
  as.character(config$imputation$exclude_from_mice_cols %||% character(0)),
  .composite_index_vars
))
config$imputation$table_s1_exclude_vars <- unique(c(
  as.character(config$imputation$table_s1_exclude_vars %||% character(0)),
  .composite_index_vars,
  .disease_exclusion_vars
))
config$baseline_binary$exclude_vars <- unique(c(
  as.character(config$baseline_binary$exclude_vars %||% character(0)),
  .disease_exclusion_vars
))
config$univariate_prognosis$excluded_predictors <- unique(c(
  as.character(config$univariate_prognosis$excluded_predictors %||% character(0)),
  .disease_exclusion_vars
))

# 双库：指向预处理后的 IBD+28d 结局；本课题不跑 Gate A
# mirror_aggregate + combine_figures：指标根 Tables/Figures 汇总两库（预后套路）
config$dual_db <- list(
  enable = TRUE,
  mirror_aggregate = TRUE,
  combine_figures = list(
    enable = TRUE,
    remove_singles = TRUE,
    drop_missing_overview = TRUE,
    panel_order = "primary_first",
    label_format = "A. {db}"
  ),
  primary = list(
    name = "eICU", db_type = "eicu",
    rawdata_path = file.path(.batch_data_root, "eicu/D04_rt_IBD_surv28.RData"),
    rawdata_obj = "rt", id_column = "ID",
    lab_id_column = "patientunitstayid",
    output_subdir = file.path(.batch_project_root, "data/eicu"),
    lab_sources = list(
      files = list.files(
        file.path(.batch_data_root, "eicu"),
        pattern = "实验室.*\\.csv$",
        full.names = TRUE
      )
    )
  ),
  secondary = list(
    name = "MIMIC", db_type = "mimic",
    rawdata_path = file.path(.batch_data_root, "mimic/D04_rt_IBD_surv28.RData"),
    rawdata_obj = "rt", id_column = "ID",
    lab_id_column = "subject_id",
    output_subdir = file.path(.batch_project_root, "data/mimic"),
    lab_sources = list(
      path = file.path(.batch_data_root, "mimic/mimic-实验室指标-all-1~30天.csv")
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
  db_seq = c("eicu", "mimic"),
  index_vars = NULL, index_group = "dual_safe",
  parallel_workers = "auto",
  worker_script = "run/trajectory_prognosis/run_trajectory_prognosis_apri_batch_worker.R"
)

pipeline_shared <- list(
  name = "trajectory_prognosis_shared",
  blocks = c(
    "data_clean", "column_mapping", "index",
    "analysis_exclusion", "trajectory_calc_28d_index"
  ),
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

pipeline_unit_suffix <- list(
  name = "trajectory_prognosis_unit_suffix",
  blocks = c(
    "trajectory_jlcm", "trajectory_baseline_by_class", "trajectory_plot_jlcm",
    "trajectory_km_class", "trajectory_dynpred", "trajectory_dynpred_individual",
    "trajectory_piecewise_cox", "trajectory_weibull_compare",
    "trajectory_subgroup_class", "trajectory_chisq",
    "attrition_flowchart"
  ),
  checkpoint = list(enable = TRUE)
)

pipeline_unit <- list(
  name = "trajectory_prognosis_unit",
  blocks = c(pipeline_unit_prefix$blocks, pipeline_unit_suffix$blocks),
  render_tables_after = pipeline_unit_prefix$render_tables_after,
  checkpoint = list(enable = TRUE)
)

config$trajectory_batch$pipeline_unit_prefix <- pipeline_unit_prefix
config$trajectory_batch$pipeline_unit_suffix <- pipeline_unit_suffix

pipeline <- pipeline_shared
