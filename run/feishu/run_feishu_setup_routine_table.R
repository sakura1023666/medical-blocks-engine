#!/usr/bin/env Rscript
# =============================================================================
#  run_feishu_setup_routine_table.R — 创建 Sheet「套路已做」
#
#  用法:
#    Rscript run/feishu/run_feishu_setup_routine_table.R [--result-root PATH]
# =============================================================================

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

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = "") {
  i <- match(flag, args)
  if (!is.na(i) && i < length(args)) return(args[i + 1L])
  default
}

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(file.path(root, "R/feishu_block_result_scan.R"))

app_token <- Sys.getenv("FEISHU_BITABLE_APP_TOKEN")
app_id    <- Sys.getenv("FEISHU_APP_ID")
app_secret<- Sys.getenv("FEISHU_APP_SECRET")
if (!nzchar(app_token) || !nzchar(app_id) || !nzchar(app_secret))
  stop("请先在 .env.feishu 配置 FEISHU_APP_ID/SECRET/BITABLE_APP_TOKEN", call. = FALSE)

result_root <- get_arg("--result-root", Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"))
scan <- feishu_scan_block_result(result_root)
routine_names <- scan$all_routines

token <- feishu_tenant_access_token(app_id, app_secret)
hdr   <- httr::add_headers(Authorization = paste("Bearer", token))
base  <- sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s", app_token)

.api <- function(method, path, body = NULL) {
  url  <- paste0(base, path)
  send_body <- if (!is.null(body))
    jsonlite::toJSON(body, auto_unbox = TRUE, null = "null") else NULL
  resp <- switch(method,
    GET    = httr::GET(url, hdr),
    POST   = httr::POST(url, hdr, httr::content_type_json(),
                        body = send_body, encode = "raw"),
    PATCH  = httr::PATCH(url, hdr, httr::content_type_json(),
                         body = send_body, encode = "raw"),
    PUT    = httr::PUT(url, hdr, httr::content_type_json(),
                       body = send_body, encode = "raw"),
    DELETE = httr::DELETE(url, hdr),
    stop("Unknown method: ", method)
  )
  raw <- httr::content(resp, as = "text", encoding = "UTF-8")
  obj <- jsonlite::fromJSON(raw, simplifyVector = FALSE)
  if (!identical(as.integer(obj$code %||% 0L), 0L))
    stop(sprintf("[%s %s] code=%s: %s", method, path,
                 obj$code %||% "?", obj$msg %||% raw))
  obj$data %||% list()
}

.sel <- function(...) {
  nms <- c(...)
  clrs <- c(2, 0, 4, 1, 5, 3, 6, 7, 8, 9, 10, 11, 12)
  list(options = lapply(seq_along(nms), function(i)
    list(name = nms[i], color = as.integer(clrs[((i - 1L) %% length(clrs)) + 1L]))
  ))
}

.add_field <- function(tid, name, type, property = NULL) {
  body <- list(field_name = name, type = as.integer(type))
  if (!is.null(property)) body$property <- property
  tryCatch({
    d <- .api("POST", sprintf("/tables/%s/fields", tid), body)
    fid <- d$field$field_id %||% "?"
    cli::cli_alert_success("  + {name} → {fid}")
    Sys.sleep(0.15)
    invisible(fid)
  }, error = function(e) {
    cli::cli_alert_warning("  字段[{name}]失败: {conditionMessage(e)}")
    invisible(NA_character_)
  })
}

existing_routine_id <- Sys.getenv("FEISHU_BITABLE_TABLE_ROUTINE_ID", "")
table_routine_id <- existing_routine_id

if (!nzchar(table_routine_id)) {
  cli::cli_h1("创建 Sheet「套路已做」")
  s <- .api("POST", "/tables", list(table = list(
    name = "套路已做",
    default_view_name = "套路矩阵",
    fields = list(list(field_name = "疾病编号", type = 1L))
  )))
  table_routine_id <- s$table_id %||% stop("创建「套路已做」表失败", call. = FALSE)
  cli::cli_alert_success("套路已做 table_id = {table_routine_id}")
  Sys.sleep(0.5)

  .add_field(table_routine_id, "疾病",         1L)
  .add_field(table_routine_id, "疾病目录",     1L)
  .add_field(table_routine_id, "已跑套路数",   2L, list(formatter = "0"))
  .add_field(table_routine_id, "套路总数",     2L, list(formatter = "0"))
  .add_field(table_routine_id, "最后同步时间", 5L,
             list(date_formatter = "yyyy/MM/dd HH:mm", auto_fill = FALSE))
} else {
  cli::cli_h1("已存在套路表 {table_routine_id}，补齐字段")
}

# 为每个已发现的套路名加列（单选）
fd <- .api("GET", sprintf("/tables/%s/fields", table_routine_id))
existing_names <- vapply(fd$items %||% list(), function(f) f$field_name, character(1L))
routine_status_opts <- .sel("未跑", "共享层完成", "部分完成", "全部成功", "全部失败", "—")

for (rn in routine_names) {
  if (rn %in% existing_names) next
  .add_field(table_routine_id, rn, 3L, routine_status_opts)
}

cli::cli_rule("套路表初始化完成")
cat(sprintf("FEISHU_BITABLE_TABLE_ROUTINE_ID=%s\n", table_routine_id))
cat("\n请将上行写入 .env.feishu 后运行 run_feishu_resync_block_result.R\n")
