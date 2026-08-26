###############################################################################
#  config_environment_cd_osteo_batch.R — 血镉×骨质疏松 NHANES 批量（RCS/亚组/中介并行）
#  入口: run/environment/run_environment_cd_osteo_batch.R
###############################################################################

source("configs/config_environment_cd_osteo_nhanes.R")

.batch_batch_root <- "Output/Environment_Cd_Osteoporosis_NHANES_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Cd_Osteoporosis_NHANES_Batch"

config$study_batch <- list(
  output_base       = .batch_batch_root,
  project_root      = NULL,
  units             = c("rcs", "subgroup", "mediation_CRP", "mediation_Albumin"),
  unit_mode         = "branch",
  parallel_workers  = "auto",
  skip_existing     = TRUE,
  worker_script     = "run/study/run_study_batch_worker.R",
  shared_ck_alias   = "logistic_quartile_nhanes_weighted",
  branch_map = list(
    rcs = list(blocks = "rcs_nhanes"),
    subgroup = list(blocks = "subgroup_nhanes_weighted"),
    mediation_CRP = list(blocks = "mediation_nhanes_weighted", mediator = "CRP"),
    mediation_Albumin = list(blocks = "mediation_nhanes_weighted", mediator = "Albumin")
  )
)

pipeline_shared <- list(
  name = "environment_cd_osteo_shared",
  blocks = c(
    "data_clean", "column_mapping", "imputation",
    "environment_single_exposure_transform",
    "cutoff", "obj", "baseline_nhanes",
    "univariate_nhanes", "multicollinearity_nhanes_screen", "multivariate_nhanes",
    "multicollinearity_nhanes_final",
    "logistic_quartile_nhanes_weighted"
  ),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "environment_cd_osteo_unit",
  blocks = character(0),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
