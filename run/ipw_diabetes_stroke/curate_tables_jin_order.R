#!/usr/bin/env Rscript
# 整理用药 IPW 汇总表：只保留 Jin 对齐的 5 张
#   Table 1  = sIPTW 基线
#   Table S1 = Uno's C-index
#   Table S2 = 多重插补前后基线
#   Table S3 = 单因素回归
#   Table S4 = VIF
suppressPackageStartupMessages({
  if (!requireNamespace("cli", quietly = TRUE)) stop("need cli")
})

proj <- "G:/02block_result/11_ischemic stroke/Medication_regimen_model_42118193"
# WSL 也可
if (!dir.exists(proj)) {
  proj <- "/mnt/g/02block_result/11_ischemic stroke/Medication_regimen_model_42118193"
}
unit_tbl <- file.path(proj, "by_unit", "\u3010success\u3011main", "Tables")
root_tbl <- file.path(proj, "Tables")
stopifnot(dir.exists(unit_tbl))
dir.create(root_tbl, recursive = TRUE, showWarnings = FALSE)

.pick <- function(dir, pattern) {
  fs <- list.files(dir, pattern = pattern, full.names = TRUE, ignore.case = TRUE)
  fs <- fs[file.exists(fs) & !grepl("\\.tex$", fs, ignore.case = TRUE)]
  if (!length(fs)) return(NA_character_)
  fs[order(file.info(fs)$mtime, decreasing = TRUE)][[1L]]
}

.dest_names <- list(
  t1 = "Table 1-MIMIC. Baseline characteristics before and after sIPTW.xlsx",
  s1 = "Table S1-MIMIC. The Uno's concordance index at 28-day.xlsx",
  s2 = "Table S2-MIMIC. Baseline characteristics of patients before and after multiple imputation.xlsx",
  s3 = "Table S3-MIMIC. Univariate Regression Analysis.xlsx",
  s4 = "Table S4-MIMIC. Multicollinearity Analysis (VIF, univariate screen) for ischemic_stroke_ipw_diabetes.xlsx"
)

srcs <- list(
  t1 = .pick(unit_tbl, "Table 1.*Baseline characteristics before and after sIPTW\\.xlsx$"),
  s1 = .pick(unit_tbl, "Uno.*concordance|concordance index.*\\.xlsx$"),
  s2 = .pick(unit_tbl, "Baseline characteristics of patients before and after multiple imputation\\.xlsx$"),
  s3 = .pick(unit_tbl, "Univariate Regression Analysis\\.xlsx$"),
  s4 = .pick(unit_tbl, "Multicollinearity Analysis.*\\.xlsx$")
)

tmpdir <- file.path(tempdir(), "ipw_tbl_curate")
unlink(tmpdir, recursive = TRUE)
dir.create(tmpdir, recursive = TRUE)

for (k in names(srcs)) {
  src <- srcs[[k]]
  if (is.na(src) || !file.exists(src)) {
    stop("缺少源表 ", k, ": ", .dest_names[[k]], call. = FALSE)
  }
  file.copy(src, file.path(tmpdir, .dest_names[[k]]), overwrite = TRUE)
  cli::cli_alert_success("staged {k}: {basename(src)} -> {(.dest_names[[k]])}")
}

# 清空 unit Tables，只写回 5 张
old <- list.files(unit_tbl, full.names = TRUE)
unlink(old)
for (nm in .dest_names) {
  file.copy(file.path(tmpdir, nm), file.path(unit_tbl, nm), overwrite = TRUE)
}

# 根目录 Tables 同步为同一套 5 张（去掉 batch 汇总等）
old_root <- list.files(root_tbl, full.names = TRUE)
unlink(old_root)
for (nm in .dest_names) {
  file.copy(file.path(tmpdir, nm), file.path(root_tbl, nm), overwrite = TRUE)
}

cli::cli_h2("unit Tables/")
print(list.files(unit_tbl))
cli::cli_h2("root Tables/")
print(list.files(root_tbl))
quit(status = 0)
