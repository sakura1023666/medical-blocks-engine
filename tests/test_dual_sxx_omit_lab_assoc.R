#!/usr/bin/env Rscript
# S-XX 双库同生共死省略 + S8 变量交集（unit，临时目录）
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}
src_runner <- file.path(root, "R", "incidence_dual_batch_runner.R")
stopifnot(file.exists(src_runner))
# 仅需 helper：避免整文件依赖；直接 source 会拉大量符号，测试只定义局部副本若缺失
if (!exists("incidence_batch_omit_dual_sxx_if_either_ns", mode = "function") ||
    !exists("incidence_batch_harmonize_dual_lab_assoc_varnames", mode = "function")) {
  suppressWarnings(source(src_runner, local = FALSE))
}
if (!exists("incidence_batch_classify_dual_supp_table", mode = "function")) {
  stop("incidence_batch_classify_dual_supp_table missing after source")
}

td <- tempfile("sxx_omit_")
dir.create(file.path(td, "Tables"), recursive = TRUE)
dir.create(file.path(td, "Figures", "image_information"), recursive = TRUE)
dir.create(file.path(td, "NHANES", "Tables"), recursive = TRUE)
dir.create(file.path(td, "CHARLS", "Tables"), recursive = TRUE)

# Fig2：NHANES Model2 非线性 NS
writeLines(c(
  "# Figure 2. RCS of HHR and Depression",
  "",
  "- NHANES Model2：P for overall < 0.001；P for nonlinear = 0.560；cutoff ≈ 2.95",
  "- CHARLS Model2：P for overall < 0.001；P for nonlinear < 0.001；cutoff ≈ 2.91"
), file.path(td, "Figures", "image_information", "Figure 2. RCS of HHR and Depression.md"))

sxx_n <- file.path(td, "Tables", "Table S-XX-NHANES. Weighted logistic regression of HHR RCS cutoff.xlsx")
sxx_c <- file.path(td, "Tables", "Table S-XX-CHARLS. Logistic regression of HHR RCS cutoff.xlsx")
writeLines("x", sxx_n)
writeLines("x", sxx_c)
# 分库副本
writeLines("x", file.path(td, "NHANES", "Tables", "Table S-XX-NHANES. Weighted logistic regression of HHR RCS cutoff.xlsx"))
writeLines("x", file.path(td, "CHARLS", "Tables", "Table S-XX-CHARLS. Logistic regression of HHR RCS cutoff.xlsx"))

cfg <- list(dual_db = list(enable = TRUE))
n <- incidence_batch_omit_dual_sxx_if_either_ns(
  tables_dirs = file.path(td, "Tables"),
  index_root = td,
  cfg = cfg
)
stopifnot(n >= 2L)
stopifnot(!file.exists(sxx_n))
stopifnot(!file.exists(sxx_c))
stopifnot(!file.exists(file.path(td, "NHANES", "Tables",
                                  "Table S-XX-NHANES. Weighted logistic regression of HHR RCS cutoff.xlsx")))

# 双侧齐全 + 非线性均显著 → 不删
writeLines(c(
  "# Figure 2. RCS",
  "- NHANES Model2：P for nonlinear = 0.01",
  "- CHARLS Model2：P for nonlinear = 0.02"
), file.path(td, "Figures", "image_information", "Figure 2. RCS of HHR and Depression.md"))
writeLines("x", sxx_n)
writeLines("x", sxx_c)
n2 <- incidence_batch_omit_dual_sxx_if_either_ns(
  tables_dirs = file.path(td, "Tables"), index_root = td, cfg = cfg
)
stopifnot(identical(as.integer(n2), 0L))
stopifnot(file.exists(sxx_n), file.exists(sxx_c))

# 仅一侧有表 → 全删（无 Fig2 时）
unlink(file.path(td, "Figures", "image_information"), recursive = TRUE)
unlink(sxx_c)
n3 <- incidence_batch_omit_dual_sxx_if_either_ns(
  tables_dirs = file.path(td, "Tables"), index_root = td, cfg = cfg
)
stopifnot(n3 >= 1L)
stopifnot(!file.exists(sxx_n))

# S8 变量交集：用最小假 xlsx（openxlsx）
if (requireNamespace("openxlsx", quietly = TRUE)) {
  mk_assoc <- function(path, vars) {
    rows <- list(c("Table S8. Associations", "", "", ""))
    rows <- c(rows, list(c("variable", "b", "ci", "p")))
    for (v in vars) {
      rows <- c(rows, list(c(v, "", "", "")))
      rows <- c(rows, list(c("Crude Model", "0.1", "(0,1)", "0.01")))
      rows <- c(rows, list(c("Model1", "0.1", "(0,1)", "0.01")))
      rows <- c(rows, list(c("Model2", "0.1", "(0,1)", "0.01")))
    }
    df <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
    openxlsx::write.xlsx(df, path, colNames = FALSE)
  }
  a_n <- file.path(td, "Tables", "Table S8-NHANES. Associations of HHR with laboratory indicators.xlsx")
  a_c <- file.path(td, "Tables", "Table S8-CHARLS. Associations of HHR with laboratory indicators.xlsx")
  mk_assoc(a_n, c("CRP", "WBC", "BUN", "Creatinine"))
  mk_assoc(a_c, c("CRP", "WBC"))
  # 需要 pub_xlsx_delete_rows；若不可用则跳过 S8 段
  sx <- file.path(root, "R", "pub_xlsx_surgical.R")
  if (file.exists(sx)) suppressWarnings(source(sx, local = FALSE))
  if (exists("pub_xlsx_delete_rows", mode = "function")) {
    n4 <- incidence_batch_harmonize_dual_lab_assoc_varnames(file.path(td, "Tables"), cfg)
    stopifnot(n4 >= 1L)
    d_n <- as.data.frame(readxl::read_excel(a_n, col_names = FALSE))
    v1 <- as.character(d_n[[1L]])
    stopifnot(!"BUN" %in% v1)
    stopifnot(!"Creatinine" %in% v1)
    stopifnot("CRP" %in% v1, "WBC" %in% v1)
  } else {
    message("skip S8 surgical (pub_xlsx_delete_rows missing)")
  }
}

unlink(td, recursive = TRUE)
message("test_dual_sxx_omit_lab_assoc: OK")
