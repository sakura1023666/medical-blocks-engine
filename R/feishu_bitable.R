###############################################################################
#  feishu_bitable.R — 飞书多维表格（Bitable）三表结果同步
#  Sheet 1 项目汇总 | Sheet 2 成功指标 | Sheet 3 失败指标
###############################################################################

.feishu_cfg <- function(config) {
  fs <- config$feishu %||% list()
  if (!isTRUE(fs$enable)) return(NULL)
  app_id     <- fs$app_id     %||% Sys.getenv("FEISHU_APP_ID", "")
  app_secret <- fs$app_secret %||% Sys.getenv("FEISHU_APP_SECRET", "")
  app_token  <- fs$app_token  %||% Sys.getenv("FEISHU_BITABLE_APP_TOKEN", "")
  table_id   <- fs$table_id   %||% Sys.getenv("FEISHU_BITABLE_TABLE_ID", "")
  table_success <- fs$table_success_id %||% Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", "")
  table_failure <- fs$table_failure_id %||% Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", "")
  table_routine <- fs$table_routine_id %||% Sys.getenv("FEISHU_BITABLE_TABLE_ROUTINE_ID", "")
  if (!nzchar(app_id) || !nzchar(app_secret) || !nzchar(app_token) || !nzchar(table_id)) {
    cli::cli_alert_warning(
      "飞书同步已启用但凭证不完整（需 FEISHU_APP_ID/SECRET/BITABLE_APP_TOKEN/BITABLE_TABLE_ID）"
    )
    return(NULL)
  }
  list(
    app_id          = app_id,
    app_secret      = app_secret,
    app_token       = app_token,
    table_id        = table_id,
    table_success_id = table_success,
    table_failure_id = table_failure,
    table_routine_id = table_routine,
    three_table     = nzchar(table_success) && nzchar(table_failure),
    four_table      = nzchar(table_success) && nzchar(table_failure) && nzchar(table_routine),
    literature_default = fs$literature_default %||% "NHANES + MIMIC 发病双库",
    project_id      = fs$project_id %||% config$project$name %||% "batch",
    protocol_label  = fs$protocol_label %||% config$project$name %||% "",
    disease_label   = fs$disease_label %||% config$project$disease %||%
                      config$project$analysis_group %||% "未知",
    owner_default   = fs$owner_default %||% Sys.getenv("FEISHU_OWNER", "")
  )
}

feishu_tenant_access_token <- function(app_id, app_secret) {
  if (!requireNamespace("httr", quietly = TRUE))
    stop("飞书同步需要 httr 包: install.packages('httr')", call. = FALSE)
  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop("飞书同步需要 jsonlite 包", call. = FALSE)

  resp <- httr::POST(
    "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
    httr::content_type_json(),
    body = list(app_id = app_id, app_secret = app_secret),
    encode = "json"
  )
  raw <- httr::content(resp, as = "text", encoding = "UTF-8")
  obj <- jsonlite::fromJSON(raw, simplifyVector = TRUE)
  if (!identical(obj$code, 0L) && !identical(as.integer(obj$code), 0L))
    stop("飞书 token 获取失败: ", obj$msg %||% raw, call. = FALSE)
  as.character(obj$tenant_access_token)
}

.feishu_bitable_request <- function(cfg, method, path, body = NULL, table_id = NULL) {
  if (!requireNamespace("httr", quietly = TRUE))
    stop("飞书同步需要 httr 包", call. = FALSE)
  token <- feishu_tenant_access_token(cfg$app_id, cfg$app_secret)
  tid   <- table_id %||% cfg$table_id
  url   <- sprintf(
    "https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s%s",
    cfg$app_token, tid, path
  )
  hdr <- httr::add_headers(Authorization = paste("Bearer", token))
  resp <- if (identical(method, "GET")) {
    httr::GET(url, hdr)
  } else if (identical(method, "POST")) {
    httr::POST(url, hdr, httr::content_type_json(), body = body, encode = "json")
  } else if (identical(method, "PUT")) {
    httr::PUT(url, hdr, httr::content_type_json(), body = body, encode = "json")
  } else if (identical(method, "DELETE")) {
    httr::DELETE(url, hdr)
  } else {
    stop("Unsupported method: ", method, call. = FALSE)
  }
  raw <- httr::content(resp, as = "text", encoding = "UTF-8")
  obj <- jsonlite::fromJSON(raw, simplifyVector = FALSE)
  if (!identical(as.integer(obj$code %||% -1L), 0L))
    stop("飞书 API 失败: ", obj$msg %||% raw, call. = FALSE)
  obj$data %||% list()
}

feishu_bitable_create_record <- function(cfg, fields_named, table_id = NULL) {
  .feishu_bitable_request(
    cfg, "POST", "/records",
    body = list(fields = fields_named),
    table_id = table_id
  )
}

#' 批量新建记录（每批最多 500；默认 100）
feishu_bitable_batch_create <- function(cfg, records_fields, table_id = NULL, chunk_size = 100L) {
  if (!length(records_fields)) return(invisible(0L))
  tid <- table_id %||% cfg$table_id
  n_ok <- 0L
  idx <- seq_along(records_fields)
  chunks <- split(idx, ceiling(idx / as.integer(chunk_size)))
  for (ch in chunks) {
    body <- list(records = lapply(records_fields[ch], function(f) list(fields = f)))
    for (attempt in seq_len(4L)) {
      ok <- tryCatch({
        .feishu_bitable_request(cfg, "POST", "/records/batch_create", body = body, table_id = tid)
        TRUE
      }, error = function(e) {
        msg <- conditionMessage(e)
        if (attempt < 4L && grepl("Internal Error|frequency|limit|429", msg, ignore.case = TRUE)) {
          Sys.sleep(1.5 * attempt)
          return(FALSE)
        }
        stop(msg, call. = FALSE)
      })
      if (isTRUE(ok)) break
    }
    n_ok <- n_ok + length(ch)
    Sys.sleep(0.3)
  }
  invisible(n_ok)
}

#' 批量删除记录
feishu_bitable_batch_delete <- function(cfg, record_ids, table_id = NULL, chunk_size = 100L) {
  record_ids <- as.character(record_ids)
  record_ids <- record_ids[nzchar(record_ids)]
  if (!length(record_ids)) return(invisible(0L))
  tid <- table_id %||% cfg$table_id
  n_ok <- 0L
  idx <- seq_along(record_ids)
  chunks <- split(idx, ceiling(idx / as.integer(chunk_size)))
  for (ch in chunks) {
    body <- list(records = as.list(unname(record_ids[ch])))
    tryCatch({
      .feishu_bitable_request(cfg, "POST", "/records/batch_delete", body = body, table_id = tid)
      n_ok <- n_ok + length(ch)
    }, error = function(e) {
      cli::cli_alert_warning("batch_delete 失败: {conditionMessage(e)}")
    })
    Sys.sleep(0.25)
  }
  invisible(n_ok)
}

feishu_bitable_update_record <- function(cfg, record_id, fields_named, table_id = NULL) {
  .feishu_bitable_request(
    cfg, "PUT", sprintf("/records/%s", record_id),
    body = list(fields = fields_named),
    table_id = table_id
  )
}

feishu_bitable_delete_record <- function(cfg, record_id, table_id = NULL) {
  .feishu_bitable_request(
    cfg, "DELETE", sprintf("/records/%s", record_id),
    table_id = table_id
  )
}

.feishu_bitable_list_records <- function(cfg, table_id, page_size = 500L) {
  items <- list()
  page_token <- NULL
  repeat {
    path <- sprintf("/records?page_size=%d", as.integer(page_size))
    if (!is.null(page_token) && nzchar(page_token))
      path <- paste0(path, "&page_token=", utils::URLencode(page_token, reserved = TRUE))
    data <- .feishu_bitable_request(cfg, "GET", path, table_id = table_id)
    batch <- data$items %||% list()
    if (length(batch)) items <- c(items, batch)
    has_more <- isTRUE(data$has_more)
    page_token <- data$page_token %||% ""
    if (!has_more || !nzchar(as.character(page_token))) break
  }
  items
}

#' 清空指定表全部记录（优先批量删除）
feishu_bitable_clear_table <- function(cfg, table_id, dry_run = FALSE) {
  items <- .feishu_bitable_list_records(cfg, table_id)
  n <- length(items)
  if (!n) {
    cli::cli_alert_info("表 {table_id} 已空，无需清空")
    return(invisible(0L))
  }
  if (isTRUE(dry_run)) {
    cli::cli_alert_info("[dry-run] 将删除表 {table_id} 的 {n} 条记录")
    return(invisible(as.integer(n)))
  }
  ids <- vapply(items, function(item) {
    as.character(item$record_id %||% item$id %||% "")
  }, character(1L))
  ok <- feishu_bitable_batch_delete(cfg, ids, table_id = table_id)
  # 兜底：若批量失败残留，逐条删
  left <- .feishu_bitable_list_records(cfg, table_id)
  if (length(left)) {
    for (item in left) {
      rid <- as.character(item$record_id %||% item$id %||% "")
      if (!nzchar(rid)) next
      tryCatch(feishu_bitable_delete_record(cfg, rid, table_id = table_id),
               error = function(e) NULL)
    }
    ok <- n
  }
  cli::cli_alert_success("表 {table_id} 已清空（约 {n} 条）")
  invisible(as.integer(ok))
}

.feishu_field_text <- function(x, default = "") {
  if (is.null(x) || length(x) == 0) return(default)
  v <- as.character(x[[1L]])
  if (!nzchar(v)) default else v
}

.feishu_fmt_num <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_real_)
  v <- suppressWarnings(as.numeric(x[[1L]]))
  if (!is.finite(v)) NA_real_ else v
}

# 飞书数字字段不接受 NA/null；省略无效数值键
.feishu_compact_payload <- function(payload) {
  payload[vapply(payload, function(v) {
    if (is.null(v) || length(v) == 0) return(FALSE)
    if (is.numeric(v)) return(is.finite(v[[1L]]))
    if (is.character(v)) return(nzchar(v[[1L]]))
    TRUE
  }, logical(1L))]
}

.feishu_now_ms <- function() {
  # 飞书日期字段：Unix 毫秒时间戳（须为 numeric，勿用 integer 防溢出）
  as.numeric(Sys.time()) * 1000
}

.feishu_map_db_mode <- function(db_mode) {
  dm <- tolower(.feishu_field_text(db_mode, "unknown"))
  switch(dm,
         both        = "双库",
         nhanes_only = "仅NHANES",
         mimic_only  = "仅MIMIC",
         nhanes      = "仅NHANES",
         mimic       = "仅MIMIC",
         if (dm %in% c("unknown", "")) "未知" else db_mode)
}

.feishu_map_branch <- function(branch) {
  b <- tolower(.feishu_field_text(branch, "unknown"))
  alias <- c(
    quartile         = "extend_quartile",
    tertile          = "extend_tertile",
    binary           = "extend_binary",
    extend_quartile  = "extend_quartile",
    extend_tertile   = "extend_tertile",
    extend_binary    = "extend_binary",
    degrade_tertile  = "degrade_tertile",
    degrade_binary   = "degrade_binary",
    unknown          = "unknown",
    "n/a"            = "N/A",
    na               = "N/A"
  )
  if (b %in% names(alias)) return(unname(alias[[b]]))
  if (b %in% c("extend_quartile", "extend_tertile", "extend_binary",
               "degrade_tertile", "degrade_binary", "unknown", "n/a"))
    return(if (identical(b, "n/a")) "N/A" else b)
  "unknown"
}

.feishu_map_failure_type <- function(error_message) {
  msg <- tolower(.feishu_field_text(error_message, ""))
  if (!nzchar(msg)) return("其他")
  if (grepl("两库均", msg)) return("两库均不可用")
  if (grepl("数据量|样本|n=", msg)) return("数据量不足")
  if (grepl("error|失败|exception", msg)) return("流水线错误")
  "其他"
}

.feishu_is_success_status <- function(st) {
  identical(tolower(.feishu_field_text(st, "")), "success")
}

.feishu_is_failure_status <- function(st) {
  tolower(.feishu_field_text(st, "")) %in% c("error", "failed", "parse_error")
}

# 解析「状态」列中的运行次序（0=尚无记录 → 下次为首次）
.feishu_parse_run_count <- function(status_text) {
  txt <- trimws(as.character(status_text %||% ""))
  if (!nzchar(txt)) return(0L)
  if (grepl("^首次", txt)) return(1L)
  m <- regexec("^第([0-9]+)次", txt, perl = TRUE)
  hit <- regmatches(txt, m)[[1L]]
  if (length(hit) >= 2L) {
    n <- suppressWarnings(as.integer(hit[2L]))
    if (is.finite(n) && n >= 2L) return(n)
  }
  cn <- c(
    "二十" = 20L, "十九" = 19L, "十八" = 18L, "十七" = 17L, "十六" = 16L,
    "十五" = 15L, "十四" = 14L, "十三" = 13L, "十二" = 12L, "十一" = 11L,
    "十" = 10L, "九" = 9L, "八" = 8L, "七" = 7L, "六" = 6L,
    "五" = 5L, "四" = 4L, "三" = 3L, "二" = 2L
  )
  for (nm in names(cn)) {
    if (grepl(paste0("^第", nm, "次"), txt)) return(cn[[nm]])
  }
  0L
}

.feishu_run_ordinal_cn <- function(n) {
  n <- as.integer(n)[1L]
  if (!is.finite(n) || n < 1L) n <- 1L
  if (n == 1L) return("首次")
  cn <- c(
    "二", "三", "四", "五", "六", "七", "八", "九", "十",
    "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十"
  )
  if (n >= 2L && n <= 21L) return(paste0("第", cn[n - 1L], "次"))
  paste0("第", n, "次")
}

.feishu_run_status_label <- function(prev_status, outcome = c("success", "failure")) {
  outcome <- match.arg(outcome)
  suffix <- if (outcome == "success") "成功" else "失败"
  n <- .feishu_parse_run_count(prev_status) + 1L
  paste0(.feishu_run_ordinal_cn(n), suffix)
}

.feishu_record_key <- function(disease, index_name) {
  paste(trimws(as.character(disease)), trimws(as.character(index_name)), sep = "\x01")
}

.feishu_find_record_by_disease_index <- function(cfg, table_id, disease, index_name) {
  items <- .feishu_bitable_list_records(cfg, table_id)
  if (!length(items)) return(NULL)
  key <- .feishu_record_key(disease, index_name)
  for (item in items) {
    fld <- item$fields %||% list()
    d <- .feishu_field_text(fld[["疾病"]], "")
    ix <- .feishu_field_text(fld[["指标名"]], "")
    if (identical(.feishu_record_key(d, ix), key)) {
      return(list(
        record_id = as.character(item$record_id %||% item$id %||% ""),
        fields = fld
      ))
    }
  }
  NULL
}

.feishu_upsert_record <- function(cfg, table_id, disease, index_name, payload) {
  hit <- .feishu_find_record_by_disease_index(cfg, table_id, disease, index_name)
  if (!is.null(hit) && nzchar(hit$record_id %||% "")) {
    feishu_bitable_update_record(cfg, hit$record_id, payload, table_id = table_id)
    list(action = "update", record_id = hit$record_id)
  } else {
    out <- feishu_bitable_create_record(cfg, payload, table_id = table_id)
    list(action = "create", record_id = out$record$record_id %||% out$record_id %||% NA_character_)
  }
}

.feishu_delete_record_by_disease_index <- function(cfg, table_id, disease, index_name) {
  hit <- .feishu_find_record_by_disease_index(cfg, table_id, disease, index_name)
  if (is.null(hit) || !nzchar(hit$record_id %||% "")) {
    return(list(deleted = FALSE, record_id = NA_character_))
  }
  feishu_bitable_delete_record(cfg, hit$record_id, table_id = table_id)
  list(deleted = TRUE, record_id = hit$record_id)
}

incidence_batch_feishu_build_summary <- function(fields) {
  parts <- c(
    paste0("指标: ", fields$index %||% "?"),
    paste0("库模式: ", fields$db_mode %||% "-"),
    paste0(
      "NHANES: ", fields$nhanes_branch %||% "-",
      " N=", .feishu_fmt_num(fields$n_nhanes_after),
      " OR=", .feishu_fmt_num(fields$nhanes_or)
    ),
    paste0(
      "MIMIC: ", fields$mimic_branch %||% "-",
      " N=", .feishu_fmt_num(fields$n_mimic_after),
      " OR=", .feishu_fmt_num(fields$mimic_or)
    )
  )
  err <- fields$error_message
  if (!is.null(err) && length(err) && nzchar(as.character(err[[1L]])))
    parts <- c(parts, paste0("错误: ", as.character(err[[1L]])))
  if (!is.null(fields$elapsed_sec))
    parts <- c(parts, paste0("耗时(s): ", .feishu_fmt_num(fields$elapsed_sec)))
  paste(parts, collapse = " | ")
}

.feishu_push_success_record <- function(cfg, config, fields) {
  owner <- cfg$owner_default
  if (!nzchar(owner)) owner <- "待分配"
  disease  <- .feishu_field_text(fields$disease, cfg$disease_label)
  protocol <- .feishu_field_text(fields$protocol, cfg$protocol_label)
  lit      <- config$feishu$literature_default %||% cfg$literature_default
  index_nm <- .feishu_field_text(fields$index, "?")

  hit <- .feishu_find_record_by_disease_index(cfg, cfg$table_success_id, disease, index_nm)
  prev_status <- if (!is.null(hit)) .feishu_field_text(hit$fields[["状态"]], "") else ""
  run_status  <- .feishu_run_status_label(prev_status, "success")

  payload <- .feishu_compact_payload(list(
    "指标名"     = index_nm,
    "疾病"       = disease,
    "套路"       = protocol,
    "文献"       = lit,
    "状态"       = run_status,
    "数据库模式" = .feishu_map_db_mode(fields$db_mode),
    "NHANES_分支" = .feishu_map_branch(fields$nhanes_branch),
    "MIMIC_分支"  = .feishu_map_branch(fields$mimic_branch),
    "NHANES_OR"  = .feishu_fmt_num(fields$nhanes_or),
    "MIMIC_OR"   = .feishu_fmt_num(fields$mimic_or),
    "NHANES_N"   = .feishu_fmt_num(fields$n_nhanes_after),
    "MIMIC_N"    = .feishu_fmt_num(fields$n_mimic_after),
    "耗时_秒"    = .feishu_fmt_num(fields$elapsed_sec),
    "项目编号"   = cfg$project_id,
    "负责人"     = owner,
    "是否已交付" = "否",
    "完成时间"   = .feishu_now_ms()
  ))
  out <- .feishu_upsert_record(cfg, cfg$table_success_id, disease, index_nm, payload)
  rm_fail <- .feishu_delete_record_by_disease_index(
    cfg, cfg$table_failure_id, disease, index_nm
  )
  list(action = out$action, status = run_status, removed_failure = isTRUE(rm_fail$deleted))
}

.feishu_push_failure_record <- function(cfg, config, fields) {
  disease  <- .feishu_field_text(fields$disease, cfg$disease_label)
  protocol <- .feishu_field_text(fields$protocol, cfg$protocol_label)
  err      <- .feishu_field_text(fields$error_message, "")
  index_nm <- .feishu_field_text(fields$index, "?")

  hit <- .feishu_find_record_by_disease_index(cfg, cfg$table_failure_id, disease, index_nm)
  prev_status <- if (!is.null(hit)) .feishu_field_text(hit$fields[["状态"]], "") else ""
  run_status  <- .feishu_run_status_label(prev_status, "failure")

  payload <- .feishu_compact_payload(list(
    "指标名"     = index_nm,
    "疾病"       = disease,
    "套路"       = protocol,
    "状态"       = run_status,
    "失败类型"   = .feishu_map_failure_type(err),
    "数据库模式" = .feishu_map_db_mode(fields$db_mode),
    "错误信息"   = if (nzchar(err)) err else incidence_batch_feishu_build_summary(fields),
    "NHANES_N"   = .feishu_fmt_num(fields$n_nhanes_after),
    "MIMIC_N"    = .feishu_fmt_num(fields$n_mimic_after),
    "耗时_秒"    = .feishu_fmt_num(fields$elapsed_sec),
    "项目编号"   = cfg$project_id,
    "备注"       = "",
    "失败时间"   = .feishu_now_ms()
  ))
  out <- .feishu_upsert_record(cfg, cfg$table_failure_id, disease, index_nm, payload)
  list(action = out$action, status = run_status)
}

#' 将单条 batch 状态推送到飞书（成功 → Sheet 2，失败 → Sheet 3）
incidence_batch_feishu_push_result <- function(config, fields) {
  fs <- config$feishu %||% list()
  if (!isTRUE(fs$push_on_worker_finish %||% TRUE)) return(invisible(FALSE))
  cfg <- .feishu_cfg(config)
  if (is.null(cfg)) return(invisible(FALSE))

  ix     <- .feishu_field_text(fields$index, "?")
  status <- .feishu_field_text(fields$status, "")

  if (!cfg$three_table) {
    cli::cli_alert_warning(
      "飞书三表 ID 未配置（FEISHU_BITABLE_TABLE_SUCCESS_ID / FAILURE_ID），跳过 [{ix}]"
    )
    return(invisible(FALSE))
  }

  tryCatch({
    if (.feishu_is_success_status(status)) {
      out <- .feishu_push_success_record(cfg, config, fields)
      verb <- if (identical(out$action, "update")) "更新" else "写入"
      extra <- if (isTRUE(out$removed_failure)) "，已从失败表移除" else ""
      cli::cli_alert_success("飞书已{verb} [{ix}] → 成功指标表（{out$status}{extra}）")
    } else if (.feishu_is_failure_status(status)) {
      out <- .feishu_push_failure_record(cfg, config, fields)
      verb <- if (identical(out$action, "update")) "更新" else "写入"
      cli::cli_alert_success("飞书已{verb} [{ix}] → 失败指标表（{out$status}）")
    } else {
      cli::cli_alert_info("飞书跳过 [{ix}]（status={status}，非成功/失败）")
      return(invisible(FALSE))
    }
    invisible(TRUE)
  }, error = function(e) {
    cli::cli_alert_warning("飞书同步失败 [{ix}]: {conditionMessage(e)}")
    invisible(FALSE)
  })
}

#' 批量结束后更新 Sheet 1 项目汇总行
incidence_batch_feishu_update_summary <- function(config, statuses_df) {
  cfg <- .feishu_cfg(config)
  if (is.null(cfg) || is.null(statuses_df) || !nrow(statuses_df))
    return(invisible(FALSE))

  n_total   <- nrow(statuses_df)
  n_success <- sum(statuses_df$status == "success", na.rm = TRUE)
  n_failed  <- sum(statuses_df$status %in% c("error", "failed", "parse_error"), na.rm = TRUE)
  n_not_run <- n_total - n_success - n_failed

  overall <- if (n_not_run == n_total) {
    "待开始"
  } else if (n_failed > 0L && n_success > 0L) {
    "部分完成"
  } else if (n_failed > 0L && n_success == 0L) {
    "运行中"
  } else if (n_success == n_total) {
    "全部成功"
  } else {
    "运行中"
  }

  owner <- cfg$owner_default
  if (!nzchar(owner)) owner <- "待分配"

  summary_text <- paste0(
    "成功 ", n_success, " / 失败 ", n_failed, " / 未运行 ", n_not_run,
    " / 共 ", n_total
  )

  payload <- list(
    "疾病"         = cfg$disease_label,
    "套路"         = cfg$protocol_label,
    "指标总数"     = n_total,
    "成功数量"     = n_success,
    "失败数量"     = n_failed,
    "未运行数量"   = n_not_run,
    "结果摘要"     = summary_text,
    "整体状态"     = overall,
    "负责人"       = owner,
    "最后同步时间" = .feishu_now_ms()
  )

  tryCatch({
    items <- .feishu_bitable_list_records(cfg, cfg$table_id)
    rec_id <- NULL
    for (item in items) {
      fld <- item$fields %||% list()
      d_match <- identical(.feishu_field_text(fld[["疾病"]], ""), cfg$disease_label)
      p_match <- identical(.feishu_field_text(fld[["套路"]], ""), cfg$protocol_label)
      if (d_match && p_match) {
        rec_id <- item$record_id %||% item$id
        break
      }
    }
    if (nzchar(rec_id %||% "")) {
      feishu_bitable_update_record(cfg, rec_id, payload, table_id = cfg$table_id)
      cli::cli_alert_success("飞书项目汇总行已更新（{overall}）")
    } else {
      feishu_bitable_create_record(cfg, payload, table_id = cfg$table_id)
      cli::cli_alert_success("飞书项目汇总行已新建（{overall}）")
    }
    invisible(TRUE)
  }, error = function(e) {
    cli::cli_alert_warning("飞书汇总行更新失败: {conditionMessage(e)}")
    invisible(FALSE)
  })
}

#' 批量汇总后同步所有指标（仅成功/失败；并更新 Sheet 1）
incidence_batch_feishu_sync_all <- function(config, statuses_df) {
  cfg <- .feishu_cfg(config)
  if (is.null(cfg) || is.null(statuses_df) || !nrow(statuses_df)) return(invisible(0L))

  ok <- 0L
  for (i in seq_len(nrow(statuses_df))) {
    row <- statuses_df[i, , drop = FALSE]
    fields <- as.list(row)
    fields$index <- row$index
    if (isTRUE(incidence_batch_feishu_push_result(config, fields))) ok <- ok + 1L
  }
  if (isTRUE((config$feishu %||% list())$push_on_batch_summary %||% FALSE)) {
    incidence_batch_feishu_update_summary(config, statuses_df)
  }
  cli::cli_alert_info("飞书批量同步完成: {ok}/{nrow(statuses_df)} 条（已跳过未运行）")
  invisible(ok)
}
