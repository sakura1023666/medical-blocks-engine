#!/usr/bin/env Rscript
# =============================================================================
#  发表 xlsx 外科式修复 CLI（保留 SCI 三线表样式；全项目复用）
#
#  沉淀自 SOSM 2026-09 审稿返工：删重复行、改单元格标签、去 'xml:space' 脏格，
#  全程绝不整表重写（write.xlsx 会丢边框/合并/字体）。见 R/pub_xlsx_surgical.R。
#
#  用法（引擎根目录）:
#    # 删行（1-based）：
#    Rscript run/pub/surgical_xlsx_repair.R --xlsx "Tables/Table 1.xlsx" --delete-rows 34,39
#    # 改单元格：--set ROW,COL=VALUE（可多次；VALUE 里的空格照写）
#    Rscript run/pub/surgical_xlsx_repair.R --xlsx "Tables/Table 3.xlsx" \
#      --set 4,3="35.28 (1.18, 16895.23) ‡" --set 5,1="Note: Firth penalized Cox ..."
#    # 批量改单元格用 CSV（表头 row,col,value）：
#    Rscript run/pub/surgical_xlsx_repair.R --xlsx "Tables/Table 1.xlsx" --edits edits.csv
#    # 仅校验+清洗（去 xml:space / drawing 悬空引用）：
#    Rscript run/pub/surgical_xlsx_repair.R --xlsx "Tables/Table 1.xlsx" --verify-only
#    # 修复后镜像到其它目录（如 mimic/Tables）：
#    Rscript ... --xlsx <src> --delete-rows 34 --mirror <dir1> --mirror <dir2>
#
#  每个 --xlsx 操作后自动 strip + openxlsx 复读校验；corrupt!=0 则非零退出。
# =============================================================================

.init_root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    fp <- sub("^--file=", "", f[[1L]])
    return(normalizePath(file.path(dirname(fp), "..", ".."), winslash = "/", mustWork = FALSE))
  }
  normalizePath(getwd(), winslash = "/")
}
.root <- .init_root()
source(file.path(.root, "R", "pub_xlsx_surgical.R"))
suppressPackageStartupMessages(library(openxlsx))

.parse_args <- function(args) {
  opts <- list(xlsx = NULL, delete_rows = NULL, edits = NULL, sets = list(),
               mirror = character(0), verify_only = FALSE)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--xlsx" && i < length(args)) { opts$xlsx <- args[[i + 1L]]; i <- i + 2L
    } else if (a == "--delete-rows" && i < length(args)) {
      opts$delete_rows <- as.integer(strsplit(args[[i + 1L]], ",")[[1]]); i <- i + 2L
    } else if (a == "--edits" && i < length(args)) { opts$edits <- args[[i + 1L]]; i <- i + 2L
    } else if (a == "--set" && i < length(args)) {
      opts$sets[[length(opts$sets) + 1L]] <- args[[i + 1L]]; i <- i + 2L
    } else if (a == "--mirror" && i < length(args)) {
      opts$mirror <- c(opts$mirror, args[[i + 1L]]); i <- i + 2L
    } else if (a == "--verify-only") { opts$verify_only <- TRUE; i <- i + 1L
    } else { i <- i + 1L }
  }
  opts
}

opts <- .parse_args(commandArgs(trailingOnly = TRUE))
if (is.null(opts$xlsx) || !file.exists(opts$xlsx)) {
  stop("--xlsx 必填且文件需存在: ", opts$xlsx %||% "(空)", call. = FALSE)
}

fail <- 0L
tryCatch({
  if (isTRUE(opts$verify_only)) {
    pub_xlsx_strip(opts$xlsx, root = .root)
  } else {
    if (length(opts$delete_rows)) {
      pub_xlsx_delete_rows(opts$xlsx, opts$delete_rows, root = .root)
      message("deleted rows: ", paste(opts$delete_rows, collapse = ","))
    }
    edits <- NULL
    if (!is.null(opts$edits) && file.exists(opts$edits)) {
      ed <- utils::read.csv(opts$edits, stringsAsFactors = FALSE)
      edits <- ed
    }
    if (length(opts$sets)) {
      rows <- cols <- vals <- integer(0); vs <- character(0)
      for (s in opts$sets) {
        m <- regmatches(s, regexec("^\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*=\\s*(.*)$", s))[[1]]
        if (length(m) < 4) { warning("skip bad --set: ", s); next }
        rows <- c(rows, as.integer(m[2])); cols <- c(cols, as.integer(m[3]))
        vs <- c(vs, m[4])
      }
      se <- data.frame(row = rows, col = cols, value = vs, stringsAsFactors = FALSE)
      edits <- if (is.null(edits)) se else rbind(edits, se)
    }
    if (!is.null(edits) && nrow(edits)) {
      pub_xlsx_edit_cells(opts$xlsx, edits, root = .root)
      message("edited ", nrow(edits), " cell(s)")
    }
  }
}, error = function(e) {
  fail <<- 1L
  message("ERROR: ", conditionMessage(e))
})

v <- pub_xlsx_verify(opts$xlsx)
message(sprintf("verify: readable=%s corrupt=%s styles=%s rows=%s",
                v$readable, v$corrupt_cells, v$styles, v$rows))
if (v$readable && identical(as.integer(v$corrupt_cells), 0L)) {
  for (d in opts$mirror) {
    if (!nzchar(d)) next
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    file.copy(opts$xlsx, file.path(d, basename(opts$xlsx)), overwrite = TRUE)
    message("mirrored -> ", file.path(d, basename(opts$xlsx)))
  }
}
if (fail == 1L || !v$readable || !identical(as.integer(v$corrupt_cells), 0L)) {
  quit(status = 2L)
}
quit(status = 0L)
