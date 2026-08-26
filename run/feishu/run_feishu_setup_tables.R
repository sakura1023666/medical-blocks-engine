#!/usr/bin/env Rscript
# =============================================================================
#  run_feishu_setup_tables.R — 飞书三表架构一键初始化（运行一次）
#
#  结果：
#    Sheet 1「项目汇总」  ← 现有表，改造为1行总览
#    Sheet 2「成功指标」  ← 新建，R 自动写入成功记录
#    Sheet 3「失败指标」  ← 新建，R 自动写入失败记录
#    Sheet 1 有关联字段指向 Sheet 2 / Sheet 3
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

source(file.path(root, "R/feishu_env.R"));  feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/feishu_bitable.R"))

app_token <- Sys.getenv("FEISHU_BITABLE_APP_TOKEN")
table1_id <- Sys.getenv("FEISHU_BITABLE_TABLE_ID")
app_id    <- Sys.getenv("FEISHU_APP_ID")
app_secret<- Sys.getenv("FEISHU_APP_SECRET")

if (!nzchar(app_token) || !nzchar(table1_id))
  stop("请先在 .env.feishu 填好凭证再运行", call. = FALSE)

token <- feishu_tenant_access_token(app_id, app_secret)
hdr   <- httr::add_headers(Authorization = paste("Bearer", token))
base  <- sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s", app_token)

# ── 基础 API 封装 ─────────────────────────────────────────────────────────────
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

.add_field <- function(tid, name, type, property = NULL) {
  body <- list(field_name = name, type = as.integer(type))
  if (!is.null(property)) body$property <- property
  tryCatch({
    d <- .api("POST", sprintf("/tables/%s/fields", tid), body)
    fid <- d$field$field_id %||% "?"
    cli::cli_alert_success("  [{tid}] + {name} (type={type}) → {fid}")
    Sys.sleep(0.15)
    invisible(fid)
  }, error = function(e) {
    cli::cli_alert_warning("  [{tid}] 字段[{name}]失败: {conditionMessage(e)}")
    invisible(NA_character_)
  })
}

.del_field <- function(tid, fid) {
  tryCatch({
    .api("DELETE", sprintf("/tables/%s/fields/%s", tid, fid))
    Sys.sleep(0.15)
  }, error = function(e)
    cli::cli_alert_warning("  删字段 {fid} 失败: {conditionMessage(e)}")
  )
}

.sel <- function(...) {
  nms <- c(...)
  clrs <- c(2,0,4,1,5,3,6,7,8,9,10,11,12)
  list(options = lapply(seq_along(nms), function(i)
    list(name = nms[i], color = as.integer(clrs[((i-1L) %% length(clrs)) + 1L]))
  ))
}

.date_prop <- function(fmt = "yyyy/MM/dd HH:mm", auto = FALSE)
  list(date_formatter = fmt, auto_fill = auto)

.num_prop <- function(fmt = "0") list(formatter = fmt)

# ═════════════════════════════════════════════════════════════════════════════
# 步骤 1  重命名 Sheet 1 → 「项目汇总」
# ═════════════════════════════════════════════════════════════════════════════
cli::cli_h1("步骤 1 · 重命名 Sheet 1 → 「项目汇总」")
tryCatch(
  .api("PATCH", sprintf("/tables/%s", table1_id), list(name = "项目汇总")),
  error = function(e) cli::cli_alert_warning("重命名失败（可能已是该名称）: {conditionMessage(e)}")
)

# ═════════════════════════════════════════════════════════════════════════════
# 步骤 2  修改 Sheet 1 字段结构
# ═════════════════════════════════════════════════════════════════════════════
cli::cli_h1("步骤 2 · 清理并重建 Sheet 1 字段")
fd <- .api("GET", sprintf("/tables/%s/fields", table1_id))
existing <- fd$items %||% list()
primary_id <- NULL
for (f in existing) {
  if (isTRUE(f$is_primary)) {
    primary_id <- f$field_id
    cli::cli_alert_info("主字段: [{f$field_name}] id={f$field_id}")
  }
}
# 删除非主字段
for (f in existing) {
  if (!isTRUE(f$is_primary)) {
    cli::cli_alert_info("  删除 [{f$field_name}]")
    .del_field(table1_id, f$field_id)
  }
}
# 重命名主字段为「疾病」
if (!is.null(primary_id)) {
  tryCatch(
    .api("PUT", sprintf("/tables/%s/fields/%s", table1_id, primary_id),
         list(field_name = "疾病", type = 1L)),
    error = function(e) cli::cli_alert_warning("重命名主字段失败: {conditionMessage(e)}")
  )
}
# 新增字段
.add_field(table1_id, "套路",           1L)
.add_field(table1_id, "指标总数",       2L, .num_prop("0"))
.add_field(table1_id, "成功数量",       2L, .num_prop("0"))
.add_field(table1_id, "失败数量",       2L, .num_prop("0"))
.add_field(table1_id, "未运行数量",     2L, .num_prop("0"))
.add_field(table1_id, "进度",          36L)   # 进度条 (0‑100)
.add_field(table1_id, "结果摘要",       1L)
.add_field(table1_id, "成功项目号",     1L)
.add_field(table1_id, "整体状态",       3L,
  .sel("待开始","运行中","部分完成","全部成功","已交付"))
.add_field(table1_id, "负责人",         1L)
.add_field(table1_id, "最后同步时间",   5L, .date_prop("yyyy/MM/dd HH:mm"))

# ═════════════════════════════════════════════════════════════════════════════
# 步骤 3  创建 Sheet 2「成功指标」
# ═════════════════════════════════════════════════════════════════════════════
cli::cli_h1("步骤 3 · 创建 Sheet 2「成功指标」")
s2 <- .api("POST", "/tables", list(table = list(
  name = "成功指标",
  default_view_name = "成功指标视图",
  fields = list(list(field_name = "指标名", type = 1L))
)))
table2_id <- s2$table_id %||% stop("Sheet 2 创建失败")
cli::cli_alert_success("Sheet 2 table_id = {table2_id}")
Sys.sleep(0.5)

.add_field(table2_id, "疾病",           1L)
.add_field(table2_id, "套路",           1L)
.add_field(table2_id, "状态",           1L)
.add_field(table2_id, "文献",           1L)
.add_field(table2_id, "数据库模式",     3L, .sel("双库","仅NHANES","仅MIMIC"))
.add_field(table2_id, "NHANES_分支",    3L,
  .sel("extend_quartile","extend_tertile","extend_binary",
       "degrade_tertile","degrade_binary","unknown"))
.add_field(table2_id, "MIMIC_分支",     3L,
  .sel("extend_quartile","extend_tertile","extend_binary",
       "degrade_tertile","degrade_binary","unknown","N/A"))
.add_field(table2_id, "NHANES_OR",      2L, .num_prop("0.0000"))
.add_field(table2_id, "MIMIC_OR",       2L, .num_prop("0.0000"))
.add_field(table2_id, "NHANES_N",       2L, .num_prop("0"))
.add_field(table2_id, "MIMIC_N",        2L, .num_prop("0"))
.add_field(table2_id, "耗时_秒",        2L, .num_prop("0.0"))
.add_field(table2_id, "完成时间",       5L, .date_prop("yyyy/MM/dd HH:mm:ss"))
.add_field(table2_id, "项目编号",       1L)
.add_field(table2_id, "负责人",         1L)
.add_field(table2_id, "是否已交付",     3L, .sel("否","是"))

# ═════════════════════════════════════════════════════════════════════════════
# 步骤 4  创建 Sheet 3「失败指标」
# ═════════════════════════════════════════════════════════════════════════════
cli::cli_h1("步骤 4 · 创建 Sheet 3「失败指标」")
s3 <- .api("POST", "/tables", list(table = list(
  name = "失败指标",
  default_view_name = "失败指标视图",
  fields = list(list(field_name = "指标名", type = 1L))
)))
table3_id <- s3$table_id %||% stop("Sheet 3 创建失败")
cli::cli_alert_success("Sheet 3 table_id = {table3_id}")
Sys.sleep(0.5)

.add_field(table3_id, "疾病",           1L)
.add_field(table3_id, "套路",           1L)
.add_field(table3_id, "状态",           1L)
.add_field(table3_id, "失败类型",       3L,
  .sel("流水线错误","两库均不可用","数据量不足","其他"))
.add_field(table3_id, "数据库模式",     3L, .sel("双库","仅NHANES","仅MIMIC","未知"))
.add_field(table3_id, "错误信息",       1L)
.add_field(table3_id, "NHANES_N",       2L, .num_prop("0"))
.add_field(table3_id, "MIMIC_N",        2L, .num_prop("0"))
.add_field(table3_id, "耗时_秒",        2L, .num_prop("0.0"))
.add_field(table3_id, "失败时间",       5L, .date_prop("yyyy/MM/dd HH:mm:ss"))
.add_field(table3_id, "项目编号",       1L)
.add_field(table3_id, "备注",           1L)

# ═════════════════════════════════════════════════════════════════════════════
# 步骤 5  Sheet 1 增加关联字段（连接三表）
# ═════════════════════════════════════════════════════════════════════════════
cli::cli_h1("步骤 5 · Sheet 1 添加关联字段（连接 Sheet 2 / Sheet 3）")
Sys.sleep(0.5)
.add_field(table1_id, "成功指标关联", 18L,
  list(table_id = table2_id, multiple = TRUE))
.add_field(table1_id, "失败指标关联", 18L,
  list(table_id = table3_id, multiple = TRUE))

# ═════════════════════════════════════════════════════════════════════════════
# 步骤 6  Sheet 1 写入初始汇总行
# ═════════════════════════════════════════════════════════════════════════════
cli::cli_h1("步骤 6 · 写入初始汇总行")
rec_url  <- sprintf(
  "https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s/records",
  app_token, table1_id)
rec_body <- jsonlite::toJSON(list(fields = list(
  "疾病"         = "01_Urinary_Incontinence",
  "套路"         = "incidence_38341157",
  "指标总数"     = 41L,
  "成功数量"     = 0L,
  "失败数量"     = 0L,
  "未运行数量"   = 41L,
  "进度"         = 0L,
  "结果摘要"     = "批量流水线初始化，尚未运行",
  "成功项目号"   = "",
  "整体状态"     = "待开始",
  "负责人"       = ""
)), auto_unbox = TRUE, null = "null")
rresp <- httr::POST(rec_url, hdr, httr::content_type_json(),
                    body = rec_body, encode = "raw")
robj  <- jsonlite::fromJSON(httr::content(rresp, as = "text", encoding = "UTF-8"),
                             simplifyVector = FALSE)
if (identical(as.integer(robj$code %||% -1L), 0L)) {
  cli::cli_alert_success("汇总行写入成功")
} else {
  cli::cli_alert_warning("汇总行写入失败: {robj$msg %||% '?'}")
}

# ═════════════════════════════════════════════════════════════════════════════
# 输出结果
# ═════════════════════════════════════════════════════════════════════════════
cli::cli_rule("三表架构初始化完成")
cat(sprintf("Sheet 1 (项目汇总):  %s\n", table1_id))
cat(sprintf("Sheet 2 (成功指标):  %s\n", table2_id))
cat(sprintf("Sheet 3 (失败指标):  %s\n", table3_id))
cat("\n.env.feishu 需补充以下两行：\n")
cat(sprintf("FEISHU_BITABLE_TABLE_SUCCESS_ID=%s\n", table2_id))
cat(sprintf("FEISHU_BITABLE_TABLE_FAILURE_ID=%s\n", table3_id))
