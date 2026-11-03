###############################################################################
#  pub_xlsx_surgical.R — 发表 xlsx「外科式」修复（保留 SCI 三线表样式）
#
#  背景（SOSM 2026-09 两轮返工教训，全项目复用）：
#    ✗ 用 write.xlsx / 自建 workbook 整表重写已导出表 → 三线边框、合并、字体全丢
#    ✓ 只能：loadWorkbook + writeData 改单元格；删行走 openpyxl（保留 styles.xml）
#    ⚠ openpyxl 往返会写 inlineStr + xml:space → openxlsx 读出 'xml:space=...' 脏文本
#    ⚠ openxlsx 写的文件留悬空 drawing rel → openpyxl 打开报 KeyError: xl/drawings/drawing1.xml
#    → openpyxl 往返后必须 pub_xlsx_strip()，并用 openxlsx 复读校验 corrupt==0
#
#  配套 python（本文件同级 pub_xlsx_tools/，勿内嵌字符串以免转义地狱）：
#    R/pub_xlsx_tools/xlsx_strip.py          去 drawing 引用 + xml:space
#    R/pub_xlsx_tools/xlsx_delete_rows.py    openpyxl 删行（保样式）
#
#  入口：
#    pub_xlsx_edit_cells(path, edits, sheet = NULL)   # worksheet XML 单元格补丁
#    pub_xlsx_delete_rows(path, rows)                 # rows: 1-based 整数向量；自动 strip+校验
#    pub_xlsx_strip(path)                             # 手动 strip
#    pub_xlsx_verify(path) -> list(readable,corrupt_cells,styles,rows)
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

.pubxs_python <- function() {
  for (p in c("python3", "python")) if (nzchar(Sys.which(p))) return(Sys.which(p))
  stop("需要 python3（openpyxl/lxml）做 xlsx 外科删行", call = FALSE)
}

# 定位 pub_xlsx_tools/*.py：MEDICAL_BLOCKS_ROOT / project$root / getwd()/R 依次尝试
.pubxs_tool <- function(name, root = NULL) {
  cands <- character(0)
  for (base in unique(c(
    root %||% "",
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
    getwd(), file.path(getwd(), "..")
  ))) if (nzchar(base)) {
    cands <- c(cands,
      file.path(base, "R", "pub_xlsx_tools", name),
      file.path(base, "pub_xlsx_tools", name))
  }
  hit <- cands[file.exists(cands)]
  if (!length(hit)) {
    stop("找不到 ", name, "（应在 R/pub_xlsx_tools/；MEDICAL_BLOCKS_ROOT 或 project$root 需指向引擎根）",
         call. = FALSE)
  }
  hit[1]
}

.pubxs_run <- function(script, args, root = NULL) {
  s <- .pubxs_tool(script, root = root)
  r <- suppressWarnings(system2(.pubxs_python(), c(shQuote(s), args), stdout = TRUE, stderr = TRUE))
  st <- attr(r, "status") %||% 0L
  if (!identical(as.integer(st), 0L)) {
    stop("python xlsx 外科操作失败 (", script, "): ", paste(r, collapse = " | "), call. = FALSE)
  }
  invisible(r)
}

#' 单元格级修改（直接补丁 worksheet XML，绝不整表重写）
#' @param edits data.frame(row, col, value)；value=NA 的行跳过
pub_xlsx_edit_cells <- function(path, edits, sheet = NULL, root = NULL) {
  stopifnot(file.exists(path), is.data.frame(edits),
            all(c("row", "col", "value") %in% names(edits)))
  keep <- !vapply(edits$value, function(x) length(x) == 1L && is.na(x), logical(1L))
  edits <- edits[keep, , drop = FALSE]
  if (!nrow(edits)) return(invisible(pub_xlsx_verify(path)))
  suppressPackageStartupMessages(library(openxlsx))
  payload <- data.frame(
    cell = paste0(openxlsx::int2col(as.integer(edits$col)), as.integer(edits$row)),
    value = as.character(edits$value),
    stringsAsFactors = FALSE
  )
  tf <- tempfile(fileext = ".tsv")
  on.exit(unlink(tf), add = TRUE)
  utils::write.table(
    payload, tf, sep = "\t", row.names = FALSE, col.names = TRUE,
    quote = TRUE, qmethod = "double", fileEncoding = "UTF-8"
  )
  pub_xlsx_strip(path, root = root)              # 先清历史 drawing 悬空引用
  args <- c(shQuote(path), shQuote(tf))
  if (!is.null(sheet) && nzchar(as.character(sheet)[1L])) {
    args <- c(args, shQuote(as.character(sheet)[1L]))
  }
  .pubxs_run("xlsx_edit_cells.py", args, root = root)
  pub_xlsx_strip(path, root = root)
  v <- pub_xlsx_verify(path)
  stopifnot(v$readable, identical(as.integer(v$corrupt_cells), 0L))
  invisible(v)
}

#' 删行（strip → openpyxl 删 → strip → openxlsx 复读校验）
pub_xlsx_delete_rows <- function(path, rows, root = NULL) {
  rows <- as.integer(rows)
  stopifnot(length(rows) > 0L, all(rows >= 1L))
  pub_xlsx_strip(path, root = root)
  .pubxs_run("xlsx_delete_rows.py",
             c(shQuote(path), paste(rows, collapse = ",")), root = root)
  pub_xlsx_strip(path, root = root)
  v <- pub_xlsx_verify(path)
  stopifnot(v$readable, identical(as.integer(v$corrupt_cells), 0L))
  invisible(v)
}

#' strip drawing 引用与 xml:space（openpyxl/openxlsx 往返后必跑）
pub_xlsx_strip <- function(path, root = NULL) {
  .pubxs_run("xlsx_strip.py", shQuote(path), root = root)
  invisible(path)
}

#' 校验：可被 openxlsx 读、无 xml:space 脏格、样式数量、行数
pub_xlsx_verify <- function(path) {
  suppressPackageStartupMessages(library(openxlsx))
  d <- tryCatch(read.xlsx(path, colNames = FALSE), error = function(e) NULL)
  if (is.null(d)) return(list(readable = FALSE, corrupt_cells = NA_integer_,
                              styles = NA_integer_, rows = NA_integer_))
  bad <- sum(grepl("xml:space", as.character(unlist(d)), fixed = TRUE))
  nst <- tryCatch(length(loadWorkbook(path)$styleObjects), error = function(e) NA_integer_)
  list(readable = identical(as.integer(bad), 0L), corrupt_cells = bad,
       styles = nst, rows = nrow(d))
}

#' 以文件名为准，把 xlsx A1 / sharedStrings 表内标题同步到 stem（数值零改动）
#'
#' 修复「文件名 Table S2、内题 Table S5」类错位（ML 补充表常见）。
#' 优先走 python/pub_sync_xlsx_a1_to_filename.py（sharedStrings 外科替换）。
pub_sync_xlsx_a1_titles_to_filenames <- function(tab_dir, recursive = FALSE) {
  tab_dir <- as.character(tab_dir %||% "")[1L]
  if (!nzchar(tab_dir) || !dir.exists(tab_dir)) {
    return(invisible(list(n = 0L, files = character(0))))
  }
  files <- list.files(
    tab_dir, pattern = "\\.xlsx$", full.names = TRUE,
    ignore.case = TRUE, recursive = isTRUE(recursive)
  )
  files <- files[!grepl("/~\\$", basename(files))]
  if (!length(files)) {
    return(invisible(list(n = 0L, files = character(0))))
  }
  eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(eng)) eng <- getwd()
  py_script <- file.path(eng, "python", "pub_sync_xlsx_a1_to_filename.py")
  py <- if (nzchar(Sys.which("python3"))) {
    Sys.which("python3")
  } else if (nzchar(Sys.which("python"))) {
    Sys.which("python")
  } else {
    ""
  }
  done <- character(0)
  if (nzchar(py) && file.exists(py_script)) {
    ## 文件名含括号/空格：逐文件调用，避免 system2 在 sh 下拆坏 argv
    st <- character(0)
    for (f in files) {
      one <- tryCatch(
        system2(
          py,
          args = c(shQuote(py_script), shQuote(normalizePath(f, winslash = "/", mustWork = TRUE))),
          stdout = TRUE,
          stderr = TRUE
        ),
        error = function(e) paste0(basename(f), ": error")
      )
      st <- c(st, one)
    }
    done <- character(0)
    for (line in st %||% character(0)) {
      if (grepl(": (set ->|already)", line)) {
        bn <- sub(":.*$", "", line)
        fp <- files[basename(files) == bn]
        if (length(fp)) done <- c(done, fp[[1L]])
      }
    }
    done <- unique(done)
  }
  ## 回退：openxlsx 写 A1。SMB/坏 sharedStrings 上 getCellInfo 可硬崩进程，
  ## 默认跳过 openxlsx（可用 MEDICAL_BLOCKS_ALLOW_OPENXLSX_TITLE_SYNC=1 打开）。
  left <- setdiff(files, done)
  allow_ox <- identical(Sys.getenv("MEDICAL_BLOCKS_ALLOW_OPENXLSX_TITLE_SYNC", ""), "1")
  if (isTRUE(allow_ox) && length(left)) {
    for (f in left) {
      new_title <- tools::file_path_sans_ext(basename(f))
      ok <- tryCatch({
        if (!requireNamespace("openxlsx", quietly = TRUE)) return(FALSE)
        withCallingHandlers({
          cur <- as.character(
            openxlsx::read.xlsx(f, colNames = FALSE, rows = 1L, cols = 1L)[1, 1]
          )
          if (identical(trimws(cur %||% ""), new_title)) return(TRUE)
          if (exists("pub_xlsx_edit_cells", mode = "function")) {
            pub_xlsx_edit_cells(f, data.frame(row = 1L, col = 1L, value = new_title))
            TRUE
          } else {
            wb <- openxlsx::loadWorkbook(f)
            sh <- openxlsx::sheets(wb)[1L]
            openxlsx::writeData(wb, sh, new_title, startCol = 1L, startRow = 1L, colNames = FALSE)
            openxlsx::saveWorkbook(wb, f, overwrite = TRUE)
            TRUE
          }
        }, warning = function(w) invokeRestart("muffleWarning"))
      }, error = function(e) FALSE)
      if (isTRUE(ok)) done <- c(done, f)
    }
  } else if (length(left) && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_info(
      "跳过 openxlsx 表题回退 {length(left)} 个（防 SMB getCellInfo 崩进程）"
    )
  }
  if (requireNamespace("cli", quietly = TRUE) && length(done)) {
    cli::cli_alert_success(
      "表内标题已与文件名对齐: {length(done)}/{length(files)} @ {tab_dir}"
    )
  }
  invisible(list(n = length(done), files = done))
}
