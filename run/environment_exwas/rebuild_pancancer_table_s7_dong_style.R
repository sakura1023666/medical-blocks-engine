#!/usr/bin/env Rscript
# Table S7 → 对齐 Dong Supplementary Table 7 列结构：
# Exposure family | Exposure | Processing | OR (95% CI) | p-values | q-values
# 本课题内容仍为调查加权 ExWAS（替代原文「无插补」敏感性），脚注写明。
#
#   Rscript run/environment_exwas/rebuild_pancancer_table_s7_dong_style.R
#
ROOT <- "/mnt/e/01block/01Block-new-Final"
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
source(file.path(ROOT, "R/utils.R"))
if (file.exists(file.path(ROOT, "R/pub_xlsx_surgical.R"))) {
  source(file.path(ROOT, "R/pub_xlsx_surgical.R"))
}

src_csv <- file.path(
  BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Tables",
  "Table S7. ExWAS survey-weighted.csv"
)
sum_tab <- file.path(BASE, "summary_results", "Tables")
src_tab <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Tables")
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)
if (!file.exists(src_csv)) stop("缺少 ", src_csv, call. = FALSE)

raw <- utils::read.csv(src_csv, stringsAsFactors = FALSE, check.names = FALSE)
fam_df <- utils::read.csv(
  file.path(BASE, "data/toxicant_family_map.csv"),
  stringsAsFactors = FALSE
)
lab_map <- stats::setNames(as.character(fam_df$Exposure), as.character(fam_df$Labels))

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
.proc_of <- function(x, transform = NULL) {
  x <- as.character(x)
  if (!is.null(transform) && nzchar(as.character(transform)[1])) {
    tr <- tolower(as.character(transform)[1])
    if (grepl("bin|categor", tr)) return("2 categories")
    if (grepl("log|ln", tr)) return("log (ln)")
  }
  if (endsWith(x, "_bin")) return("2 categories")
  if (endsWith(x, "_ln")) return("log (ln)")
  ""
}

# 展平行
expo_col <- if ("exposure" %in% names(raw)) "exposure" else names(raw)[1]
name_src <- if ("exposure_name" %in% names(raw)) raw$exposure_name else raw[[expo_col]]
fam <- if ("family" %in% names(raw)) as.character(raw$family) else "Other"
fam[is.na(fam) | !nzchar(fam)] <- "Other"
proc <- character(nrow(raw))
for (i in seq_len(nrow(raw))) {
  tr <- if ("transform" %in% names(raw)) raw$transform[i] else NULL
  proc[i] <- .proc_of(raw[[expo_col]][i], tr)
}
flat <- data.frame(
  family = fam,
  exposure_disp = vapply(name_src, .disp_tox, character(1)),
  Processing = proc,
  OR_CI = mapply(.fmt_or, raw$OR, raw$lo, raw$hi),
  p = vapply(raw$p, .fmt_p, character(1)),
  q = vapply(raw$q, .fmt_p, character(1)),
  p_num = as.numeric(raw$p),
  stringsAsFactors = FALSE
)
# 家族顺序：map 出现序；族内按 p 升序
fam_levels <- unique(c(as.character(fam_df$Family), flat$family))
flat$family <- factor(flat$family, levels = fam_levels)
flat <- flat[order(flat$family, flat$p_num, flat$exposure_disp), , drop = FALSE]

# Dong：家族标题行 + 缩进暴露行（Exposure family 列在暴露行留空）
out <- list()
is_level <- logical(0)
for (f in levels(flat$family)) {
  sub <- flat[as.character(flat$family) == f & !is.na(flat$family), , drop = FALSE]
  if (!nrow(sub)) next
  out[[length(out) + 1L]] <- data.frame(
    `Exposure family` = as.character(f),
    Exposure = "",
    Processing = "",
    `OR (95% CI)` = "",
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
      Processing = sub$Processing[i],
      `OR (95% CI)` = sub$OR_CI[i],
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
n_sig_q <- sum(is.finite(as.numeric(raw$q)) & as.numeric(raw$q) < 0.05, na.rm = TRUE)
n_sig_p <- sum(is.finite(as.numeric(raw$p)) & as.numeric(raw$p) < 0.05, na.rm = TRUE)

title <- paste0(
  "Table S7. Sensitivity analysis: survey-weighted Exposome-wide association study (ExWAS) ",
  "of environmental toxicants and pan-cancer."
)
footnotes <- c(
  "Columns: Exposure family, Exposure, Processing, OR (95% CI), p, and q.",
  "Unlike Dong (complete-case without imputation), this sensitivity uses survey weights (WTSA2YR) with complex design; covariates multiply imputed (m=5) and pooled by Rubin's rules.",
  "Processing: log (ln) = natural-log continuous exposure (OR per IQR); 2 categories = detectable vs undetectable.",
  sprintf(
    "Exposures = %d; FDR q<0.05 = %d; nominal P<0.05 = %d.",
    n_exp, n_sig_q, n_sig_p
  )
)

out_xlsx <- file.path(sum_tab, "Table S7. ExWAS survey-weighted.xlsx")
# 兼容旧名
old_xlsx <- file.path(sum_tab, "Table S7. ExWAS without imputation.xlsx")
if (file.exists(old_xlsx)) file.remove(old_xlsx)

utils::write.csv(
  body,
  file.path(src_tab, "Table S7. ExWAS survey-weighted Dong layout.csv"),
  row.names = FALSE
)

sci_xlsx_single_header_booktabs(
  filepath = out_xlsx,
  title = title,
  df_body = body,
  sheet = "Table S7",
  footnotes = footnotes
)
if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)

# 家族行加粗；暴露行 Exposure 缩进
if (requireNamespace("openxlsx", quietly = TRUE)) {
  wb <- openxlsx::loadWorkbook(out_xlsx)
  sh <- openxlsx::sheets(wb)[[1]]
  openxlsx::setColWidths(wb, sh, cols = 1:6, widths = c(28, 28, 14, 22, 12, 12))
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
  # title=1, header=2, body from 3
  for (i in seq_along(is_level)) {
    r <- 2L + i
    if (!is_level[[i]]) {
      openxlsx::addStyle(wb, sh, fam_style, rows = r, cols = 1, stack = TRUE)
    } else {
      openxlsx::addStyle(wb, sh, level_style, rows = r, cols = 2, stack = TRUE)
      openxlsx::addStyle(wb, sh, center, rows = r, cols = 3:6, gridExpand = TRUE, stack = TRUE)
    }
  }
  openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)
  if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)
}

message("[s7] wrote ", out_xlsx, " rows=", nrow(body), " exposures=", n_exp)
message("[s7] DONE")
