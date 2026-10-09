###############################################################################
#  config_trajectory_prognosis_batch.template.R — 轨迹预后 JLCM 双库批量模板
#
#  使用步骤:
#    1. 复制到研究产出目录（或直接在仓库内改【必改】路径后 --config 指向本文件）
#    2. 修改 .batch_project_root / .batch_data_root / dual_db 路径
#    3. Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R \
#         --config configs/templates/config_trajectory_prognosis_batch.template.R
#
#  单指标调试: --only-index NLR --workers 1
#  决策树: Decisiontree/decision_tree_trajectory_prognosis_apri.md
###############################################################################

source("configs/indices/composite_index_vars.R")

.block_result_root <- {
  env <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}
# 【必改】产出根目录
.batch_project_root <- file.path(.block_result_root, "09_HF/Prognosis_Trajectory_38882552_n1000")
.batch_data_root    <- file.path(.block_result_root, "09_HF/Prognosis_Trajectory_38882552/data")
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

.leak_admin_vars <- c(
  "hospitaldischargestatus", "hospitaldischargestatus_28d", "Mortality_28d",
  "discharge_status", "discharge_status_28d", "icu_los", "hospital_los",
  "los_icu", "los_hospital", "duration_icu", "duration_hospital",
  "admission_age_group", "readmission", "readmit"
)

.vital_sign_vars <- c(
  "SBP", "DBP", "MAP", "HR", "RR", "SpO2", "Temperature", "Weight", "Height", "BMI",
  "NBPS", "NBPD", "NBPM", "ABPS", "ABPD", "ABPM"
)

config <- list(
  project = list(
    name = "Prognosis_Trajectory_38882552_n1000",
    disease = "HF",
    disease_code = "09",
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
    rawdata_path = file.path(.batch_data_root, "eicu/D02_Original_AKD.RData"),
    rawdata_obj = "data_imp",
    id_column = "subject_id",
    outcome_column = "survival_28d"
  ),

  survival = list(
    time_var = "survival_time_28d",
    event_var = "survival_28d",
    index_var = "APRI"
  ),

  data_clean = list(missing_threshold = 0.3, subsample_n = 1000L, subsample_seed = 38882552L),
  column_mapping = list(enable = FALSE),

  # 疾病硬排除：课题自行填写 disease_vars（轨迹 shared 在 index 之后；unit 在 imputation 后再跑）
  analysis_exclusion = list(
    disease_vars = character(0),
    component_scope = "current_transitive",
    allow_no_index = TRUE,
    exclude_other_composite_indices = FALSE,
    exclude_exposure_if_uses_disease_var = TRUE
  ),

  imputation = list(
    missing_col_threshold = 0.3,
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
    always_include_vars = c("survival_time_28d", "Mortality_28d")
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
    exclude_vars = c("subject_id", "survival_time_28d", "survival_28d", .leak_admin_vars),
    screen = list(csv_name = "VIF_check_screen.csv"),
    final = list(csv_name = "VIF_check_final.csv")
  ),

  trajectory_jlcm = list(
    index_vars = c("APRI"),
    class_range = 1:6,
    rawdata_path_template = file.path(.batch_project_root, "data/{db}/12_{Index}.RData"),
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
    dual_db_harmonize_survival_covariates = TRUE,
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
    index_vars = c("APRI"),
    class_for_plot = NULL,
    use_optimal_class_ng = TRUE,
    cycle = 28L,
    pause_enable = FALSE
  ),
  trajectory_km_class = list(index_vars = c("APRI")),
  trajectory_dynpred = list(
    index_vars = c("APRI"),
    cycle = 28L,
    jlcm = list(prefer_ng = NULL, assessment_times = c(4, 7, 14, 21))
  ),
  trajectory_dynpred_individual = list(
    index_vars = c("APRI"),
    jlcm_ng = NULL,
    require_survivor_dyn_better = TRUE,
    survivor_dyn_better_min_margin = 0.02
  ),
  trajectory_piecewise_cox = list(
    index_vars = c("APRI"),
    # force_cut = NULL,  # 非空则本库强制该切点；双库共享切点见 trajectory_pub
    max_followup = 28L
  ),
  trajectory_weibull_compare = list(
    index_vars = c("APRI"), landmarks = 4:14, jlcm_ng = NULL,
    class_metric = "youden", include_youden_metrics = TRUE, top_prop = 0.2
  ),
  # 双库亚组铁律：显式锁同一变量集，禁止 auto_scan 扩库特异列
  # 年龄切点依据：【必改】按病种文献填写（ICU 老年常用 65）
  trajectory_subgroup_class = list(
    index_vars = c("APRI"),
    age_var = "Age",
    age_cutoff = 65L,
    auto_scan_categorical = FALSE,
    subgroup_vars = c(
      "Gender", "Race", "Ventilation"
      # 共病等按课题补齐，双库同一名单
    )
  ),
  trajectory_baseline_by_class = list(
    index_vars = c("APRI"),
    vars_from = "table1",
    filename_template = "Table_S5_Baseline_By_Class_{Index}.xlsx"
  ),
  trajectory_chisq = list(
    index_vars = c("APRI"),
    class_for_test = NULL,
    use_optimal_class_ng = TRUE,
    outcome_vars = c("survival_28d"), p_threshold = 1.0
  ),

  # 双库发表收口（worker 成功后自动调用 trajectory_batch_finalize_index_outputs）
  # 详见 .cursor/rules/trajectory_pub_reuse.mdc ；勿再堆 run/.../fix_* 课题脚本
  trajectory_pub = list(
    enable = TRUE,
    fig1_consort = TRUE,           # attrition_draw_dual_panel_pdf
    combine_figures = TRUE,        # Trajectory/Dynpred/轨迹KM 默认竖拼
    skip_class_swap = TRUE,        # 图/表同一原始 JLCM 标签
    drop_missing_overview = FALSE, # TRUE → KM 起编 S1（无 Missing overview）
    shared_piecewise_cut = list(   # Table3 双库同切点；可选根目录只留主库
      enable = TRUE,
      mode = "min_best",
      root_keep_db = NULL          # 如 "mimic"
    ),
    align_dual_tables = list(      # 双库 Table1/S1/S2/S3/S5 行交集对齐
      enable = FALSE,
      kinds = c("table1", "s1", "s2", "s3", "s5"),
      keep_vars = NULL
    ),
    figure_extra = character(0),
    enforce_13_figures = TRUE,
    export_formats = TRUE,
    fix_tables = TRUE
  ),

  feishu = list(
    enable = TRUE,
    disease_label = "07_AKD_APRI_Trajectory",
    protocol_label = "trajectory_prognosis_jlcm_apri",
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE
  )
)

# 复合指标不进入 MICE
config$imputation$exclude_from_mice_cols <- unique(c(
  as.character(config$imputation$exclude_from_mice_cols %||% character(0)),
  .composite_index_vars
))
config$imputation$table_s1_exclude_vars <- unique(c(
  as.character(config$imputation$table_s1_exclude_vars %||% character(0)),
  .composite_index_vars
))

# 【必改】双库原始数据
config$dual_db <- list(
  primary = list(
    name = "eICU", db_type = "eicu",
    rawdata_path = file.path(.batch_data_root, "eicu/D02_Original_AKD.RData"),
    rawdata_obj = "data_imp", id_column = "subject_id",
    lab_id_column = "patientunitstayid",
    output_subdir = file.path(.batch_project_root, "data/eicu"),
    lab_sources = list(
      files = list.files(file.path(.batch_data_root, "eicu/实验室指标"),
                         pattern = "\\.csv$", full.names = TRUE)
    )
  ),
  secondary = list(
    name = "MIMIC", db_type = "mimic",
    rawdata_path = file.path(.batch_data_root, "mimic/D01_baseline_MIMIC.RData"),
    rawdata_obj = "data_imp", id_column = "subject_id",
    lab_id_column = "subject_id",
    output_subdir = file.path(.batch_project_root, "data/mimic"),
    lab_sources = list(
      path = file.path(.batch_data_root, "mimic/mimic-实验室指标-all-1~30天.csv")
    )
  ),
  # 拼图布局可覆盖（默认 Trajectory/Dynpred/轨迹KM=stack，见 dual_db_combine_figures）
  combine_figures = list(
    layout_by_role = list(
      Trajectory = "stack",
      Dynpred = "stack",
      "Dynamic prediction" = "stack",
      "Kaplan Meier" = "stack"
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
