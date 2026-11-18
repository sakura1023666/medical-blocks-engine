###############################################################################
#  easymr_gwas_search — 在 GWAS Catalog 查找欧洲人群、可下载的全基因组汇总统计
#
#  register_block: "easymr_gwas_search"
#  典型位置: 下载数据之前单独跑。不调用 easyMR，也不插入发病/预后主链
#  数据源: GWAS Catalog REST API v2（2026-08 起 v1 已停用）
#          https://www.ebi.ac.uk/gwas/rest/api/v2
#
#  config$easymr_gwas_search = list(
#    query = "albumin",              # 自由词。先匹配 EFO 性状名
#    efo_id = NULL,                  # 填了就只查这一个性状，不再做自由词匹配
#    ancestry = "European",          # API 的 ancestral_group
#    ancestry_mode = "european_only",# european_only：发现样本不含其他人群
#                                    # european_included：只要发现样本里有欧洲人
#    require_summary_stats = TRUE,   # 只要目录里给了 FTP 汇总统计的研究
#    drop_cnv = TRUE,                # 去掉 disease_trait 含 CNV 的条目
#    save_dir = NULL,                # 默认 ctx$output_dir
#    page_size = 100L,
#    max_studies_per_trait = 300L
#  )
#
#  写出:
#    gwas_search_<query>_traits.csv   词匹配到的性状及研究数
#    gwas_search_<query>_studies.csv  按发表日期从新到旧
#    gwas_search_<query>.md           下载说明（Catalog 页、PubMed、FTP）
#  ctx$results$easymr_gwas_search: csv、md、n_studies
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}

.gwas_api <- "https://www.ebi.ac.uk/gwas/rest/api/v2"

.gwas_get <- function(path, query = list()) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("需要 R 包 jsonlite")
  }
  q <- query[!vapply(query, function(z) is.null(z) || (length(z) == 1 && is.na(z)), logical(1))]
  q <- lapply(q, function(z) if (is.logical(z)) tolower(as.character(z)) else as.character(z))
  url <- paste0(.gwas_api, path)
  if (length(q)) {
    url <- paste0(url, "?", paste(names(q), vapply(q, utils::URLencode, "", reserved = TRUE), sep = "=", collapse = "&"))
  }
  message("GWAS Catalog: ", url)
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)
  status <- utils::download.file(
    url, tmp, quiet = TRUE, method = "libcurl",
    headers = c("User-Agent" = "medical-blocks/easymr_gwas_search", "Accept" = "application/json")
  )
  if (!identical(status, 0L)) stop("GWAS Catalog 请求失败: ", url)
  jsonlite::fromJSON(tmp, simplifyVector = FALSE)
}

.gwas_pages <- function(path, query, embedded, page_size, max_n) {
  page <- 0L
  out <- list()
  repeat {
    q <- c(query, list(page = page, size = page_size))
    d <- .gwas_get(path, q)
    chunk <- d[["_embedded"]][[embedded]] %||% list()
    out <- c(out, chunk)
    total <- d$page$totalElements %||% length(out)
    page <- page + 1L
    if (!length(chunk) || length(out) >= total || length(out) >= max_n || page >= (d$page$totalPages %||% page)) break
    Sys.sleep(0.15)
  }
  if (length(out) > max_n) out <- out[seq_len(max_n)]
  out
}

.gwas_slug <- function(x) {
  x <- tolower(gsub("[^A-Za-z0-9]+", "_", x))
  gsub("^_|_$", "", x)
}

.gwas_parse_ancestry <- function(x) {
  x <- as.character(unlist(x))
  x <- trimws(x[!is.na(x) & nzchar(trimws(x))])
  euro <- 0
  other <- 0
  other_lab <- character()
  unparsed <- character()
  if (!length(x)) {
    return(list(european_n = NA_integer_, other_n = NA_integer_, other_labels = "", unparsed = ""))
  }
  for (s in x) {
    s2 <- gsub("(\\d),(?=\\d)", "\\1", s, perl = TRUE)
    parts <- strsplit(s2, ",\\s*(?=\\d)", perl = TRUE)[[1]]
    for (p in trimws(parts)) {
      if (!nzchar(p) || grepl("^(NR|N/A|NA|not reported)$", p, ignore.case = TRUE)) next
      m <- regexec("^([0-9]+)\\s+(.+)$", p)
      r <- regmatches(p, m)[[1]]
      if (length(r) < 3) {
        unparsed <- c(unparsed, p)
        next
      }
      n <- suppressWarnings(as.numeric(r[[2]]))
      lab <- r[[3]]
      if (grepl("^European\\b", lab, ignore.case = TRUE)) euro <- euro + n else {
        other <- other + n
        other_lab <- c(other_lab, lab)
      }
    }
  }
  list(
    european_n = as.integer(euro),
    other_n = as.integer(other),
    other_labels = paste(unique(other_lab), collapse = "; "),
    unparsed = paste(unique(unparsed), collapse = "; ")
  )
}

.gwas_trait_hits <- function(query, efo_id) {
  if (!is.null(efo_id) && nzchar(efo_id)) {
    d <- .gwas_get(paste0("/efo-traits/", utils::URLencode(efo_id, reserved = TRUE)))
    label <- d$efo_trait %||% d$trait %||% query
    return(data.frame(
      efo_id = efo_id, efo_trait = label, match_how = "efo_id",
      stringsAsFactors = FALSE
    ))
  }
  raw <- .gwas_pages(
    "/efo-traits", list(efo_trait = query), "efo_traits",
    page_size = 100L, max_n = 200L
  )
  if (!length(raw)) {
    return(data.frame(efo_id = character(), efo_trait = character(), match_how = character()))
  }
  tab <- data.frame(
    efo_id = vapply(raw, function(z) z$efo_id %||% "", ""),
    efo_trait = vapply(raw, function(z) z$efo_trait %||% "", ""),
    stringsAsFactors = FALSE
  )
  pat <- paste0("\\b", gsub("([.|()\\^{}+$*?\\[\\]])", "\\\\\\1", query), "\\b")
  tab$match_how <- ifelse(grepl(pat, tab$efo_trait, ignore.case = TRUE), "word", "substring")
  tab <- tab[tab$match_how == "word" | (sum(tab$match_how == "word") == 0), , drop = FALSE]
  if (!any(tab$match_how == "word")) tab$match_how <- "substring_fallback"
  tab
}

.gwas_one_study <- function(s, trait_id, trait_label) {
  anc <- .gwas_parse_ancestry(s$discovery_ancestry)
  efo <- s$efo_traits %||% list()
  efo_lab <- paste(unique(vapply(efo, function(z) z$efo_trait %||% "", "")), collapse = "; ")
  acc <- s$accession_id %||% ""
  list(
    accession_id = acc,
    efo_id = trait_id,
    efo_trait = if (nzchar(efo_lab)) efo_lab else trait_label,
    disease_trait = s$disease_trait %||% "",
    publication_date = "",
    first_author = "",
    journal = "",
    title = "",
    pubmed_id = as.character(s$pubmed_id %||% ""),
    european_n = anc$european_n,
    other_n = anc$other_n,
    other_ancestry = anc$other_labels,
    ancestry_unparsed = anc$unparsed,
    discovery_ancestry = paste(as.character(unlist(s$discovery_ancestry %||% list())), collapse = " | "),
    initial_sample_size = s$initial_sample_size %||% "",
    replication_sample_size = s$replication_sample_size %||% "",
    snp_count = s$snp_count %||% NA_integer_,
    cohort = paste(as.character(unlist(s$cohort %||% list())), collapse = "; "),
    ftp = s$full_summary_stats %||% "",
    catalog_page = if (nzchar(acc)) paste0("https://www.ebi.ac.uk/gwas/studies/", acc) else "",
    pubmed_page = "",
    terms_of_license = s$terms_of_license %||% "",
    is_cnv = grepl("\\bCNV\\b|copy number", paste(s$disease_trait %||% "", s$platforms %||% ""), ignore.case = TRUE)
  )
}

.gwas_fill_publications <- function(rows) {
  ids <- unique(rows$pubmed_id[nzchar(rows$pubmed_id)])
  info <- new.env(parent = emptyenv())
  for (id in ids) {
    Sys.sleep(0.12)
    d <- tryCatch(.gwas_get(paste0("/publications/", id)), error = function(e) NULL)
    if (is.null(d)) next
    info[[id]] <- d
  }
  for (i in seq_len(nrow(rows))) {
    id <- rows$pubmed_id[[i]]
    if (!nzchar(id) || is.null(info[[id]])) next
    d <- info[[id]]
    rows$publication_date[[i]] <- d$publication_date %||% ""
    rows$journal[[i]] <- d$journal %||% ""
    rows$title[[i]] <- d$title %||% ""
    fa <- d$first_author
    rows$first_author[[i]] <- if (is.list(fa)) fa$full_name %||% "" else as.character(fa %||% "")
    rows$pubmed_page[[i]] <- paste0("https://pubmed.ncbi.nlm.nih.gov/", id, "/")
  }
  rows
}

.gwas_write_md <- function(path, query, mode, studies, n_mixed_dropped, n_cnv_dropped) {
  lines <- c(
    paste0("# ", query, "：欧洲人群可下载的 GWAS"),
    "",
    paste0("检索日 ", format(Sys.Date()), "。来源是 GWAS Catalog REST API v2，人种条件为发现样本 ", mode, "，并且目录提供了全基因组汇总统计的 FTP。"),
    paste0("混合人群被拿掉 ", n_mixed_dropped, " 条；CNV 被拿掉 ", n_cnv_dropped, " 条。表内按发表日期从新到旧。"),
    "",
    "样本量 `european_n` 是发现阶段祖先描述里 European 的人数，不是论文里所有分析的总人数。同一性状不同研究的效应量单位可能不同，不能只按样本量决定哪一份能做孟德尔随机化。",
    "",
    "## 下载",
    "",
    "每一行有三个地址：",
    "",
    "- `catalog_page`：GWAS Catalog 研究页，上面有性状、样本和许可。",
    "- `pubmed_page`：原文。",
    "- `ftp`：汇总统计目录。打开后下载其中的 `GCST编号.tsv.gz`。旧一些的目录还会有 `harmonised/GCST编号.h.tsv.gz`，列名和现在 easyMR 用的 GWAS Catalog 文件一致。下载前看 `terms_of_license`。",
    "",
    "## 研究",
    ""
  )
  if (!nrow(studies)) {
    lines <- c(lines, "没有符合条件的研究。")
  } else {
    for (i in seq_len(nrow(studies))) {
      r <- studies[i, ]
      lines <- c(lines, paste0(
        "### ", r$accession_id, "  ", r$publication_date, "  ", r$disease_trait
      ), "", paste0(
        "- 性状：", r$efo_trait, "（", r$efo_id, "）"
      ), paste0(
        "- 欧洲发现样本：", r$european_n, "。原文描述：", r$discovery_ancestry
      ), paste0(
        "- SNP 数：", r$snp_count, "。队列：", r$cohort, "。第一作者：", r$first_author
      ), paste0(
        "- Catalog：", r$catalog_page
      ), paste0(
        "- PubMed：", r$pubmed_page
      ), paste0(
        "- FTP：", r$ftp
      ), "")
    }
  }
  writeLines(lines, path, useBytes = TRUE)
}

block_easymr_gwas_search <- function(ctx, ...) {
  cfg <- (ctx$config$easymr_gwas_search) %||% list()
  query <- cfg$query %||% ""
  if (!nzchar(query) && !nzchar(cfg$efo_id %||% "")) stop("config$easymr_gwas_search$query 为空")
  mode <- cfg[["ancestry_mode"]] %||% "european_only"
  if (!mode %in% c("european_only", "european_included")) {
    stop("ancestry_mode 只能是 european_only 或 european_included")
  }
  save_dir <- cfg$save_dir %||% ctx$output_dir %||% file.path(tempdir(), "gwas_search")
  dir.create(save_dir, recursive = TRUE, showWarnings = FALSE)
  traits <- .gwas_trait_hits(query, cfg$efo_id)
  if (!nrow(traits)) stop("GWAS Catalog 没有匹配到性状：", query)

  n_mixed <- 0L
  n_cnv <- 0L
  pieces <- list()
  trait_n <- integer(nrow(traits))
  for (i in seq_len(nrow(traits))) {
    raw <- .gwas_pages(
      "/studies",
      list(
        efo_id = traits$efo_id[[i]],
        ancestral_group = cfg[["ancestry"]] %||% "European",
        full_pvalue_set = isTRUE(cfg$require_summary_stats %||% TRUE),
        show_child_trait = FALSE
      ),
      "studies",
      page_size = cfg$page_size %||% 100L,
      max_n = cfg$max_studies_per_trait %||% 300L
    )
    trait_n[[i]] <- length(raw)
    rows <- lapply(raw, .gwas_one_study, trait_id = traits$efo_id[[i]], trait_label = traits$efo_trait[[i]])
    if (!length(rows)) next
    tab <- do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
    if (mode == "european_only") {
      keep <- !is.na(tab$european_n) & tab$european_n > 0 &
        (is.na(tab$other_n) | tab$other_n == 0) & !nzchar(tab$ancestry_unparsed)
      n_mixed <- n_mixed + sum(!keep)
      tab <- tab[keep, , drop = FALSE]
    }
    if (isTRUE(cfg$drop_cnv %||% TRUE) && nrow(tab)) {
      n_cnv <- n_cnv + sum(tab$is_cnv)
      tab <- tab[!tab$is_cnv, , drop = FALSE]
    }
    if (nrow(tab)) pieces[[length(pieces) + 1L]] <- tab
  }
  traits$n_api <- trait_n
  studies <- if (length(pieces)) do.call(rbind, pieces) else {
    data.frame(accession_id = character(), publication_date = character())
  }
  if (nrow(studies)) {
    studies <- studies[!duplicated(studies$accession_id), , drop = FALSE]
    studies <- .gwas_fill_publications(studies)
    studies <- studies[order(studies$publication_date, studies$european_n, decreasing = TRUE, na.last = TRUE), , drop = FALSE]
    rownames(studies) <- NULL
  }
  slug <- .gwas_slug(if (nzchar(query)) query else cfg$efo_id)
  trait_csv <- file.path(save_dir, paste0("gwas_search_", slug, "_traits.csv"))
  study_csv <- file.path(save_dir, paste0("gwas_search_", slug, "_studies.csv"))
  md <- file.path(save_dir, paste0("gwas_search_", slug, ".md"))
  utils::write.csv(traits, trait_csv, row.names = FALSE, fileEncoding = "UTF-8")
  utils::write.csv(studies, study_csv, row.names = FALSE, fileEncoding = "UTF-8")
  .gwas_write_md(md, if (nzchar(query)) query else cfg$efo_id, mode, studies, n_mixed, n_cnv)
  message("GWAS 查找写出 ", study_csv, " （", nrow(studies), " 条）")
  ctx$results$easymr_gwas_search <- list(
    traits_csv = trait_csv,
    studies_csv = study_csv,
    markdown = md,
    n_traits = nrow(traits),
    n_studies = nrow(studies),
    n_mixed_dropped = n_mixed,
    n_cnv_dropped = n_cnv
  )
  ctx
}

if (exists("register_block", mode = "function")) {
  register_block("easymr_gwas_search", block_easymr_gwas_search, "查找欧洲人群可下载 GWAS")
}
