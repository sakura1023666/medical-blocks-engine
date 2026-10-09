#!/usr/bin/env Rscript
# 一次性：修复 01_AKI/tr GPR 双库发表表序（对齐缺血卒中 MCV 白名单）
# Table1 → Table2(最优类数) → Table3(HR) → S1–S8，eICU+MIMIC 同序

args <- commandArgs(trailingOnly = TRUE)
.root_guess <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis") return(normalizePath(file.path(d, "..", ".."), winslash = "/"))
  }
  normalizePath(getwd(), winslash = "/")
}
root <- .root_guess()
setwd(root)

study_root <- if (length(args) && nzchar(args[[1L]])) args[[1L]] else
  "/mnt/g/DockerHome/5006/medical-blocks-studies/01_AKI/tr"
ix <- "GPR"
disease <- "Sepsis AKI"
base_dir <- file.path(study_root, "by_index", ix)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/trajectory_paper_tables.R"))
source(file.path(root, "R/trajectory_pub_curate.R"))

.db_lab <- function(db) if (identical(tolower(db), "eicu")) "eICU" else "MIMIC"

.copy_newest <- function(patterns, dest) {
  hits <- character(0)
  for (pat in patterns) {
    hits <- c(hits, Sys.glob(pat))
  }
  hits <- unique(hits[file.exists(hits)])
  if (!length(hits)) return(FALSE)
  mt <- file.info(hits)$mtime
  src <- hits[which.max(mt)]
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  same <- tryCatch(
    identical(normalizePath(src, mustWork = FALSE), normalizePath(dest, mustWork = FALSE)),
    error = function(e) FALSE
  )
  if (isTRUE(same) || identical(src, dest)) return(TRUE)
  # 已是正式名则跳过拷贝
  if (basename(src) == basename(dest) && dirname(src) == dirname(dest)) return(TRUE)
  file.copy(src, dest, overwrite = TRUE)
}

.restore_unit_tables <- function(db) {
  db_lab <- .db_lab(db)
  unit <- file.path(base_dir, db)
  tab <- file.path(unit, "Tables")
  dir.create(tab, recursive = TRUE, showWarnings = FALSE)
  # 把 _archive / step* 正式表先拉回根，便于 curate 认领
  specs <- list(
    list(dest = sprintf("Table 1-%s. Baseline characteristics of %s.xlsx", db_lab, disease),
         globs = c(
           file.path(unit, "step08_baseline_binary/Tables", sprintf("Table 1-%s*.xlsx", db_lab)),
           file.path(tab, "_archive", sprintf("Table 1-%s*.xlsx", db_lab)),
           file.path(tab, sprintf("Table 1-%s*.xlsx", db_lab))
         )),
    list(dest = sprintf("Table S1-%s. Baseline characteristics of patients before and after multiple imputation.xlsx", db_lab),
         globs = c(
           file.path(unit, "step06_imputation/Tables", sprintf("Table S1-%s*.xlsx", db_lab)),
           file.path(tab, "_archive", sprintf("Table S1-%s*.xlsx", db_lab)),
           file.path(tab, sprintf("Table S1-%s*.xlsx", db_lab))
         )),
    list(dest = sprintf("Table S2-%s. Normality test results for continuous variables.xlsx", db_lab),
         globs = c(
           file.path(unit, "step08_baseline_binary/Tables", sprintf("Table S2-%s*.xlsx", db_lab)),
           file.path(tab, sprintf("Table S2-%s*.xlsx", db_lab))
         )),
    list(dest = sprintf("Table S3-%s. Univariate Regression Analysis.xlsx", db_lab),
         globs = c(
           file.path(unit, "step09_univariate_prognosis/Tables", sprintf("Table S3-%s*.xlsx", db_lab)),
           file.path(tab, sprintf("Table S3-%s*.xlsx", db_lab))
         )),
    list(dest = sprintf("Table S4-%s. Multicollinearity Analysis (VIF, univariate screen).xlsx", db_lab),
         globs = c(
           file.path(unit, "step10_multicollinearity_screen/Tables", sprintf("Table S4-%s*.xlsx", db_lab)),
           file.path(tab, "_archive", sprintf("Table S4-%s*.xlsx", db_lab)),
           file.path(tab, sprintf("Table S4-%s*.xlsx", db_lab))
         )),
    list(dest = sprintf("Table S5-%s. Multivariable Regression Analysis.xlsx", db_lab),
         globs = c(
           file.path(unit, "step11_multivariate_prognosis/Tables", sprintf("Table S5-%s*.xlsx", db_lab)),
           file.path(tab, sprintf("Table S5-%s*.xlsx", db_lab))
         )),
    list(dest = sprintf("Table S6-%s. Multicollinearity Analysis (VIF, multivariate final).xlsx", db_lab),
         globs = c(
           file.path(unit, "step13_multicollinearity_final/Tables", sprintf("Table S6-%s*.xlsx", db_lab)),
           file.path(tab, "_archive", sprintf("Table S6-%s*.xlsx", db_lab)),
           file.path(tab, sprintf("Table S6-%s*.xlsx", db_lab))
         )),
    list(dest = sprintf("Table S7-%s. Baseline characteristics by trajectory class (%s).xlsx", db_lab, ix),
         globs = c(
           file.path(tab, sprintf("Table S7-%s*.xlsx", db_lab)),
           file.path(tab, "_archive", "Table_S5_Baseline_By_Class_*.xlsx"),
           file.path(unit, "step15_trajectory_baseline_by_class/Tables", "*.xlsx")
         )),
    list(dest = sprintf("Table 3-%s. Time-dependent HR for trajectory classes.xlsx", db_lab),
         globs = c(
           file.path(unit, "step20_trajectory_piecewise_cox/Tables", sprintf("Table 3-%s*.xlsx", db_lab)),
           file.path(tab, "_archive", sprintf("Table 2-%s*Time-dependent*.xlsx", db_lab)),
           file.path(tab, "_archive", sprintf("Table3 %s %s.xlsx", ix, tolower(db))),
           file.path(tab, "_archive", sprintf("Table3_%s_%s.xlsx", ix, tolower(db))),
           file.path(base_dir, "Tables", sprintf("Table 2-%s*Time-dependent*.xlsx", db_lab)),
           file.path(base_dir, "Tables", sprintf("Table3 %s %s.xlsx", ix, tolower(db)))
         ))
  )
  for (sp in specs) {
    ok <- .copy_newest(sp$globs, file.path(tab, sp$dest))
    message(if (ok) paste0("[OK] ", db, " ", sp$dest) else paste0("[MISS] ", db, " ", sp$dest))
  }
  invisible(TRUE)
}

.rebuild_t2_s8 <- function(db) {
  db_lab <- .db_lab(db)
  unit <- file.path(base_dir, db)
  tab <- file.path(unit, "Tables")
  rdata <- file.path(unit, "step14_trajectory_jlcm/Data", paste0("D01_jlcm_", ix, "_models.RData"))
  if (!file.exists(rdata)) {
    message("[MISS] models RData: ", rdata)
    return(invisible(FALSE))
  }
  env <- new.env(parent = emptyenv())
  load(rdata, envir = env)
  # 常见对象名
  pack <- NULL
  for (nm in c("models_list", "models", "jlcm_models", "pack", ls(env))) {
    obj <- env[[nm]]
    if (is.null(obj)) next
    if (is.list(obj) && !is.null(obj$models)) { pack <- obj; break }
    if (is.list(obj) && any(grepl("^m[0-9]+$", names(obj)))) {
      pack <- list(models = obj); break
    }
  }
  if (is.null(pack) || is.null(pack$models)) {
    if (exists("models_list_with_cov", envir = env, inherits = FALSE)) {
      pack <- list(models = env$models_list_with_cov)
    } else {
      for (nm in ls(env)) {
        obj <- env[[nm]]
        if (!is.list(obj)) next
        if (any(grepl("^m[0-9]+$", names(obj)))) {
          pack <- list(models = obj)
          break
        }
        if (is.list(obj$models) && any(grepl("^m[0-9]+$", names(obj$models)))) {
          pack <- obj
          break
        }
      }
    }
  }
  if (is.null(pack) || is.null(pack$models)) {
    message("[FAIL] cannot find models in ", rdata, " objs=", paste(ls(env), collapse = ","))
    return(invisible(FALSE))
  }
  ng_file <- file.path(tab, "Summary", paste0("optimal_ng_", ix, ".txt"))
  if (!file.exists(ng_file)) {
    ng_file <- file.path(unit, "step14_trajectory_jlcm/Tables/Summary", paste0("optimal_ng_", ix, ".txt"))
  }
  ng <- if (file.exists(ng_file)) as.integer(trimws(readLines(ng_file, warn = FALSE)[1L])) else 2L
  if (!is.finite(ng) || ng < 1L) ng <- 2L

  ctx <- list(results = list(), config = list(project = list(database = db_lab)))
  fp_t2 <- file.path(tab, sprintf("Table 2-%s. Metrics for determining the optimal number of classes.xlsx", db_lab))
  t2_title <- paste0("Table 2. Metrics for determining the optimal number of classes (", ix, ")")
  ok2 <- tryCatch({
    trajectory_export_table2_sci(ctx, pack$models, fp_t2, t2_title)
    TRUE
  }, error = function(e) {
    message("[FAIL] Table2 ", db, ": ", conditionMessage(e))
    FALSE
  })
  message(if (ok2) paste0("[OK] Table2 ", db) else paste0("[FAIL] Table2 ", db))

  m_sel <- pack$models[[paste0("m", ng)]]
  fp_s8 <- file.path(tab, sprintf("Table S8-%s. Posterior classification table.xlsx", db_lab))
  s8_title <- paste0("Table S8. Posterior classification table (", ix, ", ", db_lab, ")")
  ok8 <- tryCatch({
    trajectory_export_posterior_classification_sci(ctx, m_sel, fp_s8, s8_title)
    TRUE
  }, error = function(e) {
    message("[FAIL] TableS8 ", db, ": ", conditionMessage(e))
    FALSE
  })
  message(if (ok8) paste0("[OK] TableS8 ", db, " ng=", ng) else paste0("[FAIL] TableS8 ", db))
  invisible(ok2 && ok8)
}

.mirror_root <- function() {
  root_tab <- file.path(base_dir, "Tables")
  dir.create(root_tab, recursive = TRUE, showWarnings = FALSE)
  keep_re <- paste0(
    "^Table (1|2|3|S[1-8])-(eICU|MIMIC)\\. ",
    "(Baseline characteristics of Sepsis AKI|",
    "Metrics for determining the optimal number of classes|",
    "Time-dependent HR for trajectory classes|",
    "Baseline characteristics of patients before and after multiple imputation|",
    "Normality test results for continuous variables|",
    "Univariate Regression Analysis|",
    "Multicollinearity Analysis \\(VIF, univariate screen\\)|",
    "Multivariable Regression Analysis|",
    "Multicollinearity Analysis \\(VIF, multivariate final\\)|",
    "Baseline characteristics by trajectory class \\(GPR\\)|",
    "Posterior classification table)\\.xlsx$"
  )
  # 先清空根目录旧 xlsx（保留 Summary）
  old <- list.files(root_tab, pattern = "\\.xlsx$", full.names = TRUE)
  if (length(old)) unlink(old)
  n <- 0L
  for (db in c("eicu", "mimic")) {
    src_dir <- file.path(base_dir, db, "Tables")
    files <- list.files(src_dir, pattern = "^Table .*\\.xlsx$", full.names = TRUE)
    files <- files[!grepl("/_archive/", files)]
    files <- files[grepl(keep_re, basename(files))]
    for (f in files) {
      file.copy(f, file.path(root_tab, basename(f)), overwrite = TRUE)
      n <- n + 1L
    }
  }
  message("[OK] mirrored ", n, " xlsx → root Tables")
}

for (db in c("eicu", "mimic")) {
  message("==== restore ", db, " ====")
  .restore_unit_tables(db)
  message("==== rebuild T2/S8 ", db, " ====")
  .rebuild_t2_s8(db)
}

message("==== curate ====")
trajectory_curate_pub_outputs(
  base_dir = base_dir,
  index_name = ix,
  dbs = c("eicu", "mimic"),
  disease = disease
)

message("==== mirror root ====")
.mirror_root()

message("==== final listing ====")
print(sort(list.files(file.path(base_dir, "Tables"), pattern = "\\.xlsx$")))
print(sort(list.files(file.path(base_dir, "eicu", "Tables"), pattern = "\\.xlsx$")))
print(sort(list.files(file.path(base_dir, "mimic", "Tables"), pattern = "\\.xlsx$")))
message("done.")
