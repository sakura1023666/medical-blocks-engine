###############################################################################
#  config_clhls_symptom_network_batch.template.R — 性别 / NCT / 稳定性并行
#  入口: run/clhls_symptom_network/run_clhls_symptom_network_batch.R
###############################################################################

source("configs/config_clhls_symptom_network.R")

.batch_batch_root <- config$project$output_dir
config$project$name <- "CLHLS_Symptom_Network_Batch"

config$study_batch <- list(
  output_base      = .batch_batch_root,
  units            = c("Main", "Sex", "NCT", "Stability"),
  unit_mode        = "branch",
  branch_map       = list(
    Main = list(
      blocks = c("data_clean", "column_mapping", "imputation",
                 "clhls_symptom_ingest", "clhls_network", "clhls_centrality",
                 "clhls_weighted", "clhls_bridge", "clhls_network_pub"),
      row_filter = NULL
    ),
    Sex = list(
      blocks = c("data_clean", "column_mapping", "imputation",
                 "clhls_symptom_ingest", "clhls_network", "clhls_sex", "clhls_network_pub"),
      row_filter = NULL
    ),
    NCT = list(
      blocks = c("data_clean", "column_mapping", "imputation",
                 "clhls_symptom_ingest", "clhls_sex_nct"),
      row_filter = NULL
    ),
    Stability = list(
      blocks = c("data_clean", "column_mapping", "imputation",
                 "clhls_symptom_ingest", "clhls_network", "clhls_stability", "clhls_network_pub"),
      row_filter = NULL
    )
  ),
  parallel_workers = "auto",
  skip_existing    = TRUE,
  worker_script    = "run/study/run_study_batch_worker.R",
  shared_ck_alias  = "clhls_network"
)

pipeline_shared <- list(
  name = "clhls_symptom_shared",
  blocks = c("data_clean", "column_mapping", "imputation",
             "clhls_symptom_ingest", "clhls_network"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "clhls_symptom_unit",
  blocks = c("clhls_centrality"),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
