###############################################################################
#  config_environment_dkd_nhanes.template.R — 配置模板（复制到研究产出目录后按【必改】修改）
#  原始实例已移至 configs/_archive/config_environment_dkd_nhanes.R
###############################################################################

###############################################################################
#  config_environment_dkd_nhanes.R — DKD × 环境 VOC（NHANES 单次全流程）
#  批量并行 + 飞书请用: configs/config_environment_dkd_batch.R
#                     run_environment_dkd_batch.R
#
#  单次跑仅执行 1 个 rcs_nhanes（见 rcs_nhanes$index_var）；多 VOC RCS 请用 batch。
###############################################################################

.cfg_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(.cfg_root)) .cfg_root <- getwd()
source(file.path(.cfg_root, "configs/_archive/config_environment_dkd_batch.R"), local = FALSE)

config$project$output_dir <- file.path(
  config$environment_batch$output_base %||% config$project$output_dir,
  "full_single"
)
config$project$name <- "DKD_Environment_VOC_Single"

# 单次 RCS 默认暴露（试跑前请改为你的显著 VOC 列名）
if (is.null(config$rcs_nhanes$index_var) || !nzchar(config$rcs_nhanes$index_var)) {
  config$rcs_nhanes$index_var <- "DHBMA"
}
config$incidence$index_var     <- config$rcs_nhanes$index_var
config$logistic$index_var      <- config$rcs_nhanes$index_var
config$nhanes$cutoff_index_var <- config$rcs_nhanes$index_var

pipeline$checkpoint$dir <- file.path(
  config$environment_batch$output_base %||% "Output/DKD_Environment_VOC_NHANES",
  "checkpoints", "full_single"
)

config$feishu$enable                <- FALSE
config$feishu$push_on_worker_finish <- FALSE
config$feishu$push_on_batch_summary <- FALSE
