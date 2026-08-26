#!/usr/bin/env Rscript
# SEM + 链式中介 — configs/templates/config_sem_chain_mediation_charls.template.R

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

script_path <- .init_script_dir()
if (basename(script_path) == "sem_chain_mediation" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
config_path <- if (length(args) >= 2L && args[1L] == "--config") {
  normalizePath(args[2L], winslash = "/", mustWork = TRUE)
} else normalizePath(file.path(root, "configs/templates/config_sem_chain_mediation_charls.template.R"), winslash = "/", mustWork = TRUE)

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/rscript_study.R"))
source(config_path)
if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)
run_pipeline(root, config = config, pipeline = pipeline)
