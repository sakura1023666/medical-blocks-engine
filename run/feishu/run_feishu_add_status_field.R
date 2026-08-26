#!/usr/bin/env Rscript
# 在已有「成功指标」「失败指标」表中补建「状态」列（文本字段）
# 用法: Rscript run_feishu_add_status_field.R

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

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/feishu_bitable.R"))

app_id     <- Sys.getenv("FEISHU_APP_ID")
app_secret <- Sys.getenv("FEISHU_APP_SECRET")
app_token  <- Sys.getenv("FEISHU_BITABLE_APP_TOKEN")
table2_id  <- Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID")
table3_id  <- Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID")

if (!nzchar(app_token) || !nzchar(table2_id) || !nzchar(table3_id))
  stop("请先在 .env.feishu 配置 BITABLE_APP_TOKEN / TABLE_SUCCESS_ID / TABLE_FAILURE_ID",
       call. = FALSE)

token <- feishu_tenant_access_token(app_id, app_secret)
hdr   <- httr::add_headers(Authorization = paste("Bearer", token))
base  <- sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables", app_token)

.add_text_field <- function(tid, name) {
  url  <- sprintf("%s/%s/fields", base, tid)
  body <- jsonlite::toJSON(
    list(field_name = name, type = 1L),
    auto_unbox = TRUE
  )
  resp <- httr::POST(url, hdr, httr::content_type_json(), body = body, encode = "raw")
  obj  <- jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8"),
                              simplifyVector = FALSE)
  if (!identical(as.integer(obj$code %||% -1L), 0L)) {
    cli::cli_alert_warning("[{tid}] 字段「{name}」: {obj$msg %||% '?'}")
  } else {
    cli::cli_alert_success("[{tid}] 已添加字段「{name}」")
  }
}

cli::cli_h1("补建飞书「状态」列")
.add_text_field(table2_id, "状态")
.add_text_field(table3_id, "状态")
cli::cli_alert_info("若表中已有重复行（疾病+指标名），请手动合并后保留一行")
