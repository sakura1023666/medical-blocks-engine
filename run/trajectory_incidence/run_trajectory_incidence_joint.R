#!/usr/bin/env Rscript
# run_trajectory_incidence_joint.R — 联合轨迹发病套路 单跑入口
# 用法:
#   Rscript run/trajectory_incidence/run_trajectory_incidence_joint.R [--config <path>]
#           [--from <block>] [--to <block>] [--blocks b1,b2] [--resume]
# 默认 config = configs/templates/config_trajectory_incidence_joint.template.R
#   （真实课题请把模板拷到课题 configs/ 改后 --config 指过去）

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
root <- if (basename(dirname(script_path)) == "run")
  normalizePath(file.path(script_path, "..", ".."), winslash = "/") else script_path
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
config_path <- file.path(root, "configs/templates/config_trajectory_incidence_joint.template.R")
i <- match("--config", args)
rest <- args
if (!is.na(i) && i < length(args)) {
  config_path <- normalizePath(args[i + 1L], winslash = "/")
  rest <- args[-c(i, i + 1L)]
}

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(config_path)

run_opts <- pipeline_parse_cli(rest)
if (is.null(run_opts$root)) run_opts$root <- root

if (isTRUE(run_opts$list_ck)) {
  ck <- file.path(root, "checkpoints")
  if (dir.exists(ck)) {
    print(list.files(ck, pattern = "^step", full.names = FALSE))
  } else cli::cli_alert("检查点目录为空: {ck}")
  quit(status = 0)
}
options(cli.hyperlink = FALSE, warn = 1)

t0 <- Sys.time(); status <- "success"; err <- ""
tryCatch({
  run_pipeline(root, config = config, pipeline = pipeline, run_opts = run_opts)
}, error = function(e) {
  status <<- "error"; err <<- conditionMessage(e)
  cli::cli_alert_danger("联合轨迹发病失败: {err}")
})
el <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
cli::cli_alert("联合轨迹发病 [{status}] 用时 {el} min")
if (status != "success") quit(status = 1)
