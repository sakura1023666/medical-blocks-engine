#!/usr/bin/env Rscript
# 飞书工作计划标记：多算法融合 TCF（脓毒症AKI / PMID 40295871）
# 表格: https://lcn1in9jd6ie.feishu.cn/base/RBjfb2iwmamW14s4WhKcS7kwnie
#
#   Rscript run/feishu/run_feishu_mark_ml_tcf_sepsis_aki.R [--dry-run]

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
  当前阶段 = "套路已建：决策树+config+run+TCF Blocks；待 shared-only/workers",
  是否已做Block = "是",
  验收标准 = paste0(
    "PMID40295871 TCF；Decisiontree/decision_tree_ml_tcf_sepsis_aki_40295871.md；",
    "config_ml_tcf_sa_aki.R；run/ml_tcf_sepsis_aki/；",
    "Blocks: ml_naive_bayes/ml_gbdt/ml_topsis_fusion/entropy_stepwise；",
    "python/ml_tcf；飞书本行"
  )
)

recs <- .feishu_bitable_list_records(cfg, table_id)
hit <- NULL
for (rec in recs) {
  mod <- as.character(rec$fields$`工作模块` %||% rec$fields$工作模块 %||% "")
  title <- as.character(rec$fields$`文献` %||% rec$fields$题目 %||% rec$fields$名称 %||% "")
  blob <- paste(mod, title, collapse = " ")
  if (grepl("多算法融合|TCF|40295871|脓毒性休克多专科", blob, ignore.case = TRUE) || grepl("多算法", mod, ignore.case = TRUE)) {
    hit <- rec
    break
  }
}
if (is.null(hit)) {
  ## 尝试按编号常见空行：打印候选供人工
  message("未精确匹配行；将尝试新增/请人工指定编号。候选模块关键词含 ML/预后 的前 10 条：")
  n <- 0L
  for (rec in recs) {
    mod <- as.character(rec$fields$`工作模块` %||% "")
    code <- as.character(rec$fields$编号 %||% "")
    if (grepl("ML|机器学习|预后|融合", mod) && n < 10L) {
      message("  ", code, " | ", mod)
      n <- n + 1L
    }
  }
  if (dry_run) quit(save = "no", status = 0)
  stop("请在飞书表中增加「多算法融合/TCF/40295871」行后重跑，或改本脚本匹配逻辑", call. = FALSE)
}

code <- as.character(hit$fields$编号 %||% "")
fields <- c(list(编号 = code), payload)
if (dry_run) {
  message("[dry-run] 将更新 ", code, " record=", hit$record_id)
  quit(save = "no", status = 0)
}
feishu_bitable_update_record(cfg, hit$record_id, fields, table_id = table_id)
message("已更新飞书工作计划: ", code)
