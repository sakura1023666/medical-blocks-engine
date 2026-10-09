#!/usr/bin/env Rscript
# Post-fix after reorganize_aki_wpr_2primary_4sens.R:
#   - Fig3 from Dynpred D2 (2-class primary)
#   - drop Missing-value S1 + duplicate Weibull Spec as S9
#   - sync mimic/eicu Tables to root AP roles
#   - refresh four-dir formats + README

suppressPackageStartupMessages({
  library(cli)
})
`%||%` <- function(a, b) if (!is.null(a)) a else b

.root <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.root)
source("R/utils.R", local = FALSE)
source("R/dual_db_combine_figures.R", local = FALSE)
source("R/pub_figure_export.R", local = FALSE)

block_root <- if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result" else "G:/02block_result"
proj <- file.path(block_root, "44_AKI_SPESIS_CKD/Prognosis_Trajectory_38882552/tr")
index_root <- file.path(proj, "by_index/【success】WPR")
fig_root <- file.path(index_root, "Figures")
tab_root <- file.path(index_root, "Tables")
cfg_path <- file.path(proj, "config.R")
if (file.exists(cfg_path)) source(cfg_path, local = FALSE)

cli_h1("Fixup 【success】WPR publication package")

.arch_db <- function(db, fp) {
  if (!file.exists(fp)) return(invisible(FALSE))
  ad <- file.path(index_root, db, "Tables", "_archive")
  dir.create(ad, showWarnings = FALSE, recursive = TRUE)
  file.copy(fp, file.path(ad, basename(fp)), overwrite = TRUE)
  unlink(fp)
  invisible(TRUE)
}

# ── 1) Fix per-db figures: Fig3 + drop conflicts ────────────────────────────
for (db in c("mimic", "eicu")) {
  db_lab <- if (identical(db, "mimic")) "MIMIC" else "eICU"
  fdir <- file.path(index_root, db, "Figures")
  raw <- file.path(fdir, "_raw")

  # Fig3 from 2-class dynpred
  src3 <- file.path(raw, "Figure Dynpred WPR D2.pdf")
  if (!file.exists(src3)) src3 <- file.path(raw, "Figure Dynpred WPR D4.pdf")
  out3 <- file.path(fdir, sprintf("Figure 3-%s. Dynamic prediction of WPR trajectory.pdf", db_lab))
  if (file.exists(src3)) {
    file.copy(src3, out3, overwrite = TRUE)
    cli_alert_success("{db_lab}: Figure 3 from {basename(src3)}")
  } else {
    cli_alert_danger("{db_lab}: Dynpred raw missing")
  }

  # drop Missing value overview (not in AP WPR role set for this study)
  unlink(list.files(fdir, pattern = "Missing value overview", full.names = TRUE))

  # drop duplicate Weibull Specificity wrongly kept as S9
  unlink(list.files(fdir, pattern = "Figure S9-.*Weibull.*Specificity", full.names = TRUE))

  # ensure S8 Specificity exists from raw
  src_s8 <- file.path(raw, "Figure Weibull Dynamic Compare WPR Specificity.pdf")
  out_s8 <- file.path(fdir, sprintf("Figure S8-%s. Weibull dynamic model comparison Specificity.pdf", db_lab))
  if (file.exists(src_s8) && !file.exists(out_s8)) {
    file.copy(src_s8, out_s8, overwrite = TRUE)
  }

  cli_alert_info("{db} figures: {paste(basename(list.files(fdir, pattern='\\\\.pdf$')), collapse='; ')}")
}

# compose / refresh Fig3 + S8 at root
.compose <- function(stem, layout = "stack", mimic_only = FALSE) {
  a <- file.path(index_root, "mimic", "Figures", sub("^Figure ([0-9S]+)\\. ", "Figure \\1-MIMIC. ", stem))
  b <- file.path(index_root, "eicu", "Figures", sub("^Figure ([0-9S]+)\\. ", "Figure \\1-eICU. ", stem))
  out <- file.path(fig_root, stem)
  if (mimic_only) {
    if (file.exists(a)) file.copy(a, out, overwrite = TRUE)
    return(invisible(file.exists(out)))
  }
  if (!file.exists(a) || !file.exists(b)) {
    cli_alert_warning("缺配对 {stem}")
    return(invisible(FALSE))
  }
  ok <- tryCatch({
    .dual_db_compose_pair_pdf(a, b, out, layout = layout,
                              label_a = "A. MIMIC", label_b = "B. eICU",
                              dpi = 220L, label_cex = 1.2)
    TRUE
  }, error = function(e) { cli_alert_danger("{stem}: {e$message}"); FALSE })
  if (isTRUE(ok)) cli_alert_success("拼好 {stem}")
  invisible(isTRUE(ok))
}

# clear flat pdfs that will be re-exported into four dirs
unlink(file.path(fig_root, "Figure 3. Dynamic prediction of WPR trajectory.pdf"))
.compose("Figure 3. Dynamic prediction of WPR trajectory.pdf", "stack")
.compose("Figure S8. Weibull dynamic model comparison Specificity.pdf", "side")

# remove stale image_information that doesn't match current pdf stems
imd <- file.path(fig_root, "image_information")
if (dir.exists(imd)) {
  pdf_stems <- tools::file_path_sans_ext(list.files(file.path(fig_root, "pdf"), pattern = "\\.pdf$"))
  # also match flat root before ensure_formats
  flat <- tools::file_path_sans_ext(list.files(fig_root, pattern = "\\.pdf$"))
  keep_stems <- unique(c(pdf_stems, flat))
  for (md in list.files(imd, pattern = "\\.md$", full.names = TRUE)) {
    st <- tools::file_path_sans_ext(basename(md))
    if (identical(st, "README")) next
    if (!st %in% keep_stems) {
      unlink(md)
      cli_alert_info("removed stale md: {basename(md)}")
    }
  }
}

# ── 2) Sync per-db Tables to root AP roles ──────────────────────────────────
wanted_re <- c(
  "^Table 1-", "^Table 2-", "^Table 3-",
  "^Table S1-.*after multiple imputation",
  "^Table S2-.*Normality",
  "^Table S3-.*Univariate",
  "^Table S4-.*univariate screen",
  "^Table S5-.*by trajectory class",
  "^Table S6-.*Posterior",
  "^Table S7-.*AvePP|^Table S7-.*OCC|^Table S7-.*2-class and 4-class",
  "^Table S8-.*mortality",
  "^Table S9-.*Rescaled"
)

for (db in c("mimic", "eicu")) {
  db_lab <- if (identical(db, "mimic")) "MIMIC" else "eICU"
  tdir <- file.path(index_root, db, "Tables")
  arch <- file.path(tdir, "_archive")
  dir.create(arch, showWarnings = FALSE, recursive = TRUE)

  # promote S7 by-class → S5 if S5 missing
  s7_bc <- file.path(tdir, sprintf("Table S7-%s. Baseline characteristics by trajectory class (WPR).xlsx", db_lab))
  s5_bc <- file.path(tdir, sprintf("Table S5-%s. Baseline characteristics by trajectory class (WPR).xlsx", db_lab))
  root_s5 <- file.path(tab_root, basename(s5_bc))
  if (!file.exists(s5_bc)) {
    if (file.exists(root_s5)) {
      file.copy(root_s5, s5_bc, overwrite = TRUE)
    } else if (file.exists(s7_bc)) {
      file.copy(s7_bc, s5_bc, overwrite = TRUE)
      if (exists("trajectory_sync_xlsx_a1_from_filename", mode = "function"))
        try(trajectory_sync_xlsx_a1_from_filename(s5_bc), silent = TRUE)
    }
  }

  # copy sensitivity / rebuilt tables from root if missing in db
  for (bn in c(
    sprintf("Table 2-%s. Metrics for determining the optimal number of classes.xlsx", db_lab),
    sprintf("Table 3-%s. Time-dependent HR for trajectory classes.xlsx", db_lab),
    sprintf("Table S5-%s. Baseline characteristics by trajectory class (WPR).xlsx", db_lab),
    sprintf("Table S6-%s. Posterior classification table.xlsx", db_lab),
    sprintf("Table S7-%s. Average posterior probability and OCC for 2-class and 4-class WPR models.xlsx", db_lab),
    sprintf("Table S8-%s. Class-specific 28-day mortality and approximate likelihood-ratio comparisons.xlsx", db_lab),
    sprintf("Table S9-%s. Rescaled univariable HRs for continuous baseline WPR.xlsx", db_lab)
  )) {
    src <- file.path(tab_root, bn)
    dst <- file.path(tdir, bn)
    if (file.exists(src)) file.copy(src, dst, overwrite = TRUE)
  }

  # archive non-wanted
  for (fp in list.files(tdir, pattern = "\\.xlsx$", full.names = TRUE)) {
    bn <- basename(fp)
    ok <- any(vapply(wanted_re, function(p) grepl(p, bn, ignore.case = TRUE), logical(1)))
    if (!ok) .arch_db(db, fp)
  }
  cli_alert_success("{db_lab} Tables synced: {paste(basename(list.files(tdir, pattern='\\\\.xlsx$')), collapse='; ')}")
}

# ── 3) Four-dir + README ────────────────────────────────────────────────────
# move any flat root pdfs into workflow then ensure formats
pub_figure_ensure_formats(fig_root, config = if (exists("config")) config else list())
st <- pub_figure_formats_status(fig_root)
cli_alert_info("四目录: pdf={length(st$pdf)} png={length(st$png)} tiff={length(st$tiff)} ok={isTRUE(st$ok)}")

readme <- c(
  "# Tables / Figures（WPR）— 主文 2 类 · 敏感性 4 类",
  "",
  "角色对齐 AP `41_AP/.../by_index/WPR`。",
  "",
  "## 主分析（2 类）",
  "| 编号 | 内容 |",
  "|---|---|",
  "| Figure 1 | 纳排流程图 |",
  "| Figure 2 | 2 类 WPR 轨迹 |",
  "| Figure 3–4 | 动态预测 / 个体预测 |",
  "| Figure S1 | KM by class |",
  "| Figure S2 | 分段 Cox 切点（仅 MIMIC） |",
  "| Figure S3 | 亚组 |",
  "| Figure S4–S8 | Weibull 比较 |",
  "| Table 1–3 | 基线 / 选类指标 / 分段 HR |",
  "| Table S1–S4 | 插补 / 正态 / 单因素 / VIF screen |",
  "| Table S5 | 按轨迹类基线（2 类） |",
  "| Table S6 | 后验分类（2 类） |",
  "",
  "## 敏感性（4 类）",
  "| 编号 | 内容 |",
  "|---|---|",
  "| Table S7 | 2 类(主)+4 类(敏) AvePP/OCC |",
  "| Table S8 | 类间死亡 + 近似 LRT |",
  "| Table S9 | 连续 WPR HR 换算 |",
  "| Figure S9 | 4 类轨迹（敏感性） |",
  "| Figure S10 | 28 天死亡率柱图（2 vs 4） |",
  "",
  "## 选类依据",
  "主文 2 类：最小类占比 / Entropy / 双库表型一致。",
  "4 类：信息准则更优，但最小类过小且外验形态不完全同构，仅敏感性。",
  "",
  "旧目录 `WPR(class=4)` 仅作探索；发表终稿以本目录为准。",
  "",
  sprintf("整理时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
)
writeLines(readme, file.path(tab_root, "README.md"), useBytes = TRUE)
writeLines(readme, file.path(index_root, "README.md"), useBytes = TRUE)
dir.create(file.path(fig_root, "image_information"), showWarnings = FALSE, recursive = TRUE)
writeLines(readme, file.path(fig_root, "image_information", "README.md"), useBytes = TRUE)

cli_alert_success("Fixup done")
cli_alert_info("Figures/pdf: {paste(list.files(file.path(fig_root,'pdf')), collapse='; ')}")
cli_alert_info("Tables: {paste(basename(list.files(tab_root, pattern='\\\\.xlsx$')), collapse='; ')}")
