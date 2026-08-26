#!/usr/bin/env Rscript
# 仅重跑 TST stroke Table 1：按院内死亡分层 + 临床评分/共病归位 + 规范列名
suppressPackageStartupMessages({
  library(cli)
})

root <- {
  cands <- c(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", ""),
    "E:/01block/01Block-new-Final",
    "/mnt/e/01block/01Block-new-Final"
  )
  hit <- cands[nzchar(cands) & dir.exists(cands)]
  if (!length(hit)) stop("repo root not found")
  hit[[1L]]
}
proj <- {
  cands <- c(
    "G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421",
    "/mnt/g/02block_result/11_ischemic stroke/two_stage_transformer_40041421"
  )
  hit <- cands[dir.exists(cands)]
  if (!length(hit)) stop("project root not found")
  hit[[1L]]
}

setwd(root)
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/baseline_dictionary_labels.R"), local = FALSE)
source(file.path(root, "Blocks/04_baseline/01block_baseline_binary.R"), local = FALSE)

cfg_path <- file.path(proj, "config_two_stage_transformer_stroke.R")
sys.source(cfg_path, envir = environment())
stopifnot(exists("config"))
options(pipeline.database_name = config$project$database %||% "MIMIC")

imp_path <- file.path(proj, "_shared/step05_imputation/D01_AfterMI_Data.RData")
load(imp_path)
dat <- get("object")
stopifnot(is.data.frame(dat), "is_hosp_dead" %in% names(dat))

out_dir <- file.path(proj, "_shared/step06_baseline_binary")
dir.create(file.path(out_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_dir, "Figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_dir, "Data"), recursive = TRUE, showWarnings = FALSE)

ctx <- list(
  config = config,
  data = list(imputed = dat, cleaned = dat),
  results = list(),
  output_dir = out_dir,
  output_dir_tables = file.path(out_dir, "Tables"),
  output_dir_figures = file.path(out_dir, "Figures"),
  output_dir_data = file.path(out_dir, "Data"),
  project_root = proj,
  log = list()
)
if (exists("pub_reset_counters", mode = "function")) pub_reset_counters(ctx)

cli::cli_h1("Rebuild Table 1 for TST stroke (mortality strata)")
ctx <- block_baseline_binary(ctx)

# 同步到 summary_results（优先最新重建文件）
sum_tab <- file.path(proj, "summary_results/Tables")
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)
cands <- list.files(
  file.path(out_dir, "Tables"),
  pattern = "^Table 1-.*Baseline characteristics.*\\.xlsx$",
  full.names = TRUE
)
stopifnot(length(cands) >= 1L)
info <- file.info(cands)
src_xlsx <- rownames(info)[which.max(info$mtime)]
dst <- file.path(sum_tab, "Table 1-MIMIC-Baseline_characteristics.xlsx")
if (!identical(normalizePath(src_xlsx, winslash = "/", mustWork = FALSE),
               normalizePath(dst, winslash = "/", mustWork = FALSE))) {
  file.copy(src_xlsx, dst, overwrite = TRUE)
}
dst2 <- file.path(
  out_dir, "Tables",
  "Table 1-MIMIC. Baseline characteristics of IschemicStroke TwoStageTransformer.xlsx"
)
if (!identical(normalizePath(src_xlsx, winslash = "/", mustWork = FALSE),
               normalizePath(dst2, winslash = "/", mustWork = FALSE))) {
  file.copy(src_xlsx, dst2, overwrite = TRUE)
}
cli::cli_alert_success("Table 1 -> {dst}")
cli::cli_alert_info("source: {basename(src_xlsx)}")
