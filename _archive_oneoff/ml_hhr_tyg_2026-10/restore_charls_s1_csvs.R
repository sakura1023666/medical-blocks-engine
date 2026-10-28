#!/usr/bin/env Rscript
# 恢复原 keycols，并把 Table1 版另存为新文件（不覆盖原名用途）。
# 优先用 inspect_pack 里已有的 Table1 宽表做列切分，避免再读巨大 checkpoint。

args <- commandArgs(trailingOnly = TRUE)
data_dir <- if (length(args)) args[[1L]] else {
  if (.Platform$OS.type == "windows") {
    "G:/02block_result/23_circadian rhythm/cross_laged_shehui_1008/reports/CHARLS_TableS1_inspect_pack/data"
  } else {
    "/mnt/g/02block_result/23_circadian rhythm/cross_laged_shehui_1008/reports/CHARLS_TableS1_inspect_pack/data"
  }
}
data_dir <- normalizePath(data_dir, winslash = "/", mustWork = TRUE)
message("data_dir = ", data_dir)

orig_cols <- c(
  "ID", "Leisure_score", "Leisure_tertile", "Disease_Group", "outcome_01",
  "Age", "Gender", "Weight", "Height", "WBC",
  "Education", "Marital_Status", "Smoking", "Alcohol_drinking", "BMI"
)
t1_vars <- c(
  "Age", "Gender", "Education", "Marital_Status", "Smoking", "Alcohol_drinking",
  "Weight", "Height", "Waist_circumference", "BMI", "SBP", "DBP", "WBC",
  "Hemoglobin", "Glucose", "HbA1c", "Total_Cholesterol", "Triglycerides",
  "LDL", "HDL", "Hypertension", "Diabetes", "Hyperlipidemia", "Leisure_score"
)
prefix <- c("ID", "Disease_Group", "outcome_01", "Leisure_tertile")
t1_cols <- unique(c(prefix, t1_vars))

path_imp <- file.path(data_dir, "CHARLS_TableS1_analysis_keycols.csv")
path_miss <- file.path(data_dir, "CHARLS_TableS1_analysis_keycols_with_missing.csv")
imp <- utils::read.csv(path_imp, stringsAsFactors = FALSE, fileEncoding = "UTF-8", na.strings = c("", "NA"))
miss <- utils::read.csv(path_miss, stringsAsFactors = FALSE, fileEncoding = "UTF-8", na.strings = c("", "NA"))

# 若当前已是 Table1 宽表：先另存新名，再切回窄列写回原名
has_t1 <- all(t1_vars %in% names(imp)) && all(t1_vars %in% names(miss))
if (!has_t1) {
  stop(
    "当前 keycols 不是 Table1 宽表，无法仅靠 CSV 切分。\n",
    "现有列: ", paste(names(imp), collapse = ", "),
    call. = FALSE
  )
}

# 新文件（Table1）
p_new_imp <- file.path(data_dir, "CHARLS_TableS1_table1_baseline_imputed.csv")
p_new_miss <- file.path(data_dir, "CHARLS_TableS1_table1_baseline_with_missing.csv")
utils::write.csv(imp[, t1_cols, drop = FALSE], p_new_imp, row.names = FALSE, fileEncoding = "UTF-8", na = "")
utils::write.csv(miss[, t1_cols, drop = FALSE], p_new_miss, row.names = FALSE, fileEncoding = "UTF-8", na = "")

# 恢复原窄列文件名
utils::write.csv(imp[, orig_cols, drop = FALSE], path_imp, row.names = FALSE, fileEncoding = "UTF-8", na = "")
utils::write.csv(miss[, orig_cols, drop = FALSE], path_miss, row.names = FALSE, fileEncoding = "UTF-8", na = "")

summ <- data.frame(
  column = t1_cols,
  n = nrow(miss),
  n_missing = vapply(miss[, t1_cols, drop = FALSE], function(z) sum(is.na(z)), integer(1)),
  stringsAsFactors = FALSE
)
summ$pct_missing <- round(100 * summ$n_missing / summ$n, 2)
utils::write.csv(
  summ,
  file.path(data_dir, "CHARLS_TableS1_table1_baseline_missing_summary.csv"),
  row.names = FALSE
)

message("Restored narrow: ", basename(path_imp), " / ", basename(path_miss), " (ncol=", length(orig_cols), ")")
message("Wrote new:       ", basename(p_new_imp), " / ", basename(p_new_miss), " (ncol=", length(t1_cols), ")")
message("N = ", nrow(imp))
