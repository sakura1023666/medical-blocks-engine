###############################################################################
#  config_cdc_wonder_dobbs_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改）
#  原始实例已移至 configs/_archive/config_cdc_wonder_dobbs_batch.R
###############################################################################

source("configs/_archive/config_cdc_wonder_dobbs.R")

.batch_batch_root <- "Output/CDC_WONDER_Dobbs_CITS_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "CDC_WONDER_Dobbs_CITS_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("Nonliving_birth", "Congenital_anomaly", "Maternal_morbidity"),
  unit_mode = "branch",
  branch_map = list(
    Nonliving_birth    = list(blocks = c("cits_model_full", "cits_plot"), row_filter = NULL),
    Congenital_anomaly = list(blocks = c("cits_model_full", "cits_sensitivity_extended", "cits_plot"), row_filter = NULL),
    Maternal_morbidity = list(blocks = c("cits_model_full", "cits_plot"), row_filter = NULL)
  ),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "cits_aggregate_monthly"
)

pipeline_shared <- list(
  name = "cdc_shared",
  blocks = c("data_clean", "cdc_wonder_fetch", "cits_aggregate_monthly", "cits_publication_tables"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "cdc_unit",
  blocks = c("cits_model_full", "cits_sensitivity_extended", "cits_plot"),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
