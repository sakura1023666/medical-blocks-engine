source("configs/config_ai_clinical_cdm.R")

.batch_batch_root <- "Output/AI_Clinical_CDM_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "AI_Clinical_CDM_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("appendicitis", "cholecystitis", "diverticulitis", "pancreatitis"),
  unit_mode = "branch",
  branch_map = list(
    appendicitis = list(blocks = "ai_llm_evaluate", row_filter = "true_diagnosis == 'appendicitis'"),
    cholecystitis = list(blocks = "ai_llm_evaluate", row_filter = "true_diagnosis == 'cholecystitis'"),
    diverticulitis = list(blocks = "ai_llm_evaluate", row_filter = "true_diagnosis == 'diverticulitis'"),
    pancreatitis = list(blocks = "ai_llm_evaluate", row_filter = "true_diagnosis == 'pancreatitis'")
  ),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "ai_cases_prepare"
)

pipeline_shared <- list(
  name = "ai_shared",
  blocks = c("ai_cases_prepare", "ai_guideline_audit", "ai_lab_interpret", "ai_order_robustness"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "ai_unit",
  blocks = c("ai_llm_evaluate", "ai_llm_multimodel", "ai_multiround_sim",
             "ai_reader_comparison", "ai_reader_study"),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
