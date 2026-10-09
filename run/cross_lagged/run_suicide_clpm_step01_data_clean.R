#!/usr/bin/env Rscript
# =============================================================================
# step01_data_clean — 门诊入组 + 六节点 complete（CLPM 纳排）
#
# 本步只做：has_ID → 门诊入组 → 六节点 listwise complete。
# 不做：analysis_exclusion / imputation / UV / paths。
#
# 用法:
#   CROSS_LAGGED_STUDY_ROOT=/mnt/g/02block_result/43_Suicide/cross-laged_40595747 \
#     Rscript run/cross_lagged/run_suicide_clpm_step01_data_clean.R
#   # 强制重跑 prep（改节点定义如 CSSRS item2 后必加）:
#   ... Rscript ... --force-prep
#
# 产出（研究区）:
#   step01_data_clean/
#     dabiao.RData / attrition.csv / prep_qc.csv / step_meta.csv / README.md
# =============================================================================

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

force_prep <- "--force-prep" %in% commandArgs(trailingOnly = TRUE)

study_root <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")
if (!nzchar(study_root)) {
  stop(
    "Set CROSS_LAGGED_STUDY_ROOT to the study root ",
    "(e.g. /mnt/g/02block_result/43_Suicide/cross-laged_40595747)",
    call. = FALSE
  )
}
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)
Sys.setenv(CROSS_LAGGED_STUDY_ROOT = study_root, MEDICAL_BLOCKS_ROOT = engine_root)

step_dir <- file.path(study_root, "step01_data_clean")
dir.create(step_dir, recursive = TRUE, showWarnings = FALSE)
harm <- file.path(study_root, "data/harmonized")
src_rdata <- file.path(harm, "D04_outpatient_clpm.RData")
src_attr <- file.path(harm, "attrition_outpatient.csv")
src_qc <- file.path(harm, "prep_qc.csv")

message("[step01_data_clean] study_root = ", study_root)
message("[step01_data_clean] step_dir   = ", step_dir)

need_prep <- isTRUE(force_prep) || !all(file.exists(c(src_rdata, src_attr, src_qc)))
if (need_prep) {
  message("[step01_data_clean] running prep (merge + outpatient + six-node complete)...")
  prep_script <- file.path(engine_root, "scripts/prep_cross_lagged_suicide_cssrs.R")
  if (!file.exists(prep_script)) stop("Missing prep script: ", prep_script)
  prep_env <- new.env(parent = globalenv())
  sys.source(prep_script, envir = prep_env)
} else {
  message("[step01_data_clean] reuse existing harmonized products (pass --force-prep to rebuild)")
}

for (p in c(src_rdata, src_attr, src_qc)) {
  if (!file.exists(p)) stop("Expected product missing: ", p, call. = FALSE)
}

ok_copy <- function(from, to) {
  if (!file.copy(from, to, overwrite = TRUE)) stop("copy failed: ", from, " -> ", to)
}
ok_copy(src_rdata, file.path(step_dir, "dabiao.RData"))
ok_copy(src_attr, file.path(step_dir, "attrition.csv"))

qc <- utils::read.csv(src_qc, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
qc_out <- qc[qc$cohort == "门诊入组", , drop = FALSE]
utils::write.csv(qc_out, file.path(step_dir, "prep_qc.csv"), row.names = FALSE, fileEncoding = "UTF-8")

e <- new.env(parent = emptyenv())
load(file.path(step_dir, "dabiao.RData"), envir = e)
dabiao <- e$dabiao
nodes <- c("HAMD_Index", "HAMD_1st", "HAMA_Index", "HAMA_1st", "CSSRS_Index", "CSSRS_1st")
stopifnot(is.data.frame(dabiao), nrow(dabiao) > 0L)
stopifnot(all(nodes %in% names(dabiao)))
stopifnot(all(dabiao$patient_group == "门诊入组", na.rm = TRUE))
stopifnot(all(stats::complete.cases(dabiao[, nodes, drop = FALSE])))

attr_tbl <- utils::read.csv(file.path(step_dir, "attrition.csv"), stringsAsFactors = FALSE)
n_final <- as.integer(attr_tbl$n_remain[attr_tbl$step == "six_nodes_complete"][1L])
stopifnot(identical(as.integer(nrow(dabiao)), n_final))

meta <- data.frame(
  step = "step01_data_clean",
  block = "data_clean",
  cohort = "outpatient",
  n = nrow(dabiao),
  n_cols = ncol(dabiao),
  nodes = paste(nodes, collapse = ","),
  cssrs_item = 2L,
  cssrs_cols = "C_SSRS_Ideation_index_2,C_SSRS_Ideation_1st_2",
  source = if (need_prep) "prep_rebuilt" else "harmonized_reuse",
  skipped = "analysis_exclusion,imputation,univariate,vif,clpm_paths",
  written_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  stringsAsFactors = FALSE
)
utils::write.csv(meta, file.path(step_dir, "step_meta.csv"), row.names = FALSE, fileEncoding = "UTF-8")

readme <- c(
  "# step01_data_clean",
  "",
  "等价 block：`data_clean`（本课题 CLPM 纳排）。",
  "",
  "## 本步规则",
  "",
  "1. `has_ID`：合并后非缺失 `新编号`",
  "2. `group_门诊入组`：`patient_group == 门诊入组`",
  "3. `six_nodes_complete`：六节点 listwise complete（CSSRS **item2** 主动自杀想法，已编码 0/1）",
  "",
  paste0("- **最终 n = ", nrow(dabiao), "**（见 `attrition.csv`；含逐步 require_* 明细）"),
  "",
  "## 产物",
  "",
  "| 文件 | 说明 |",
  "|------|------|",
  "| `dabiao.RData` | 对象 `dabiao`，门诊六节点完整集；CSSRS=item2 |",
  "| `Tables/*.xlsx` | SCI 三线表（纳排 / 节点完整 / QC） |",
  "| `attrition.csv` | 逐步保留 / 排除人数（中间文件） |",
  "| `prep_qc.csv` | 门诊 QC |",
  "| `step_meta.csv` | 本步元数据 |",
  "",
  "## 明确未做（下一步再跑）",
  "",
  "- `analysis_exclusion`",
  "- `imputation`",
  "- UV / VIF / CLPM paths",
  "",
  paste0("CSSRS 源列：`C_SSRS_Ideation_index_2` / `C_SSRS_Ideation_1st_2`。"),
  paste0("同步源：`data/harmonized/D04_outpatient_clpm.RData`。"),
  paste0("写入时间：", meta$written_at)
)
writeLines(readme, file.path(step_dir, "README.md"), useBytes = TRUE)

# SCI three-line tables → step01_data_clean/Tables/
source(file.path(engine_root, "R/utils.R"), local = FALSE)
source(file.path(engine_root, "run/cross_lagged/suicide_clpm_step_sci_tables.R"), local = FALSE)
.table_queue_env$items <- list()
suicide_clpm_export_step01_tables(step_dir, n_final = nrow(dabiao))
suicide_clpm_flush_sci_tables()
message("[step01_data_clean] SCI tables → ", file.path(step_dir, "Tables"))

message("[step01_data_clean] OK n=", nrow(dabiao), " cols=", ncol(dabiao))
message("[step01_data_clean] wrote ", step_dir)
print(attr_tbl, row.names = FALSE)
