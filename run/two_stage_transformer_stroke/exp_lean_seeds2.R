#!/usr/bin/env Rscript
# Experiment: lean features (20) x 6 split seeds at L120 Day5
# Measures AUC distribution; can any reach 0.75?
suppressPackageStartupMessages({ library(cli) })

root <- normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", "E:/01block/01Block-new-Final"), winslash = "/", mustWork = TRUE)
study <- "G:/02block_result/10_osteoporosis/two_stage_transformer_40041421"
cfg_file <- file.path(study, "config_two_stage_transformer_stroke_task_parallel.R")
rscript <- "C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
runner <- file.path(root, "run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R")
log_file <- file.path(study, "logs/exp_lean_seeds.log")
res_file <- file.path(study, "logs/exp_lean_seeds_result.log")

base_cfg <- readLines(cfg_file)
cat("=== lean x seeds start", format(Sys.time()), "===\n", file = log_file)
cat("=== lean(20) features x 6 seeds (L120 Day5) ===\n", file = res_file)

seeds <- c(42L, 7L, 123L, 2024L, 314L, 8888L)
units_str <- "L120_B_twostage,L120_A2_single,L120_mlp,L120_logistic"

for (s in seeds) {
  cli::cli_h2("seed = {s}")
  cat("=== seed", s, format(Sys.time()), "===\n", file = log_file, append = TRUE)

  # modify config text: seed + lean whitelist
  cfg_txt <- base_cfg
  cfg_txt <- gsub("seed = 42L", paste0("seed = ", s, "L"), cfg_txt, fixed = TRUE)
  cfg_txt <- gsub("osteoporosis_mimic.R", "osteoporosis_mimic_lean.R", cfg_txt, fixed = TRUE)
  tmp_cfg <- file.path(study, sprintf("config_exp_seed%d.R", s))
  writeLines(cfg_txt, tmp_cfg)

  # clear shared from step04 + by_unit
  for (d in c("step04_tst_timeseries","step05_imputation","step06_baseline_binary",
              "step07_tst_landmark","step08_tst_split")) {
    p <- file.path(study, "_shared", d); if (dir.exists(p)) unlink(p, recursive = TRUE)
  }
  ck <- file.path(study, "checkpoints", "_shared", "main")
  for (f in list.files(ck, pattern = "^(step0[4-8]|tst_timeseries|imputation|baseline_binary|tst_landmark|tst_split|index)", full.names = TRUE)) {
    file.remove(f)
  }
  bu <- file.path(study, "by_unit"); if (dir.exists(bu)) unlink(bu, recursive = TRUE)
  dir.create(bu, showWarnings = FALSE)

  # run via Rscript (Windows) so Python train works
  cmd <- sprintf('"%s" "%s" --config "%s" --workers 2 --only-unit %s',
                 rscript, runner, tmp_cfg, units_str)
  cat(cmd, "\n", file = log_file, append = TRUE)
  out <- system2(rscript, c(runner, "--config", tmp_cfg, "--workers", "2",
                            "--only-unit", units_str),
                  stdout = TRUE, stderr = TRUE, timeout = 1800)
  cat(paste(out, collapse = "\n"), "\n", file = log_file, append = TRUE)

  # collect AUCs - search for 【success】 prefix or bare name
  line <- sprintf("seed=%d ", s)
  for (u in strsplit(units_str, ",")[[1]]) {
    # find any dir matching this unit (with or without 【success】 prefix)
    hits <- list.files(file.path(study, "by_unit"), pattern = u, full.names = TRUE)
    m <- character(0)
    for (h in hits) {
      m <- c(m, list.files(h, pattern = "Table_TST_Metrics", recursive = TRUE, full.names = TRUE))
    }
    if (!length(m)) { line <- paste0(line, u, "=NA "); next }
    dt <- data.table::fread(m[1])[split == "test" & day == 5]
    if (nrow(dt)) line <- paste0(line, sprintf("%s=%.3f ", u, dt$auc[1]))
  }
  cat(line, "\n", file = res_file, append = TRUE)
  cli::cli_alert_success(line)
  file.remove(tmp_cfg)
}

cat("ALL_DONE\n", file = res_file, append = TRUE)
cat("EXIT=0\n", file = log_file, append = TRUE)
