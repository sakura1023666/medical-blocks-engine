###############################################################################
#  config_multimorbidity_additive_batch.template.R — 多队列批跑壳
###############################################################################

source("configs/templates/config_multimorbidity_additive.template.R")

.batch_batch_root <- "Output/Multimorbidity_Depression_AO_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Multimorbidity_Additive_Batch"
config$project$database <- "CHARLS+ELSA+HRS+MHAS"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("CHARLS", "ELSA", "HRS", "MHAS"),
  unit_mode = "cohort",
  unit_col = "Cohort",
  cohort_worker_blocks = c(
    "multimorbidity_define_exposures",
    "multimorbidity_cognition_zscore",
    "multimorbidity_baseline_category",
    "multimorbidity_kml3d_trajectory",
    "multimorbidity_gee_cognition",
    "multimorbidity_gee_trajectory",
    "multimorbidity_sensitivity_suite",
    "multimorbidity_graphical_abstract"
  ),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R"
)

pipeline_shared <- list(
  name = "multimorbidity_shared",
  blocks = c("data_clean", "imputation"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "multimorbidity_unit",
  blocks = config$study_batch$cohort_worker_blocks,
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
