#!/usr/bin/env Rscript
# 重导 Table S5：两库变量与 Table 1 对齐，版式走 Table 1 guan 三线表
#   Rscript run/trajectory_prognosis/rebuild_ap_wpr_table_s5_like_table1.R

suppressPackageStartupMessages({
  library(gtsummary)
  library(dplyr)
})

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
if (!exists("register_block", mode = "function")) {
  register_block <- function(...) invisible(NULL)
}
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "Blocks/04_baseline/01block_baseline_binary.R"), local = FALSE)
source(file.path(.engine, "configs/config_trajectory_prognosis_ap_wpr_dual.R"))

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
stopifnot(dir.exists(index_root))

# 与已对齐 Table 1 同一变量顺序
include_vars <- c(
  "Age", "Gender", "Weight", "Height",
  "HR", "RR", "SpO2", "Temperature", "NBPS", "NBPD", "NBPM",
  "RBC", "Hematocrit", "Lymphocytes", "RDW", "ALT", "AST", "LD",
  "Albumin", "Bilirubin_Total", "BUN", "Creatinine",
  "Sodium", "Potassium", "AnionGap", "Glucose", "Total_Cholesterol",
  "Hypertension", "COPD", "CKD", "Hepatitis", "Pneumonia",
  "survival_time_28d", "WPR"
)
cat_vars <- c("Gender", "Hypertension", "COPD", "CKD", "Hepatitis", "Pneumonia")
force_iqr <- unique(c(
  as.character(config$baseline_binary$median_iqr_vars %||% character(0)),
  as.character(config$baseline_binary$force_continuous_vars %||% character(0)),
  "Age", "survival_time_28d", "WPR"
))

.rebuild_one <- function(db, db_lab) {
  ck <- file.path(
    block_root, "41_AP/Prognosis_Trajectory_38882552_WPR_dual",
    "checkpoints/by_index/WPR", db, "step01_trajectory_jlcm.rds"
  )
  stopifnot(file.exists(ck))
  pack <- readRDS(ck)
  data <- pack$ctx$data$imputed
  cls <- suppressWarnings(as.integer(gsub("\\D+", "", as.character(data$trajectory_class))))
  data$class_factor <- factor(cls, levels = c(1L, 2L), labels = c("Class 1", "Class 2"))
  data <- data[!is.na(data$class_factor), , drop = FALSE]
  vars <- include_vars[include_vars %in% names(data)]
  for (v in intersect(cat_vars, vars)) {
    data[[v]] <- factor(data[[v]])
  }
  cont_vars <- setdiff(vars, cat_vars)
  categorical_vars <- intersect(cat_vars, vars)
  is_norm <- vapply(cont_vars, function(v) {
    if (v %in% force_iqr) return(FALSE)
    .bb01_test_normality(suppressWarnings(as.numeric(data[[v]])))
  }, logical(1L))
  normal_vars <- cont_vars[is_norm]
  skewed_vars <- setdiff(cont_vars, normal_vars)

  stat_list <- c(
    setNames(rep(list("{mean} \u00b1 {sd}"), length(normal_vars)), normal_vars),
    setNames(rep(list("{median} ({p25}, {p75})"), length(skewed_vars)), skewed_vars)
  )
  cat_stat <- list(gtsummary::all_categorical() ~ "{n} ({p}%)")
  type_list <- c(
    lapply(cont_vars, function(v) stats::as.formula(paste0("`", v, "` ~ \"continuous\""))),
    lapply(categorical_vars, function(v) stats::as.formula(paste0("`", v, "` ~ \"categorical\"")))
  )
  fisher_vars <- categorical_vars[vapply(categorical_vars, function(v) {
    any(table(data[[v]], data$class_factor) < 5, na.rm = TRUE)
  }, logical(1L))]
  test_list <- c(
    setNames(lapply(normal_vars, function(v) "t.test"), normal_vars),
    setNames(lapply(skewed_vars, function(v) "wilcox.test"), skewed_vars),
    setNames(lapply(categorical_vars, function(v) {
      if (v %in% fisher_vars) "fisher.test" else "chisq.test"
    }), categorical_vars)
  )
  fisher_test_args <- if (length(fisher_vars)) {
    stats::setNames(
      rep(list(list(workspace = 2e8, simulate.p.value = TRUE, B = 2000)), length(fisher_vars)),
      fisher_vars
    )
  } else NULL

  dat_use <- data[, c("class_factor", vars), drop = FALSE]
  tbl_args <- list(
    data = dat_use,
    by = "class_factor",
    statistic = c(stat_list, cat_stat),
    digits = list(all_continuous() ~ 2, all_categorical() ~ c(0, 2)),
    missing = "no",
    type = type_list
  )
  tbl <- do.call(gtsummary::tbl_summary, tbl_args) %>%
    gtsummary::add_p(
      test = test_list,
      pvalue_fun = function(x) fmt_pval(x),
      test.args = fisher_test_args
    ) %>%
    gtsummary::add_overall() %>%
    gtsummary::bold_p(t = 0.05)

  cfg <- config
  cfg$project$database <- db_lab
  cfg$survival$index_var <- "WPR"
  cfg$baseline_binary$include_vars <- vars
  title_t1 <- sprintf(
    "Table S5-%s. Baseline characteristics by trajectory class (WPR)",
    db_lab
  )
  ctx <- list(
    config = cfg,
    data = list(imputed = data),
    results = list(),
    output_dir_tables = tab_root
  )
  ctx <- .bb01_export_table1(
    ctx, tbl, cfg$baseline_binary, cfg, data, 2L,
    normal_vars, skewed_vars, categorical_vars, fisher_vars, title_t1
  )
  fp <- file.path(tab_root, paste0(title_t1, ".xlsx"))
  if (!file.exists(fp)) {
    hits <- list.files(tab_root, pattern = sprintf("^Table S5-%s", db_lab), full.names = TRUE)
    fp <- hits[1L]
  }
  db_tab <- file.path(index_root, db, "Tables")
  dir.create(db_tab, recursive = TRUE, showWarnings = FALSE)
  if (file.exists(fp)) {
    file.copy(fp, file.path(db_tab, basename(fp)), overwrite = TRUE)
  }
  cli::cli_alert_success("[{db_lab}] Table S5 -> {basename(fp)}")
  invisible(fp)
}

fp_m <- .rebuild_one("mimic", "MIMIC")
fp_e <- .rebuild_one("eicu", "eICU")

# 行名对齐检查（去掉标题库标签）
.norm <- function(x) {
  x <- trimws(as.character(x %||% ""))
  x[is.na(x)] <- ""
  sub("-(MIMIC|eICU)\\.", ".", x)
}
am <- .norm(openxlsx::read.xlsx(
  file.path(tab_root, "Table S5-MIMIC. Baseline characteristics by trajectory class (WPR).xlsx"),
  colNames = FALSE
)[[1L]])
ae <- .norm(openxlsx::read.xlsx(
  file.path(tab_root, "Table S5-eICU. Baseline characteristics by trajectory class (WPR).xlsx"),
  colNames = FALSE
)[[1L]])
t1 <- .norm(openxlsx::read.xlsx(
  file.path(tab_root, "Table 1-MIMIC. Baseline characteristics of Acute pancreatitis.xlsx"),
  colNames = FALSE
)[[1L]])
cat("S5 MIMIC vs eICU first-col identical:", identical(am, ae), " rows", length(am), length(ae), "\n")
if (!identical(am, ae)) {
  cat("only MIMIC:", paste(setdiff(am, ae), collapse = " | "), "\n")
  cat("only eICU:", paste(setdiff(ae, am), collapse = " | "), "\n")
}
# Table 1 特征名（去掉 Overall 分组标题行）应与 S5 特征名一致
t1_body <- t1[-c(1L, 2L)]
s5_body <- am[-c(1L, 2L)]
cat("T1 vs S5 body identical:", identical(t1_body, s5_body), "\n")
if (!identical(t1_body, s5_body)) {
  cat("T1 extra:", paste(setdiff(t1_body, s5_body), collapse = " | "), "\n")
  cat("S5 extra:", paste(setdiff(s5_body, t1_body), collapse = " | "), "\n")
}
