###############################################################################
# batch_prune_failed.R — 批跑结束后删除【failed】结果/检查点（引擎默认开）
#
# 入口：batch_prune_failed_outputs()
# 挂点：study_batch / incidence dual-batch / trajectory / TST 收口末尾
# 关闭：config$*$prune_failed_on_finish = FALSE 或 MEDICAL_BLOCKS_PRUNE_FAILED=0
###############################################################################

#' 是否启用 failed 清理（默认 TRUE）
batch_prune_failed_enabled <- function(config = list()) {
  env <- Sys.getenv("MEDICAL_BLOCKS_PRUNE_FAILED", unset = "")
  if (identical(env, "0") || identical(tolower(env), "false")) return(FALSE)
  if (identical(env, "1") || identical(tolower(env), "true")) return(TRUE)

  cfg <- config %||% list()
  for (key in c("study_batch", "incidence_batch", "ml_batch", "survival_batch",
                "trajectory_batch", "tst_batch", "cum_egdr_kmeans")) {
    blk <- cfg[[key]]
    if (is.list(blk) && !is.null(blk$prune_failed_on_finish)) {
      return(isTRUE(blk$prune_failed_on_finish))
    }
  }
  # 引擎默认：跑完即删 failed，避免占盘
  TRUE
}

.batch_failed_dir_has_nested_success <- function(path) {
  if (!dir.exists(path)) return(FALSE)
  kids <- list.files(path, full.names = FALSE)
  any(grepl("^\u3010success\u3011", kids))
}

.batch_failed_bare_name <- function(bn) {
  sub("^\u3010failed\u3011\\s*", "", as.character(bn)[1L])
}

#' 删除项目下【failed】by_index/by_unit 及对应检查点/日志
#'
#' @param output_base 课题根（含 by_index / by_unit）
#' @param config 可选；读 prune 开关与 keep_nested_success
#' @param units 可选；仅清理这些裸名（NULL=扫全部【failed】）
#' @param also_logs 是否删 logs/<unit>.log（默认 TRUE）
#' @param dry_run 只列不删
#' @return data.frame 已删/跳过记录
batch_prune_failed_outputs <- function(
    output_base,
    config = list(),
    units = NULL,
    also_logs = TRUE,
    dry_run = FALSE
) {
  output_base <- as.character(output_base %||% "")[1L]
  if (!nzchar(output_base) || !dir.exists(output_base)) {
    return(data.frame(
      path = character(0), bare = character(0), action = character(0),
      stringsAsFactors = FALSE
    ))
  }
  if (!batch_prune_failed_enabled(config)) {
    if (exists("cli_alert_info", mode = "function") || requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_info("prune_failed: 已关闭（config 或 MEDICAL_BLOCKS_PRUNE_FAILED=0）")
    }
    return(data.frame(
      path = character(0), bare = character(0), action = "disabled",
      stringsAsFactors = FALSE
    ))
  }

  keep_nested <- TRUE
  for (key in c("study_batch", "incidence_batch", "ml_batch", "survival_batch",
                "trajectory_batch")) {
    blk <- (config %||% list())[[key]]
    if (is.list(blk) && !is.null(blk$prune_failed_keep_nested_success)) {
      keep_nested <- isTRUE(blk$prune_failed_keep_nested_success)
      break
    }
  }

  units <- if (is.null(units)) NULL else unique(as.character(units))
  rows <- list()

  .record <- function(path, bare, action) {
    rows[[length(rows) + 1L]] <<- data.frame(
      path = path, bare = bare, action = action, stringsAsFactors = FALSE
    )
  }

  .maybe_unlink <- function(path, bare, kind = "dir") {
    if (!file.exists(path) && !dir.exists(path)) return(invisible(NULL))
    if (isTRUE(dry_run)) {
      .record(path, bare, paste0("dry_run_", kind))
      return(invisible(NULL))
    }
    ok <- tryCatch({
      if (dir.exists(path)) unlink(path, recursive = TRUE, force = TRUE)
      else unlink(path, force = TRUE)
      TRUE
    }, error = function(e) FALSE)
    .record(path, bare, if (ok) paste0("deleted_", kind) else paste0("error_", kind))
    invisible(NULL)
  }

  for (subdir in c("by_index", "by_unit")) {
    parent <- file.path(output_base, subdir)
    if (!dir.exists(parent)) next
    bns <- list.files(parent, full.names = FALSE)
    failed_bns <- bns[grepl("^\u3010failed\u3011", bns)]
    for (bn in failed_bns) {
      bare <- .batch_failed_bare_name(bn)
      if (!is.null(units) && length(units) && !(bare %in% units)) next
      path <- file.path(parent, bn)
      if (isTRUE(keep_nested) && .batch_failed_dir_has_nested_success(path)) {
        .record(path, bare, "kept_nested_success")
        next
      }
      .maybe_unlink(path, bare, "dir")
    }
  }

  # 项目级 checkpoints/<bare>
  ck_root <- file.path(output_base, "checkpoints")
  if (dir.exists(ck_root)) {
    for (bn in list.files(ck_root, full.names = FALSE)) {
      if (identical(bn, "_shared")) next
      bare <- .batch_failed_bare_name(bn)
      # 只删：目录名带 failed，或 units 指定且 by_* 已无 success
      is_failed_name <- grepl("^\u3010failed\u3011", bn)
      target <- FALSE
      if (is_failed_name) {
        target <- is.null(units) || bare %in% units
      } else if (!is.null(units) && bare %in% units) {
        # 裸名检查点：仅当该 unit 已无 success 包时删
        has_success <- dir.exists(file.path(output_base, "by_unit", paste0("\u3010success\u3011", bare))) ||
          dir.exists(file.path(output_base, "by_index", paste0("\u3010success\u3011", bare)))
        target <- !has_success
      }
      if (target) .maybe_unlink(file.path(ck_root, bn), bare, "checkpoint")
    }
  }

  if (isTRUE(also_logs)) {
    log_dir <- file.path(output_base, "logs")
    if (dir.exists(log_dir)) {
      # 从已记录的 deleted bare 推，或扫描 units
      bares <- unique(vapply(rows, function(r) r$bare[[1L]], character(1)))
      if (!is.null(units) && length(units)) bares <- unique(c(bares, units))
      for (bare in bares) {
        if (!nzchar(bare)) next
        # 若仍有 success，保留日志
        if (dir.exists(file.path(output_base, "by_unit", paste0("\u3010success\u3011", bare))) ||
            dir.exists(file.path(output_base, "by_index", paste0("\u3010success\u3011", bare)))) {
          next
        }
        lp <- file.path(log_dir, paste0(bare, ".log"))
        if (file.exists(lp)) .maybe_unlink(lp, bare, "log")
      }
    }
  }

  out <- if (length(rows)) {
    do.call(rbind, rows)
  } else {
    data.frame(path = character(0), bare = character(0), action = character(0),
               stringsAsFactors = FALSE)
  }

  n_del <- sum(grepl("^deleted_", out$action))
  n_keep <- sum(out$action == "kept_nested_success")
  if (n_del > 0L || n_keep > 0L || isTRUE(dry_run)) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_success(
        "prune_failed: deleted={n_del}; kept_nested_success={n_keep}; dry_run={isTRUE(dry_run)}"
      )
    }
  }

  # 落盘清单（便于审计；不占客户交付）
  tab_dir <- file.path(output_base, "Tables")
  if (!dir.exists(tab_dir)) dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  if (nrow(out)) {
    tryCatch(
      utils::write.csv(
        out,
        file.path(tab_dir, "Pruned_failed_outputs.csv"),
        row.names = FALSE, fileEncoding = "UTF-8"
      ),
      error = function(e) NULL
    )
  }
  invisible(out)
}

#' 从 statuses 表抽出 failed/error 的 unit/index 裸名后清理
batch_prune_failed_from_statuses <- function(output_base, statuses, config = list(),
                                             name_col = NULL) {
  if (is.null(statuses) || !nrow(statuses)) {
    return(batch_prune_failed_outputs(output_base, config = config, units = character(0)))
  }
  if (is.null(name_col)) {
    name_col <- if ("unit" %in% names(statuses)) "unit" else if ("index" %in% names(statuses)) "index" else NULL
  }
  if (is.null(name_col) || !name_col %in% names(statuses)) {
    return(batch_prune_failed_outputs(output_base, config = config))
  }
  st <- as.character(statuses$status)
  failed <- as.character(statuses[[name_col]][st %in% c("failed", "error")])
  failed <- failed[nzchar(failed)]
  # 即使 statuses 漏了，也扫磁盘上全部【failed】
  batch_prune_failed_outputs(output_base, config = config, units = NULL)
}
