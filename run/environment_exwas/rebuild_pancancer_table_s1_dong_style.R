#!/usr/bin/env Rscript
# Table S1 → 对齐 Dong 补充材料 Supplementary Table 1 列结构：
# Family | Exposure | Unit | LOD | Under LOD (%) | Missing (%) | Outlier(%) |
# Median (IQR) | X ± SD | Matrix | Label | Process
#
# Unit/LOD/Matrix/Label 优先挂 Dong S1 元数据；统计量按本队列原始浓度计算。
#
#   Rscript run/environment_exwas/rebuild_pancancer_table_s1_dong_style.R
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

.norm_name <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[^a-z0-9]+", "", x)
  x
}
# o-Anisidine ↔ Anisidine o；2,6-Dimethylaniline ↔ Dimethylaniline 2 6
.name_aliases <- function(x) {
  x0 <- as.character(x)
  out <- unique(c(x0, gsub("_", " ", x0, fixed = TRUE)))
  n <- .norm_name(x0)
  # 末尾 o/p/m/数字 挪到前面
  m <- regexec("^([a-z]+)([opm])$", n)
  if (m[[1]][1] >= 0) {
    g <- regmatches(n, m)[[1]]
    out <- c(out, paste0(g[3], "-", g[2]), paste0(g[3], g[2]))
  }
  m2 <- regexec("^([a-z]+)([0-9]+)$", n)
  if (m2[[1]][1] >= 0) {
    g <- regmatches(n, m2)[[1]]
    out <- c(out, paste0(g[3], g[2]), paste0(g[3], "-", g[2]))
  }
  # 数字夹在中间 dimethylaniline26 ↔ 26dimethylaniline
  m3 <- regexec("^([a-z]+)([0-9]+)([a-z]+)$", n)
  if (m3[[1]][1] >= 0) {
    g <- regmatches(n, m3)[[1]]
    out <- c(out, paste0(g[3], g[2], g[4]), paste0(g[2], ",", g[3], "-", g[4]))
  }
  unique(out)
}

built <- exwas_tox_build_cancer_table("pancancer", opt$data_dir, min_age = opt$min_age)
# S1 描述用原始浓度（尿肌酐校正前）；纳排与主分析一致
d0 <- built$data
d0 <- d0[is.finite(exwas_to_num(d0$URXUCR)) & exwas_to_num(d0$URXUCR) > 0, , drop = FALSE]
d0 <- d0[is.finite(exwas_to_num(d0$WTSA2YR)) & exwas_to_num(d0$WTSA2YR) > 0, , drop = FALSE]
tox <- intersect(built$tox_cols, names(d0))
exwas_log("S1 cohort N=", nrow(d0), " analytes=", length(tox))

# 筛查决策（与主分析同一套：校正后再判 LOD）
d1 <- exwas_tox_creatinine_adjust(d0, tox, creat_col = "URXUCR")$data
scr <- exwas_tox_screen_transform(d1, tox)
notes <- scr$notes
dec_map <- stats::setNames(notes$decision, notes$exposure)

# 家族 / 展示名
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

# Dong S1 元数据（Unit/LOD/Matrix/Label）
meta_path <- file.path(opt$data_dir, "dong_supp_table1_meta.csv")
meta <- if (file.exists(meta_path)) {
  utils::read.csv(meta_path, stringsAsFactors = FALSE, check.names = FALSE)
} else {
  data.frame()
}
# 多键匹配：Exposure / Label / 规范化
meta_keys <- character(0)
meta_idx <- integer(0)
if (nrow(meta)) {
  for (i in seq_len(nrow(meta))) {
    for (k in unique(c(meta$Exposure[i], meta$Label[i]))) {
      nk <- .norm_name(k)
      if (!nzchar(nk)) next
      if (!nk %in% meta_keys) {
        meta_keys <- c(meta_keys, nk)
        meta_idx <- c(meta_idx, i)
      }
    }
  }
}
# 给 Dong 名也挂别名键
if (nrow(meta)) {
  for (i in seq_len(nrow(meta))) {
    for (k in .name_aliases(meta$Exposure[i])) {
      nk <- .norm_name(k)
      if (!nzchar(nk) || nk %in% meta_keys) next
      meta_keys <- c(meta_keys, nk)
      meta_idx <- c(meta_idx, i)
    }
  }
}
lookup_meta <- function(disp, raw) {
  cands <- unique(c(.name_aliases(disp), .name_aliases(raw)))
  for (cand in cands) {
    nk <- .norm_name(cand)
    hit <- match(nk, meta_keys)
    if (is.finite(hit)) return(meta[meta_idx[[hit]], , drop = FALSE])
  }
  nk2 <- .norm_name(disp)
  letters2 <- gsub("[0-9]", "", nk2)
  digits2 <- paste(sort(strsplit(gsub("[^0-9]", "", nk2), "")[[1]]), collapse = "")
  hit2 <- which(vapply(meta_keys, function(k) {
    identical(gsub("[0-9]", "", k), letters2) &&
      identical(paste(sort(strsplit(gsub("[^0-9]", "", k), "")[[1]]), collapse = ""), digits2)
  }, logical(1)))
  if (length(hit2)) return(meta[meta_idx[[hit2[1]]], , drop = FALSE])
  NULL
}

.fmt_pct <- function(x) {
  if (!is.finite(x)) return("")
  sprintf("%.3f", 100 * x)
}
.fmt_med_iqr <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) < 3L) return("")
  # Dong: Median (IQR 宽度) — 如 42.300 (20.800) = median (Q3-Q1)
  med <- stats::median(x)
  iqr <- stats::IQR(x)
  sprintf("%.3f (%.3f)", med, iqr)
}
.fmt_mean_sd <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) < 2L) return("")
  sprintf("%.1f \u00b1 %.1f", mean(x), stats::sd(x))
}
.outlier_frac <- function(x) {
  # Tukey 1.5×IQR（Dong 报告 Outlier%）
  x <- x[is.finite(x)]
  if (length(x) < 4L) return(NA_real_)
  q <- stats::quantile(x, c(0.25, 0.75), names = FALSE)
  iqr <- q[2] - q[1]
  if (!is.finite(iqr) || iqr == 0) return(0)
  lo <- q[1] - 1.5 * iqr
  hi <- q[2] + 1.5 * iqr
  mean(x < lo | x > hi)
}
.proc_lab <- function(dec) {
  if (identical(dec, "log")) "log (ln)"
  else if (identical(dec, "binary")) "2 categories"
  else if (identical(dec, "drop")) "removed"
  else as.character(dec)
}

# 周期感知缺失率（与筛查 notes 一致）
miss_map <- stats::setNames(notes$missing_rate, notes$exposure)
under0_map <- stats::setNames(notes$under_lod_rate, notes$exposure)

rows <- lapply(tox, function(raw) {
  x <- exwas_to_num(d0[[raw]])
  n_meas <- sum(is.finite(x))
  # Missing：优先用「有测定周期」分母（notes）
  miss <- unname(miss_map[[raw]])
  if (is.null(miss) || !is.finite(miss)) {
    miss <- 1 - n_meas / max(nrow(d0), 1L)
  }
  disp <- disp_of(raw)
  mrow <- lookup_meta(disp, raw)
  lod <- if (!is.null(mrow)) suppressWarnings(as.numeric(mrow$LOD[1])) else NA_real_
  unit <- if (!is.null(mrow)) as.character(mrow$Unit[1]) else ""
  matrix <- if (!is.null(mrow) && nzchar(as.character(mrow$Matrix[1]))) {
    as.character(mrow$Matrix[1])
  } else if (exwas_tox_is_urine(raw)) {
    "Urine"
  } else if (exwas_tox_is_blood(raw)) {
    "Serum"
  } else ""
  label <- if (!is.null(mrow) && nzchar(as.character(mrow$Label[1]))) {
    as.character(mrow$Label[1])
  } else disp
  # Under LOD：有文献 LOD 用原始浓度 x < LOD；否则用筛查 ≤0 比例
  if (is.finite(lod) && n_meas > 0L) {
    under <- mean(x[is.finite(x)] < lod)
  } else {
    under <- unname(under0_map[[raw]])
    if (is.null(under) || !is.finite(under)) {
      under <- if (n_meas > 0L) mean(x[is.finite(x)] <= 0) else NA_real_
    }
  }
  outl <- .outlier_frac(x)
  dec <- unname(dec_map[[raw]])
  if (is.null(dec) || is.na(dec)) dec <- "drop"
  data.frame(
    Family = fam_of(raw),
    Exposure = if (!is.null(mrow) && nzchar(as.character(mrow$Exposure[1]))) {
      as.character(mrow$Exposure[1])
    } else disp,
    Unit = unit,
    LOD = if (is.finite(lod)) as.character(lod) else "",
    `Under LOD (%)` = .fmt_pct(under),
    `Missing (%)` = .fmt_pct(miss),
    `Outlier(%)` = .fmt_pct(outl),
    `Median (IQR)` = .fmt_med_iqr(x),
    `X ± SD` = .fmt_mean_sd(x),
    Matrix = matrix,
    Label = label,
    Process = .proc_lab(dec),
    .raw = raw,
    .ord = match(fam_of(raw), unique(c(fam_df$Family, fam_of(raw)))),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
})
tab <- do.call(rbind, rows)
tab <- tab[order(tab$.ord, tab$Exposure), , drop = FALSE]

# Dong：家族只在首行写一次
fam_show <- tab$Family
prev <- ""
for (i in seq_len(nrow(tab))) {
  if (identical(fam_show[i], prev)) fam_show[i] <- "" else prev <- fam_show[i]
}
body <- tab[, c(
  "Family", "Exposure", "Unit", "LOD", "Under LOD (%)", "Missing (%)",
  "Outlier(%)", "Median (IQR)", "X ± SD", "Matrix", "Label", "Process"
), drop = FALSE]
body$Family <- fam_show

n_all <- nrow(body)
n_kept <- sum(body$Process %in% c("log (ln)", "2 categories"))
title <- sprintf(
  "Table S1. Characteristics of %d environmental contaminants or metabolites of environmental contaminants.",
  n_all
)
footnotes <- c(
  "Under LOD (%): measured values below the NHANES LOD (LOD values matched from Dong et al. Supplementary Table 1 when available; otherwise \u22640 as proxy).",
  "Missing (%): missing among participants in NHANES cycles where the analyte was assayed (cycle-aware denominator).",
  "Outlier (%): Tukey fences (outside Q1\u22121.5\u00d7IQR or Q3+1.5\u00d7IQR) among measured values.",
  "Median (IQR) = median (IQR width); X \u00b1 SD on the original concentration scale before urinary creatinine adjustment.",
  "Process reflects the transformation used in the primary ExWAS (log / 2 categories / removed), based on missing and <LOD screening rules.",
  sprintf("Retained for primary ExWAS: %d of %d analytes in the screened panel.", n_kept, n_all)
)

utils::write.csv(body, file.path(src_tab, "Table S1. Toxicant analyte characteristics and LOD screen.csv"),
                 row.names = FALSE)

out_xlsx <- file.path(sum_tab, "Table S1. Toxicant analyte characteristics and LOD screen.xlsx")
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)

# 家族行加粗 Family；毒物行左对齐
sci_xlsx_single_header_booktabs(
  filepath = out_xlsx,
  title = title,
  df_body = body,
  sheet = "Table S1",
  footnotes = footnotes
)

if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)

if (requireNamespace("openxlsx", quietly = TRUE)) {
  wb <- openxlsx::loadWorkbook(out_xlsx)
  sh <- openxlsx::sheets(wb)[[1]]
  fam_style <- openxlsx::createStyle(
    fontSize = 11, fontName = "Times New Roman",
    halign = "left", textDecoration = "bold"
  )
  # title row1, header row2, body from 3
  for (i in seq_len(nrow(body))) {
    if (nzchar(trimws(body$Family[i]))) {
      openxlsx::addStyle(wb, sh, style = fam_style, rows = 2L + i, cols = 1L, gridExpand = FALSE)
    }
  }
  openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)
  if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)
}

exwas_log("写完 ", out_xlsx)
exwas_log("analytes=", n_all, " kept=", n_kept, " removed=", n_all - n_kept)
exwas_log("DONE")
