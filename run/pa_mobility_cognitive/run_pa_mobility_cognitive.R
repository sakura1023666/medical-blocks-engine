#!/usr/bin/env Rscript
# PA–Mobility × 认知衰老 — 单流水线入口
# R: "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

script_path <- .init_script_dir()
if (basename(script_path) == "pa_mobility_cognitive" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
config_path <- "configs/config_pa_mobility_cognitive.R"
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--config" && i < length(args)) {
    config_path <- args[[i + 1L]]; i <- i + 2L
  } else i <- i + 1L
}
config_path <- normalizePath(config_path, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(config_path)

options(cli.hyperlink = FALSE, warn = 1)
run_pipeline(root, config, pipeline, run_opts = list())
