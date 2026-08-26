###############################################################################
#  config_sle_aki_inc_prog_batch.template.R
#  SLE → AKI 发病 + AKI 后 28 天死亡预后（单库 MIMIC 两阶段 batch）
#
#  使用步骤:
#    1. 复制到研究产出目录（与 .batch_project_root 一致）:
#       G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/config_sle_aki_inc_prog_batch.R
#    2. 核对【必改】路径；勿改 pipeline blocks / VIF 阈值
#    3. 运行（Task 8 入口）:
#       Rscript run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R \
#         --config "G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/config_sle_aki_inc_prog_batch.R"
#
#  决策树: Decisiontree/decision_tree_sle_aki_inc_prog.md
#  规格:   docs/superpowers/specs/2026-08-26-sle-aki-incidence-prognosis-two-stage-design.md
#  列审阅: <output_dir>/data/_column_review.md（Task 1）
#
#  source 后产物: config, pipeline_shared, pipeline_stage1, pipeline_stage2,
#                 pipeline_regular_batch, pipeline
#  单库: dual_db$enable = FALSE
#  产出只写 project$output_dir（结果根），禁止镜像到引擎仓库根
###############################################################################

# 【必改】与本文件所在研究目录一致（Windows R 读 G:/）
.batch_project_root <- "G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")
.batch_data_root    <- file.path(.batch_project_root, "data")
.batch_mimic_root   <- file.path(.batch_data_root, "mimic")

.baseline_rdata <- file.path(
  .batch_mimic_root, "D01_baseline_MIMIC_ICU_frist_0626 (1).RData"
)
.sle_csv        <- file.path(.batch_mimic_root, "SLE.csv")
.arf_csv        <- file.path(.batch_mimic_root, "ARF.csv")
.prognosis_csv  <- file.path(.batch_mimic_root, "mimic预后数据-all.csv")
.dabiao_rdata   <- file.path(.batch_mimic_root, "D04_dabiao(1).RData")

# Task 1 `_column_review.md` disease_vars（SLE/AKI 结局泄漏 + 肾标志物 + 边界 severity）
.disease_exclusion_vars <- c(
  "Acute_Renal_Failure", "CRRT", "CRRT_Day", "CKD",
  "Creatinine", "UreaNitrogen",
  "UrineProtein", "UrineGlucose", "AlbuminUrine", "AlbuminCreatinine",
  "UrineCreatinine", "UrineVolume",
  "SOFA", "CHARLSON", "DN"
)

# 预后 CSV 列：不进协变量 / Table1
.prognosis_exclude_vars <- c(
  "is_dead", "dead_time", "is_hosp_dead", "is_icu_dead",
  "death_within_hosp_28days", "death_within_icu_28days",
  "hosp_survival_day", "icu_survival_day",
  "admit_time", "icu_intime", "disch_time", "icu_outtime",
  "admission_location", "discharge_location",
  "hosp_day", "icu_day", "futime", "fustatus", "aki_time"
)

# 文献 force 集（MIMIC 营养/炎症发病-预后范式：人口学 + 代谢/心血管合并症 + 非肾 severity）
# 不含 disease_vars（SOFA/CHARLSON/CKD/肌酐等）
.force_covariates <- c(
  "Age", "Gender", "Race", "BMI",
  "Hypertension", "T2DM", "Heart_Failure", "GCS"
)

config <- list(

  data = list(
    # 现场筛入由 ip_cohort_sle_aki 写 ctx$data$raw；rawdata_path 供 attrition / 回退 load
    rawdata_path     = .baseline_rdata,
    rawdata_obj      = "baseline",
    outcome_path     = NULL,
    outcome_column   = "Disease",          # Stage1；Stage2 胶水改为 fustatus
    id_column        = "ID",
    strip_id_columns_after_imputation = c("ID", "subject_id", "stay_id", "hadm_id", "SEQN")
  ),

  project = list(
    name                = "SLE_AKI_inc_prog_batch",
    disease_code        = "29",
    disease             = "SLE",
    literature_pmid     = "39003396_42304330",
    database            = "MIMIC",
    database_type       = "MIMIC",
    study_type          = "incidence",     # Stage1；ip_stage2_cohort_28d 切到 prognosis
    classification_mode = "binary",
    # 背景人群=SLE（SLE.csv）；结局列 Disease=AKI。勿用 "0"/"1" 占位，否则 data_clean 会标成 SLE/No SLE
    analysis_group      = "AKI",
    reference_group     = "No AKI",
    output_dir          = .batch_project_root,   # 结果根，非引擎仓库
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root = TRUE,           # 相对 output_dir
    export_figure_svg   = FALSE,
    root                = NULL
  ),

  # 仅本套路开启文献图；缺省/其它课题不得设此 profile
  pub_figure = list(
    profile = "mimic_inc_prog_sle_aki"
  ),
  pub_figures = list(
    formats_dir = TRUE,
    dpi = 300L,
    tiff_compression = "lzw",
    write_image_information = TRUE
  ),

  dual_db = list(
    enable = FALSE
  ),

  incidence = list(
    outcome_var = "Disease",
    index_var   = NULL
  ),
  logistic = list(
    index_var = NULL
  ),
  survival = list(
    time_var      = "futime",
    event_var     = "fustatus",
    index_var     = NULL,
    time_unit     = "days",
    time_divisor  = 1
  ),

  index = list(
    enable = TRUE,
    # 放开全库指标定义（~90+）；缺成分（如 Monocyte）自动 skip，不中断
    only = NULL,
    skip = NULL,
    digits = 4L
  ),

  analysis_exclusion = list(
    disease_vars = .disease_exclusion_vars,
    component_scope = "current_transitive",
    exclude_other_composite_indices = TRUE,
    exclude_exposure_if_uses_disease_var = TRUE
  ),

  # ── 两阶段胶水路径 / 窗 / 脚注 ───────────────────────────────────────────
  ip_two_stage = list(
    baseline_path     = .baseline_rdata,
    baseline_obj      = "baseline",
    sle_path          = .sle_csv,
    arf_path          = .arf_csv,
    prognosis_path    = .prognosis_csv,
    dabiao_path       = .dabiao_rdata,     # 仅交叉核对；主分析以现场筛入为准
    baseline_id_col   = "ID",
    sle_id_col        = "subject_id",
    arf_id_col        = "subject_id",
    prognosis_id_col  = "subject_id",
    min_age           = 18,
    keep_age_na       = TRUE,          # Age 缺失留队，交 imputation 补齐（保持 n=271）
    aki_time_col      = "aki_time",
    icu_intime_col    = "icu_intime",
    dead_time_col     = "dead_time",
    dead_col          = "is_dead",
    last_followup_cols = c("disch_time", "icu_outtime"),
    force_covariates  = .force_covariates,
    # 主分析窗：ICU 住院期间 ARF/AKI 二分类（无精确发病时刻）
    aki_window_note   = paste(
      "Primary AKI window: ICU-stay ARF/AKI (Acute_Renal_Failure or ARF.csv membership).",
      "Exact aki_time is absent in baseline; 48h early-AKI is not the primary analysis.",
      "Time-zero rule C: Stage1 = ICU intime; Stage2 = aki_time if non-missing else icu_intime."
    ),
    footnotes = c(
      paste(
        "Time-zero (rule C): Stage1 exposure/incidence clock = ICU intime;",
        "Stage2 survival clock = aki_time if available else ICU intime.",
        "This MIMIC extract has no aki_time; Stage2 t0 falls back to icu_intime",
        "(ctx$results$ip_stage2_timezero_source)."
      ),
      paste(
        "28-day death: fustatus=1 iff dead and t<=28; futime=min(t,28).",
        "Survivors without community follow-up are censored at disch_time/icu_outtime",
        "(in-hospital 28-day mortality). Post-discharge deaths within 28d are missed (informative censoring bias)."
      ),
      paste(
        "dabiao n=271 vs live SLE intersect baseline after Age>=18: analytic ~270",
        "(1 Age=NA excluded in ip_cohort). Main analysis uses the live filter."
      )
    )
  ),

  covariate_policy = list(
    force_age = TRUE,
    force_sex = TRUE
  ),

  prediction = list(
    index_vars = NULL,
    keep_index_vars_in_regression_table = TRUE
  ),

  plot = list(
    font_family = "Times New Roman"
  ),

  # Figure 1：attrition_flowchart 不读 ip_attrition_steps；用 steps 对齐该表
  # ip_cohort 写出 ctx$results$ip_attrition_steps（baseline_icu / intersect_SLE / age_ge_18）
  attrition = list(
    enable = TRUE,
    title = "Figure 1. Inclusion exclusion flowchart (SLE to AKI, MIMIC)",
    db_label = "MIMIC",
    outcome_breakdown = TRUE,
    auto_append = TRUE,
    draw_pdf = TRUE,
    csv_name = "Flowchart_attrition.csv",
    figure_name = "Figure 1. Inclusion exclusion flowchart.pdf",
    specialty_figure_mode = "skip_if_generic",
    steps = list(
      list(
        id = "baseline_icu",
        label = "MIMIC ICU first-stay baseline",
        source = "rdata",
        path = .baseline_rdata,
        obj = "baseline",
        exclude_label = NULL
      ),
      list(
        id = "intersect_SLE",
        label = "SLE.csv intersect baseline (subject_id = ID)",
        source = "id_file",
        path = .sle_csv,
        id_col = "subject_id",
        join_on = "ID",
        join_universe_path = .baseline_rdata,
        join_universe_obj = "baseline",
        exclude_label = "Not in SLE.csv"
      ),
      list(
        id = "analytic",
        label = "Analytic cohort (Age >= 18; live SLE filter)",
        source = "current",
        exclude_label = "Age < 18 or Age missing"
      )
    )
  ),

  data_clean = list(
    missing_threshold = 0.3,
    age_filter        = NULL,   # Age>=18 已在 ip_cohort
    drop_columns      = NULL
  ),

  column_mapping = list(
    enable        = TRUE,
    database_type = "MIMIC"
  ),

  imputation = list(
    missing_col_threshold = 0.4,
    method                = "cart",
    m                     = 5L,
    max_iter              = 5L,
    seed                  = 1234L,
    complete_action       = 1L,
    rubin_pool            = TRUE,
    export_missing_fig    = TRUE,
    export_table_s1       = TRUE,
    force_keep_columns    = c("Age"),
    table_s1_exclude_vars = unique(c(
      "ID", "subject_id", "stay_id", "hadm_id", "SEQN", "Age_Group",
      "Disease", "Acute_Renal_Failure",
      .disease_exclusion_vars, .prognosis_exclude_vars
    ))
  ),

  analysis_var_policy = list(
    drop_sparse_categorical = TRUE,
    min_categorical_n = 20L,
    discrete_unique_max = 5L,
    dual_db_lock = FALSE
  ),

  analysis_models = list(
    model3_required_factors = character(0)
  ),

  baseline_binary = list(
    sig_cutoff = 0.05,
    strata     = NULL,
    include_vars = NULL,
    exclude_vars = unique(c(
      "ID", "subject_id", "stay_id", "hadm_id", "SEQN", "Age_Group",
      "Disease", "Acute_Renal_Failure",
      .disease_exclusion_vars, .prognosis_exclude_vars
    )),
    pause_enable = FALSE,
    pause_on_table1_fail = FALSE,
    pause_on_min_sig_vars = FALSE,
    # Stage1：指标在 Table1 组间不显著 → 早停记失败；切 Stage2 时 runner 会关掉
    early_stop_if_index_ns = TRUE
  ),

  boxplot = list(
    group_var = NULL,
    response_vars = NULL,
    overall_method = "kruskal.test",
    pairwise_method = "wilcox.test",
    pause_enable = FALSE,
    pause_if_all_overall_ns = FALSE,
    figure_kind = "supp_figure",
    figure_number = 1L
  ),

  univariate_incidence_binary = list(
    sig_cutoff = 0.05,
    screening_cutoff = 0.1,
    required_predictors = .force_covariates,
    excluded_predictors = unique(c(
      .disease_exclusion_vars, .prognosis_exclude_vars,
      "Disease", "Acute_Renal_Failure", "ID"
    )),
    demo_keywords = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "Marital", "Smoking", "Smoke", "Alcohol", "BMI"
    ),
    index_transform = "none",
    pause_enable = FALSE
  ),
  multivariate_incidence_binary = list(
    sig_cutoff = 0.05,
    input_from = "vif_screen_pass",
    write_model_factors = TRUE,
    required_predictors = .force_covariates,
    excluded_predictors = unique(c(
      .disease_exclusion_vars, .prognosis_exclude_vars,
      "Disease", "Acute_Renal_Failure", "ID"
    )),
    pause_enable = FALSE
  ),
  univariate_prognosis = list(
    sig_cutoff = 0.05,
    screening_cutoff = 0.1,
    required_predictors = .force_covariates,
    excluded_predictors = unique(c(
      .disease_exclusion_vars, .prognosis_exclude_vars, "ID"
    )),
    pause_enable = FALSE
  ),
  multivariate_prognosis = list(
    sig_cutoff = 0.05,
    required_predictors = .force_covariates,
    excluded_predictors = unique(c(
      .disease_exclusion_vars, .prognosis_exclude_vars, "ID"
    )),
    pause_enable = FALSE
  ),
  multivariate_prognosis_harmonized = list(
    table_number = 7L,
    defer_until_cox_lock = TRUE
  ),
  multivariate_covariate_resolve = list(
    enable = TRUE,
    never_stop = TRUE,
    fallback_from = c("vif_screen_pass", "tb_screen", "tb1", "univar_features")
  ),

  multicollinearity = list(
    vif_threshold_strict = 4,
    vif_threshold_loose  = 10,
    min_vars_threshold   = 0,
    export_full_vif_table = TRUE,
    anthropometric_vif_resolution = list(
      enable = TRUE,
      vars = c("BMI", "Weight", "Height"),
      prefer_drop_one_order = c("Weight", "Height"),
      apply_in_screen_only = TRUE
    ),
    screen = list(
      table_title = "Multicollinearity Analysis (VIF, univariate p<0.1 screen)",
      csv_name = "VIF_check_screen.csv"
    ),
    final = list(
      table_title = "Multicollinearity Analysis (VIF, multivariate p<0.05)",
      csv_name = "VIF_check_final.csv"
    )
  ),

  roc_simple = list(
    enable = TRUE,
    mode = "multivariable",
    covariate_source = "locked",
    export_table = FALSE,
    write_cutoff_value = TRUE,
    figure_kind = "supp_figure",
    figure_number = 2L,
    figure_width = 8,
    figure_height = 7,
    pause_enable = FALSE
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
    pause_enable = FALSE
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
    pause_enable = FALSE
  ),
  logistic_binary_glm = list(
    index_var = NULL, include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_highest_ns = FALSE,
    extend_branch = "extend_binary", degrade_branch = "degrade_quintile",
    p_threshold = 0.05, phase = "screen",
    random_search = list(
      max_outer_attempts = 100L, max_inner_attempts = 10L,
      initial_factors_n = 1L, p_threshold = 0.05, seed = NULL,
      require_triple_model_sig = TRUE, m1_to_m2_fallback = TRUE
    ),
    pause_enable = FALSE
  ),
  logistic_quintile_glm = list(
    index_var = NULL, include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_separation = TRUE, stop_if_crude_all_ns = TRUE,
    extend_branch = "extend_quintile", degrade_branch = character(0),
    p_threshold = 0.05, phase = "screen",
    random_search = list(
      max_outer_attempts = 100L, max_inner_attempts = 10L,
      initial_factors_n = 1L, p_threshold = 0.05, seed = NULL
    ),
    pause_enable = FALSE
  ),

  # 主文图序：Fig1 纳排 → Fig2 发病 RCS → Fig3 发病森林 → Fig4 预后 RCS → Fig5 闸门 KM → Fig6 预后森林
  rcs_incidence = list(
    index_var = NULL, nk_range = 3:5, histbin = 1, color_seed = 123,
    group_cutoffs = "primary",
    figure_kind = "main_figure", figure_number = 2L, bump_counter = TRUE,
    plot_x_quantiles = c(0.10, 0.90),
    ylim = c(0, 5), y_min = 0, y_max = 5, ylim_force = TRUE
  ),
  rcs_prognosis = list(
    index_var = NULL, nk_range = 3:5, pause_enable = FALSE,
    figure_kind = "main_figure", figure_number = 4L, bump_counter = TRUE,
    plot_x_quantiles = c(0.10, 0.90),
    ylim = c(0, 5), y_min = 0, y_max = 5, ylim_force = TRUE
  ),

  threshold_logistic = list(
    index_var = NULL,
    outcome_var = NULL,
    covariates = NULL,          # NULL → Model2Factors → Model1
    q_lo = 0.10, q_hi = 0.90, n_grid = 81L,
    min_segment_n = 20L,
    start_from_rcs = TRUE,
    export_figure = FALSE       # 阈值表保留；图与 RCS/主文重复，默认不出
  ),

  cox_quartile = list(
    gate_enable = TRUE, stop_if_crude_highest_ns = TRUE,
    extend_branch = "extend_quartile", degrade_branch = "degrade_tertile",
    p_threshold = 0.05, pause_enable = FALSE,
    require_both_models_sig = TRUE,
    ph_test_enable = TRUE,
    covariate_search = list(
      enable = TRUE, prefer_full_first = TRUE,
      max_model1_attempts = 1000L, max_model2_attempts = 1000L,
      on_search_fail = "degrade"
    )
  ),
  cox_tertile = list(
    gate_enable = TRUE, stop_if_crude_highest_ns = TRUE,
    extend_branch = "extend_tertile", degrade_branch = "degrade_binary",
    p_threshold = 0.05, pause_enable = FALSE,
    require_both_models_sig = TRUE,
    ph_test_enable = TRUE,
    covariate_search = list(
      enable = TRUE, prefer_full_first = TRUE,
      max_model1_attempts = 1000L, max_model2_attempts = 1000L,
      on_search_fail = "degrade"
    )
  ),
  cox_binary = list(
    gate_enable = TRUE, stop_if_crude_highest_ns = TRUE,
    extend_branch = "extend_binary",
    p_threshold = 0.05, pause_enable = FALSE,
    require_both_models_sig = TRUE,
    ph_test_enable = TRUE,
    covariate_search = list(
      enable = TRUE, prefer_full_first = TRUE,
      max_model1_attempts = 1000L, max_model2_attempts = 1000L,
      on_search_fail = "degrade"
    )
  ),

  # spec Stage2 含 plot_cutoff；本套路显式开启（双库预后默认已停产）
  plot_cutoff = list(
    enable = FALSE,
    minprop = 0.2,
    auto_fallback = TRUE,
    annotate_cutoff = "auto",
    figure_kind = "supp_figure",
    figure_number = 1L,
    pause_enable = FALSE
  ),

  km_strata = list(
    time_var = "futime", event_var = "fustatus", event_value = 1,
    time_divisor = 1,
    auto_xlim = FALSE, auto_break_time = FALSE,
    xlim = c(0, 28), break_time_by = 7,
    id_column = "ID",
    figure_kind = "main_figure",
    figure_number = 5L,
    figure_caption_template = "Kaplan-Meier curves of {index} {method} and 28-day mortality in {disease}",
    title = "",
    risk_table = TRUE,
    risk_table_height = 0.28,
    export_combined = FALSE,
    combined_figure_kind = "supp_figure",
    # strata_vars / strata_defs 由 ip_two_stage_patch_km_strata_for_index() 按指标注入
    strata_vars = NULL,
    strata_vars_by_branch = list(
      extend_quartile = NULL, extend_tertile = NULL,
      degrade_tertile = NULL, degrade_binary = NULL, degrade_done = NULL
    ),
    strata_defs = list(),
    font_family = "Times New Roman",
    pause_enable = FALSE
  ),
  km_binary = list(
    time_divisor = 1,
    auto_xlim = FALSE, auto_break_time = FALSE,
    xlim = c(0, 28), break_time_by = 7,
    figure_kind = "supp_figure",
    figure_number = 3L,
    figure_caption_template = "Kaplan-Meier curves of {index} {method} and 28-day mortality in {disease}",
    title = "",
    risk_table = TRUE,
    pause_enable = FALSE
  ),
  segmented_cox_binary = list(
    maxstat_fallback = FALSE,
    covariates = NULL,
    random_covariate_search = list(enable = FALSE),
    pause_enable = FALSE,
    pause_on_cox_mismatch = FALSE,
    min_segment_n = 10L,
    min_segment_events = 3L
  ),
  segmented_cox_tertile = list(
    pause_enable = FALSE,
    pause_on_cox_mismatch = FALSE,
    min_segment_n = 10L,
    min_segment_events = 3L
  ),
  segmented_cox_quartile = list(
    pause_enable = FALSE,
    pause_on_cox_mismatch = FALSE,
    min_segment_n = 10L,
    min_segment_events = 3L
  ),

  subgroup = list(
    min_n = 20,
    # 年龄切点依据：老年 SLE / 重症风湿病亚组与 ICU 预后文献常用 65 岁（ACR/EULAR 老年 SLE 口径；
    # 无本课题 RCT 特异界值时与引擎默认 65 一致）。森林图仅二分类，禁止四档。
    age_cutoff = 65L,
    var_source = "table1_categorical",
    required_subgroup_vars = c("Age_Group", "Gender", "Hypertension", "T2DM"),
    forbid_subgroup_vars = unique(c(
      "Index_Group", "Index_Group_Tertile", "Index_Group_Quartile",
      "Ventilation", "Ventilation_Hour",
      .disease_exclusion_vars
    )),
    forest_xlim = c(0.2, 4),
    forest_xlim_max = 80,
    export_table = FALSE,
    pause_enable = FALSE,
    level_order = list(
      Age_Group = c("< 65", "\u2265 65")
    )
  ),
  subgroup_incidence = list(
    figure_kind = "main_figure", figure_number = 3L, bump_counter = TRUE,
    pause_enable = FALSE
  ),
  subgroup_prognosis = list(
    figure_kind = "main_figure", figure_number = 6L, bump_counter = TRUE,
    pause_enable = FALSE
  ),

  feishu = list(
    enable = TRUE,
    disease_label  = "29_SLE",
    protocol_label = "29_SLE_inc_prog_39003396_42304330",
    workplan_id    = "Bxx",          # Task 9：飞书工作计划下一空号
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE
  ),

  incidence_batch = list(
    index_vars = NULL,
    index_group = "dual_safe",
    skip_existing = TRUE,
    db_mode = "regular",
    output_base = .batch_project_root,
    shared_ck_base = file.path(.batch_ck_root, "_shared"),
    index_ck_base = file.path(.batch_ck_root, "by_index"),
    min_valid_per_db = 50L,
    mimic_imputation_threshold = 0.40,
    base_exclude_vars = unique(c(
      "ID", "subject_id", "stay_id", "hadm_id", "SEQN",
      "Disease", "Acute_Renal_Failure",
      .disease_exclusion_vars, .prognosis_exclude_vars
    )),
    base_subgroup_vars = c("Age", "Gender", "Race", "Hypertension", "T2DM"),
    sensitivity_suite = list(
      enable        = TRUE,  # 主分析 success 后由 ip_two_stage_batch_run 自动跑
      age_cutoff    = 65L,     # 与 subgroup$age_cutoff 同值
      min_n_per_db  = 30L,
      min_yes_n     = 20L,
      complete_case = TRUE
    ),
    subgroup_fallback = list(
      enable = TRUE,
      try_all = TRUE,
      min_n_per_subgroup = 30L,
      age_cutoff = 65L,
      age_mid_lower = 45L,
      subgroups = list(
        list(label = "Age_{age_cutoff}", expr = "Age >= {age_cutoff}"),
        list(label = "Male",   expr = 'Gender == "Male"'),
        list(label = "Female", expr = 'Gender == "Female"')
      )
    )
  ),

  ip_two_stage_batch = list(
    index_vars = NULL,
    skip_existing = TRUE,
    output_base = .batch_project_root,
    shared_ck_base = file.path(.batch_ck_root, "_shared"),
    index_ck_base = file.path(.batch_ck_root, "by_index")
  ),

  feature_selection = list(enable = FALSE)
)

# ── spec §6 分阶段 block 序（单库；无 dual_db_* / 无 mediation）────────────
.blocks_stage0 <- c(
  "ip_cohort_sle_aki",
  "attrition_flowchart",
  "data_clean",
  "column_mapping",
  "index",
  "analysis_exclusion",
  "imputation"
)

.blocks_stage1 <- c(
  "baseline_binary",
  "boxplot",
  "univariate_incidence_binary",
  "multicollinearity_screen",
  "multivariate_incidence_binary",
  "multicollinearity_final",
  "multivariate_incidence_harmonized",
  "simple_ROC",
  "logistic_quartile_glm",
  "logistic_tertile_glm",
  "logistic_binary_glm",
  "logistic_quintile_glm",
  "rcs_incidence",
  "logistic_quartile_glm_rcs",
  "logistic_tertile_glm_rcs",
  "logistic_binary_glm_rcs",
  "threshold_logistic",
  "subgroup_incidence"
)

.blocks_bridge <- c("ip_stage2_cohort_28d")

.blocks_stage2 <- c(
  "baseline_binary",
  "univariate_prognosis",
  "multicollinearity_screen",
  "multivariate_prognosis",
  "multicollinearity_final",
  "multivariate_prognosis_harmonized",
  "simple_ROC",
  "cox_quartile",
  "cox_tertile",
  "cox_binary",
  "rcs_prognosis",
  "km_strata",
  "segmented_cox_quartile",
  "segmented_cox_tertile",
  "segmented_cox_binary",
  "subgroup_prognosis"
)

.blocks_full <- c(.blocks_stage0, .blocks_stage1, .blocks_bridge, .blocks_stage2)

pipeline_shared <- list(
  name   = "sle_aki_inc_prog_shared_stage0",
  blocks = .blocks_stage0,
  logistic_gate = list(enable = FALSE),
  cox_gate = list(enable = FALSE),
  render_tables_after  = c("analysis_exclusion", "imputation", "attrition_flowchart"),
  render_figures_after = "attrition_flowchart",
  dual_db    = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    dir    = file.path(.batch_ck_root, "_shared", "mimic")
  )
)

pipeline_stage1 <- list(
  name   = "sle_aki_inc_prog_stage1",
  blocks = .blocks_stage1,
  logistic_gate = list(enable = TRUE),
  cox_gate = list(enable = FALSE),
  render_tables_after = c(
    "baseline_binary", "boxplot",
    "univariate_incidence_binary", "multicollinearity_screen",
    "multivariate_incidence_binary", "multicollinearity_final",
    "multivariate_incidence_harmonized",
    "simple_ROC",
    "logistic_quartile_glm", "logistic_tertile_glm",
    "logistic_binary_glm", "logistic_quintile_glm",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
    "threshold_logistic", "subgroup_incidence"
  ),
  render_figures_after = c(
    "boxplot", "simple_ROC", "rcs_incidence", "threshold_logistic", "subgroup_incidence"
  ),
  dual_db    = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline_stage2 <- list(
  name   = "sle_aki_inc_prog_stage2",
  blocks = .blocks_stage2,
  logistic_gate = list(enable = FALSE),
  cox_gate = list(enable = TRUE),
  render_tables_after = c(
    "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multicollinearity_final",
    "multivariate_prognosis_harmonized",
    "simple_ROC",
    "cox_quartile", "cox_tertile", "cox_binary",
    "segmented_cox_quartile", "segmented_cox_tertile", "segmented_cox_binary",
    "subgroup_prognosis"
  ),
  render_figures_after = c(
    "simple_ROC", "rcs_prognosis",
    "km_strata", "subgroup_prognosis"
  ),
  dual_db    = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline_regular_batch <- list(
  name   = "sle_aki_inc_prog_full",
  blocks = .blocks_full,
  logistic_gate = list(enable = TRUE),
  cox_gate = list(enable = TRUE),
  render_tables_after = unique(c(
    pipeline_shared$render_tables_after,
    pipeline_stage1$render_tables_after,
    pipeline_stage2$render_tables_after
  )),
  render_figures_after = unique(c(
    pipeline_shared$render_figures_after,
    pipeline_stage1$render_figures_after,
    pipeline_stage2$render_figures_after
  )),
  dual_db    = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline <- pipeline_regular_batch
