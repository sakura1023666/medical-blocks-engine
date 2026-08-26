#!/usr/bin/env Rscript
# run/incidence/run_incidence_single.R
# 薄入口：单库发病 Logistic 流水线
# --config 必填；可选 --only-index / --from / --to / --only
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
} else if (basename(script_path) == "incidence" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  root <- script_path
}
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
config_path <- NULL
only_index <- NULL
from_t <- NULL
to_t <- NULL
only_blocks <- NULL
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--config" && i < length(args)) {
    config_path <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--only-index" && i < length(args)) {
    only_index <- trimws(args[[i + 1L]]); i <- i + 2L
  } else if (args[[i]] == "--from" && i < length(args)) {
    from_t <- trimws(args[[i + 1L]]); i <- i + 2L
  } else if (args[[i]] == "--to" && i < length(args)) {
    to_t <- trimws(args[[i + 1L]]); i <- i + 2L
  } else if (args[[i]] == "--only" && i < length(args)) {
    only_blocks <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
  } else i <- i + 1L
}
if (is.null(config_path) || !nzchar(config_path))
  stop("--config 必填", call. = FALSE)
config_path <- normalizePath(config_path, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/cross_lagged_table1_harmonize.R"))
source(config_path)
config <- cross_lagged_apply_table1_harmonized(config, root)

if (!is.null(only_index) && nzchar(only_index)) {
  config$incidence$index_var <- only_index
  config$logistic$index_var <- only_index
  if (!is.null(config$prediction)) config$prediction$index_vars <- only_index
  if (!is.null(config$index)) {
    config$index$enable <- TRUE
    config$index$only <- only_index
  }
}

if (!exists("pipeline")) stop("config 未定义 pipeline", call. = FALSE)
options(warn = 1, cli.hyperlink = FALSE)
run_opts <- list()
if (!is.null(from_t) && nzchar(from_t)) run_opts$from <- from_t
if (!is.null(to_t) && nzchar(to_t)) run_opts$to <- to_t
if (!is.null(only_blocks) && length(only_blocks)) run_opts$only <- only_blocks
run_pipeline(root, config = config, pipeline = pipeline, run_opts = run_opts)
