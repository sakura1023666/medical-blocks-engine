#!/usr/bin/env Rscript
# 仅重导出 Table 2 / Table 3 / 后验分类表（不重跑单因素/多因素/JLCM）
#
# 用法:
#   Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_reexport_tables.R \
#     --config configs/templates/config_trajectory_prognosis_batch.template.R --unit NLR

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
    else i <- i + 1L
  }
  opts
}

script_path <- .init_script_dir()
root <- if (basename(script_path) == "trajectory_prognosis" && basename(dirname(script_path)) == "run") {
  normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else script_path
setwd(root)

opt <- .parse_args(commandArgs(trailingOnly = TRUE))
ix <- opt$unit

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(root, "R/trajectory_paper_tables.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))

config_path <- if (!is.null(opt$config) && nzchar(opt$config)) {
  normalizePath(opt$config, winslash = "/", mustWork = TRUE)
} else file.path(root, "configs/templates/config_trajectory_prognosis_batch.template.R")
source(config_path)
config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)

config_ix <- trajectory_batch_patch_config_for_index(config, ix)
ctx_merge <- NULL

for (db in opt$dbs) {
  cli::cli_h1("[{ix}] {toupper(db)} — 仅重导出 Table 2/3/S4")
  ck_dir <- trajectory_batch_index_ck_dir(config_ix, ix, db)
  ctx <- tryCatch(
    study_batch_load_checkpoint_ctx(ck_dir, "trajectory_piecewise_cox"),
    error = function(e) {
      study_batch_load_checkpoint_ctx(ck_dir, "trajectory_jlcm")
    }
  )
  if (is.null(ctx)) {
    cli::cli_alert_warning("无可用检查点，跳过 {db}")
    next
  }

  db_cfg <- if (identical(db, "eicu")) config_ix$dual_db$primary else config_ix$dual_db$secondary
  cfg_db <- config_ix
  cfg_db$project$database   <- db_cfg$name %||% toupper(db)
  cfg_db$project$output_dir <- file.path(config_ix$project$output_dir, db)
  ctx$config <- cfg_db
  ctx$root_output_dir <- cfg_db$project$output_dir

  trajectory_reexport_paper_tables(ctx, cfg_db, ix)
  if (is.null(ctx_merge) && identical(db, "eicu")) ctx_merge <- ctx
  cli::cli_alert_success("[{ix}/{toupper(db)}] 表已重导出")
}

if (is.null(ctx_merge)) {
  ctx_merge <- list(
    config = config_ix,
    root_output_dir = file.path(config_ix$project$output_dir, "eicu"),
    output_dir_tables = file.path(config_ix$project$output_dir, "by_index", ix, "eicu", "Tables")
  )
}

trajectory_merge_table3_dual_db(
  trajectory_batch_index_output_dir(config_ix, ix), index_name = ix,
  cut_from_db = "mimic", end_day = 28L, ctx = ctx_merge
)
message("重导出完成（未重跑单因素/多因素）。")
