###############################################################################
#  config_complex_network_clhls_batch.R — 复杂网络批量（性别亚组并行）
#  入口: run/complex_network/run_complex_network_clhls_batch.R
###############################################################################

source("configs/config_complex_network_clhls.R")

.batch_batch_root <- "Output/Complex_Network_CLHLS_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Complex_Network_CLHLS_Batch"

config$study_batch <- list(
  output_base      = .batch_batch_root,
  units            = c("All", "Male", "Female"),
  unit_mode        = "branch",
  branch_map       = list(
    All    = list(blocks = "complex_network_ggm", row_filter = NULL),
    Male   = list(blocks = "complex_network_ggm", row_filter = "Gender == 'Male'"),
    Female = list(blocks = "complex_network_ggm", row_filter = "Gender == 'Female'")
  ),
  parallel_workers = "auto",
  skip_existing    = TRUE,
  worker_script    = "run/study/run_study_batch_worker.R",
  shared_ck_alias  = "complex_network_descriptive"
)

pipeline_shared <- list(
  name = "complex_network_shared",
  blocks = c("data_clean", "imputation", "complex_network_descriptive"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "complex_network_unit",
  blocks = c("complex_network_ggm"),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
