#!/usr/bin/env Rscript
# =============================================================================
#  run_feishu_import_literature.R
#  把 文献/文献 登记进工作计划 base 的新表「文献库」。
#
#  列：文献题名、套路、状态、是否更新、PMID、DOI、期刊分区、发表年、
#      期刊、工作计划编号、入库批次、本地文件名、备注
#
#  状态取自工作计划「临床」表的上线情况，不表示这篇稿已经跑完。
#  是否更新只看文件名里的新/旧；没写的标「单篇」。
#
#  用法:
#    Rscript run/feishu/run_feishu_import_literature.R
#    Rscript run/feishu/run_feishu_import_literature.R --replace
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
do_replace <- "--replace" %in% args

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/feishu_bitable.R"))

get_arg <- function(flag, default = "") {
  i <- match(flag, args)
  if (!is.na(i) && i < length(args)) return(args[i + 1L])
  default
}
app_token <- get_arg(
  "--app-token",
  Sys.getenv("FEISHU_LITERATURE_APP_TOKEN",
             Sys.getenv("FEISHU_WORKPLAN_APP_TOKEN", "RBjfb2iwmamW14s4WhKcS7kwnie"))
)
app_id     <- Sys.getenv("FEISHU_APP_ID", "")
app_secret <- Sys.getenv("FEISHU_APP_SECRET", "")
if (!nzchar(app_id) || !nzchar(app_secret))
  stop("请先配置 FEISHU_APP_ID / FEISHU_APP_SECRET", call. = FALSE)

catalog_path <- file.path(root, "run/feishu/literature_catalog.json")
if (!file.exists(catalog_path))
  stop("找不到 ", catalog_path, call. = FALSE)
rows <- jsonlite::fromJSON(catalog_path, simplifyVector = FALSE)
if (!length(rows)) stop("文献目录为空", call. = FALSE)

token <- feishu_tenant_access_token(app_id, app_secret)
hdr   <- httr::add_headers(Authorization = paste("Bearer", token))
base  <- sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s", app_token)

.api <- function(method, path, body = NULL) {
  url <- paste0(base, path)
  resp <- switch(method,
    GET    = httr::GET(url, hdr),
    POST   = httr::POST(url, hdr, httr::content_type_json(), body = body, encode = "json"),
    PUT    = httr::PUT(url, hdr, httr::content_type_json(), body = body, encode = "json"),
    DELETE = httr::DELETE(url, hdr),
    stop("Unknown method: ", method)
  )
  raw <- httr::content(resp, as = "text", encoding = "UTF-8")
  obj <- jsonlite::fromJSON(raw, simplifyVector = FALSE)
  if (!identical(as.integer(obj$code %||% 0L), 0L))
    stop(sprintf("[%s %s] code=%s: %s", method, path, obj$code %||% "?", obj$msg %||% raw),
         call. = FALSE)
  obj$data %||% list()
}

.sel <- function(nms) {
  nms <- unique(nms[nzchar(nms)])
  clrs <- c(2, 0, 4, 1, 5, 3, 6, 7, 8, 9, 10, 11, 12)
  list(options = lapply(seq_along(nms), function(i)
    list(name = nms[i], color = as.integer(clrs[((i - 1L) %% length(clrs)) + 1L]))
  ))
}

tables <- .api("GET", "/tables?page_size=100")
existing <- NULL
for (t in tables$items %||% list()) {
  if (identical(t$name, "文献库")) existing <- t$table_id
}
if (!is.null(existing) && !do_replace) {
  stop("已有表「文献库」 ", existing, "。确认覆盖后加 --replace。", call. = FALSE)
}
reuse_id <- NULL
if (!is.null(existing) && do_replace) {
  cli::cli_alert_warning("尝试删除已有表 文献库 {existing}")
  del <- tryCatch({
    .api("DELETE", paste0("/tables/", existing))
    TRUE
  }, error = function(e) {
    cli::cli_alert_warning("不能删表（{conditionMessage(e)}），改为清空后重写")
    FALSE
  })
  if (!del) reuse_id <- existing
  Sys.sleep(0.3)
}

pick <- function(key) vapply(rows, function(r) as.character(r[[key]] %||% ""), character(1L))
routine_opts <- .sel(pick("routine"))
status_opts  <- .sel(c("已上线", "流水线已完成", "进行中", "未开始", "不在Block范围"))
update_opts  <- .sel(c("新文献", "旧文献", "单篇", "补充文件"))
zone_opts    <- .sel(c("3分", "4分", "5分", "6分", "8分", "未标注"))

if (is.null(reuse_id)) {
  cli::cli_h1("创建表「文献库」")
  created <- .api("POST", "/tables", list(table = list(
    name = "文献库",
    default_view_name = "按套路",
    fields = list(list(field_name = "文献题名", type = 1L))
  )))
  tid <- created$table_id %||% stop("创建文献库失败", call. = FALSE)
  cli::cli_alert_success("table_id = {tid}")
  Sys.sleep(0.4)
} else {
  tid <- reuse_id
  cli::cli_h1("重写已有表 {tid}")
  fd <- .api("GET", sprintf("/tables/%s/fields?page_size=100", tid))
  primary_id <- NULL
  for (f in fd$items %||% list()) {
    if (isTRUE(f$is_primary)) {
      primary_id <- f$field_id
    } else {
      .api("DELETE", sprintf("/tables/%s/fields/%s", tid, f$field_id))
      Sys.sleep(0.12)
    }
  }
  if (!is.null(primary_id)) {
    .api("PUT", sprintf("/tables/%s/fields/%s", tid, primary_id),
         list(field_name = "文献题名", type = 1L))
  }
  repeat {
    recs <- .api("GET", sprintf("/tables/%s/records?page_size=100", tid))
    items <- recs$items %||% list()
    if (!length(items)) break
    ids <- vapply(items, function(it) it$record_id, character(1L))
    .api("POST", sprintf("/tables/%s/records/batch_delete", tid), list(records = as.list(ids)))
    if (!isTRUE(recs$has_more)) break
  }
  Sys.sleep(0.3)
}

.add_field <- function(name, type, property = NULL) {
  body <- list(field_name = name, type = as.integer(type))
  if (!is.null(property)) body$property <- property
  .api("POST", sprintf("/tables/%s/fields", tid), body)
  cli::cli_alert_success("  + {name}")
  Sys.sleep(0.15)
}

.add_field("套路", 3L, routine_opts)
.add_field("状态", 3L, status_opts)
.add_field("是否更新", 3L, update_opts)
.add_field("PMID", 1L)
.add_field("DOI", 15L)
.add_field("期刊分区", 3L, zone_opts)
.add_field("发表年", 2L, list(formatter = "0"))
.add_field("期刊", 1L)
.add_field("工作计划编号", 1L)
.add_field("入库批次", 1L)
.add_field("本地文件名", 1L)
.add_field("备注", 1L)

.txt <- function(x) {
  if (is.null(x) || length(x) == 0L || is.na(x)) return(NULL)
  s <- trimws(as.character(x))
  if (!nzchar(s)) NULL else s
}

records <- lapply(rows, function(r) {
  fields <- list(
    "文献题名" = .txt(r$title),
    "套路" = .txt(r$routine),
    "状态" = .txt(r$status),
    "是否更新" = .txt(r$update),
    "期刊分区" = .txt(r$zone),
    "入库批次" = .txt(r$batch),
    "本地文件名" = .txt(r$file)
  )
  pmid <- .txt(r$pmid)
  if (!is.null(pmid)) fields[["PMID"]] <- pmid
  doi <- .txt(r$doi)
  if (!is.null(doi)) fields[["DOI"]] <- list(text = doi, link = paste0("https://doi.org/", doi))
  if (!is.null(r$year) && !is.na(r$year) && nzchar(as.character(r$year)))
    fields[["发表年"]] <- as.integer(r$year)
  journal <- .txt(r$journal)
  if (!is.null(journal)) fields[["期刊"]] <- journal
  plan <- .txt(r$plan_id)
  if (!is.null(plan)) fields[["工作计划编号"]] <- plan
  note <- .txt(r$note)
  if (!is.null(note)) fields[["备注"]] <- note
  fields
})

cfg <- list(
  app_id = app_id, app_secret = app_secret,
  app_token = app_token, table_id = tid
)
feishu_bitable_batch_create(cfg, records, table_id = tid, chunk_size = 50L)

env_path <- file.path(root, "run/feishu/.env.feishu")
if (file.exists(env_path)) {
  lines <- readLines(env_path, warn = FALSE, encoding = "UTF-8")
  lines <- lines[!grepl("^FEISHU_LITERATURE_TABLE_ID=", lines)]
  lines <- lines[!grepl("^FEISHU_LITERATURE_APP_TOKEN=", lines)]
  lines <- c(lines, paste0("FEISHU_LITERATURE_APP_TOKEN=", app_token))
  lines <- c(lines, paste0("FEISHU_LITERATURE_TABLE_ID=", tid))
  writeLines(lines, env_path, useBytes = TRUE)
}

cli::cli_rule("文献库已写入")
cat(sprintf("记录数: %d\n", length(records)))
cat(sprintf("表: https://lcn1in9jd6ie.feishu.cn/base/%s?table=%s\n", app_token, tid))
