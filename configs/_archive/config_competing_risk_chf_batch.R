source("configs/config_competing_risk_chf.R")

.batch_batch_root <- "Output/Competing_Risk_CHF_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Competing_Risk_CHF_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("WHF", "Mortality", "Trajectory"),
  unit_mode = "branch",
  branch_map = list(
    WHF = list(blocks = c("competing_finegray", "competing_mixed_cox", "competing_models_123", "competing_rcs"), row_filter = NULL),
    Mortality = list(blocks = c("competing_cif_plot", "competing_cox_sensitivity", "competing_ph_calibration"), row_filter = NULL),
    Trajectory = list(blocks = c("competing_lmm_trajectory", "competing_lasso_screen", "competing_rf_screen", "competing_stratified"), row_filter = NULL)
  ),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "competing_tyg_compute"
)

pipeline_shared <- list(
  name = "competing_shared",
  blocks = c("data_clean", "competing_tyg_compute"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "competing_unit",
  blocks = c("competing_lmm_trajectory", "competing_lasso_screen", "competing_rf_screen",
             "competing_finegray", "competing_mixed_cox", "competing_models_123",
             "competing_stratified", "competing_rcs", "competing_cif_plot",
             "competing_cox_sensitivity", "competing_ph_calibration"),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
