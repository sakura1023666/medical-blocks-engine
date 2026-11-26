#!/usr/bin/env Rscript
# Table 2 → 对齐 Dong 主文：全毒物 × Processing × Median(IQR) × Model1 + Model2
# Model1 = 未调整；Model2 = 全协变量（m=5 Rubin，复用已有筛查表或重跑）
#
#   Rscript run/environment_exwas/rebuild_pancancer_table2_dong_style.R
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
source(file.path(repo, "run/environment_exwas/pancancer_model2_covars.R"))
if (file.exists(file.path(repo, "R/pub_xlsx_surgical.R"))) {
  source(file.path(repo, "R/pub_xlsx_surgical.R"))
}

root <- opt$root
src_tab <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Tables")
sum_tab <- file.path(root, "summary_results", "Tables")
screen_csv <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub", # fallback paths
                        "Tables", "Table 2. Exwas toxicant associations.csv")
# 实际已有 Model2 表
m2_candidates <- c(
  file.path(root, "Output_pancancer_paperflow_age20_full_noSmoke_UCR_WTSA", "Table_2_ExWAS_toxicant_screen.csv"),
  file.path(src_tab, "Table 2. ExWAS toxicant associations.csv"),
  file.path(root, "Output_pancancer_paperflow_age20_full_noSmoke", "Table_2_ExWAS_toxicant_screen.csv")
)
exwas_log <- function(...) message("[exwas] ", paste0(..., collapse = ""))

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
# Model2 = DAG→UV→VIF→stepwise 终末集（与 ERS/FigS1 同一套；禁止再用全量 Age 池）
covars_m2 <- intersect(pancancer_model2_covars_from_path(root), names(df))
if (!length(covars_m2)) covars_m2 <- intersect(pancancer_model2_final_default, names(df))
covars_full <- covars_m2
df <- exwas_aligned_as_model_frame(df, covars_full)
df$DN <- as.integer(exwas_to_num(df$DN) == 1L)
exposures <- scr$keep
exwas_log("N=", nrow(df), " exposures=", length(exposures),
          " Model2=", paste(covars_m2, collapse = "+"))

# 展示名 / 家族
fam_path <- file.path(opt$data_dir, "toxicant_family_map.csv")
fam_df <- utils::read.csv(fam_path, stringsAsFactors = FALSE)
lab_map <- stats::setNames(fam_df$Exposure, fam_df$Labels)
fam_map <- stats::setNames(fam_df$Family, fam_df$Labels)
disp_of <- function(raw) {
  x <- unname(lab_map[raw])
  x <- ifelse(is.na(x) | !nzchar(x), raw, x)
  if (exists("pipeline_display_label", mode = "function")) {
    x <- vapply(as.character(x), pipeline_display_label, character(1), USE.NAMES = FALSE)
  } else {
    x <- gsub("_", " ", as.character(x), fixed = TRUE)
  }
  x
}
fam_of <- function(raw) {
  x <- unname(fam_map[raw])
  ifelse(is.na(x) | !nzchar(x), "Other", x)
}

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

# ---------- Model 1：未调整（完整病例，无需 mice）----------
exwas_log("Model1 unadjusted ExWAS …")
m1 <- exwas_run_unweighted(df, "DN", exposures, covars = character(0))
m1$q <- exwas_fdr(m1$p)
m1$raw <- sub("_(ln|bin)$", "", m1$exposure)

# ---------- Model 2：必须按终末 5 协变量重跑 mice（旧 screen 含 Age，禁止复用）----------
exwas_log("Model2 mice 重跑 covars=", paste(covars_m2, collapse = "+"), " …")
m2 <- exwas_run_unweighted_mice(
  df, "DN", exposures, covars_m2, m = 5L, maxit = 5L, seed = 123456L
)
# 落盘新 screen，供下游复用
m2_out <- file.path(src_tab, "Table 2. ExWAS toxicant associations_model2_numeric.csv")
utils::write.csv(m2, m2_out, row.names = FALSE)
utils::write.csv(m2, file.path(src_tab, "Table 2. ExWAS toxicant associations_model2_numeric.bak.csv"), row.names = FALSE)
hits <- m2[is.finite(m2$q) & m2$q < 0.05, , drop = FALSE]
utils::write.csv(hits, file.path(src_tab, "Table 2b. ExWAS FDR hits.csv"), row.names = FALSE)
exwas_log("Model2 FDR hits=", nrow(hits))
if (!"exposure" %in% names(m2) && "Exposure" %in% names(m2)) m2$exposure <- m2$Exposure
m2$raw <- sub("_(ln|bin)$", "", m2$exposure)
if (!"q" %in% names(m2) && "q_value" %in% names(m2)) m2$q <- m2$q_value
if (!"q" %in% names(m2)) m2$q <- exwas_fdr(m2$p)

# ---------- Median (IQR) on model scale ----------
med_map <- setNames(rep(NA_character_, length(exposures)), exposures)
for (x in exposures) {
  if (!x %in% names(df)) next
  if (endsWith(x, "_bin")) {
    med_map[[x]] <- "NA"
  } else {
    med_map[[x]] <- .fmt_med_iqr(exwas_to_num(df[[x]]))
  }
}

# ---------- 合并 ----------
keys <- unique(c(m1$exposure, m2$exposure))
keys <- keys[keys %in% exposures]
rows_flat <- lapply(keys, function(x) {
  r1 <- m1[m1$exposure == x, , drop = FALSE]
  r2 <- m2[m2$exposure == x, , drop = FALSE]
  raw <- sub("_(ln|bin)$", "", x)
  proc <- if (endsWith(x, "_bin")) "2 categories" else if (endsWith(x, "_ln")) "log (ln)" else ""
  data.frame(
    exposure = x,
    raw = raw,
    name = disp_of(raw),
    family = fam_of(raw),
    Processing = proc,
    Median_IQR = unname(med_map[[x]] %||% "NA"),
    M1_OR = if (nrow(r1)) .fmt_or(r1$OR[1], r1$lo[1], r1$hi[1]) else "",
    M1_p = if (nrow(r1)) .fmt_p(r1$p[1]) else "",
    M1_q = if (nrow(r1)) .fmt_p(r1$q[1]) else "",
    M2_OR = if (nrow(r2)) .fmt_or(r2$OR[1], r2$lo[1], r2$hi[1]) else "",
    M2_p = if (nrow(r2)) .fmt_p(r2$p[1]) else "",
    M2_q = if (nrow(r2)) .fmt_p(r2$q[1]) else "",
    M2_p_num = if (nrow(r2)) as.numeric(r2$p[1]) else NA_real_,
    stringsAsFactors = FALSE
  )
})
flat <- do.call(rbind, rows_flat)
# 家族内按 Model2 p 升序（与火山图/命中优先一致）；家族顺序按 map 出现序
fam_levels <- unique(c(fam_df$Family, flat$family))
flat$family <- factor(flat$family, levels = fam_levels)
flat <- flat[order(flat$family, flat$M2_p_num, flat$name), , drop = FALSE]

# ---------- Dong 展示：家族标题行 + 缩进毒物行 ----------
# 列顺序固定，xlsx 用双行表头（对齐原文）：
#   h1: Exposure | Processing | Median (IQR) | Model 1×3 | Model 2×3
#   h2: (竖跨)   | (竖跨)     | (竖跨)       | OR / p / q | OR / p / q
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
  "Table 2. Exposome-wide association study of %d environmental toxicants with pan-cancer among %s US adults.",
  length(keys), format(nrow(df), big.mark = ",", trim = TRUE)
)
footnotes <- c(
  "Processing: log (ln) = natural-log continuous exposure (OR per IQR); 2 categories = detectable vs undetectable.",
  "Median (IQR) is on the model scale (ln units for continuous; NA for dichotomized).",
  "Model 1: unadjusted logistic regression (complete cases for each exposure).",
  paste0(
    "Model 2: adjusted for ",
    paste(pancancer_model2_display_labs(covars_m2), collapse = ", "),
    "; covariates multiply imputed (m=5) and pooled by Rubin's rules; BH-FDR q-values."
  ),
  pancancer_model2_footnote(covars_m2),
  "Bold Model 2 q < 0.05 indicates FDR-significant associations."
)

# CSV：扁平可读列名 + 缩进
body_csv <- body
colnames(body_csv) <- c(
  "Exposure family by toxicant exposure", "Processing", "Median (IQR)",
  "Model 1 OR (95% CI)", "Model 1 p", "Model 1 q",
  "Model 2 OR (95% CI)", "Model 2 p", "Model 2 q"
)
body_csv[[1]][is_level] <- paste0("    ", body_csv[[1]][is_level])
utils::write.csv(body_csv, file.path(src_tab, "Table 2. ExWAS toxicant associations.csv"), row.names = FALSE)
utils::write.csv(flat, file.path(src_tab, "Table 2. ExWAS Model1 Model2 flat.csv"), row.names = FALSE)

out_xlsx <- file.path(sum_tab, "Table 2. ExWAS toxicant associations.xlsx")
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)

# Dong 双行表头
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
  sheet = "Table 2",
  footnotes = footnotes,
  col_widths = c(32, 12, 18, 18, 10, 10, 18, 10, 10)
)

if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)

# 缩进 + 显著加粗（双行表头：title=1, h1=2, h2=3, body 从 4 起）
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
  body_start <- 4L # title + 2 header rows
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
exwas_log("表头: Exposure/Processing/Median + Model1×3 + Model2×3")
exwas_log("毒物数=", length(keys), " 展示行=", nrow(body), " (含家族标题)")
exwas_log("DONE")
