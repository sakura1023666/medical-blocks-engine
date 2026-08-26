#!/usr/bin/env Rscript
# 重绘 Figure 4：年龄 65 分层两联 KM（格式对齐 Fig2）
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

obj <- readRDS(ck)
ctx0 <- obj$ctx
ctx0$config <- config
ctx0$output_dir <- out_dir
ctx0$root_output_dir <- out_dir

# 预置发表计数器，使本块拿到 Figure 4
if (exists(".pub_state", mode = "environment", inherits = TRUE)) {
  assign("main_figure", 3L, envir = .pub_state)
}

remain <- "ipw_subgroup_km_pub"
pl <- list(name = "redraw_fig4", blocks = remain, checkpoint = list(enable = FALSE))
ctx <- run_pipeline(root, config = config, pipeline = pl, run_opts = list(initial_ctx = ctx0, only = remain))

res <- ctx$results$ipw_subgroup_km_pub
cli::cli_alert_info("P-inter={pub_format_p(res$p_interaction)}; n by age={paste(names(res$n_by_stratum), res$n_by_stratum, sep='=', collapse=', ')}")
fig <- res$figure_path
if (length(fig) && file.exists(fig)) {
  dest <- file.path(out_dir, "Figures", basename(fig))
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  file.copy(fig, dest, overwrite = TRUE)
  # 同步标准 Fig4 文件名（避免编号漂移）
  dest4 <- file.path(
    out_dir, "Figures",
    "Figure 4-MIMIC. Subgroup Kaplan–Meier curves of 28-day mortality by age.pdf"
  )
  file.copy(fig, dest4, overwrite = TRUE)
  cli::cli_alert_success("Updated {.file {dest4}} size={file.info(dest4)$size}")
}
quit(status = 0)
