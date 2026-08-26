#!/usr/bin/env Rscript
# 重绘补充图编号对齐原文：
#   Figure S1 = 缺失热图（项目新增）
#   Figure S2 = PS 分布 + SMD Love（对齐原文 Fig.S1）
#   Figure S3 = 未加权 KM（对齐原文 Fig.S2）
suppressPackageStartupMessages({
  root <- normalizePath("E:/01block/01Block-new-Final", winslash = "/", mustWork = FALSE)
  if (!dir.exists(file.path(root, "R"))) root <- getwd()
  setwd(root)
  source("R/utils.R")
  source("R/pipeline_runner.R")
})

out_dir <- "G:/02block_result/11_ischemic stroke/Medication_regimen_model_42118193/by_unit/【success】NLR"
fig_root <- file.path(out_dir, "Figures")
dir.create(fig_root, recursive = TRUE, showWarnings = FALSE)

# ── S1：把已有缺失热图改名为 Figure S1 ─────────────────────────────────────
miss_src <- file.path(fig_root, "Figure Missing Value Overview.pdf")
miss_dst <- file.path(fig_root, "Figure S1-MIMIC. Missing value overview.pdf")
if (file.exists(miss_src)) {
  file.copy(miss_src, miss_dst, overwrite = TRUE)
  cli::cli_alert_success("S1 from existing missing heatmap → {.file {basename(miss_dst)}}")
} else {
  alt <- list.files(fig_root, pattern = "Missing|missing", full.names = TRUE)
  if (length(alt)) {
    file.copy(alt[[1]], miss_dst, overwrite = TRUE)
    cli::cli_alert_success("S1 from {.file {basename(alt[[1]])}}")
  } else {
    cli::cli_alert_warning("未找到缺失热图；S1 需重跑 imputation")
  }
}

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

# ── S2：从 multicollinearity 检查点重跑 iptw_balance（需 PS 协变量）────────
ck6 <- file.path(out_dir, "checkpoints", "step06_multicollinearity_screen.rds")
stopifnot(file.exists(ck6))
obj6 <- readRDS(ck6)
ctx0 <- obj6$ctx
ctx0$config <- config
ctx0$output_dir <- out_dir
ctx0$root_output_dir <- out_dir

# 预置：S1 已占用 → supp_figure=1，下一张为 S2
if (exists(".pub_state", mode = "environment", inherits = TRUE)) {
  assign("supp_figure", 1L, envir = .pub_state)
  assign("main_figure", 0L, envir = .pub_state)
  assign("main_table", 0L, envir = .pub_state)
}

pl2 <- list(name = "redraw_s2", blocks = "iptw_balance", checkpoint = list(enable = FALSE))
ctx2 <- run_pipeline(
  root, config = config, pipeline = pl2,
  run_opts = list(initial_ctx = ctx0, only = "iptw_balance")
)

s2_name <- ctx2$results$iptw_ps_smd_figure %||% ctx2$results$iptw_love_plot
cli::cli_alert_info("iptw figure key: {s2_name}")

# 收集刚写出的 PS/SMD pdf
cands <- list.files(
  out_dir,
  pattern = "propensity score|standardized mean|SMD Love|PS.*SMD",
  full.names = TRUE,
  recursive = TRUE,
  ignore.case = TRUE
)
cands <- cands[grepl("\\.pdf$", cands, ignore.case = TRUE)]
cands <- cands[file.exists(cands)]
if (length(cands)) {
  best <- cands[which.max(file.info(cands)$mtime)]
  dest_s2 <- file.path(
    fig_root,
    "Figure S2-MIMIC. The distribution of propensity score and standardized mean difference before and after weighting.pdf"
  )
  if (!identical(normalizePath(best, winslash = "/", mustWork = FALSE),
                 normalizePath(dest_s2, winslash = "/", mustWork = FALSE))) {
    file.copy(best, dest_s2, overwrite = TRUE)
  }
  cli::cli_alert_success("S2 size={file.info(dest_s2)$size} ← {.file {basename(best)}}")
} else {
  cli::cli_alert_danger("未找到新生成的 PS+SMD PDF")
}

# ── S3：重跑未加权 KM（依赖 iptw 后的权重数据）────────────────────────────
# 用刚跑完的 ctx2（含 iptw_weighted）
if (exists(".pub_state", mode = "environment", inherits = TRUE)) {
  assign("supp_figure", 2L, envir = .pub_state)
  assign("main_figure", 1L, envir = .pub_state)
}
ctx2$config <- config
pl3 <- list(name = "redraw_s3", blocks = "ipw_weighted_km_pub", checkpoint = list(enable = FALSE))
ctx3 <- run_pipeline(
  root, config = config, pipeline = pl3,
  run_opts = list(initial_ctx = ctx2, only = "ipw_weighted_km_pub")
)

uw <- ctx3$results$ipw_weighted_km_pub$figure_supp_path
if (length(uw) && isTRUE(file.exists(uw))) {
  dest_s3 <- file.path(
    fig_root,
    "Figure S3-MIMIC. Unweighted Kaplan–Meier curves of 28-day all-cause mortality by Diabetes HbA1c.pdf"
  )
  file.copy(uw, dest_s3, overwrite = TRUE)
  # 兼容旧 S2 未加权文件名：覆盖为提示用副本也可选删除
  legacy_s2_km <- file.path(
    fig_root,
    "Figure S2-MIMIC. Unweighted Kaplan–Meier curves of 28-day all-cause mortality by Diabetes HbA1c.pdf"
  )
  if (file.exists(legacy_s2_km)) {
    file.remove(legacy_s2_km)
    cli::cli_alert_info("Removed legacy unweighted KM named as S2")
  }
  legacy_s1_love <- list.files(fig_root, pattern = "Figure S1.*Love|Figure S1.*SMD", full.names = TRUE)
  for (f in legacy_s1_love) {
    file.remove(f)
    cli::cli_alert_info("Removed legacy {.file {basename(f)}}")
  }
  cli::cli_alert_success("S3 size={file.info(dest_s3)$size}")
} else {
  cli::cli_alert_warning("未加权 KM 路径缺失: {uw}")
}

cli::cli_alert_success("Done. Check Figures/ Figure S1 / S2 / S3")
quit(status = 0)
