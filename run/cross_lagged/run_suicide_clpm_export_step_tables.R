#!/usr/bin/env Rscript
# One-shot: export SCI three-line tables for existing step01 / step02 products.
# Usage:
#   CROSS_LAGGED_STUDY_ROOT=... Rscript run/cross_lagged/run_suicide_clpm_export_step_tables.R

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
if (basename(script_path) == "cross_lagged" && basename(dirname(script_path)) == "run") {
  engine_root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  engine_root <- normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), winslash = "/")
}
setwd(engine_root)

study_root <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")
if (!nzchar(study_root)) stop("Set CROSS_LAGGED_STUDY_ROOT", call. = FALSE)
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)

source(file.path(engine_root, "R/utils.R"), local = FALSE)
source(file.path(engine_root, "run/cross_lagged/suicide_clpm_step_sci_tables.R"), local = FALSE)

.table_queue_env$items <- list()

s1 <- file.path(study_root, "step01_data_clean")
s2 <- file.path(study_root, "step02_imputation")
if (dir.exists(s1)) {
  message("[export] step01 → ", s1)
  suicide_clpm_export_step01_tables(s1)
}
if (dir.exists(s2)) {
  message("[export] step02 → ", s2)
  suicide_clpm_export_step02_tables(s2)
}
suicide_clpm_flush_sci_tables()

# Convention note at study root
note <- c(
  "# SCI 三线表约定（本课题逐步运行）",
  "",
  "每一步产物目录下必须有 `Tables/`，内存 `export_sci_table` 生成的 SCI 三线表 xlsx。",
  "",
  "| Step | 目录 | Tables 内容 |",
  "|------|------|-------------|",
  "| step01_data_clean | `step01_data_clean/Tables/` | 纳排 / 节点完整 / QC |",
  "| step02_imputation | `step02_imputation/Tables/` | 插补前后缺失 / MICE 变量 / 禁插补 / 方法说明 |",
  "| 后续 step03+ | `stepNN_*/Tables/` | 同规则：本步主表必须三线表落盘 |",
  "",
  "中间 csv 可保留；发表级查看以 `Tables/*.xlsx` 为准。",
  "实现：`run/cross_lagged/suicide_clpm_step_sci_tables.R`"
)
writeLines(note, file.path(study_root, "STEP_SCI_TABLES.md"), useBytes = TRUE)
message("[export] wrote STEP_SCI_TABLES.md")
message("[export] DONE")
