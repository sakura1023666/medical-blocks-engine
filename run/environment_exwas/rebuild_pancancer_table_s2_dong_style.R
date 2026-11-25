#!/usr/bin/env Rscript
# Table S2 → 对齐 Dong 补充材料 Supplementary Table 2：
# 与主文 Table 2 同版式（家族分组 + Processing + Median + Model1/2），
# 但 q-values = 化学家族内 BH-FDR（familywise FDR sensitivity）。
#
#   Rscript run/environment_exwas/rebuild_pancancer_table_s2_dong_style.R
#
opt <- list(
  root = "/mnt/g/02block_result/58_cancer/environment_41380607",
  data_dir = "/mnt/g/02block_result/58_cancer/environment_41380607/data",
  min_age = 20L
)
ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
repo <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(repo)
source(file.path(repo, "R/utils.R"))
source(file.path(repo, "R/environment_exwas_core.R"))
source(file.path(repo, "R/environment_exwas_aligned.R"))
source(file.path(repo, "R/environment_exwas_toxicant.R"))
if (file.exists(file.path(repo, "R/pub_xlsx_surgical.R"))) {
  source(file.path(repo, "R/pub_xlsx_surgical.R"))
}

root <- opt$root
src_tab <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Tables")
sum_tab <- file.path(root, "summary_results", "Tables")
exwas_log <- function(...) message("[exwas] ", paste0(..., collapse = ""))

.fmt_or <- function(or, lo, hi) {
  or <- as.numeric(or); lo <- as.numeric(lo); hi <- as.numeric(hi)
  ifelse(
    is.finite(or) & is.finite(lo) & is.finite(hi),
    sprintf("%.3f (%.3f, %.3f)", or, lo, hi),
    ""
  )
}
.fmt_p <- function(p) {
  p <- as.numeric(p)
  # 禁止 ifelse(exists, vapply(...))：exists 长度为 1 会截断为第一项
  if (exists("pub_format_p", mode = "function")) {
    vapply(p, function(z) {
      if (!is.finite(z)) "" else as.character(pub_format_p(z))
    }, character(1))
  } else {
    ifelse(!is.finite(p), "", ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
  }
}
.fmt_med_iqr <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) < 3L) return("NA")
  sprintf(
    "%.3f (%.3f, %.3f)",
    stats::median(x),
    stats::quantile(x, 0.25, names = FALSE),
    stats::quantile(x, 0.75, names = FALSE)
  )
}
.fdr_by_family <- function(p, family) {
  out <- rep(NA_real_, length(p))
  for (fam in unique(as.character(family))) {
    idx <- which(as.character(family) == fam)
    out[idx] <- exwas_fdr(p[idx])
  }
  out
}

built <- exwas_tox_build_cancer_table("pancancer", opt$data_dir, min_age = opt$min_age)
d0 <- built$data
d0 <- d0[is.finite(exwas_to_num(d0$URXUCR)) & exwas_to_num(d0$URXUCR) > 0, , drop = FALSE]
d0 <- d0[is.finite(exwas_to_num(d0$WTSA2YR)) & exwas_to_num(d0$WTSA2YR) > 0, , drop = FALSE]
tox <- intersect(built$tox_cols, names(d0))
d1 <- exwas_tox_creatinine_adjust(d0, tox, creat_col = "URXUCR")$data
scr <- exwas_tox_screen_transform(d1, tox)
person <- exwas_tox_drop_person_missing(
  scr$data, scr$keep, max_frac = 1 / 3, cycle_col = "cycle",
  raw_from_model = sub("_(ln|bin)$", "", scr$keep)
)
df <- person$data
covars_full <- intersect(
  c("Age", "Gender", "Race", "Education", "Marital_Status", "PIR_cat", "BMI_cat",
    "Alcohol_drinking", "eGFR"),
  names(df)
)
df <- exwas_aligned_as_model_frame(df, covars_full)
df$DN <- as.integer(exwas_to_num(df$DN) == 1L)
exposures <- scr$keep
exwas_log("S2 N=", nrow(df), " exposures=", length(exposures))

fam_df <- utils::read.csv(file.path(opt$data_dir, "toxicant_family_map.csv"), stringsAsFactors = FALSE)
lab_map <- stats::setNames(fam_df$Exposure, fam_df$Labels)
fam_map <- stats::setNames(fam_df$Family, fam_df$Labels)
disp_of <- function(raw) {
  x <- unname(lab_map[raw])
  x <- ifelse(is.na(x) | !nzchar(x), raw, x)
  if (exists("pipeline_display_label", mode = "function")) {
    vapply(as.character(x), pipeline_display_label, character(1), USE.NAMES = FALSE)
  } else gsub("_", " ", as.character(x), fixed = TRUE)
}
fam_of <- function(raw) {
  x <- unname(fam_map[raw])
  ifelse(is.na(x) | !nzchar(x), "Other", x)
}

exwas_log("Model1 unadjusted …")
m1 <- exwas_run_unweighted(df, "DN", exposures, covars = character(0))
m1$raw <- sub("_(ln|bin)$", "", m1$exposure)

m2_candidates <- c(
  file.path(root, "Output_pancancer_paperflow_age20_full_noSmoke_UCR_WTSA", "Table_2_ExWAS_toxicant_screen.csv"),
  file.path(src_tab, "Table 2. ExWAS toxicant associations_model2_numeric.bak.csv"),
  file.path(src_tab, "Table 2. ExWAS Model1 Model2 flat.csv")
)
m2_path <- NULL
for (p in m2_candidates) if (file.exists(p)) { m2_path <- p; break }
if (is.null(m2_path)) stop("找不到 Model2 数值源表")
exwas_log("Model2 复用 ", m2_path)
m2 <- utils::read.csv(m2_path, stringsAsFactors = FALSE, check.names = FALSE)
if (!"exposure" %in% names(m2)) {
  if ("Exposure" %in% names(m2)) m2$exposure <- m2$Exposure
}
# flat 备份无 OR 数值时不可用
if (!all(c("OR", "lo", "hi", "p") %in% names(m2))) {
  # 再找 screen
  alt <- file.path(root, "Output_pancancer_paperflow_age20_full_noSmoke_UCR_WTSA",
                   "Table_2_ExWAS_toxicant_screen.csv")
  if (!file.exists(alt)) stop("Model2 缺 OR/lo/hi/p 列")
  m2 <- utils::read.csv(alt, stringsAsFactors = FALSE, check.names = FALSE)
  m2_path <- alt
}
m2$raw <- sub("_(ln|bin)$", "", m2$exposure)

keys <- exposures
rows_flat <- lapply(keys, function(x) {
  r1 <- m1[m1$exposure == x, , drop = FALSE]
  r2 <- m2[m2$exposure == x, , drop = FALSE]
  raw <- sub("_(ln|bin)$", "", x)
  proc <- if (endsWith(x, "_bin")) "2 categories" else if (endsWith(x, "_ln")) "log (ln)" else ""
  med <- if (endsWith(x, "_bin")) "NA" else .fmt_med_iqr(exwas_to_num(df[[x]]))
  data.frame(
    exposure = x, raw = raw, name = disp_of(raw), family = fam_of(raw),
    Processing = proc, Median_IQR = med,
    M1_OR = if (nrow(r1)) .fmt_or(r1$OR[1], r1$lo[1], r1$hi[1]) else "",
    M1_p_num = if (nrow(r1)) as.numeric(r1$p[1]) else NA_real_,
    M2_OR = if (nrow(r2)) .fmt_or(r2$OR[1], r2$lo[1], r2$hi[1]) else "",
    M2_p_num = if (nrow(r2)) as.numeric(r2$p[1]) else NA_real_,
    stringsAsFactors = FALSE
  )
})
flat <- do.call(rbind, rows_flat)
# ★ 家族内 FDR（Dong S2 核心差异）
flat$M1_q_fam <- .fdr_by_family(flat$M1_p_num, flat$family)
flat$M2_q_fam <- .fdr_by_family(flat$M2_p_num, flat$family)
flat$M1_p <- .fmt_p(flat$M1_p_num)
flat$M1_q <- .fmt_p(flat$M1_q_fam)
flat$M2_p <- .fmt_p(flat$M2_p_num)
flat$M2_q <- .fmt_p(flat$M2_q_fam)

fam_levels <- unique(c(fam_df$Family, flat$family))
flat$family <- factor(flat$family, levels = fam_levels)
flat <- flat[order(flat$family, flat$M2_p_num, flat$name), , drop = FALSE]

.mk_row <- function(name, proc = "", med = "", m1or = "", m1p = "", m1q = "",
                    m2or = "", m2p = "", m2q = "") {
  data.frame(
    col1 = name, col2 = proc, col3 = med,
    col4 = m1or, col5 = m1p, col6 = m1q,
    col7 = m2or, col8 = m2p, col9 = m2q,
    stringsAsFactors = FALSE
  )
}
out_rows <- list()
is_level <- logical(0)
for (fam in levels(flat$family)) {
  sub <- flat[flat$family == fam & !is.na(flat$family), , drop = FALSE]
  if (!nrow(sub)) next
  out_rows[[length(out_rows) + 1L]] <- .mk_row(as.character(fam))
  is_level <- c(is_level, FALSE)
  for (i in seq_len(nrow(sub))) {
    out_rows[[length(out_rows) + 1L]] <- .mk_row(
      as.character(sub$name[i]),
      sub$Processing[i], sub$Median_IQR[i],
      sub$M1_OR[i], sub$M1_p[i], sub$M1_q[i],
      sub$M2_OR[i], sub$M2_p[i], sub$M2_q[i]
    )
    is_level <- c(is_level, TRUE)
  }
}
body <- do.call(rbind, out_rows)
colnames(body) <- c(
  "Exposure family by toxicant exposure", "Processing", "Median (IQR)",
  "OR1", "p1", "q1", "OR2", "p2", "q2"
)

title <- sprintf(
  paste0(
    "Table S2. Exposome-wide association study of %d environmental toxicants with pan-cancer ",
    "among %s United States adults: Sensitivity analysis with familywise false discovery ",
    "rate (FDR) correction by chemical class."
  ),
  length(keys), format(nrow(df), big.mark = ",", trim = TRUE)
)
footnotes <- c(
  "Same analysis as Table 2, except q-values are Benjamini–Hochberg FDR recomputed within each chemical family.",
  "Processing: log (ln) = natural-log continuous exposure (OR per IQR); 2 categories = detectable vs undetectable.",
  "Model 1: unadjusted. Model 2: adjusted for Age, Gender, Race, Education, Marital status, PIR, BMI, Alcohol drinking, eGFR (MICE m=5, Rubin's rules).",
  "Bold Model 2 familywise q < 0.05."
)

body_csv <- body
colnames(body_csv) <- c(
  "Exposure family by toxicant exposure", "Processing", "Median (IQR)",
  "Model 1 OR (95% CI)", "Model 1 p", "Model 1 q (family)",
  "Model 2 OR (95% CI)", "Model 2 p", "Model 2 q (family)"
)
body_csv[[1]][is_level] <- paste0("    ", body_csv[[1]][is_level])
utils::write.csv(body_csv, file.path(src_tab, "Table S2. Familywise FDR ExWAS.csv"), row.names = FALSE)
utils::write.csv(flat, file.path(src_tab, "Table S2. Familywise FDR ExWAS flat.csv"), row.names = FALSE)

out_xlsx <- file.path(sum_tab, "Table S2. Familywise FDR ExWAS.xlsx")
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)

h1 <- c(
  "Exposure family by toxicant exposure", "Processing", "Median (IQR)",
  "Model 1", "Model 1", "Model 1",
  "Model 2", "Model 2", "Model 2"
)
h2 <- c(
  NA, NA, NA,
  "OR (95 %CI)", "p-values", "q-values",
  "OR (95 %CI)", "p-values", "q-values"
)

.sci_xlsx_double_header_booktabs(
  filepath = out_xlsx,
  title = title,
  df_body = body,
  h1 = h1,
  h2 = h2,
  sheet = "Table S2",
  footnotes = footnotes,
  col_widths = c(32, 12, 18, 18, 10, 10, 18, 10, 10)
)
if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)

if (requireNamespace("openxlsx", quietly = TRUE)) {
  wb <- openxlsx::loadWorkbook(out_xlsx)
  sh <- openxlsx::sheets(wb)[[1]]
  level_style <- openxlsx::createStyle(
    fontSize = 11, fontName = "Times New Roman", halign = "left", indent = 2L
  )
  fam_style <- openxlsx::createStyle(
    fontSize = 11, fontName = "Times New Roman",
    halign = "left", textDecoration = "bold"
  )
  bold_cell <- openxlsx::createStyle(
    fontSize = 11, fontName = "Times New Roman",
    halign = "center", textDecoration = "bold"
  )
  body_start <- 4L
  for (i in seq_len(nrow(body))) {
    excel_row <- body_start + i - 1L
    if (!isTRUE(is_level[[i]])) {
      openxlsx::addStyle(wb, sh, style = fam_style, rows = excel_row, cols = 1L, gridExpand = FALSE)
    } else {
      openxlsx::addStyle(wb, sh, style = level_style, rows = excel_row, cols = 1L, gridExpand = FALSE)
      qv <- body[[9]][i]
      qnum <- suppressWarnings(as.numeric(gsub("[<>]", "", qv)))
      if (identical(qv, "<0.001") || (is.finite(qnum) && qnum < 0.05)) {
        openxlsx::addStyle(wb, sh, style = bold_cell, rows = excel_row, cols = 7:9, gridExpand = TRUE)
      }
    }
  }
  openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)
  if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)
}

exwas_log("写完 ", out_xlsx)
exwas_log("S2 = Table2 版式 + 家族内 FDR q")
exwas_log("DONE")
