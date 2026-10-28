#!/usr/bin/env Rscript
# 汇总表对齐卒中 Medication_regimen Jin 补充表四件套：
#   Table 1  Baseline sIPTW
#   Table S1 Uno C-index
#   Table S2 Imputation baseline
#   Table S3 Univariate
#   Table S4 VIF
#   (+ Table Sens Cox / Overlap)
# 其余进 _archive/

proj <- {
  a <- commandArgs(trailingOnly = TRUE)
  i <- match("--project", a)
  if (!is.na(i) && i < length(a)) a[[i + 1L]] else
    "G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw"
}
if (!dir.exists(proj)) {
  proj <- "/mnt/g/02block_result/47_PE/Medication_regimen_model_alteplase_ipw"
}
stopifnot(dir.exists(proj))

stamp <- format(Sys.time(), "%Y%m%d_%H%M")
arch <- file.path(proj, "_archive", paste0("tables_pre_jin4_", stamp))
dir.create(arch, recursive = TRUE, showWarnings = FALSE)

.pick_latest <- function(paths) {
  paths <- paths[file.exists(paths)]
  if (!length(paths)) return(NULL)
  paths[which.max(file.info(paths)$mtime)]
}

.find_one <- function(roots, pattern) {
  hits <- character(0)
  for (r in roots) {
    if (!dir.exists(r)) next
    hits <- c(hits, list.files(r, pattern = pattern, recursive = TRUE, full.names = TRUE))
  }
  hits <- hits[grepl("\\.xlsx$|\\.csv$", hits, ignore.case = TRUE)]
  hits <- hits[!grepl("/_archive/", hits)]
  .pick_latest(hits)
}

.curate_db <- function(db_lab, unit_tag) {
  unit_root <- file.path(proj, "by_unit", unit_tag)
  unit_tbl <- file.path(unit_root, "Tables")
  dir.create(unit_tbl, recursive = TRUE, showWarnings = FALSE)
  search_roots <- c(
    unit_tbl,
    unit_root,
    file.path(proj, "_archive")
  )

  # role -> regex (prefer content, not current wrong S#)
  roles <- list(
    t1 = "Baseline characteristics before and after sIPTW\\.xlsx$",
    s1_uno = "(Uno.?s concordance|Uno concordance index)",
    s2_imp = "(before and after (multiple )?imputation|Baseline characteristics of patients before and after)",
    s3_uv = "Univariate Regression Analysis",
    s4_vif = "(Multicollinearity|VIF)",
    sens_cox = "Multivariable Cox",
    sens_ow = "Overlap Weights"
  )
  # avoid picking wrong files for s2 (imputation not sIPTW)
  src <- list(
    t1 = .find_one(search_roots, roles$t1),
    s1_uno = .find_one(search_roots, roles$s1_uno),
    s2_imp = .find_one(
      search_roots,
      "(Baseline characteristics.*(imputation|multiple imputation)|before and after imputation)"
    ),
    s3_uv = .find_one(search_roots, roles$s3_uv),
    s4_vif = .find_one(search_roots, roles$s4_vif),
    sens_cox = .find_one(search_roots, roles$sens_cox),
    sens_ow = .find_one(search_roots, roles$sens_ow)
  )
  # s2 must not be sIPTW table1
  if (!is.null(src$s2_imp) && grepl("sIPTW", basename(src$s2_imp), ignore.case = TRUE)) {
    alts <- list.files(search_roots, pattern = "imputation", recursive = TRUE, full.names = TRUE)
    alts <- alts[grepl("\\.xlsx$", alts) & !grepl("sIPTW", alts, ignore.case = TRUE)]
    src$s2_imp <- .pick_latest(alts)
  }

  dest_names <- list(
    t1 = sprintf("Table 1-%s. Baseline characteristics before and after sIPTW.xlsx", db_lab),
    s1_uno = sprintf("Table S1-%s. The Uno's concordance index at 28-day.xlsx", db_lab),
    s2_imp = sprintf(
      "Table S2-%s. Baseline characteristics of patients before and after multiple imputation.xlsx",
      db_lab
    ),
    s3_uv = sprintf("Table S3-%s. Univariate Regression Analysis.xlsx", db_lab),
    s4_vif = sprintf(
      "Table S4-%s. Multicollinearity Analysis (VIF, univariate screen) for pe_ipw_alteplase.xlsx",
      db_lab
    ),
    sens_cox = sprintf(
      "Table Sens-%s. Multivariable Cox for Alteplase and 28-day mortality.xlsx", db_lab
    ),
    sens_ow = sprintf("Table Sens-%s. Overlap Weights.xlsx", db_lab)
  )

  # archive current unit Tables
  old <- list.files(unit_tbl, full.names = TRUE)
  old <- old[!file.info(old)$isdir]
  if (length(old)) {
    a_unit <- file.path(arch, paste0("unit_", db_lab))
    dir.create(a_unit, recursive = TRUE, showWarnings = FALSE)
    for (f in old) file.copy(f, file.path(a_unit, basename(f)), overwrite = TRUE)
    unlink(old)
  }

  # write clean set
  for (role in names(dest_names)) {
    s <- src[[role]]
    if (is.null(s) || !file.exists(s)) {
      message("MISSING ", db_lab, " ", role)
      next
    }
    # if source is inside unit_tbl and was deleted, try archive
    if (!file.exists(s)) {
      s2 <- file.path(arch, paste0("unit_", db_lab), basename(s))
      if (file.exists(s2)) s <- s2
    }
    # prefer archive copy if we just wiped
    s_arch <- file.path(arch, paste0("unit_", db_lab), basename(s))
    if (!file.exists(s) && file.exists(s_arch)) s <- s_arch
    if (!file.exists(s)) {
      # search archive for role pattern
      s <- .find_one(file.path(arch, paste0("unit_", db_lab)), gsub("\\\\", "", roles[[role]] %||% dest_names[[role]]))
    }
    if (is.null(s) || !file.exists(s)) {
      message("MISSING after archive ", db_lab, " ", role)
      next
    }
    file.copy(s, file.path(unit_tbl, dest_names[[role]]), overwrite = TRUE)
    message("OK ", dest_names[[role]], " <- ", basename(s))
  }
  invisible(dest_names)
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

# Fix find after wipe: first copy sources from scattered places BEFORE wipe
.collect_then_write <- function(db_lab, unit_tag) {
  unit_root <- file.path(proj, "by_unit", unit_tag)
  unit_tbl <- file.path(unit_root, "Tables")
  roots <- c(unit_tbl, list.dirs(unit_root, recursive = FALSE), file.path(proj, "_archive"))
  # flatten step Tables too
  roots <- unique(c(roots, list.dirs(unit_root, full.names = TRUE)))
  roots <- roots[grepl("Tables$|/Tables$|_archive", roots) | roots == unit_tbl]

  pick <- function(pat, anti = NULL) {
    hits <- character(0)
    for (r in roots) {
      if (!dir.exists(r)) next
      hits <- c(hits, list.files(r, pattern = "\\.xlsx$", recursive = FALSE, full.names = TRUE))
      hits <- c(hits, list.files(r, pattern = "\\.xlsx$", recursive = TRUE, full.names = TRUE))
    }
    hits <- unique(hits)
    hits <- hits[!grepl(paste0("tables_pre_jin4_", stamp), hits)]
    hits <- hits[grepl(pat, basename(hits), ignore.case = TRUE)]
    # 强制同库文件名（防 MIMIC 误拿 eICU）
    hits <- hits[grepl(db_lab, basename(hits), fixed = TRUE)]
    if (!is.null(anti)) hits <- hits[!grepl(anti, basename(hits), ignore.case = TRUE)]
    .pick_latest(hits)
  }

  files <- list(
    t1 = pick("sIPTW"),
    s1 = pick("Uno"),
    s2 = pick("imputation|multiple imputation", anti = "sIPTW"),
    s3 = pick("Univariate Regression"),
    s4 = pick("VIF|Multicollinearity"),
    cox = pick("Multivariable Cox"),
    ow = pick("Overlap Weights")
  )

  dest <- list(
    t1 = sprintf("Table 1-%s. Baseline characteristics before and after sIPTW.xlsx", db_lab),
    s1 = sprintf("Table S1-%s. The Uno's concordance index at 28-day.xlsx", db_lab),
    s2 = sprintf(
      "Table S2-%s. Baseline characteristics of patients before and after multiple imputation.xlsx",
      db_lab
    ),
    s3 = sprintf("Table S3-%s. Univariate Regression Analysis.xlsx", db_lab),
    s4 = sprintf(
      "Table S4-%s. Multicollinearity Analysis (VIF, univariate screen) for pe_ipw_alteplase.xlsx",
      db_lab
    ),
    cox = sprintf("Table Sens-%s. Multivariable Cox for Alteplase and 28-day mortality.xlsx", db_lab),
    ow = sprintf("Table Sens-%s. Overlap Weights.xlsx", db_lab)
  )

  # stage copies to temp so wipe won't lose
  stage <- file.path(tempdir(), paste0("jin4_", db_lab))
  dir.create(stage, recursive = TRUE, showWarnings = FALSE)
  staged <- list()
  for (nm in names(files)) {
    s <- files[[nm]]
    if (is.null(s)) {
      message("MISSING source ", db_lab, " ", nm)
      next
    }
    d <- file.path(stage, dest[[nm]])
    file.copy(s, d, overwrite = TRUE)
    staged[[nm]] <- d
    message("stage ", nm, " <- ", s)
  }

  # archive + wipe unit
  a_unit <- file.path(arch, paste0("unit_", db_lab))
  dir.create(a_unit, recursive = TRUE, showWarnings = FALSE)
  old <- list.files(unit_tbl, full.names = TRUE)
  old <- old[!isTRUE(file.info(old)$isdir)]
  for (f in old) {
    file.copy(f, file.path(a_unit, basename(f)), overwrite = TRUE)
  }
  unlink(old)

  .fix_xlsx_a1_to_basename <- function(path) {
    if (!file.exists(path) || !requireNamespace("openxlsx", quietly = TRUE)) return(invisible(FALSE))
    title <- tools::file_path_sans_ext(basename(path))
    ok <- tryCatch({
      wb <- openxlsx::loadWorkbook(path)
      openxlsx::writeData(wb, sheet = 1L, x = title, startCol = 1L, startRow = 1L)
      openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
      TRUE
    }, error = function(e) FALSE)
    invisible(ok)
  }

  for (nm in names(staged)) {
    dest_path <- file.path(unit_tbl, dest[[nm]])
    file.copy(staged[[nm]], dest_path, overwrite = TRUE)
    .fix_xlsx_a1_to_basename(dest_path)
  }
  message(db_lab, " -> ", paste(list.files(unit_tbl), collapse = " | "))
  staged
}

m <- .collect_then_write("MIMIC", "\u3010success\u3011main")
e <- .collect_then_write("eICU", "\u3010success\u3011eICU")

# rebuild root Tables = only Jin summary set
root_tbl <- file.path(proj, "Tables")
if (dir.exists(root_tbl)) {
  a_root <- file.path(arch, "root_Tables")
  dir.create(a_root, recursive = TRUE, showWarnings = FALSE)
  old <- list.files(root_tbl, full.names = TRUE)
  old <- old[!isTRUE(file.info(old)$isdir)]
  for (f in old) file.copy(f, file.path(a_root, basename(f)), overwrite = TRUE)
  unlink(old)
} else {
  dir.create(root_tbl, recursive = TRUE, showWarnings = FALSE)
}

for (db in c("MIMIC", "eICU")) {
  tag <- if (identical(db, "MIMIC")) "\u3010success\u3011main" else "\u3010success\u3011eICU"
  src_dir <- file.path(proj, "by_unit", tag, "Tables")
  for (bn in list.files(src_dir, pattern = "^Table (1|S[1-4]|Sens)-")) {
    file.copy(file.path(src_dir, bn), file.path(root_tbl, bn), overwrite = TRUE)
  }
}

message("ROOT Tables:\n", paste(list.files(root_tbl), collapse = "\n"))
message("archive: ", arch)
