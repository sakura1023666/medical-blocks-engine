#!/usr/bin/env Rscript
# 重绘 Figure 5：Jin 同构 STEPP（共享窗 × Diabetes 两臂 + 95% CI）
suppressPackageStartupMessages({
  root <- normalizePath("E:/01block/01Block-new-Final", winslash = "/", mustWork = FALSE)
  if (!dir.exists(file.path(root, "R"))) root <- getwd()
  setwd(root)
  source("R/utils.R")
  source("R/pipeline_runner.R")
})

out_dir <- "G:/02block_result/11_ischemic stroke/Medication_regimen_model_42118193/by_unit/【success】NLR"
ck <- file.path(out_dir, "checkpoints", "step13_ipw_subgroup_km_pub.rds")
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
config$stepp_prognosis$index_var <- "NLR"
config$stepp_prognosis$plot_style <- "jin_treatment"
config$stepp_prognosis$pause_enable <- FALSE

obj <- readRDS(ck)
ctx0 <- obj$ctx
ctx0$config <- config
ctx0$output_dir <- out_dir
ctx0$root_output_dir <- out_dir

# 确认 Diabetes_HbA1c 在数据中
d0 <- ctx0$data$imputed %||% ctx0$data$cleaned
stopifnot("Diabetes_HbA1c" %in% names(d0), "NLR" %in% names(d0))

if (exists(".pub_state", mode = "environment", inherits = TRUE)) {
  assign("main_figure", 4L, envir = .pub_state)
}

remain <- "stepp_prognosis"
pl <- list(name = "redraw_fig5_jin", blocks = remain, checkpoint = list(enable = FALSE))
ctx <- run_pipeline(root, config = config, pipeline = pl, run_opts = list(initial_ctx = ctx0, only = remain))

dest <- file.path(
  out_dir, "Figures",
  "Figure 5-MIMIC. STEPP of 28-day survival by Diabetes across NLR composite risk.pdf"
)
# 只取本次 jin 图（文件名含 by Diabetes），不要误选旧 Gender 2x2
cands <- list.files(
  file.path(out_dir, "step17_stepp_prognosis", "Figures"),
  pattern = "STEPP of 28-day survival by Diabetes.*\\.pdf$",
  full.names = TRUE,
  ignore.case = TRUE
)
if (!length(cands)) {
  cands <- list.files(
    file.path(out_dir, "Figures"),
    pattern = "STEPP of 28-day survival by Diabetes.*\\.pdf$",
    full.names = TRUE,
    ignore.case = TRUE
  )
}
stopifnot(length(cands) > 0)
best <- cands[which.max(file.info(cands)$mtime)]
dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
file.copy(best, dest, overwrite = TRUE)
legacy <- file.path(
  out_dir, "Figures",
  "Figure 5-MIMIC. STEPP sliding-window analysis of NLR (overall and by Gender).pdf"
)
file.copy(best, legacy, overwrite = TRUE)
# step17 也放一份标准 Fig5 名
file.copy(best, file.path(dirname(best), basename(dest)), overwrite = TRUE)
cli::cli_alert_success("Fig5 size={file.info(dest)$size} ← {.file {basename(best)}}")

tbl <- ctx$results$stepp_prognosis_table
if (is.data.frame(tbl) && nrow(tbl)) {
  n_win <- length(unique(tbl$median_risk))
  cli::cli_alert_info(
    "STEPP rows={nrow(tbl)}; unique windows={n_win}; style={ctx$results$stepp_prognosis_plot_style}"
  )
  print(tbl)
}
quit(status = 0)
