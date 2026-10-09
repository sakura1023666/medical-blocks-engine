#!/usr/bin/env Rscript
# tests/test_pub_xlsx_surgical.R — R/pub_xlsx_surgical.R 回归
# 用法: Rscript tests/test_pub_xlsx_surgical.R
# 在临时副本上测：删行保样式、改单元格、strip xml:space、verify 零脏格。
# 找不到样例 HRR/SOSM 表时改用任意存在的发表 xlsx；全无则 SKIP。

root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), ".."), winslash = "/", mustWork = FALSE)
source(file.path(root, "R/pub_xlsx_surgical.R"))
suppressPackageStartupMessages(library(openxlsx))

cands <- Sys.glob("/mnt/g/DockerHome/5006/medical-blocks-studies/02_fuzhumailiu/tr/by_index/【success】*/Tables/Table S2-*.xlsx")
if (!length(cands)) { cat("SKIP: no sample pub xlsx found\n"); quit(status = 0) }
p <- tempfile(fileext = ".xlsx")
file.copy(cands[1], p, overwrite = TRUE)

v0 <- pub_xlsx_verify(p)
stopifnot(v0$readable, v0$styles > 0)
d0 <- read.xlsx(p, colNames = FALSE)
pub_xlsx_delete_rows(p, nrow(d0), root = root)
d1 <- read.xlsx(p, colNames = FALSE)
stopifnot(nrow(d1) == nrow(d0) - 1L)
v1 <- pub_xlsx_verify(p)
stopifnot(v1$readable, identical(as.integer(v1$corrupt_cells), 0L), v1$styles > 0)

ed <- data.frame(row = 2L, col = 1L, value = "Variable", stringsAsFactors = FALSE)
pub_xlsx_edit_cells(p, ed, root = root)
d2 <- read.xlsx(p, colNames = FALSE)
stopifnot(identical(as.character(d2[2, 1]), "Variable"))
stopifnot(pub_xlsx_verify(p)$readable)
cat("PASS: pub_xlsx_surgical delete/edit/verify keep styles, zero corrupt\n")
