###############################################################################
# config_cum_egdr_kmeans_ckm_batch.template.R
# 发病地基 + 累积暴露/k-means 后缀
# 本跑：仅 eGDR；文献固定 Model1–3 协变量；不做 UV/VIF；串行 workers=1
# 文献: Wang et al. Cardiovasc Diabetol 2026;25:78
###############################################################################

.block_repo_root <- {
  env <- Sys.getenv("BLOCK_REPO_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env
  else if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else "E:/01block/01Block-new-Final"
}
.block_result_root <- {
  env <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env
  else if (dir.exists("G:/02block_result")) "G:/02block_result"
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}

.batch_project_root <- file.path(.block_result_root, "46_CKM", "\u7d2f\u8ba1\u66b4\u9732\u805a\u7c7b_41654871")
.batch_data_csv <- file.path(.batch_project_root, "data", "4d_\u7eb5\u5411\u5206\u6790\u5bbd\u8868_4983.csv")
.batch_attrition_csv <- file.path(.batch_project_root, "data", "4_\u6570\u636e\u96c6_17708.csv")

source(file.path(.block_repo_root, "configs/indices/composite_index_vars.R"))

# 用户指定本跑仅 eGDR（全深度）
.test_units <- c("eGDR")

config <- list(
  project = list(
    name = "CKM_Cum_eGDR_Kmeans_CHARLS",
    disease = "stroke_CKM",
    disease_code = "46",
    study_type = "incidence",
    literature_pmid = "41654871",
    database = "CHARLS",
    root = .block_repo_root,
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    analysis_group = "Stroke",
    reference_group = "No stroke"
  ),

  data = list(
    rawdata_path = .batch_data_csv,
    rawdata_obj = NULL,
    id_column = "ID",
    outcome_column = "Stroke",
    strip_id_columns_after_imputation = character(0)
  ),

  incidence = list(
    outcome_var = "Stroke",
    index_var = "eGDR"
  ),

  logistic = list(index_var = "eGDR"),

  # 年龄切点依据: reports/disease_age_cutoff_ckm_stroke_charls.md（CHARLS CKM 卒中同设计用 60）
  # 协变量：文献固定 Model2/3，不做单因素/VIF 筛选
  subgroup = list(
    enable = TRUE,
    var_source = "required",
    required_subgroup_vars = c("Age", "Gender", "Education", "Smoke", "Drink",
                               "Dyslipidemia", "Diabetes", "CKM_stage"),
    age_cutoff = 60L,
    continuous_index_mode = "highest_vs_lowest",
    forest_n_source = "full_stratum",
    adjust_covariates = c("Age", "Gender", "Marital", "BMI", "Education",
                          "Smoke", "Drink", "eGFR", "Dyslipidemia", "Diabetes"),
    level_order = list(Age_Group = c("< 60", "\u2265 60"))
  ),

  cum_egdr_kmeans = list(
    data_csv = .batch_data_csv,
    attrition_csv = .batch_attrition_csv,
    filter_cohort_final = TRUE,
    recompute_egdr = TRUE,
    cum_multiplier = 3,          # 与文献公式一致
    full_depth_indices = c("eGDR"),
    force_k = 4L,
    k_max = 8L,
    seed = 2026L,
    nstart = 25L,
    class_ref = "Persistent_low",
    # 文献 Methods：Model1 未校正；Model2 年龄/性别/婚姻；Model3 +BMI/教育/吸烟饮酒/eGFR/血脂异常/糖尿病
    model2 = c("Age", "Gender", "Marital"),
    model3 = c("Age", "Gender", "Marital", "BMI", "Education", "Smoke", "Drink",
               "eGFR", "Dyslipidemia", "Diabetes")
  ),

  analysis_exclusion = list(
    enable = TRUE,
    disease_vars = c(
      "stroke1", "r1stroke", "r2stroke", "r3stroke",
      "hearte1", "clinicalCVD1",
      "t2dm1", "prediabetes1", "hyperTG1", "ckd1", "overweight1"
    ),
    protect_vars = c("Age", "CKM_stage", "ckm_stage", "Diabetes", "Dyslipidemia",
                     "Gender", "Marital", "BMI", "Education", "Smoke", "Drink", "eGFR"),
    exclude_exposure_if_uses_disease_var = TRUE
  ),

  data_clean = list(
    missing_threshold = 0.9,
    # 行过滤表达式，如 "Age >= 50"；本流水线无 data_clean block，由 ckm_stroke_data_ingest 落实
    age_filter = NULL,
    drop_columns = NULL
  ),

  column_mapping = list(enable = FALSE),

  # 本跑不做 index 批量派生；eGDR/cum 由 ingest + cum_exposure_build 负责
  index = list(
    enable = FALSE,
    only = .test_units
  ),

  imputation = list(
    missing_col_threshold = 0.5,
    method = "cart",
    m = 5L,
    max_iter = 5L,
    seed = 1234L,
    complete_action = 1L,
    export_missing_fig = FALSE,
    export_table_s1 = FALSE
  ),

  baseline_multiclass = list(
    enable = TRUE,
    sig_cutoff = 0.05,
    strata = "eGDR_Class",
    pause_enable = FALSE,
    pause_on_table1_fail = FALSE,
    pause_on_min_sig_vars = FALSE
  ),

  # 主 RCS 由 rcs_ckm_strata_panels 产出；关闭通用 rcs 以免重复/缺配
  rcs_incidence = list(enable = FALSE, pause_enable = FALSE),

  # 明确关闭 UV/VIF 选协变量路径
  univariate_incidence = list(enable = FALSE),
  multicollinearity_screen = list(enable = FALSE),
  multicollinearity_final = list(enable = FALSE),

  pub_digits = list(est = 3L, p = 3L, desc = 3L, cutoff = 3L, int_big_mark = TRUE),

  study_batch = list(
    output_base = .batch_project_root,
    units = .test_units,
    unit_mode = "index",
    parallel_workers = 1L,       # 用户要求：不并行
    skip_existing = FALSE,
    fail_policy = "stop",
    worker_script = "run/study/run_study_batch_worker.R",
    shared_ck_alias = "ckm_attrition_flowchart"
  ),

  feishu = list(
    enable = FALSE,
    app_token = Sys.getenv("FEISHU_WORKPLAN_APP_TOKEN", "RBjfb2iwmamW14s4WhKcS7kwnie")
  ),

  plot = list(font_family = "Times New Roman")
)

pipeline_shared <- list(
  name = "ckm_cum_egdr_shared",
  blocks = c("ckm_stroke_data_ingest", "analysis_exclusion", "ckm_attrition_flowchart"),
  checkpoint = list(
    enable = TRUE,
    dir = file.path(.batch_project_root, "checkpoints", "_shared", "main")
  )
)

pipeline_unit <- list(
  name = "ckm_cum_egdr_unit",
  blocks = c(
    "cum_exposure_build",
    "kmeans_elbow_bivar",
    "kmeans_trajectory_panels",
    "table1_by_class_ckm",
    "logistic_cum_index_bundle",
    "rcs_ckm_strata_panels",
    "table3_class_subgroup_forests",
    "sensitivity_cox_mice_bundle",
    "ckm_pub_finalize"
  ),
  checkpoint = list(enable = TRUE)
)

config$pipeline_unit <- pipeline_unit
pipeline <- pipeline_shared
