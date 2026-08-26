#!/usr/bin/env Rscript
# 整理轨迹预后发表图表：Fig1 纳排占位 + 文献顺序主图；Tables 去重归档
#
# 用法:
#   Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_curate_pub.R \
#     --config configs/templates/config_trajectory_prognosis_batch.template.R --unit NLR

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_args <- function(args) {
  opts <- list(unit = "NLR", config = NULL, dbs = c("eicu", "mimic"))
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--unit" && i < length(args)) { opts$unit <- trimws(args[[i + 1L]]); i <- i + 2L }
    else if (a == "--config" && i < length(args)) { opts$config <- trimws(args[[i + 1L]]); i <- i + 2L }
    else if (a == "--db" && i < length(args)) { opts$dbs <- strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]; i <- i + 2L }
    else i <- i + 1L
  }
  opts
}

script_path <- .init_script_dir()
root <- if (basename(script_path) == "trajectory_prognosis" && basename(dirname(script_path)) == "run") {
  normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else script_path
setwd(root)

opt <- .parse_args(commandArgs(trailingOnly = TRUE))
ix <- opt$unit

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(root, "R/trajectory_pub_curate.R"))

config_path <- if (!is.null(opt$config) && nzchar(opt$config)) {
  normalizePath(opt$config, winslash = "/", mustWork = TRUE)
} else file.path(root, "configs/templates/config_trajectory_prognosis_batch.template.R")
source(config_path)

config_ix <- trajectory_batch_patch_config_for_index(config, ix)
base_dir <- trajectory_batch_index_output_dir(config_ix, ix)

trajectory_curate_pub_outputs(
  base_dir, index_name = ix, dbs = opt$dbs,
  db_labels = list(eicu = "eICU", mimic = "MIMIC")
)
message("发表图表整理完成。")
