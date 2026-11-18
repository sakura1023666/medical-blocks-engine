#!/usr/bin/env Rscript
# 飞书工作计划：登记 COPD 轨迹 JLCM/PAMM 套路
# base: https://lcn1in9jd6ie.feishu.cn/base/RBjfb2iwmamW14s4WhKcS7kwnie
#
#   Rscript run/feishu/run_feishu_mark_copd_trajectory_jlcm.R --dry-run
#   Rscript run/feishu/run_feishu_mark_copd_trajectory_jlcm.R

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
  当前阶段 = "工程落地（决策树已确认；PAMM新块+外验强化+config/run已写；待prepare与试跑）",
  是否已做Block = "是",
  验收标准 = paste0(
    "预后地基+轨迹后缀；MIMIC发现→eICU套参；dual_safe复合指标；",
    "PAMM(P5/P95锁定)；K=2-6自选；Decisiontree/decision_tree_trajectory_prognosis_copd_jlcm.md；",
    "文献fcimb-16-1871653方法迁移"
  )
)

module_kw <- c("COPD", "42558177", "轨迹", "JLCM", "PAMM", "体温", "1871653")
recs <- tryCatch(.feishu_bitable_list_records(cfg, table_id), error = function(e) {
  message("飞书列表失败: ", conditionMessage(e)); list()
})

hit <- NULL
for (rec in recs) {
  mod <- as.character(rec$fields$`工作模块` %||% rec$fields$工作模块 %||% "")
  cfgname <- as.character(rec$fields$`配置文件` %||% rec$fields$config %||% "")
  blob <- paste(mod, cfgname)
  if (grepl("COPD|42558177|copd_jlcm|fcimb-16-1871653", blob, ignore.case = TRUE)) {
    hit <- rec; break
  }
}

if (is.null(hit)) {
  message("飞书未找到 COPD/42558177 行；请手动新增后重跑，或设 FEISHU_COPD_ROW_CODE。")
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
