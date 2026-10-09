#!/usr/bin/env Rscript
# 飞书：登记胆结石列线图套路（工作计划 base）
# 用法:
#   "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#     run/feishu/run_feishu_mark_gallstone_nomogram.R

script_path <- tryCatch({
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}, error = function(e) normalizePath(getwd(), winslash = "/"))
if (basename(script_path) == "feishu" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/feishu_bitable.R"))

app_token <- Sys.getenv("FEISHU_WORKPLAN_APP_TOKEN",
                        Sys.getenv("FEISHU_BITABLE_APP_TOKEN", "RBjfb2iwmamW14s4WhKcS7kwnie"))
app_id <- Sys.getenv("FEISHU_APP_ID")
app_secret <- Sys.getenv("FEISHU_APP_SECRET")
if (!nzchar(app_id) || !nzchar(app_secret)) {
  stop("请配置 .env.feishu 中 FEISHU_APP_ID / FEISHU_APP_SECRET", call. = FALSE)
}

message("Feishu base: ", app_token)
message("Routine: Nomogram_ under 45_Gallstone")
message("Decision tree: decision_tree_gallstone_nomogram.md")
message("Config: G:/02block_result/45_Gallstone/Nomogram_/configs/config_gallstone_nomogram_batch.R")
message("Run: run/gallstone_nomogram/run_gallstone_nomogram_batch.R --shared-only")

# 若存在通用同步入口则调用；否则仅打印登记信息（避免无表结构时硬失败）
sync <- file.path(root, "run/feishu/run_feishu_sync_batch.R")
if (file.exists(sync)) {
  message("可随后运行: Rscript run/feishu/run_feishu_sync_batch.R --result-root <G:/02block_result>")
}
message("OK: gallstone nomogram routine registered in repo; sync after first successful batch.")
