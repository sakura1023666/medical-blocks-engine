###############################################################################
#  config_trajectory_prognosis_apri.R — 轨迹预后（APRI/NLR/LAR/CAR/BUN_Cr/BAR JLCM）
#  单指标单库调试用（默认 APRI + eICU），完整批量见
#  configs/config_trajectory_prognosis_apri_batch.R
#  决策树: Decisiontree/decision_tree_trajectory_prognosis_apri.md
#  入口: run/trajectory_prognosis/run_trajectory_prognosis_apri.R
#
#  产出根目录（与发病 batch 一致）:
#    {BLOCK_RESULT_ROOT}/09_HF/Prognosis_Trajectory_38882552/
#    Windows: \\192.168.68.133\02block_result\09_HF\Prognosis_Trajectory_38882552
###############################################################################

# WSL 用 /mnt/g/...；Windows R 用 G:/02block_result（与发病 config 相同约定）
.block_result_root <- {
  env <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}
.batch_project_root <- file.path(.block_result_root, "09_HF/Prognosis_Trajectory_38882552_n1000")
.batch_data_root    <- file.path(.block_result_root, "09_HF/Prognosis_Trajectory_38882552/data")
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

# ── 结局泄漏 / 管理型 / 时间戳变量：绝不能作为预后协变量（否则单/多因素+VIF 会把
#    出科死亡状态、住院/ICU 天数等选进模型，导致 Weibull/动态模型 AUC 虚高甚至=1）。
#    两库并集；各 block 内部会与实际列名取交集，缺失的自动忽略。
.leak_admin_vars <- c(
  # eICU 结局 / 出入院 / 住院时长 / ICU 管理
  "hospdischargestatus", "hospitaladmitsource", "hospitaldischargelocation", "hosplosday",
  "unitadmitsource", "unitdischargelocation", "unitdischargestatus", "unitlosday",
  "unitstaytype", "unittype",
  # MIMIC 时间戳 / 出入院 / 住院时长 / 死亡结局 / 管理编码
  "admit_time", "icu_intime", "disch_time", "icu_outtime",
  "admission_location", "discharge_location", "hosp_day", "icu_day",
  "is_hosp_dead", "is_icu_dead", "death_within_hosp_28days", "death_within_icu_28days",
  "Micu_Code", "Marital_Status"
)

# 生命体征：强制连续变量 + 一律 median (IQR) 展示（与 Table 1 文献格式一致）
.vital_sign_vars <- c(
  "HR", "RR", "SpO2", "Temperature",
  "NBPS", "NBPD", "NBPM", "ABPS", "ABPD", "ABPM",
  "Nbps", "Nbpd", "Nbpm", "GCS", "APS", "APACHE", "SOFA"
)

config <- list(
  data = list(
    rawdata_path   = file.path(.batch_data_root, "eicu/D02_Original_AKD.RData"),
    rawdata_obj    = "data_imp",
    outcome_column = "survival_28d",
    id_column      = "subject_id",
    strip_id_columns_after_imputation = character(0)
  ),

  project = list(
    name = "Prognosis_Trajectory_38882552",
    disease_code = "09",
    disease = "HF",
    literature_pmid = "38882552",
    database = "eICU",
    study_type = "prognosis",
    classification_mode = "binary",
    analysis_group = "Non-survivor",
    reference_group = "Survivor",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),

  survival = list(
    time_var  = "survival_time_28d",
    event_var = "survival_28d",
    index_var = "APRI"
  ),

  data_clean = list(missing_threshold = 0.3),
  column_mapping = list(enable = FALSE),
  imputation = list(
    missing_col_threshold = 0.3,
    method = "cart", m = 5L, max_iter = 5L, seed = 1234L,
    complete_action = 1L, export_missing_fig = TRUE, export_table_s1 = TRUE,
    # 复合指标列不进入 MICE（batch 会追加 .composite_index_vars 全量名）
    exclude_from_mice_cols = character(0)
  ),

  baseline_binary = list(
    sig_cutoff = 0.05, pause_enable = FALSE, early_stop_if_index_ns = FALSE,
    force_continuous_vars = .vital_sign_vars,
    median_iqr_vars = .vital_sign_vars,
    # 住院/死亡/时间戳/管理变量不进 Table 1（survival 结局列单独 always_include）
    exclude_vars = .leak_admin_vars,
    # 28 天生存时间与结局须出现在基线表「28-day Outcomes」小节
    always_include_vars = c("survival_time_28d", "Mortality_28d")
  ),

  univariate_prognosis = list(
    sig_cutoff = 0.1, pause_enable = FALSE,
    # 从单/多因素候选中剔除结局泄漏 / 管理 / 时间戳变量
    excluded_predictors = .leak_admin_vars
  ),

  multivariate_prognosis = list(
    sig_cutoff = 0.05, pause_enable = FALSE, pause_on_min_sig_vars = FALSE, input_from = "tb1"
  ),

  multivariate_covariate_resolve = list(
    enable = TRUE,
    never_stop = TRUE,
    fallback_from = c("tb_screen", "tb1", "vif_screen_pass", "univar_features")
  ),

  multicollinearity = list(
    vif_threshold_strict = 4, vif_threshold_loose = 10, min_vars_threshold = 0,
    exclude_vars = c(
      "subject_id", "survival_time_28d", "survival_28d",
      .leak_admin_vars
    ),
    screen = list(csv_name = "VIF_check_screen.csv"),
    final  = list(csv_name = "VIF_check_final.csv")
  ),

  # ── 复合指标：插补后重算（单元管线 index block）；不进入 MICE，但进入基线/单多因素/VIF
  index = list(
    enable = TRUE,
    only = NULL,   # NULL → 计算 dual_safe 全量可算指标；single 配置会覆盖为 trajectory_apri 子集
    skip = NULL,
    digits = 4L
  ),

  # ── 28 天纵向指标宽表（共享层）────────────────────────────────────────────
  trajectory_calc_28d_index = list(
    index_vars = c("APRI"),
    days = 1:28,
    min_non_na_days = 2L,
    db_type = "eicu",
    lab_id_column = "patientunitstayid",
    output_dir = file.path(.batch_data_root, "eicu"),
    lab_sources = list(
      files = list.files(
        file.path(.batch_data_root, "eicu/实验室指标"),
        pattern = "\\.csv$", full.names = TRUE
      )
    ),
    restrict_to_baseline_ids = TRUE
  ),

  # ── 轨迹 JLCM（协变量取 multicollinearity_final 的 Model1∪Model2，自适应类别数）──
  trajectory_jlcm = list(
    index_vars = c("APRI"),
    class_range = 1:6,
    rawdata_path_template = file.path(.batch_data_root, "eicu/12_{Index}.RData"),
    output_dir_template = file.path(.batch_data_root, "eicu"),
    rawdata_obj = "index_df",
    id_column = "subject_id",
    non_na_col = "non_na_count",
    time_col_start = 2L,
    time_col_end = 29L,
    time_col_sep = "_",
    outlier_quantiles = c(0.01, 0.99),
    value_transform = "none",
    survival_time_var = "survival_time_28d",
    survival_event_var = "survival_28d",
    max_followup = 28,
    covariate_vars = character(0),
    covariate_vars_from_vif = TRUE,
    survival_covariate_max = 5L,
    survival_covariate_continuous_only = TRUE,
    spline_df = 2L,
    hazard = "Weibull",
    hazardtype = "Specific",
    gridsearch_rep = 50L,
    gridsearch_maxiter = 10L,
    adaptive_class_cap = TRUE,
    adaptive_class_cap_n_threshold = 1000L,
    adaptive_class_cap_ng_low = 4L,
    adaptive_class_cap_ng_high = 6L,
    prefer_final_ng = NULL,
    assign_class_ng = NULL,
    auto_select_class_ng = TRUE,
    min_class_proportion_pct = 5,
    min_entropy_for_selection = 0.3,
    stop_on_ng1_fail = TRUE,
    stop_on_no_output = TRUE,
    pause_enable = FALSE,
    pause_on_no_output = TRUE,
    pause_on_missing_survival = TRUE
  ),

  # trajectory_dynpred / trajectory_chisq 共用（与 trajectory_* 分块配置对齐）
  trajectory = list(
    index_vars = c("APRI"),
    id_column = "subject_id",
    class_for_test = 2L,
    class_for_plot = 2L,
    outcome_vars = c("survival_28d"),
    p_threshold = 1.0,
    pause_on_no_results = FALSE,
    cycle = 28L,
    jlcm = list(
      prefer_ng = 2L,
      assessment_times = c(4, 7, 14, 21),
      ndraws = 2000L,
      pause_enable = FALSE
    )
  ),

  # ── 潜类别基线特征对比表（Table S5）：协变量默认取自 VIF final ──────────────
  trajectory_baseline_by_class = list(
    index_vars = c("APRI"),
    vars_to_include = NULL,
    vars_from = "table1",   # table1 → 与 Table 1 同套基线变量（按潜类别分层）
    extra_vars = c("survival_time_28d", "Mortality_28d"),
    force_continuous_vars = .vital_sign_vars,
    survival_time_var = "survival_time_28d",
    survival_event_var = "survival_28d",
    title_template = "Table S5. Baseline characteristics of patients in {ng} latent classes of {Index}",
    filename_template = "Table_S5_Baseline_By_Class_{Index}.xlsx",
    pause_enable = FALSE,
    pause_on_no_output = FALSE
  ),

  trajectory_plot_jlcm = list(
    index_vars = c("APRI"),
    class_for_plot = 2L,
    cycle = 28L,
    pause_enable = FALSE,
    pause_on_no_figures = FALSE
  ),

  trajectory_km_class = list(
    index_vars = c("APRI"),
    survival_time_var = "survival_time_28d",
    survival_event_var = "survival_28d",
    max_followup = 28,
    pause_enable = FALSE,
    pause_on_no_output = FALSE
  ),

  trajectory_dynpred = list(
    index_vars = c("APRI"),
    cycle = 28L,
    jlcm = list(
      prefer_ng = 2L,
      assessment_times = c(4, 7, 14, 21),
      ndraws = 2000L,
      pause_enable = FALSE
    )
  ),

  trajectory_dynpred_individual = list(
    index_vars = c("APRI"),
    jlcm_ng = 2L,
    horizon = 28,
    final_landmarks = c(2, 5, 8, 11),
    ndraws = 2000L,
    boot_weibull = 2000L,
    min_pts_trend = 6L,
    pause_enable = FALSE,
    pause_on_no_output = FALSE
  ),

  trajectory_piecewise_cox = list(
    index_vars = c("APRI"),
    ref_class = "2",
    survival_time_var = "survival_time_28d",
    survival_event_var = "survival_28d",
    max_followup = 28,
    auto_scan = TRUE,
    pause_enable = FALSE,
    pause_on_no_output = FALSE
  ),

  trajectory_weibull_compare = list(
    index_vars = c("APRI"),
    jlcm_ng = 2L,
    landmarks = 4:14,
    horizon = 28,
    include_index_baseline = TRUE,
    augment_with_covariates = TRUE,
    top_prop = 0.2,
    boot_n = 2000L,
    perm_n = 2000L,
    include_youden_metrics = FALSE,
    pause_enable = FALSE,
    pause_on_no_output = FALSE
  ),

  trajectory_subgroup_class = list(
    index_vars = c("APRI"),
    survival_time_var = "survival_time_28d",
    survival_event_var = "survival_28d",
    max_followup = 28,
    age_var = "Age",
    age_cutoff = 65,
    auto_scan_categorical = TRUE,
    min_n_per_subgroup = 5L,
    pause_enable = FALSE,
    pause_on_no_output = FALSE
  ),

  trajectory_chisq = list(
    index_vars = c("APRI"),
    class_for_test = 2L,
    outcome_vars = c("survival_28d"),
    p_threshold = 1.0,
    pause_on_no_results = FALSE
  ),

  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "07_AKD_APRI_Trajectory",
    protocol_label = "trajectory_prognosis_jlcm_apri",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B07"
  )
)

pipeline <- list(
  name = "trajectory_prognosis_apri",
  blocks = c(
    "data_clean", "column_mapping", "index", "trajectory_calc_28d_index",
    "imputation",
    "index",
    "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final",
    "trajectory_jlcm",
    "trajectory_baseline_by_class",
    "trajectory_plot_jlcm",
    "trajectory_km_class",
    "trajectory_dynpred",
    "trajectory_dynpred_individual",
    "trajectory_piecewise_cox",
    "trajectory_weibull_compare",
    "trajectory_subgroup_class",
    "trajectory_chisq"
  ),
  render_tables_after = c(
    "imputation", "index", "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
