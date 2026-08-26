#!/usr/bin/env Rscript
# 飞书连通性自检：token → 可选写入一条测试记录
# 用法: Rscript run_feishu_test.R [--write-test]

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
source(file.path(root, "configs/templates/config_incidence_dual_batch.template.R"))

args <- commandArgs(trailingOnly = TRUE)
write_test <- "--write-test" %in% args

cat("=== 飞书凭证检查 ===\n")
st <- feishu_env_status()
for (nm in names(st)) {
  mark <- if (st[[nm]]) "OK" else "缺失"
  cat(sprintf("  %-28s %s\n", nm, mark))
}

app_id     <- Sys.getenv("FEISHU_APP_ID", "")
app_secret <- Sys.getenv("FEISHU_APP_SECRET", "")
if (!nzchar(app_id) || !nzchar(app_secret)) {
  stop("请在 run/feishu/.env.feishu 或 .env.feishu 中填写 FEISHU_APP_ID 和 FEISHU_APP_SECRET", call. = FALSE)
}

cat("\n=== 获取 tenant_access_token ===\n")
tok <- tryCatch(
  feishu_tenant_access_token(app_id, app_secret),
  error = function(e) stop("Token 失败: ", conditionMessage(e), call. = FALSE)
)
cat("  token 获取成功 (前 12 字符): ", substr(tok, 1L, 12L), "...\n", sep = "")

cfg <- .feishu_cfg(config)
if (is.null(cfg)) {
  cat("\n多维表格 ID 未配置。请编辑 .env.feishu：\n")
  cat("  独立表格: base/bascnXXXX → APP_TOKEN，table=tblXXXX → TABLE_ID\n")
  cat("  Wiki表格: wiki/J63XXXX   → APP_TOKEN，table=tblXXXX → TABLE_ID\n")
  cat("\n填好后重新运行: Rscript run_feishu_test.R --write-test\n")
  quit(save = "no", status = 0)
}

cat("\n=== 多维表格配置 ===\n")
cat("  app_token : ", cfg$app_token, "\n", sep = "")
cat("  table_id  : ", cfg$table_id, "\n", sep = "")

if (!write_test) {
  cat("\n凭证齐全。试写一条测试记录请运行:\n")
  cat("  Rscript run_feishu_test.R --write-test\n")
  quit(save = "no", status = 0)
}

cat("\n=== 写入测试记录 ===\n")
if (!isTRUE(cfg$three_table)) {
  stop("三表 ID 未配置：请在 .env.feishu 填写 FEISHU_BITABLE_TABLE_SUCCESS_ID / FAILURE_ID",
       call. = FALSE)
}
test_fields <- list(
  index = paste0("TEST_", format(Sys.time(), "%H%M%S")),
  status = "success",
  db_mode = "both",
  nhanes_branch = "extend_quartile",
  mimic_branch = "extend_quartile",
  nhanes_or = 1.01,
  mimic_or = 1.02,
  n_nhanes_after = 1000,
  n_mimic_after = 500,
  elapsed_sec = 1.2,
  disease = cfg$disease_label,
  protocol = cfg$protocol_label
)
tryCatch({
  incidence_batch_feishu_push_result(config, test_fields)
  cat("  测试记录已写入「成功指标」表，请到飞书查看。\n")
}, error = function(e) {
  stop("写入失败: ", conditionMessage(e),
       "\n常见原因: 应用未发布 / 未开通 bitable 权限 / 表格未添加应用为协作者",
       call. = FALSE)
})
