#!/usr/bin/env Rscript
# run/ml/run_ml_nafld_cm.R — 34 脂肪肝定制课题入口（不改通用模板）
.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) return(normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/"))
  normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
env_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (nzchar(env_root)) {
  root <- normalizePath(env_root, winslash = "/", mustWork = TRUE)
} else if (basename(script_path) == "ml" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  root <- script_path
}
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
config_path <- NULL
from_t <- NULL
to_t <- NULL
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--config" && i < length(args)) {
    config_path <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--from" && i < length(args)) {
    from_t <- trimws(args[[i + 1L]]); i <- i + 2L
  } else if (args[[i]] == "--to" && i < length(args)) {
    to_t <- trimws(args[[i + 1L]]); i <- i + 2L
  } else i <- i + 1L
}
if (is.null(config_path) || !nzchar(config_path))
  stop("--config 必填", call. = FALSE)
config_path <- normalizePath(config_path, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(config_path)
if (!is.null(config$project) && (is.null(config$project$root) || !nzchar(config$project$root))) {
  config$project$root <- root
}
if (!exists("pipeline")) stop("config 未定义 pipeline", call. = FALSE)
options(warn = 1, cli.hyperlink = FALSE)
run_opts <- list()
if (!is.null(from_t) && nzchar(from_t)) run_opts$from <- from_t
if (!is.null(to_t) && nzchar(to_t)) run_opts$to <- to_t
run_pipeline(root, config = config, pipeline = pipeline, run_opts = run_opts)
