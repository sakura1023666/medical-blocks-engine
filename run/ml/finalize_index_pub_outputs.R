#!/usr/bin/env Rscript
# 对已有 checkpoint 的指标重跑 finalize（表/图 curate、双库拼图、export_pub_figures）
args <- commandArgs(trailingOnly = TRUE)
ix <- if (length(args) >= 1L && !startsWith(args[[1L]], "--")) args[[1L]] else "SHR"
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  root <- if (length(f)) {
    normalizePath(file.path(dirname(sub("^--file=", "", f[1L])), "..", ".."), winslash = "/")
  } else {
    normalizePath(getwd(), winslash = "/")
  }
}
setwd(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))
source(file.path(root, "R/ml_dual_pub_table_curate.R"))
source(file.path(root, "R/pub_figure_export.R"))
source(file.path(root, "R/dual_db_combine_figures.R"))
# --config 须在 commandArgs 中（由调用方传入）
cfg_i <- match("--config", commandArgs(trailingOnly = TRUE))
if (is.na(cfg_i)) stop("须传入 --config <study/config.R>", call. = FALSE)
source(normalizePath(commandArgs(trailingOnly = TRUE)[[cfg_i + 1L]], winslash = "/", mustWork = TRUE))
study_root <- .batch_project_root
ix_root <- file.path(study_root, "by_index", paste0("【success】", ix))
if (!dir.exists(ix_root)) {
  ix_root <- incidence_batch_find_index_output_dir(
    study_root, ix, incidence_batch_index_output_subdir(config$ml_batch %||% list()),
    config = config, ix_bare = ix
  )
}
config$ml_batch$.force_index_output_root <- ix_root
config$incidence_batch <- config$ml_batch
cli::cli_alert_info("finalize [{ix}] @ {ix_root}")
incidence_batch_finalize_index_outputs(study_root, config, ix, c("nhanes", "mimic"))
