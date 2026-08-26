###############################################################################
#  config_trajectory_prognosis_apri_batch.R — 轨迹预后 APRI 多指标 × 双库批量
#  入口: run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R
#  决策树: Decisiontree/decision_tree_trajectory_prognosis_apri.md
#
#  产出根目录（与发病 incidence batch 相同约定）:
#    {BLOCK_RESULT_ROOT}/09_HF/Prognosis_Trajectory_38882552_n1000/
#      checkpoints/ _shared/ by_index/ by_unit/ logs/
#    原始数据仍读全量 cohort 目录:
#    {BLOCK_RESULT_ROOT}/09_HF/Prognosis_Trajectory_38882552/data/
###############################################################################

source("configs/config_trajectory_prognosis_apri.R")
source("configs/indices/composite_index_vars.R")

# 复合指标不插补：共享层 index 算出的列 + 28天宽表均保持原始/日度实测值
config$imputation$exclude_from_mice_cols <- unique(c(
  as.character(config$imputation$exclude_from_mice_cols %||% character(0)),
  .composite_index_vars
))
config$imputation$table_s1_exclude_vars <- unique(c(
  as.character(config$imputation$table_s1_exclude_vars %||% character(0)),
  .composite_index_vars
))

# batch 覆盖：产出写到网络盘项目根（非仓库内 Output/）
config$project$output_dir <- .batch_project_root
config$project$name       <- "Prognosis_Trajectory_38882552_n1000"
config$project$database   <- "eICU+MIMIC"

# ── 开发/调试：每库随机抽取 1000 人跑全流程（共享层 + 各指标 worker 均生效）──
config$data_clean$subsample_n    <- 1000L
config$data_clean$subsample_seed <- 38882552L

# ── 双库各自独立的原始数据路径（eICU 主库 / MIMIC 验证库）────────────────────
config$dual_db <- list(
  primary = list(
    name = "eICU", db_type = "eicu",
    rawdata_path = file.path(.batch_data_root, "eicu/D02_Original_AKD.RData"),
    rawdata_obj  = "data_imp",
    id_column    = "subject_id",
    lab_id_column = "patientunitstayid",
    output_subdir = file.path(.batch_project_root, "data/eicu"),
    lab_sources = list(
      files = list.files(
        file.path(.batch_data_root, "eicu/实验室指标"),
        pattern = "\\.csv$", full.names = TRUE
      )
    )
  ),
  secondary = list(
    name = "MIMIC", db_type = "mimic",
    rawdata_path = file.path(.batch_data_root, "mimic/D01_baseline_MIMIC.RData"),
    rawdata_obj  = "data_imp",
    id_column    = "subject_id",
    lab_id_column = "subject_id",
    output_subdir = file.path(.batch_project_root, "data/mimic"),
    lab_sources = list(
      path = file.path(.batch_data_root, "mimic/mimic-实验室指标-all-1~30天.csv")
    )
  )
)

# ── 28 天纵向指标（共享层）：不插补，仅保留 ≥2 天非空的受试者 ─────────────────
config$trajectory_calc_28d_index <- list(
  index_vars = NULL,
  index_group = "dual_safe",
  days = 1:28,
  min_non_na_days = 2L,
  restrict_to_baseline_ids = TRUE
)

# ── 每指标宽表 RData 路径模板：{db} 由 worker 按 eicu/mimic 替换 ─────────────
config$trajectory_jlcm$rawdata_path_template <- file.path(.batch_project_root, "data/{db}/12_{Index}.RData")
config$trajectory_jlcm$output_dir_template   <- file.path(.batch_project_root, "data/{db}")

# ── 按指标并行批量配置（与发病 batch：index_vars=NULL + index_group=dual_safe）──
config$trajectory_batch <- list(
  output_base      = .batch_project_root,
  shared_ck_base   = file.path(.batch_project_root, "checkpoints", "_shared"),
  index_ck_base    = file.path(.batch_project_root, "checkpoints", "by_index"),
  db_seq           = c("eicu", "mimic"),
  index_vars       = NULL,
  index_group      = "dual_safe",
  parallel_workers = "auto",
  worker_script    = "run/trajectory_prognosis/run_trajectory_prognosis_apri_batch_worker.R"
)

# ── 共享层 pipeline（与发病一致：清洗→映射→基线指标→28天宽表；插补在 worker）──
pipeline_shared <- list(
  name = "trajectory_prognosis_apri_shared",
  blocks = c("data_clean", "column_mapping", "index", "trajectory_calc_28d_index"),
  checkpoint = list(enable = TRUE)
)

# ── 指标层 pipeline（从共享 checkpoint 续跑：插补→预后前缀→JLCM→图表）──────
pipeline_unit_prefix <- list(
  name = "trajectory_prognosis_apri_unit_prefix",
  blocks = c(
    "imputation",
    "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final"
  ),
  render_tables_after = c(
    "imputation", "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final"
  ),
  checkpoint = list(enable = TRUE)
)

pipeline_unit_suffix <- list(
  name = "trajectory_prognosis_apri_unit_suffix",
  blocks = c(
    "trajectory_jlcm",
    "trajectory_baseline_by_class",
    "trajectory_plot_jlcm",
    "trajectory_km_class",
    "trajectory_dynpred",
    "trajectory_dynpred_individual",
    "trajectory_piecewise_cox",
    "trajectory_weibull_compare",
    "trajectory_subgroup_class",
    "trajectory_chisq"
  ),
  checkpoint = list(enable = TRUE)
)

# 兼容旧引用：完整链条 = prefix + suffix
pipeline_unit <- list(
  name = "trajectory_prognosis_apri_unit",
  blocks = c(pipeline_unit_prefix$blocks, pipeline_unit_suffix$blocks),
  render_tables_after = pipeline_unit_prefix$render_tables_after,
  checkpoint = list(enable = TRUE)
)

config$trajectory_jlcm$dual_db_harmonize_survival_covariates <- TRUE

config$trajectory_batch$pipeline_unit_prefix <- pipeline_unit_prefix
config$trajectory_batch$pipeline_unit_suffix <- pipeline_unit_suffix

pipeline <- pipeline_shared
