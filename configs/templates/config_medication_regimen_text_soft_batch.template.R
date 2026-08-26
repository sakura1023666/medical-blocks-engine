###############################################################################
#  config_medication_regimen_text_soft_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改）
#  原始实例已移至 configs/_archive/config_medication_regimen_text_soft_batch.R
###############################################################################

source("configs/_archive/config_medication_regimen_text_soft.R")

.batch_batch_root <- "Output/Medication_Regimen_TEXT_SOFT_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Medication_Regimen_TEXT_SOFT_Batch"
config$stepp_prognosis$overall$window_size <- 15L
config$stepp_prognosis$overall$step_size <- 5L
config$stepp_prognosis$by_group$window_size <- 10L
config$stepp_prognosis$by_group$step_size <- 3L

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("TEXT_Chemo", "SOFT_Chemo", "No_Chemo"),
  unit_mode = "branch",
  branch_map = list(
    TEXT_Chemo = list(blocks = c("medication_km_treatment", "stepp_prognosis"), row_filter = "Trial == 'TEXT' & Chemotherapy == 'Yes'"),
    SOFT_Chemo = list(blocks = c("medication_km_treatment", "stepp_prognosis"), row_filter = "Trial == 'SOFT' & Chemotherapy == 'Yes'"),
    No_Chemo   = list(blocks = c("medication_km_treatment", "stepp_prognosis"), row_filter = "Chemotherapy == 'No'")
  ),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "medication_composite_risk"
)

pipeline_shared <- list(
  name = "medication_shared",
  blocks = c("data_clean", "imputation", "medication_composite_risk",
             "medication_descriptive", "medication_chemo_strata",
             "medication_trial_comparisons", "medication_stepp_strata",
             "medication_literature_targets"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "medication_unit",
  blocks = c("medication_km_treatment", "stepp_prognosis"),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
