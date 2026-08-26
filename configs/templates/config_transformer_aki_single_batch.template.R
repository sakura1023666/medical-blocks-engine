###############################################################################
#  config_transformer_aki_single_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改）
#  原始实例已移至 configs/_archive/config_transformer_aki_single_batch.R
###############################################################################

source("configs/_archive/config_transformer_aki_single.R")

.batch_batch_root <- "Output/Transformer_AKI_Single_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Transformer_AKI_Single_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("Internal", "LSTM_baseline", "MLP_baseline"),
  unit_mode = "branch",
  branch_map = list(
    Internal = list(
      blocks = c("trf_causal_discovery", "trf_train_eval", "trf_calibration",
                 "trf_early_detection", "trf_multicenter_val", "trf_external_val",
                 "trf_sensitivity", "trf_literature_validate"),
      row_filter = "TRUE"
    ),
    LSTM_baseline = list(blocks = c("trf_train_eval", "trf_calibration"), row_filter = "TRUE"),
    MLP_baseline = list(blocks = c("trf_train_eval", "trf_calibration"), row_filter = "TRUE")
  ),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "trf_data_prep"
)

pipeline_shared <- list(
  name = "trf_shared",
  blocks = c("data_clean", "imputation", "trf_data_prep", "trf_causal_discovery"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "trf_unit",
  blocks = c("trf_train_eval", "trf_calibration", "trf_early_detection", "trf_multicenter_val",
             "trf_external_val", "trf_sensitivity", "trf_literature_validate"),
  checkpoint = list(enable = TRUE)
)

config$pipeline_unit <- pipeline_unit
config$transformer_aki$model_variant <- "transformer"
pipeline <- pipeline_shared
