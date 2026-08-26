###############################################################################
#  config_trajectory_prognosis_plt_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改）
#  原始实例已移至 configs/_archive/config_trajectory_prognosis_plt_batch.R
###############################################################################

###############################################################################
#  config_trajectory_prognosis_plt_batch.R — 轨迹预后批量（eICU / MIMIC 并行）
#  入口: run/trajectory_prognosis/run_trajectory_prognosis_plt_batch.R
###############################################################################

source("configs/_archive/config_trajectory_prognosis_plt.R")

.batch_batch_root <- "Output/Trajectory_Prognosis_Platelet_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Trajectory_Prognosis_Platelet_Batch"

config$study_batch <- list(
  output_base      = .batch_batch_root,
  units            = c("eICU", "MIMIC"),
  unit_mode        = "cohort",
  unit_col         = "Cohort",
  cohort_worker_blocks = c(
    "trajectory_prepare_wide_rdata",
    "trajectory_jlcm",
    "trajectory_plot_jlcm",
    "trajectory_chisq",
    "trajectory_piecewise_cox",
    "trajectory_dynpred",
    "trajectory_weibull_compare"
  ),
  parallel_workers = "auto",
  skip_existing    = TRUE,
  worker_script    = "run/study/run_study_batch_worker.R",
  shared_ck_alias  = "trajectory_jlcm_discovery_validate"
)

pipeline_shared <- list(
  name = "trajectory_prognosis_shared",
  blocks = c(
    "data_clean", "column_mapping", "imputation",
    "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multicollinearity_final",
    "trajectory_jlcm_discovery_validate"
  ),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "trajectory_prognosis_unit",
  blocks = c(
    "trajectory_prepare_wide_rdata",
    "trajectory_jlcm",
    "trajectory_plot_jlcm",
    "trajectory_chisq",
    "trajectory_piecewise_cox",
    "trajectory_dynpred",
    "trajectory_weibull_compare"
  ),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
