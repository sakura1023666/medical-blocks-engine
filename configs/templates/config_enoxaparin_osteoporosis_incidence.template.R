###############################################################################
#  config_enoxaparin_osteoporosis_incidence.template.R
#  Liu et al. J Transl Med 2026;24:663 — 依诺肝素暴露 × 新发骨质疏松（临床发病地基）
#
#  使用步骤:
#    1. 先跑课题壳 ingest:
#         Rscript run/enoxaparin_osteoporosis_incidence/blocks_shell/01_ingest_analysis_cohort.R
#    2. 复制本文件到研究目录，改【必改】路径
#    3. Rscript run/incidence/run_incidence_single.R --config "<your_config>"
#
#  设计要点（相对 config_incidence_single）:
#    - 先验锁定 Model1–4（跳过 UV/VIF 选模与分位 gate）
#    - 固定切点四分位 duration_q；连续暴露 exposure_days_per10
#    - 中介锁定 avg_admin_per_day + daily_avg_dose
#    - 方案 B：主表允许 BMI 缺失并由 imputation 填补
#
#  gap 登记: adversarial_lit_reading/rounds/block_gap_liu2026_enoxaparin_osteoporosis_manual.md
#  决策树: Decisiontree/decision_tree_enoxaparin_op_incidence.md
###############################################################################

config <- list(
  data = list(
    # 【必改】ingest 产出的 RData
    rawdata_path     = "/mnt/g/02block_result/66_linchuangshengxin/Clinical_Bio_41947218/AnalysisData/Enoxaparin_OP.RData",
    rawdata_obj      = "Enoxaparin_OP",
    outcome_path     = NULL,
    outcome_column   = "Disease",
    id_column        = "ID",
    strip_id_columns_after_imputation = c("ID", "subject_id", "index_hadm_id")
  ),

  project = list(
    name                = "Enoxaparin_Osteoporosis",
    disease             = "Osteoporosis",
    database            = "MIMIC-IV",
    study_type          = "incidence",
    classification_mode = "binary",
    analysis_group      = "Osteoporosis",
    reference_group     = "Non_Osteoporosis",
    # 【必改】
    output_dir          = "/mnt/g/02block_result/66_linchuangshengxin/Clinical_Bio_41947218/Output/enoxaparin_op_incidence",
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root = TRUE
  ),

  incidence = list(
    outcome_var = "Disease",
    index_var   = "exposure_days_per10"
  ),

  logistic = list(
    index_var = "exposure_days_per10"
  ),

  # 文献 Model4 = Model3 + 剂量强度；引擎 Model3 = Model2 + required
  analysis_models = list(
    model3_required_factors = c("avg_admin_per_day", "daily_avg_dose"),
    model3_show_when_insignificant = TRUE
  ),

  # 回归用数值共病列（ingest 写入 *_num）；人口学用规范名
  logistic_covariates = list(
    model1_factors = c("Age", "Gender", "Race", "BMI"),
    model2_factors = c(
      "Age", "Gender", "Race", "BMI",
      "DVT_num", "CKD_num", "Malignancy_num", "Glucocorticoid_num"
    ),
    random_search = list(enable = FALSE)
  ),

  prediction = list(
    index_vars                          = c("exposure_days_per10"),
    keep_index_vars_in_regression_table = TRUE
  ),

  plot = list(
    font_family = "Times New Roman"
  ),

  attrition = list(
    enable = TRUE,
    title = "Enoxaparin exposure and incident osteoporosis (MIMIC-IV)",
    db_label = "MIMIC-IV",
    steps = list(
      list(id = "start", label = "Enoxaparin exposure pool",
           source = "fixed", n = 38306L),
      list(id = "age18", label = "Age >= 18 at index",
           source = "fixed", n = 38306L),
      list(id = "exposure", label = "Exposure days > 0",
           source = "fixed", n = 38306L),
      list(id = "no_prior_op", label = "No prior osteoporosis (disch < index)",
           source = "fixed", n = 37219L,
           exclude_label = "Prior osteoporosis"),
      list(id = "main_B", label = "Analytic cohort Scheme B (BMI missing allowed)",
           source = "fixed", n = 37219L)
    ),
    auto_append = FALSE,
    config_steps_only = TRUE,
    outcome_breakdown = TRUE,
    draw_pdf = TRUE,
    csv_name = "Flowchart_attrition.csv",
    figure_name = "Figure 1. Inclusion exclusion flowchart.pdf",
    specialty_figure_mode = "skip_if_generic"
  ),

  data_clean = list(
    missing_threshold = 0.5,
    age_filter        = NULL,
    # 泄漏 / 非分析列
    drop_columns      = c(
      "osteoporosis", "osteoporosis_sa7", "op_pre_index",
      "index_datetime", "index_date", "analysis_set",
      "dvt", "ckd", "malignancy", "glucocorticoid_systemic",
      "dvt_ever", "ckd_ever", "malignancy_ever",
      "bmi_missing", "exposure_days_index_hadm"
    )
  ),

  column_mapping = list(
    enable        = FALSE,
    database_type = "MIMIC"
  ),

  analysis_exclusion = list(
    enable = TRUE,
    # 本表无 BMD/T-score 等 OP 标志物；原始结局码已在 data_clean$drop_columns
    disease_vars = character(0),
    # 暴露编码与中介/亚组列必须保留在数据中（禁止被误删）
    protect_vars = c(
      "duration_q", "long_term_label", "long_term_ge30",
      "exposure_days", "exposure_days_per10",
      "n_admin", "cum_dose_mg", "avg_admin_per_day", "daily_avg_dose",
      "DVT", "CKD", "Malignancy", "Glucocorticoid",
      "DVT_num", "CKD_num", "Malignancy_num", "Glucocorticoid_num",
      "Age_Group", "BMI_Group", "Race", "Gender", "Age", "BMI",
      "Disease_SA7"
    )
  ),

  imputation = list(
    missing_col_threshold = 0.4,
    method                = "cart",
    m                     = 5L,
    max_iter              = 5L,
    seed                  = 20261127L,
    complete_action       = 1L,
    rubin_pool            = TRUE,
    export_missing_fig    = TRUE,
    export_table_s1       = TRUE
  ),

  baseline_binary = list(
    sig_cutoff            = 0.05,
    strata                = "Disease",
    include_vars          = c(
      "Age", "Gender", "Race", "BMI",
      "DVT", "CKD", "Malignancy", "Glucocorticoid",
      "exposure_days", "n_admin", "cum_dose_mg",
      "avg_admin_per_day", "daily_avg_dose", "long_term_label"
    ),
    exclude_vars          = c("ID", "index_hadm_id"),
    pause_enable          = FALSE,
    pause_on_table1_fail  = FALSE,
    pause_on_min_sig_vars = FALSE
  ),

  boxplot = list(
    group_var            = "Disease",
    response_vars        = c("exposure_days_per10", "exposure_days"),
    exposure_only        = TRUE,
    overall_method       = "wilcox.test",
    pairwise_method      = "wilcox.test",
    figure_width         = 8,
    figure_height        = 6
  ),

  logistic_quartile_glm = list(
    index_var              = "exposure_days_per10",
    group_var              = "duration_q",
    group_levels           = c("Q1_<15", "Q2_15_30", "Q3_30_90", "Q4_>90"),
    include_continuous_row = TRUE,
    model1_factors         = c("Age", "Gender", "Race", "BMI"),
    model2_factors         = c(
      "Age", "Gender", "Race", "BMI",
      "DVT_num", "CKD_num", "Malignancy_num", "Glucocorticoid_num"
    ),
    gate_enable            = FALSE,
    stop_if_crude_all_ns   = FALSE,
    extend_branch          = character(0),
    degrade_branch         = character(0),
    p_threshold            = 0.05,
    phase                  = "screen",
    random_search          = list(enable = FALSE),
    pause_enable           = FALSE,
    pause_on_search_fail   = FALSE
  ),

  logistic_binary_glm = list(
    index_var              = "exposure_days_per10",
    group_var              = "long_term_label",
    group_levels           = c("Non_LongTerm", "LongTerm"),
    include_continuous_row = TRUE,
    model1_factors         = c("Age", "Gender", "Race", "BMI"),
    model2_factors         = c(
      "Age", "Gender", "Race", "BMI",
      "DVT_num", "CKD_num", "Malignancy_num", "Glucocorticoid_num"
    ),
    gate_enable            = FALSE,
    stop_if_crude_highest_ns = FALSE,
    extend_branch          = character(0),
    degrade_branch         = character(0),
    p_threshold            = 0.05,
    phase                  = "screen",
    random_search          = list(enable = FALSE),
    pause_enable           = FALSE,
    pause_on_search_fail   = FALSE
  ),

  rcs_incidence = list(
    index_var          = "exposure_days_per10",
    nk_range           = 3:5,
    histbin            = 1,
    color_seed         = 123,
    group_cutoffs      = "primary"
  ),

  logistic_quartile_glm_rcs = list(
    index_var              = "exposure_days_per10",
    include_continuous_row = TRUE,
    model1_factors         = c("Age", "Gender", "Race", "BMI"),
    model2_factors         = c(
      "Age", "Gender", "Race", "BMI",
      "DVT_num", "CKD_num", "Malignancy_num", "Glucocorticoid_num"
    ),
    gate_enable            = FALSE,
    phase                  = "rcs",
    random_search          = list(enable = FALSE),
    pause_enable           = FALSE
  ),

  logistic_binary_glm_rcs = list(
    index_var              = "exposure_days_per10",
    include_continuous_row = TRUE,
    model1_factors         = c("Age", "Gender", "Race", "BMI"),
    model2_factors         = c(
      "Age", "Gender", "Race", "BMI",
      "DVT_num", "CKD_num", "Malignancy_num", "Glucocorticoid_num"
    ),
    gate_enable            = FALSE,
    phase                  = "rcs",
    random_search          = list(enable = FALSE),
    pause_enable           = FALSE
  ),

  subgroup = list(
    min_n                  = 20,
    required_subgroup_vars = c(
      "Age_Group", "Gender", "Race", "BMI_Group",
      "DVT", "CKD", "Malignancy", "Glucocorticoid"
    ),
    forest_xlim            = c(0, 8)
  ),

  subgroup_incidence = list(
    enable = TRUE
  ),

  mediation_incidence = list(
    exposure                = "exposure_days_per10",
    mediators               = c("avg_admin_per_day", "daily_avg_dose"),
    outcome                 = "Disease",
    bootstrap_iter          = 200L,
    standardize_mediator    = TRUE,
    auto_covariate_search   = FALSE,
    dual_library_lm_screen  = FALSE,
    diagram_enable          = TRUE,
    pause_enable            = FALSE
  ),

  pub = list(
    write_index_summary_results = TRUE,
    index_summary_results_dir = "summary_results",
    summary_dirname = "summary_results",
    curate_incidence_figures = TRUE,
    # 对齐 Liu 2026：Fig1 流程 → Fig2 亚组 → Fig3 RCS → Fig4 中介
    figure_scheme = "liu_clinical",
    drop_non_main_logistic = FALSE,
    drop_final_multivariable_model = TRUE,
    tables_figures_only = FALSE
  ),

  feature_selection = list(enable = FALSE)
)

pipeline <- list(
  name   = "enoxaparin_osteoporosis_incidence_liu2026",
  blocks = c(
    "attrition_flowchart",
    "data_clean",
    "column_mapping",
    "analysis_exclusion",
    "imputation",
    "baseline_binary",
    "boxplot",
    "logistic_quartile_glm",
    "logistic_binary_glm",
    "rcs_incidence",
    "logistic_quartile_glm_rcs",
    "logistic_binary_glm_rcs",
    "subgroup_incidence",
    "mediation_incidence"
  ),
  logistic_gate = list(enable = FALSE),
  render_tables_after = c(
    "imputation", "baseline_binary", "boxplot",
    "logistic_quartile_glm", "logistic_binary_glm",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_binary_glm_rcs",
    "subgroup_incidence", "mediation_incidence"
  ),
  render_figures_after = character(0),
  dual_db = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    dir    = "/mnt/g/02block_result/66_linchuangshengxin/Clinical_Bio_41947218/Output/enoxaparin_op_incidence/checkpoints"
  )
)
