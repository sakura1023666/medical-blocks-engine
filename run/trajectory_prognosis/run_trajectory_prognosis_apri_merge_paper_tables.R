#!/usr/bin/env Rscript
# 合并双库论文表（Table 3 等）+ 清理 by_index 无用中间表
#
# 用法:
#   Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_merge_paper_tables.R \
#     --config configs/templates/config_trajectory_prognosis_batch.template.R --unit NLR

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_args <- function(args) {
  opts <- list(unit = "NLR", config = NULL)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--unit" && i < length(args)) { opts$unit <- trimws(args[[i + 1L]]); i <- i + 2L }
    else if (a == "--config" && i < length(args)) { opts$config <- trimws(args[[i + 1L]]); i <- i + 2L }
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
source(file.path(root, "R/utils.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
config_path <- if (!is.null(opt$config) && nzchar(opt$config)) {
  normalizePath(opt$config, winslash = "/", mustWork = TRUE)
} else file.path(root, "configs/templates/config_trajectory_prognosis_batch.template.R")
source(config_path)

source(file.path(root, "R/trajectory_paper_tables.R"))

base_root <- config$project$output_dir
ix <- opt$unit

# 双库 Table 3 合并（MIMIC 定 cut）
trajectory_merge_table3_dual_db(base_root, index_name = ix, cut_from_db = "mimic", end_day = 28L)

# 发表白名单整理（Figures/Tables 顺序编号；中间 CSV/错号表进 _archive/_raw）
source(file.path(root, "R/trajectory_pub_curate.R"), local = FALSE)
disease <- (config$feishu %||% list())$disease_label %||%
  config$project$disease %||% "ischemic stroke"
disease <- gsub("^\\d+_", "", as.character(disease)[1L])
disease <- gsub("_", " ", disease)
ix_out <- file.path(base_root, "by_index", ix)
if (!dir.exists(ix_out)) ix_out <- base_root
trajectory_curate_pub_outputs(
  base_dir = ix_out,
  index_name = ix,
  dbs = c("eicu", "mimic"),
  disease = disease
)

message("合并与发表整理完成。")
