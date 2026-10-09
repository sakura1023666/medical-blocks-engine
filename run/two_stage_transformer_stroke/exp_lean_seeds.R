#!/usr/bin/env Rscript
# Experiment: lean features + multiple split seeds at L120
# Goal: see Day5 AUC distribution; can it reach 0.75?
suppressPackageStartupMessages({
  library(cli)
})
root <- normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", "E:/01block/01Block-new-Final"), winslash = "/", mustWork = TRUE)
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)
Sys.setenv(PYTHON = "C:/ProgramData/Miniconda3/envs/torch/python.exe")

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/rscript_study.R"))
source(file.path(root, "R/tst_stroke_task_runner.R"))

cfg_file <- "G:/02block_result/10_osteoporosis/two_stage_transformer_40041421/config_two_stage_transformer_stroke_task_parallel.R"
source(cfg_file)  # provides: config, pipeline_shared, task_units

seeds <- c(42L, 7L, 123L, 2024L, 314L, 8888L)
units <- c("L120_B_twostage", "L120_A2_single", "L120_mlp", "L120_logistic")

res_log <- "G:/02block_result/10_osteoporosis/two_stage_transformer_40041421/logs/exp_lean_seeds_result.log"
con <- file(res_log, "w"); writeLines("=== lean features x seeds (L120 Day5) ===", con); close(con)

for (s in seeds) {
  cfg <- config
  cfg$tst_stroke$split$seed <- s
  cfg$tst_timeseries$feature_priority_file <- file.path(
    root, "configs/tst_feature_priority/osteoporosis_mimic_lean.R"
  )
  # force re-split with new seed: clear split ck
  ck_dir <- file.path(cfg$project$output_dir, "checkpoints", "_shared", "main")
  for (f in c("step08_tst_split.rds", "tst_split.rds")) {
    p <- file.path(ck_dir, f); if (file.exists(p)) file.remove(p)
  }
  # also clear by_unit so workers re-run
  bu <- file.path(cfg$project$output_dir, "by_unit")
  if (dir.exists(bu)) unlink(bu, recursive = TRUE)
  dir.create(bu, showWarnings = FALSE)

  cli::cli_h2("seed = {s}")
  tryCatch(
    tst_stroke_run_task_parallel(root, cfg, pipeline_shared, units = units, workers = 2L),
    error = function(e) cli::cli_alert_danger("seed {s} failed: {conditionMessage(e)}")
  )

  # collect AUCs
  line <- sprintf("seed=%d ", s)
  for (u in units) {
    d <- file.path(cfg$project$output_dir, "by_unit", u)
    m <- list.files(d, pattern = "Table_TST_Metrics", recursive = TRUE, full.names = TRUE)
    if (!length(m)) { line <- paste0(line, u, "=NA "); next }
    dt <- data.table::fread(m[1])[split == "test" & day == 5]
    if (nrow(dt)) line <- paste0(line, sprintf("%s=%.3f ", u, dt$auc[1]))
  }
  cat(line, "\n", file = res_log, append = TRUE)
  cli::cli_alert_success(line)
}
cat("ALL_DONE\n", file = res_log, append = TRUE)
