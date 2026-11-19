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
  # 含子集前缀名（如 KJQHEV+NimbusSans-Regular）
  # Noto/CJK/SourceHan：Linux 上「Times」常被映到 CJK，Adobe/部分阅读器直接打不开
  paste0(
    "(?i)(^|[+])(helvetica|arial|courier|sans|calibri|segoe|",
    "nimbussans|dejavu.?sans|liberation.?sans|free.?sans|",
    "noto|source.?han|cjk|wenquan|droid.?sans.?fallback|simsun|simhei|microsoft.?yahei)"
  )
}

#' 抽出 PDF 内嵌/引用字体名（优先 pdffonts；失败则扫原始字节常见 CJK token）
pub_pdf_font_names <- function(path) {
  path <- as.character(path %||% "")[1L]
  if (!nzchar(path) || !file.exists(path)) return(character(0))
  pf <- Sys.which("pdffonts")
  if (!nzchar(pf)) {
    for (cand in c("/usr/bin/pdffonts", "/usr/local/bin/pdffonts")) {
      if (file.exists(cand)) { pf <- cand; break }
    }
  }
  if (nzchar(pf) && file.exists(pf)) {
    out <- tryCatch({
      cmd <- paste(shQuote(pf), shQuote(normalizePath(path, winslash = "/", mustWork = TRUE)))
      suppressWarnings(system(cmd, intern = TRUE))
    }, error = function(e) character(0))
    if (length(out) >= 3L) {
      body <- out[-(1:2)]
      nms <- vapply(body, function(ln) {
        cols <- strsplit(trimws(ln), "\\s{2,}")[[1]]
        if (!length(cols)) return(NA_character_)
        nm <- cols[[1L]]
        if (!nzchar(nm) || grepl("^-+$", nm) || identical(nm, "name")) NA_character_ else nm
      }, character(1L), USE.NAMES = FALSE)
      return(unique(stats::na.omit(nms)))
    }
  }
  # 兜底：字节里搜常见坏字体 token（null 安全）
  n <- min(as.integer(file.info(path)$size %||% 0L), 4e6L)
  if (!is.finite(n) || n < 32L) return(character(0))
  raw <- tryCatch(readBin(path, what = "raw", n = n), error = function(e) raw(0))
  if (!length(raw)) return(character(0))
  # 只保留可打印 ASCII，避免 rawToChar 因 NUL 失败
  raw[raw < as.raw(32L) | raw > as.raw(126L)] <- as.raw(32L)
  txt <- rawToChar(raw, multiple = FALSE)
  hits <- character(0)
  for (tok in c(
    "NotoSerifCJK", "NotoSansCJK", "SourceHan", "WenQuanYi",
    "DroidSansFallback", "SimSun", "SimHei", "MicrosoftYaHei"
  )) {
    if (grepl(tok, txt, fixed = TRUE)) hits <- c(hits, tok)
  }
  unique(hits)
}

#' PDF 是否含会令 Adobe 打不开的 CJK/Noto 等字体
pub_pdf_has_unsafe_cjk_font <- function(path) {
  nms <- pub_pdf_font_names(path)
  if (!length(nms)) return(FALSE)
  grepl(
    "(?i)noto|source.?han|cjk|wenquan|droid.?sans.?fallback|simsun|simhei|yahei",
    paste(nms, collapse = " "),
    perl = TRUE
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
  ## Windows R 常找不到 pdffonts：试 PATH / Poppler / WSL
  if (!nzchar(pdffonts)) {
    extra <- c(
      "/usr/bin/pdffonts",
      "/usr/local/bin/pdffonts",
      "C:/Program Files/poppler/Library/bin/pdffonts.exe",
      "C:/poppler/Library/bin/pdffonts.exe"
    )
    hit <- extra[file.exists(extra)]
    if (length(hit)) pdffonts <- hit[[1L]]
  }
  use_wsl <- FALSE
  if ((!nzchar(pdffonts) || !file.exists(pdffonts)) &&
      identical(.Platform$OS.type, "windows")) {
    wsl <- Sys.which("wsl")
    if (nzchar(wsl)) {
      chk <- tryCatch(
        system2(wsl, c("bash", "-lc", "command -v pdffonts"), stdout = TRUE, stderr = FALSE),
        error = function(e) character(0)
      )
      if (length(chk) && nzchar(chk[1L])) {
        use_wsl <- TRUE
        pdffonts <- "wsl_pdffonts"
      }
    }
  }
  if ((!nzchar(pdffonts) || (!use_wsl && !file.exists(pdffonts)))) {
    return(list(
      ok = FALSE, n_bad = 1L,
      hits = data.frame(
        file = "(scanner)", font = "pdffonts_missing", source = "pub_qc_fonts",
        stringsAsFactors = FALSE
      ),
      note = "pdffonts_missing_fail"
    ))
  }

  .win_to_wsl_path <- function(p) {
    p <- gsub("\\\\", "/", as.character(p)[1L])
    if (grepl("^[A-Za-z]:/", p)) {
      drv <- tolower(substr(p, 1L, 1L))
      return(paste0("/mnt/", drv, "/", substring(p, 4L)))
    }
    p
  }
  .run_pdffonts <- function(fp) {
    # Unix R often routes interned system2 through sh (adds 2>/dev/null). Paths with
    # "(" must be shell-quoted or pdffonts never sees the file.
    if (isTRUE(use_wsl)) {
      wp <- .win_to_wsl_path(fp)
      return(tryCatch(
        system2(Sys.which("wsl"), c("pdffonts", shQuote(wp)), stdout = TRUE, stderr = FALSE),
        error = function(e) character(0)
      ))
    }
    tryCatch(
      {
        cmd <- paste(shQuote(pdffonts), shQuote(normalizePath(fp, winslash = "/", mustWork = TRUE)))
        suppressWarnings(system(cmd, intern = TRUE))
      },
      error = function(e) character(0)
    )
  }

  allow_re <- .pub_qc_font_allow_re()
  deny_re <- .pub_qc_font_deny_re()
  rows <- list()
  for (d in pdf_dirs) {
    pdfs <- list.files(d, pattern = "(?i)\\.pdf$", full.names = TRUE)
    for (fp in pdfs) {
      out <- .run_pdffonts(fp)
      if (!length(out) || length(out) < 3L) next
      # skip header lines (usually 2)
      body <- out[-(1:2)]
      # cairo/pdf 常挂未嵌入 Helvetica 空壳；若同文件已嵌入 Times* 则忽略
      # 未嵌入 Helvetica/Courier。仍拒 NimbusSans/Arial 等正文 sans。
      parsed <- list()
      for (ln in body) {
        cols <- strsplit(trimws(ln), "\\s{2,}")[[1]]
        if (!length(cols)) next
        nm <- cols[[1L]]
        if (!nzchar(nm) || grepl("^-+$", nm) || identical(nm, "name")) next
        # pdffonts 在 emb/sub/uni 之间有时只有单空格，会并成 "yes yes yes"
        emb_raw <- if (length(cols) >= 4L) tolower(cols[[4L]]) else ""
        emb_flag <- identical(emb_raw, "yes") || startsWith(emb_raw, "yes ")
        parsed[[length(parsed) + 1L]] <- list(nm = nm, emb = emb_flag)
      }
      has_times_emb <- any(vapply(parsed, function(x) {
        grepl("(?i)times|liberation.?serif|nimbus.?roman", x$nm) && isTRUE(x$emb)
      }, logical(1)))
      for (x in parsed) {
        nm <- x$nm
        if (grepl(allow_re, nm)) next
        is_deny <- grepl(deny_re, nm, perl = TRUE) ||
          grepl("(?i)helvetica|arial|calibri|nimbussans|(^|[+])sans([-_]|$)", nm, perl = TRUE)
        if (!is_deny) next
        if (has_times_emb && !isTRUE(x$emb) &&
            grepl("(?i)^(helvetica|courier)", nm)) {
          next
        }
        rows[[length(rows) + 1L]] <- data.frame(
          file = basename(fp), font = nm, source = "pdffonts",
          stringsAsFactors = FALSE
        )
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
