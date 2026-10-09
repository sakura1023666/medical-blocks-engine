#!/usr/bin/env Rscript
# 飞书工作计划：登记/更新 CKM 累积 eGDR k-means 套路
# base: https://lcn1in9jd6ie.feishu.cn/base/RBjfb2iwmamW14s4WhKcS7kwnie
#
#   Rscript run/feishu/run_feishu_mark_cum_egdr_kmeans_ckm.R --dry-run
#   Rscript run/feishu/run_feishu_mark_cum_egdr_kmeans_ckm.R

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

args <- commandArgs(trailingOnly = TRUE)
dry_run <- "--dry-run" %in% args

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/feishu_bitable.R"))

app_token <- Sys.getenv("FEISHU_WORKPLAN_APP_TOKEN", "RBjfb2iwmamW14s4WhKcS7kwnie")
table_id  <- Sys.getenv("FEISHU_WORKPLAN_TABLE_ID", "tblenCHO3ErYIpYp")
cfg <- list(
  app_id = Sys.getenv("FEISHU_APP_ID"),
  app_secret = Sys.getenv("FEISHU_APP_SECRET"),
  app_token = app_token,
  table_id = table_id
)

payload <- list(
  状态 = "进行中",
  当前阶段 = "阶段一工程落地（对抗阅读PASS；config/run/Blocks76已写；待试跑）",
  是否已做Block = "是",
  验收标准 = paste0(
    "发病地基+76后缀；index batch=",
    "eGDR(全深度kmeans)+TyG/AIP/CHG/NHHR/VAI/LAP/METSIR/SHR；",
    "年龄60；cum×3；Decisiontree/decision_tree_cum_egdr_kmeans_ckm.md"
  )
)

module_kw <- c("CKM", "eGDR", "累积", "41654871", "卒中")
recs <- tryCatch(.feishu_bitable_list_records(cfg, table_id), error = function(e) {
  message("飞书列表失败: ", conditionMessage(e)); list()
})

hit <- NULL
for (rec in recs) {
  mod <- as.character(rec$fields$`工作模块` %||% rec$fields$工作模块 %||% "")
  cfgname <- as.character(rec$fields$`配置文件` %||% rec$fields$config %||% "")
  if (grepl("cum_egdr_kmeans|CKM.*eGDR|累计暴露聚类", paste(mod, cfgname), ignore.case = TRUE)) {
    hit <- rec; break
  }
  if (any(vapply(module_kw, function(k) grepl(k, mod, fixed = TRUE), logical(1)))) {
    # 弱匹配仅作候选
    if (is.null(hit)) hit <- rec
  }
}

if (is.null(hit)) {
  message("飞书未找到既有 CKM/eGDR 行；请在工作计划表手动新增一行后重跑本脚本，或把编号通过环境变量 FEISHU_CKM_ROW_CODE 指定。")
  if (!dry_run) quit(status = 0)
} else {
  code <- as.character(hit$fields$编号 %||% "")
  fields <- c(list(编号 = code), payload)
  if (dry_run) {
    message("[dry-run] 将更新记录 ", code, " / ", hit$record_id)
  } else {
    feishu_bitable_update_record(cfg, hit$record_id, fields, table_id = table_id)
    message("已更新飞书: ", code)
  }
}
