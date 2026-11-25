#!/usr/bin/env Rscript
# Table S3 → 对齐 Dong 补充材料 Supplementary Table 3（按性别分层宽表）：
# Exposure family | Processing | Sex → Male / Female × OR · p · q
#
#   Rscript run/environment_exwas/rebuild_pancancer_table_s3_dong_style.R
#
opt <- list(
  root = "/mnt/g/02block_result/58_cancer/environment_41380607",
  data_dir = "/mnt/g/02block_result/58_cancer/environment_41380607/data"
)
ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
repo <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(repo)
source(file.path(repo, "R/utils.R"))
if (file.exists(file.path(repo, "R/pub_xlsx_surgical.R"))) {
  source(file.path(repo, "R/pub_xlsx_surgical.R"))
}
if (file.exists(file.path(repo, "R/environment_exwas_core.R"))) {
  source(file.path(repo, "R/environment_exwas_core.R"))
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
  if (exists("pub_format_p", mode = "function")) {
    vapply(p, function(z) {
      if (!is.finite(z)) "" else as.character(pub_format_p(z))
    }, character(1))
  } else {
    ifelse(!is.finite(p), "", ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
  }
}

csv_path <- file.path(src_tab, "Table S3. ExWAS stratified by sex.csv")
csv_long_bak <- file.path(src_tab, "Table S3. ExWAS stratified by sex_long.bak.csv")
if (!file.exists(csv_path) && file.exists(csv_long_bak)) csv_path <- csv_long_bak
if (!file.exists(csv_path)) stop("缺少 ", csv_path)
raw <- utils::read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE)
# 若已是宽表（无 stratum），改读备份
if (!"stratum" %in% names(raw)) {
  if (!file.exists(csv_long_bak)) stop("S3 已是宽表且无 long 备份")
  raw <- utils::read.csv(csv_long_bak, stringsAsFactors = FALSE, check.names = FALSE)
}
# 首次：保留 long 底稿
if ("stratum" %in% names(raw) && !file.exists(csv_long_bak)) {
  utils::write.csv(raw, csv_long_bak, row.names = FALSE)
}
# 该文件可能混有年龄层；S3 只要性别
raw <- raw[raw$stratum %in% c("Male", "Female"), , drop = FALSE]
if (!nrow(raw)) stop("S3 CSV 无 Male/Female 行")

fam_df <- utils::read.csv(file.path(opt$data_dir, "toxicant_family_map.csv"), stringsAsFactors = FALSE)
lab_map <- stats::setNames(fam_df$Exposure, fam_df$Labels)
fam_map <- stats::setNames(fam_df$Family, fam_df$Labels)
disp_of <- function(raw_code, fallback = NULL) {
  x <- unname(lab_map[raw_code])
  x <- ifelse(is.na(x) | !nzchar(x), {
    if (!is.null(fallback) && length(fallback)) fallback else raw_code
  }, x)
  if (exists("pipeline_display_label", mode = "function")) {
    vapply(as.character(x), pipeline_display_label, character(1), USE.NAMES = FALSE)
  } else gsub("_", " ", as.character(x), fixed = TRUE)
}
fam_of <- function(raw_code) {
  x <- unname(fam_map[raw_code])
  ifelse(is.na(x) | !nzchar(x), "Other", x)
}

raw$raw_code <- sub("_(ln|bin)$", "", raw$exposure)
raw$Processing <- ifelse(
  grepl("_bin$", raw$exposure), "2 categories",
  ifelse(grepl("_ln$", raw$exposure), "log (ln)", "")
)
raw$name <- ifelse(
  !is.na(raw$exposure_name) & nzchar(raw$exposure_name),
  disp_of(raw$raw_code, raw$exposure_name),
  disp_of(raw$raw_code)
)
# 若 map 有更规范文献名则覆盖
for (i in seq_len(nrow(raw))) {
  nm <- unname(lab_map[raw$raw_code[i]])
  if (!is.na(nm) && nzchar(nm)) {
    raw$name[i] <- if (exists("pipeline_display_label", mode = "function")) {
      pipeline_display_label(nm)
    } else gsub("_", " ", nm)
  }
}
raw$family <- fam_of(raw$raw_code)
raw$OR_ci <- .fmt_or(raw$OR, raw$lo, raw$hi)
raw$p_fmt <- .fmt_p(raw$p)
raw$q_fmt <- .fmt_p(raw$q)

# 宽表：每毒物一行
keys <- unique(raw$exposure)
flat_rows <- lapply(keys, function(x) {
  sub <- raw[raw$exposure == x, , drop = FALSE]
  m <- sub[sub$stratum == "Male", , drop = FALSE]
  f <- sub[sub$stratum == "Female", , drop = FALSE]
  data.frame(
    exposure = x,
    name = sub$name[1],
    family = sub$family[1],
    Processing = sub$Processing[1],
    Male_OR = if (nrow(m)) m$OR_ci[1] else "",
    Male_p = if (nrow(m)) m$p_fmt[1] else "",
    Male_q = if (nrow(m)) m$q_fmt[1] else "",
    Female_OR = if (nrow(f)) f$OR_ci[1] else "",
    Female_p = if (nrow(f)) f$p_fmt[1] else "",
    Female_q = if (nrow(f)) f$q_fmt[1] else "",
    Male_p_num = if (nrow(m)) as.numeric(m$p[1]) else NA_real_,
    stringsAsFactors = FALSE
  )
})
flat <- do.call(rbind, flat_rows)
fam_levels <- unique(c(fam_df$Family, flat$family))
flat$family <- factor(flat$family, levels = fam_levels)
flat <- flat[order(flat$family, flat$Male_p_num, flat$name), , drop = FALSE]

.mk <- function(name, proc = "", m_or = "", m_p = "", m_q = "",
                f_or = "", f_p = "", f_q = "") {
  data.frame(
    col1 = name, col2 = proc,
    col3 = m_or, col4 = m_p, col5 = m_q,
    col6 = f_or, col7 = f_p, col8 = f_q,
    stringsAsFactors = FALSE
  )
}
out_rows <- list(); is_level <- logical(0)
for (fam in levels(flat$family)) {
  sub <- flat[flat$family == fam & !is.na(flat$family), , drop = FALSE]
  if (!nrow(sub)) next
  out_rows[[length(out_rows) + 1L]] <- .mk(as.character(fam))
  is_level <- c(is_level, FALSE)
  for (i in seq_len(nrow(sub))) {
    out_rows[[length(out_rows) + 1L]] <- .mk(
      sub$name[i], sub$Processing[i],
      sub$Male_OR[i], sub$Male_p[i], sub$Male_q[i],
      sub$Female_OR[i], sub$Female_p[i], sub$Female_q[i]
    )
    is_level <- c(is_level, TRUE)
  }
}
body <- do.call(rbind, out_rows)
colnames(body) <- c(
  "Exposure family by toxicant exposure", "Processing",
  "Male_OR", "Male_p", "Male_q", "Female_OR", "Female_p", "Female_q"
)

n_tox <- sum(is_level)
n_male <- unique(raw$n_stratum[raw$stratum == "Male"])
n_female <- unique(raw$n_stratum[raw$stratum == "Female"])
n_tot <- sum(c(n_male, n_female), na.rm = TRUE)
title <- sprintf(
  paste0(
    "Table S3. Exposome-wide association study of %d environmental toxicants with pan-cancer ",
    "among %s United States adults: Stratified by Sex."
  ),
  n_tox,
  format(as.integer(n_tot), big.mark = ",", trim = TRUE)
)
footnotes <- c(
  "Adjusted logistic models within sex strata; covariates match Table 2 Model 2 (without Gender).",
  "OR per IQR for log (ln) exposures; 2 categories = detectable vs undetectable.",
  "q-values: Benjamini–Hochberg FDR within each sex stratum.",
  sprintf("Analytic n: Male = %s; Female = %s.",
          format(as.integer(n_male[1]), big.mark = ",", trim = TRUE),
          format(as.integer(n_female[1]), big.mark = ",", trim = TRUE))
)

# CSV 宽表
body_csv <- body
colnames(body_csv) <- c(
  "Exposure family by toxicant exposure", "Processing",
  "Male OR (95% CI)", "Male p", "Male q",
  "Female OR (95% CI)", "Female p", "Female q"
)
body_csv[[1]][is_level] <- paste0("    ", body_csv[[1]][is_level])
utils::write.csv(body_csv, file.path(src_tab, "Table S3. ExWAS stratified by sex.csv"), row.names = FALSE)

out_xlsx <- file.path(sum_tab, "Table S3. ExWAS stratified by sex.xlsx")
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)
nc <- ncol(body)

# ---- 三层表头（对齐 Dong S3）----
# h1: Exposure | Processing | Sex (span 3-8)
# h2:           |            | Male (3-5) | Female (6-8)
# h3:           |            | OR | p | q | OR | p | q
if (!requireNamespace("openxlsx", quietly = TRUE)) stop("需要 openxlsx")
wb <- openxlsx::createWorkbook()
sh <- "Table S3"
openxlsx::addWorksheet(wb, sh, gridLines = FALSE)

title_style <- openxlsx::createStyle(
  fontSize = 12, fontName = "Times New Roman", halign = "center", textDecoration = "bold"
)
h_style <- openxlsx::createStyle(
  fontSize = 11, fontName = "Times New Roman", halign = "center", valign = "center",
  textDecoration = "bold", wrapText = TRUE,
  border = c("top", "bottom"), borderStyle = c("thick", "thin")
)
h2_style <- openxlsx::createStyle(
  fontSize = 11, fontName = "Times New Roman", halign = "center", valign = "center",
  textDecoration = "bold", wrapText = TRUE,
  border = "bottom", borderStyle = "thin"
)
h3_style <- openxlsx::createStyle(
  fontSize = 11, fontName = "Times New Roman", halign = "center", valign = "center",
  textDecoration = "bold", wrapText = TRUE,
  border = "bottom", borderStyle = "thin"
)
span_style <- openxlsx::createStyle(
  fontSize = 11, fontName = "Times New Roman", halign = "center", valign = "center",
  textDecoration = "bold", wrapText = TRUE,
  border = c("top", "bottom"), borderStyle = c("thick", "thin")
)
body_c <- openxlsx::createStyle(fontSize = 11, fontName = "Times New Roman", halign = "center")
body_l <- openxlsx::createStyle(fontSize = 11, fontName = "Times New Roman", halign = "left")
body_l_indent <- openxlsx::createStyle(
  fontSize = 11, fontName = "Times New Roman", halign = "left", indent = 2L
)
fam_style <- openxlsx::createStyle(
  fontSize = 11, fontName = "Times New Roman", halign = "left", textDecoration = "bold"
)
last_c <- openxlsx::createStyle(
  fontSize = 11, fontName = "Times New Roman", halign = "center",
  border = "bottom", borderStyle = "thick"
)
last_l <- openxlsx::createStyle(
  fontSize = 11, fontName = "Times New Roman", halign = "left",
  border = "bottom", borderStyle = "thick"
)
foot_style <- openxlsx::createStyle(
  fontSize = 11, fontName = "Times New Roman", halign = "left", wrapText = TRUE,
  border = "top", borderStyle = "thin"
)

openxlsx::writeData(wb, sh, title, startRow = 1, startCol = 1, colNames = FALSE)
openxlsx::mergeCells(wb, sh, rows = 1, cols = 1:nc)
openxlsx::addStyle(wb, sh, title_style, rows = 1, cols = 1:nc, gridExpand = TRUE)

# header rows 2-4
openxlsx::writeData(wb, sh, data.frame(
  t(c("Exposure family by toxicant exposure", "Processing", "Sex", "", "", "", "", "")),
  stringsAsFactors = FALSE
), startRow = 2, colNames = FALSE)
openxlsx::writeData(wb, sh, data.frame(
  t(c("", "", "Male", "", "", "Female", "", "")),
  stringsAsFactors = FALSE
), startRow = 3, colNames = FALSE)
openxlsx::writeData(wb, sh, data.frame(
  t(c("", "", "OR (95 %CI)", "p-values", "q-values",
      "OR (95 %CI)", "p-values", "q-values")),
  stringsAsFactors = FALSE
), startRow = 4, colNames = FALSE)

openxlsx::mergeCells(wb, sh, rows = 2:4, cols = 1) # Exposure 竖跨
openxlsx::mergeCells(wb, sh, rows = 2:4, cols = 2) # Processing 竖跨
openxlsx::mergeCells(wb, sh, rows = 2, cols = 3:8) # Sex
openxlsx::mergeCells(wb, sh, rows = 3, cols = 3:5) # Male
openxlsx::mergeCells(wb, sh, rows = 3, cols = 6:8) # Female

openxlsx::addStyle(wb, sh, span_style, rows = 2:4, cols = 1, gridExpand = TRUE)
openxlsx::addStyle(wb, sh, span_style, rows = 2:4, cols = 2, gridExpand = TRUE)
openxlsx::addStyle(wb, sh, h_style, rows = 2, cols = 3:8, gridExpand = TRUE)
openxlsx::addStyle(wb, sh, h2_style, rows = 3, cols = 3:8, gridExpand = TRUE)
openxlsx::addStyle(wb, sh, h3_style, rows = 4, cols = 3:8, gridExpand = TRUE)

body_start <- 5L
openxlsx::writeData(wb, sh, body, startRow = body_start, colNames = FALSE)
last_data <- body_start + nrow(body) - 1L
if (nrow(body) > 0) {
  openxlsx::addStyle(wb, sh, body_c, rows = body_start:last_data, cols = 2:nc, gridExpand = TRUE)
  openxlsx::addStyle(wb, sh, body_l, rows = body_start:last_data, cols = 1, gridExpand = TRUE)
  openxlsx::addStyle(wb, sh, last_c, rows = last_data, cols = 2:nc, gridExpand = TRUE)
  openxlsx::addStyle(wb, sh, last_l, rows = last_data, cols = 1, gridExpand = TRUE)
  for (i in seq_len(nrow(body))) {
    r <- body_start + i - 1L
    if (!isTRUE(is_level[[i]])) {
      openxlsx::addStyle(wb, sh, fam_style, rows = r, cols = 1, gridExpand = FALSE)
    } else {
      openxlsx::addStyle(wb, sh, body_l_indent, rows = r, cols = 1, gridExpand = FALSE)
    }
  }
}

# footnotes
for (i in seq_along(footnotes)) {
  r <- last_data + i
  openxlsx::mergeCells(wb, sh, rows = r, cols = 1:nc)
  openxlsx::writeData(wb, sh, footnotes[[i]], startRow = r, startCol = 1, colNames = FALSE)
  openxlsx::addStyle(
    wb, sh,
    style = if (i == 1L) foot_style else openxlsx::createStyle(
      fontSize = 11, fontName = "Times New Roman", halign = "left", wrapText = TRUE
    ),
    rows = r, cols = 1:nc, gridExpand = TRUE
  )
}
openxlsx::setColWidths(wb, sh, cols = 1:nc, widths = c(34, 12, 18, 10, 10, 18, 10, 10))
openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)
if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)

exwas_log("写完 ", out_xlsx)
exwas_log("毒物=", n_tox, " Male/Female 宽表三层表头")
exwas_log("DONE")
