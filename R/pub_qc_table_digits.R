###############################################################################
#  pub_qc_table_digits — 发表表数字格式结构门控（全项目）
#
#  挂点：pub_qc_run_after_project（Layer A 扩展）
#  规则：.cursor/rules/pub_digits_consistency.mdc
#
#  扫 Tables/*.xlsx（及 image_information/*.md）中的反规范写法：
#    - P / DeLong / NRI/IDI / AUC 类单元格裸 "0" / "0.000"
#    - P 写成 "0.0000" / 科学计数未收成 <0.001
#  超参表跳过（允许 0.000237）。
###############################################################################

.pub_qc_find_tables_dirs <- function(project_root) {
  project_root <- as.character(project_root %||% "")[1L]
  if (!nzchar(project_root) || !dir.exists(project_root)) return(character(0))
  hits <- character(0)
  for (cand in c(
    file.path(project_root, "summary_results", "Tables"),
    file.path(project_root, "summary_result", "Tables"),
    file.path(project_root, "Tables")
  )) {
    if (dir.exists(cand)) hits <- c(hits, normalizePath(cand, winslash = "/", mustWork = FALSE))
  }
  # by_index/【success】*/summary_results/Tables 与 by_index/【success】*/Tables
  bi <- file.path(project_root, "by_index")
  if (dir.exists(bi)) {
    for (d in list.dirs(bi, full.names = TRUE, recursive = FALSE)) {
      if (!grepl("\u3010success\u3011|【success】", basename(d))) next
      for (sub in c(
        file.path(d, "summary_results", "Tables"),
        file.path(d, "Tables")
      )) {
        if (dir.exists(sub)) hits <- c(hits, normalizePath(sub, winslash = "/", mustWork = FALSE))
      }
    }
  }
  unique(hits)
}

.pub_qc_xlsx_cell_strings <- function(path) {
  path <- as.character(path)[1L]
  if (!nzchar(path) || !file.exists(path)) return(character(0))
  if (requireNamespace("openxlsx", quietly = TRUE)) {
    d <- tryCatch(
      openxlsx::read.xlsx(path, colNames = FALSE),
      error = function(e) NULL
    )
    if (!is.null(d)) {
      v <- as.character(unlist(d, use.names = FALSE))
      return(trimws(v[!is.na(v) & nzchar(trimws(v))]))
    }
  }
  ## fallback：sharedStrings
  py <- Sys.which("python3")
  if (!nzchar(py)) py <- Sys.which("python")
  if (!nzchar(py)) return(character(0))
  code <- paste(
    "import zipfile,sys",
    "from xml.etree import ElementTree as ET",
    "p=sys.argv[1]",
    "NS={'m':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}",
    "with zipfile.ZipFile(p) as z:",
    "  if 'xl/sharedStrings.xml' not in z.namelist():",
    "    sys.exit(0)",
    "  root=ET.fromstring(z.read('xl/sharedStrings.xml'))",
    "  for si in root.findall('m:si', NS):",
    "    t=''.join(x.text or '' for x in si.iter('{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t'))",
    "    if t.strip(): print(t)",
    sep = "\n"
  )
  out <- tryCatch(
    system2(py, c("-c", code, path), stdout = TRUE, stderr = FALSE),
    error = function(e) character(0)
  )
  trimws(as.character(out %||% character(0)))
}

#' 扫描单表：返回违规 token 列表（空=通过）
pub_qc_table_digits_violations <- function(path) {
  bn <- basename(as.character(path)[1L])
  if (grepl("Hyperparameter|超参", bn, ignore.case = TRUE)) {
    return(character(0))
  }
  cells <- .pub_qc_xlsx_cell_strings(path)
  if (!length(cells)) return(character(0))
  is_metric_ctx <- grepl(
    "DeLong|NRI|IDI|Log-Loss|LogLoss|ML performance|AUC|ROC|P-value|P value|Association|Logistic|Cox|Univariable|VIF",
    bn,
    ignore.case = TRUE
  )
  bad <- character(0)
  for (s in cells) {
    s0 <- trimws(s)
    if (!nzchar(s0) || nchar(s0) > 80L) next
    ## 裸 0 / 0.000 出现在度量语境（整格）
    if (is_metric_ctx && grepl("^(0|0\\.0+|0\\.000)$", s0)) {
      bad <- c(bad, s0)
      next
    }
    ## 任意表：独立单元格 0.000（描述 IQR 内 0.0 允许；整格 0.000 否）
    if (grepl("^[-−]?0\\.000$", s0)) {
      bad <- c(bad, s0)
      next
    }
    ## P 科学计数未收口
    if (is_metric_ctx && grepl("^[0-9]+\\.?[0-9]*[eE]-[0-9]+$", s0)) {
      bad <- c(bad, s0)
    }
  }
  unique(bad)
}

#' 扫项目下全部发表 Tables；返回 list(ok, hits=data.frame)
pub_qc_scan_table_digits <- function(project_root) {
  dirs <- .pub_qc_find_tables_dirs(project_root)
  hits <- list()
  for (td in dirs) {
    for (f in list.files(td, pattern = "\\.xlsx$", full.names = TRUE)) {
      v <- tryCatch(pub_qc_table_digits_violations(f), error = function(e) paste0("ERR:", e$message))
      if (length(v)) {
        hits[[length(hits) + 1L]] <- data.frame(
          path = f,
          file = basename(f),
          bad = paste(utils::head(v, 12L), collapse = "; "),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  df <- if (length(hits)) {
    do.call(rbind, hits)
  } else {
    data.frame(path = character(0), file = character(0), bad = character(0),
               stringsAsFactors = FALSE)
  }
  list(ok = nrow(df) == 0L, n_bad = nrow(df), hits = df, tables_dirs = dirs)
}
