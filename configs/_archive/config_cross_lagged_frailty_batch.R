source("configs/config_cross_lagged_frailty.R")

.batch_batch_root <- "Output/Cross_Lagged_Frailty_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Cross_Lagged_Frailty_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("HRS", "CHARLS", "SHARE", "ELSA", "MHAS"),
  unit_mode = "cohort",
  unit_col = "Cohort",
  cohort_worker_blocks = c(
    "cross_lagged_cox_frailty", "cross_lagged_mediation", "cross_lagged_mediation_bootstrap",
    "cross_lagged_panel_network", "cross_lagged_frailty_transition",
    "cross_lagged_subgroup", "cross_lagged_subgroup_extended",
    "cross_lagged_sensitivity", "cross_lagged_biomarker_cor"
  ),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "cross_lagged_fi_compute"
)

pipeline_shared <- list(
  name = "cross_lagged_shared",
  blocks = c("data_clean", "cross_lagged_fi_compute", "cross_lagged_km", "cross_lagged_meta_merge"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "cross_lagged_unit",
  blocks = c("cross_lagged_cox_frailty", "cross_lagged_mediation", "cross_lagged_mediation_bootstrap",
             "cross_lagged_panel_network", "cross_lagged_frailty_transition",
             "cross_lagged_subgroup", "cross_lagged_subgroup_extended",
             "cross_lagged_sensitivity", "cross_lagged_biomarker_cor"),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
