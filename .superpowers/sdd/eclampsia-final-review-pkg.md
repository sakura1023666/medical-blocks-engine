# Final review package — eclampsia by_index ML
## Deliverables
-rw-r--r-- 1 root root   6236 Aug 21 14:12 /mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/_column_review.md
-rw-r--r-- 1 root root 125020 Aug 21 14:01 /mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/mimic/D04_dabiao.RData
-rw-r--r-- 1 root root   1072 Aug 21 13:59 /mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/build_merged_data.R
-rw-r--r-- 1 root root   7503 Aug 21 14:20 /mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/config.R

## by_index summary
non-failed: 22
failed: 20
non-failed names:
ALBI
ANLR
APRI
BAR
CAR
De_Ritis
FIB4
HALP
HHR
HRR
LAR
MCH
MCHC
MCV
NLPR
PLR
PNI
RAR
RDW_CV
SII
WPR
log2LAR

## Ledger
# SDD Progress Ledger

Plan: docs/superpowers/plans/2026-08-21-eclampsia-mimic-ml-incidence-by-index.md
Note: workspace has no .git — commits skipped; track via this ledger + file presence + review reports.

Task 1: complete (no git; D04_dabiao n=4756 events=482; review Approved)
Task 1: complete (no git; D04_dabiao n=4756 events=482; review Approved)
Task 1: complete (no git; D04_dabiao n=4756 events=482; review Approved)
Task 1: complete (no git; D04_dabiao n=4756 events=482; review Approved)
Task 1: complete (no git; D04_dabiao n=4756 events=482; review Approved)
Task 2: complete (76/76 cols; disease_vars n=13; review Approved)

Task 2: complete (config_incidence_single.R; dry-source OK)
Task 3: complete (config.R CONFIG PASS; review Approved; TabPFN Windows path noted)
Task 3: complete (config.R CONFIG PASS; review Approved; TabPFN Windows path noted)
Task 4: complete (batch launched workers=10 db=nhanes; many early status=error — follow-up)

## config.R head
###############################################################################
#  27 eclampsia — MIMIC 单库发病 ML by_index（PMID 39780007 六模型）
#  结局：子痫发病（DN；Case / Control）
#  年龄切点依据：高龄产妇常用界 35 岁
#
#  数据:
#    Data/mimic/D04_dabiao.RData → dabiao（n=4756；DN 事件=482）
#
#  模型: adaboost, tabpfnv2, catboost, xgboost, lightgbm, rf
#  运行:
#    MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
#    Rscript run/ml/run_ml_dual_batch.R \
#      --config "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/config.R" \
#      --workers 10 --db nhanes
###############################################################################

if (!exists("%||%", mode = "function"))
  `%||%` <- function(a, b) if (!is.null(a)) a else b

.study <- list(
  disease_code    = "27",
  disease         = "eclampsia",
  literature_pmid = "39780007",
  analysis_group  = "Case",
  reference_group = "Control",

  index_group     = "all",
  index_vars      = NULL,

  outcome_column  = "DN",
  id_column       = "ID",

  primary_name             = "MIMIC_IV",
  primary_db_type          = "regular",
  primary_subdir           = "mimic",
  primary_rdata_file       = "D04_dabiao.RData",
  primary_rdata_obj        = "dabiao",
  primary_column_mapping   = "MIMIC",

  ## 单库：次库槽位指向同一份文件，db_mode=nhanes 只跑主库
  secondary_name             = "UNUSED",
  secondary_db_type          = "regular",
  secondary_subdir           = "mimic",
  secondary_rdata_file       = "D04_dabiao.RData",
  secondary_rdata_obj        = "dabiao",
  secondary_column_mapping   = "MIMIC",

  merge_dual_db_tables        = FALSE,
  mirror_aggregate_prefix_db  = FALSE,
  baseline_early_stop_disable = TRUE,
  apply_nhanes_upstream       = FALSE,

  disease_config_preset = "psoriasis",
  feishu_enable         = FALSE
)

.study_config_file <- {
  ca <- commandArgs(trailingOnly = TRUE)
  i  <- match("--config", ca)
  if (!is.na(i) && i < length(ca))
    normalizePath(ca[[i + 1L]], winslash = "/", mustWork = TRUE)
  else {
    ## source(config.R) 时无 --config：从 ofile 取本文件路径
    .of <- NULL
    for (.i in seq_len(sys.nframe())) {
      .of <- sys.frame(.i)$ofile
      if (!is.null(.of) && nzchar(.of)) break
    }
    if (!is.null(.of) && nzchar(.of))
      normalizePath(.of, winslash = "/", mustWork = TRUE)
    else
      NA_character_
  }
}
.batch_project_root <- if (!is.na(.study_config_file)) {
  dirname(.study_config_file)
} else {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

