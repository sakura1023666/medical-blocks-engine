#!/usr/bin/env Rscript
# 在飞书「block套路工作计划」中标记四套目标文献流水线为已完成
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
  list(code = "B18", module_kw = "发病前后比较", config = "config_incidence_prepost_charls.R"),
  list(code = "B19", module_kw = "目标模拟临床试验", config = "config_target_trial_rasi_aki.R"),
  list(code = "B17", module_kw = "单数据库短时间transformer", config = "config_transformer_aki_single.R"),
  list(code = "B25", module_kw = "结构方程", config = "config_dual_change_score_elsa.R")
)

payload_done <- list(
  状态 = "已完成",
  当前阶段 = "阶段二：原文方法学补全 + Decisiontree 同步 + 4/4 smoke batch",
  是否已做Block = "是",
  验收标准 = paste(
    "4/4 smoke PASS（run_four_target_paper_pipelines_parallel_batch.R）；",
    "完整 block 链：B18 piecewise LMM / B19 sequential TTE+bootstrap / ",
    "B17 REACT 因果发现+多中心 / B25 lavaan DCSM；",
    "Decisiontree/decision_tree_* 四套已更新；含 literature_validate"
  )
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
