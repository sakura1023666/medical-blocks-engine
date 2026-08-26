#!/usr/bin/env Rscript
# 缺血性脑卒中两阶段 Transformer — 任务并行 Worker 子进程
#
# 用法:
#   Rscript run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_worker.R \
#     --unit L72_B_twostage --config ".../config_two_stage_transformer_stroke_task_parallel.template.R" \
#     [--epochs 1] [<root>]
#
# unit 对应 config$tst_stroke$branch_map[[unit]]（R blocks + python_mode），由
# Task7 的 R/tst_stroke_task_runner.R::tst_stroke_run_unit() 解析并派发；本 worker
# 入口先行落地并可 parse/可 source config，在 runner 文件出现前以清晰报错退出。

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_worker_args <- function(args) {
  opts <- list(unit = NULL, root = NULL, config = NULL, epochs = NULL)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--unit" && i < length(args)) {
      opts$unit <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--epochs" && i < length(args)) {
      opts$epochs <- suppressWarnings(as.integer(args[[i + 1L]])); i <- i + 2L
    } else if (!startsWith(a, "--") && is.null(opts$root)) {
      opts$root <- a; i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  if (is.null(opts$unit) || !nzchar(opts$unit)) {
    env_unit <- trimws(Sys.getenv("TST_STROKE_UNIT", ""))
    if (nzchar(env_unit)) opts$unit <- env_unit
  }
  if (is.null(opts$unit) || !nzchar(opts$unit)) stop("--unit \u53c2\u6570\u5fc5\u586b", call. = FALSE)
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) == "two_stage_transformer_stroke" && basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}
setwd(script_path)

args    <- commandArgs(trailingOnly = TRUE)
wk_opts <- .parse_worker_args(args)

root_guess <- normalizePath(getwd(), winslash = "/")
if (!is.null(wk_opts$root) && nzchar(wk_opts$root)) {
  root_guess <- normalizePath(wk_opts$root, winslash = "/", mustWork = TRUE)
}

owd <- getwd()
setwd(root_guess)
on.exit(setwd(owd), add = TRUE)
root <- root_guess

unit <- wk_opts$unit

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/rscript_study.R"))

config_path <- if (!is.null(wk_opts$config) && nzchar(wk_opts$config)) {
  normalizePath(wk_opts$config, winslash = "/", mustWork = TRUE)
} else {
  normalizePath(
    file.path(root, "configs/templates/config_two_stage_transformer_stroke_task_parallel.template.R"),
    winslash = "/", mustWork = TRUE
  )
}
source(config_path)

if (nzchar(as.character(config$feishu$app_token %||% "")[1L])) {
  Sys.setenv(FEISHU_BITABLE_APP_TOKEN = config$feishu$app_token)
}
if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)

if (!is.null(wk_opts$epochs) && !is.na(wk_opts$epochs)) {
  config$tst_stroke$worker_epochs <- wk_opts$epochs
}

source(file.path(root, "R/feishu_bitable.R"))
source(file.path(root, "R/tst_stroke_task_runner.R"))

t_start <- proc.time()
tryCatch({
  final_ctx <- tst_stroke_run_unit(
    root, config, unit = unit,
    pipeline_shared = pipeline_shared, t_start = t_start,
    config_path = config_path
  )
  quit(save = "no", status = 0)
}, error = function(e) {
  cli::cli_alert_danger("{unit}: {conditionMessage(e)}")
  quit(save = "no", status = 1)
})
