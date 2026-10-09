###############################################################################
# config_pa_mobility_cognitive_batch.R — CHARLS / NHANES 双 unit batch
###############################################################################

source("configs/config_pa_mobility_cognitive.R")

.batch_batch_root <- "G:/02block_result/02_Cognitive_impairment/pa_mobility_cognitive_charls_nhanes"
config$project$output_dir <- .batch_batch_root
config$project$name <- "PA_Mobility_Cognitive_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("CHARLS", "NHANES"),
  unit_mode = "branch",
  branch_map = list(
    CHARLS = list(
      row_filter = "TRUE",
      blocks = c(
        "pamob_assemble_charls", "pamob_cognition_long", "pamob_baseline_charls",
        "pamob_lmm_global", "pamob_lmm_episodic", "pamob_contrast_preset",
        "pamob_traj_plot", "pamob_sensitivity_charls",
        "pamob_flowchart", "pamob_concept_fig1"
      )
    ),
    NHANES = list(
      row_filter = "TRUE",
      blocks = c(
        "pamob_assemble_nhanes", "pamob_baseline_nhanes",
        "pamob_svy_dsst", "pamob_svy_nfl", "pamob_panel_fig4",
        "pamob_sensitivity_nhanes"
      )
    )
  ),
  finalize_blocks = c("pamob_pub_export"),
  parallel_workers = 1L,
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "pamob_feasibility"
)

pipeline_shared <- list(
  name = "pamob_shared",
  blocks = c("pamob_feasibility"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "pamob_unit",
  blocks = c(
    "pamob_assemble_charls", "pamob_cognition_long", "pamob_baseline_charls",
    "pamob_lmm_global", "pamob_lmm_episodic", "pamob_contrast_preset",
    "pamob_traj_plot", "pamob_sensitivity_charls",
    "pamob_flowchart", "pamob_concept_fig1"
  ),
  checkpoint = list(enable = TRUE)
)

config$pipeline_unit <- pipeline_unit
pipeline <- pipeline_shared
