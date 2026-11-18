#!/usr/bin/env Rscript
# 飞书登记：预后 2.0（血脂异常 × 睡眠 × 死亡）
# 多维表格: https://lcn1in9jd6ie.feishu.cn/base/RBjfb2iwmamW14s4WhKcS7kwnie
# 不改旧预后套路那一行的状态。

script_path <- tryCatch({
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}, error = function(e) getwd())
if (basename(script_path) == "feishu" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
app_token <- Sys.getenv("FEISHU_WORKPLAN_APP_TOKEN",
                        Sys.getenv("FEISHU_BITABLE_APP_TOKEN", "RBjfb2iwmamW14s4WhKcS7kwnie"))
message("Feishu base: ", app_token)
message("套路名: 预后2.0")
message("PMID: 41904528")
message("决策树: Decisiontree/decision_tree_prognosis_v2.md")
message("配置: configs/config_prognosis_v2_sleep_dyslipid.R")
message("运行: run/prognosis_v2/run_prognosis_v2_batch.R")
message("输出: G:/02block_result/49_Dyslipidemia/prognosis_v2_41904528")
message("旧预后 config_survival_dual_batch 保持原状。")
if (!nzchar(Sys.getenv("FEISHU_APP_ID", ""))) {
  message("未配置 FEISHU_APP_ID，本次只打印登记信息，不写表。")
}
