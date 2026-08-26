#!/usr/bin/env Rscript
# 重跑 JLCM + 下游表格（Table 2 自动选类、Table S5、Table 3、Chisq）
#
# 用法:
#   Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_rerun_jlcm.R \
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

jlcm_blocks <- c(
  "trajectory_jlcm",
  "trajectory_baseline_by_class",
  "trajectory_piecewise_cox",
  "trajectory_chisq"
)

for (db in opt$dbs) {
  cli::cli_h1("[{ix}] {toupper(db)} — 重跑 JLCM + Table 2/3/S5")
  ck_dir <- trajectory_batch_index_ck_dir(config_ix, ix, db)
  ctx <- tryCatch(
    study_batch_load_checkpoint_ctx(ck_dir, "multicollinearity_final"),
    error = function(e) { cli::cli_alert_danger("载入检查点失败: {conditionMessage(e)}"); NULL }
  )
  if (is.null(ctx)) next

  db_cfg <- if (identical(db, "eicu")) config_ix$dual_db$primary else config_ix$dual_db$secondary
  cfg_db <- config_ix
  cfg_db$project$database   <- db_cfg$name %||% toupper(db)
  cfg_db$project$output_dir <- file.path(config_ix$project$output_dir, db)
  if (!is.null(cfg_db$trajectory_jlcm$rawdata_path_template)) {
    cfg_db$trajectory_jlcm$rawdata_path_template <- gsub(
      "\\{db\\}", db, cfg_db$trajectory_jlcm$rawdata_path_template
    )
  }
  ctx$config <- cfg_db
  ctx$root_output_dir <- cfg_db$project$output_dir

  pl <- pipeline_unit
  pl$checkpoint <- list(enable = TRUE, dir = ck_dir)

  ok <- tryCatch({
    run_pipeline(root, config = cfg_db, pipeline = pl,
                 run_opts = list(initial_ctx = ctx, only = jlcm_blocks))
    TRUE
  }, error = function(e) { cli::cli_alert_danger("{conditionMessage(e)}"); FALSE })
  if (ok) cli::cli_alert_success("[{ix}/{toupper(db)}] JLCM 下游完成")
}

source(file.path(root, "R/trajectory_paper_tables.R"))
trajectory_merge_table3_dual_db(config_ix$project$output_dir, index_name = ix, cut_from_db = "mimic", end_day = 28L)
message("JLCM 重跑与 Table 3 合并完成。")
