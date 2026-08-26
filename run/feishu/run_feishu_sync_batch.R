#!/usr/bin/env Rscript
# 将已有 batch 汇总结果一次性同步到飞书（补历史 / 汇总后重推）
# 用法: FEISHU_APP_ID=... Rscript run_feishu_sync_batch.R

script_path <- tryCatch({
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}, error = function(e) normalizePath(getwd(), winslash = "/"))
if (basename(script_path) == "feishu" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  root <- script_path
}
setwd(root)

source(file.path(root, "R/feishu_env.R"))
feishu_load_dotenv(root)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))
source(file.path(root, "configs/templates/config_incidence_dual_batch.template.R"))

config$feishu$push_on_worker_finish <- TRUE
config$feishu$push_on_batch_summary <- TRUE

bc <- config$incidence_batch %||% list()
output_base <- bc$output_base %||% config$project$output_dir
candidate_vars <- incidence_batch_resolve_index_vars(config)
index_vars <- tryCatch(
  incidence_batch_resolve_from_shared_ck(config, candidate_vars, bc$db_mode %||% "both"),
  error = function(e) candidate_vars
)

statuses <- incidence_batch_read_all_status(output_base, index_vars)
incidence_batch_print_summary(statuses)
n <- incidence_batch_feishu_sync_all(config, statuses)
cat("飞书同步条数:", n, "\n")
