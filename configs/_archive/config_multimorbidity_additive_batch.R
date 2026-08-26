###############################################################################
#  config_multimorbidity_additive_batch.R — 多病叠加批量（CHARLS/ELSA 并行 GEE）
#  入口: run/multimorbidity/run_multimorbidity_additive_batch.R
###############################################################################

source("configs/config_multimorbidity_additive.R")

.batch_batch_root <- "Output/Multimorbidity_Depression_AO_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Multimorbidity_Additive_Batch"

config$study_batch <- list(
  output_base      = .batch_batch_root,
  units            = c("CHARLS", "ELSA"),
  unit_mode        = "cohort",
  unit_col         = "Cohort",
  cohort_worker_blocks = "multimorbidity_gee_cognition",
  parallel_workers = "auto",
  skip_existing    = TRUE,
  worker_script    = "run/study/run_study_batch_worker.R",
  shared_ck_alias  = "multimorbidity_baseline_category"
)

pipeline_shared <- list(
  name = "multimorbidity_shared",
  blocks = c(
    "data_clean", "imputation",
    "multimorbidity_baseline_category"
  ),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "multimorbidity_unit",
  blocks = c("multimorbidity_gee_cognition"),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
