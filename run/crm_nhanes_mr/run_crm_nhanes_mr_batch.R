#!/usr/bin/env Rscript
# NHANES CRM x MR 批量 — configs/templates/config_crm_nhanes_mr_batch.template.R

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
.parse_batch_args <- function(args) {
  opts <- list(config = NULL, workers = NULL, shared_only = FALSE, only_unit = NULL, skip_existing = TRUE)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) { opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--workers" && i < length(args)) {
      opts$workers <- if (tolower(trimws(args[[i + 1L]])) == "auto") "auto" else as.integer(args[[i + 1L]])
      i <- i + 2L
    } else if (a == "--shared-only") { opts$shared_only <- TRUE; i <- i + 1L
    } else if (a == "--only-unit" && i < length(args)) {
      opts$only_unit <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
    } else if (a == "--no-skip") { opts$skip_existing <- FALSE; i <- i + 1L
    } else { i <- i + 1L }
  }
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) == "crm_nhanes_mr" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
run_opts <- .parse_batch_args(args)
config_path <- normalizePath(run_opts$config %||% file.path(root, "configs/templates/config_crm_nhanes_mr_batch.template.R"), winslash = "/", mustWork = TRUE)

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/rscript_study.R"))
source(config_path)

if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
run_opts$workers <- run_opts$workers %||% (config$study_batch$parallel_workers %||% "auto")
options(cli.hyperlink = FALSE, warn = 1)

run_study_batch(root, config, pipeline_shared, pipeline_unit = pipeline_unit, run_opts = run_opts, config_path = config_path)
