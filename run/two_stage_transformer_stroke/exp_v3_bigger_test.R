#!/usr/bin/env Rscript
# Experiment v3: bigger test set (50/25/25) + full osteoporosis features + no patient drop
# Goal: L120 Day5 AUC > 0.75 with Transformer on top
suppressPackageStartupMessages({ library(cli) })

root <- normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", "E:/01block/01Block-new-Final"), winslash = "/", mustWork = TRUE)
study <- "G:/02block_result/10_osteoporosis/two_stage_transformer_40041421"
cfg_file <- file.path(study, "config_two_stage_transformer_stroke_task_parallel.R")
rscript <- "C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
runner <- file.path(root, "run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R")
log_file <- file.path(study, "logs/exp_v3_bigger_test.log")
res_file <- file.path(study, "logs/exp_v3_bigger_test_result.log")

base_cfg <- readLines(cfg_file)
cat("=== exp v3 bigger test start", format(Sys.time()), "===\n", file = log_file)
cat("=== v3: 50/25/25 split, full osteoporosis features, no patient drop ===\n", file = res_file)

# Config: split 50/25/25, no patient drop, full osteoporosis_mimic.R features
# Also try 40/30/30 for even bigger test
splits <- list(
  c(0.5, 0.25, 0.25),   # 50/25/25: test ~100 at L120
  c(0.4, 0.30, 0.30)    # 40/30/30: test ~121 at L120
)
split_names <- c("50_25_25", "40_30_30")
seeds <- c(42L, 123L)
units_str <- "L120_B_twostage,L120_A2_single,L120_mlp,L120_logistic,L120_xgb"

for (si in seq_along(splits)) {
  sp <- splits[[si]]
  spn <- split_names[[si]]
  for (s in seeds) {
    tag <- sprintf("%s_seed%d", spn, s)
    cli::cli_h2("{tag}")
    cat("=== ", tag, format(Sys.time()), " ===\n", file = log_file, append = TRUE)

    cfg_txt <- base_cfg
    cfg_txt <- gsub("seed = 42L", paste0("seed = ", s, "L"), cfg_txt, fixed = TRUE)
    cfg_txt <- gsub("train = 0.8, val = 0.1, test = 0.1",
                    sprintf("train = %.2f, val = %.2f, test = %.2f", sp[1], sp[2], sp[3]),
                    cfg_txt, fixed = TRUE)
    tmp_cfg <- file.path(study, sprintf("config_exp_%s.R", tag))
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

    out <- system2(rscript, c(runner, "--config", tmp_cfg, "--workers", "2",
                              "--only-unit", units_str),
                    stdout = TRUE, stderr = TRUE, timeout = 1800)
    cat(paste(out, collapse = "\n"), "\n", file = log_file, append = TRUE)

    # collect AUCs - search 【success】 prefix
    line <- sprintf("%s ", tag)
    for (u in strsplit(units_str, ",")[[1]]) {
      hits <- list.files(file.path(study, "by_unit"), pattern = u, full.names = TRUE)
      m <- character(0)
      for (h in hits) m <- c(m, list.files(h, pattern = "Table_TST_Metrics", recursive = TRUE, full.names = TRUE))
      if (!length(m)) { line <- paste0(line, u, "=NA "); next }
      dt <- data.table::fread(m[1])[split == "test" & day == 5]
      if (nrow(dt)) line <- paste0(line, sprintf("%s=%.3f ", u, dt$auc[1]))
    }
    cat(line, "\n", file = res_file, append = TRUE)
    cli::cli_alert_success(line)
    file.remove(tmp_cfg)
  }
}

cat("ALL_DONE\n", file = res_file, append = TRUE)
cat("EXIT=0\n", file = log_file, append = TRUE)
