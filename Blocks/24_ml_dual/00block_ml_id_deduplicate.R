###############################################################################
#  ml_id_deduplicate — ML 预测专用：读入原始表后按 ID 去重（data_clean 之前）
#
#  register_block: "ml_id_deduplicate"
#  典型流水线: 本块 → data_clean → column_mapping → …（仅 ML 双库 / ML 预测）
#
#  ml_id_deduplicate = list(
#    enable     = TRUE,          # FALSE 跳过
#    id_column  = NULL,          # NULL → config$data$id_column
#    keep       = "first",       # first | last（同 ID 多行保留策略）
#    stop_if_no_id_col = TRUE    # ID 列缺失时 stop；FALSE 则 warning 跳过
#  )
#
#  读: ctx$data$raw / ctx$data$cleaned；否则从 config$data$rawdata_path 加载
#  写: ctx$data$raw（供 data_clean 续跑）；id_deduplicate_report.csv
###############################################################################

.ml_id_dedup_load_raw <- function(cfg) {
  rawdata_path <- cfg$data$rawdata_path
  rawdata_obj  <- cfg$data$rawdata_obj %||% NULL
  if (is.null(rawdata_path) || !nzchar(as.character(rawdata_path)[1L])) {
    return(NULL)
  }
  abs_raw <- normalizePath(rawdata_path, winslash = "/", mustWork = TRUE)
  if (!is.null(rawdata_obj)) {
    env <- new.env()
    load(abs_raw, envir = env)
    if (exists(rawdata_obj, envir = env, inherits = FALSE)) {
      cand <- get(rawdata_obj, envir = env)
      if (is.data.frame(cand)) return(as.data.frame(cand))
      stop("Object '", rawdata_obj, "' in ", abs_raw, " is not a data.frame", call. = FALSE)
    }
    objs <- ls(env)
    df_objs <- objs[vapply(objs, function(o) is.data.frame(get(o, envir = env)), logical(1L))]
    if (!length(df_objs)) stop("No data.frame found in: ", abs_raw, call. = FALSE)
    return(as.data.frame(get(df_objs[1L], envir = env)))
  }
  if (exists("load_rawdata", mode = "function")) {
    return(as.data.frame(load_rawdata(abs_raw)))
  }
  NULL
}

.ml_id_dedup_write_back <- function(ctx, data) {
  ctx$data$raw <- data
  ctx$data$cleaned <- NULL
  ctx
}

block_ml_id_deduplicate <- function(ctx, ...) {
  cfg <- ctx$config
  bl  <- cfg$ml_id_deduplicate %||% list()
  if (isFALSE(bl$enable %||% TRUE)) {
    cli::cli_alert_info("ml_id_deduplicate$enable=FALSE，跳过。")
    return(ctx)
  }

  id_col <- as.character(bl$id_column %||% cfg$data$id_column %||% "ID")[1L]
  keep   <- tolower(as.character(bl$keep %||% "first")[1L])
  if (!identical(keep, "last")) keep <- "first"

  data <- ctx$data$raw
  if (is.null(data) || !is.data.frame(data)) data <- ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    cli::cli_h2("ml_id_deduplicate: loading raw data")
    data <- .ml_id_dedup_load_raw(cfg)
  }
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    cli::cli_alert_warning("ml_id_deduplicate: 无可用数据，跳过。")
    return(ctx)
  }

  if (!id_col %in% names(data)) {
    msg <- paste0("ml_id_deduplicate: ID 列 ", id_col, " 不在数据中。")
    if (isTRUE(bl$stop_if_no_id_col %||% TRUE)) stop(msg, call. = FALSE)
    cli::cli_alert_warning("{msg} 跳过。")
    return(ctx)
  }

  ids <- data[[id_col]]
  if (is.data.frame(ids)) ids <- ids[[1L]]
  n_before <- nrow(data)
  dup_n    <- sum(duplicated(ids) | duplicated(ids, fromLast = TRUE))
  if (dup_n <= 0L) {
    cli::cli_alert_success("ml_id_deduplicate: {id_col} 无重复 ({n_before} 行)")
    ctx <- .ml_id_dedup_write_back(ctx, data)
    ctx$results$ml_id_deduplicate <- list(
      id_column = id_col, n_before = n_before, n_after = n_before,
      n_dup_rows_removed = 0L, n_dup_ids = 0L, keep = keep
    )
    return(ctx)
  }

  dup_ids <- unique(as.character(ids[duplicated(ids) | duplicated(ids, fromLast = TRUE)]))
  keep_rows <- if (identical(keep, "last")) {
    !duplicated(ids, fromLast = TRUE)
  } else {
    !duplicated(ids)
  }
  data_out <- data[keep_rows, , drop = FALSE]
  n_after  <- nrow(data_out)
  n_removed <- n_before - n_after

  cli::cli_alert_warning(
    "ml_id_deduplicate: {id_col} 重复 ID {length(dup_ids)} 个，删除 {n_removed} 行（{n_before} → {n_after}，keep={keep}）"
  )

  rep_df <- data.frame(
    id = dup_ids,
    n_rows = as.integer(vapply(dup_ids, function(d) sum(as.character(ids) == d, na.rm = TRUE), integer(1L))),
    stringsAsFactors = FALSE
  )
  rep_df <- rep_df[order(-rep_df$n_rows, rep_df$id), , drop = FALSE]
  names(rep_df)[1L] <- id_col

  ctx <- .ml_id_dedup_write_back(ctx, data_out)

  if (exists("attrition_record", mode = "function")) {
    ctx <- attrition_record(
      ctx, "after_id_deduplicate",
      paste0("After ID deduplication (", id_col, ", keep=", keep, ")"),
      as.integer(n_after),
      meta = list(
        block = "ml_id_deduplicate",
        n_removed = n_removed,
        n_dup_ids = length(dup_ids)
      )
    )
  }

  ctx <- save_result(ctx, "ml_id_deduplicate_report", rep_df, "id_deduplicate_report.csv")
  ctx$results$ml_id_deduplicate <- list(
    id_column = id_col,
    n_before = n_before,
    n_after = n_after,
    n_dup_rows_removed = n_removed,
    n_dup_ids = length(dup_ids),
    keep = keep,
    duplicate_ids = dup_ids
  )
  ctx
}

register_block(
  "ml_id_deduplicate",
  block_ml_id_deduplicate,
  "ML: load raw data and deduplicate rows by subject ID before data_clean"
)
