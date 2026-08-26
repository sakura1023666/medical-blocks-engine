### Task 3: 写 `config.R`（发病 + 六模型 + age 35 + 10 workers）

**Files:**
- Create: `/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/config.R`

**Interfaces:**
- Consumes: Task 2 的 `.disease_exclusion_vars`；`Data/mimic/D04_dabiao.RData`
- Produces: sourceable `config` list，`ml_batch$db_mode="nhanes"`，`methods` 长度 6

- [ ] **Step 1: 创建 config.R（完整内容）**

以卵巢癌 config 为骨架，关键差异如下（实施时写完整文件，勿留 cox 段）：

```r
###############################################################################
#  27 eclampsia — MIMIC 单库发病 ML by_index（PMID 39780007 六模型）
#  年龄切点依据：高龄产妇常用界 35 岁
#  运行:
#    MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
#    Rscript run/ml/run_ml_dual_batch.R \
#      --config "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/config.R" \
#      --workers 10 --db nhanes
###############################################################################

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

# … .study_config_file / .batch_project_root 同卵巢癌 …
# source ml_dual_batch_build.R

config$index$enable <- TRUE
config$index$only   <- NULL
config$index$digits <- 4L

# 发病：不要 assoc_model="cox"；build 默认 study_type=incidence
config$ml_batch$assoc_model <- "logistic"

config$ml_models$methods <- c(
  "adaboost", "tabpfnv2", "catboost", "xgboost", "lightgbm", "rf"
)
# TabPFN / Sys.setenv 段同卵巢癌（Windows python 路径）

.disease_exclusion_vars <- c( /* 粘贴 Task 2 名单 */ )
config$analysis_exclusion <- list(
  disease_vars = .disease_exclusion_vars,
  component_scope = "current_transitive",
  exclude_other_composite_indices = TRUE,
  exclude_exposure_if_uses_disease_var = TRUE
)
# data_clean / baseline_binary / univariate / imputation 同步排除 + Gender

# 年龄亚组二分类 35
config$subgroup <- modifyList(config$subgroup %||% list(), list(
  age_cutoff = 35L,
  level_order = list(
    Age_Group = c("< 35", "\u2265 35")
  )
))
config$subgroup_incidence <- modifyList(config$subgroup_incidence %||% list(), list(
  age_cutoff = 35L
))
config$nhanes <- modifyList(config$nhanes %||% list(), list(
  age_cutoff = 35L
))
# 确认无 age_group_cutoffs

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
config$feishu$enable <- FALSE
```

- [ ] **Step 2: dry-load config**

```bash
export MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final
Rscript -e '
Sys.setenv(MEDICAL_BLOCKS_ROOT="/mnt/e/01block/01Block-new-Final")
source("/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/config.R")
stopifnot(identical(config$project$study_type, "incidence"))
stopifnot(identical(config$ml_batch$assoc_model, "logistic"))
stopifnot(length(config$ml_models$methods)==6L)
stopifnot(identical(as.integer(config$subgroup$age_cutoff), 35L))
stopifnot(is.null(config$subgroup$age_group_cutoffs))
cat("CONFIG PASS\n")
'
```

Expected: `CONFIG PASS`

---

