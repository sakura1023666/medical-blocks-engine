###############################################################################
#  config_trajectory_prognosis_apri_single.R — 单指标双库全流程（文献图表对齐）
#  指标: NLR（trajectory_apri 子集首位；JLCM 已验证可收敛）
#  产出: {BLOCK_RESULT_ROOT}/09_HF/Prognosis_Trajectory_38882552_single/
#  入口:
#    Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R \
#      --config configs/config_trajectory_prognosis_apri_single.R \
#      --only-index NLR --workers 1 --no-skip
###############################################################################

source("configs/config_trajectory_prognosis_apri.R")
source("configs/indices/composite_index_vars.R")

.single_root <- file.path(.block_result_root, "09_HF/Prognosis_Trajectory_38882552_single")
.batch_project_root <- .single_root
.batch_ck_root      <- file.path(.single_root, "checkpoints")

config$project$output_dir <- .single_root
config$project$name       <- "Prognosis_Trajectory_38882552_single"

config$data_clean$subsample_n    <- 1000L
config$data_clean$subsample_seed <- 38882552L

config$dual_db <- list(
  primary = list(
    name = "eICU", db_type = "eicu",
    rawdata_path = file.path(.batch_data_root, "eicu/D02_Original_AKD.RData"),
    rawdata_obj  = "data_imp",
    id_column    = "subject_id",
    lab_id_column = "patientunitstayid",
    output_subdir = file.path(.single_root, "data/eicu"),
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
    output_subdir = file.path(.single_root, "data/mimic"),
    lab_sources = list(
      path = file.path(.batch_data_root, "mimic/mimic-实验室指标-all-1~30天.csv")
    )
  )
)

config$imputation$exclude_from_mice_cols <- unique(c(
  as.character(config$imputation$exclude_from_mice_cols %||% character(0)),
  .composite_index_vars
))
# 复合指标：仅当前暴露指标由 trajectory_batch_patch_config_for_index 写入 index$only / force_keep
# Table S1 在 index 之前生成，不含复合列
config$imputation$table_s1_exclude_vars <- unique(c(
  as.character(config$imputation$table_s1_exclude_vars %||% character(0))
))

config$trajectory_jlcm$rawdata_path_template <- file.path(.single_root, "data/{db}/12_{Index}.RData")
config$trajectory_jlcm$output_dir_template   <- file.path(.single_root, "data/{db}")

# 共享层仅计算 NLR 宽表（节省时间）
config$trajectory_calc_28d_index$index_group <- NULL
config$trajectory_calc_28d_index$index_vars  <- c("NLR")

config$trajectory_batch <- list(
  output_base      = .single_root,
  shared_ck_base   = file.path(.single_root, "checkpoints", "_shared"),
  index_ck_base    = file.path(.single_root, "checkpoints", "by_index"),
  db_seq           = c("eicu", "mimic"),
  index_vars       = c("NLR"),
  index_group      = NULL,
  parallel_workers = 1L,
  worker_script    = "run/trajectory_prognosis/run_trajectory_prognosis_apri_batch_worker.R"
)

# 与 Fig3.R 一致：群体动态预测评估时点 day 4/7/14/21
paper_landmarks <- c(4, 7, 14, 21)
for (blk in c("trajectory", "trajectory_dynpred")) {
  if (!is.null(config[[blk]])) {
    config[[blk]]$jlcm$assessment_times <- paper_landmarks
  }
}
config$trajectory_weibull_compare$include_youden_metrics <- TRUE
# 与 run_fig_APRI_v2.R / run_FigS7_APRI_v2.R 一致：landmark 评估时点 = 4..14 天
config$trajectory_weibull_compare$landmarks <- 4:14

# 关键图表缺失时必须失败（避免 silent skip）
for (blk in c("trajectory_plot_jlcm", "trajectory_dynpred", "trajectory_piecewise_cox",
              "trajectory_subgroup_class")) {
  if (!is.null(config[[blk]])) {
    config[[blk]]$pause_enable <- TRUE
    if (blk == "trajectory_plot_jlcm") {
      config[[blk]]$pause_on_no_figures <- TRUE
    } else {
      config[[blk]]$pause_on_no_output <- TRUE
    }
  }
}
config$trajectory_dynpred$pause_on_no_output <- TRUE
config$trajectory_dynpred$pause_enable <- TRUE

config$feishu$enable <- FALSE

pipeline_shared <- list(
  name = "trajectory_prognosis_apri_shared_single",
  blocks = c("data_clean", "column_mapping", "index", "trajectory_calc_28d_index"),
  checkpoint = list(enable = TRUE)
)

pipeline_unit <- list(
  name = "trajectory_prognosis_apri_unit_single",
  blocks = c(
    "imputation",
    "index",
    "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final",
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
  render_tables_after = c(
    "imputation", "index", "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final"
  ),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
