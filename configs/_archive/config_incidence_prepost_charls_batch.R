source("configs/config_incidence_prepost_charls.R")

.batch_batch_root <- "Output/Incidence_PrePost_CHARLS_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Incidence_PrePost_CHARLS_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("Global", "Episodic_memory", "Visuospatial", "Attention_calc"),
  unit_mode = "branch",
  branch_map = list(
    Global = list(
      blocks = c("prepost_lmm_fit", "prepost_domain_slopes", "prepost_subgroup_age",
                 "prepost_sensitivity", "prepost_visualize", "prepost_literature_validate"),
      row_filter = "TRUE"
    ),
    Episodic_memory = list(blocks = c("prepost_domain_slopes", "prepost_subgroup_age"), row_filter = "TRUE"),
    Visuospatial = list(blocks = c("prepost_domain_slopes", "prepost_subgroup_age"), row_filter = "TRUE"),
    Attention_calc = list(blocks = c("prepost_domain_slopes"), row_filter = "TRUE")
  ),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "prepost_descriptive"
)

pipeline_shared <- list(
  name = "prepost_shared",
  blocks = c("data_clean", "imputation", "prepost_data_prep", "prepost_descriptive"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "prepost_unit",
  blocks = c("prepost_lmm_fit", "prepost_domain_slopes", "prepost_subgroup_age",
             "prepost_sensitivity", "prepost_visualize", "prepost_literature_validate"),
  checkpoint = list(enable = TRUE)
)

config$pipeline_unit <- pipeline_unit
pipeline <- pipeline_shared
