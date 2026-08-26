#!/usr/bin/env Rscript
# =============================================================================
#  轨迹预后 APRI 单指标 — 仅重跑「图表 block」（跳过昂贵的 JLCM 重算）
#
#  从 by_index/<ix>/<db>/trajectory_baseline_by_class.rds 检查点载入 ctx，
#  仅重跑 JLCM 之后的全部绘图/表格 block（样式已按参考脚本对齐）。
#
#  用法:
#    Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_refig.R \
#      --config configs/templates/config_trajectory_prognosis_batch.template.R --unit NLR
# =============================================================================

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_args <- function(args) {
  opts <- list(unit = "NLR", config = NULL, dbs = c("eicu", "mimic"))
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--unit" && i < length(args)) { opts$unit <- trimws(args[[i + 1L]]); i <- i + 2L }
    else if (a == "--config" && i < length(args)) { opts$config <- trimws(args[[i + 1L]]); i <- i + 2L }
    else if (a == "--db" && i < length(args)) { opts$dbs <- strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]; i <- i + 2L }
    else if (a == "--blocks" && i < length(args)) { opts$blocks <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L }
    else i <- i + 1L
  }
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) == "trajectory_prognosis" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
opt  <- .parse_args(args)
ix   <- opt$unit

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))

config_path <- if (!is.null(opt$config) && nzchar(opt$config)) {
  normalizePath(opt$config, winslash = "/", mustWork = TRUE)
} else file.path(root, "configs/templates/config_trajectory_prognosis_batch.template.R")
source(config_path)

config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)

config_ix <- trajectory_batch_patch_config_for_index(config, ix)

# 仅重跑 JLCM 之后的图表 block（baseline_by_class=Table S5 由 --with-tables 单独控制）
fig_blocks <- c(
  "trajectory_plot_jlcm",
  "trajectory_km_class",
  "trajectory_dynpred",
  "trajectory_dynpred_individual",
  "trajectory_piecewise_cox",
  "trajectory_weibull_compare",
  "trajectory_subgroup_class",
  "trajectory_chisq"
)
if (!is.null(opt$blocks) && length(opt$blocks)) fig_blocks <- opt$blocks

for (db in opt$dbs) {
  cli::cli_h1("[{ix}] {toupper(db)} — 仅重跑图表 block（从 trajectory_baseline_by_class 检查点续跑）")
  ck_dir <- trajectory_batch_index_ck_dir(config_ix, ix, db)
  ctx <- tryCatch(
    study_batch_load_checkpoint_ctx(ck_dir, c("trajectory_baseline_by_class", "trajectory_jlcm")),
    error = function(e) { cli::cli_alert_danger("[{ix}/{toupper(db)}] 载入检查点失败: {conditionMessage(e)}"); NULL }
  )
  if (is.null(ctx)) next

  db_cfg <- if (identical(db, "eicu")) config_ix$dual_db$primary else config_ix$dual_db$secondary
  cfg_db <- config_ix
  cfg_db$project$database   <- db_cfg$name %||% toupper(db)
  cfg_db$project$output_dir <- file.path(config_ix$project$output_dir, db)
  if (!is.null(cfg_db$trajectory_jlcm$rawdata_path_template)) {
    cfg_db$trajectory_jlcm$rawdata_path_template <- gsub(
      "\\{db\\}", db, cfg_db$trajectory_jlcm$rawdata_path_template)
  }
  ctx$config <- cfg_db
  ctx$root_output_dir <- cfg_db$project$output_dir

  pl <- pipeline_unit
  pl$checkpoint <- list(enable = TRUE, dir = ck_dir)

  ok <- tryCatch({
    run_pipeline(root, config = cfg_db, pipeline = pl,
                 run_opts = list(initial_ctx = ctx, only = fig_blocks))
    TRUE
  }, error = function(e) { cli::cli_alert_danger("[{ix}/{toupper(db)}] {conditionMessage(e)}"); FALSE })

  if (ok) cli::cli_alert_success("[{ix}/{toupper(db)}] 图表重跑完成")
}
