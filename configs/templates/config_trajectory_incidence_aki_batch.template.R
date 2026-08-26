###############################################################################
#  config_trajectory_incidence_aki_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改）
#  原始实例已移至 configs/_archive/config_trajectory_incidence_aki_batch.R
###############################################################################

###############################################################################
#  config_trajectory_incidence_aki_batch.R — 轨迹发病批量（MIMIC / eICU 并行）
#  入口: run/trajectory_incidence/run_trajectory_incidence_aki_batch.R
###############################################################################

source("configs/_archive/config_trajectory_incidence_aki.R")

.batch_batch_root <- "Output/Trajectory_Incidence_AKI_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Trajectory_Incidence_AKI_Batch"

config$study_batch <- list(
  output_base      = .batch_batch_root,
  units            = c("MIMIC", "eICU"),
  unit_mode        = "cohort",
  unit_col         = "Cohort",
  cohort_worker_blocks = c(
    "trajectory_wide_to_long", "trajectory_lcmm_fit", "trajectory_outcome_models"
  ),
  parallel_workers = "auto",
  skip_existing    = TRUE,
  worker_script    = "run/study/run_study_batch_worker.R",
  shared_ck_alias  = "imputation"
)

pipeline_shared <- list(
  name = "trajectory_incidence_shared",
  blocks = c("data_clean", "imputation"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "trajectory_incidence_unit",
  blocks = c("trajectory_wide_to_long", "trajectory_lcmm_fit", "trajectory_outcome_models"),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
