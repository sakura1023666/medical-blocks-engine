# CSA-AKI (cardiac perioperative AKI) — Allyn 2026 pooling
# MIMIC-IV + SICdb train; eICU + INSPIRE external. Amsterdam skipped.
# Client: 龚倩. Output: \\192.168.68.133\02block_result\33_AKI\database_pooled_42151996
# Decision tree: Decisiontree/decision_tree_database_pooling_csaaki_gongqian.md
# Feature gate: drop AKI inclusion features from model inputs
#   urine_output (KDIGO UO branch; also INSPIRE post-op ICU urine unavailable)
#   creatinine   (KDIGO Cr branch; inclusion leakage, ACG-style)

.root <- if (nzchar(Sys.getenv("MEDICAL_BLOCKS_ROOT", ""))) {
  Sys.getenv("MEDICAL_BLOCKS_ROOT")
} else {
  "/mnt/e/01block/01Block-new-Final"
}

source(file.path(.root, "configs/templates/config_database_pooling_batch.template.R"))

config$project$root <- .root
config$project$name <- "database_pooled_42151996_csaaki_gongqian"
config$project$output_dir <- "/mnt/g/02block_result/33_AKI/database_pooled_42151996/Output_database_pooling"
config$project$database <- "CSAAKI_MIMIC_eICU_SICdb_INSPIRE"

# Assembled on 29; sync/rsync tree to 34 before GPU train if needed.
config$dbpool$blendedicu_ready <- "/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/blendedlos_csaaki"
config$dbpool$blended_out <- "/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/blendedlos_csaaki"
config$dbpool$skip_realextraction_adapt <- TRUE
config$dbpool$python_bin <- "/home/ps/miniconda3/envs/torch-gpu/bin/python"
config$dbpool$upstream_dir <- file.path(.root, "Blocks/78_database_pooling_full/upstream/BlendedLoS")
config$dbpool$fast_train <- FALSE
config$dbpool$literature_mode <- TRUE
config$dbpool$n_epochs <- 200L
config$dbpool$batch_size <- 32L
config$dbpool$alpha <- 20
config$dbpool$run_upstream_split <- FALSE
config$dbpool$selected_only <- TRUE
config$dbpool$drop_features <- "urine_output,creatinine"
# Env consumed by _run_one_template.py
Sys.setenv(DBPOOL_DROP_TS = "urine_output,creatinine")

config$dbpool$units <- c(
  "csa_expA_sicdb_solo",
  "csa_expB_mimic_solo",
  "csa_expC_mimic2sicdb_transfer",
  "csa_expD_pooled_mimic_sicdb",
  "csa_model_benchmark",
  "csa_dataset_benchmark",
  "csa_training_size_study"
)

config$feishu$enable <- FALSE
config$feishu$disease_label <- "33_AKI_CSAAKI_DatabasePooling_GongQian"
config$feishu$protocol_label <- "database_pooling"
config$feishu$project_id <- "DBPOOL_CSAAKI_001"
