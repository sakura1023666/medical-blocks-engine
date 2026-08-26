###############################################################################
#  config_ai_medical_qa_cot_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改）
#  原始实例已移至 configs/_archive/config_ai_medical_qa_cot_batch.R
###############################################################################

source("configs/_archive/config_ai_medical_qa_cot.R")

.batch_batch_root <- "Output/AI_Medical_QA_CoT_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "AI_Medical_QA_CoT_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("MedQA", "MedMCQA", "EHRNoteQA"),
  unit_mode = "branch",
  branch_map = list(
    MedQA     = list(row_filter = "dataset == 'MedQA'"),
    MedMCQA   = list(row_filter = "dataset == 'MedMCQA'"),
    EHRNoteQA = list(row_filter = "dataset == 'EHRNoteQA'")
  ),
  finalize_blocks = c("ai_qa_dataset_summary", "ai_qa_model_ranking", "ai_qa_table4_validate"),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "ai_qa_prepare"
)

pipeline_shared <- list(
  name = "ai_qa_shared",
  blocks = c("ai_qa_prepare", "ai_qa_prompt_templates"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "ai_qa_unit",
  blocks = c("ai_qa_cot_eval", "ai_qa_prompt_compare", "ai_qa_statistics"),
  checkpoint = list(enable = TRUE)
)

config$pipeline_unit <- pipeline_unit
pipeline <- pipeline_shared
