###############################################################################
#  pub_dedup_identical_tables.R — 发表 Tables 逐格全等去重（全项目复用）
#
#  踩坑：ML 性能 wide validation 被写成 Table 3 又写 Table 5；Cox ML continuous
#  既落主文 Table 4 又残留 Table S6。写作/评分必抓。
#
#  策略：对 Tables/*.xlsx 比「数据区」哈希（忽略 A1 表号与文件名）；同哈希保留
#  优先序：主文号更小 > 补充表号更小 > 文件名更短；其余移入 _archive_identical/。
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

.pub_dedup_table_role_key <- function(bn) {
  bn <- as.character(bn %||% "")[1L]
  m_main <- regmatches(bn, regexpr("(?i)^Table\\s+(\\d+)\\b", bn, perl = TRUE))
  if (length(m_main) && nzchar(m_main)) {
    n <- suppressWarnings(as.integer(sub("(?i)^Table\\s+", "", m_main, perl = TRUE)))
    if (is.finite(n)) return(list(kind = "main", n = n))
  }
  m_s <- regmatches(bn, regexpr("(?i)^Table\\s+S(\\d+)\\b", bn, perl = TRUE))
  if (length(m_s) && nzchar(m_s)) {
    n <- suppressWarnings(as.integer(sub("(?i)^Table\\s+S", "", m_s, perl = TRUE)))
    if (is.finite(n)) return(list(kind = "supp", n = n))
  }
  list(kind = "other", n = 9999L)
}

.pub_dedup_xlsx_body_hash <- function(path) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    return(paste0("raw:", as.character(tools::md5sum(path))))
  }
  ## 悬空 drawing 时 openxlsx 可能失败 → 退回文件 md5（仍可去重同字节副本）
  df <- tryCatch(
    {
      suppressMessages(openxlsx::read.xlsx(path, colNames = FALSE, skipEmptyRows = FALSE))
    },
    error = function(e) NULL
  )
  if (is.null(df) || !nrow(df)) {
    return(paste0("raw:", as.character(tools::md5sum(path))))
  }
  ## 去掉首行标题（常含 Table N 号），比内容本体
  body <- if (nrow(df) >= 2L) df[-1L, , drop = FALSE] else df
  raw <- paste(apply(body, 1L, function(r) paste(as.character(r), collapse = "\t")),
               collapse = "\n")
  paste0("body:", digest::digest(raw, algo = "md5", serialize = FALSE))
}

#' 删除 Tables/ 内逐格全等的重复发表表
#'
#' @param tables_dir Tables 目录
#' @param dry_run 只报告
#' @param archive_subdir 归档子目录名（相对 tables_dir）
#' @return data.frame(keep, drop, hash)
pub_dedup_identical_tables <- function(tables_dir,
                                       dry_run = FALSE,
                                       archive_subdir = "_archive_identical") {
  tables_dir <- as.character(tables_dir %||% "")[1L]
  if (!nzchar(tables_dir) || !dir.exists(tables_dir)) {
    return(invisible(data.frame()))
  }
  if (!requireNamespace("digest", quietly = TRUE)) {
    warning("pub_dedup_identical_tables: 需要 digest 包", call. = FALSE)
    return(invisible(data.frame()))
  }
  files <- list.files(tables_dir, pattern = "(?i)^Table.*\\.xlsx$", full.names = TRUE)
  files <- files[!grepl("/_", dirname(files)) & !grepl("^_", basename(files))]
  if (length(files) < 2L) return(invisible(data.frame()))

  hashes <- vapply(files, .pub_dedup_xlsx_body_hash, character(1L))
  by_h <- split(files, hashes)
  plan <- list()
  for (h in names(by_h)) {
    group <- by_h[[h]]
    if (length(group) < 2L) next
    keys <- lapply(basename(group), .pub_dedup_table_role_key)
    ord <- order(
      vapply(keys, function(k) if (identical(k$kind, "main")) 0L else if (identical(k$kind, "supp")) 1L else 2L, 1L),
      vapply(keys, function(k) as.integer(k$n), 1L),
      nchar(basename(group)),
      basename(group)
    )
    keep <- group[ord[1L]]
    drop <- group[ord[-1L]]
    plan[[length(plan) + 1L]] <- data.frame(
      hash = h, keep = basename(keep), drop = paste(basename(drop), collapse = " | "),
      n_drop = length(drop), stringsAsFactors = FALSE
    )
    if (!isTRUE(dry_run)) {
      arch <- file.path(tables_dir, archive_subdir)
      dir.create(arch, recursive = TRUE, showWarnings = FALSE)
      for (f in drop) {
        dest <- file.path(arch, basename(f))
        if (file.exists(dest)) {
          dest <- file.path(arch, paste0(
            tools::file_path_sans_ext(basename(f)), "_",
            format(Sys.time(), "%H%M%S"), ".xlsx"
          ))
        }
        ok <- file.rename(f, dest)
        if (!isTRUE(ok)) {
          file.copy(f, dest, overwrite = TRUE)
          unlink(f)
        }
      }
    }
  }
  out <- if (length(plan)) do.call(rbind, plan) else data.frame()
  if (nrow(out) && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_info(
      "pub_dedup_identical_tables: {nrow(out)} 组全等表（dry_run={dry_run}）"
    )
  }
  invisible(out)
}
