#!/usr/bin/env Rscript
# Align AKI WPR Table 1 / S1 / S3 / S5 to AP dual-db logic:
#   - keep variable intersection across eICU + MIMIC
#   - among composite indices keep ONLY exposure WPR
#   - surgical row delete (preserve SCI 三线表)
#
#   Rscript run/trajectory_prognosis/align_aki_wpr_table1_dual_exposure_only.R

suppressPackageStartupMessages({
  library(cli)
})
`%||%` <- function(a, b) if (!is.null(a)) a else b

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
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/pub_xlsx_surgical.R"), local = FALSE)
source(file.path(.engine, "configs/indices/composite_index_vars.R"), local = FALSE)
if (file.exists(file.path(.engine, "R/trajectory_paper_tables.R")))
  source(file.path(.engine, "R/trajectory_paper_tables.R"), local = FALSE)

block_root <- if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result" else "G:/02block_result"
index_root <- file.path(
  block_root, "44_AKI_SPESIS_CKD/Prognosis_Trajectory_38882552/tr/by_index/【success】WPR"
)
tab_root <- file.path(index_root, "Tables")
stopifnot(dir.exists(tab_root))

cli_h1("Align Table1/S1/S3/S5: dual intersection + exposure=WPR only")

.norm <- function(x) {
  x <- trimws(as.character(x %||% ""))
  x[is.na(x)] <- ""
  x <- sub(",.*$", "", x)                 # drop units after comma
  x <- sub("\\s*\\(.*\\)\\s*$", "", x)    # drop trailing (IQR)/(%) etc for S5
  x <- gsub("_", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

# categorical levels / junk that are not variable names
.levels <- c(
  "Female", "Male", "No", "Yes", "Missing (%)",
  "Asian", "Black", "Hispanic", "Other", "White",
  "Married", "Single/divorced", "English",
  "0", "1", "2", "3"
)
.sections <- c(
  "Demographics", "Vital Signs", "Laboratory Tests", "Clinical Scores",
  "Interventions and Hospital Course", "Comorbidities", "Exposure",
  "Characteristic", "Variable", "Overall", "Class 1", "Class 2", "Class 3", "Class 4"
)

# composite indices except exposure WPR (+ common aliases / derived index-like)
.composites_drop <- {
  ix <- as.character(get0(".composite_index_vars", inherits = TRUE) %||% character(0))
  ix <- setdiff(ix, "WPR")
  aliases <- c(
    gsub("_", " ", ix),
    "BUN Cr", "BUN_Cr", "RDW CV", "RDW_CV", "De Ritis", "De_Ritis",
    "ALT AST ratio flag", "lymp score", "alb score",
    "HHR", "HRR",  # derived indices（非 AP Table1 生命体征）
    "ACAG", "EASIX", "FIB4", "APRI", "GNRI", "SOSM", "PLR", "BAR", "CAR",
    "GPR", "RAR", "NLR", "SII"
  )
  unique(c(.norm(ix), .norm(aliases)))
}

.extra_drop <- .norm(c(
  "Mortality 28d", "Mortality_28d", "fustatus",
  # single-db / AP-style exclusions (even if one side has them)
  "Marital Status", "Language", "Height", "BMI",
  "Mechanical ventilation duration",
  "Acute Renal Failure", "Tuberculosis", "CRRT",
  "SAPSII", "GCS", "CHARLSON",
  "Lactate", "PH", "PCO2", "PO2", "TotalCo2", "FreeCalcium",
  "INR", "PT", "PTT",
  "ALT", "AST", "LD", "Albumin", "BilirubinTotal", "Bilirubin Total",
  "NeutrophilCount", "Lymphocytes",
  "lymp score", "alb score"
))

.read_var_names <- function(path) {
  d <- openxlsx::read.xlsx(path, colNames = FALSE)
  v <- .norm(d[[1L]])
  out <- character()
  for (lab in v) {
    if (!nzchar(lab)) next
    if (grepl("^Table ", lab, ignore.case = TRUE)) next
    if (grepl("^(Continuous variables|Statistical comparisons)", lab)) next
    if (lab %in% .levels || lab %in% .sections) next
    if (grepl("presented as", lab, ignore.case = TRUE)) next
    out <- c(out, lab)
  }
  unique(out)
}

.t1_e <- list.files(tab_root, pattern = "^Table 1-eICU\\.", full.names = TRUE)[1]
.t1_m <- list.files(tab_root, pattern = "^Table 1-MIMIC\\.", full.names = TRUE)[1]
stopifnot(file.exists(.t1_e), file.exists(.t1_m))
ve <- .read_var_names(.t1_e)
vm <- .read_var_names(.t1_m)
inter <- intersect(ve, vm)
keep_vars <- setdiff(inter, unique(c(.composites_drop, .extra_drop)))
# always keep exposure
keep_vars <- unique(c(keep_vars, "WPR", "survival time 28d"))
# remove accidental numeric-only
keep_vars <- keep_vars[!grepl("^[0-9]+$", keep_vars)]

cli_alert_info("Table1 eICU vars={length(ve)} MIMIC={length(vm)} intersect={length(inter)}")
cli_alert_info("keep after drop composites/extra={length(keep_vars)}")
cli_alert_info("dropped composites in intersect: {paste(intersect(inter, .composites_drop), collapse=', ')}")
cli_bullets(c("*" = paste(keep_vars, collapse = ", ")))

.drop_rows_not_in_keep <- function(path, kind = c("table1", "s1", "s3", "s5")) {
  kind <- match.arg(kind)
  if (!file.exists(path)) {
    cli_alert_warning("missing: {path}")
    return(invisible(integer(0)))
  }
  d <- openxlsx::read.xlsx(path, colNames = FALSE)
  n <- nrow(d)
  c1 <- .norm(d[[1L]])
  current <- NA_character_
  drop <- logical(n)
  for (i in seq_len(n)) {
    lab <- c1[[i]]
    if (i == 1L || grepl("^Table ", lab, ignore.case = TRUE)) next
    if (lab %in% c("Characteristic", "Variable")) next
    if (grepl("^(Continuous variables|Statistical comparisons)", lab)) next
    if (lab %in% .sections) {
      current <- NA_character_
      next
    }
    is_level <- lab %in% .levels || (identical(lab, "") && kind %in% c("s3", "s5"))
    if (kind == "s1" && identical(lab, "Missing (%)")) is_level <- TRUE
    if (!is_level && nzchar(lab)) current <- lab
    if (is.na(current) || !nzchar(current)) next
    if (!current %in% keep_vars) drop[i] <- TRUE
  }
  # second pass: drop empty section headers (section followed by another section / footnote / EOF)
  for (i in seq_len(n)) {
    lab <- c1[[i]]
    if (!lab %in% .sections) next
    if (lab %in% c("Characteristic", "Variable", "Overall",
                   "Class 1", "Class 2", "Class 3", "Class 4")) next
    j <- i + 1L
    while (j <= n && (drop[j] || !nzchar(c1[[j]]))) j <- j + 1L
    if (j > n || c1[[j]] %in% .sections || grepl("^(Continuous|Statistical|presented)", c1[[j]])) {
      drop[i] <- TRUE
    }
  }
  rows <- which(drop)
  if (!length(rows)) {
    cli_alert_info("{basename(path)}: 无需删行")
    return(invisible(integer(0)))
  }
  shown <- c1[rows]
  shown <- shown[nzchar(shown)]
  cli_alert_info(
    "{basename(path)}: 删 {length(rows)} 行 eg. {paste(utils::head(unique(shown), 10), collapse = ', ')}"
  )
  pub_xlsx_delete_rows(path, rows, root = .engine)
  # verify
  vr <- pub_xlsx_verify(path)
  if (!isTRUE(vr$readable) || as.integer(vr$corrupt_cells %||% 1) > 0L)
    cli_alert_danger("verify fail: {basename(path)}")
  else
    cli_alert_success("ok {basename(path)} (styles={vr$styles})")
  invisible(rows)
}

# collect paths: root + per-db mirrors
.paths_for <- function(pattern) {
  roots <- c(
    tab_root,
    file.path(index_root, "eicu", "Tables"),
    file.path(index_root, "mimic", "Tables")
  )
  unique(unlist(lapply(roots, function(d) {
    if (!dir.exists(d)) return(character())
    list.files(d, pattern = pattern, full.names = TRUE)
  })))
}

# ── Table 1 ────────────────────────────────────────────────────────────────
for (fp in .paths_for("^Table 1-.*\\.xlsx$")) .drop_rows_not_in_keep(fp, "table1")

# ── Table S1 ───────────────────────────────────────────────────────────────
for (fp in .paths_for("^Table S1-.*\\.xlsx$")) .drop_rows_not_in_keep(fp, "s1")

# ── Table S3 ───────────────────────────────────────────────────────────────
for (fp in .paths_for("^Table S3-.*Univariate.*\\.xlsx$")) .drop_rows_not_in_keep(fp, "s3")

# ── Table S5 by class ──────────────────────────────────────────────────────
for (fp in .paths_for("^Table S5-.*by trajectory class.*\\.xlsx$")) {
  .drop_rows_not_in_keep(fp, "s5")
  # fix leftover S7 title in A1 if present
  if (exists("trajectory_sync_xlsx_a1_from_filename", mode = "function")) {
    try(trajectory_sync_xlsx_a1_from_filename(fp), silent = TRUE)
  } else {
    # light surgical A1 fix
    d0 <- tryCatch(openxlsx::read.xlsx(fp, colNames = FALSE, rows = 1, cols = 1), error = function(e) NULL)
    if (!is.null(d0)) {
      a1 <- as.character(d0[1, 1] %||% "")
      if (grepl("Table S7", a1)) {
        new_a1 <- sub("Table S7", "Table S5", a1)
        pub_xlsx_edit_cells(fp, data.frame(row = 1L, col = 1L, value = new_a1, stringsAsFactors = FALSE))
      }
    }
  }
}

# save keep list
sum_dir <- file.path(tab_root, "Summary")
dir.create(sum_dir, showWarnings = FALSE, recursive = TRUE)
utils::write.csv(
  data.frame(keep_var = keep_vars, stringsAsFactors = FALSE),
  file.path(sum_dir, "table1_dual_keep_vars_WPR.csv"),
  row.names = FALSE
)

# README note
rp <- file.path(tab_root, "README.md")
note <- c(
  "",
  "## Table 1 / S1 / S3 / S5 双库对齐（AP 逻辑）",
  "- 变量 = 两库 Table 1 交集",
  "- 复合指标仅保留暴露 **WPR**（剔除 BAR/CAR/PLR/RAR/SOSM/HHR/HRR/…）",
  "- 单库独有列（Race 两侧都有则保留；婚姻/语言/Height 等单库列已剔）",
  sprintf("- 整理时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
)
if (file.exists(rp)) writeLines(c(readLines(rp, warn = FALSE), note), rp, useBytes = TRUE)

# final peek
cli_h2("After: Table1 variable lists")
for (fp in c(.t1_e, .t1_m)) {
  cli_alert_info("{basename(fp)}: {paste(.read_var_names(fp), collapse = ' | ')}")
}
cli_alert_success("Done")
