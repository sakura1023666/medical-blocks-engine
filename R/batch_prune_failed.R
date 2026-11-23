###############################################################################
# batch_prune_failed.R — 批跑结束后删除【failed】结果/检查点（引擎默认开）
#
# 入口：
#   batch_prune_failed_outputs() / batch_prune_failed_from_statuses()
#   batch_prune_index_packages()  — 按裸名删 success/bare/failed 包+检查点
#   batch_prune_after_batch()     — failed 后再按 PubMed 查重未过清理
#
# 挂点：study_batch / incidence dual-batch / ML / trajectory / TST 收口末尾
# 关闭 failed：config$*$prune_failed_on_finish = FALSE 或 MEDICAL_BLOCKS_PRUNE_FAILED=0
# 查重未过：config$pubmed_novelty$enable = TRUE（见 R/pubmed_novelty_prune.R）
###############################################################################

`%||%` <- function(a, b) if (is.null(a)) b else a

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
  TRUE
}

.batch_failed_dir_has_nested_success <- function(path) {
  if (!dir.exists(path)) return(FALSE)
  kids <- list.files(path, full.names = FALSE)
  any(grepl("^\u3010success\u3011", kids))
}

.batch_failed_bare_name <- function(bn) {
  sub("^\u3010(failed|success)\u3011\\s*", "", as.character(bn)[1L])
}

.batch_has_success_package <- function(output_base, bare) {
  bare <- as.character(bare)[1L]
  dir.exists(file.path(output_base, "by_unit", paste0("\u3010success\u3011", bare))) ||
    dir.exists(file.path(output_base, "by_index", paste0("\u3010success\u3011", bare)))
}

#' 检查点候选路径（根 + by_index/by_unit + 敏感性嵌套）
.batch_checkpoint_paths_for_bare <- function(output_base, bare) {
  bare <- as.character(bare)[1L]
  ck <- file.path(output_base, "checkpoints")
  if (!dir.exists(ck)) return(character(0))
  c(
    file.path(ck, bare),
    file.path(ck, paste0("\u3010failed\u3011", bare)),
    file.path(ck, "by_index", bare),
    file.path(ck, "by_index", paste0("\u3010failed\u3011", bare)),
    file.path(ck, "by_unit", bare),
    file.path(ck, "by_unit", paste0("\u3010failed\u3011", bare)),
    file.path(ck, "by_index_sensitivity", bare),
    file.path(ck, "by_unit_sensitivity", bare),
    file.path(ck, "by_index_sensitivity", paste0("\u3010failed\u3011", bare)),
    file.path(ck, "by_unit_sensitivity", paste0("\u3010failed\u3011", bare))
  )
}

#' 按裸名删除结果包与检查点（供 failed / novelty 共用）
#'
#' @param also_success 删 【success】<bare>
#' @param also_bare 删 裸名目录（未 rename 的草稿）
#' @param also_failed 删 【failed】<bare>
#' @param reason 写入审计列
batch_prune_index_packages <- function(
    output_base,
    bares,
    config = list(),
    also_success = FALSE,
    also_bare = FALSE,
    also_failed = TRUE,
    also_logs = TRUE,
    dry_run = FALSE,
    reason = "failed"
) {
  output_base <- as.character(output_base %||% "")[1L]
  bares <- unique(as.character(bares %||% character(0)))
  bares <- bares[nzchar(bares)]
  empty <- data.frame(
    path = character(0), bare = character(0), action = character(0),
    reason = character(0), stringsAsFactors = FALSE
  )
  if (!nzchar(output_base) || !dir.exists(output_base) || !length(bares)) {
    return(empty)
  }

  rows <- list()
  .record <- function(path, bare, action) {
    rows[[length(rows) + 1L]] <<- data.frame(
      path = path, bare = bare, action = action, reason = reason,
      stringsAsFactors = FALSE
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

  for (bare in bares) {
    for (subdir in c("by_index", "by_unit")) {
      parent <- file.path(output_base, subdir)
      if (!dir.exists(parent)) next
      cands <- character(0)
      if (isTRUE(also_failed)) cands <- c(cands, paste0("\u3010failed\u3011", bare))
      if (isTRUE(also_success)) cands <- c(cands, paste0("\u3010success\u3011", bare))
      if (isTRUE(also_bare)) cands <- c(cands, bare)
      for (bn in unique(cands)) {
        path <- file.path(parent, bn)
        if (!dir.exists(path)) next
        if (grepl("^\u3010failed\u3011", bn) &&
            .batch_failed_dir_has_nested_success(path)) {
          .record(path, bare, "kept_nested_success")
          next
        }
        .maybe_unlink(path, bare, "dir")
      }
    }
    for (cp in .batch_checkpoint_paths_for_bare(output_base, bare)) {
      .maybe_unlink(cp, bare, "checkpoint")
    }
    if (isTRUE(also_logs)) {
      lp <- file.path(output_base, "logs", paste0(bare, ".log"))
      if (file.exists(lp)) .maybe_unlink(lp, bare, "log")
    }
  }

  if (!length(rows)) return(empty)
  do.call(rbind, rows)
}

#' 删除项目下【failed】by_index/by_unit 及对应检查点/日志
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
    if (requireNamespace("cli", quietly = TRUE)) {
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

  failed_bares <- character(0)
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
      failed_bares <- c(failed_bares, bare)
    }
  }
  failed_bares <- unique(c(failed_bares, if (!is.null(units)) units else character(0)))
  failed_bares <- failed_bares[nzchar(failed_bares)]

  for (bare in failed_bares) {
    if (.batch_has_success_package(output_base, bare)) next
    for (cp in .batch_checkpoint_paths_for_bare(output_base, bare)) {
      .maybe_unlink(cp, bare, "checkpoint")
    }
  }

  if (isTRUE(also_logs)) {
    log_dir <- file.path(output_base, "logs")
    if (dir.exists(log_dir)) {
      for (bare in failed_bares) {
        if (.batch_has_success_package(output_base, bare)) next
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
  # 磁盘扫全部【failed】；statuses 仅作兼容入参
  batch_prune_failed_outputs(output_base, config = config, units = NULL)
}

#' 批跑收口：先删【failed】，再按 PubMed 查重未过删 success/裸名包
batch_prune_after_batch <- function(output_base, statuses = NULL, config = list(),
                                    name_col = NULL, dry_run = FALSE) {
  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(root)) root <- getwd()
  .pn <- file.path(root, "R/pubmed_novelty_prune.R")
  if (file.exists(.pn) && !exists("batch_prune_novelty_failed_outputs", mode = "function")) {
    source(.pn, local = FALSE)
  }

  failed_df <- tryCatch(
    batch_prune_failed_from_statuses(
      output_base, statuses, config = config, name_col = name_col
    ),
    error = function(e) {
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning("prune_failed: {conditionMessage(e)}")
      }
      data.frame(path = character(0), bare = character(0), action = character(0),
                 stringsAsFactors = FALSE)
    }
  )

  novelty_df <- data.frame(
    path = character(0), bare = character(0), action = character(0),
    reason = character(0), stringsAsFactors = FALSE
  )
  if (exists("batch_prune_novelty_failed_outputs", mode = "function")) {
    novelty_df <- tryCatch(
      batch_prune_novelty_failed_outputs(
        output_base, config = config, dry_run = dry_run
      ),
      error = function(e) {
        if (requireNamespace("cli", quietly = TRUE)) {
          cli::cli_alert_warning("prune_novelty: {conditionMessage(e)}")
        }
        novelty_df
      }
    )
  }

  invisible(list(failed = failed_df, novelty = novelty_df))
}
