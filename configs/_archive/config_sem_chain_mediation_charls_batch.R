source("configs/config_sem_chain_mediation_charls.R")

.batch_batch_root <- "Output/SEM_Chain_Mediation_CHARLS_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "SEM_Chain_Mediation_CHARLS_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("Overall", "Male", "Female"),
  unit_mode = "branch",
  branch_map = list(
    Overall = list(blocks = c("sem_chain_mediation", "sem_cox_chain_mediation", "sem_stratified", "sem_sensitivity", "sem_literature_validate"), row_filter = "TRUE"),
    Male    = list(blocks = c("sem_chain_mediation", "sem_cox_chain_mediation", "sem_stratified", "sem_sensitivity"), row_filter = "Sex == 'Male'"),
    Female  = list(blocks = c("sem_chain_mediation", "sem_cox_chain_mediation", "sem_stratified", "sem_sensitivity"), row_filter = "Sex == 'Female'")
  ),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "sem_path_lavaan"
)

pipeline_shared <- list(
  name = "sem_shared",
  blocks = c(
    "data_clean", "imputation", "sem_data_prep", "sem_descriptive",
    "sem_cox_baseline", "sem_path_lavaan"
  ),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "sem_unit",
  blocks = c("sem_chain_mediation", "sem_cox_chain_mediation", "sem_stratified", "sem_sensitivity", "sem_literature_validate"),
  checkpoint = list(enable = TRUE)
)

config$pipeline_unit <- pipeline_unit
pipeline <- pipeline_shared
