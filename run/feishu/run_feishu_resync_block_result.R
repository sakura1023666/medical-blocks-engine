#!/usr/bin/env Rscript
# =============================================================================
#  run_feishu_resync_block_result.R
#  从 02block_result 全量扫描 → 清空并重建飞书四表
#
#  疾病编号（01/02/…）从目录名解析，不可改写。
#
#  用法:
#    Rscript run/feishu/run_feishu_resync_block_result.R [--dry-run]
#    Rscript run/feishu/run_feishu_resync_block_result.R --clear
#    Rscript run/feishu/run_feishu_resync_block_result.R --clear --result-root /mnt/g/02block_result
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
dry_run   <- "--dry-run" %in% args
do_clear  <- "--clear" %in% args
get_arg <- function(flag, default = "") {
  i <- match(flag, args)
  if (!is.na(i) && i < length(args)) return(args[i + 1L])
  default
}

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(file.path(root, "R/feishu_block_result_scan.R"))

app_id     <- Sys.getenv("FEISHU_APP_ID")
app_secret <- Sys.getenv("FEISHU_APP_SECRET")
app_token  <- Sys.getenv("FEISHU_BITABLE_APP_TOKEN")
table_summary <- Sys.getenv("FEISHU_BITABLE_TABLE_ID")
table_success <- Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID")
table_failure <- Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID")
table_routine <- Sys.getenv("FEISHU_BITABLE_TABLE_ROUTINE_ID")

if (!nzchar(app_id) || !nzchar(app_secret) || !nzchar(app_token))
  stop("请配置 .env.feishu 中的 FEISHU_APP_ID / FEISHU_APP_SECRET / FEISHU_BITABLE_APP_TOKEN",
       call. = FALSE)
if (!nzchar(table_summary) || !nzchar(table_success) || !nzchar(table_failure))
  stop("请配置 FEISHU_BITABLE_TABLE_ID / SUCCESS_ID / FAILURE_ID", call. = FALSE)

result_root <- get_arg("--result-root", Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"))
cfg <- list(
  app_id = app_id, app_secret = app_secret, app_token = app_token,
  table_id = table_summary,
  table_success_id = table_success,
  table_failure_id = table_failure,
  table_routine_id = table_routine,
  owner_default = Sys.getenv("FEISHU_OWNER", "")
)

# ── 飞书字段管理（套路列动态补齐）────────────────────────────────────────────
.feishu_api_admin <- local({
  token <- feishu_tenant_access_token(app_id, app_secret)
  hdr   <- httr::add_headers(Authorization = paste("Bearer", token))
  base  <- sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s", app_token)
  function(method, path, body = NULL) {
    url <- paste0(base, path)
    send_body <- if (!is.null(body))
      jsonlite::toJSON(body, auto_unbox = TRUE, null = "null") else NULL
    resp <- switch(method,
      GET  = httr::GET(url, hdr),
      POST = httr::POST(url, hdr, httr::content_type_json(),
                        body = send_body, encode = "raw"),
      stop("Unsupported: ", method)
    )
    raw <- httr::content(resp, as = "text", encoding = "UTF-8")
    obj <- jsonlite::fromJSON(raw, simplifyVector = FALSE)
    if (!identical(as.integer(obj$code %||% 0L), 0L))
      stop(obj$msg %||% raw, call. = FALSE)
    obj$data %||% list()
  }
})

.ensure_summary_fields <- function() {
  fd <- .feishu_api_admin("GET", sprintf("/tables/%s/fields", table_summary))
  existing <- vapply(fd$items %||% list(), function(f) f$field_name, character(1L))
  add_text <- function(nm) {
    if (nm %in% existing || dry_run) return(invisible(NULL))
    .feishu_api_admin("POST", sprintf("/tables/%s/fields", table_summary), list(
      field_name = nm, type = 1L
    ))
    Sys.sleep(0.15)
  }
  add_num <- function(nm) {
    if (nm %in% existing || dry_run) return(invisible(NULL))
    .feishu_api_admin("POST", sprintf("/tables/%s/fields", table_summary), list(
      field_name = nm, type = 2L, property = list(formatter = "0")
    ))
    Sys.sleep(0.15)
  }
  for (nm in c("疾病编号", "疾病目录")) add_text(nm)
  for (nm in c("已跑套路数", "套路总数", "进度")) add_num(nm)
  invisible(NULL)
}

.ensure_routine_fields <- function(routine_names) {
  if (!nzchar(table_routine)) {
    cli::cli_alert_warning("未配置 FEISHU_BITABLE_TABLE_ROUTINE_ID，跳过套路表字段补齐")
    return(invisible(NULL))
  }
  fd <- .feishu_api_admin("GET", sprintf("/tables/%s/fields", table_routine))
  existing <- vapply(fd$items %||% list(), function(f) f$field_name, character(1L))
  opts <- list(options = lapply(
    c("未跑", "共享层完成", "部分完成", "全部成功", "全部失败", "—"),
    function(nm, i) list(name = nm, color = as.integer(c(2, 0, 4, 1, 5, 3)[i])),
    seq_along(c("未跑", "共享层完成", "部分完成", "全部成功", "全部失败", "—"))
  ))
  for (rn in routine_names) {
    if (rn %in% existing) next
    if (dry_run) {
      cli::cli_alert_info("[dry-run] 新建套路列: {rn}")
      next
    }
    .feishu_api_admin("POST", sprintf("/tables/%s/fields", table_routine), list(
      field_name = rn, type = 3L, property = opts
    ))
    cli::cli_alert_success("新建套路列: {rn}")
    Sys.sleep(0.15)
  }
  invisible(NULL)
}

# ── 按疾病编号 upsert ─────────────────────────────────────────────────────────
.find_record_by_key <- function(cfg, table_id, key_field, key_value) {
  items <- .feishu_bitable_list_records(cfg, table_id)
  for (item in items) {
    fld <- item$fields %||% list()
    v <- .feishu_field_text(fld[[key_field]], "")
    if (identical(v, key_value)) {
      return(list(
        record_id = as.character(item$record_id %||% item$id %||% ""),
        fields = fld
      ))
    }
  }
  NULL
}

.upsert_by_key <- function(cfg, table_id, key_field, key_value, payload, dry_run = FALSE) {
  if (dry_run) {
    cli::cli_alert_info("[dry-run] upsert {key_field}={key_value}: {paste(names(payload), collapse=', ')}")
    return(list(action = "dry-run"))
  }
  hit <- .find_record_by_key(cfg, table_id, key_field, key_value)
  tryCatch({
    if (!is.null(hit) && nzchar(hit$record_id %||% "")) {
      feishu_bitable_update_record(cfg, hit$record_id, payload, table_id = table_id)
      list(action = "update", record_id = hit$record_id)
    } else {
      out <- feishu_bitable_create_record(cfg, payload, table_id = table_id)
      list(action = "create", record_id = out$record$record_id %||% out$record_id %||% NA_character_)
    }
  }, error = function(e) {
    stop(sprintf("upsert 失败 [%s=%s @ %s]: %s",
                 key_field, key_value, table_id, conditionMessage(e)), call. = FALSE)
  })
}

# ── 指标表缓存（避免每条都全表 list）────────────────────────────────────────
.metric_cache <- new.env(parent = emptyenv())

.metric_key <- function(disease, routine, index_nm) {
  paste(disease, routine, index_nm, sep = "\x01")
}

.load_metric_cache <- function(cfg, table_id) {
  cache_key <- as.character(table_id)
  if (exists(cache_key, envir = .metric_cache, inherits = FALSE))
    return(get(cache_key, envir = .metric_cache))
  items <- .feishu_bitable_list_records(cfg, table_id)
  map <- new.env(parent = emptyenv())
  for (item in items) {
    fld <- item$fields %||% list()
    d <- .feishu_field_text(fld[["疾病"]], "")
    r <- .feishu_field_text(fld[["套路"]], "")
    ix <- .feishu_field_text(fld[["指标名"]], "")
    rid <- as.character(item$record_id %||% item$id %||% "")
    if (nzchar(d) && nzchar(ix) && nzchar(rid))
      assign(.metric_key(d, r, ix), rid, envir = map)
  }
  assign(cache_key, map, envir = .metric_cache)
  map
}

.upsert_metric <- function(cfg, table_id, disease, routine, index_nm, payload, dry_run = FALSE) {
  if (dry_run) {
    cli::cli_alert_info("[dry-run] metric {disease}/{routine}/{index_nm}")
    return(list(action = "dry-run"))
  }
  map <- .load_metric_cache(cfg, table_id)
  key <- .metric_key(disease, routine, index_nm)
  rid <- if (exists(key, envir = map, inherits = FALSE)) get(key, envir = map) else ""

  for (attempt in seq_len(4L)) {
    ok <- tryCatch({
      if (nzchar(rid)) {
        feishu_bitable_update_record(cfg, rid, payload, table_id = table_id)
        list(action = "update")
      } else {
        out <- feishu_bitable_create_record(cfg, payload, table_id = table_id)
        new_id <- as.character(out$record$record_id %||% out$record_id %||% "")
        if (nzchar(new_id)) assign(key, new_id, envir = map)
        list(action = "create")
      }
    }, error = function(e) {
      msg <- conditionMessage(e)
      if (attempt < 4L && grepl("Internal Error|frequency|limit|429", msg, ignore.case = TRUE)) {
        Sys.sleep(1.5 * attempt)
        return(NULL)
      }
      stop(sprintf("metric 失败 [%s/%s/%s]: %s", disease, routine, index_nm, msg),
           call. = FALSE)
    })
    if (!is.null(ok)) return(ok)
  }
  invisible(NULL)
}

# ── 扫描 ──────────────────────────────────────────────────────────────────────
cli::cli_h1("扫描 block_result: {result_root}")
scan <- feishu_scan_block_result(result_root)
cli::cli_alert_success(
  "发现 {length(scan$diseases)} 个疾病, {length(scan$all_routines)} 种套路名"
)

if (nzchar(table_routine)) .ensure_routine_fields(scan$all_routines)
.ensure_summary_fields()

# ── 清空 ──────────────────────────────────────────────────────────────────────
if (do_clear) {
  cli::cli_h1("清空飞书表")
  for (label_tid in list(
    list("项目汇总", table_summary),
    list("套路已做", table_routine),
    list("成功指标", table_success),
    list("失败指标", table_failure)
  )) {
    if (!nzchar(label_tid[[2]])) {
      cli::cli_alert_warning("跳过 {label_tid[[1]]}（未配置 table_id）")
      next
    }
    feishu_bitable_clear_table(cfg, label_tid[[2]], dry_run = dry_run)
  }
  # 清空后重置指标缓存
  rm(list = ls(envir = .metric_cache), envir = .metric_cache)
}

# ── 写入（先收集，再批量）────────────────────────────────────────────────────
success_payloads <- list()
failure_payloads <- list()
routine_payloads <- list()
summary_payloads <- list()

for (dkey in sort(names(scan$diseases))) {
  dis <- scan$diseases[[dkey]]
  disease_id    <- dis$disease_id
  disease_name  <- dis$disease_name
  disease_dir   <- dis$disease_dir
  disease_label <- sprintf("%s_%s", disease_id, disease_name)

  routines <- dis$routines %||% list()
  n_run_routines <- sum(vapply(routines, function(x) {
    !identical(x$cell_status %||% "未跑", "未跑")
  }, logical(1L)))

  if (nzchar(table_routine)) {
    routine_payload <- list(
      "疾病编号"     = disease_id,
      "疾病"         = disease_name,
      "疾病目录"     = disease_dir,
      "已跑套路数"   = as.integer(n_run_routines),
      "套路总数"     = as.integer(length(routines)),
      "最后同步时间" = .feishu_now_ms()
    )
    for (rn in scan$all_routines) {
      if (rn %in% names(routines)) {
        routine_payload[[rn]] <- routines[[rn]]$cell_status %||% "未跑"
      } else {
        routine_payload[[rn]] <- "—"
      }
    }
    routine_payloads[[length(routine_payloads) + 1L]] <- routine_payload
  }

  total_ix <- success_ix <- failure_ix <- notrun_ix <- 0L
  for (rn in names(routines)) {
    st <- routines[[rn]]
    total_ix   <- total_ix   + (st$total %||% 0L)
    success_ix <- success_ix + (st$success %||% 0L)
    failure_ix <- failure_ix + (st$failure %||% 0L)
    notrun_ix  <- notrun_ix  + (st$not_run %||% 0L)

    rows <- st$rows
    if (is.null(rows) || !nrow(rows)) next

    for (i in seq_len(nrow(rows))) {
      row <- rows[i, , drop = FALSE]
      ix_nm  <- as.character(row$index[[1L]])
      status <- tolower(as.character(row$status[[1L]]))
      db_mode <- as.character(row$db_mode[[1L]] %||% NA_character_)
      nh_br <- as.character(row$nhanes_branch[[1L]] %||% NA_character_)
      mi_br <- as.character(row$mimic_branch[[1L]] %||% NA_character_)
      nh_or <- suppressWarnings(as.numeric(row$nhanes_or[[1L]]))
      mi_or <- suppressWarnings(as.numeric(row$mimic_or[[1L]]))
      nh_n  <- suppressWarnings(as.numeric(row$n_nhanes_after[[1L]]))
      mi_n  <- suppressWarnings(as.numeric(row$n_mimic_after[[1L]]))
      elap  <- suppressWarnings(as.numeric(row$elapsed_sec[[1L]]))
      err   <- as.character(row$error_message[[1L]] %||% NA_character_)

      if (identical(status, "success")) {
        owner <- cfg$owner_default; if (!nzchar(owner)) owner <- "待分配"
        success_payloads[[length(success_payloads) + 1L]] <- .feishu_compact_payload(list(
          "指标名" = ix_nm, "疾病" = disease_label, "套路" = rn,
          "状态" = "首次成功",
          "数据库模式" = .feishu_map_db_mode(db_mode),
          "NHANES_分支" = .feishu_map_branch(nh_br),
          "MIMIC_分支" = .feishu_map_branch(mi_br),
          "NHANES_OR" = .feishu_fmt_num(nh_or),
          "MIMIC_OR" = .feishu_fmt_num(mi_or),
          "NHANES_N" = .feishu_fmt_num(nh_n),
          "MIMIC_N" = .feishu_fmt_num(mi_n),
          "耗时_秒" = .feishu_fmt_num(elap),
          "项目编号" = disease_id, "负责人" = owner,
          "是否已交付" = "否", "完成时间" = .feishu_now_ms()
        ))
      } else if (status %in% c("error", "failed", "parse_error")) {
        if (!nzchar(err %||% "")) err <- paste0("status=", status)
        failure_payloads[[length(failure_payloads) + 1L]] <- .feishu_compact_payload(list(
          "指标名" = ix_nm, "疾病" = disease_label, "套路" = rn,
          "状态" = "首次失败",
          "失败类型" = .feishu_map_failure_type(err),
          "数据库模式" = .feishu_map_db_mode(db_mode),
          "错误信息" = err,
          "NHANES_N" = .feishu_fmt_num(nh_n),
          "MIMIC_N" = .feishu_fmt_num(mi_n),
          "耗时_秒" = .feishu_fmt_num(elap),
          "项目编号" = disease_id, "备注" = "",
          "失败时间" = .feishu_now_ms()
        ))
      }
    }
  }

  overall <- .feishu_disease_overall_status(dis)
  owner <- cfg$owner_default; if (!nzchar(owner)) owner <- "待分配"
  progress <- if (total_ix > 0L) as.integer(round(100 * success_ix / total_ix)) else 0L
  summary_payloads[[length(summary_payloads) + 1L]] <- .feishu_compact_payload(list(
    "疾病编号" = disease_id, "疾病" = disease_name, "疾病目录" = disease_dir,
    "已跑套路数" = as.integer(n_run_routines),
    "套路总数" = as.integer(length(routines)),
    "指标总数" = as.integer(total_ix),
    "成功数量" = as.integer(success_ix),
    "失败数量" = as.integer(failure_ix),
    "未运行数量" = as.integer(notrun_ix),
    "进度" = progress,
    "结果摘要" = sprintf(
      "套路 %d 个 | 指标 成功 %d / 失败 %d / 未跑 %d / 共 %d",
      length(routines), success_ix, failure_ix, notrun_ix, total_ix
    ),
    "整体状态" = overall, "负责人" = owner,
    "最后同步时间" = .feishu_now_ms()
  ))

  cli::cli_alert_info(
    "{disease_id} {disease_name}: {overall} | 套路 {n_run_routines}/{length(routines)}"
  )
}

cli::cli_h1("批量写入飞书")
if (dry_run) {
  cli::cli_alert_info(
    "[dry-run] 汇总 {length(summary_payloads)} / 套路 {length(routine_payloads)} / 成功 {length(success_payloads)} / 失败 {length(failure_payloads)}"
  )
} else {
  if (length(summary_payloads)) {
    n <- feishu_bitable_batch_create(cfg, summary_payloads, table_id = table_summary)
    cli::cli_alert_success("项目汇总写入 {n} 行")
  }
  if (nzchar(table_routine) && length(routine_payloads)) {
    n <- feishu_bitable_batch_create(cfg, routine_payloads, table_id = table_routine)
    cli::cli_alert_success("套路已做写入 {n} 行")
  }
  if (length(success_payloads)) {
    n <- feishu_bitable_batch_create(cfg, success_payloads, table_id = table_success)
    cli::cli_alert_success("成功指标写入 {n} 条")
  }
  if (length(failure_payloads)) {
    n <- feishu_bitable_batch_create(cfg, failure_payloads, table_id = table_failure)
    cli::cli_alert_success("失败指标写入 {n} 条")
  }
}

cli::cli_rule("同步完成")
cat(sprintf("  项目汇总: %d 行\n", length(summary_payloads)))
cat(sprintf("  套路已做: %d 行\n", length(routine_payloads)))
cat(sprintf("  成功指标: %d 条\n", length(success_payloads)))
cat(sprintf("  失败指标: %d 条\n", length(failure_payloads)))
if (dry_run) cat("  （dry-run 模式，未实际写入飞书）\n")
