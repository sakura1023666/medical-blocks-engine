###############################################################################
#  config_network_temperature_adolescent_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改）
#  原始实例已移至 configs/_archive/config_network_temperature_adolescent_batch.R
###############################################################################

source("configs/_archive/config_network_temperature_adolescent.R")

.batch_batch_root <- "Output/Network_Temperature_Adolescent_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Network_Temperature_Adolescent_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("ABCD", "ALSPAC", "MCS"),
  unit_mode = "branch",
  branch_map = list(
    ABCD   = list(row_filter = "Cohort == 'ABCD'"),
    ALSPAC = list(row_filter = "Cohort == 'ALSPAC'"),
    MCS    = list(row_filter = "Cohort == 'MCS'")
  ),
  finalize_blocks = c("network_temp_literature_validate"),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "network_temp_prepare_long"
)

pipeline_shared <- list(
  name = "network_temp_shared",
  blocks = c("data_clean", "imputation", "network_temp_prepare_long"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "network_temp_unit",
  blocks = c(
    "network_temp_compute", "network_temp_ggm_fit", "network_temp_mixed_model",
    "network_temp_centrality", "network_temp_trajectory",
    "network_temp_cohort_summary", "network_temp_outcome_assoc"
  ),
  checkpoint = list(enable = TRUE)
)

config$pipeline_unit <- pipeline_unit
pipeline <- pipeline_shared
