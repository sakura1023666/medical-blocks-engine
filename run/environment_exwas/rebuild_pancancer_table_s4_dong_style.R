#!/usr/bin/env Rscript
# Table S4 → 对齐 Dong 补充材料 Supplementary Table 4（按年龄分层宽表）：
# Exposure family | Processing | Age (years) → < 65 / ≥ 65 × OR · p · q
# （癌症常用老年界值 65；由 rerun_pancancer_age65_strata.R 产出 long 源）
#
#   Rscript run/environment_exwas/rebuild_pancancer_table_s4_dong_style.R
#
opt <- list(
  root = "/mnt/g/02block_result/58_cancer/environment_41380607",
  data_dir = "/mnt/g/02block_result/58_cancer/environment_41380607/data",
  age_cut = 65L
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

root <- opt$root
age_cut <- as.integer(opt$age_cut)
lab_lt <- paste0("Age_lt", age_cut)
lab_ge <- paste0("Age_ge", age_cut)
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

csv_path <- file.path(src_tab, "Table S4. ExWAS stratified by age.csv")
csv_long_bak <- file.path(src_tab, "Table S4. ExWAS stratified by age_long.bak.csv")
# 也可从 S3 long 备份抽年龄层
s3_bak <- file.path(src_tab, "Table S3. ExWAS stratified by sex_long.bak.csv")
if (!file.exists(csv_path) && file.exists(csv_long_bak)) csv_path <- csv_long_bak
if (!file.exists(csv_path) && file.exists(s3_bak)) csv_path <- s3_bak
if (!file.exists(csv_path)) stop("缺少 Table S4 / 年龄分层源表")
raw <- utils::read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE)
if (!"stratum" %in% names(raw)) {
  if (file.exists(csv_long_bak)) {
    raw <- utils::read.csv(csv_long_bak, stringsAsFactors = FALSE, check.names = FALSE)
  } else if (file.exists(s3_bak)) {
    raw <- utils::read.csv(s3_bak, stringsAsFactors = FALSE, check.names = FALSE)
  } else stop("S4 已是宽表且无 long 备份")
}
young_aliases <- c(
  lab_lt, paste0("< ", age_cut), paste0("<", age_cut),
  "Age_lt60", "< 60", "<60", "Age_lt65", "< 65", "<65"
)
old_aliases <- c(
  lab_ge, paste0("\u2265 ", age_cut), paste0("\u2265", age_cut),
  paste0(">=", age_cut), "Age_ge60", "\u2265 60", "\u226560", ">=60",
  "Age_ge65", "\u2265 65", "\u226565", ">=65"
)
raw <- raw[raw$stratum %in% c(young_aliases, old_aliases), , drop = FALSE]
if (!nrow(raw)) stop("无年龄分层行 ", lab_lt, " / ", lab_ge)
# 统一 stratum 标签
raw$stratum <- ifelse(raw$stratum %in% young_aliases, lab_lt, lab_ge)
if ("stratum" %in% names(raw) && !file.exists(csv_long_bak)) {
  utils::write.csv(raw, csv_long_bak, row.names = FALSE)
}

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
  !is.na(raw$exposure_name) & nzchar(as.character(raw$exposure_name)),
  disp_of(raw$raw_code, raw$exposure_name),
  disp_of(raw$raw_code)
)
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

lab_young <- paste0("< ", age_cut)
lab_old <- paste0("\u2265 ", age_cut)

keys <- unique(raw$exposure)
flat_rows <- lapply(keys, function(x) {
  sub <- raw[raw$exposure == x, , drop = FALSE]
  a <- sub[sub$stratum == lab_lt, , drop = FALSE]
  b <- sub[sub$stratum == lab_ge, , drop = FALSE]
  data.frame(
    exposure = x,
    name = sub$name[1],
    family = sub$family[1],
    Processing = sub$Processing[1],
    Y_OR = if (nrow(a)) a$OR_ci[1] else "",
    Y_p = if (nrow(a)) a$p_fmt[1] else "",
    Y_q = if (nrow(a)) a$q_fmt[1] else "",
    O_OR = if (nrow(b)) b$OR_ci[1] else "",
    O_p = if (nrow(b)) b$p_fmt[1] else "",
    O_q = if (nrow(b)) b$q_fmt[1] else "",
    Y_p_num = if (nrow(a)) as.numeric(a$p[1]) else NA_real_,
    stringsAsFactors = FALSE
  )
})
flat <- do.call(rbind, flat_rows)
fam_levels <- unique(c(fam_df$Family, flat$family))
flat$family <- factor(flat$family, levels = fam_levels)
flat <- flat[order(flat$family, flat$Y_p_num, flat$name), , drop = FALSE]

.mk <- function(name, proc = "", y_or = "", y_p = "", y_q = "",
                o_or = "", o_p = "", o_q = "") {
  data.frame(
    col1 = name, col2 = proc,
    col3 = y_or, col4 = y_p, col5 = y_q,
    col6 = o_or, col7 = o_p, col8 = o_q,
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
      sub$Y_OR[i], sub$Y_p[i], sub$Y_q[i],
      sub$O_OR[i], sub$O_p[i], sub$O_q[i]
    )
    is_level <- c(is_level, TRUE)
  }
}
body <- do.call(rbind, out_rows)
colnames(body) <- c(
  "Exposure family by toxicant exposure", "Processing",
  "Y_OR", "Y_p", "Y_q", "O_OR", "O_p", "O_q"
)

n_tox <- sum(is_level)
n_y <- unique(raw$n_stratum[raw$stratum == lab_lt])
n_o <- unique(raw$n_stratum[raw$stratum == lab_ge])
n_tot <- sum(as.integer(c(n_y[1], n_o[1])), na.rm = TRUE)
title <- sprintf(
  paste0(
    "Table S4. Exposome-wide association study of %d environmental toxicants with pan-cancer ",
    "among %s United States adults: Stratified by Age."
  ),
  n_tox,
  format(as.integer(n_tot), big.mark = ",", trim = TRUE)
)
footnotes <- c(
  sprintf(
    "Adjusted logistic models within age strata (<%d / \u2265%d years); covariates match Table 2 Model 2 (sex, race/ethnicity, poverty income ratio, alcohol use, eGFR).",
    age_cut, age_cut
  ),
  "OR per IQR for log (ln) exposures; 2 categories = detectable vs undetectable.",
  "q-values: Benjamini–Hochberg FDR within each age stratum.",
  sprintf("Analytic n: %s = %s; %s = %s.",
          lab_young, format(as.integer(n_y[1]), big.mark = ",", trim = TRUE),
          lab_old, format(as.integer(n_o[1]), big.mark = ",", trim = TRUE))
)

body_csv <- body
colnames(body_csv) <- c(
  "Exposure family by toxicant exposure", "Processing",
  paste(lab_young, "OR (95% CI)"), paste(lab_young, "p"), paste(lab_young, "q"),
  paste(lab_old, "OR (95% CI)"), paste(lab_old, "p"), paste(lab_old, "q")
)
body_csv[[1]][is_level] <- paste0("    ", body_csv[[1]][is_level])
utils::write.csv(body_csv, file.path(src_tab, "Table S4. ExWAS stratified by age.csv"), row.names = FALSE)

out_xlsx <- file.path(sum_tab, "Table S4. ExWAS stratified by age.xlsx")
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)
nc <- ncol(body)

if (!requireNamespace("openxlsx", quietly = TRUE)) stop("需要 openxlsx")
wb <- openxlsx::createWorkbook()
sh <- "Table S4"
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
  fontSize = 11, fontName = "Times New Roman",
  halign = "left", textDecoration = "bold"
)
last_c <- openxlsx::createStyle(
  fontSize = 11, fontName = "Times New Roman",
  halign = "center", border = "bottom", borderStyle = "thick"
)
last_l <- openxlsx::createStyle(
  fontSize = 11, fontName = "Times New Roman",
  halign = "left", border = "bottom", borderStyle = "thick"
)
foot_style <- openxlsx::createStyle(
  fontSize = 11, fontName = "Times New Roman",
  halign = "left", wrapText = TRUE, border = "top", borderStyle = "thin"
)

openxlsx::writeData(wb, sh, title, startRow = 1, startCol = 1, colNames = FALSE)
openxlsx::mergeCells(wb, sh, rows = 1, cols = 1:nc)
openxlsx::addStyle(wb, sh, title_style, rows = 1, cols = 1:nc, gridExpand = TRUE)

# h1: Exposure | Processing | Age (years)
# h2:           |            | < 60 | ≥ 60
# h3:           |            | OR p q | OR p q
openxlsx::writeData(wb, sh, data.frame(
  t(c("Exposure family by toxicant exposure", "Processing", "Age (years)", "", "", "", "", "")),
  stringsAsFactors = FALSE
), startRow = 2, colNames = FALSE)
openxlsx::writeData(wb, sh, data.frame(
  t(c("", "", lab_young, "", "", lab_old, "", "")),
  stringsAsFactors = FALSE
), startRow = 3, colNames = FALSE)
openxlsx::writeData(wb, sh, data.frame(
  t(c("", "", "OR (95 %CI)", "p-values", "q-values",
      "OR (95 %CI)", "p-values", "q-values")),
  stringsAsFactors = FALSE
), startRow = 4, colNames = FALSE)

openxlsx::mergeCells(wb, sh, rows = 2:4, cols = 1)
openxlsx::mergeCells(wb, sh, rows = 2:4, cols = 2)
openxlsx::mergeCells(wb, sh, rows = 2, cols = 3:8)
openxlsx::mergeCells(wb, sh, rows = 3, cols = 3:5)
openxlsx::mergeCells(wb, sh, rows = 3, cols = 6:8)

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
exwas_log("毒物=", n_tox, " Age <", age_cut, " / \u2265", age_cut, " 宽表三层表头")
exwas_log("DONE")
