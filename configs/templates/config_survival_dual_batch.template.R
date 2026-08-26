###############################################################################
#  config_survival_dual_batch.template.R — 双库预后批量多指标配置模板（引擎 defaults）
#
#  注意: 本文件被 survival_dual_batch_build.R 以 source(local=TRUE) 加载，
#        必须是完整 config list（不可再 source build.R，否则会死递归）。
#  程序员薄配置请用研究目录 config_survival.R（见 18_SAE 成功样板）。
#
#  使用步骤:
#    1. 研究区复制程序员薄配置到项目根:
#       参照 configs/templates 旁说明 / 18_SAE/prognosis_38902748/config_survival.R
#    2. 或直接运行 run_survival_dual_batch.R --config config_survival.R
#
#  source 后产物（由 build 合并）: config 的 block 级默认参数
###############################################################################

# 【仅当直接 source 本模板测试时用】程序员薄配置会由 build 覆盖路径
.batch_project_root <- if (exists(".batch_project_root", inherits = TRUE)) .batch_project_root else "G:/02block_result/01_ARDS/prognosis_38341157"
.batch_ck_root      <- if (exists(".batch_ck_root", inherits = TRUE)) .batch_ck_root else file.path(.batch_project_root, "checkpoints")
.batch_data_root    <- if (exists(".batch_data_root", inherits = TRUE)) .batch_data_root else file.path(.batch_project_root, "Data")

config <- list(
  data = list(
    rawdata_path     = file.path(.batch_data_root, "eicu/D04_rt_CleanData.RData"),
    rawdata_obj      = "rt",
    outcome_column   = "fustatus",
    id_column        = "subject_id",
    strip_id_columns_after_imputation = c("ID", "subject_id", "SEQN")
  ),
  project = list(
    name = "ARDS_dual_survival_batch",
    disease_code = "01", disease = "ARDS",
    literature_pmid = "38341157",
    study_type = "prognosis",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    # 发表图只保留 PDF；需要 Illustrator 源文件时再设 TRUE
    export_figure_svg = FALSE
  ),
  attrition = list(
    enable = TRUE,
    title = NULL,
    db_label = NULL,
    steps = list(),
    outcome_breakdown = TRUE,
    auto_append = TRUE,
    draw_pdf = TRUE,
    csv_name = "Flowchart_attrition.csv",
    figure_name = "Figure 1. Inclusion exclusion flowchart.pdf",
    specialty_figure_mode = "skip_if_generic"
  ),
  survival = list(
    time_var = "futime", event_var = "fustatus",
    index_var = NULL, time_unit = "days", time_divisor = 1
  ),
  index = list(enable = TRUE, only = NULL, skip = NULL, digits = 4L),
  analysis_models = list(
    model3_required_factors = character(0)
  ),
  # 强制协变量：默认只 Age；Gender 不强制（需时设 force_sex=TRUE）
  covariate_policy = list(
    force_age = TRUE,
    force_sex = FALSE
  ),
  pub_figures = list(
    formats_dir = TRUE,
    dpi = 300L,
    tiff_compression = "lzw",
    write_image_information = TRUE
  ),
  dual_db = list(
    enable = TRUE, mirror_aggregate = TRUE,
    # 汇总 Figures：成对 -DB 图拼为 A/B 一张；默认删除分库单图与 Missing Value Overview
    combine_figures = list(
      enable = TRUE,
      remove_singles = TRUE,
      drop_missing_overview = TRUE,
      panel_order = "primary_first",
      label_format = "A. {db}"
      # 版式默认：RCS=上下；KM/亚组森林=左右（见 dual_db_combine_figures.R）
    ),
    checkpoint_base = .batch_ck_root,
    harmonization_dir = file.path(.batch_ck_root, "_global_harmonization"),
    primary = list(
      name = "eICU", db_type = "regular",
      rawdata_path = file.path(.batch_data_root, "eicu/D04_rt_CleanData.RData"),
      rawdata_obj = "rt", id_column = "subject_id",
      column_mapping_type = "eICU"
    ),
    secondary = list(
      name = "MIMIC", db_type = "regular",
      rawdata_path = file.path(.batch_data_root, "mimic/D04_rt_CleanData.RData"),
      rawdata_obj = "rt", id_column = "subject_id",
      column_mapping_type = "MIMIC"
    ),
    harmonization = list(
      demo_keywords = c("Age", "Gender", "Sex", "Race", "Smoking", "Smoke"),
      require_same_clinical_cols = TRUE,
      require_same_demo_cols = TRUE,
      sync_after_vif_final = TRUE,
      covariate_source = "auto"
    )
  ),
  feishu = list(
    enable = TRUE,
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    disease_label = "01_ARDS",
    protocol_label = "01_ARDS_prognosis_38341157"
  ),
  survival_batch = list(
    index_vars = NULL, index_group = "dual_safe",
    db_mode = "both", skip_existing = TRUE,
    output_base = .batch_project_root,
    shared_ck_base = file.path(.batch_ck_root, "_shared"),
    index_ck_base = file.path(.batch_ck_root, "by_index"),
    gate_a_missing_threshold = 1.0,
    min_valid_per_db = 50L,
    nhanes_imputation_threshold = 0.40,
    mimic_imputation_threshold = 0.40,
    base_exclude_vars = c("ID", "subject_id", "Hemoglobin", "futime", "fustatus"),
    # ── 敏感性（与发病同构）：Yes/No 从两库 Table 1 动态生成；忽略旧课题残留的 scenarios。
    # complete_case=TRUE（默认）：插补前 mapped/cleaned 对暴露+时间/结局+锁定 Model1/2 listwise。
    # enable 由 study_interface build 的 sens_enable 覆盖。
    sensitivity_suite = list(
      enable         = TRUE,
      age_cutoff     = 65L,
      min_n_per_db   = 50L,
      min_yes_n      = 50L,
      complete_case  = TRUE
    )
  ),
  capability = list(
    exposure_mode = "primary_only",
    variable_aliases = list(age = "Age", hypertension = "Hypertension", diabetes = "Diabetes")
  ),
  imputation = list(
    missing_col_threshold = 0.4, method = "cart", m = 1L, seed = 1234L,
    mi_quality_exclude_enable = TRUE, mi_quality_p_threshold = 0.05,
    export_missing_fig = FALSE
  ),
  # 生成所有表/图前：删除任一层级观测数 < min_categorical_n 的分类列（全局默认开启）
  # 双库：dual_db_lock=TRUE 时按两库并集锁定删除（稀疏分类 + 高缺失），保证后续全部表/图列对齐
  analysis_var_policy = list(
    drop_sparse_categorical = TRUE,
    min_categorical_n = 20L,
    discrete_unique_max = 5L,
    dual_db_lock = TRUE
  ),
  # Cox 闸门、VIF、baseline 等 — 与 configs/config_survival_dual_batch.R 保持一致，勿改阈值
  cox_quartile = list(gate_enable = TRUE, stop_if_crude_highest_ns = TRUE,
                      extend_branch = "extend_quartile", degrade_branch = "degrade_tertile",
                      p_threshold = 0.05, pause_enable = FALSE,
                      require_both_models_sig = TRUE,
                      # 四分位基线表固定 S10，勿与 Gate C+ 双库统一多因素 Table S7 抢号
                      baseline_by_group_table_s = 10L,
                      ph_test_enable = TRUE,
                      covariate_search = list(
                        enable = TRUE, prefer_full_first = TRUE,
                        max_model1_attempts = 1000L, max_model2_attempts = 1000L,
                        on_search_fail = "degrade"
                      )),
  cox_tertile  = list(gate_enable = TRUE, stop_if_crude_highest_ns = TRUE,
                      extend_branch = "extend_tertile", degrade_branch = "degrade_binary",
                      p_threshold = 0.05, pause_enable = FALSE,
                      require_both_models_sig = TRUE,
                      ph_test_enable = TRUE,
                      covariate_search = list(
                        enable = TRUE, prefer_full_first = TRUE,
                        max_model1_attempts = 1000L, max_model2_attempts = 1000L,
                        on_search_fail = "degrade"
                      )),
  cox_binary   = list(gate_enable = TRUE, stop_if_crude_highest_ns = TRUE,
                      extend_branch = "extend_binary", p_threshold = 0.05, pause_enable = FALSE,
                      require_both_models_sig = TRUE,
                      ph_test_enable = TRUE,
                      covariate_search = list(
                        enable = TRUE, prefer_full_first = TRUE,
                        max_model1_attempts = 1000L, max_model2_attempts = 1000L,
                        on_search_fail = "degrade"
                      )),
  multivariate_covariate_resolve = list(
    enable = TRUE, never_stop = TRUE,
    fallback_from = c("vif_screen_pass", "tb_screen", "tb1", "univar_features")
  ),
  logistic = list(model2_max_covariates = 20L),
  baseline_binary = list(sig_cutoff = 0.05, pause_enable = FALSE, export_train_val_baseline = TRUE),
  univariate_prognosis = list(sig_cutoff = 0.05, screening_cutoff = 0.1, pause_enable = FALSE),
  multivariate_prognosis = list(sig_cutoff = 0.05, pause_enable = FALSE),
  multivariate_prognosis_harmonized = list(
    table_number = 7L,
    # 文件名括号由 locked_multivariable_table_caption() 运行时决定：双库才加
    # (dual-database harmonized covariates)；单库不加。协变量=vif_final_pass。
    defer_until_cox_lock = TRUE
  ),
  multicollinearity = list(vif_threshold_strict = 4, vif_threshold_loose = 10),
  column_mapping = list(enable = TRUE, database_type = "eICU"),
  data_clean = list(missing_threshold = 0.3),

  # KM / RCS / 亚组：time_var/event_var 必须与 survival 一致；strata_vars 由 runner 按指标注入
  rcs_prognosis = list(
    index_var = NULL, nk_range = 3:5, pause_enable = FALSE,
    figure_kind = "main_figure", figure_number = 2L, bump_counter = TRUE
    # x_max / x_min: 可选，裁切 RCS 横轴显示范围（仅显示，不删样本）
    # 按指标配置：config$index_overrides$BAR$rcs_prognosis$x_max <- 40
  ),
  # 发表图号默认（主文 1–4 / 补充 S1–S4）：
  # Fig1 流程 → Fig2 RCS → Fig3 KM → Fig4 亚组森林；
  # S1 boxplot → S2 mediation → S3 ROC（已停产 maxstat Cutoff 图）
  km_strata = list(
    time_var = "futime", event_var = "fustatus", event_value = 1,
    time_divisor = 1, auto_xlim = TRUE, auto_break_time = TRUE,
    id_column = "subject_id",
    figure_number = 3L,
    figure_caption_template = "Kaplan-Meier curves of {index} {method} and mortality in {disease}",
    single_filename_template = NULL, single_use_main_figure = FALSE,
    strata_vars = NULL,
    strata_vars_by_branch = list(extend_quartile = NULL, extend_tertile = NULL),
    strata_defs = list(), export_combined = FALSE,
    font_family = "Times New Roman",
    pause_enable = FALSE, pause_on_no_figures = FALSE
  ),
  km_binary = list(
    time_divisor = 1, auto_xlim = TRUE, auto_break_time = TRUE,
    figure_number = 3L,
    figure_caption_template = "Kaplan-Meier curves of {index} {method} and mortality in {disease}",
    pause_enable = FALSE, pause_on_no_output = FALSE
  ),
  # 分段 Cox 统一走单切点两段：切点 = RCS primary cutoff（勿用分位数外层分段 / maxstat 图）
  # 协变量默认回退 Model2Factors（与 Table 2 双库锁定协变量一致）；不随机搜索、不扫切点
  segmented_cox_binary = list(
    maxstat_fallback = FALSE,
    maxstat_minprop = 0.2,
    cutoff_scan_range = 0,
    cutoff_scan_step = 0.01,
    covariates = NULL,
    random_covariate_search = list(enable = FALSE),
    pause_enable = FALSE,
    pause_on_no_data = FALSE,
    pause_on_no_cutoff = FALSE,
    pause_on_high_stratum_fail = FALSE
  ),
  plot_cutoff = list(
    enable = FALSE,  # 2026-08-21 起停产 maxstat Cutoff 图
    minprop = 0.2, auto_fallback = TRUE,
    annotate_cutoff = "maxstat",
    figure_kind = "supp_figure", figure_number = 1L, bump_counter = FALSE,
    pause_enable = FALSE, pause_on_no_output = FALSE
  ),
  roc_simple = list(
    enable = TRUE, write_cutoff_value = TRUE,
    mode = "multivariable",
    # 判别用完整 VIF 临床集；Table 2 仍可用 Gate C 剪枝短名单
    covariate_source = "vif_final",
    figure_kind = "supp_figure", figure_number = 3L, bump_counter = FALSE,
    figure_width = 8, figure_height = 7, pause_enable = FALSE
  ),
  boxplot = list(
    group_var = NULL,
    response_vars = NULL,
    overall_method = "kruskal.test",
    pairwise_method = "wilcox.test",
    # 预后按 fustatus 分组时默认不显示轴标题「fustatus」
    show_group_axis_title = FALSE,
    group_axis_label = "survival status",
    brewer_palette = "block",
    figure_kind = "supp_figure", figure_number = 1L, bump_counter = FALSE,
    pause_enable = FALSE, pause_if_all_overall_ns = FALSE
  ),
  # 中介路径：默认与 Table 2 / Cox 主表锁定多因素同套
  mediation_policy = list(
    path_use_covariates = TRUE,
    covariate_source = "table2"
  ),
  mediation_prognosis = list(
    exposure = NULL, mediators = NULL,
    bootstrap_iter = 100L,
    auto_covariate_search = FALSE,
    dual_library_lm_screen = TRUE,
    lm_screen_alpha = 0.05,
    lm_screen_require_nonneg_beta = TRUE,
    fallback_single_library_model2 = TRUE,
    mediation_path_alpha = 0.05,
    diagram_enable = TRUE,
    # 双库 Figure S3 必须同一中介（闸门 E：交集内双库 Prop_Med 均值最大）
    dual_db_lock_best_mediator = TRUE,
    dual_db_force_rerun_mediation = TRUE,
    best_mediator = NULL,
    diagram_palette = "matcha",
    diagram_palette_random = FALSE,
    figure_kind = "supp_figure", figure_number = 2L, bump_counter = TRUE,
    # 预后路径图 Y 默认院内死亡/存活状态（勿用 disease 名）
    outcome_label = "In-hospital mortality",
    pause_enable = FALSE
  ),
  subgroup = list(
    min_n = 20,
    # 年龄切点依据：写 config 前查本疾病常用界值；默认二分类（age_subgroup_binary 铁律）
    age_cutoff = 65, export_table = FALSE,
    pause_enable = FALSE,
    level_order = list(
      Age_Group = c("< 65", "\u2265 65")
    )
  ),
  subgroup_prognosis = list(
    figure_kind = "main_figure", figure_number = 4L, bump_counter = TRUE,
    pause_enable = FALSE
  ),
  feature_selection = list(enable = FALSE)
)

# pipeline_* 由 configs/config_survival_dual_batch.R 加载（build.R 负责）
# 勿在本模板内 source survival_dual_batch_build.R
