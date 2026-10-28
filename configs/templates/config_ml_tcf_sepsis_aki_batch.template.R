###############################################################################
#  枫叶 · 脓毒症AKI · TCF 多算法融合（PMID 40295871）
#  地基: 预后 + ML/TCF；MIMIC 开发 + eICU 外验（dev_internal_ext）
#  暴露: ALLVARS（全临床变量池，非复合指标循环）
#  决策树: Decisiontree/decision_tree_ml_tcf_sepsis_aki_40295871.md
###############################################################################

.batch_project_root <- "G:/02block_result/42_AKI_spesis/multi-algorithm fusion_40295871"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")
.batch_data_root    <- file.path(.batch_project_root, "Data")

.engine_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(.engine_root)) {
  .engine_root <- if (dir.exists("E:/01block/01Block-new-Final")) {
    "E:/01block/01Block-new-Final"
  } else if (dir.exists("/mnt/e/01block/01Block-new-Final")) {
    "/mnt/e/01block/01Block-new-Final"
  } else {
    getwd()
  }
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = .engine_root)
Sys.setenv(MEDICAL_BLOCKS_SKIP_PIPELINE_GUARD = "1")

if (file.exists(file.path(.engine_root, "configs/ml_dual_shared_overrides.R"))) {
  source(file.path(.engine_root, "configs/ml_dual_shared_overrides.R"), local = TRUE)
}

config <- list(
  data = list(
    rawdata_path = file.path(.batch_data_root, "mimic/D04_dabiao.RData"),
    rawdata_obj = "dabiao",
    outcome_column = "DN",
    id_column = "ID",
    strip_id_columns_after_imputation = c("ID", "subject_id", "stay_id", "hadm_id")
  ),
  project = list(
    name = "SA_AKI_TCF_40295871",
    disease_code = "42",
    disease = "AKI_sepsis",
    literature_pmid = "40295871",
    database = "MIMIC",
    database_type = "regular",
    study_type = "prognosis",
    analysis_group = "1",
    reference_group = "0",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = NULL
  ),
  survival = list(
    time_var = "futime",
    event_var = "fustatus"
  ),
  index = list(enable = FALSE),
  prediction = list(index_vars = character(0)),
  # 年龄切点依据：成人 ICU 常用 65（无病种特异 RCT 亚组界则用默认 65）
  subgroup = list(
    age_cutoff = 65L,
    level_order = list(Age_Group = c("< 65", "\u2265 65"))
  ),
  analysis_exclusion = list(
    enable = TRUE,
    disease_vars = c(
      "Acute_Renal_Failure", "CKD", "T2DM", "T1DM", "Diabetes",
      "SOFA", "APSIII", "SAPSII", "OASIS", "SIRS", "CHARLSON"
    ),
    exclude_exposure_if_uses_disease_var = TRUE,
    protect_vars = c("Age")
  ),
  imputation = list(
    enable = TRUE,
    method = "pmm",
    m = 5L,
    maxit = 10L,
    seed = 42L,
    rubin_pool = TRUE,
    complete_action = 1L,
    fit_on = "train"
  ),
  train_validation = list(
    enable = TRUE,
    train_ratio = 0.7,
    seed = 42L,
    stratify = TRUE,
    ## TCF 文献：单次分层划分即可；勿用默认 2000 次重划分（全变量 KS 极慢）
    max_resplit_iter = 1L,
    p_strict = 0,
    export_baseline_table = TRUE
  ),
  splitting = list(
    enable = TRUE,
    train_ratio = 0.7,
    seed = 42L,
    stratify = TRUE
  ),
  baseline_binary = list(
    enable = TRUE,
    sig_cutoff = 0.05,
    early_stop_if_index_ns = FALSE,
    pause_enable = FALSE,
    pause_on_min_sig_vars = FALSE,
    pause_on_fit_fail = FALSE,
    pause_on_table1_fail = FALSE
  ),
  dual_db = list(
    enable = TRUE,
    workflow = "primary_full_secondary_ml",
    split_mode = "dev_internal_ext",
    mirror_aggregate = TRUE,
    ## 文献口径：MIMIC 开发 / eICU 外验；本队列 eICU N 可略大于 MIMIC
    allow_primary_smaller_n = TRUE,
    checkpoint_base = .batch_ck_root,
    harmonization_dir = file.path(.batch_ck_root, "_global_harmonization"),
    ## 显式 list，避免 $harmonization 与 harmonization_dir 部分匹配
    harmonization = list(),
    primary = list(
      name = "MIMIC", db_type = "regular",
      rawdata_path = file.path(.batch_data_root, "mimic/D04_dabiao.RData"),
      rawdata_obj = "dabiao", id_column = "ID", column_mapping_type = "MIMIC"
    ),
    secondary = list(
      name = "eICU", db_type = "regular",
      rawdata_path = file.path(.batch_data_root, "eicu/D04_dabiao.RData"),
      rawdata_obj = "dabiao", id_column = "ID", column_mapping_type = "EICU"
    )
  ),
  ml_batch = list(
    index_vars = c("ALLVARS"),
    index_mode = "all_vars",
    split_mode = "dev_internal_ext",
    db_mode = "both",
    output_base = .batch_project_root,
    shared_ck_base = file.path(.batch_ck_root, "_shared"),
    index_ck_base = file.path(.batch_ck_root, "by_index"),
    skip_existing = TRUE,
    ram_per_worker_gb = 4,
    baseline_index_ns_fail_rule = FALSE
  ),
  feature_selection = list(
    enable = TRUE,
    methods = c("entropy_stepwise"),
    entropy_stepwise = list(enable = TRUE, step = 2L, max_k = 50L)
  ),
  feature_selection_entropy_stepwise = list(enable = TRUE, step = 2L, max_k = 50L),
  ml_models = list(
    enable = TRUE,
    methods = c("dt", "rf", "xgboost", "lightgbm", "rsvm", "naive_bayes", "gbdt"),
    cv_folds = 5L  # 文献 / NPJ-codes RandomizedSearchCV cv=5
  ),
  ## 对齐公开代码：MinMax(fit train) + SMOTE(sampling_strategy=1, k_neighbors=20)
  ml_tcf_balance_scale = list(
    enable = TRUE,
    k_neighbors = 20L,
    seed = 42L
  ),
  ml_topsis_fusion = list(
    enable = TRUE,
    models = c("DT", "RF", "XGB", "LGBM", "SVM", "NB", "GBDT"),
    threshold = 0.5
  ),
  ml_naive_bayes = list(enable = TRUE),
  ml_gbdt = list(enable = TRUE, n_trees = 100L, learning_rate = 0.1),
  ml_eval_external = list(enable = TRUE),
  pub_figures = list(formats_dir = TRUE, dpi = 600L, tiff_compression = "lzw",
                     write_image_information = TRUE),
  pub_digits = list(est = 3L, p = 3L, desc = 3L, cutoff = 3L,
                    int_big_mark = TRUE, desc_trim = TRUE),
  feishu = list(
    enable = TRUE,
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE
  )
)

.primary_slot <- tolower(config$dual_db$primary$name %||% "mimic")
.secondary_slot <- tolower(config$dual_db$secondary$name %||% "eicu")
._tcf_head <- c(
  "ml_id_deduplicate", "data_clean", "column_mapping", "dual_db_column_harmonize",
  "index", "analysis_exclusion", "train_validation", "imputation"
)

pipeline_shared_nhanes <- list(
  name = paste0("ml_tcf_shared_", .primary_slot),
  blocks = c(
    "ml_id_deduplicate", "data_clean", "column_mapping",
    "dual_db_column_harmonize", "index"
  ),
  logistic_gate = list(enable = FALSE),
  render_tables_after = character(0),
  render_figures_after = character(0),
  dual_db = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    dir = file.path(.batch_ck_root, "_shared", .primary_slot)
  )
)

pipeline_shared_regular <- list(
  name = paste0("ml_tcf_shared_", .secondary_slot),
  blocks = c(
    "ml_id_deduplicate", "data_clean", "column_mapping",
    "dual_db_column_harmonize", "index"
  ),
  logistic_gate = list(enable = FALSE),
  render_tables_after = character(0),
  render_figures_after = character(0),
  dual_db = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    dir = file.path(.batch_ck_root, "_shared", .secondary_slot)
  )
)

pipeline_regular_primary_ml_batch <- list(
  name = "ml_tcf_primary_mimic",
  blocks = c(
    ._tcf_head,
    "baseline_binary",
    "feature_selection_entropy_stepwise",
    "ml_tcf_balance_scale",
    "ml_models_bundle", "ml_topsis_fusion",
    "performance_ml", "shap",
    "attrition_flowchart"
  ),
  logistic_gate = list(enable = FALSE),
  render_tables_after = c(
    "train_validation", "imputation", "baseline_binary",
    "feature_selection_entropy_stepwise",
    "ml_tcf_balance_scale",
    "ml_models_bundle", "ml_topsis_fusion", "performance_ml"
  ),
  render_figures_after = c(
    "feature_selection_entropy_stepwise", "performance_ml", "shap"
  ),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline_mimic_ml_batch <- list(
  name = "ml_tcf_secondary_eicu_ext",
  blocks = c(
    ._tcf_head,
    "baseline_binary",
    "ml_inherit_primary_features",
    "ml_eval_external",
    "attrition_flowchart"
  ),
  logistic_gate = list(enable = FALSE),
  render_tables_after = c(
    "train_validation", "imputation", "baseline_binary",
    "ml_inherit_primary_features", "ml_eval_external"
  ),
  render_figures_after = c("ml_eval_external"),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline_nhanes_batch <- pipeline_regular_primary_ml_batch
pipeline <- pipeline_regular_primary_ml_batch

rm(.primary_slot, .secondary_slot, ._tcf_head)
