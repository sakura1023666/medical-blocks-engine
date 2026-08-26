#!/usr/bin/env Rscript
# =============================================================================
#  run_feishu_setup_crm_nhanes_mr_tables.R
#  在 CRM×NHANES 孟德尔随机化项目专用 base 上创建/确认「项目汇总」「成功指标」
#  「失败指标」「套路已做」四张表，字段 schema 参照
#  run_feishu_setup_ipw_diabetes_tables.R 的结构，按本项目（单库 NHANES +
#  obs/MR 多分析单元）特点调整。
#
#  项目: 14_CRM_NHANES_MR（Han et al. 2025 JAHA e038723）
#  协议: crm_nhanes_mr
#
#  硬约束：
#    - app_token 固定为本项目专用 base RBjfb2iwmamW14s4WhKcS7kwnie（--app-token 可覆盖，
#      仅用于测试；生产不要改）
#    - 只在进程内用 Sys.setenv 临时覆盖 FEISHU_BITABLE_APP_TOKEN，绝不改写
#      .env.feishu / run/feishu/.env.feishu 的默认 BITABLE_APP_TOKEN
#    - 幂等：若同名表已存在则直接复用其 table_id，不重复创建
#
#  用法:
#    Rscript run/feishu/run_feishu_setup_crm_nhanes_mr_tables.R
#    Rscript run/feishu/run_feishu_setup_crm_nhanes_mr_tables.R --skip-routine
#    Rscript run/feishu/run_feishu_setup_crm_nhanes_mr_tables.R --app-token bascnXXXX   # 仅测试用
#
#  输出:
#    打印 table_id / table_success_id / table_failure_id / table_routine_id，
#    供人工写入项目 live config 与 template 的 config$feishu（本脚本不自动改配置文件）。
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
skip_routine <- "--skip-routine" %in% args

# 目标 base（项目专用；硬约束值，仅测试时可用 --app-token 覆盖）
CRM_NHANES_MR_APP_TOKEN <- "RBjfb2iwmamW14s4WhKcS7kwnie"
app_token <- get_arg("--app-token", CRM_NHANES_MR_APP_TOKEN)

source(file.path(root, "R/feishu_env.R"))
feishu_load_dotenv(root)   # 只取 FEISHU_APP_ID / FEISHU_APP_SECRET；不依赖其中的 BITABLE_APP_TOKEN
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/feishu_bitable.R"))

app_id     <- Sys.getenv("FEISHU_APP_ID")
app_secret <- Sys.getenv("FEISHU_APP_SECRET")
if (!nzchar(app_id) || !nzchar(app_secret))
  stop("请先在 .env.feishu 配置 FEISHU_APP_ID / FEISHU_APP_SECRET", call. = FALSE)

# 进程内临时覆盖（不落盘、不改 .env.feishu 文件）
Sys.setenv(FEISHU_BITABLE_APP_TOKEN = app_token)
cli::cli_alert_info("使用 app_token（进程内临时覆盖）: {app_token}")

token <- feishu_tenant_access_token(app_id, app_secret)
hdr   <- httr::add_headers(Authorization = paste("Bearer", token))
base  <- sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s", app_token)

# ── 基础 API 封装（同 run_feishu_setup_tables.R）───────────────────────────────
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
    cli::cli_alert_success("  [{tid}] + {name} (type={type}) -> {fid}")
    Sys.sleep(0.15)
    invisible(fid)
  }, error = function(e) {
    cli::cli_alert_warning("  [{tid}] 字段[{name}]失败: {conditionMessage(e)}")
    invisible(NA_character_)
  })
}

.sel <- function(...) {
  nms <- c(...)
  clrs <- c(2, 0, 4, 1, 5, 3, 6, 7, 8, 9, 10, 11, 12)
  list(options = lapply(seq_along(nms), function(i)
    list(name = nms[i], color = as.integer(clrs[((i - 1L) %% length(clrs)) + 1L]))
  ))
}
.date_prop <- function(fmt = "yyyy/MM/dd HH:mm", auto = FALSE)
  list(date_formatter = fmt, auto_fill = auto)
.num_prop <- function(fmt = "0") list(formatter = fmt)

# ── 幂等：先列出 base 内已有表，按名字匹配复用 ────────────────────────────────
existing_tables <- .api("GET", "/tables")$items %||% list()
existing_by_name <- stats::setNames(
  vapply(existing_tables, function(t) t$table_id %||% "", character(1L)),
  vapply(existing_tables, function(t) t$name %||% "", character(1L))
)
cli::cli_alert_info("base 内已有表: {paste(names(existing_by_name), collapse = ', ')}")

.get_or_create_table <- function(name, default_view_name, primary_field_name, primary_field_type = 1L) {
  if (name %in% names(existing_by_name) && nzchar(existing_by_name[[name]])) {
    cli::cli_alert_info("表「{name}」已存在，复用 table_id={existing_by_name[[name]]}")
    return(list(table_id = existing_by_name[[name]], created = FALSE))
  }
  s <- .api("POST", "/tables", list(table = list(
    name = name,
    default_view_name = default_view_name,
    fields = list(list(field_name = primary_field_name, type = as.integer(primary_field_type)))
  )))
  tid <- s$table_id %||% stop("表「", name, "」创建失败", call. = FALSE)
  cli::cli_alert_success("表「{name}」创建成功 table_id = {tid}")
  Sys.sleep(0.5)
  list(table_id = tid, created = TRUE)
}

.existing_field_names <- function(tid) {
  fd <- .api("GET", sprintf("/tables/%s/fields", tid))
  vapply(fd$items %||% list(), function(f) f$field_name, character(1L))
}

# ═════════════════════════════════════════════════════════════════════════════
# Sheet A 「项目汇总」（对应 config$feishu$table_id；字段结构对齐 Sheet1）
# ═════════════════════════════════════════════════════════════════════════════
cli::cli_h1("Sheet A · 项目汇总")
tblA <- .get_or_create_table("CRM_NHANES_MR_项目汇总", "项目汇总视图", "疾病")
table1_id <- tblA$table_id
if (tblA$created) {
  .add_field(table1_id, "套路",           1L)
  .add_field(table1_id, "指标总数",       2L, .num_prop("0"))
  .add_field(table1_id, "成功数量",       2L, .num_prop("0"))
  .add_field(table1_id, "失败数量",       2L, .num_prop("0"))
  .add_field(table1_id, "未运行数量",     2L, .num_prop("0"))
  .add_field(table1_id, "进度",          36L)
  .add_field(table1_id, "结果摘要",       1L)
  .add_field(table1_id, "成功项目号",     1L)
  .add_field(table1_id, "整体状态",       3L,
    .sel("待开始", "运行中", "部分完成", "全部成功", "已交付"))
  .add_field(table1_id, "负责人",         1L)
  .add_field(table1_id, "最后同步时间",   5L, .date_prop("yyyy/MM/dd HH:mm"))
} else {
  cli::cli_alert_info("跳过字段初始化（表已存在，假定字段已齐）")
}

# ═════════════════════════════════════════════════════════════════════════════
# Sheet B 「成功指标」（对应 config$feishu$table_success_id；字段结构对齐 Sheet2，
#  按本项目单库 NHANES + obs/MR 多分析单元特点调整：数据库模式/双分支 -> 分析单元 + MR结局）
# ═════════════════════════════════════════════════════════════════════════════
cli::cli_h1("Sheet B · 成功指标")
tblB <- .get_or_create_table("CRM_NHANES_MR_成功指标", "成功指标视图", "指标名")
table2_id <- tblB$table_id
if (tblB$created) {
  .add_field(table2_id, "疾病",           1L)
  .add_field(table2_id, "套路",           1L)
  .add_field(table2_id, "状态",           1L)
  .add_field(table2_id, "文献",           1L)
  .add_field(table2_id, "分析单元",       3L,
    .sel("obs_main", "obs_strata", "mr_cvd", "mr_ckd", "mr_diabetes"))
  .add_field(table2_id, "MR结局",         3L,
    .sel("CVD", "CKD", "Diabetes", "N/A"))
  .add_field(table2_id, "NHANES_OR",      2L, .num_prop("0.0000"))
  .add_field(table2_id, "NHANES_N",       2L, .num_prop("0"))
  .add_field(table2_id, "MR_F统计量",     2L, .num_prop("0.00"))
  .add_field(table2_id, "MR_SNP数",       2L, .num_prop("0"))
  .add_field(table2_id, "耗时_秒",        2L, .num_prop("0.0"))
  .add_field(table2_id, "完成时间",       5L, .date_prop("yyyy/MM/dd HH:mm:ss"))
  .add_field(table2_id, "项目编号",       1L)
  .add_field(table2_id, "负责人",         1L)
  .add_field(table2_id, "是否已交付",     3L, .sel("否", "是"))
} else {
  existing_names <- .existing_field_names(table2_id)
  cli::cli_alert_info("已存在字段: {paste(existing_names, collapse = ', ')}")
}

# ═════════════════════════════════════════════════════════════════════════════
# Sheet C 「失败指标」（对应 config$feishu$table_failure_id；字段结构对齐 Sheet3）
# ═════════════════════════════════════════════════════════════════════════════
cli::cli_h1("Sheet C · 失败指标")
tblC <- .get_or_create_table("CRM_NHANES_MR_失败指标", "失败指标视图", "指标名")
table3_id <- tblC$table_id
if (tblC$created) {
  .add_field(table3_id, "疾病",           1L)
  .add_field(table3_id, "套路",           1L)
  .add_field(table3_id, "状态",           1L)
  .add_field(table3_id, "失败类型",       3L,
    .sel("流水线错误", "数据量不足", "MR工具变量弱", "共享层缺失", "其他"))
  .add_field(table3_id, "分析单元",       3L,
    .sel("obs_main", "obs_strata", "mr_cvd", "mr_ckd", "mr_diabetes", "未知"))
  .add_field(table3_id, "错误信息",       1L)
  .add_field(table3_id, "NHANES_N",       2L, .num_prop("0"))
  .add_field(table3_id, "耗时_秒",        2L, .num_prop("0.0"))
  .add_field(table3_id, "失败时间",       5L, .date_prop("yyyy/MM/dd HH:mm:ss"))
  .add_field(table3_id, "项目编号",       1L)
  .add_field(table3_id, "备注",           1L)
} else {
  existing_names <- .existing_field_names(table3_id)
  cli::cli_alert_info("已存在字段: {paste(existing_names, collapse = ', ')}")
}

# ═════════════════════════════════════════════════════════════════════════════
# Sheet A 补充关联字段（连接 Sheet B / Sheet C；失败不影响主流程）
# ═════════════════════════════════════════════════════════════════════════════
if (tblA$created) {
  cli::cli_h1("Sheet A · 添加关联字段（连接 成功指标 / 失败指标）")
  Sys.sleep(0.3)
  .add_field(table1_id, "成功指标关联", 18L, list(table_id = table2_id, multiple = TRUE))
  .add_field(table1_id, "失败指标关联", 18L, list(table_id = table3_id, multiple = TRUE))
}

# ═════════════════════════════════════════════════════════════════════════════
# Sheet D 「套路已做」（可选；对应 config$feishu$table_routine_id）
# ═════════════════════════════════════════════════════════════════════════════
table_routine_id <- ""
if (!skip_routine) {
  cli::cli_h1("Sheet D · 套路已做（可选）")
  tblD <- .get_or_create_table("CRM_NHANES_MR_套路已做", "套路矩阵", "疾病编号")
  table_routine_id <- tblD$table_id
  if (tblD$created) {
    .add_field(table_routine_id, "疾病",         1L)
    .add_field(table_routine_id, "疾病目录",     1L)
    .add_field(table_routine_id, "已跑套路数",   2L, .num_prop("0"))
    .add_field(table_routine_id, "套路总数",     2L, .num_prop("0"))
    .add_field(table_routine_id, "最后同步时间", 5L, .date_prop("yyyy/MM/dd HH:mm", auto = FALSE))
    routine_status_opts <- .sel("未跑", "共享层完成", "部分完成", "全部成功", "全部失败", "—")
    .add_field(table_routine_id, "crm_nhanes_mr", 3L, routine_status_opts)
  } else {
    existing_names <- .existing_field_names(table_routine_id)
    cli::cli_alert_info("已存在字段: {paste(existing_names, collapse = ', ')}")
  }
} else {
  cli::cli_alert_info("--skip-routine 已指定，跳过套路表创建")
}

# ═════════════════════════════════════════════════════════════════════════════
# 输出结果
# ═════════════════════════════════════════════════════════════════════════════
cli::cli_rule("CRM×NHANES 孟德尔随机化 飞书表初始化完成")
cat(sprintf("app_token（base）      : %s\n", app_token))
cat(sprintf("table_id（项目汇总）   : %s\n", table1_id))
cat(sprintf("table_success_id（成功）: %s\n", table2_id))
cat(sprintf("table_failure_id（失败）: %s\n", table3_id))
if (nzchar(table_routine_id))
  cat(sprintf("table_routine_id（套路）: %s\n", table_routine_id))
cat("\n请手动写入项目 live config 与 template 的 config$feishu：\n")
cat(sprintf(
  "  feishu = list(\n    enable = TRUE,\n    app_token = \"%s\",\n    table_id = \"%s\",\n    table_success_id = \"%s\",\n    table_failure_id = \"%s\"%s,\n    disease_label = \"14_CRM_NHANES_MR\",\n    protocol_label = \"crm_nhanes_mr\",\n    project_id = \"14_crm_nhanes_mr_038723\"\n  )\n",
  app_token, table1_id, table2_id, table3_id,
  if (nzchar(table_routine_id)) sprintf(",\n    table_routine_id = \"%s\"", table_routine_id) else ""
))
cat("\n提示: 本脚本仅在进程内用 Sys.setenv 覆盖 FEISHU_BITABLE_APP_TOKEN，未改写 .env.feishu。\n")
