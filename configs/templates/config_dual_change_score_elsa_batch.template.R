###############################################################################
#  config_dual_change_score_elsa_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改）
#  原始实例已移至 configs/_archive/config_dual_change_score_elsa_batch.R
###############################################################################

source("configs/_archive/config_dual_change_score_elsa.R")

.batch_batch_root <- "Output/Dual_Change_Score_ELSA_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Dual_Change_Score_ELSA_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("Dep_to_Mem", "Mem_to_Dep", "Verbal_fluency"),
  unit_mode = "branch",
  branch_map = list(
    Dep_to_Mem = list(
      blocks = c("dcs_bivariate_dcsm", "dcs_depression_to_memory", "dcs_sensitivity", "dcs_literature_validate"),
      row_filter = "TRUE"
    ),
    Mem_to_Dep = list(blocks = c("dcs_bivariate_dcsm", "dcs_memory_to_depression", "dcs_sensitivity"), row_filter = "TRUE"),
    Verbal_fluency = list(blocks = c("dcs_verbal_fluency", "dcs_sensitivity"), row_filter = "TRUE")
  ),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "dcs_descriptive"
)

pipeline_shared <- list(
  name = "dcs_shared",
  blocks = c("data_clean", "imputation", "dcs_data_prep", "dcs_descriptive"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "dcs_unit",
  blocks = c("dcs_bivariate_dcsm", "dcs_depression_to_memory", "dcs_memory_to_depression",
             "dcs_verbal_fluency", "dcs_sensitivity", "dcs_literature_validate"),
  checkpoint = list(enable = TRUE)
)

config$pipeline_unit <- pipeline_unit
pipeline <- pipeline_shared
