###############################################################################
#  config_bayesian_comorbidity_batch.R — 共病贝叶斯批量（三队列并行）
#  入口: run/bayesian_comorbidity/run_bayesian_comorbidity_batch.R
###############################################################################

source("configs/config_bayesian_comorbidity.R")

.batch_batch_root <- "Output/Bayesian_Comorbidity_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Bayesian_Comorbidity_Batch"

config$study_batch <- list(
  output_base      = .batch_batch_root,
  units            = c("BLSA", "InCHIANTI", "NHANES"),
  unit_mode        = "cohort",
  unit_col         = "Cohort",
  cohort_worker_blocks = c(
    "bayesian_bodn", "bayesian_body_clock",
    "bayesian_bsc_aging", "bayesian_outcome_validate"
  ),
  parallel_workers = "auto",
  skip_existing    = TRUE,
  worker_script    = "run/study/run_study_batch_worker.R",
  shared_ck_alias  = "imputation"
)

pipeline_shared <- list(
  name = "bayesian_shared",
  blocks = c("data_clean", "imputation"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "bayesian_unit",
  blocks = c(
    "bayesian_bodn", "bayesian_body_clock",
    "bayesian_bsc_aging", "bayesian_outcome_validate"
  ),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
