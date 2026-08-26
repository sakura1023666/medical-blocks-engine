#!/usr/bin/env Rscript
# 重绘 Figure S4：预后模型校准 + 28 天 ROC（对齐原文 Fig.S3）
suppressPackageStartupMessages({
  root <- normalizePath("E:/01block/01Block-new-Final", winslash = "/", mustWork = FALSE)
  if (!dir.exists(file.path(root, "R"))) root <- getwd()
  setwd(root)
  source("R/utils.R")
  source("R/pipeline_runner.R")
})

out_dir <- "G:/02block_result/11_ischemic stroke/Medication_regimen_model_42118193/by_unit/【success】NLR"
ck <- file.path(out_dir, "checkpoints", "step06_multicollinearity_screen.rds")
stopifnot(file.exists(ck))

cfg_path <- "G:/02block_result/11_ischemic stroke/Medication_regimen_model_42118193/config_ipw_diabetes_stroke_batch.R"
file.copy(
  file.path(root, "configs/templates/config_ipw_diabetes_stroke_batch.template.R"),
  cfg_path, overwrite = TRUE
)
source(cfg_path, local = TRUE)
config$feishu$enable <- FALSE
config$project$output_dir <- out_dir
config$analysis_exclusion$index_var <- "NLR"
config$active_unit <- "NLR"
config$incidence$index_var <- "NLR"

obj <- readRDS(ck)
ctx0 <- obj$ctx
ctx0$config <- config
ctx0$output_dir <- out_dir
ctx0$root_output_dir <- out_dir

# S1–S3 已占用 → 下一张为 S4
if (exists(".pub_state", mode = "environment", inherits = TRUE)) {
  assign("supp_figure", 3L, envir = .pub_state)
}

remain <- "ipw_surv_calibration_roc"
pl <- list(name = "redraw_fig_s4", blocks = remain, checkpoint = list(enable = FALSE))
ctx <- run_pipeline(root, config = config, pipeline = pl, run_opts = list(initial_ctx = ctx0, only = remain))

res <- ctx$results$ipw_surv_calibration_roc
cli::cli_alert_info("AUC={res$auc}; n={res$n}; events={res$n_events}")

dest <- file.path(
  out_dir, "Figures",
  "Figure S4-MIMIC. Calibration and receiver operating characteristic curves of the prediction model at 28-day.pdf"
)
cands <- list.files(
  out_dir,
  pattern = "Calibration|ROC|receiver operating",
  full.names = TRUE,
  recursive = TRUE,
  ignore.case = TRUE
)
cands <- cands[grepl("\\.pdf$", cands, ignore.case = TRUE)]
cands <- cands[file.exists(cands)]
stopifnot(length(cands) > 0)
best <- cands[which.max(file.info(cands)$mtime)]
dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
if (!identical(
  normalizePath(best, winslash = "/", mustWork = FALSE),
  normalizePath(dest, winslash = "/", mustWork = FALSE)
)) {
  file.copy(best, dest, overwrite = TRUE)
}
cli::cli_alert_success("S4 size={file.info(dest)$size} ← {.file {basename(best)}}")
quit(status = 0)
