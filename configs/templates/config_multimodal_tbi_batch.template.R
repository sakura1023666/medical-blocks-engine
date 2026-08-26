###############################################################################
#  config_multimodal_tbi_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改）
#  原始实例已移至 configs/_archive/config_multimodal_tbi_batch.R
###############################################################################

###############################################################################
#  config_multimodal_tbi_batch.R — 多模态 TBI 批量（临床/组学/融合并行）
#  入口: run/multimodal/run_multimodal_tbi_batch.R
###############################################################################

source("configs/_archive/config_multimodal_tbi.R")

.batch_batch_root <- "Output/Multimodal_TBI_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Multimodal_TBI_Batch"

config$study_batch <- list(
  output_base      = .batch_batch_root,
  units            = c("clinical", "omics", "fusion"),
  unit_mode        = "modality",
  parallel_workers = "auto",
  skip_existing    = TRUE,
  worker_script    = "run/study/run_study_batch_worker.R",
  shared_ck_alias  = "imputation"
)

pipeline_shared <- list(
  name = "multimodal_shared",
  blocks = c("data_clean", "imputation"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "multimodal_unit",
  blocks = c("multimodal_early_fusion"),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
