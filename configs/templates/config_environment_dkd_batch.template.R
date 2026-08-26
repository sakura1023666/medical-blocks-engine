###############################################################################
#  config_environment_dkd_batch.template.R — DKD × 环境 VOC（NHANES 批量模板）
#
#  协变量筛选（与 config_incidence_nhanes.R 一致）:
#    Table 1 → 单因素 P<0.1 → VIF 筛 → 多因素 P<0.05 → VIF 终筛
#    → 环境 VOC 分析（LASSO/GLM/WQS/BKMR）→ 并行 rcs_nhanes → qgcomp/中介/亚组
#
#  source 后: config, pipeline_shared, pipeline_voc_batch, pipeline_tail, pipeline
#  入口:     run_environment_dkd_batch.R
#  飞书:     项目根 .env.feishu（与 run_incidence_dual_batch.R 相同，见 .env.feishu.example）
#
#  ⚠️ 复制为 configs/config_<study>.R 后回填 <TO_CONFIRM> 占位符再试跑
###############################################################################

.batch_project_root <- "Output/<TO_CONFIRM_DKD_VOC>"          # ❓ 产出根目录
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(

  # ── 数据（路径相对项目根 Data/）──────────────────────────────────────────
  data = list(
    # 推荐：Step01 合并后临床+环境 RData（对应 initConfig D03_EnvResultData）
    rawdata_path     = "Data/nhanes/<TO_CONFIRM>.RData",       # ❓ 如 D03_EnvResultData.RData
    rawdata_obj      = "<TO_CONFIRM>",                         # ❓ 如 EnvResult / data_MI
    outcome_path     = NULL,
    outcome_column   = "Group",                                # ❓ 或 Disease_Group
    id_column        = "SEQN",
    strip_id_columns_after_imputation = c("SEQN")
  ),

  project = list(
    name                         = "DKD_Environment_VOC_Batch",
    disease                      = "DKD",
    disease_cn                   = "糖尿病肾病",
    database                     = "NHANES",
    database_type                = "NHANES",
    study_type                   = "incidence",
    classification_mode          = "binary",
    analysis_group               = "DKD",                      # ❓ 病例组标签
    reference_group              = "Never DKD",                  # ❓ 对照组标签
    output_dir                   = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix           = "step",
    mirror_pub_outputs_to_root   = TRUE,                       # ❓ wizard 确认
    root                         = NULL
  ),

  incidence = list(
    outcome_var        = "Group",
    index_var          = NULL,
    # NULL → 运行时按 environment$voc_col_pattern 自动识别 URX* 列
    index_exclude_vars = NULL                                  # 也可手动填全量 VOC 向量
  ),

  environment = list(
    voc_col_pattern   = "^URX",
    voc_exclude_fixed = c("URXUCR", "URXUMA", "URXU_SG", "URXHEM", "URXPHE")
  ),

  prediction = list(
    index_vars                          = NULL,
    keep_index_vars_in_regression_table = FALSE
  ),

  logistic = list(
    index_var = NULL
  ),

  nhanes = list(
    survey_weight    = "WTMEC2YR",
    survey_cluster   = "SDMVPSU",
    survey_strata    = "SDMVSTRA",
    auto_new_weight  = FALSE,
    cutoff_index_var = NULL,
    exclude_cols     = c(
      "ID", "SEQN", "WTINT2YR", "WTMEC2YR", "SDMVPSU", "SDMVSTRA", "Source_File"
    )
  ),

  plot = list(font_family = "Times New Roman"),

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

  # ── Table 1（加权，发病 NHANES 同款）──────────────────────────────────────
  baseline_nhanes = list(
    sig_cutoff                   = 0.05,
    pause_enable                 = FALSE,
    pause_on_weighted_table_fail = FALSE,
    pause_on_min_sig_vars        = FALSE,
    pause_min_sig_vars           = 3L
  ),

  # ── 单因素：P<0.1 进 VIF 筛（发病 NHANES 同款）────────────────────────────
  univariate_nhanes = list(
    sig_cutoff            = 0.05,
    screening_cutoff      = 0.1,
    excluded_predictors   = NULL,                              # ❓ 填全部 VOC 列名，避免进入协变量筛
    pause_enable          = FALSE,
    pause_on_min_sig_vars = FALSE,
    pause_min_sig_vars    = 3L
  ),

  # ── 多因素：输入 vif_screen_pass，P<0.05（发病 NHANES 同款）──────────────
  multivariate_nhanes = list(
    sig_cutoff              = 0.05,
    input_from              = "vif_screen_pass",
    demo_keywords           = c("Age", "Gender", "Race"),
    model1_candidate_names  = c("Age", "Gender", "Race", "PIR", "Education"),
    pause_enable            = FALSE,
    pause_on_min_sig_vars   = FALSE,
    pause_min_sig_vars      = 3L
  ),

  # ── VIF：screen（单因素后）+ final（多因素后），阈值 4（发病 NHANES 同款）──
  multicollinearity = list(
    vif_threshold_strict    = 4,
    vif_threshold_loose     = 10,
    vif_threshold_hard_drop = 50,
    min_vars_threshold      = 0,
    exclude_vars            = c("ID", "SEQN"),
    vif_design_extra_predictors = character(0),
    vif_append_extra_to_model2_outputs = FALSE,
    export_full_vif_table   = TRUE,
    anthropometric_vif_resolution = list(
      enable = TRUE,
      vars = c("BMI", "Weight", "Height", "Waist_circumstance"),
      protect_vars = character(0),
      prefer_drop_one_order = c("Weight", "Height", "Waist_circumstance"),
      apply_in_screen_only = FALSE
    ),
    screen = list(
      table_title = "Weighted Multicollinearity Analysis (VIF, univariate p<0.1 screen, NHANES)",
      csv_name    = "VIF_check_screen_weighted.csv"
    ),
    final = list(
      table_title = "Weighted Multicollinearity Analysis (VIF, multivariate p<0.05, NHANES)",
      csv_name    = "VIF_check_final_weighted.csv"
    )
  ),

  # ── 环境 VOC 预处理 ───────────────────────────────────────────────────────
  environment_process = list(
    id_column                     = "SEQN",
    missing_percentage_cutoff     = 0.2,
    below_limit_percentage_cutoff = 0.8,
    seed                          = 123L,
    mice_m                        = 5L,
    mice_method                   = "pmm",
    export_stats                  = TRUE
  ),
  process_environment_data = list(),

  remove_outliers = list(
    target_cols = NULL,
    low_prob    = 0.10,
    high_prob   = 0.90,
    iqr_factor  = 1.5
  ),

  environment_characteristics = list(
    stats_source        = "ctx",
    stats_id_col        = "SEQN",
    table_title         = "Table S1. Characteristics of Environmental Contaminants"
  ),

  voc_correlation = list(
    method       = "pearson",
    sig_cutoff   = 0.05,
    fig_filename = "Figure_VOC_Correlation.pdf"
  ),

  lasso_environment = list(
    univariate_enable   = TRUE,
    univariate_p_cutoff = 0.05,
    univariate_or_min   = 1.0,
    exclude_vars        = c("URXHEM", "URXPHE"),
    min_select_vocs     = 4L,
    table_filename      = "Table_Lasso_Univariate_Screen.xlsx",
    cv_times            = 1000L,
    lambda_multiplier   = 0.5,
    freq_cutoff_method  = "auto_floor100"
  ),
  lasso_environment_voc = list(),

  # Model1/2 = NULL → 用 multivariate_nhanes 写入的 Model1Factors / vif_final_pass
  glm_environment_quartile = list(
    model1_factors        = NULL,
    model2_factors        = NULL,
    min_select_vocs       = 4L,
    screening_p_threshold = 0.05,
    table_filename        = "Table_S4_GLM_Environment_Selection.xlsx"
  ),

  wqs_environment = list(
    auto_select_vocs = TRUE,
    min_select_vocs  = 4L,
    auto_select = list(
      quick_b = 200L, bkmr_quick_iter = 300L, bkmr_quick_nchains = 2L, max_trials = 40L
    ),
    covariates        = NULL,                                  # NULL → ctx vif_final_pass
    q_values          = 4:6,
    validation_values = c(0.6, 0.7, 0.8),
    b                 = 1000L,
    family            = "binomial",
    p_threshold       = 0.05
  ),

  bkmr_fit = list(
    min_select_vocs = 4L,
    auto_iter       = TRUE,
    min_iter_candidate = 100L,
    max_iter_candidate = 10000L,
    iter_candidate_step = 500L,
    iter_candidates = NULL,
    iter            = 1000L,
    covariates      = NULL,
    family     = "binomial",
    varsel     = TRUE
  ),

  bkmr_analysis = list(pip_threshold = 0.5),

  # Model1/2 = NULL → lnw00_resolve_models 读 ctx$vif_final_pass / Model1Factors
  rcs_nhanes = list(
    index_var       = NULL,
    model1_factors  = NULL,
    model2_factors  = NULL,
    max_model1_vars = 4L,
    knot_quantiles  = c(0.1, 0.5, 0.9),
    histper         = 25L
  ),

  qgcomp_environment = list(q = 4L, covariates = NULL),
  mediation_ers_environment = list(sims = 1000L, compute_fi_lab = TRUE),
  subgroup_environment_or = list(
    stratify_col = "Gender",
    strata_levels = c("Male", "Female")
  ),

  # ── 飞书（与 run_incidence_dual_batch / run_association_nhanes 相同机制）──
  # 凭证文件: 项目根 .env.feishu（复制 .env.feishu.example）
  # 初始化表: Rscript run_feishu_setup_tables.R
  # 自检:     Rscript run_feishu_test.R
  feishu = list(
    enable                = TRUE,
    app_id                = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret            = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token             = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id              = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    literature_default    = "DKD × 环境 VOC（NHANES）",
    project_id            = "<TO_CONFIRM_PROTOCOL>",
    owner_default         = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    disease_label         = "DKD_VOC",
    protocol_label        = "<TO_CONFIRM_PROTOCOL>",
    table_success_id      = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id      = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", "")
  ),

  environment_batch = list(
    voc_vars          = NULL,
    parallel_workers  = NULL,
    skip_existing     = TRUE,
    output_base       = .batch_project_root,
    shared_ck_base    = file.path(.batch_ck_root, "_shared", "main"),
    ram_per_worker_gb = 2.5,
    cpu_headroom      = 2L,
    ram_headroom_gb   = 4.0,
    subgroup_strata = list(
      list(stratify_col = "Gender", strata_levels = c("Male", "Female"),
           table_filename = "Table_S8_Subgroup_Gender.xlsx"),
      list(stratify_col = "Race",
           strata_levels = c("Mexican American", "Non-Hispanic Black",
                             "Non-Hispanic White", "Other Hispanic", "Other Race"),
           table_filename = "Table_S9_Subgroup_Race.xlsx"),
      list(stratify_col = "PIR", strata_levels = c("> 3.5", "1.3-3.5", "\u2264 1.3"),
           table_filename = "Table_S10_Subgroup_PIR.xlsx"),
      list(stratify_col = "Smoke", strata_levels = c("nonSmoked", "Smoked"),
           table_filename = "Table_S11_Subgroup_Smoked.xlsx")
    )
  )
)

# ── 共享层：Table1 + 单因素/VIF/多因素 + 环境 Step01–06 + Step11 ─────────────
pipeline_shared <- list(
  name   = "dkd_env_shared",
  blocks = c(
    "data_clean",
    "column_mapping",
    "imputation",
    "obj",
    "baseline_nhanes",
    "univariate_nhanes",
    "multicollinearity_nhanes_screen",
    "multivariate_nhanes",
    "multicollinearity_nhanes_final",
    "process_environment_data",
    "remove_outliers",
    "lasso_environment_voc",
    "glm_environment_quartile",
    "wqs_environment",
    "bkmr_fit",
    "bkmr_analysis",
    "environment_characteristics",
    "voc_correlation"
  ),
  render_tables_after = c(
    "imputation",
    "baseline_nhanes",
    "univariate_nhanes",
    "multicollinearity_nhanes_screen",
    "multivariate_nhanes",
    "multicollinearity_nhanes_final",
    "glm_environment_quartile",
    "wqs_environment",
    "bkmr_analysis",
    "environment_characteristics"
  ),
  render_figures_after = c(
    "imputation",
    "voc_correlation",
    "lasso_environment_voc",
    "wqs_environment",
    "bkmr_analysis"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "_shared", "main"))
)

pipeline_voc_batch <- list(
  name   = "dkd_env_voc_rcs",
  blocks = c("rcs_nhanes"),
  render_figures_after = c("rcs_nhanes"),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline_tail <- list(
  name   = "dkd_env_tail",
  blocks = c("qgcomp_environment", "mediation_ers_environment", "subgroup_environment_or"),
  render_tables_after = c("qgcomp_environment", "mediation_ers_environment", "subgroup_environment_or"),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "_shared", "main"))
)

pipeline <- list(
  name   = "dkd_environment_voc_nhanes_full",
  blocks = c(pipeline_shared$blocks, "rcs_nhanes", pipeline_tail$blocks),
  render_tables_after = unique(c(
    pipeline_shared$render_tables_after, pipeline_tail$render_tables_after
  )),
  render_figures_after = unique(c(
    pipeline_shared$render_figures_after, "rcs_nhanes",
    pipeline_tail$render_figures_after
  )),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "full_run"))
)
