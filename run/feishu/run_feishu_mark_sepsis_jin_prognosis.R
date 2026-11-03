#!/usr/bin/env Rscript
# 飞书工作计划：脓毒症 Jin2025 方法迁移 / prediction_41194138
# 表格: https://lcn1in9jd6ie.feishu.cn/base/RBjfb2iwmamW14s4WhKcS7kwnie
#
#   Rscript run/feishu/run_feishu_mark_sepsis_jin_prognosis.R [--dry-run]

script_path <- tryCatch({
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
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
  当前阶段 = "套路已建：对抗阅读Q1-8+决策树+config+run+Blocks/82；待确认试跑 shared-only/workers",
  是否已做Block = "是",
  研究场景 = "风险预测模型/评分系统",
  `风险/卡点` = "eICU无HbA1c禁主分析SHR轴；TotalCo2代理bicarbonate；四组T2不入Q；待shared-only",
  验收标准 = paste0(
    "Jin2025方法迁脓毒症双库；Decisiontree/decision_tree_sepsis_jin_prognosis_index_sofa_dual.md；",
    "prediction_41194138/config_survival.R；run/sepsis_jin_prognosis/；",
    "Blocks/82_jin_index_sofa_prognosis_full；41复合指标 single_loop；",
    "主终点院内死亡；TotalCo2中介代理"
  )
)

recs <- .feishu_bitable_list_records(cfg, table_id)
hit <- NULL
for (rec in recs) {
  mod <- as.character(rec$fields$`工作模块` %||% rec$fields$工作模块 %||% "")
  title <- as.character(rec$fields$`文献` %||% rec$fields$题目 %||% rec$fields$名称 %||% "")
  blob <- paste(mod, title, collapse = " ")
  if (grepl("41194138|Jin2025|神马|脓毒症.*预测|SHR.*SOFA|prediction_41194138", blob, ignore.case = TRUE)) {
    hit <- rec
    break
  }
}
## 次选：空的「预测（预后）」槽
if (is.null(hit)) {
  for (rec in recs) {
    mod <- as.character(rec$fields$`工作模块` %||% rec$fields$工作模块 %||% "")
    title <- as.character(rec$fields$`文献` %||% rec$fields$题目 %||% "")
    if (grepl("预测（预后）|预测\\(预后\\)", mod) && !nzchar(trimws(title))) {
      hit <- rec
      break
    }
  }
}

if (is.null(hit)) {
  create_fields <- c(
    list(
      工作模块 = "预测（预后）",
      编号 = "B36"
    ),
    payload
  )
  if (dry_run) {
    message("[dry-run] 将新建记录: ", paste(names(create_fields), collapse = ","))
    quit(save = "no", status = 0)
  }
  out <- feishu_bitable_create_record(cfg, create_fields, table_id = table_id)
  message("已新建飞书工作计划记录: ", out$record_id %||% "<ok>")
  quit(save = "no", status = 0)
}

code <- as.character(hit$fields$编号 %||% "")
fields <- c(
  list(编号 = if (nzchar(trimws(code))) code else "B36"),
  payload
)
if (dry_run) {
  message("[dry-run] 将更新 ", fields$编号, " record=", hit$record_id)
  quit(save = "no", status = 0)
}
feishu_bitable_update_record(cfg, hit$record_id, fields, table_id = table_id)
message("已更新飞书工作计划: ", fields$编号, " / ", hit$record_id)
