###############################################################################
#  config_association_nhanes.template.R — NHANES 加权【横断面关联】通用模板
#  源自 paper_003（CMI × 抑郁，NHANES 2011–2014）抽取：
#    多重插补 → 基线 → 加权 logistic（连续 + tertile）→ RCS 非线性 → 拐点三分段
#    → 亚组 + 交互。无随访时间（横断面），无中介分析。
#  source 后得到: config, pipeline
#  用法: 由 run_association_nhanes.R 加载
#
#  ⚠️ 这是【研究型通用模板】，含占位符；论文级可运行实例须经 wizard 交互门：
#     数据探查（读 Data/）→ 决策树确认 → 试跑确认，再回填下方 ❓ 占位符。
#  ⚠️ study_type 沿用 "incidence" 以复用 NHANES block 变体；语义实为
#     cross-sectional association（库内暂无独立 association 变体，见 block_gap 报告）。
#  ⚠️ GAP1 roc_multi_indicator / GAP2 logistic_external_cutoff 尚未在 Blocks/ 实现，
#     下方以 TODO 注释占位，建成并注册前不得放入 pipeline$blocks。
###############################################################################

config <- list(
  data = list(
    rawdata_path     = "Data/nhanes/<TO_CONFIRM>.RData",          # ❓ 待 wizard 确认
    rawdata_obj      = "<TO_CONFIRM>",                            # ❓ 待 wizard 确认
    outcome_path     = NULL,
    outcome_column   = "<Depression_Binary>",                     # ❓ 抑郁二分结局列名
    id_column        = "SEQN",
    strip_id_columns_after_imputation = c("SEQN")
  ),

  project = list(
    name                = "association_nhanes",
    disease             = "<Depression>",                          # ❓ 待确认
    database            = "NHANES",
    study_type          = "incidence",                             # 语义=横断面关联（见上注）
    classification_mode = "binary",
    analysis_group      = "<Depression>",                          # ❓ 病例组标签
    reference_group     = "<No_Depression>",                       # ❓ 对照组标签
    output_dir          = "Output/<TO_CONFIRM>",                   # ❓ 待确认
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root = TRUE                              # ❓ 须 wizard 确认 TRUE/FALSE
  ),

  incidence = list(     # 沿用 incidence 槽位以对齐 NHANES 变体；index_var=主暴露
    outcome_var = "<Depression_Binary>",                           # ❓
    index_var   = "<CMI>"                                           # ❓ 主暴露指标列名
  ),

  logistic = list(
    index_var = "<CMI>"                                             # ❓
  ),

  nhanes = list(
    survey_weight    = "WTMEC2YR",
    survey_cluster   = "SDMVPSU",
    survey_strata    = "SDMVSTRA",
    cutoff_index_var = "<CMI>",                                     # ❓
    exclude_cols     = c(
      "ID", "SEQN", "WTINT2YR", "WTMEC2YR", "SDMVPSU", "SDMVSTRA", "Source_File"
    )
  ),

  prediction = list(
    index_vars                          = c("<CMI>"),               # ❓
    keep_index_vars_in_regression_table = TRUE
  ),

  plot = list(
    font_family = "Times New Roman"
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
    missing_col_threshold = 0.2,
    method                = "cart",
    m                     = 5L,
    max_iter              = 5L,
    seed                  = 1234L,
    complete_action       = 1L,
    export_missing_fig    = TRUE,
    export_table_s1       = TRUE
  ),

  baseline_nhanes = list(
    sig_cutoff                  = 0.05,
    pause_enable                = TRUE,
    pause_on_weighted_table_fail = TRUE,
    pause_on_min_sig_vars       = FALSE,
    pause_min_sig_vars          = 3L
  ),

  boxplot = list(
    group_var               = "<Depression_Binary>",               # ❓
    response_vars           = c("<CMI>"),                           # ❓
    overall_method          = "kruskal.test",
    pairwise_method         = "wilcox.test",
    pause_enable            = FALSE,
    pause_if_all_overall_ns = FALSE
  ),

  # 论文直接用固定协变量全模型（未做单因素→VIF→多因素逐步筛选）。
  # 以下两组可关停；若保留作校验，需确认 sig_cutoff / input_from 行为。
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
    model1_candidate_names  = c("Age", "Gender", "Race"),
    pause_enable            = FALSE,
    pause_on_min_sig_vars   = FALSE,
    pause_min_sig_vars      = 3L
  ),

  multicollinearity = list(
    vif_threshold_strict     = 4,
    vif_threshold_loose      = 10,
    vif_threshold_hard_drop  = 50,
    min_vars_threshold       = 0,
    exclude_vars             = c("ID", "SEQN"),
    vif_design_extra_predictors = character(0),
    vif_append_extra_to_model2_outputs = FALSE,
    export_full_vif_table    = TRUE,
    screen = list(
      table_title = "Weighted Multicollinearity Analysis (VIF screen, NHANES)",
      csv_name    = "VIF_check_screen_weighted.csv"
    ),
    final = list(
      table_title = "Weighted Multicollinearity Analysis (VIF final, NHANES)",
      csv_name    = "VIF_check_final_weighted.csv"
    )
  ),

  # 主分析：加权 logistic_gate（连续行 + tertile），对齐 Model1=人口学 / Model2=全调整
  logistic_nhanes_weighted = list(
    cascade = list(
      crude_p_threshold = 0.05,
      crude_sig_method  = "trend_or_any_group"
    ),
    covariate_source = "vif_final_pass",
    demo_factor_names = c("Age", "Gender", "Race", "Education", "Income", "Marital_Status", "Smoke", "Alcohol"),
    clinical_factor_names = c("HDL", "Hypertension", "Diabetes", "Hyperlipidemia", "CVD", "CKD"),
    exclude_from_models = c("ID", "SEQN"),
    random_search = list(
      enable                 = TRUE,
      max_attempts           = 1000L,
      max_inner_attempts     = 1000L,
      initial_sample_n       = 1L,
      p_threshold            = NULL,
      require_highest_group_or_gt1 = FALSE,
      require_all_six_p      = FALSE,
      pause_on_search_fail   = FALSE
    ),
    model1_factors = NULL,
    model2_factors = NULL
  ),

  logistic_tertile_nhanes_weighted = list(
    index_var              = "<CMI>",                              # ❓
    include_continuous_row = TRUE,
    gate_enable            = TRUE,
    stop_if_crude_all_ns   = FALSE,
    extend_branch          = "extend_tertile",
    degrade_branch         = "degrade_binary",
    p_threshold            = 0.05,
    phase                  = "screen",
    pause_enable           = FALSE,
    pause_on_missing_design = TRUE
  ),

  logistic_binary_nhanes_weighted = list(
    index_var              = "<CMI>",                              # ❓
    include_continuous_row = TRUE,
    gate_enable            = TRUE,
    stop_if_crude_highest_ns = TRUE,
    extend_branch          = "extend_binary",
    degrade_branch         = character(0),
    p_threshold            = 0.05,
    phase                  = "screen",
    pause_enable           = FALSE,
    pause_on_missing_design = TRUE
  ),

  rcs_nhanes = list(
    index_var       = "<CMI>",                                     # ❓
    max_model1_vars = 4L,
    knot_quantiles  = c(0.1, 0.5, 0.9),   # 3 结点 → 至多 2 拐点（对齐论文 0.9522 / 1.58）
    histper         = 25L
  ),

  subgroup = list(
    min_n                  = 20,
    # 年龄切点依据：写 config 前查本疾病常用界值；默认二分类（age_subgroup_binary 铁律）
    age_cutoff             = 65L,
    required_subgroup_vars = c("Age", "Gender", "Race", "BMI", "Smoke", "Alcohol",
                               "Hypertension", "Diabetes"),
    forest_xlim            = c(0, 4),
    level_order = list(
      Age_Group = c("< 65", "\u2265 65")
    )
  ),

  feature_selection = list(enable = FALSE)

  # ── GAP1（缺失）：多指标 ROC 对比（CMI/VAI/LAP/TyG 同图 + AUC 表）──────────
  # roc_multi_indicator = list(index_vars = c("<CMI>","<VAI>","<LAP>","<TyG>"))
  #   现有 ROC 块仅画 ML 模型；cutoff 块仅单指标 Youden；均不支持多指标叠加。
  #   须先在 Blocks/13_roc/ 新建并在 pipeline_runner.R 注册，方可启用。

  # ── GAP2（缺失）：外部文献界值二分敏感分析（Wakabayashi 性别特异 CMI 界值）──
  # logistic_external_cutoff_nhanes_weighted = list(
  #   index_var = "<CMI>",
  #   cutoff_by_sex = list(female = c(0.799, 0.800), male = c(1.625, 1.748)),
  #   include_continuous_row = TRUE
  # )
  #   现有 cutoff 块为数据驱动 Youden，非应用外部文献界值；须新建并注册。
)

pipeline <- list(
  name   = "association_nhanes_cross_sectional",
  blocks = c(
    "data_clean",
    "column_mapping",
    "imputation",
    "cutoff",
    "obj",
    "baseline_nhanes",
    "boxplot",
    # "univariate_nhanes",          # 可选：论文未做逐步筛选，按需启用
    # "multicollinearity_nhanes_screen",
    # "multivariate_nhanes",
    # "multicollinearity_nhanes_final",
    "logistic_binary_nhanes_weighted",
    "logistic_tertile_nhanes_weighted",
    # "roc_multi_indicator",         # GAP1 未实现：注释占位
    "rcs_nhanes",
    "logistic_binary_nhanes_weighted_rcs",
    "logistic_tertile_nhanes_weighted_rcs",
    # "logistic_external_cutoff_nhanes_weighted",  # GAP2 未实现：注释占位
    "subgroup_nhanes_weighted"
    # 注：横断面关联，无 mediation_nhanes_weighted
  ),
  logistic_gate = list(
    enable   = TRUE,
    weighted = TRUE
  ),
  render_tables_after = c(
    "imputation", "baseline_nhanes",
    "logistic_binary_nhanes_weighted", "logistic_tertile_nhanes_weighted",
    "rcs_nhanes",
    "logistic_binary_nhanes_weighted_rcs", "logistic_tertile_nhanes_weighted_rcs",
    "subgroup_nhanes_weighted"
  ),
  render_figures_after = c(
    "imputation", "cutoff", "boxplot",
    "rcs_nhanes", "subgroup_nhanes_weighted"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    dir    = "checkpoints/<TO_CONFIRM>"                            # ❓ 待确认
  )
)
