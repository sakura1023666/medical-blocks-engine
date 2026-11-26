#!/usr/bin/env Rscript
# Table S10 → 对齐 Dong Supplementary Table 10：
# Exposure family | Exposure | Unit | Median (IQR) |
# OR per IQR (95% CI) | OR per Unit (95% CI) | p-values | q-values
# 全毒物（非仅 FDR hits）；每单位 OR = exp(β / IQR)，IQR 取展示 Median 的 Q3−Q1
#
#   Rscript run/environment_exwas/rebuild_pancancer_table_s10_dong_style.R
#
ROOT <- "/mnt/e/01block/01Block-new-Final"
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
source(file.path(ROOT, "R/utils.R"))
if (file.exists(file.path(ROOT, "R/pub_xlsx_surgical.R"))) {
  source(file.path(ROOT, "R/pub_xlsx_surgical.R"))
}

src_tab <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Tables")
sum_tab <- file.path(BASE, "summary_results", "Tables")
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)

flat_csv <- file.path(src_tab, "Table 2. ExWAS Model1 Model2 flat.csv")
bak_csv <- file.path(src_tab, "Table 2. ExWAS toxicant associations_model2_numeric.bak.csv")
s1_csv <- file.path(src_tab, "Table S1. Toxicant analyte characteristics and LOD screen.csv")
meta_csv <- file.path(BASE, "data/dong_supp_table1_meta.csv")
fam_csv <- file.path(BASE, "data/toxicant_family_map.csv")
if (!file.exists(flat_csv)) stop("缺少 ", flat_csv, call. = FALSE)

flat <- utils::read.csv(flat_csv, stringsAsFactors = FALSE, check.names = FALSE)
bak <- if (file.exists(bak_csv)) {
  utils::read.csv(bak_csv, stringsAsFactors = FALSE, check.names = FALSE)
} else {
  NULL
}
fam_df <- utils::read.csv(fam_csv, stringsAsFactors = FALSE)
lab_map <- stats::setNames(as.character(fam_df$Exposure), as.character(fam_df$Labels))
fam_map <- stats::setNames(as.character(fam_df$Family), as.character(fam_df$Labels))

.norm_name <- function(x) {
  x <- tolower(trimws(as.character(x)))
  gsub("[^a-z0-9]+", "", x)
}
# Unit：S1 + Dong meta，规范化键（CYMA / MHBMA3 / Ethylene Oxide …）
unit_by_norm <- character(0)
.add_unit_key <- function(key, unit) {
  unit <- as.character(unit)
  if (!nzchar(unit) || toupper(unit) %in% c("NA", "N/A")) return(invisible(NULL))
  nk <- .norm_name(key)
  if (!nzchar(nk)) return(invisible(NULL))
  if (!nk %in% names(unit_by_norm)) unit_by_norm[[nk]] <<- unit
  invisible(NULL)
}
if (file.exists(s1_csv)) {
  s1 <- utils::read.csv(s1_csv, stringsAsFactors = FALSE, check.names = FALSE)
  for (i in seq_len(nrow(s1))) {
    .add_unit_key(s1$Exposure[i], s1$Unit[i])
    if ("Label" %in% names(s1)) .add_unit_key(s1$Label[i], s1$Unit[i])
  }
}
if (file.exists(meta_csv)) {
  meta <- utils::read.csv(meta_csv, stringsAsFactors = FALSE, check.names = FALSE)
  for (i in seq_len(nrow(meta))) {
    .add_unit_key(meta$Exposure[i], meta$Unit[i])
    if ("Label" %in% names(meta)) .add_unit_key(meta$Label[i], meta$Unit[i])
  }
}
# 常见缩写别名（本队列展示名 ↔ Dong meta Exposure）
.alias_pairs <- list(
  c("HP2MA", "2HPMA"),
  c("HPMA 3", "3HPMA"),
  c("HPMA3", "3HPMA"),
  c("TTC", "TTCA"),
  c("ATC", "ATCA"),
  c("MHA 2", "2MHA"),
  c("MHA2", "2MHA"),
  c("MHA 3 4", "3&4 MHA"),
  c("DCVMA 1 2", "1,2DCVMA"),
  c("DCVMA 2 2", "2,2DCVMA")
)
for (pr in .alias_pairs) {
  a <- .norm_name(pr[[1]]); b <- .norm_name(pr[[2]])
  if (a %in% names(unit_by_norm) && !b %in% names(unit_by_norm)) {
    unit_by_norm[[b]] <- unit_by_norm[[a]]
  }
  if (b %in% names(unit_by_norm) && !a %in% names(unit_by_norm)) {
    unit_by_norm[[a]] <- unit_by_norm[[b]]
  }
}

.disp_tox <- function(code_or_name) {
  raw_code <- sub("_(ln|bin)$", "", as.character(code_or_name))
  nm <- unname(lab_map[raw_code])
  if (is.na(nm) || !nzchar(nm)) nm <- as.character(code_or_name)
  nm <- gsub("_", " ", nm, fixed = TRUE)
  nm <- sub("^Aminonaphthalene 1$", "1-Aminonaphthalene", nm)
  nm <- sub("^Aminonaphthalene 2$", "2-Aminonaphthalene", nm)
  nm <- sub("^Aminobiphenyl 4$", "4-Aminobiphenyl", nm)
  nm <- sub("^Anisidine o$", "o-Anisidine", nm)
  nm <- sub("^Toluidine o$", "o-Toluidine", nm)
  nm <- sub("^Napthol 1$", "1-Naphthol", nm)
  nm <- sub("^Napthol 2$", "2-Naphthol", nm)
  nm <- sub("^Dimethylaniline 2 6$", "2,6-Dimethylaniline", nm)
  nm <- sub("^Hydroxyfluorene 3$", "3-Hydroxyfluorene", nm)
  nm <- sub("^Hydroxyfluorene 2$", "2-Hydroxyfluorene", nm)
  nm <- sub("^Hydroxyphenanthrene 1$", "1-Hydroxyphenanthrene", nm)
  nm <- sub("^Hydroxyphenanthrene 2 3$", "2&3-Hydroxyphenanthrene", nm)
  nm <- sub("^Hydroxypyrene 1$", "1-Hydroxypyrene", nm)
  nm <- sub("^TNE 2$", "TNE-2", nm)
  if (exists("pipeline_display_label", mode = "function")) {
    nm <- pipeline_display_label(nm)
  }
  nm
}
.fmt_or <- function(or, lo, hi) {
  or <- as.numeric(or); lo <- as.numeric(lo); hi <- as.numeric(hi)
  if (!is.finite(or) || !is.finite(lo) || !is.finite(hi)) return("")
  sprintf("%.3f (%.3f, %.3f)", or, lo, hi)
}
.fmt_p <- function(p) {
  p <- as.numeric(p)
  if (!is.finite(p)) return("")
  if (exists("pub_format_p", mode = "function")) return(as.character(pub_format_p(p)))
  if (p < 0.001) return("<0.001")
  sprintf("%.3f", p)
}
.parse_med_iqr_width <- function(s) {
  s <- as.character(s)
  if (!nzchar(s) || toupper(s) %in% c("NA", "N/A")) return(NA_real_)
  m <- regexec("^\\s*([-0-9.]+)\\s*\\(([-0-9.]+),\\s*([-0-9.]+)\\)\\s*$", s)
  g <- regmatches(s, m)[[1]]
  if (length(g) < 4L) return(NA_real_)
  as.numeric(g[4]) - as.numeric(g[3])
}
.parse_or_ci <- function(s) {
  s <- as.character(s)
  m <- regexec("^\\s*([-0-9.]+)\\s*\\(([-0-9.]+),\\s*([-0-9.]+)\\)\\s*$", s)
  g <- regmatches(s, m)[[1]]
  if (length(g) < 4L) return(c(NA_real_, NA_real_, NA_real_))
  as.numeric(g[2:4])
}
.unit_of <- function(disp_name, raw, fam_name = NULL) {
  cands <- unique(c(
    disp_name,
    gsub("_", " ", as.character(disp_name), fixed = TRUE),
    fam_name,
    gsub("_", " ", as.character(fam_name %||% ""), fixed = TRUE),
    raw,
    # MHBMA 3 → MHBMA3；HPMA 3 → 3HPMA；HP2MA → 2HPMA
    gsub(" ", "", as.character(disp_name), fixed = TRUE),
    gsub(" ", "", as.character(fam_name %||% ""), fixed = TRUE)
  ))
  cands <- cands[nzchar(as.character(cands)) & !is.na(cands)]
  for (cand in cands) {
    nk <- .norm_name(cand)
    if (nk %in% names(unit_by_norm)) return(unname(unit_by_norm[[nk]]))
  }
  # 数字前后翻转：mhbma3 ↔ 3mhbma；hp2ma ↔ 2hpma
  for (cand in cands) {
    nk <- .norm_name(cand)
    m <- regexec("^([a-z]+)([0-9]+)$", nk)
    if (m[[1]][1] >= 0) {
      g <- regmatches(nk, m)[[1]]
      alt <- paste0(g[3], g[2])
      if (alt %in% names(unit_by_norm)) return(unname(unit_by_norm[[alt]]))
    }
    m2 <- regexec("^([0-9]+)([a-z]+)$", nk)
    if (m2[[1]][1] >= 0) {
      g <- regmatches(nk, m2)[[1]]
      alt <- paste0(g[3], g[2])
      if (alt %in% names(unit_by_norm)) return(unname(unit_by_norm[[alt]]))
    }
  }
  ""
}

# 合并 bak 数值（优先）
bak_idx <- list()
if (!is.null(bak) && nrow(bak)) {
  for (i in seq_len(nrow(bak))) bak_idx[[bak$exposure[i]]] <- i
}

rows <- list()
for (i in seq_len(nrow(flat))) {
  x <- as.character(flat$exposure[i])
  raw <- as.character(flat$raw[i])
  disp <- .disp_tox(if ("name" %in% names(flat)) flat$name[i] else x)
  fam <- as.character(flat$family[i])
  if (is.na(fam) || !nzchar(fam) || toupper(fam) %in% c("NA", "N/A")) {
    fam <- unname(fam_map[raw])
  }
  if (is.na(fam) || !nzchar(fam)) fam <- "Other"
  proc <- as.character(flat$Processing[i])
  med <- as.character(flat$Median_IQR[i])
  if (!nzchar(med)) med <- "NA"

  or_iqr <- lo_iqr <- hi_iqr <- p_v <- q_v <- beta <- se <- NA_real_
  if (length(bak_idx) && !is.null(bak_idx[[x]])) {
    j <- bak_idx[[x]]
    or_iqr <- as.numeric(bak$OR[j])
    lo_iqr <- as.numeric(bak$lo[j])
    hi_iqr <- as.numeric(bak$hi[j])
    p_v <- as.numeric(bak$p[j])
    q_v <- as.numeric(bak$q[j])
    beta <- as.numeric(bak$beta[j])
    se <- as.numeric(bak$se[j])
  } else {
    v <- .parse_or_ci(flat$M2_OR[i])
    or_iqr <- v[1]; lo_iqr <- v[2]; hi_iqr <- v[3]
    p_v <- as.numeric(flat$M2_p[i])
    q_v <- suppressWarnings(as.numeric(flat$M2_q[i]))
  }
  if (!is.finite(q_v) && "M2_q" %in% names(flat)) {
    q_v <- suppressWarnings(as.numeric(flat$M2_q[i]))
  }

  is_bin <- grepl("2 categor|bin", proc, ignore.case = TRUE) || endsWith(x, "_bin")
  iqr_w <- .parse_med_iqr_width(med)
  if (is_bin || !is.finite(iqr_w) || iqr_w <= 0) {
    or_u <- or_iqr; lo_u <- lo_iqr; hi_u <- hi_iqr
    if (is_bin) med <- "NA"
  } else if (is.finite(beta) && is.finite(se)) {
    or_u <- exp(beta / iqr_w)
    lo_u <- exp((beta - 1.96 * se) / iqr_w)
    hi_u <- exp((beta + 1.96 * se) / iqr_w)
  } else if (is.finite(or_iqr) && is.finite(lo_iqr) && is.finite(hi_iqr)) {
    or_u <- or_iqr^(1 / iqr_w)
    lo_u <- lo_iqr^(1 / iqr_w)
    hi_u <- hi_iqr^(1 / iqr_w)
  } else {
    or_u <- lo_u <- hi_u <- NA_real_
  }

  fam_name <- unname(lab_map[raw])
  rows[[length(rows) + 1L]] <- data.frame(
    family = fam,
    exposure_disp = disp,
    Unit = .unit_of(disp, raw, fam_name),
    Median_IQR = med,
    OR_IQR = .fmt_or(or_iqr, lo_iqr, hi_iqr),
    OR_unit = .fmt_or(or_u, lo_u, hi_u),
    p = .fmt_p(p_v),
    q = .fmt_p(q_v),
    p_num = p_v,
    stringsAsFactors = FALSE
  )
}
tab <- do.call(rbind, rows)
fam_levels <- unique(c(as.character(fam_df$Family), tab$family))
tab$family <- factor(tab$family, levels = fam_levels)
tab <- tab[order(tab$family, tab$p_num, tab$exposure_disp), , drop = FALSE]

out <- list()
is_level <- logical(0)
for (f in levels(tab$family)) {
  sub <- tab[as.character(tab$family) == f & !is.na(tab$family), , drop = FALSE]
  if (!nrow(sub)) next
  out[[length(out) + 1L]] <- data.frame(
    `Exposure family` = as.character(f),
    Exposure = "",
    Unit = "",
    `Median (IQR)` = "",
    `OR per IQR (95% CI)` = "",
    `OR per Unit (95% CI)` = "",
    `p-values` = "",
    `q-values` = "",
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  is_level <- c(is_level, FALSE)
  for (i in seq_len(nrow(sub))) {
    out[[length(out) + 1L]] <- data.frame(
      `Exposure family` = "",
      Exposure = sub$exposure_disp[i],
      Unit = sub$Unit[i],
      `Median (IQR)` = sub$Median_IQR[i],
      `OR per IQR (95% CI)` = sub$OR_IQR[i],
      `OR per Unit (95% CI)` = sub$OR_unit[i],
      `p-values` = sub$p[i],
      `q-values` = sub$q[i],
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    is_level <- c(is_level, TRUE)
  }
}
body <- do.call(rbind, out)
rownames(body) <- NULL

n_exp <- sum(is_level)
title <- sprintf(
  "Table S10. Association results per IQR and per unit increase for %d environmental toxicants.",
  n_exp
)
footnotes <- c(
  "Columns: Exposure family, Exposure, Processing, OR (95% CI), p, and q.",
  "Median (IQR) = median (Q1, Q3) on the modeled exposure scale (natural-log for continuous toxicants).",
  "OR per IQR = Model 2 (same as Table 2). OR per Unit = exp(\u03b2 / IQR), where IQR = Q3\u2212Q1 of the modeled exposure and \u03b2 is the Model 2 log-OR for a 1-IQR change.",
  "p-values / q-values are from Model 2 (Benjamini\u2013Hochberg FDR); identical for per-IQR and per-unit because they share the same coefficient test.",
  "Unit from analyte characteristics (Table S1 / Dong matrix dictionary)."
)

out_xlsx <- file.path(sum_tab, "Table S10. Per IQR and per unit associations.xlsx")
utils::write.csv(
  body,
  file.path(src_tab, "Table S10. Per IQR and per unit Dong layout.csv"),
  row.names = FALSE
)

sci_xlsx_single_header_booktabs(
  filepath = out_xlsx,
  title = title,
  df_body = body,
  sheet = "Table S10",
  footnotes = footnotes
)
if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)

if (requireNamespace("openxlsx", quietly = TRUE)) {
  wb <- openxlsx::loadWorkbook(out_xlsx)
  sh <- openxlsx::sheets(wb)[[1]]
  openxlsx::setColWidths(wb, sh, cols = 1:8, widths = c(28, 26, 12, 22, 22, 22, 11, 11))
  fam_style <- openxlsx::createStyle(
    fontSize = 11, fontName = "Times New Roman",
    halign = "left", textDecoration = "bold"
  )
  level_style <- openxlsx::createStyle(
    fontSize = 11, fontName = "Times New Roman",
    halign = "left", indent = 1L
  )
  center <- openxlsx::createStyle(
    fontSize = 11, fontName = "Times New Roman", halign = "center"
  )
  for (i in seq_along(is_level)) {
    r <- 2L + i
    if (!is_level[[i]]) {
      openxlsx::addStyle(wb, sh, fam_style, rows = r, cols = 1, stack = TRUE)
    } else {
      openxlsx::addStyle(wb, sh, level_style, rows = r, cols = 2, stack = TRUE)
      openxlsx::addStyle(wb, sh, center, rows = r, cols = 3:8, gridExpand = TRUE, stack = TRUE)
    }
  }
  openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)
  if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)
}

message("[s10] wrote ", out_xlsx, " rows=", nrow(body), " exposures=", n_exp)
message("[s10] DONE")
