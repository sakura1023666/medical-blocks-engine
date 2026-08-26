#!/usr/bin/env Rscript
# =============================================================================
#  血镉×骨质疏松 NHANES 批量入口（RCS / 亚组 / 中介 并行 worker）
#  配置: configs/templates/config_environment_dkd_batch.template.R
#
#  用法:
#    Rscript run/environment/run_environment_cd_osteo_batch.R
#    Rscript run/environment/run_environment_cd_osteo_batch.R --workers 4
#    Rscript run/environment/run_environment_cd_osteo_batch.R --shared-only
#    Rscript run/environment/run_environment_cd_osteo_batch.R --only-unit rcs,subgroup
# =============================================================================

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
      raw_w <- trimws(args[[i + 1L]])
      opts$workers <- if (tolower(raw_w) == "auto") "auto" else as.integer(raw_w)
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
if (basename(script_path) == "environment" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

args     <- commandArgs(trailingOnly = TRUE)
run_opts <- .parse_batch_args(args)
config_path <- run_opts$config %||% file.path(root, "configs/templates/config_environment_dkd_batch.template.R")
config_path <- normalizePath(config_path, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/nhanes_survey_weight.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/rscript_study.R"))
source(config_path)

if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
run_opts$workers <- run_opts$workers %||% (config$study_batch$parallel_workers %||% "auto")
options(cli.hyperlink = FALSE, warn = 1)

run_study_batch(
  root, config, pipeline_shared,
  pipeline_unit = pipeline_unit,
  run_opts = run_opts,
  config_path = config_path
)
