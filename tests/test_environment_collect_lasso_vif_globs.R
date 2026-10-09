#!/usr/bin/env Rscript
# 汇总不得把 Table S4-VOC VIF / Table S7 LASSO 误配成 univariate 或临床 VIF

.test_dir <- local({
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) return(normalizePath(dirname(sub("^--file=", "", f[1L]))))
  normalizePath("tests")
})
.root <- normalizePath(file.path(.test_dir, ".."), winslash = "/")
source(file.path(.root, "R/utils.R"), local = FALSE)
source(file.path(.root, "R/environment_collect_results.R"), local = FALSE)

.check <- function(cond, msg) {
  if (!isTRUE(cond)) stop(msg, call. = FALSE)
}

.write_marker_xlsx <- function(path, marker) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Table")
  openxlsx::writeData(wb, "Table", marker, startRow = 1L, colNames = FALSE)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
}

.read_a1 <- function(path) {
  wb <- openxlsx::loadWorkbook(path)
  as.character(openxlsx::read.xlsx(wb, sheet = 1L, colNames = FALSE)[1, 1])
}

tmp <- tempfile("env_collect_glob_")
dir.create(tmp, recursive = TRUE)
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

shared_tbl <- file.path(tmp, "_shared", "Tables")
step15_tbl <- file.path(tmp, "_shared", "step15_lasso_environment_voc", "Tables")
step11_tbl <- file.path(tmp, "_shared", "step11_multicollinearity_nhanes_screen", "Tables")
dir.create(shared_tbl, recursive = TRUE)
dir.create(step15_tbl, recursive = TRUE)
dir.create(step11_tbl, recursive = TRUE)

.write_marker_xlsx(
  file.path(shared_tbl, "Table S4-NHANES-VOC. Univariate Regression Analysis.xlsx"),
  "WRONG_UNIVARIATE"
)
.write_marker_xlsx(
  file.path(shared_tbl, "Table S4-NHANES-VOC. Weighted Multicollinearity Analysis.xlsx"),
  "CORRECT_VOC_VIF"
)
.write_marker_xlsx(
  file.path(shared_tbl, "Table S7-NHANES. Weighted Multicollinearity Analysis.xlsx"),
  "WRONG_CLINICAL_VIF"
)
.write_marker_xlsx(
  file.path(step11_tbl, "Table S4-NHANES. Weighted Multicollinearity Analysis.xlsx"),
  "CORRECT_CLINICAL_VIF"
)
.write_marker_xlsx(
  file.path(step15_tbl, "Table S7. Association between Environmental Toxicants and DKD.xlsx"),
  "CORRECT_LASSO"
)

res <- environment_collect_dkd_results(
  result_root = tmp,
  disease = "DKD",
  project_root = .root
)
mf <- res$manifest
pick <- function(id) {
  mf$dest[mf$standard_id == id & mf$status == "copied"][1L]
}

s4_voc <- pick("Table S4-VOC-VIF")
s7 <- pick("Table S7-LASSO")
s4 <- pick("Table S4-VIF-screen")
.check(file.exists(s4_voc), "S4-VOC dest missing")
.check(file.exists(s7), "S7 dest missing")
.check(identical(.read_a1(s4_voc), "CORRECT_VOC_VIF"), paste("S4-VOC got", .read_a1(s4_voc)))
.check(identical(.read_a1(s7), "CORRECT_LASSO"), paste("S7 got", .read_a1(s7)))
.check(identical(.read_a1(s4), "CORRECT_CLINICAL_VIF"), paste("S4 got", .read_a1(s4)))
.check(!identical(.read_a1(s4), .read_a1(s7)), "S4 and S7 must differ")

message("OK: environment collect LASSO/VIF globs")
