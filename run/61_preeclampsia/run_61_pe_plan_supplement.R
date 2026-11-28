#!/usr/bin/env Rscript
# 方案补跑：3.2 变化指标 + S1 单胎 Logistic + S2 PE vs SPE 轨迹
# Rscript run/61_preeclampsia/run_61_pe_plan_supplement.R --config .../config_61_preeclampsia_batch.R

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) return(normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/"))
  normalizePath(getwd(), winslash = "/")
}
`%||%` <- function(a, b) if (!is.null(a)) a else b

script_path <- .init_script_dir()
root <- if (basename(script_path) == "61_preeclampsia" && basename(dirname(script_path)) == "run") {
  normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), winslash = "/")
}
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
config_path <- "/mnt/g/02block_result/61_Preeclampsia/configs/config_61_preeclampsia_batch.R"
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--config" && i < length(args)) {
    config_path <- args[[i + 1L]]; i <- i + 2L
  } else i <- i + 1L
}
config_path <- normalizePath(config_path, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(config_path)

options(warn = 1, cli.hyperlink = FALSE)
Sys.setenv(SMOKE_NO_FEISHU = "1")

out_base <- config$project$output_dir
# checkpoints 与 Output 同级：…/61_Preeclampsia/checkpoints/Full_pipeline/_shared
ck_shared <- (pipeline_shared$checkpoint %||% list())$dir %||%
  file.path(dirname(dirname(out_base)), "checkpoints", basename(out_base), "_shared")
ck_shared <- as.character(ck_shared)[1L]
cli::cli_alert_info("checkpoint dir: {ck_shared}")

.pe_load_ck <- function(path) {
  obj <- readRDS(path)
  if (is.list(obj) && !is.null(obj$ctx)) obj$ctx else obj
}
ck_pick <- file.path(ck_shared, "multicollinearity_screen.rds")
if (!file.exists(ck_pick)) {
  ck_pick <- file.path(ck_shared, "step08_multicollinearity_screen.rds")
}
if (!file.exists(ck_pick)) stop("缺少 multicollinearity_screen checkpoint", call. = FALSE)
ctx <- .pe_load_ck(ck_pick)
ctx$config <- config
# 输出根指向 Full_pipeline（非 _shared），便于补跑目录落盘
ctx$config$project$output_dir <- out_base

# 载入轨迹块 + 补跑壳
source(file.path(root, "Blocks/26_trajectory/31block_trajectory_plot_gbmt_priori_mean_ci.R"), local = FALSE)
source(file.path(root, "Blocks/26_trajectory/30block_trajectory_plot_gbmt_priori.R"), local = FALSE)
source(file.path(root, "run/61_preeclampsia/blocks_shell/01block_pe_plan_supplement.R"), local = FALSE)

cli::cli_h1("pe_plan_supplement")
ctx <- block_pe_plan_supplement(ctx)
cli::cli_alert_success("补跑完成")
invisible(ctx)
