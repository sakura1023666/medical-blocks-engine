#!/usr/bin/env Rscript
# 整理发表 Tables：只留 Jin 主文/必要补充；其余挪到 _archive/tables_misc/
# 保留（每库）：
#   Table 1  Baseline sIPTW
#   Table 2  IPTW Subgroup（一张）
#   Table Sens  Multivariable Cox + Overlap
#   Table S1  Imputation baseline
#   Table S2  Univariate
#   Table S3  VIF
#   Table S4  Association before/after IPTW
#   Table S5  STEPP composite / definition
#   Table S6  PH assumption
#   Table S7  Uno C-index
# 根目录另：Batch/Indicator → reports/

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
archive_root <- file.path(proj, "_archive", paste0("tables_misc_", stamp))
dir.create(archive_root, recursive = TRUE, showWarnings = FALSE)
reports <- file.path(proj, "reports")
dir.create(reports, recursive = TRUE, showWarnings = FALSE)

.move_to <- function(files, dest_dir) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  for (f in files) {
    if (!file.exists(f)) next
    file.rename(f, file.path(dest_dir, basename(f)))
  }
}

# ---- root Tables ----
root_tbl <- file.path(proj, "Tables")
if (dir.exists(root_tbl)) {
  # batch / indicator → reports
  batch <- list.files(root_tbl, pattern = "^(Batch_summary|Indicator_availability)", full.names = TRUE)
  if (length(batch)) file.copy(batch, reports, overwrite = TRUE)
  .move_to(batch, file.path(archive_root, "root_batch"))

  keep_pat <- c(
    "^Table 1-.*(Baseline characteristics before and after sIPTW)",
    "^Table Sens-.*(Multivariable Cox|Overlap Weights)",
    "^Table S1-.*(imputation|Uno)",
    "^Table S2-.*(Univariate|Baseline characteristics of patients before and after multiple imputation)",
    "^Table S3-.*(Univariate|VIF|Multicollinearity)",
    "^Table S4-.*(VIF|Multicollinearity|Association)",
    "^Table S5-",
    "^Table S6-",
    "^Table S7-"
  )
  # 明确不要：错标成 Table 1 的亚组森林表
  drop_explicit <- list.files(root_tbl, pattern = "Table 1-.*IPTW Subgroup", full.names = TRUE)
  all_f <- list.files(root_tbl, full.names = TRUE)
  all_f <- all_f[file.info(all_f)$isdir %in% FALSE]
  keep <- character(0)
  for (p in keep_pat) {
    keep <- c(keep, all_f[grepl(p, basename(all_f), ignore.case = TRUE)])
  }
  keep <- unique(keep)
  # 根目录只留：双库 Table1 + Sens Cox/Overlap；其余进 archive（S 表以 unit 为准）
  root_keep <- all_f[grepl(
    "^Table 1-.*(Baseline characteristics before and after sIPTW)|^Table Sens-",
    basename(all_f),
    ignore.case = TRUE
  )]
  root_drop <- setdiff(all_f, root_keep)
  .move_to(unique(c(root_drop, drop_explicit)), file.path(archive_root, "root_Tables"))
  message("root Tables kept: ", paste(basename(root_keep), collapse = " | "))
}

# ---- unit Tables ----
.curate_unit <- function(unit_tag, db_lab) {
  tbl <- file.path(proj, "by_unit", unit_tag, "Tables")
  if (!dir.exists(tbl)) return(invisible(NULL))
  arch <- file.path(archive_root, paste0("unit_", db_lab))
  dir.create(arch, recursive = TRUE, showWarnings = FALSE)

  # preferred sources (latest by mtime among candidates)
  .pick <- function(patterns) {
    hits <- list.files(tbl, full.names = TRUE)
    hits <- hits[!file.info(hits)$isdir]
    out <- character(0)
    for (p in patterns) {
      h <- hits[grepl(p, basename(hits), ignore.case = TRUE)]
      if (!length(h)) next
      h <- h[order(file.info(h)$mtime, decreasing = TRUE)]
      out <- c(out, h[[1L]])
    }
    unique(out)
  }

  preferred <- .pick(c(
    paste0("^Table 1-", db_lab, "\\. Baseline characteristics before and after sIPTW\\.xlsx$"),
    paste0("^Table 2-", db_lab, "\\. IPTW Subgroup Analysis"),
    paste0("^Table Sens-", db_lab, "\\. Multivariable Cox"),
    paste0("^Table Sens-", db_lab, "\\. Overlap Weights"),
    "Baseline characteristics before and after imputation",
    "Baseline characteristics of patients before and after multiple imputation",
    "Univariate Regression Analysis",
    "Multicollinearity Analysis",
    "Association between Alteplase",
    "STEPP Composite|STEPP_Composite|CompositeRisk_Definition",
    "Proportional hazards assumption",
    "Uno.?s concordance|Uno's concordance"
  ))

  # rename/copy into clean names
  clean_map <- list()
  for (f in preferred) {
    bn <- basename(f)
    if (grepl("Baseline characteristics before and after sIPTW", bn, ignore.case = TRUE)) {
      clean_map[[f]] <- paste0("Table 1-", db_lab, ". Baseline characteristics before and after sIPTW.xlsx")
    } else if (grepl("IPTW Subgroup Analysis", bn, ignore.case = TRUE) && grepl("^Table [24]-", bn)) {
      clean_map[[f]] <- paste0("Table 2-", db_lab, ". IPTW Subgroup Analysis.xlsx")
    } else if (grepl("Multivariable Cox", bn, ignore.case = TRUE)) {
      clean_map[[f]] <- paste0("Table Sens-", db_lab, ". Multivariable Cox for Alteplase and 28-day mortality.xlsx")
    } else if (grepl("Overlap Weights", bn, ignore.case = TRUE)) {
      clean_map[[f]] <- paste0("Table Sens-", db_lab, ". Overlap Weights.xlsx")
    } else if (grepl("imputation", bn, ignore.case = TRUE) && grepl("Baseline", bn, ignore.case = TRUE)) {
      clean_map[[f]] <- paste0("Table S1-", db_lab, ". Baseline characteristics before and after imputation.xlsx")
    } else if (grepl("Univariate", bn, ignore.case = TRUE)) {
      clean_map[[f]] <- paste0("Table S2-", db_lab, ". Univariate Regression Analysis.xlsx")
    } else if (grepl("Multicollinearity|VIF", bn, ignore.case = TRUE)) {
      clean_map[[f]] <- paste0("Table S3-", db_lab, ". Multicollinearity Analysis VIF screen.xlsx")
    } else if (grepl("Association between", bn, ignore.case = TRUE)) {
      clean_map[[f]] <- paste0("Table S4-", db_lab, ". Association between Alteplase and 28-day mortality before and after IPTW.xlsx")
    } else if (grepl("STEPP|CompositeRisk", bn, ignore.case = TRUE)) {
      if (grepl("\\.csv$", bn, ignore.case = TRUE)) {
        clean_map[[f]] <- paste0("Table S5-", db_lab, ". STEPP CompositeRisk Definition.csv")
      } else {
        clean_map[[f]] <- paste0("Table S5-", db_lab, ". STEPP Composite window coefficients.xlsx")
      }
    } else if (grepl("Proportional hazards|Schoenfeld", bn, ignore.case = TRUE)) {
      clean_map[[f]] <- paste0("Table S6-", db_lab, ". Proportional hazards assumption test.xlsx")
    } else if (grepl("Uno|concordance", bn, ignore.case = TRUE)) {
      clean_map[[f]] <- paste0("Table S7-", db_lab, ". Uno concordance index at 28-day.xlsx")
    }
  }

  # archive everything first, then rebuild clean set from archive copies
  all_now <- list.files(tbl, full.names = TRUE)
  all_now <- all_now[!file.info(all_now)$isdir]
  for (f in all_now) {
    file.copy(f, file.path(arch, basename(f)), overwrite = TRUE)
  }
  unlink(all_now)
  for (src0 in names(clean_map)) {
    src <- file.path(arch, basename(src0))
    if (!file.exists(src)) next
    dest <- file.path(tbl, clean_map[[src0]])
    file.copy(src, dest, overwrite = TRUE)
  }
  # also copy Table1/Sens to root
  root_tbl <- file.path(proj, "Tables")
  dir.create(root_tbl, recursive = TRUE, showWarnings = FALSE)
  for (bn in c(
    paste0("Table 1-", db_lab, ". Baseline characteristics before and after sIPTW.xlsx"),
    paste0("Table Sens-", db_lab, ". Multivariable Cox for Alteplase and 28-day mortality.xlsx"),
    paste0("Table Sens-", db_lab, ". Overlap Weights.xlsx")
  )) {
    src <- file.path(tbl, bn)
    if (file.exists(src)) file.copy(src, file.path(root_tbl, bn), overwrite = TRUE)
  }
  message(db_lab, " Tables now: ", paste(list.files(tbl), collapse = " | "))
}

.curate_unit("\u3010success\u3011main", "MIMIC")
.curate_unit("\u3010success\u3011eICU", "eICU")
message("archive -> ", archive_root)
message("root Tables -> ", paste(list.files(file.path(proj, "Tables")), collapse = " | "))
