#!/usr/bin/env Rscript
# 缺血性脑卒中两阶段 Transformer — 任务并行总入口
# configs/templates/config_two_stage_transformer_stroke_task_parallel.template.R
#
# 用法:
#   Rscript run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R
#   Rscript run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R --shared-only
#   Rscript run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R \
#     --only-unit L72_B_twostage,external_synthetic --workers 2
#   Rscript run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R --list-units
#
# Runner: R/tst_stroke_task_runner.R :: tst_stroke_run_task_parallel(root, config,
#   pipeline_shared, units, workers)（Task7 交付）。本入口先行落地并可 parse/可
#   source config；在 runner 文件出现前，非 --list-units 调用会以清晰报错退出。

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_tp_args <- function(args) {
  opts <- list(config = NULL, workers = NULL, shared_only = FALSE, only_unit = NULL,
               list_units = FALSE, skip_existing = TRUE)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--workers" && i < length(args)) {
      opts$workers <- if (tolower(trimws(args[[i + 1L]])) == "auto") "auto" else as.integer(args[[i + 1L]])
      i <- i + 2L
    } else if (a == "--shared-only") {
      opts$shared_only <- TRUE; i <- i + 1L
    } else if (a == "--only-unit" && i < length(args)) {
      opts$only_unit <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
    } else if (a == "--list-units") {
      opts$list_units <- TRUE; i <- i + 1L
    } else if (a == "--no-skip") {
      opts$skip_existing <- FALSE; i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) == "two_stage_transformer_stroke" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

args     <- commandArgs(trailingOnly = TRUE)
run_opts <- .parse_tp_args(args)
.default_cfg <- {
  proj_cfg_cands <- c(
    "G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421/config_two_stage_transformer_stroke_task_parallel.R",
    "/mnt/g/02block_result/11_ischemic stroke/two_stage_transformer_40041421/config_two_stage_transformer_stroke_task_parallel.R"
  )
  hit <- proj_cfg_cands[file.exists(proj_cfg_cands)]
  if (length(hit)) {
    hit[[1]]
  } else {
    file.path(root, "configs/templates/config_two_stage_transformer_stroke_task_parallel.template.R")
  }
}
config_path <- normalizePath(
  run_opts$config %||% .default_cfg,
  winslash = "/", mustWork = TRUE
)

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/rscript_study.R"))
source(config_path)

if (nzchar(as.character(config$feishu$app_token %||% "")[1L])) {
  Sys.setenv(FEISHU_BITABLE_APP_TOKEN = config$feishu$app_token)
}
if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)

source(file.path(root, "R/tst_stroke_task_runner.R"))
resolved <- tst_stroke_resolve_task_units(config, explicit_units = task_units)
task_units <- resolved$units
config$tst_stroke$branch_map <- resolved$branch_map

units   <- if (length(run_opts$only_unit)) run_opts$only_unit else task_units
workers <- run_opts$workers %||% "auto"

if (isTRUE(run_opts$list_units)) {
  cat(paste(units, collapse = "\n"), "\n")
  cat("# units:", length(units), "\n")
  quit(save = "no", status = 0)
}

if (isTRUE(run_opts$shared_only)) units <- character(0)

tst_stroke_run_task_parallel(
  root, config, pipeline_shared,
  units = units, workers = workers,
  config_path = config_path,
  skip_existing = isTRUE(run_opts$skip_existing),
  pipeline_unit = pipeline_unit
)
