###############################################################################
#  config_dynamic_causal_dual_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改）
#  原始实例已移至 configs/_archive/config_dynamic_causal_dual_batch.R
###############################################################################

###############################################################################
#  config_dynamic_causal_dual_batch.R — CMI×CVD 双队列批量（CHARLS/ELSA 并行 Cox）
#  入口: run/dynamic_causal/run_dynamic_causal_dual_batch.R
###############################################################################

source("configs/_archive/config_dynamic_causal_dual.R")

.batch_batch_root <- "Output/Dynamic_Causal_CMI_CVD_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Dynamic_Causal_CMI_CVD_Batch"

config$study_batch <- list(
  output_base      = .batch_batch_root,
  units            = c(
    "CHARLS_baseline", "ELSA_baseline",
    "CHARLS_change", "ELSA_change",
    "CHARLS_rcs", "ELSA_rcs"
  ),
  unit_mode        = "dynamic_cohort",
  unit_col         = "Cohort",
  parallel_workers = "auto",
  skip_existing    = TRUE,
  worker_script    = "run/study/run_study_batch_worker.R",
  shared_ck_alias  = "multicollinearity_final",
  run_meta_after   = TRUE
)

pipeline_shared <- list(
  name = "dynamic_causal_shared",
  blocks = c(
    "data_clean", "imputation",
    "dynamic_causal_index_compute",
    "baseline_binary", "univariate_prognosis", "multicollinearity_screen", "multivariate_prognosis", "multicollinearity_final"
  ),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "dynamic_causal_unit",
  blocks = c("dynamic_causal_cox_total"),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
