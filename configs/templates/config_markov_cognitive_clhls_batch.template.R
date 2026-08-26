###############################################################################
#  config_markov_cognitive_clhls_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改）
#  原始实例已移至 configs/_archive/config_markov_cognitive_clhls_batch.R
###############################################################################

source("configs/_archive/config_markov_cognitive_clhls.R")

.batch_batch_root <- "Output/Markov_Cognitive_CLHLS_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Markov_Cognitive_CLHLS_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("APOE_High", "APOE_Low", "Lifestyle_High", "Lifestyle_Low"),
  unit_mode = "branch",
  branch_map = list(
    APOE_High      = list(blocks = c("markov_msm_fit", "markov_life_expectancy"), row_filter = "APOE_carrier == 'Carrier'"),
    APOE_Low       = list(blocks = c("markov_msm_fit", "markov_life_expectancy"), row_filter = "APOE_carrier == 'Non_carrier'"),
    Lifestyle_High = list(blocks = c("markov_apoe_lifestyle"), row_filter = "Healthy_lifestyle == 'High'"),
    Lifestyle_Low  = list(blocks = c("markov_apoe_lifestyle"), row_filter = "Healthy_lifestyle == 'Low'")
  ),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "markov_state_prep"
)

pipeline_shared <- list(
  name = "markov_shared",
  blocks = c("data_clean", "markov_state_prep", "markov_msm_fit", "markov_msm_bootstrap"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "markov_unit",
  blocks = c("markov_life_expectancy", "markov_life_table_figure",
             "markov_apoe_le_difference", "markov_apoe_lifestyle", "markov_sensitivity_glmm"),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
