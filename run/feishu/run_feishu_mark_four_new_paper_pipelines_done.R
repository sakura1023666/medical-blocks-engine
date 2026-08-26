#!/usr/bin/env Rscript
# 在飞书「block套路工作计划」中标记四套新文献流水线为已完成
# 表格: https://lcn1in9jd6ie.feishu.cn/base/RBjfb2iwmamW14s4WhKcS7kwnie

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

mark_rows <- list(
  list(code = "B30", module_kw = "用药", config = "config_medication_regimen_text_soft.R"),
  list(code = "B31", module_kw = "马尔可夫", config = "config_markov_cognitive_clhls.R"),
  list(code = "B15", module_kw = "CDC WONDER", config = "config_cdc_wonder_dobbs.R"),
  list(code = "B29", module_kw = "网络温度", config = "config_network_temperature_adolescent.R")
)

payload_done <- list(
  状态 = "已完成",
  当前阶段 = "阶段二完整复现冒烟通过",
  是否已做Block = "是",
  验收标准 = "4/4 smoke PASS：STEPP+Markov MSM+CITS+Network Temperature；含 config/run/Blocks/决策树/batch"
)

recs <- .feishu_bitable_list_records(cfg, table_id)
rec_by_code <- stats::setNames(recs, vapply(recs, function(x) as.character(x$fields$编号 %||% ""), character(1L)))

ok <- 0L
for (row in mark_rows) {
  hit <- rec_by_code[[row$code]]
  if (is.null(hit)) {
    for (rec in recs) {
      mod <- as.character(rec$fields$`工作模块` %||% rec$fields$工作模块 %||% "")
      if (grepl(row$module_kw, mod, fixed = TRUE)) { hit <- rec; break }
    }
  }
  if (is.null(hit)) {
    message("飞书未找到 ", row$code, " / ", row$module_kw, "，跳过")
    next
  }
  fields <- c(list(编号 = row$code), payload_done)
  if (dry_run) {
    message("[dry-run] 更新 ", row$code, ": ", row$config)
    ok <- ok + 1L
    next
  }
  tryCatch({
    feishu_bitable_update_record(cfg, hit$record_id, fields, table_id = table_id)
    message("已标记完成: ", row$code, " (", row$config, ")")
    ok <- ok + 1L
  }, error = function(e) message(row$code, " 失败: ", conditionMessage(e)))
}

cat(sprintf("飞书工作计划更新: 成功 %d / %d\n", ok, length(mark_rows)))
