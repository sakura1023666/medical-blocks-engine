###############################################################################
# config_gallstone_nomogram_batch.template.R
# 发病地基 + 临床预测列线图后缀（Chen JAD 2026 方法 → 胆结石碎石成功）
# 外验面板 = 内部 bootstrap；关联/RCS 对全部连续特征 batch 并行
# 决策树: Decisiontree/decision_tree_gallstone_nomogram.md
###############################################################################

.block_repo_root <- {
  if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else if (nzchar(Sys.getenv("BLOCK_REPO_ROOT", "")) &&
           dir.exists(Sys.getenv("BLOCK_REPO_ROOT"))) Sys.getenv("BLOCK_REPO_ROOT")
  else if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else "E:/01block/01Block-new-Final"
}
.block_result_root <- {
  # Windows Rscript 优先 G:/；勿被 WSL 的 BLOCK_RESULT_ROOT=/mnt/g 污染
  if (dir.exists("G:/02block_result")) "G:/02block_result"
  else if (nzchar(Sys.getenv("BLOCK_RESULT_ROOT", "")) &&
           dir.exists(Sys.getenv("BLOCK_RESULT_ROOT"))) Sys.getenv("BLOCK_RESULT_ROOT")
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}

.batch_project_root <- file.path(.block_result_root, "45_Gallstone", "Nomogram_41815074")
.batch_data_xlsx <- {
  cands <- c(
    file.path(.batch_project_root, "data", "gallstone_features.xlsx"),
    file.path(.batch_project_root, "Data", "gallstone_features.xlsx"),
    file.path(.batch_project_root, "data", "\u6a0a\u9e4f\u98de\u8001\u5e08-\u80c6\u7ed3\u77f3\u7279\u5f81  20260921\uff0c\u8bbe\u8ba1\u6570\u636e(1).xlsx")
  )
  hit <- cands[file.exists(cands)]
  if (length(hit)) hit[[1L]] else cands[[1L]]
}

.cont_all <- c(
  "Age", "diameter_cm", "volume_cm3", "ct_min", "ct_max",
  "pct_lt40", "pct_40_80", "pct_gt80", "energy_j", "shots"
)
.prespec_predictors <- c("Age", "diameter_cm", "volume_cm3", "energy_j", "shots")
.cont_units <- .prespec_predictors

config <- list(
  project = list(
    name = "Gallstone_Lithotripsy_Nomogram",
    disease = "gallstone",
    disease_code = "45",
    study_type = "incidence",
    literature_doi = "10.1177/13872877261424471",
    database = "single_center_xlsx",
    root = .block_repo_root,
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    analysis_group = "Yes",
    reference_group = "No"
  ),

  data = list(
    rawdata_path = .batch_data_xlsx,
    rawdata_obj = NULL,
    id_column = "id",
    outcome_column = "Success"
  ),

  incidence = list(
    outcome_var = "Success",
    index_var = .cont_units[[1L]]
  ),

  # 年龄切点依据: reports/disease_age_cutoff_gallstone_nomogram.md（无病种特异文献，默认65）
  subgroup = list(
    enable = TRUE,
    var_source = "required",
    required_subgroup_vars = c("Sex", "Age"),
    age_cutoff = 65L,
    level_order = list(Age_Group = c("< 65", "\u2265 65"))
  ),

  gallstone_nomogram = list(
    data_xlsx = .batch_data_xlsx,
    continuous_features = .cont_all,
    categorical_features = c("Sex", "shape", "color", "surface", "stone_type"),
    # 关联段 Model1–3：UV 显著入选；死规则 force_model1=Age（不论 UV 是否显著）
    assoc_covariate_source = "uv_significant",
    force_model1 = "Age",
    uv_alpha = 0.05,
    uv_demo_pool = c("Age", "Sex"),
    uv_candidate_pool = c("Age", "Sex", "shape", "color", "surface", "stone_type"),
    # 由 UV block 回写（已并入 Age）；此处仅作空占位
    model2 = character(0),
    model3 = character(0),
    # 预测段：临床预指定 + Ridge（替代 LASSO 海选）
    feature_select_mode = "prespecified",
    prespecified_predictors = .prespec_predictors,
    ridge_lambda = "lambda.1se",
    exclude_from_lasso = c("stone_type", "shape", "color", "surface",
                           "ct_min", "ct_max", "pct_lt40", "pct_40_80", "pct_gt80"),
    train_ratio = 0.7,
    seed = 42L,
    bootstrap_B = 200L,
    external_mode = "bootstrap_internal"
  ),

  analysis_exclusion = list(
    enable = TRUE,
    disease_vars = c("success"),
    protect_vars = c(
      "Age", "Sex", "shape", "color", "surface", "stone_type",
      "diameter_cm", "volume_cm3", "ct_min", "ct_max",
      "pct_lt40", "pct_40_80", "pct_gt80", "energy_j", "shots", "Success"
    ),
    exclude_exposure_if_uses_disease_var = FALSE
  ),

  data_clean = list(
    missing_threshold = 0.9,
    age_filter = NULL,
    drop_columns = NULL
  ),

  column_mapping = list(enable = FALSE),
  index = list(enable = FALSE, only = .cont_all),

  imputation = list(
    enable = FALSE,
    missing_col_threshold = 0.5,
    method = "cart",
    m = 1L,
    seed = 42L,
    complete_action = 1L,
    export_missing_fig = FALSE,
    export_table_s1 = FALSE
  ),

  pub_digits = list(est = 3L, p = 3L, desc = 3L, cutoff = 3L, int_big_mark = TRUE),

  # 禁止缺号顺延压缩：文献 Fig1/4–9 必须保持空位（关联 Fig2/3 在 unit 目录）
  pub = list(renumber = FALSE),

  study_batch = list(
    output_base = .batch_project_root,
    units = .cont_units,
    unit_mode = "index",
    parallel_workers = "auto",
    skip_existing = TRUE,
    fail_policy = "continue",
    worker_script = "run/study/run_study_batch_worker.R",
    shared_ck_alias = "gallstone_flowchart"
  ),

  feishu = list(
    enable = TRUE,
    app_token = Sys.getenv("FEISHU_WORKPLAN_APP_TOKEN", "RBjfb2iwmamW14s4WhKcS7kwnie")
  ),

  plot = list(font_family = "Times New Roman")
)

# shared: 入库 + Table1 + 7:3 + 预测列线图全套（只跑一次）
pipeline_shared <- list(
  name = "gallstone_nomogram_shared",
  blocks = c(
    "gallstone_data_ingest",
    "gallstone_uv_covariate_screen",
    "gallstone_flowchart",
    "gallstone_table1",
    "gallstone_train_split",
    "gallstone_lasso_onese",
    "gallstone_mv_nomogram",
    "gallstone_roc_cal_boot",
    "gallstone_dca_cic"
  ),
  checkpoint = list(
    enable = TRUE,
    dir = file.path(.batch_project_root, "checkpoints", "_shared", "main")
  )
)

# unit: 每个连续特征的关联 OR + RCS + 亚组 + 收口（可并行）
pipeline_unit <- list(
  name = "gallstone_nomogram_unit",
  blocks = c(
    "gallstone_assoc_or_panels",
    "gallstone_rcs_panels",
    "gallstone_subgroup_sex",
    "gallstone_pub_finalize"
  ),
  checkpoint = list(enable = TRUE)
)

config$pipeline_unit <- pipeline_unit
pipeline <- pipeline_shared
