###############################################################################
#  config_incidence_dual_batch.template.R — 双库发病批量多指标配置模板
#
#  使用步骤:
#    1. 复制本文件到研究产出目录（与 .batch_project_root 一致）:
#       cp configs/templates/config_incidence_dual_batch.template.R \
#          "G:/02block_result/{disease_code}_{disease}/{study_type}_{PMID}/config_incidence_dual_batch.R"
#    2. 按 CONFIG_WORKFLOW 修改下方标有【必改】的键
#    3. 运行:
#       Rscript run_incidence_dual_batch.R \
#         --config "G:/02block_result/.../config_incidence_dual_batch.R"
#
#  【必改键一览】:
#    .batch_project_root   ← 与本文件所在目录完全一致
#    data$rawdata_path / rawdata_obj / id_column（两库各一组）
#    project$disease_code / disease / analysis_group / reference_group
#    dual_db$primary / secondary（路径、对象名、ID 列、列映射类型）
#    nhanes$survey_weight / survey_cluster / survey_strata（若与模板不同）
#
#  【不要改】: pipeline blocks 列表、VIF 阈值、logistic 搜索策略
#
#  source 后产物: config, pipeline_shared_*, pipeline_nhanes_batch, pipeline_regular_batch
#  产出根目录: G:/02block_result/{疾病编码}_{疾病}/{study_type}_{PubMedID}/
#  by_index/<指标>/ 子目录名 = dual_db$primary$name / secondary$name（如 eICU、MIMIC），
#  非写死的 nhanes/mimic；引擎内部槽位仍为 nhanes(主)/mimic(副)。
###############################################################################

# 【必改】将此路径设为本文件所在目录（与运行命令 --config 的 dirname 一致）
.batch_project_root <- "/02block_result/01_Urinary_Incontinence/incidence_38341157"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(

  # ── 数据 ──────────────────────────────────────────────────────────────────
  data = list(
    rawdata_path     = "Data/nhanes/D04_dabiao_OK.RData",
    rawdata_obj      = "dabiao",
    outcome_path     = NULL,
    outcome_column   = "Disease_Group",
    id_column        = "SEQN",
    strip_id_columns_after_imputation = c("SEQN", "subject_id")
  ),

  # ── 项目 ──────────────────────────────────────────────────────────────────
  project = list(
    name                = "UI_dual_batch",
    disease_code        = "01",
    disease             = "Urinary_Incontinence",
    literature_pmid     = "38341157",
    database            = "NHANES",
    database_type       = "nhanes",
    study_type          = "incidence",
    classification_mode = "binary",
    analysis_group      = "Urinary_Incontinence",
    reference_group     = "Continent",
    output_dir          = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root  = TRUE,
    root                = NULL
  ),

  # ── 发表小数位（全项目统一；一般勿改。改后新跑表/图才生效，旧表不自动回刷）──
  # est=OR/HR；p=P 值；desc=均值/SD/%；cutoff=ROC/RCS 切点
  pub_digits = list(est = 3L, p = 3L, desc = 3L, cutoff = 3L, int_big_mark = TRUE),

  # ── 发病（index_var 由 batch runner patch）────────────────────────────────
  incidence = list(
    outcome_var          = "Disease_Group",
    index_var            = NULL,
    index_component_vars = NULL,
    index_exclude_vars   = NULL
  ),

  logistic = list(
    index_var = NULL
  ),

  # ── 复合指标（批量多指标须 enable=TRUE；仅跑单个原生列时可设 FALSE）────────
  index = list(
    enable = TRUE,
    only   = NULL,
    skip   = NULL,
    digits = 4L
  ),

  # 【必改·按疾病】疾病相关变量硬排除；空向量=不跳过疾病衍生指标，但仍建议填写
  # 糖尿病视网膜病变示例: c("T1DM","T2DM","Diabetes","HbA1c","Glucose","Insulin","Antidiabetic_agents")
  analysis_exclusion = list(
    disease_vars = character(0),
    component_scope = "current_transitive",
    exclude_other_composite_indices = TRUE,
    exclude_exposure_if_uses_disease_var = TRUE
  ),

  # ── NHANES 复杂抽样权重 ──────────────────────────────────────────────────
  nhanes = list(
    survey_weight    = "new_Weight",
    survey_cluster   = "SDMVPSU",
    survey_strata    = "SDMVSTRA",
    cutoff_index_var = NULL,
    auto_new_weight  = TRUE,
    exclude_cols     = c(
      "ID", "SEQN", "new_Weight",
      "WTINT2YR", "WTMEC2YR", "WTMEC4YR",
      "WTSAF2YR", "WTSAF4YR", "SDMVPSU", "SDMVSTRA", "Source_File"
    )
  ),

  prediction = list(
    index_vars                          = NULL,
    keep_index_vars_in_regression_table = TRUE
  ),

  plot = list(
    font_family = "Times New Roman"
  ),

  # 强制协变量：默认只 Age；Gender 不强制（需时设 force_sex=TRUE）
  covariate_policy = list(
    force_age = TRUE,
    force_sex = FALSE
  ),

  attrition = list(
    enable = TRUE,
    title = NULL,
    db_label = NULL,
    steps = list(),
    # CONSORT Figure 1：主列纳入、右侧 Exclude、底部分叉（发病=病例/对照；预后=Expired/Alive）
    outcome_breakdown = TRUE,
    auto_append = TRUE,
    draw_pdf = TRUE,
    csv_name = "Flowchart_attrition.csv",
    figure_name = "Figure 1. Inclusion exclusion flowchart.pdf",
    specialty_figure_mode = "skip_if_generic"
  ),

  data_clean = list(
    missing_threshold = 0.3,
    age_filter        = NULL,
    drop_columns      = NULL
  ),

  column_mapping = list(
    enable        = TRUE,
    database_type = "NHANES"
  ),

  imputation = list(
    missing_col_threshold = 0.4,
    method                = "cart",
    m                     = 5L,
    max_iter              = 5L,
    seed                  = 1234L,
    complete_action       = 1L,   # 操作层单套
    rubin_pool            = TRUE, # 推断回归默认 Rubin（m>1）
    export_missing_fig    = FALSE,
    export_table_s1       = TRUE
  ),

  pub_figures = list(
    formats_dir = TRUE,
    dpi = 300L,
    tiff_compression = "lzw",
    write_image_information = TRUE
  ),

  dual_db = list(
    enable            = TRUE,
    mirror_aggregate  = TRUE,
    combine_figures = list(
      enable = TRUE,
      remove_singles = TRUE,
      drop_missing_overview = TRUE,
      panel_order = "primary_first",
      label_format = "A. {db}"
    ),
    checkpoint_base   = .batch_ck_root,
    harmonization_dir = file.path(.batch_ck_root, "_global_harmonization"),
    current_db        = NULL,
    primary = list(
      name                = "NHANES",
      db_type             = "nhanes",
      rawdata_path        = "Data/nhanes/D04_dabiao_OK.RData",
      rawdata_obj         = "dabiao",
      id_column           = "SEQN",
      column_mapping_type = "NHANES"
    ),
    secondary = list(
      name                = "MIMIC",
      db_type             = "regular",
      rawdata_path        = "Data/mimic/D04_dabiao.RData",
      rawdata_obj         = "dabiao",
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
      sync_after_vif_final       = TRUE,
      # auto：优先两库多因素-VIF 交集；空则两边一起退回单因素-VIF（禁止混用）
      covariate_source           = "auto",
      sync_logistic_branch       = TRUE,
      subgroup_var_aliases = list(
        Gender  = c("Gender", "Sex"),
        Smoking = c("Smoking", "Smoke"),
        Smoke   = c("Smoking", "Smoke")
      )
    )
  ),

  # ── 飞书结果管理表 ────────────────────────────────────────────────────────
  feishu = list(
    enable             = TRUE,
    app_id             = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret         = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token          = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id           = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    literature_default = "NHANES + MIMIC 发病双库（01 Urinary_Incontinence, PMID 38341157）",
    project_id         = "01_incidence_38341157",
    owner_default      = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    disease_label  = "YOUR_DISEASE",
    protocol_label = "YOUR_PROTOCOL",
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", "")
  ),

  # ── 批量控制 ──────────────────────────────────────────────────────────────
  incidence_batch = list(
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
      "ID", "SEQN", "subject_id",
      "new_Weight",
      "WTINT2YR", "WTMEC2YR", "WTMEC4YR",
      "WTSAF2YR", "WTSAF4YR", "SDMVPSU", "SDMVSTRA", "Source_File"
    ),
    extra_index_exclude_vars = character(0),
    index_component_overrides = list(
      OAScore_z = c("Age", "HbA1c", "Total_Cholesterol")
    ),
    base_subgroup_vars = c("Age", "Gender", "Race", "Smoking", "Hypertension", "Diabetes"),

    # ── 敏感性分析（主分析 success 后自动执行；亦可 --sensitivity-only 单独补跑）──
    # Yes/No 从两库 Table 1 动态生成（两库 Yes n>50）；年龄分层用 age_cutoff。
    # complete_case=TRUE（默认）：插补前 mapped/cleaned 对暴露+结局+锁定 Model1/2 listwise。
    # 忽略旧课题残留的 scenarios；勿在此手写四场。
    sensitivity_suite = list(
      enable         = TRUE,
      age_cutoff     = 65L,
      min_n_per_db   = 50L,
      min_yes_n      = 50L,
      complete_case  = TRUE
    ),

    # ── 失败指标亚组补救重跑（详见 R/incidence_subgroup_fallback.R）──────────────
    #  某指标在主批量流程失败后，按以下亚组把人群剔除一部分，重跑整个双库发病流程。
    #  触发：主批量跑完后自动对本批 failed/error 指标执行（enable=TRUE）；
    #        也可手动：Rscript run_incidence_dual_batch.R --subgroup-fallback-only [IX1,IX2]
    #  产物：by_index/【failed】<ix>/<Label>/ → 打标 【success】/【failed】<Label>；
    #        父目录改名 【failed_subgr_<succ>_succ】<ix>（成功）/【failed_subgr_allfail】<ix>。
    subgroup_fallback = list(
      enable             = TRUE,     # 失败后自动补救（缺省/缺失块按 FALSE 处理）
      try_all            = TRUE,     # TRUE=所有亚组都跑、分别报告；FALSE=首个成功即停
      min_n_per_subgroup = 30L,      # 过滤后某库可分析样本 < 该值 → 该库跳过该亚组
      sep                = "|",      # 多个亚组成功时父目录名的分隔符
      # —— 取数口径接口 ——
      age_cutoff         = 65L,      # 老年切点，驱动 Age_{age_cutoff} / Age_{age_mid_lower}_{age_cutoff}
      age_mid_lower      = 45L,      # 中年段下界
      obesity_standard   = "chinese",# "chinese"(BMI>=28) | "western"(BMI>=30)，驱动 Obesity_BMI{obesity_cut}
      # —— 启用亚组（顺序即尝试顺序；某库缺所需列则该库静默跳过，两库均缺则跳过该亚组）——
      #  占位符 {age_cutoff} {age_mid_lower} {obesity_cut} 由上方接口值替换；label 与 expr 同步替换。
      subgroups = list(
        list(label = "Age_{age_cutoff}",                  expr = "Age >= {age_cutoff}"),
        list(label = "Age_{age_mid_lower}_{age_cutoff}",  expr = "Age >= {age_mid_lower} & Age < {age_cutoff}"),
        list(label = "Hypertension",                      expr = 'Hypertension == "Yes"'),
        list(label = "Diabetes",                          expr = 'Diabetes == "Yes"'),
        list(label = "Obesity_BMI{obesity_cut}",          expr = "BMI >= {obesity_cut}"),
        list(label = "Male",                              expr = 'Gender == "Male"'),       # 当前 dabiao 无 Gender 列 → 自动跳过
        list(label = "Female",                            expr = 'Gender == "Female"'),     # 同上
        list(label = "Non_smoker",                        expr = 'Smoke == "never"'),
        list(label = "Smoker",                            expr = 'Smoke %in% c("current", "former")')
        # 备选（列已存在，按需启用）：
        # list(label = "CKD",           expr = 'CKD == "Yes"'),
        # list(label = "Heart_Failure", expr = 'Heart_Failure == "Yes"'),
        # list(label = "COPD",          expr = 'COPD == "Yes"')
      )
    )
  ),

  # ── NHANES 块 ─────────────────────────────────────────────────────────────
  baseline_nhanes = list(
    sig_cutoff                   = 0.05,
    pause_enable                 = FALSE,
    pause_on_weighted_table_fail = FALSE,
    pause_on_min_sig_vars        = FALSE,
    pause_min_sig_vars           = 3L,
    early_stop_if_index_ns       = FALSE
  ),

  boxplot = list(
    group_var               = "Disease_Group",
    response_vars           = NULL,
    overall_method          = "kruskal.test",
    pairwise_method         = "wilcox.test",
    pause_enable            = FALSE,
    pause_if_all_overall_ns = FALSE
  ),

  univariate_nhanes = list(
    sig_cutoff            = 0.05,
    screening_cutoff      = 0.1,
    excluded_predictors   = NULL,
    pause_enable          = FALSE,
    pause_on_min_sig_vars = FALSE,
    pause_min_sig_vars    = 3L
  ),

  multivariate_nhanes = list(
    sig_cutoff              = 0.05,
    input_from              = "vif_screen_pass",
    excluded_predictors     = NULL,
    demo_keywords           = c("Age", "Gender", "Race", "Smoking", "Education", "Income"),
    model1_candidate_names  = c("Age", "Gender", "Race"),
    pause_enable            = FALSE,
    pause_on_min_sig_vars   = FALSE,
    pause_min_sig_vars      = 3L
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
      table_title = "Weighted Multicollinearity Analysis (VIF, univariate p<0.1 screen, NHANES)",
      csv_name    = "VIF_check_screen_weighted.csv"
    ),
    final = list(
      table_title = "Weighted Multicollinearity Analysis (VIF, multivariate p<0.05, NHANES)",
      csv_name    = "VIF_check_final_weighted.csv"
    )
  ),

  logistic_nhanes_weighted = list(
    cascade = list(
      crude_p_threshold = 0.05,
      crude_sig_method  = "trend_or_any_group"
    ),
    covariate_source = "vif_final_pass",
    demo_factor_names = c(
      "Age", "Gender", "Race", "Smoking", "Education", "Income", "Marital_Status"
    ),
    clinical_factor_names = c(
      "HDL", "Hypertension", "Diabetes", "Lipid_lowering_agents",
      "Hyperlipidemia", "Heart_Failure", "CKD", "COPD"
    ),
    exclude_from_models = NULL,
    random_search = list(
      enable                   = FALSE,
      max_attempts             = 100L,
      max_inner_attempts       = 20L,
      initial_sample_n         = 1L,
      p_threshold              = NULL,
      require_highest_group_or_gt1 = FALSE,
      require_all_six_p        = FALSE,
      pause_on_search_fail     = FALSE,
      require_triple_model_sig = TRUE,
      m1_to_m2_fallback        = TRUE
    ),
    model1_factors = NULL,
    model2_factors = NULL
  ),

  # Model3 = Model2 + 课题学术必调；空则不上 Model3。禁止写入 disease_vars / 指标组分。
  # 不显著则下游全调整回退 Model2。闸门仍只看 Crude/Model1/Model2。
  analysis_models = list(
    model3_required_factors = character(0)
  ),

  logistic_quartile_nhanes_weighted = list(
    index_var = NULL, include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_all_ns = FALSE,
    extend_branch = "extend_quartile", degrade_branch = "degrade_tertile",
    p_threshold = 0.05, phase = "screen", pause_enable = FALSE,
    pause_on_missing_design = TRUE
  ),
  logistic_tertile_nhanes_weighted = list(
    index_var = NULL, include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_all_ns = FALSE,
    extend_branch = "extend_tertile", degrade_branch = "degrade_binary",
    p_threshold = 0.05, phase = "screen", pause_enable = FALSE,
    pause_on_missing_design = TRUE
  ),
  logistic_binary_nhanes_weighted = list(
    index_var = NULL, include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_highest_ns = TRUE,
    extend_branch = "extend_binary", degrade_branch = character(0),
    p_threshold = 0.05, phase = "screen", pause_enable = FALSE,
    pause_on_missing_design = TRUE
  ),

  rcs_nhanes = list(
    index_var = NULL, max_model1_vars = 4L,
    knot_quantiles = c(0.1, 0.5, 0.9), histper = 25L,
    plot_x_quantiles = c(0.01, 0.99),
    group_cutoffs = "primary"   # Table S-XX 只用主 cutoff 二分
  ),

  subgroup = list(
    min_n = 20,
    # 年龄切点依据：写 config 前查本疾病常用界值；默认二分类（见 age_subgroup_binary 铁律）
    age_cutoff = 65L,
    # 双库亚组必须一致（见 dual_db_subgroup_consistency 铁律）
    var_source = "required",
    required_subgroup_vars = NULL,  # 课题填写；或由 Gate D / force_subgroup_vars 注入
    # 发表铁律（引擎默认）：亚组森林图 = 全部人群估计，各层报告「最高 vs 最低」分位对比，
    # 分位跟随主文锁定方案（subgroup_resolve_main_scheme：tertile/quartile），与 Table 2 同分母。
    # full_stratum（默认）= OR 与 N 都用全分析集；model_sample 才回退旧「仅 Q1+Q4 子集」口径。
    continuous_index_mode = "highest_vs_lowest",
    forest_n_source = "full_stratum",
    forbid_subgroup_vars = c(
      "Index_Group", "Index_Group_Tertile", "Index_Group_Quartile", "MCV_RCS_Group",
      # 双库类型常不一致（Yes/No vs 连续通气小时），默认不进亚组森林
      "Ventilation", "Ventilation_Hour"
    ),
    forest_xlim = c(0.2, 4),
    forest_xlim_max = 80,   # 默认 80；旧默认 10 会把 OR>10 的亚组点裁出画布
    level_order = list(
      Age_Group = c("< 65", "\u2265 65")
    )
  ),

  # 中介路径：默认与 Table 2 锁定多因素同套（mediation_policy$covariate_source = table2）
  mediation_policy = list(
    path_use_covariates = TRUE,
    covariate_source = "table2"
  ),

  mediation_nhanes_weighted = list(
    exposure = NULL, lab_indicator_vars = NULL, mediators = NULL, covariates = NULL,
    bootstrap_iter = 100L, standardize_mediator = FALSE,
    dual_library_lm_screen = TRUE, lm_screen_alpha = 0.05,
    lm_screen_require_nonneg_beta = TRUE,
    fallback_single_library_model2 = TRUE, auto_covariate_search = FALSE,
    # 与 CHARLS mediation_incidence 共用 .mi02_resolve_lab_indicator_pool
    mediator_extra_vars = NULL,
    path_use_covariates = TRUE,
    mediation_path_alpha = 0.05, diagram_enable = TRUE, pause_enable = FALSE
  ),

  # ── MIMIC / 普通库块 ───────────────────────────────────────────────────────
  roc_simple = list(
    enable = TRUE,
    mode = "multivariable",
    covariate_source = "locked",
    model_engine = "glm",   # glm | rpart | glmnet | xgboost（判别专用，不影响 Table 2）
    export_table = FALSE,
    write_cutoff_value = FALSE,
    figure_kind = "supp_figure",
    figure_number = 2L,
    bump_counter = TRUE,
    figure_width = 8, figure_height = 7
  ),

  cutoff = list(
    export_roc_figure = FALSE
  ),

  baseline_binary = list(
    sig_cutoff = 0.05, strata = "Disease_Group",
    include_vars = NULL,
    exclude_vars = c(
      "SEQN", "subject_id", "new_Weight",
      "WTINT2YR", "WTMEC2YR", "WTMEC4YR",
      "WTSAF2YR", "WTSAF4YR", "SDMVPSU", "SDMVSTRA", "Source_File"
    ),
    pause_enable = FALSE, pause_on_table1_fail = FALSE,
    pause_on_min_sig_vars = FALSE, pause_min_sig_vars = 3L,
    early_stop_if_index_ns = FALSE
  ),

  univariate_incidence_binary = list(
    sig_cutoff = 0.05, screening_cutoff = 0.1,
    excluded_predictors = NULL,
    required_predictors = character(0),
    include_predictors = NULL,
    demo_keywords = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital", "marriage",
      "Income", "PIR", "poverty", "Smoking", "Smoke",
      "Insurance", "Language", "Alcohol"
    ),
    index_transform = "none",
    pause_enable = FALSE, pause_on_min_sig_vars = FALSE
  ),

  multivariate_incidence_binary = list(
    sig_cutoff = 0.05, input_from = "vif_screen_pass", write_model_factors = TRUE,
    excluded_predictors = NULL,
    required_predictors = character(0),
    include_predictors = NULL,
    demo_keywords = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital", "marriage",
      "Income", "PIR", "poverty", "Smoking", "Smoke",
      "Insurance", "Language", "Alcohol"
    ),
    pause_enable = FALSE, pause_on_min_sig_vars = FALSE
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
    pause_enable = FALSE, pause_on_search_fail = FALSE
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
    pause_enable = FALSE, pause_on_search_fail = FALSE
  ),
  logistic_binary_glm = list(
    index_var = NULL, include_continuous_row = TRUE,
    gate_enable = TRUE, stop_if_crude_highest_ns = TRUE,
    extend_branch = "extend_binary", degrade_branch = character(0),
    p_threshold = 0.05, phase = "screen",
    random_search = list(
      max_outer_attempts = 100L, max_inner_attempts = 10L,
      initial_factors_n = 1L, p_threshold = 0.05, seed = NULL,
      require_triple_model_sig = TRUE, m1_to_m2_fallback = TRUE
    ),
    pause_enable = FALSE, pause_on_search_fail = FALSE
  ),

  rcs_incidence = list(
    index_var = NULL, nk_range = 3:5, histbin = 1, color_seed = 123,
    # primary=主 cutoff→2 组（Table S-XX）；all=全部交点（仅诊断，不进汇总）
    group_cutoffs = "primary"
  ),

  mediation_incidence = list(
    exposure = NULL, mediators = NULL, outcome = NULL,
    bootstrap_iter = 100L, auto_covariate_search = FALSE,
    dual_library_lm_screen = TRUE,
    # S8 候选池由引擎 .mi02_resolve_lab_indicator_pool 决定（血检+mediator_extra_vars+best_mediator）
    # lm_screen_exclude_vars 只作额外黑名单，不能再靠它从「全列」里抠实验室指标
    lab_indicator_vars = NULL,
    mediator_extra_vars = NULL,
    lm_screen_exclude_vars = c(
      "ID", "subject_id", "Group", "Disease", "Disease_Group",
      "Age", "Gender", "Education", "Smoke", "Hemoglobin",
      "Hypertension", "Diabetes"
    ),
    diagram_enable = TRUE, pause_enable = FALSE
  ),

  feature_selection = list(enable = FALSE)
)

# ── 共享层流水线（每库 1 次）───────────────────────────────────────────────
pipeline_shared_nhanes <- list(
  name   = "mcv_ui_dual_batch_shared_nhanes",
  blocks = c("data_clean", "column_mapping", "dual_db_column_harmonize", "index"),
  logistic_gate = list(enable = FALSE),
  render_tables_after  = character(0),
  render_figures_after = character(0),
  dual_db    = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    # 运行时由 incidence_batch_shared_ck_canonical_dir 覆盖为 dual_db$primary$name
    dir    = file.path(.batch_ck_root, "_shared", "nhanes")
  )
)

pipeline_shared_regular <- list(
  name   = "mcv_ui_dual_batch_shared_mimic",
  blocks = c("data_clean", "column_mapping", "dual_db_column_harmonize", "index"),
  logistic_gate = list(enable = FALSE),
  render_tables_after  = character(0),
  render_figures_after = character(0),
  dual_db    = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    # 运行时由 incidence_batch_shared_ck_canonical_dir 覆盖为 dual_db$secondary$name
    dir    = file.path(.batch_ck_root, "_shared", "mimic")
  )
)

# ── 每指标 NHANES 分析流水线 ────────────────────────────────────────────────
pipeline_nhanes_batch <- list(
  name = "mcv_ui_dual_batch_nhanes",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "index",
    "analysis_exclusion",
    # 发病套路不修剪指标极端值（不挂 trim_index_extreme）
    "imputation",
    "cutoff", "obj", "baseline_nhanes", "boxplot",
    "univariate_nhanes", "multicollinearity_nhanes_screen",
    "multivariate_nhanes", "multivariate_covariate_resolve", "multicollinearity_nhanes_final",
    "dual_db_covariate_harmonize",
    "multivariate_nhanes_harmonized",
    "simple_ROC",
    "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted",
    "dual_db_logistic_scheme_harmonize", "dual_db_logistic_main_table_realign",
    "rcs_nhanes",
    "logistic_quartile_nhanes_weighted_rcs", "logistic_tertile_nhanes_weighted_rcs",
    "logistic_binary_nhanes_weighted_rcs",
    "subgroup_nhanes_weighted", "mediation_nhanes_weighted",
    "baseline_binary", "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "attrition_flowchart"
  ),
  logistic_gate = list(enable = TRUE, weighted = TRUE),
  render_tables_after = c(
    "analysis_exclusion",
    "imputation",
    "baseline_nhanes", "univariate_nhanes",
    "multicollinearity_nhanes_screen", "multivariate_nhanes",
    "multivariate_covariate_resolve", "multicollinearity_nhanes_final",
    "dual_db_covariate_harmonize",
    "multivariate_nhanes_harmonized",
    "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted",
    "dual_db_logistic_scheme_harmonize", "dual_db_logistic_main_table_realign",
    "rcs_nhanes",
    "logistic_quartile_nhanes_weighted_rcs", "logistic_tertile_nhanes_weighted_rcs",
    "logistic_binary_nhanes_weighted_rcs",
    "subgroup_nhanes_weighted", "mediation_nhanes_weighted",
    "baseline_binary", "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "attrition_flowchart"
  ),
  render_figures_after = c(
    "cutoff", "boxplot", "simple_ROC", "rcs_nhanes", "subgroup_nhanes_weighted",
    "mediation_nhanes_weighted"
  ),
  dual_db    = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

# ── 每指标 MIMIC 分析流水线 ─────────────────────────────────────────────────
pipeline_regular_batch <- list(
  name = "mcv_ui_dual_batch_mimic",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "index",
    "analysis_exclusion",
    # 发病套路不修剪指标极端值（不挂 trim_index_extreme）
    "imputation",
    "baseline_binary", "boxplot",
    "univariate_incidence_binary", "multicollinearity_screen",
    "multivariate_incidence_binary", "multivariate_covariate_resolve", "multicollinearity_final",
    "dual_db_covariate_harmonize",
    "multivariate_incidence_harmonized",
    "simple_ROC",
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "dual_db_logistic_scheme_harmonize", "dual_db_logistic_main_table_realign",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
    "subgroup_incidence", "mediation_incidence",
    "attrition_flowchart"
  ),
  logistic_gate = list(enable = TRUE),
  render_tables_after = c(
    "analysis_exclusion",
    "imputation",
    "baseline_binary", "boxplot",
    "univariate_incidence_binary", "multicollinearity_screen",
    "multivariate_incidence_binary", "multivariate_covariate_resolve", "multicollinearity_final",
    "dual_db_covariate_harmonize",
    "multivariate_incidence_harmonized",
    "simple_ROC",
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "dual_db_logistic_scheme_harmonize", "dual_db_logistic_main_table_realign",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
    "subgroup_incidence", "mediation_incidence",
    "attrition_flowchart"
  ),
  render_figures_after = c(
    "simple_ROC", "boxplot", "rcs_incidence", "subgroup_incidence"
  ),
  dual_db    = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline <- pipeline_nhanes_batch
