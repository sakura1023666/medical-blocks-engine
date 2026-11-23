###############################################################################
# pubmed_novelty_prune.R — 批跑收口：按 PubMed 四维查新未过删除结果/检查点
#
# 四维默认口径：疾病 × 暴露(指标) × 结局 × 方法/分层（如 SOFA+stratification）
# 命中数 > keep_max（默认 0）= 查重未过 → 删 by_index/by_unit 包与检查点。
#
# 启用：config$pubmed_novelty$enable = TRUE
#   或环境变量 MEDICAL_BLOCKS_PRUNE_NOVELTY=1
# 关闭：enable=FALSE 或 MEDICAL_BLOCKS_PRUNE_NOVELTY=0
#
# 命中来源（优先序）：
#   1) config$pubmed_novelty$fail_indices 显式名单
#   2) result_csv（列 index + count_col，默认 pubmed_*method* / pubmed_4d / n）
#   3) reports/ 下自动找 *pubmed*method*.csv / *pubmed_novelty*.csv
###############################################################################

`%||%` <- function(a, b) if (is.null(a)) b else a

pubmed_novelty_prune_enabled <- function(config = list()) {
  env <- Sys.getenv("MEDICAL_BLOCKS_PRUNE_NOVELTY", unset = "")
  if (identical(env, "0") || identical(tolower(env), "false")) return(FALSE)
  if (identical(env, "1") || identical(tolower(env), "true")) return(TRUE)
  pn <- (config %||% list())$pubmed_novelty
  if (is.list(pn) && !is.null(pn$enable)) return(isTRUE(pn$enable))
  FALSE
}

.pubmed_novelty_cfg <- function(config = list()) {
  pn <- (config %||% list())$pubmed_novelty
  if (!is.list(pn)) pn <- list()
  pn
}

.pubmed_novelty_read_csv <- function(path) {
  path <- as.character(path %||% "")[1L]
  if (!nzchar(path) || !file.exists(path)) return(NULL)
  tryCatch(
    utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) NULL
  )
}

.pubmed_novelty_find_default_csv <- function(output_base) {
  roots <- c(
    file.path(output_base, "reports"),
    file.path(output_base, "Tables"),
    output_base
  )
  pats <- c(
    "*pubmed*method*.csv",
    "*pubmed_novelty*.csv",
    "*pubmed*SIO*.csv",
    "publishable_zero_pubmed*.csv"
  )
  for (root in roots) {
    if (!dir.exists(root)) next
    for (pat in pats) {
      hits <- Sys.glob(file.path(root, pat))
      if (length(hits)) {
        # 优先含 method / 4d 列的表
        return(hits[[1L]])
      }
    }
  }
  NULL
}

.pubmed_novelty_pick_count_col <- function(df, count_col = NULL) {
  nms <- names(df)
  if (!is.null(count_col) && nzchar(count_col) && count_col %in% nms) return(count_col)
  prefer <- c(
    "pubmed_sepsis_index_outcome_methodSOFA",
    "pubmed_SIO_methodSOFA",
    "pubmed_4d", "pubmed_four_way", "n_4d", "n_method",
    "pubmed_count", "n"
  )
  for (p in prefer) if (p %in% nms) return(p)
  hit <- grep("method|sofa|4d|four", nms, ignore.case = TRUE, value = TRUE)
  if (length(hit)) return(hit[[1L]])
  hit2 <- grep("pubmed|count|^n$", nms, ignore.case = TRUE, value = TRUE)
  if (length(hit2)) return(hit2[[1L]])
  NULL
}

.pubmed_novelty_pick_index_col <- function(df) {
  nms <- names(df)
  for (p in c("index", "Index", "unit", "bare", "name")) {
    if (p %in% nms) return(p)
  }
  nms[[1L]]
}

#' 解析查重未过的指标裸名
#'
#' @return character 裸名向量（去重）
pubmed_novelty_fail_indices <- function(output_base, config = list()) {
  pn <- .pubmed_novelty_cfg(config)
  explicit <- unique(as.character(pn$fail_indices %||% character(0)))
  explicit <- explicit[nzchar(explicit)]
  if (length(explicit)) return(explicit)

  csv_path <- as.character(pn$result_csv %||% "")[1L]
  if (!nzchar(csv_path)) {
    csv_path <- .pubmed_novelty_find_default_csv(output_base) %||% ""
  } else if (!file.exists(csv_path) && !grepl("^(/|[A-Za-z]:)", csv_path)) {
    alt <- file.path(output_base, csv_path)
    if (file.exists(alt)) csv_path <- alt
  }
  df <- .pubmed_novelty_read_csv(csv_path)
  if (is.null(df) || !nrow(df)) return(character(0))

  ix_col <- .pubmed_novelty_pick_index_col(df)
  ct_col <- .pubmed_novelty_pick_count_col(df, pn$count_col %||% NULL)
  if (is.null(ct_col)) return(character(0))

  keep_max <- suppressWarnings(as.integer(pn$keep_max %||% 0L)[1L])
  if (!is.finite(keep_max)) keep_max <- 0L

  # 若表只有「四维未发表」白名单（publishable_zero_*），则盘上 success 不在表内的一律算未过
  if (isTRUE(pn$csv_is_pass_list) ||
      grepl("publishable_zero|pass_list|zero_pubmed", basename(csv_path), ignore.case = TRUE)) {
    pass <- unique(as.character(df[[ix_col]]))
    pass <- pass[nzchar(pass)]
    on_disk <- .batch_list_index_bares(output_base)
    return(setdiff(on_disk, pass))
  }

  n <- suppressWarnings(as.numeric(df[[ct_col]]))
  ix <- as.character(df[[ix_col]])
  fail <- ix[is.finite(n) & n > keep_max]
  unique(fail[nzchar(fail)])
}

.batch_list_index_bares <- function(output_base) {
  out <- character(0)
  for (subdir in c("by_index", "by_unit")) {
    parent <- file.path(output_base, subdir)
    if (!dir.exists(parent)) next
    bns <- list.files(parent, full.names = FALSE)
    for (bn in bns) {
      full <- file.path(parent, bn)
      if (!dir.exists(full)) next  # 跳过误放的 txt 等文件
      if (grepl("^\u3010success\u3011", bn) || grepl("^\u3010failed\u3011", bn)) {
        out <- c(out, sub("^\u3010(success|failed)\u3011\\s*", "", bn))
      } else if (!grepl("^\\.|^_", bn)) {
        out <- c(out, bn)
      }
    }
  }
  unique(out[nzchar(out)])
}

#' 删除查重未过指标的结果包与检查点（含 nested checkpoints/by_index）
batch_prune_novelty_failed_outputs <- function(
    output_base,
    config = list(),
    dry_run = FALSE
) {
  output_base <- as.character(output_base %||% "")[1L]
  empty <- data.frame(
    path = character(0), bare = character(0), action = character(0),
    reason = character(0), stringsAsFactors = FALSE
  )
  if (!nzchar(output_base) || !dir.exists(output_base)) return(empty)
  if (!pubmed_novelty_prune_enabled(config)) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_info("prune_novelty: 未启用（config$pubmed_novelty$enable 或 MEDICAL_BLOCKS_PRUNE_NOVELTY）")
    }
    return(empty)
  }

  fails <- pubmed_novelty_fail_indices(output_base, config = config)
  if (!length(fails)) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_info("prune_novelty: 无查重未过指标可删")
    }
    return(empty)
  }

  if (!exists("batch_prune_index_packages", mode = "function")) {
    .pf <- file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "."), "R/batch_prune_failed.R")
    if (file.exists(.pf)) source(.pf, local = FALSE)
  }
  out <- batch_prune_index_packages(
    output_base,
    bares = fails,
    config = config,
    also_success = TRUE,
    also_bare = TRUE,
    also_failed = FALSE,
    also_logs = TRUE,
    dry_run = dry_run,
    reason = "pubmed_novelty_fail"
  )
  if (requireNamespace("cli", quietly = TRUE) && nrow(out)) {
    n_del <- sum(grepl("^deleted_", out$action))
    cli::cli_alert_success(
      "prune_novelty: fail_indices={length(fails)}; deleted={n_del}; dry_run={isTRUE(dry_run)}"
    )
  }
  tab_dir <- file.path(output_base, "Tables")
  if (!dir.exists(tab_dir)) dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  if (nrow(out)) {
    tryCatch(
      utils::write.csv(
        out,
        file.path(tab_dir, "Pruned_novelty_failed_outputs.csv"),
        row.names = FALSE, fileEncoding = "UTF-8"
      ),
      error = function(e) NULL
    )
  }
  invisible(out)
}
