# Cirrhosis cohort — Allyn 2026 pooling on MIMIC-IV, eICU, NWICU
# AmsterdamUMC and HiRID have no cirrhosis diagnosis in the local extracts.
# Output: \\192.168.68.133\02block_result\50_Cirrhosis\database_pooled_42151996

.root <- if (nzchar(Sys.getenv("MEDICAL_BLOCKS_ROOT", ""))) {
  Sys.getenv("MEDICAL_BLOCKS_ROOT")
} else {
  "/mnt/e/01block/01Block-new-Final"
}

source(file.path(.root, "configs/templates/config_database_pooling_batch.template.R"))

config$project$root <- .root
config$project$name <- "database_pooled_42151996_cirrhosis"
config$project$output_dir <- "/mnt/g/02block_result/50_Cirrhosis/database_pooled_42151996/Output_database_pooling"

config$dbpool$blendedicu_ready <- "/mnt/sda/BlendedICU/data/cirrhosis_dzx_42151996/blendedlos_cirrhosis"
config$dbpool$blended_out <- "/mnt/sda/BlendedICU/data/cirrhosis_dzx_42151996/blendedlos_cirrhosis"
config$dbpool$skip_realextraction_adapt <- TRUE
config$dbpool$python_bin <- "/home/ps/anaconda3/envs/torch/bin/python"
config$dbpool$upstream_dir <- file.path(.root, "Blocks/78_database_pooling_full/upstream/BlendedLoS")
config$dbpool$fast_train <- FALSE
config$dbpool$literature_mode <- TRUE
config$dbpool$n_epochs <- 200L
config$dbpool$batch_size <- 32L
config$dbpool$alpha <- 20
config$dbpool$run_upstream_split <- FALSE
config$dbpool$selected_only <- TRUE

# Train: MIMIC-IV + NWICU. External test: eICU. Units: cirr_expA/B/C/D.
config$dbpool$units <- c(
  "cirr_expA_nwicu_solo",
  "cirr_expB_mimic_solo",
  "cirr_expC_mimic2nwicu_transfer",
  "cirr_expD_pooled_mimic_nwicu"
)
