#!/usr/bin/env Rscript
###############################################################################
#  run_ml_small_sample_pub.R — 小样本 ML 发表后处理（Table 4/5 + Figure 4）
#
#  复用 R/ml_small_sample_* 与 python/ml_figure_combined_2x4.py
#  单指标 / 全变量、发病 / 预后 共用；由 config$ml_small_sample 控制。
#
#  Usage:
#    MEDICAL_BLOCKS_ROOT=/path/to/repo Rscript run/ml/run_ml_small_sample_pub.R \
#      --config /path/to/study/config.R
###############################################################################

args <- commandArgs(trailingOnly = TRUE)
cfg_path <- NULL
if (length(args) >= 2L && args[1] == "--config") cfg_path <- args[2L]
if (is.null(cfg_path) || !file.exists(cfg_path)) {
  stop("Usage: Rscript run/ml/run_ml_small_sample_pub.R --config /path/to/config.R")
}

repo <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
if (!dir.exists(repo)) repo <- "/mnt/e/01block/01Block-new-Final"

source(file.path(repo, "R/utils.R"))
source(file.path(repo, "R/competing_supp_xlsx.R"))
source(file.path(repo, "R/ml_small_sample_metrics.R"))
source(file.path(repo, "R/ml_small_sample_table45.R"))

cfg <- source(cfg_path, local = TRUE)$value
if (is.null(cfg)) cfg <- get("config", envir = .GlobalEnv)

ms <- cfg$ml_small_sample
if (is.null(ms) || !isTRUE(ms$enable)) {
  stop("config$ml_small_sample$enable must be TRUE")
}

out_dir <- cfg$project$output_dir
if (!is.null(ms$output_dir)) out_dir <- ms$output_dir
tab_dir <- file.path(out_dir, ms$tables_dir %||% "Tables")
fig_dir <- file.path(out_dir, ms$figures_dir %||% "Figures")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

# 可选：读 imputed 数据用于脚注 n/events
d <- NULL
rds_candidates <- c(
  file.path(out_dir, "data_all_vars_imputed.rds"),
  file.path(out_dir, "data_imputed.rds")
)
for (rp in rds_candidates) {
  if (file.exists(rp)) {
    d <- readRDS(rp)
    if (!is.null(d$event) && !"event" %in% names(d)) {
      ok <- ms$prognosis %||% list()
      if (!is.null(ok$event_column)) {
        d$event <- as.integer(as.character(d[[ok$event_column]]) == ok$event_positive)
      }
    }
    break
  }
}

feats <- character()
feat_csv <- file.path(out_dir, "ml_final_features.csv")
if (file.exists(feat_csv)) {
  fx <- read.csv(feat_csv, stringsAsFactors = FALSE)
  if ("feature" %in% names(fx)) feats <- fx$feature
  else if (ncol(fx)) feats <- fx[[1L]]
} else if (!is.null(ms$index_var) && nzchar(ms$index_var)) {
  feats <- ms$index_var
}

ml_write_table45(
  out_dir = out_dir,
  tab_dir = tab_dir,
  d = d,
  cfg = cfg,
  feature_label = feats,
  footnote_extra_t5 = if (identical(ms$feature_mode, "all_vars")) {
    "DeLong vs single-index model may appear in Table S10."
  } else character()
)

# Figure 4 via Python
py_exe <- ms$python_exe %||% Sys.getenv("MEDICAL_BLOCKS_PYTHON", unset = "python")
fig4 <- file.path(fig_dir, ms$figure4_name %||% "Figure 4. ML performance combined 2x4.pdf")
py_script <- file.path(repo, "python", "ml_figure_combined_2x4.py")
if (file.exists(py_script)) {
  cmd <- sprintf(
    "%s %s --root %s --out %s --bootstrap %d",
    shQuote(py_exe), shQuote(py_script), shQuote(out_dir), shQuote(fig4),
    as.integer(ms$bootstrap_B %||% 1000L)
  )
  message("Figure 4: ", cmd)
  status <- system(cmd)
  if (status != 0L) warning("Figure 4 python exited ", status)
} else {
  warning("Missing ", py_script)
}

cat("\nDone. Tables in:", tab_dir, "\n")
