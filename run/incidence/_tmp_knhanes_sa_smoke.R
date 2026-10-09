root <- "/mnt/e/01block/01Block-new-Final"
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/dual_db_harmonize.R"), local = FALSE)
source(file.path(root, "R/incidence_dual_batch_runner.R"), local = FALSE)
source(file.path(root, "R/incidence_subgroup_fallback.R"), local = FALSE)
source(file.path(root, "R/incidence_sensitivity_suite.R"), local = FALSE)
cfg_path <- "/mnt/g/02block_result/39_Sinusitis/incidence_38341157/config_incidence_knhanes.R"
source(cfg_path, local = FALSE)
stopifnot(exists("pipeline_nhanes_batch"))
config$incidence_batch$output_base <- dirname(cfg_path)
config$incidence_batch$index_ck_base <- file.path(dirname(cfg_path), "checkpoints/_by_index")
config$incidence_batch$db_mode <- "nhanes_only"
ix <- "FIB4"
sg <- list(
  label = "SA_no_Hypertension",
  expr = 'is.na(Hypertension) | trimws(as.character(Hypertension)) != "Yes"',
  required_vars = "Hypertension"
)
parent <- file.path(dirname(cfg_path), "by_index", "\u3010success\u3011FIB4")
res <- incidence_sensitivity_run_one(
  root, config, cfg_path, ix, sg, "nhanes", parent,
  worker_script = "run/incidence/run_incidence_dual_batch_worker.R",
  scheme = "quartile"
)
print(res)
