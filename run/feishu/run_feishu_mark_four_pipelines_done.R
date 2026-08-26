#!/usr/bin/env Rscript
# 在飞书「block套路工作计划」中标记四套新流水线为已完成
# 表格: https://lcn1in9jd6ie.feishu.cn/base/RBjfb2iwmamW14s4WhKcS7kwnie
#
# 用法:
#   Rscript run/feishu/run_feishu_mark_four_pipelines_done.R
#   Rscript run/feishu/run_feishu_mark_four_pipelines_done.R --dry-run

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

# 编号 → 工作模块关键词（用于飞书行匹配）
mark_rows <- list(
  list(code = "B08", module_kw = "单环境毒物", config = "config_environment_cd_osteo_nhanes.R"),
  list(code = "B12", module_kw = "动态因果", config = "config_dynamic_causal_dual.R"),
  list(code = "B09", module_kw = "多病", config = "config_multimorbidity_additive.R"),
  list(code = "B23", module_kw = "多模态", config = "config_multimodal_tbi.R")
)

payload_done <- list(
  状态 = "已完成",
  当前阶段 = "冒烟通过",
  是否已做Block = "是",
  验收标准 = "随机 smoke 数据四套流水线均可跑通；含 config/run/决策树/飞书段"
)

recs <- .feishu_bitable_list_records(cfg, table_id)
rec_by_code <- stats::setNames(recs, vapply(recs, function(x) as.character(x$fields$编号 %||% ""), character(1L)))

ok <- 0L
for (row in mark_rows) {
  hit <- rec_by_code[[row$code]]
  if (is.null(hit)) {
  # 按工作模块模糊搜
    hit <- NULL
    for (rec in recs) {
      mod <- as.character(rec$fields$`工作模块` %||% rec$fields$工作模块 %||% "")
      if (grepl(row$module_kw, mod, fixed = TRUE)) { hit <- rec; break }
    }
  }
  if (is.null(hit)) {
    cli::cli_alert_warning("飞书未找到 {row$code} / {row$module_kw}，跳过")
    next
  }
  fields <- c(list(编号 = row$code), payload_done)
  if (dry_run) {
    cli::cli_alert_info("[dry-run] 更新 {row$code}: {row$config}")
    ok <- ok + 1L
    next
  }
  tryCatch({
    feishu_bitable_update_record(cfg, hit$record_id, fields, table_id = table_id)
    cli::cli_alert_success("已标记完成: {row$code} ({row$config})")
    ok <- ok + 1L
  }, error = function(e) cli::cli_alert_warning("{row$code} 失败: {conditionMessage(e)}"))
}

cli::cli_rule("飞书工作计划更新")
cat(sprintf("成功 %d / %d\n", ok, length(mark_rows)))
