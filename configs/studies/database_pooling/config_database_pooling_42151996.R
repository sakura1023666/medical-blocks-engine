# Live config — Allyn et al. Critical Care 2026 database pooling
# Output: \\192.168.68.133\02block_result\48_ICU\database_pooled_42151996

.root <- if (nzchar(Sys.getenv("MEDICAL_BLOCKS_ROOT", ""))) {
  Sys.getenv("MEDICAL_BLOCKS_ROOT")
} else {
  "/mnt/e/01block/01Block-new-Final"
}
if (!dir.exists(file.path(.root, "Blocks"))) {
  .root <- "/mnt/e/01block/01Block-new-Final"
}

source(file.path(.root, "configs/templates/config_database_pooling_batch.template.R"))

config$project$root <- .root
config$project$output_dir <- "/mnt/g/02block_result/48_ICU/database_pooled_42151996/Output_database_pooling"
config$project$name <- "database_pooled_42151996"

# 协调底座在 192.168.68.29，全课题共用，不按课题重抽
config$dbpool$blendedicu_base <- "/mnt/sda/BlendedICU/data/blended_data"
config$dbpool$blendedicu_ready <- "/mnt/sda/BlendedICU/data/blendedlos_ready"
config$dbpool$data_root <- "/mnt/g/02block_result/48_ICU/database_pooled_42151996/data/RealExtraction_4DB_20261009"
config$dbpool$blended_out <- file.path(config$project$output_dir, "blendedlos_ready")
config$dbpool$skip_realextraction_adapt <- TRUE
config$dbpool$python_bin <- file.path(.root, ".venv_dbpool/bin/python")
config$dbpool$upstream_dir <- file.path(.root, "Blocks/78_database_pooling_full/upstream/BlendedLoS")
config$dbpool$smoke_max_stays_per_db <- NULL
config$dbpool$dry_run <- FALSE
config$dbpool$run_upstream_split <- TRUE
config$dbpool$run_generate_tables <- TRUE
config$dbpool$selected_only <- TRUE
# 文献级（默认）：n_epochs=200, batch=32, alpha=20
# 归一化 = 原文：训练集 q5/q95，x=2*(x-q5)/(q95-q5)-1，再截断到 [-4, 4]；ffill + mask
# 仅调试可改 TRUE 或 shell: DBPOOL_FAST_TRAIN=1
config$dbpool$fast_train <- FALSE
config$dbpool$literature_mode <- TRUE
config$dbpool$n_epochs <- 200L
config$dbpool$batch_size <- 32L
config$dbpool$alpha <- 20

# Feishu: enable after run/feishu/run_feishu_setup_database_pooling_tables.R
config$feishu$enable <- FALSE
config$feishu$disease_label <- "48_ICU_DatabasePooling_BlendedLoS"
config$feishu$protocol_label <- "database_pooling"
config$feishu$project_id <- "DBPOOL_001"
