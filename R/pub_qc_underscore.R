###############################################################################
# pub_qc_underscore.R — 交付 Figures/Tables/image_information 禁编程下划线（P0）
#
# 规则：.cursor/rules/pub_no_underscore_display.mdc
# 挂点：pub_qc_run_after_project（Layer A3）
###############################################################################

.pub_qc_underscore_allow <- function() {
  c(
    "P_linear", "P_nonlinear", "P_overall", "P_int", "log_rank", "cox_zph",
    "image_information", "summary_results", "summary_result",
    "Flowchart_attrition", "quantile_scheme_cascade", "pass_rule",
    "labevents", "icu_intime", "complete_action", "rubin_pool",
    "boot_ci", "n_boot", "ref_zero", "max_edge", "bad_dpi",
    "AUTO_STUB", "AUTHOR_INPUT"
  )
}

#' 从文本抽取疑似临床/编程展示下划线 token
pub_qc_underscore_tokens <- function(text, allow = NULL) {
  text <- as.character(text %||% "")
  if (!length(text)) return(character(0))
  text <- paste(text, collapse = "\n")
  if (!nzchar(text) || is.na(text)) return(character(0))
  allow <- unique(c(.pub_qc_underscore_allow(), as.character(allow %||% character(0))))
  m <- gregexpr("\\b[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]*\\b", text, perl = TRUE)
  tok <- unique(regmatches(text, m)[[1L]])
  setdiff(tok, allow)
}

.pub_qc_read_xlsx_text <- function(path) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) return(character(0))
  sheets <- tryCatch(openxlsx::getSheetNames(path), error = function(e) character(0))
  if (!length(sheets)) return(character(0))
  out <- character(0)
  for (sh in sheets) {
    d <- tryCatch(
      openxlsx::read.xlsx(path, sheet = sh, colNames = FALSE),
      error = function(e) NULL
    )
    if (is.null(d)) next
    v <- unlist(d, use.names = FALSE)
    v <- as.character(v[!is.na(v)])
    out <- c(out, v)
  }
  out
}

.pub_qc_pdftotext <- function(pdf) {
  bin <- Sys.which("pdftotext")
  if (!nzchar(bin)) return(NA_character_)
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp), add = TRUE)
  st <- tryCatch(
    system2(bin, c("-layout", pdf, tmp), stdout = FALSE, stderr = FALSE),
    error = function(e) 1L
  )
  if (!identical(as.integer(st), 0L) || !file.exists(tmp)) return(NA_character_)
  paste(readLines(tmp, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

.pub_qc_find_delivery_roots <- function(project_root) {
  project_root <- as.character(project_root)[1L]
  cands <- c(
    file.path(project_root, "summary_results"),
    file.path(project_root, "summary_result")
  )
  by_index <- file.path(project_root, "by_index")
  if (dir.exists(by_index)) {
    hits <- list.files(by_index, pattern = "^\u3010success\u3011", full.names = TRUE)
    cands <- c(
      cands,
      file.path(hits, "summary_results"),
      file.path(hits, "summary_result")
    )
  }
  hit <- unique(cands[dir.exists(cands)])
  ## 有定稿 summary_* 时只扫定稿，避免草稿根 Figures/Tables 假 FAIL
  if (length(hit)) return(hit)
  ## 无 summary 时才扫课题根 / success 草稿
  draft <- c(project_root)
  if (dir.exists(by_index)) {
    hits <- list.files(by_index, pattern = "^\u3010success\u3011", full.names = TRUE)
    draft <- c(draft, hits)
  }
  unique(draft[dir.exists(draft)])
}

#' 扫描交付根：Tables xlsx + Figures/pdf + image_information md
#' @return list(ok, n_bad, hits=data.frame(path,file,token,source))
pub_qc_scan_underscores <- function(project_root, allow = NULL) {
  roots <- .pub_qc_find_delivery_roots(project_root)
  hits <- list()
  push <- function(path, file, token, source) {
    hits[[length(hits) + 1L]] <<- data.frame(
      path = path, file = file, token = token, source = source,
      stringsAsFactors = FALSE
    )
  }

  for (root in roots) {
    tab <- file.path(root, "Tables")
    if (dir.exists(tab)) {
      for (f in list.files(tab, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)) {
        txt <- .pub_qc_read_xlsx_text(f)
        tok <- pub_qc_underscore_tokens(txt, allow = allow)
        for (t in tok) push(root, basename(f), t, "table_xlsx")
      }
    }
    fig_pdf <- file.path(root, "Figures", "pdf")
    if (!dir.exists(fig_pdf)) fig_pdf <- file.path(root, "Figures")
    if (dir.exists(fig_pdf)) {
      for (f in list.files(fig_pdf, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)) {
        txt <- .pub_qc_pdftotext(f)
        if (is.na(txt)) next
        tok <- pub_qc_underscore_tokens(txt, allow = allow)
        for (t in tok) push(root, basename(f), t, "figure_pdf")
      }
    }
    md_dir <- file.path(root, "Figures", "image_information")
    if (dir.exists(md_dir)) {
      for (f in list.files(md_dir, pattern = "\\.md$", full.names = TRUE, ignore.case = TRUE)) {
        txt <- paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
        tok <- pub_qc_underscore_tokens(txt, allow = allow)
        for (t in tok) push(root, basename(f), t, "image_information")
      }
    }
  }

  if (!length(hits)) {
    return(list(ok = TRUE, n_bad = 0L, hits = data.frame(
      path = character(), file = character(), token = character(), source = character(),
      stringsAsFactors = FALSE
    )))
  }
  df <- do.call(rbind, hits)
  rownames(df) <- NULL
  list(ok = FALSE, n_bad = nrow(df), hits = df)
}
