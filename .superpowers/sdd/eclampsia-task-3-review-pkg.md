# Review package Task 3
-rw-r--r-- 1 root root 7503 Aug 21 14:20 /mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/config.R

## Grep risk patterns
27:  index_group     = "all",
90:## 发病 logistic（禁止 assoc_model="cox"）
91:config$ml_batch$assoc_model <- "logistic"
94:config$ml_models$methods <- c(
132:.disease_exclusion_vars <- c(
139:  disease_vars = .disease_exclusion_vars,
149:    .disease_exclusion_vars,
150:    "Gender"
155:  .disease_exclusion_vars, "Gender", "ID", "Group"
159:  .disease_exclusion_vars, "Gender"
163:  .disease_exclusion_vars, "Gender"
166:## 年龄亚组二分类 35（高龄产妇常用界）；禁止多档 age_group_cutoffs
168:  age_cutoff = 35L,
171:    "Gender"
177:config$subgroup$age_group_cutoffs <- NULL
179:  age_cutoff = 35L
182:  age_cutoff = 35L
184:config$nhanes$age_group_cutoffs <- NULL
188:  list(age_cutoff = 35L)
191:  age_cutoff = 35L
195:config$ml_batch$index_group <- "all"
200:config$ml_batch$parallel_workers <- 10L
230:rm(.disease_exclusion_vars)

## Full config.R
```r
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

source(file.path(
  Sys.getenv("MEDICAL_BLOCKS_ROOT"),
  "configs/study_interface/ml_dual_batch_build.R"
))

config$index$enable <- TRUE
config$index$only   <- NULL
config$index$digits <- 4L

## 发病 logistic（禁止 assoc_model="cox"）
config$ml_batch$assoc_model <- "logistic"

## tabfen → tabpfnv2（PMID 39780007 Nature TabPFN）；仅六模型
config$ml_models$methods <- c(
  "adaboost", "tabpfnv2", "catboost", "xgboost", "lightgbm", "rf"
)
config$ml_adaboost <- modifyList(config$ml_adaboost %||% list(), list(
  enable = TRUE,
  pause_enable = FALSE,
  limits = list(max_train_n = 349L)
))
config$ml_tabpfnv2 <- modifyList(config$ml_tabpfnv2 %||% list(), list(
  enable = TRUE,
  pause_enable = FALSE
))

.py_tabpfn <- "C:/ProgramData/anaconda3/python.exe"
config$ml_models$tabpfn_reticulate <- modifyList(
  config$ml_models$tabpfn_reticulate %||% list(),
  list(
    python = .py_tabpfn,
    device = "cpu",
    project_wd = Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
  )
)
Sys.setenv(
  HF_HUB_OFFLINE = "1",
  TRANSFORMERS_OFFLINE = "1",
  HF_DATASETS_OFFLINE = "1",
  TABPFN_ALLOW_CPU_LARGE_DATASET = "1",
  RETICULATE_PYTHON = .py_tabpfn,
  KMP_DUPLICATE_LIB_OK = "TRUE",
  APPDATA = "C:/Users/Administrator/AppData/Roaming",
  LOCALAPPDATA = "C:/Users/Administrator/AppData/Local",
  USERPROFILE = "C:/Users/Administrator",
  COMSPEC = "C:/Windows/System32/cmd.exe",
  SystemRoot = "C:/Windows"
)
rm(.py_tabpfn)

## Task 2 disease_vars（与 Data/_column_review.md 对齐）
.disease_exclusion_vars <- c(
  "Hypertension",
  "T1DM", "T2DM", "Diabetes", "Glucose", "HbA1c",
  "UrineProtein", "UrineGlucose", "AlbuminUrine", "AlbuminCreatinine",
  "UricAcid", "CKD", "Acute_Renal_Failure"
)
config$analysis_exclusion <- list(
  disease_vars = .disease_exclusion_vars,
  component_scope = "current_transitive",
  exclude_other_composite_indices = TRUE,
  exclude_exposure_if_uses_disease_var = TRUE
)
config$data_clean <- modifyList(config$data_clean %||% list(), list(
  missing_threshold = 0.3,
  age_filter = NULL,
  drop_columns = unique(c(
    as.character(config$data_clean$drop_columns %||% character(0)),
    .disease_exclusion_vars,
    "Gender"
  ))
))
config$baseline_binary$exclude_vars <- unique(c(
  as.character(config$baseline_binary$exclude_vars %||% character(0)),
  .disease_exclusion_vars, "Gender", "ID", "Group"
))
config$univariate_incidence_binary$excluded_predictors <- unique(c(
  as.character(config$univariate_incidence_binary$excluded_predictors %||% character(0)),
  .disease_exclusion_vars, "Gender"
))
config$imputation$table_s1_exclude_vars <- unique(c(
  as.character(config$imputation$table_s1_exclude_vars %||% character(0)),
  .disease_exclusion_vars, "Gender"
))

## 年龄亚组二分类 35（高龄产妇常用界）；禁止多档 age_group_cutoffs
config$subgroup <- modifyList(config$subgroup %||% list(), list(
  age_cutoff = 35L,
  forbid_subgroup_vars = unique(c(
    as.character(config$subgroup$forbid_subgroup_vars %||% character(0)),
    "Gender"
  )),
  level_order = list(
    Age_Group = c("< 35", "\u2265 35")
  )
))
config$subgroup$age_group_cutoffs <- NULL
config$subgroup_incidence <- modifyList(config$subgroup_incidence %||% list(), list(
  age_cutoff = 35L
))
config$nhanes <- modifyList(config$nhanes %||% list(), list(
  age_cutoff = 35L
))
config$nhanes$age_group_cutoffs <- NULL
config$nhanes$age_group_labels <- NULL
config$capability$sensitivity_suite <- modifyList(
  config$capability$sensitivity_suite %||% list(),
  list(age_cutoff = 35L)
)
config$subgroup_fallback <- modifyList(config$subgroup_fallback %||% list(), list(
  age_cutoff = 35L
))

config$ml_batch$index_mode <- "single_loop"
config$ml_batch$index_group <- "all"
config$ml_batch$index_vars <- NULL
config$ml_batch$db_mode <- "nhanes"
config$ml_batch$fail_policy <- "continue"
config$ml_batch$skip_existing <- TRUE
config$ml_batch$parallel_workers <- 10L
config$ml_batch$max_workers <- 10L
config$ml_batch$min_valid_per_db <- 30L
config$ml_batch$ram_per_worker_gb <- 3.0
config$incidence_batch <- config$ml_batch

config$assoc_covariate <- modifyList(config$assoc_covariate %||% list(), list(
  enable = TRUE,
  force_model1 = "Age",
  uv_source = "tb1",
  max_model2_extra = Inf,
  allow_m2_eq_m1 = TRUE
))

config$imputation <- modifyList(config$imputation %||% list(), list(
  fit_on = "train",
  method = config$imputation$method %||% "cart",
  m = as.integer(config$imputation$m %||% 5L),
  max_iter = as.integer(config$imputation$max_iter %||% 5L)
))
config$train_validation <- modifyList(config$train_validation %||% list(), list(
  enable = TRUE,
  export_baseline_table = FALSE,
  max_resplit_iter = 150L
))
config$plot <- modifyList(config$plot %||% list(), list(
  font_family = "Times New Roman",
  pdf_device = "cairo_pdf"
))
config$feishu$enable <- FALSE
rm(.disease_exclusion_vars)
```
