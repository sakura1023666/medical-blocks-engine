#!/usr/bin/env Rscript
# CKM 累积 eGDR × k-means × 卒中 — study_batch 入口
# 用法:
#   "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#     run/cum_egdr_kmeans_ckm/run_cum_egdr_kmeans_ckm_batch.R \
#     --config "/mnt/g/02block_result/46_CKM/累计暴露聚类_41654871/configs/config_cum_egdr_kmeans_ckm_batch.R" \
#     --shared-only
#   ... --workers auto

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
      opts$workers <- if (tolower(trimws(args[[i + 1L]])) == "auto") "auto" else as.integer(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--shared-only") { opts$shared_only <- TRUE; i <- i + 1L
    } else if (a == "--only-unit" && i < length(args)) {
      opts$only_unit <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
    } else if (a == "--no-skip") { opts$skip_existing <- FALSE; i <- i + 1L
    } else { i <- i + 1L }
  }
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) == "cum_egdr_kmeans_ckm" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
run_opts <- .parse_batch_args(args)
default_cfg <- file.path(
  Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"),
  "46_CKM", "累计暴露聚类_41654871", "configs", "config_cum_egdr_kmeans_ckm_batch.R"
)
config_path <- normalizePath(run_opts$config %||% default_cfg, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/rscript_study.R"))
source(config_path)
if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
run_opts$workers <- run_opts$workers %||% (config$study_batch$parallel_workers %||% "auto")
options(cli.hyperlink = FALSE, warn = 1)
run_study_batch(root, config, pipeline_shared, pipeline_unit = pipeline_unit,
                run_opts = run_opts, config_path = config_path)
