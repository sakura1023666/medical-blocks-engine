#!/usr/bin/env Rscript
# 1) 去掉 Figure S1 Missing overview，后面补图顺延
# 2) Table 1 / S1 / S3 按两库变量交集对齐（外科删行，保三线表）
#
#   Rscript run/trajectory_prognosis/fix_ap_wpr_dual_drop_s1_align_tables.R

suppressPackageStartupMessages(library(openxlsx))

`%||%` <- function(a, b) if (is.null(a)) b else a

.engine <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.engine)
source(file.path(.engine, "R/pub_xlsx_surgical.R"), local = FALSE)
source(file.path(.engine, "R/pub_figure_export.R"), local = FALSE)
source(file.path(.engine, "R/trajectory_paper_tables.R"), local = FALSE)

block_root <- {
  x <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(x) && dir.exists(x)) x
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}
index_root <- file.path(
  block_root, "41_AP/Prognosis_Trajectory_38882552_WPR_dual/by_index/WPR"
)
tab_root <- file.path(index_root, "Tables")
fig_root <- file.path(index_root, "Figures")
stopifnot(dir.exists(index_root), dir.exists(tab_root), dir.exists(fig_root))

# 两库 Table 1 都有的变量（去单位后）。S1 / 单因素用同一名单。
keep_vars <- c(
  "Age", "Gender", "Weight", "Height",
  "HR", "RR", "SpO2", "Temperature", "NBPS", "NBPD", "NBPM",
  "RBC", "Hematocrit", "Lymphocytes", "RDW", "ALT", "AST", "LD",
  "Albumin", "Bilirubin Total", "BUN", "Creatinine",
  "Sodium", "Potassium", "AnionGap", "Glucose", "Total Cholesterol",
  "Hypertension", "COPD", "CKD", "Hepatitis", "Pneumonia",
  "survival time 28d", "WPR"
)
sections <- c(
  "Demographics", "Vital Signs", "Laboratory Tests", "Comorbidities", "Exposure"
)
levels <- c(
  "Female", "Male", "No", "Yes", "Missing (%)",
  "Asian", "Black", "Hispanic", "Other", "White",
  "Married", "Single/divorced", "English"
)

.norm <- function(x) {
  x <- trimws(as.character(x %||% ""))
  x[is.na(x)] <- ""
  x <- sub(",.*$", "", x)
  x <- gsub("_", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

.drop_rows_not_in_keep <- function(path, kind = c("table1", "s1", "s3")) {
  kind <- match.arg(kind)
  d <- read.xlsx(path, colNames = FALSE)
  n <- nrow(d)
  c1 <- .norm(d[[1L]])
  c2 <- if (ncol(d) >= 2L) .norm(d[[2L]]) else rep("", n)
  current <- NA_character_
  drop <- logical(n)
  for (i in seq_len(n)) {
    lab <- c1[[i]]
    if (i == 1L || grepl("^Table ", lab, ignore.case = TRUE)) next
    if (lab %in% c("Characteristic", "Variable")) next
    if (grepl("^(Continuous variables|Statistical comparisons)", lab)) next
    if (lab %in% sections) {
      current <- NA_character_
      next
    }
    is_level <- lab %in% levels || (lab == "" && kind == "s3")
    if (kind == "s1" && identical(lab, "Missing (%)")) is_level <- TRUE
    if (!is_level && nzchar(lab)) {
      current <- lab
    }
    if (is.na(current) || !nzchar(current)) next
    if (!current %in% keep_vars) drop[i] <- TRUE
  }
  rows <- which(drop)
  if (!length(rows)) {
    cli::cli_alert_info("{basename(path)} 无需删行")
    return(invisible(integer(0)))
  }
  cli::cli_alert_info(
    "{basename(path)} 删 {length(rows)} 行: {paste(c1[rows][c1[rows] != ''][seq_len(min(8L, sum(c1[rows] != '')))], collapse = ', ')}…"
  )
  pub_xlsx_delete_rows(path, rows, root = .engine)
  invisible(rows)
}

.labels <- function(path) {
  d <- read.xlsx(path, colNames = FALSE)
  .norm(d[[1L]])
}

# ── 1) 删 Fig S1，后面序号 -1 ─────────────────────────────────────────────
renumber <- data.frame(
  old = c(
    "Figure S1. Missing value overview",
    "Figure S2. Kaplan Meier survival by trajectory class",
    "Figure S3. Piecewise Cox cut point search",
    "Figure S4. Subgroup analysis by trajectory class",
    "Figure S5. Weibull dynamic model comparison AUC",
    "Figure S6. Weibull dynamic model comparison C index",
    "Figure S7. Weibull dynamic model comparison Accuracy",
    "Figure S8. Weibull dynamic model comparison Sensitivity",
    "Figure S9. Weibull dynamic model comparison Specificity",
    "Figure S10. Trajectory of WPR three latent classes",
    "Figure S11. Twenty-eight day mortality by WPR trajectory class"
  ),
  new = c(
    NA_character_,
    "Figure S1. Kaplan Meier survival by trajectory class",
    "Figure S2. Piecewise Cox cut point search",
    "Figure S3. Subgroup analysis by trajectory class",
    "Figure S4. Weibull dynamic model comparison AUC",
    "Figure S5. Weibull dynamic model comparison C index",
    "Figure S6. Weibull dynamic model comparison Accuracy",
    "Figure S7. Weibull dynamic model comparison Sensitivity",
    "Figure S8. Weibull dynamic model comparison Specificity",
    "Figure S9. Trajectory of WPR three latent classes",
    "Figure S10. Twenty-eight day mortality by WPR trajectory class"
  ),
  stringsAsFactors = FALSE
)

.rename_one <- function(dir, ext, old_stem, new_stem) {
  src <- file.path(dir, paste0(old_stem, ".", ext))
  if (!file.exists(src)) return(FALSE)
  if (is.na(new_stem) || !nzchar(new_stem)) {
    unlink(src)
    return(TRUE)
  }
  dest <- file.path(dir, paste0(new_stem, ".", ext))
  if (identical(normalizePath(src, mustWork = FALSE),
                normalizePath(dest, mustWork = FALSE))) return(FALSE)
  file.rename(src, dest)
  TRUE
}

# 从大号往小号改，避免覆盖
ord <- rev(seq_len(nrow(renumber)))
for (i in ord) {
  old <- renumber$old[[i]]
  new <- renumber$new[[i]]
  for (sub in c("pdf", "png", "tiff")) {
    .rename_one(file.path(fig_root, sub), sub, old, new)
  }
  md_old <- file.path(fig_root, "image_information", paste0(old, ".md"))
  if (file.exists(md_old)) {
    if (is.na(new) || !nzchar(new)) {
      unlink(md_old)
    } else {
      md_new <- file.path(fig_root, "image_information", paste0(new, ".md"))
      txt <- readLines(md_old, warn = FALSE, encoding = "UTF-8")
      txt <- sub(paste0("^# ", old, "$"), paste0("# ", new), txt)
      writeLines(txt, md_new, useBytes = TRUE)
      if (!identical(md_old, md_new)) unlink(md_old)
    }
  }
  # 分库 tagged
  for (db_lab in c("MIMIC", "eICU")) {
    old_t <- sub("^(Figure S[0-9]+)\\.", paste0("\\1-", db_lab, "."), old)
    new_t <- if (is.na(new) || !nzchar(new)) NA_character_ else
      sub("^(Figure S[0-9]+)\\.", paste0("\\1-", db_lab, "."), new)
    db <- if (identical(db_lab, "eICU")) "eicu" else "mimic"
    .rename_one(file.path(index_root, db, "Figures"), "pdf", old_t, new_t)
  }
}

# 根目录若还留平铺 pdf
for (i in ord) {
  .rename_one(fig_root, "pdf", renumber$old[[i]], renumber$new[[i]])
}

cli::cli_alert_success("Figure S1 已删，S2–S11 已顺延为 S1–S10")

# ── 2) 对齐 Table 1 / S1 / S3 ─────────────────────────────────────────────
pairs <- list(
  list(
    kind = "table1",
    files = c(
      file.path(tab_root, "Table 1-MIMIC. Baseline characteristics of Acute pancreatitis.xlsx"),
      file.path(tab_root, "Table 1-eICU. Baseline characteristics of Acute pancreatitis.xlsx"),
      file.path(index_root, "mimic/Tables",
                "Table 1-MIMIC. Baseline characteristics of Acute pancreatitis.xlsx"),
      file.path(index_root, "eicu/Tables",
                "Table 1-eICU. Baseline characteristics of Acute pancreatitis.xlsx")
    )
  ),
  list(
    kind = "s1",
    files = c(
      file.path(tab_root, "Table S1-MIMIC. Baseline characteristics of patients before and after multiple imputation.xlsx"),
      file.path(tab_root, "Table S1-eICU. Baseline characteristics of patients before and after multiple imputation.xlsx"),
      file.path(index_root, "mimic/Tables",
                "Table S1-MIMIC. Baseline characteristics of patients before and after multiple imputation.xlsx"),
      file.path(index_root, "eicu/Tables",
                "Table S1-eICU. Baseline characteristics of patients before and after multiple imputation.xlsx")
    )
  ),
  list(
    kind = "s3",
    files = c(
      file.path(tab_root, "Table S3-MIMIC. Univariate Regression Analysis.xlsx"),
      file.path(tab_root, "Table S3-eICU. Univariate Regression Analysis.xlsx"),
      file.path(index_root, "mimic/Tables",
                "Table S3-MIMIC. Univariate Regression Analysis.xlsx"),
      file.path(index_root, "eicu/Tables",
                "Table S3-eICU. Univariate Regression Analysis.xlsx")
    )
  )
)

for (job in pairs) {
  for (fp in job$files) {
    if (!file.exists(fp)) next
    .drop_rows_not_in_keep(fp, job$kind)
  }
}

# 根目录两库行名核对
.check <- function(a, b, label) {
  la <- .labels(a)
  lb <- .labels(b)
  # 去掉标题行里的库标签差异
  la[1] <- sub("-(MIMIC|eICU)\\.", ".", la[1])
  lb[1] <- sub("-(MIMIC|eICU)\\.", ".", lb[1])
  # Table 1 A1 本来就没有库标签
  if (!identical(la, lb)) {
    only_a <- setdiff(la, lb)
    only_b <- setdiff(lb, la)
    cli::cli_alert_warning(
      "{label} 行名未完全一致 | MIMIC独有={paste(only_a, collapse=', ')} | eICU独有={paste(only_b, collapse=', ')}"
    )
    cat("MIMIC:\n"); print(la)
    cat("eICU:\n"); print(lb)
  } else {
    cli::cli_alert_success("{label} 两库行名已对齐（{length(la)} 行）")
  }
}
.check(
  file.path(tab_root, "Table 1-MIMIC. Baseline characteristics of Acute pancreatitis.xlsx"),
  file.path(tab_root, "Table 1-eICU. Baseline characteristics of Acute pancreatitis.xlsx"),
  "Table 1"
)
.check(
  file.path(tab_root, "Table S1-MIMIC. Baseline characteristics of patients before and after multiple imputation.xlsx"),
  file.path(tab_root, "Table S1-eICU. Baseline characteristics of patients before and after multiple imputation.xlsx"),
  "Table S1"
)
.check(
  file.path(tab_root, "Table S3-MIMIC. Univariate Regression Analysis.xlsx"),
  file.path(tab_root, "Table S3-eICU. Univariate Regression Analysis.xlsx"),
  "Table S3"
)

readme <- file.path(tab_root, "README.md")
if (file.exists(readme)) {
  txt <- readLines(readme, warn = FALSE, encoding = "UTF-8")
  extra <- c(
    "",
    "Figure S1（Missing overview）已删除；其后补图顺延：",
    "KM=S1，切点搜索=S2（仅 MIMIC），亚组=S3，Weibull AUC–Spec=S4–S8，三类轨迹=S9，死亡率柱图=S10。",
    "Table 1 / S1 / S3 两库变量已按交集对齐（去掉 Race/婚姻/单库共病/WPR 成分列等）。"
  )
  writeLines(c(txt, extra), readme, useBytes = TRUE)
}

cli::cli_alert_success("drop S1 + 表列对齐完成")
