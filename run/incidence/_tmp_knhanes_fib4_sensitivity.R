###############################################################################
# 一次性：KNHANES FIB4 敏感性补跑（单库 nhanes_only）
###############################################################################
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
cfg_path <- "/mnt/g/02block_result/39_Sinusitis/incidence_38341157/config_incidence_knhanes.R"
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/dual_db_harmonize.R"), local = FALSE)
source(file.path(root, "R/incidence_dual_batch_runner.R"), local = FALSE)
source(file.path(root, "R/incidence_subgroup_fallback.R"), local = FALSE)
source(file.path(root, "R/incidence_sensitivity_suite.R"), local = FALSE)
source(cfg_path, local = FALSE)
config$incidence_batch$output_base <- dirname(cfg_path)
config$incidence_batch$index_ck_base <- file.path(dirname(cfg_path), "checkpoints/_by_index")
config$incidence_batch$db_mode <- "nhanes_only"
cli::cli_h1("KNHANES FIB4 敏感性补跑（期望 ~15 场景）")
incidence_sensitivity_pass(
  root = root,
  config = config,
  indices = "FIB4",
  config_path = cfg_path,
  only_index = "FIB4",
  worker_script = "run/incidence/run_incidence_dual_batch_worker.R",
  force = TRUE
)
cli::cli_alert_success("敏感性补跑结束")
