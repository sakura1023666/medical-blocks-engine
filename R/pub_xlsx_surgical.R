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
