#!/usr/bin/env Rscript
# 还原听力 UHR Table1：只用主分析产物（暴露=UHR），撤掉 fullvars 误推的全复合指标表。
# 禁止对本目录做「复制到父目录」之类自拷贝（SMB 上会把文件截成 0 字节）。
suppressPackageStartupMessages(options(stringsAsFactors = FALSE, warn = 1))

study <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
success <- file.path(study, "by_index", "【success】UHR")
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")

src_map <- list(
  NHANES = file.path(
    success, "NHANES", "step09_baseline_nhanes", "Tables",
    "Table 1-NHANES. Weighted Baseline Characteristics of Participants Categorized by - Hearing Loss Status.xlsx"
  ),
  CHARLS = file.path(
    success, "CHARLS", "step07_baseline_binary", "Tables",
    "Table 1-CHARLS. Baseline characteristics of hearing loss.xlsx"
  )
)

agg <- file.path(success, "Tables")
dir.create(agg, recursive = TRUE, showWarnings = FALSE)

for (db in names(src_map)) {
  src <- src_map[[db]]
  if (!file.exists(src) || isTRUE(file.info(src)$size < 100)) {
    stop("missing/empty source Table1 (run reexport_uhr_from_checkpoints.R first): ", src)
  }
  dests <- unique(c(
    file.path(success, db, "Tables", basename(src)),
    file.path(agg, basename(src))
  ))
  for (dest in dests) {
    if (normalizePath(src, mustWork = TRUE) == normalizePath(dest, mustWork = FALSE)) next
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    ok <- file.copy(src, dest, overwrite = TRUE)
    if (!isTRUE(ok) || isTRUE(file.info(dest)$size < 100))
      stop("copy failed/empty: ", src, " -> ", dest)
    message(sprintf("restored %s → %s (size=%s)", db, dest, file.info(dest)$size))
  }
}

junk <- list.files(
  c(file.path(success, "CHARLS", "Tables"), agg),
  pattern = "^Table 2-CHARLS\\. Baseline characteristics",
  full.names = TRUE
)
if (length(junk)) {
  unlink(junk)
  message("removed fullvars baseline junk: ", paste(basename(junk), collapse = ", "))
}

# 仅收集 summary_result；副本请用 PowerShell Copy-Item，勿在此自拷贝
sh <- file.path(root, "run/hearing_loss_uhr/collect_hearing_uhr_summary_result.sh")
if (file.exists(sh)) system2("bash", c(sh, study))

suppressPackageStartupMessages({
  library(readxl)
  source(file.path(root, "configs/indices/composite_index_vars.R"))
})
other_ix <- setdiff(.composite_index_vars, "UHR")
fail <- FALSE
for (db in c("NHANES", "CHARLS", "Single")) {
  f <- list.files(agg, pattern = paste0("^Table 1-", db), full.names = TRUE)[1]
  if (is.na(f) || !file.exists(f) || isTRUE(file.info(f)$size < 100)) {
    message("FAIL missing/empty Table1-", db)
    fail <- TRUE
    next
  }
  x <- as.data.frame(read_excel(f, col_names = FALSE), stringsAsFactors = FALSE)
  labs <- unique(trimws(as.character(x[[1]])))
  labs <- labs[!is.na(labs) & nzchar(labs)]
  bad <- intersect(other_ix, labs)
  for (v in other_ix) {
    if (any(labs == gsub("_", " ", v))) bad <- c(bad, v)
  }
  bad <- unique(setdiff(bad, "BMI")) # BMI 临床行标签常为 BMI,kg/m²，不按复合指标名命中
  has_uhr <- "UHR" %in% labs
  message(sprintf(
    "OK check %s: rows=%d size=%s UHR=%s other_composites=%s",
    db, nrow(x), file.info(f)$size, has_uhr,
    if (length(bad)) paste(bad, collapse = ",") else "none"
  ))
  if (!has_uhr || length(bad)) fail <- TRUE
}
if (fail) quit(status = 1)
message("Table1 restored to exposure-only (UHR)")
