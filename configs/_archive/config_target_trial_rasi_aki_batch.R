source("configs/config_target_trial_rasi_aki.R")

.batch_batch_root <- "Output/Target_Trial_RASi_AKI_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Target_Trial_RASi_AKI_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("Overall", "CRDS", "MIMIC", "Death_180d"),
  unit_mode = "branch",
  branch_map = list(
    Overall = list(
      blocks = c("tte_weighting", "tte_pooled_logistic", "tte_risk_difference", "tte_bootstrap_ci",
                 "tte_stratified", "tte_sensitivity", "tte_literature_validate"),
      row_filter = "TRUE"
    ),
    CRDS = list(blocks = c("tte_pooled_logistic", "tte_risk_difference"), row_filter = "Database == 'CRDS'"),
    MIMIC = list(blocks = c("tte_pooled_logistic", "tte_risk_difference"), row_filter = "Database == 'MIMIC'"),
    Death_180d = list(blocks = c("tte_pooled_logistic", "tte_risk_difference"), row_filter = "TRUE")
  ),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "tte_descriptive"
)

pipeline_shared <- list(
  name = "tte_shared",
  blocks = c("data_clean", "imputation", "tte_data_prep", "tte_descriptive"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "tte_unit",
  blocks = c("tte_weighting", "tte_pooled_logistic", "tte_risk_difference", "tte_bootstrap_ci",
             "tte_stratified", "tte_sensitivity", "tte_literature_validate"),
  checkpoint = list(enable = TRUE)
)

config$pipeline_unit <- pipeline_unit
config$target_trial$active_outcome <- "Death_30d"
pipeline <- pipeline_shared
