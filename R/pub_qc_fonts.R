###############################################################################
#  pub_qc_scan_fonts — 交付 PDF 字体门控（Times 系；禁 Helvetica/Arial/sans）
#
#  挂点：pub_qc_run_after_project Layer A4
#  规则：.cursor/rules/pub_times_new_roman.mdc
###############################################################################

.pub_qc_font_allow_re <- function() {
  paste0(
    "(?i)(times|timesnewroman|liberation.?serif|nimbus.?roman|",
    "dejavu.?serif|freese?rif|serif|symbol|zapf|standardsymbols)"
  )
}

.pub_qc_font_deny_re <- function() {
  paste0(
    "(?i)^(helvetica|arial|courier|sans|calibri|segoe|",
    "nimbussans|dejavu.?sans|liberation.?sans|free.?sans)"
  )
}

#' 扫描交付 Figures/pdf 的 pdffonts；命中 Helvetica/Arial/sans 等 → FAIL/P0
#' @param project_root 课题根（优先 summary_results/Figures/pdf）
#' @return list(ok, n_bad, hits=data.frame(file, font, source))
pub_qc_scan_fonts <- function(project_root, pdf_dirs = NULL) {
  project_root <- as.character(project_root %||% "")[1L]
  if (!nzchar(project_root) || !dir.exists(project_root)) {
    return(list(ok = TRUE, n_bad = 0L, hits = data.frame(
      file = character(), font = character(), source = character(),
      stringsAsFactors = FALSE
    )))
  }
  if (is.null(pdf_dirs)) {
    cands <- c(
      file.path(project_root, "summary_results", "Figures", "pdf"),
      file.path(project_root, "summary_result", "Figures", "pdf"),
      file.path(project_root, "Figures", "pdf")
    )
    by_index <- file.path(project_root, "by_index")
    if (dir.exists(by_index)) {
      hits <- list.files(by_index, pattern = "^\u3010success\u3011", full.names = TRUE)
      cands <- c(cands, file.path(hits, "summary_results", "Figures", "pdf"))
    }
    pdf_dirs <- unique(cands[dir.exists(cands)])
  }
  # 有 summary_* 时只扫定稿
  sum_dirs <- pdf_dirs[grepl("summary_results?/Figures/pdf", pdf_dirs)]
  if (length(sum_dirs)) pdf_dirs <- sum_dirs

  pdffonts <- Sys.which("pdffonts")
  if (!nzchar(pdffonts)) {
    return(list(ok = TRUE, n_bad = 0L, hits = data.frame(
      file = character(), font = character(), source = character(),
      stringsAsFactors = FALSE
    ), note = "pdffonts_missing_skip"))
  }

  allow_re <- .pub_qc_font_allow_re()
  deny_re <- .pub_qc_font_deny_re()
  rows <- list()
  for (d in pdf_dirs) {
    pdfs <- list.files(d, pattern = "(?i)\\.pdf$", full.names = TRUE)
    for (fp in pdfs) {
      out <- tryCatch(
        system2(pdffonts, args = shQuote(fp), stdout = TRUE, stderr = TRUE),
        error = function(e) character(0)
      )
      if (!length(out) || length(out) < 3L) next
      # skip header lines (usually 2)
      body <- out[-(1:2)]
      for (ln in body) {
        nm <- trimws(sub("\\s{2,}.*$", "", ln))
        if (!nzchar(nm) || grepl("^-+$", nm)) next
        # Symbol / ZapfDingbats 允许
        if (grepl(allow_re, nm)) next
        if (grepl(deny_re, nm) || grepl("(?i)helvetica|arial|calibri|nimbussans|sans$", nm)) {
          rows[[length(rows) + 1L]] <- data.frame(
            file = basename(fp), font = nm, source = "pdffonts",
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  hits <- if (length(rows)) {
    do.call(rbind, rows)
  } else {
    data.frame(file = character(), font = character(), source = character(),
               stringsAsFactors = FALSE)
  }
  list(ok = nrow(hits) == 0L, n_bad = nrow(hits), hits = hits)
}
