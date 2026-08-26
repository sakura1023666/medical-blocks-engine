#!/usr/bin/env Rscript
# 重跑 subgroup_iptw_weighted（修复 Events 全 0），写回【success】NLR
suppressPackageStartupMessages({
  root <- normalizePath("E:/01block/01Block-new-Final", winslash = "/", mustWork = FALSE)
  if (!dir.exists(file.path(root, "R"))) root <- getwd()
  setwd(root)
  source("R/utils.R")
  source("R/pipeline_runner.R")
})

out_dir <- "G:/02block_result/11_ischemic stroke/Medication_regimen_model_42118193/by_unit/【success】NLR"
ck <- file.path(out_dir, "checkpoints", "step07_iptw_balance.rds")
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
# 保证预后二分类结局标签（即便走标签匹配也正确）
config$project$analysis_group <- "1"
config$project$reference_group <- "0"

obj <- readRDS(ck)
ctx0 <- obj$ctx
ctx0$config <- config
ctx0$output_dir <- out_dir
ctx0$root_output_dir <- out_dir

remain <- "subgroup_iptw_weighted"
pl <- list(name = "redraw_fig3", blocks = remain, checkpoint = list(enable = FALSE))
ctx <- run_pipeline(root, config = config, pipeline = pl, run_opts = list(initial_ctx = ctx0, only = remain))

tab <- ctx$results$subgroup_iptw
cli::cli_alert_info("Events sample: {paste(utils::head(unique(tab$Events), 8), collapse=', ')}")
fig <- ctx$results$subgroup_iptw_figure
if (length(fig) && file.exists(fig)) {
  dest <- file.path(out_dir, "Figures", basename(fig))
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  file.copy(fig, dest, overwrite = TRUE)
  cli::cli_alert_success("Updated {.file {dest}}")
}
quit(status = 0)
