#!/usr/bin/env Rscript
# 脓毒症AKI · TCF 双库 batch（薄封装 → run/ml/run_ml_dual_batch.R）
#
#   "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#     run/ml_tcf_sepsis_aki/01_prepare_analytic_dabiao.R
#   "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#     run/ml_tcf_sepsis_aki/run_ml_tcf_sa_aki_batch.R --shared-only
#   同上 --workers 2

script_path <- tryCatch({
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}, error = function(e) normalizePath(getwd(), winslash = "/"))
root <- if (basename(script_path) == "ml_tcf_sepsis_aki") {
  normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else script_path
setwd(root)
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)
Sys.setenv(MEDICAL_BLOCKS_SKIP_PIPELINE_GUARD = "1")

args <- commandArgs(trailingOnly = TRUE)
cfg_default <- "G:/02block_result/42_AKI_spesis/multi-algorithm fusion_40295871/config_ml_tcf_sa_aki.R"
if (!"--config" %in% args) {
  args <- c("--config", cfg_default, args)
}
## 含空格路径：同时写环境变量，避免 WSL↔Windows Rscript argv 截断
Sys.setenv(MEDICAL_BLOCKS_CONFIG = cfg_default)

rscript <- if (.Platform$OS.type == "windows") {
  file.path(R.home("bin"), "Rscript.exe")
} else if (file.exists("/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe")) {
  "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
} else {
  Sys.which("Rscript")
}

## 凡调 Windows Rscript（含本机 Windows / WSL 互调），含空格参数逐参加引号
.win_q <- function(x) {
  x <- as.character(x)
  vapply(x, function(a) {
    if (!nzchar(a)) return('""')
    if (grepl("[[:space:]]", a) || grepl('"', a, fixed = TRUE)) {
      paste0('"', gsub('"', '\\"', a, fixed = TRUE), '"')
    } else a
  }, character(1), USE.NAMES = FALSE)
}
argv <- c(file.path(root, "run/ml/run_ml_dual_batch.R"), args)
if (grepl("Rscript\\.exe$", rscript, ignore.case = TRUE)) {
  argv <- .win_q(argv)
}

status <- system2(
  rscript,
  args = argv,
  wait = TRUE,
  env = c(
    paste0("MEDICAL_BLOCKS_ROOT=", root),
    "MEDICAL_BLOCKS_SKIP_PIPELINE_GUARD=1",
    paste0("MEDICAL_BLOCKS_CONFIG=", cfg_default)
  )
)
quit(status)
