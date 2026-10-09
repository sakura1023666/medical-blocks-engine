#!/usr/bin/env Rscript
# GLIDE-SOL Seoul 100m CPU smoke (+ optional GEE domain)
# config: configs/config_glide_sol_seoul.R

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
if (basename(script_path) == "environment" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  root <- script_path
}
setwd(root)
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)

args <- commandArgs(trailingOnly = TRUE)
config_path <- file.path(root, "configs/config_glide_sol_seoul.R")
i <- match("--config", args)
if (!is.na(i) && i < length(args)) {
  config_path <- normalizePath(args[i + 1L], winslash = "/")
}

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/python_literature.R"))
source(config_path)

# Prefer project venv for Python
venv_py <- file.path(root, ".venv_ml_pub", "bin", "python")
if (file.exists(venv_py)) Sys.setenv(PYTHON = venv_py)

run_opts <- pipeline_parse_cli(args[args != "--config" & args != config_path])
options(cli.hyperlink = FALSE, warn = 1)

cli::cli_alert_info("GLIDE-SOL Seoul 100m -> {config$project$output_dir}")
run_pipeline(root, config = config, pipeline = pipeline, run_opts = run_opts)
cli::cli_alert_success("GLIDE-SOL pipeline finished")
