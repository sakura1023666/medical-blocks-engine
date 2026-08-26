#!/usr/bin/env Rscript
# =============================================================================
#  run_feishu_import_workplan.R — 从 Excel 导入 block 套路工作计划到飞书多维表格
#
#  用法:
#    Rscript run/feishu/run_feishu_import_workplan.R [xlsx路径] [--dry-run] [--clear]
#
#  默认 xlsx: run/feishu/副本副本block套路工作计划.xlsx
#  默认飞书表: FEISHU_WORKPLAN_APP_TOKEN / FEISHU_WORKPLAN_TABLE_ID
#             （未设置时可用 FEISHU_BITABLE_APP_TOKEN / 命令行 --app-token --table-id）
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

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/feishu_bitable.R"))

args <- commandArgs(trailingOnly = TRUE)
dry_run <- "--dry-run" %in% args
do_clear <- "--clear" %in% args
pos_args <- args[!grepl("^--", args) & !grepl("^--.*=", args)]

default_xlsx <- file.path(root, "run/feishu/副本副本block套路工作计划.xlsx")
xlsx_path <- if (length(pos_args)) normalizePath(pos_args[1L], winslash = "/", mustWork = FALSE) else default_xlsx

get_arg <- function(flag, env_key, default = "") {
  i <- match(flag, args)
  if (!is.na(i) && i < length(args)) return(args[i + 1L])
  v <- Sys.getenv(env_key, unset = "")
  if (nzchar(v)) v else default
}

sheet_name <- get_arg("--sheet", "FEISHU_WORKPLAN_SHEET", "工作计划总表")
skip_rows  <- as.integer(get_arg("--skip", "FEISHU_WORKPLAN_SKIP", "2"))

app_token <- get_arg("--app-token", "FEISHU_WORKPLAN_APP_TOKEN",
                     get_arg("--app-token", "FEISHU_BITABLE_APP_TOKEN", "RBjfb2iwmamW14s4WhKcS7kwnie"))
table_id  <- get_arg("--table-id", "FEISHU_WORKPLAN_TABLE_ID",
                     get_arg("--table-id", "FEISHU_BITABLE_TABLE_ID", "tblenCHO3ErYIpYp"))

app_id     <- Sys.getenv("FEISHU_APP_ID", "")
app_secret <- Sys.getenv("FEISHU_APP_SECRET", "")

if (!file.exists(xlsx_path))
  stop("找不到 Excel 文件: ", xlsx_path,
       "\n请将文件复制到 run/feishu/ 后重试。", call. = FALSE)
if (!requireNamespace("readxl", quietly = TRUE))
  stop("需要 readxl 包: install.packages('readxl')", call. = FALSE)

cfg <- list(
  app_id = app_id, app_secret = app_secret,
  app_token = app_token, table_id = table_id
)

.api <- function(method, path, body = NULL, tid = table_id) {
  if (dry_run && !identical(method, "GET")) {
    cli::cli_alert_info("[dry-run] {method} {path}")
    return(list())
  }
  .feishu_bitable_request(cfg, method, path, body = body, table_id = tid)
}

.guess_field_type <- function(col_name, values) {
  vals <- values[!is.na(values) & nzchar(trimws(as.character(values)))]
  if (!length(vals)) return(1L)
  # 日期列（含 Excel 计划表固定列名）
  if (grepl("日期|时间|deadline|due|计划开始|计划完成", col_name, ignore.case = TRUE)) return(5L)
  if (grepl("^负责人$", col_name)) return(1L)
  if (grepl("^进度$", col_name)) return(2L)
  num_ok <- suppressWarnings(as.numeric(vals))
  if (mean(is.finite(num_ok)) > 0.85 && !grepl("编号|序号|PMID|pmid|ID", col_name)) return(2L)
  # 状态/阶段类 → 单选
  if (grepl("状态|阶段|优先级|是否", col_name) && length(unique(vals)) <= 20L) return(3L)
  if (length(unique(vals)) <= 8L && mean(nchar(vals)) <= 12L) return(3L)
  1L
}

.sel_prop <- function(values) {
  vals <- unique(trimws(as.character(values)))
  vals <- vals[nzchar(vals)]
  clrs <- c(2, 0, 4, 1, 5, 3, 6, 7, 8, 9, 10, 11, 12)
  list(options = lapply(seq_along(vals), function(i)
    list(name = vals[i], color = as.integer(clrs[((i - 1L) %% length(clrs)) + 1L]))
  ))
}

.to_feishu_value <- function(v, field_type) {
  if (is.null(v) || length(v) == 0 || is.na(v)) return(NULL)
  if (field_type == 1L) {
    s <- trimws(as.character(v))
    if (!nzchar(s)) return(NULL)
    return(s)
  }
  if (field_type == 2L) {
    n <- suppressWarnings(as.numeric(v))
    if (!is.finite(n)) return(NULL)
    return(n)
  }
  if (field_type == 3L) {
    s <- trimws(as.character(v))
    if (!nzchar(s)) return(NULL)
    return(s)
  }
  if (field_type == 5L) {
    if (inherits(v, "Date") || inherits(v, "POSIXt")) {
      return(as.numeric(as.POSIXct(v)) * 1000)
    }
    s <- trimws(as.character(v))
    if (!nzchar(s)) return(NULL)
    ts <- suppressWarnings(as.POSIXct(s, tryFormats = c(
      "%Y-%m-%d", "%Y/%m/%d", "%Y-%m-%d %H:%M:%S", "%Y/%m/%d %H:%M:%S",
      "%m/%d/%Y", "%d/%m/%Y"
    )))
    if (is.na(ts)) return(NULL)
    return(as.numeric(ts) * 1000)
  }
  trimws(as.character(v))
}

cli::cli_h1("读取 Excel")
sheets <- readxl::excel_sheets(xlsx_path)
cli::cli_alert_info("工作表: {paste(sheets, collapse = ', ')}")
if (!sheet_name %in% sheets)
  stop("找不到工作表 [", sheet_name, "]，可用: ", paste(sheets, collapse = ", "), call. = FALSE)
cli::cli_alert_info("读取 [{sheet_name}]，跳过前 {skip_rows} 行")
df <- readxl::read_excel(xlsx_path, sheet = sheet_name, skip = skip_rows)
df <- as.data.frame(df, stringsAsFactors = FALSE)
names(df) <- trimws(names(df))
names(df) <- sub("^\\.\\.\\.[0-9]+$", "", names(df))
# 去掉全空行；主键列（编号/工作模块）均为空则跳过
key_cols <- intersect(c("编号", "工作模块"), names(df))
keep <- apply(df, 1L, function(r) {
  any(!is.na(r) & nzchar(trimws(as.character(r))))
})
if (length(key_cols)) {
  keep <- keep & apply(df[, key_cols, drop = FALSE], 1L, function(r) {
    any(!is.na(r) & nzchar(trimws(as.character(r))))
  })
}
df <- df[keep, , drop = FALSE]
if (!nrow(df)) stop("Excel 工作表 [", sheet_name, "] 没有有效数据行", call. = FALSE)

cli::cli_alert_success("共 {nrow(df)} 行 × {ncol(df)} 列")
for (nm in names(df)) cli::cli_alert_info("  列: {nm}")

cli::cli_h1("对齐飞书字段")
existing <- .api("GET", "/fields")$items %||% list()
existing_map <- stats::setNames(
  lapply(existing, function(f) list(id = f$field_id, type = f$type, primary = isTRUE(f$is_primary))),
  vapply(existing, function(f) f$field_name, character(1L))
)

col_types <- stats::setNames(
  vapply(names(df), function(nm) .guess_field_type(nm, df[[nm]]), integer(1L)),
  names(df)
)

# 若仅有一个主字段且列名不同，重命名主字段为 Excel 第一列
if (length(existing) == 1L && isTRUE(existing[[1L]]$is_primary)) {
  first_col <- names(df)[1L]
  old_name <- existing[[1L]]$field_name
  if (!identical(old_name, first_col)) {
    cli::cli_alert_info("重命名主字段 [{old_name}] → [{first_col}]")
    if (!dry_run) {
      .api("PUT", sprintf("/fields/%s", existing[[1L]]$field_id),
           list(field_name = first_col, type = as.integer(existing[[1L]]$type)))
    }
    existing_map[[first_col]] <- list(
      id = existing[[1L]]$field_id,
      type = existing[[1L]]$type,
      primary = TRUE
    )
    existing_map[[old_name]] <- NULL
  }
}

for (nm in names(df)) {
  if (nm %in% names(existing_map)) next
  ftype <- col_types[[nm]]
  prop <- if (ftype == 3L) .sel_prop(df[[nm]]) else NULL
  cli::cli_alert_info("新建字段 [{nm}] type={ftype}")
  if (!dry_run) {
    body <- list(field_name = nm, type = as.integer(ftype))
    if (!is.null(prop)) body$property <- prop
    .api("POST", "/fields", body)
    Sys.sleep(0.15)
  }
}

if (!dry_run) {
  existing <- .api("GET", "/fields")$items %||% list()
  existing_map <- stats::setNames(
    lapply(existing, function(f) list(id = f$field_id, type = f$type)),
    vapply(existing, function(f) f$field_name, character(1L))
  )
}

if (do_clear) {
  cli::cli_h1("清空现有记录")
  recs <- .feishu_bitable_list_records(cfg, table_id)
  if (length(recs)) {
    for (item in recs) {
      rid <- item$record_id %||% item$id
      if (nzchar(rid %||% "")) {
        cli::cli_alert_info("删除 {rid}")
        if (!dry_run) .api("DELETE", sprintf("/records/%s", rid))
      }
    }
  }
}

cli::cli_h1("写入记录")
ok <- 0L
for (i in seq_len(nrow(df))) {
  row <- df[i, , drop = FALSE]
  fields <- list()
  for (nm in names(df)) {
    meta <- existing_map[[nm]]
    ftype <- if (!is.null(meta)) meta$type else col_types[[nm]]
    val <- .to_feishu_value(row[[nm]][[1L]], ftype)
    if (!is.null(val)) fields[[nm]] <- val
  }
  if (!length(fields)) next
  if (dry_run) {
    cli::cli_alert_info("行 {i}: {paste(names(fields), collapse=', ')}")
    ok <- ok + 1L
    next
  }
  tryCatch({
    .api("POST", "/records", list(fields = fields))
    ok <- ok + 1L
    if (i %% 10L == 0L) Sys.sleep(0.2)
  }, error = function(e) {
    cli::cli_alert_warning("行 {i} 写入失败: {conditionMessage(e)}")
  })
}

cli::cli_rule("导入完成")
cat(sprintf("  Excel: %s\n", xlsx_path))
cat(sprintf("  飞书 app_token: %s\n", app_token))
cat(sprintf("  飞书 table_id:  %s\n", table_id))
cat(sprintf("  成功写入: %d / %d 行\n", ok, nrow(df)))
if (dry_run) cat("  （dry-run 模式，未实际写入飞书）\n")
