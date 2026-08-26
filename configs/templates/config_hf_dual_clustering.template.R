###############################################################################
#  config_hf_dual_clustering.R — HF 双库（eICU + MIMIC）无监督亚型分析配置
#  source 后得到: config, pipeline
#  说明:
#   1) 本文件仅配置，不包含可执行 run_block 代码
#   2) 双库切换由 run 脚本分库加载该模板并覆盖 data/column_mapping/outcome 字段
###############################################################################

# 与临床/结局无关的行政或流程变量（双库 eICU 特有列名；MIMIC 无则自动忽略）
hf_nonclinical_vars <- c(
  "hosplosday", "unitadmitsource", "unitdischargelocation",
  "unitdischargestatus", "unitlosday", "unittype"
)

config <- list(
  data = list(
    rawdata_path     = "data_cc/eicu/D02_Original_AKD.RData",
    rawdata_obj      = "data_imp",
    outcome_path     = NULL,
    outcome_column   = "hospdischargestatus",
    id_column        = "subject_id",
    strip_id_columns_after_imputation = c("subject_id")
  ),

  project = list(
    name             = "HF_dual_unsupervised",
    disease          = "Heart Failure",
    database         = "eICU",
    study_type       = "prognosis",
    classification_mode = "binary",
    analysis_group   = "non-survivor",
    reference_group  = "survivor",
    output_dir       = "Output/HF_dual_clustering",
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),

  survival = list(
    time_var  = "survival_time_28d",
    event_var = "survival_28d",
    index_var = "Age"
  ),

  logistic = list(
    index_var = "Age"
  ),

  plot = list(
    font_family = "Times New Roman"
  ),

  data_clean = list(
    missing_threshold = 0.3,
    age_filter        = NULL,
    drop_columns      = hf_nonclinical_vars
  ),

  column_mapping = list(
    enable        = TRUE,
    database_type = "eICU"
  ),

  imputation = list(
    missing_col_threshold = 0.2,
    method                = "cart",
    m                     = 5L,
    max_iter              = 5L,
    seed                  = 1234L,
    complete_action       = 1L,
    export_missing_fig    = TRUE,
    export_table_s1       = TRUE,
    table_s1_max_cat_levels = 15L
  ),

  baseline_binary = list(
    sig_cutoff            = 0.05,
    strata                = NULL,
    include_vars          = NULL, # 运行时建议写入两库 common_vars
    exclude_vars          = c("subject_id", "survival_time_28d", hf_nonclinical_vars),
    pause_enable          = FALSE,
    pause_on_table1_fail  = TRUE,
    pause_on_min_sig_vars = FALSE,
    pause_min_sig_vars    = 3L
  ),

  univariate_prognosis = list(
    include_predictors   = NULL,       # run_hf 写入双库 common_vars（与 baseline 一致）
    sig_cutoff           = 0.05,
    screening_cutoff     = 0.1,
    excluded_predictors  = c(
      "subject_id", "ID", "survival_28d", "survival_time_28d",
      "in-hospital mortality", "is_hosp_dead", "hospdischargestatus",
      hf_nonclinical_vars
    ),
    required_predictors  = character(0),
    demo_keywords        = c("Age", "Gender", "Race", "BMI", "Weight", "Height"),
    index_transform      = "none",
    pause_enable         = FALSE
  ),

  multivariate_prognosis = list(
    include_predictors   = NULL,       # run_hf 写入双库 common_vars（与 baseline 一致）
    sig_cutoff           = 0.05,
    input_from           = "vif_screen_pass",
    write_model_factors  = FALSE,
    excluded_predictors  = c(
      "subject_id", "ID", "survival_28d", "survival_time_28d",
      "in-hospital mortality", "is_hosp_dead", "hospdischargestatus",
      hf_nonclinical_vars
    ),
    required_predictors  = character(0),
    demo_keywords        = c("Age", "Gender", "Race", "BMI", "Weight", "Height"),
    pause_enable         = FALSE
  ),

  multicollinearity = list(
    vif_threshold_strict = 4,
    vif_threshold_loose  = 10,
    min_vars_threshold   = 0,
    exclude_vars         = c("Height", hf_nonclinical_vars),
    vif_design_extra_predictors = character(0),
    vif_append_extra_to_model2_outputs = FALSE,
    export_full_vif_table = TRUE,
    screen = list(
      table_title = "Multicollinearity Analysis (VIF, univariate p<0.1 screen)",
      csv_name = "VIF_check_screen.csv"
    ),
    final = list(
      table_title = "Multicollinearity Analysis (VIF, multivariate p<0.05)",
      csv_name = "VIF_check_final.csv"
    )
  ),

  correlation = list(
    include_vars       = NULL,         # run_hf 写入双库 common_vars
    high_cor_threshold = 0.5
  ),

  lca = list(
    # 双库穷举扫描命中：6 变量一致，Crude Cox+Logistic 两库均 P<0.05（dual_sweep/exhaustive.log）
    candidate_vars = c(
      "Weight", "BUN", "CalciumTotal", "Potassium", "HR", "SBP"
    ),
    optimal_k      = 2,                # 固定 k=2（双库一致）
    vif_threshold  = 4,
    cor_threshold  = 0.5,
    min_vars       = 6,
    max_vars       = 6,
    max_k          = 6,
    reps           = 100,
    pItem          = 0.8,
    swap_label_1_2 = FALSE,
    outcome_col    = "survival_28d",
    time_col       = "survival_time_28d",
    factor_vars    = c("Gender", "Race", "survival_28d"),
    required_vars  = character(0),
    required_any_of = list(c("SBP")),
    # 聚类专用排除（不进 LCA；Age/BMI 等留作 Cox/Logistic 协变量）
    exclude_vars   = c("Age", "Height", "BMI", "Creatinine", "Chloride", "DBP"),
    output_dir     = "lca_output"
  ),

  cox_binary = list(
    index_var         = "Subphenotype",
    group_var         = "Subphenotype",  # 直接用亚型标签，不做中位数二分
    group_levels      = NULL,            # 由实际 k 自动决定
    cutoff            = NULL,
    model1_factors    = c("Age"),        # 人口学协变量（两库共有）
    model2_factors    = c("Age", "SBP", "BUN", "HR", "RR", "Temperature"),
    table_filename    = NULL,
    pause_enable      = FALSE,
    pause_on_fit_fail = FALSE
  ),

  logistic_binary_glm = list(
    index_var = "Subphenotype",
    group_var = "Subphenotype",
    group_levels = NULL,
    include_continuous_row = TRUE,
    model1_factors = NULL,
    random_search = list(
      max_attempts = 100L,
      sample_n     = 8L,
      p_threshold  = 0.05
    ),
    pause_enable = FALSE,
    pause_on_search_fail = FALSE,
    table_filename = NULL
  ),

  plot_histogram = list(
    subtype_col    = "Subphenotype",
    event_var      = "in-hospital mortality",
    dead_values    = c("Expired", "Non-survivor", "1", "Dead"),
    class_prefix   = "Subphenotype",
    show_pct_label = TRUE,
    show_chi2_p    = TRUE,
    x_label        = "Subphenotype",
    y_label        = "In-hospital mortality (%)",
    plot_title     = NULL,
    plot_width     = 6.5,
    plot_height    = 5.5,
    pause_enable   = FALSE,
    pause_on_no_output = TRUE
  ),

  km_strata = list(
    strata_vars = c("Subphenotype"),
    strata_defs = list(),
    time_var = "survival_time_28d",
    event_var = "survival_28d",
    event_value = 1,
    time_divisor = 1,
    fun = "pct",
    risk_table = TRUE,
    fallback_no_pval = TRUE,
    export_combined = TRUE,
    combined_ncol = 1,
    combined_nrow = 1,
    pause_enable = FALSE,
    pause_on_no_figures = TRUE
  ),

  # ── Table 2a: Cox（28天）四模型 ──────────────────────────────────────────────
  # register_block: "cox_subphenotype"
  cox_subphenotype = list(
    subphenotype_col = "Subphenotype",   # LCA 亚型列（来自 df_final）
    ref_class        = NULL,             # NULL → 按 28 天死亡粗率自动选最低风险亚型为参照
    time_var         = NULL,             # NULL → config$survival$time_var
    event_var        = NULL,             # NULL → config$survival$event_var
    model_sets       = list(
      Crude  = NULL,                     # 不调整
      Model2 = c("Age"),
      Model3 = c("Age", "BMI"),
      Model4 = c("Age", "BMI", "BUN", "HR", "Temperature")
    ),
    table_filename   = NULL,             # NULL → 自动命名
    pause_enable     = FALSE
  ),

  # ── Table 2b: Logistic（院内死亡）四模型 ─────────────────────────────────────
  # register_block: "logistic_subphenotype"
  logistic_subphenotype = list(
    subphenotype_col = "Subphenotype",
    ref_class        = NULL,             # NULL → 按院内死亡粗率自动选最低风险亚型为参照
    outcome_col      = NULL,             # NULL → config$data$outcome_column
    model_sets       = list(
      Crude  = NULL,
      Model2 = c("Age"),
      Model3 = c("Age", "BMI"),
      Model4 = c("Age", "BMI", "BUN", "HR", "Temperature")
    ),
    table_filename   = NULL,
    pause_enable     = FALSE
  ),

  unsupervised_clustering_table = list(
    k_select            = 2,
    # 映射后列名；两库插补数据共有（见 column_mapping）
    vars                = c(
      "HR", "SBP", "DBP", "RR", "Temperature",
      "Weight", "BUN", "CalciumTotal", "Potassium", "Sodium", "Chloride", "Creatinine"
    ),
    preferred_event_var = "survival_28d",
    preferred_time_var  = "survival_time_28d",
    fallback_event_var  = "survival_28d",
    fallback_time_var   = "survival_time_28d",
    cut_spec            = list(),
    pause_enable        = FALSE
  ),

  dual_db = list(
    enable = TRUE,
    primary = list(
      name = "eICU",
      rawdata_path = "data_cc/eicu/D02_Original_AKD.RData",
      rawdata_obj = "data_imp",
      outcome_column = "hospdischargestatus",
      column_mapping_type = "eICU"
    ),
    secondary = list(
      name = "MIMIC",
      rawdata_path = "data_cc/mimic/D01_baseline_MIMIC.RData",
      rawdata_obj = "data_imp",
      outcome_column = "is_hosp_dead",
      column_mapping_type = "MIMIC"
    ),
    harmonization = list(
      prognosis_include_vars = NULL,   # run_hf 写入：与 baseline 相同的双库 common_vars
      common_continuous_after = "imputation",
      min_cluster_vars = 5L,
      max_cluster_vars = 15L,
      require_same_k = TRUE,
      align_subtype_semantics = TRUE,
      require_same_covariates = TRUE
    )
  )
)

pipeline <- list(
  name   = "hf_dual_unsupervised_standard",
  blocks = c(
    "data_clean",
    "column_mapping",
    "imputation",
    "baseline_binary",
    "univariate_prognosis",
    "multicollinearity_screen",
    "multivariate_prognosis",
    "multicollinearity_final",
    "correlation",
    "lca",
    "subtype_viz",
    "chord_diagram",
    "cox_binary",
    "cox_subphenotype",
    "logistic_subphenotype",
    "plot_histogram",
    "km_strata",
    "unsupervised_clustering_table"
  ),
  render_tables_after  = c(
    "imputation",
    "baseline_binary",
    "univariate_prognosis",
    "multicollinearity_screen",
    "multivariate_prognosis",
    "multicollinearity_final",
    "unsupervised_clustering_table"
  ),
  render_figures_after = c(
    "correlation",
    "lca",
    "subtype_viz",
    "chord_diagram",
    "plot_histogram",
    "km_strata"
  ),
  dual_db = list(enable = TRUE),
  checkpoint = list(
    enable = TRUE,
    dir    = "checkpoints_hf_dual"
  )
)

