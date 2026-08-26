source("configs/config_cftraj_charls.R")

.batch_batch_root <- "Output/Causal_Forest_Trajectory_CHARLS_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Causal_Forest_Trajectory_CHARLS_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("Global", "Episodic"),
  unit_mode = "branch",
  branch_map = list(
    Global   = list(row_filter = "TRUE"),
    Episodic = list(row_filter = "TRUE")
  ),
  finalize_blocks = c("cftraj_trajectory_validate"),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "cftraj_wide_to_long"
)

pipeline_shared <- list(
  name = "cftraj_shared",
  blocks = c("data_clean", "imputation", "cftraj_circs_compute", "cftraj_wide_to_long"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "cftraj_unit",
  blocks = c(
    "cftraj_lcmm_fit", "cftraj_lcmm_episodic", "cftraj_multinomial", "cftraj_causal_forest",
    "cftraj_subgroup_viz", "cftraj_sensitivity"
  ),
  checkpoint = list(enable = TRUE)
)

config$pipeline_unit <- pipeline_unit
pipeline <- pipeline_shared
