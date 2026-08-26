# 子痫 MIMIC by_index 发病 ML Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `27_eclampsia/small sample prediction_39780007` 上合并 dabiao、写发病 ML config（全部可算复合指标 by_index、六模型、年龄切点 35、10 路并行）并启动批量跑通。

**Architecture:** 对齐卵巢癌同 PMID 单库小样本：`D01+D03→D04_dabiao` → `config.R`（`ml_dual_batch_build` + incidence 覆盖）→ `run_ml_dual_batch.R --workers 10 --db nhanes`。不改主仓引擎；产物全在课题目录。

**Tech Stack:** R 4.5.1（优先 Windows `Rscript.exe`）、`run/ml/run_ml_dual_batch.R`、TabPFN（`C:/ProgramData/anaconda3/python.exe`）、MIMIC 单库。

## Global Constraints

- 课题根：`/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/`
- 主仓：`/mnt/e/01block/01Block-new-Final`（`MEDICAL_BLOCKS_ROOT`）
- 仅六模型：`adaboost`, `tabpfnv2`, `catboost`, `xgboost`, `lightgbm`, `rf`
- `index_group=all`，`index_vars=NULL`，10 workers，`fail_policy=continue`
- 发病 logistic（禁止 `assoc_model="cox"`）
- `age_cutoff=35`；`Age_Group` 仅 `"< 35"` / `"≥ 35"`；禁止多档 `age_group_cutoffs`
- 全女性：`Gender` 进 drop/exclude
- 无 git：跳过所有 commit 步骤
- Spec：`docs/superpowers/specs/2026-08-21-eclampsia-mimic-ml-incidence-by-index-design.md`

---

## File map

| 路径 | 职责 |
|------|------|
| `…/Data/mimic/D04_dabiao.RData` | 分析用 dabiao（新建） |
| `…/Data/_column_review.md` | 逐列审阅（新建） |
| `…/build_merged_data.R` | 可复现合并脚本（新建） |
| `…/config.R` | 程序员 config（新建） |
| `run/ml/run_ml_dual_batch.R` | 只调用，不改 |

---

### Task 1: 合并 D04_dabiao + 冒烟检查

**Files:**
- Create: `/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/build_merged_data.R`
- Create: `/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/mimic/D04_dabiao.RData`

**Interfaces:**
- Consumes: `data/D01_baseline_MIMIC_GW_0804.RData` (`baseline`), `data/D03_result_子痫_MIMIC(1).RData` (`result`)
- Produces: `dabiao` data.frame，列含 `ID`, `DN`, 基线全部列；`nrow==4756`，`sum(DN==1)==482`

- [ ] **Step 1: 写合并脚本**

```r
# build_merged_data.R
.root <- if (nzchar(Sys.getenv("ECLAMPSIA_STUDY_ROOT"))) {
  Sys.getenv("ECLAMPSIA_STUDY_ROOT")
} else {
  normalizePath(dirname(sys.frame(1)$ofile %||% "."), winslash = "/", mustWork = FALSE)
}
# 稳定写法：相对本脚本
.args <- commandArgs(trailingOnly = FALSE)
.file <- sub("^--file=", "", grep("^--file=", .args, value = TRUE)[1])
.root <- if (length(.file) && nzchar(.file) && !is.na(.file)) {
  dirname(normalizePath(.file, winslash = "/"))
} else getwd()

dir.create(file.path(.root, "Data", "mimic"), recursive = TRUE, showWarnings = FALSE)

load(file.path(.root, "data", "D01_baseline_MIMIC_GW_0804.RData"))
load(file.path(.root, "data", "D03_result_子痫_MIMIC(1).RData"))

stopifnot(exists("baseline"), exists("result"))
dabiao <- merge(result, baseline, by.x = "subject_id", by.y = "ID", all.x = TRUE)
names(dabiao)[names(dabiao) == "subject_id"] <- "ID"
stopifnot(nrow(dabiao) == 4756L)
stopifnot(sum(dabiao$DN == 1L, na.rm = TRUE) == 482L)
stopifnot(!anyDuplicated(dabiao$ID))

save(dabiao, file = file.path(.root, "Data", "mimic", "D04_dabiao.RData"))
message("OK dabiao n=", nrow(dabiao), " events=", sum(dabiao$DN == 1))
```

- [ ] **Step 2: 运行合并**

```bash
cd "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007"
Rscript build_merged_data.R
```

Expected: `OK dabiao n=4756 events=482`；`Data/mimic/D04_dabiao.RData` 存在。

- [ ] **Step 3: 验证**

```bash
Rscript -e 'load("/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/mimic/D04_dabiao.RData"); stopifnot(nrow(dabiao)==4756, sum(dabiao$DN==1)==482); cat("PASS\n")'
```

Expected: `PASS`

---

### Task 2: 逐列审阅 → `_column_review.md` + disease_vars

**Files:**
- Create: `/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/_column_review.md`

**Interfaces:**
- Consumes: `dabiao` 全列名
- Produces: 审阅表；`.disease_exclusion_vars` 字符向量供 Task 3 粘贴

- [ ] **Step 1: 导出列名**

```bash
Rscript -e 'load("/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/mimic/D04_dabiao.RData"); writeLines(names(dabiao), "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/_column_review_raw.txt"); cat(length(names(dabiao)), "cols\n")'
```

- [ ] **Step 2: 按子痫病理写 `_column_review.md`**

对每一列写：`列名 | 保留/排除 | 理由`。

**默认排除进 `disease_vars`（子痫/子痫前期谱系泄漏，不确定则排除）：**

- 诊断/共病：`Hypertension`（与子痫定义高度重叠）
- 糖尿病轴：`T1DM`, `T2DM`, `Diabetes`, `Glucose`, `HbA1c`
- 尿蛋白轴：`UrineProtein`, `UrineGlucose`, `AlbuminUrine`, `AlbuminCreatinine`
- 其它明显疾病诊断列若与子痫病理强相关且易泄漏，标注【边界·已排除】一并列入

**保留示例：** 人口学 `Age`/`Race`/…；通用实验室（非尿蛋白/血糖轴）；其它共病如 `COPD` 等非子痫核心标志（若审阅认为可留）。

**不进 disease_vars：** `ID`, `DN`（结局）；复合指标 `ALBI`（由成分排除处理）。

- [ ] **Step 3: 自检**

确认原始列无一遗漏；摘要打印 `disease_vars` 名单长度 ≥ 8。

---

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

### Task 4: 启动 10 路批量并确认调度

**Files:**
- Touch: `…/by_index/`, `…/checkpoints/`, `…/logs/`（由引擎创建）

**Interfaces:**
- Consumes: Task 1–3 产物
- Produces: 后台批处理进程；日志出现 worker / index 调度

- [ ] **Step 1: 启动批处理（后台，长跑）**

```bash
export MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final
cd "$MEDICAL_BLOCKS_ROOT"
nohup Rscript run/ml/run_ml_dual_batch.R \
  --config "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/config.R" \
  --workers 10 --db nhanes \
  > "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/logs/batch_$(date +%Y%m%d_%H%M%S).log" 2>&1 &
echo $!
```

若入口自动转 Windows Rscript，保持同一参数即可。

- [ ] **Step 2: 确认启动**

```bash
# 日志出现 config 加载 / workers=10 / 指标列表或首批 index 开始
tail -n 40 "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/logs/"*.log | tail -40
ls "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/by_index" 2>/dev/null | head
```

Expected: 进程存活；日志无立刻 FATAL；`by_index` 或 checkpoints 开始出现产物。

- [ ] **Step 3: 向用户报告**

回报：日志路径、PID、已排队/已出现的指标数；说明整批为长跑，可断点续跑（`skip_existing=TRUE`）。

---

## Spec coverage check

| Spec 项 | Task |
|---------|------|
| D04 合并 n=4756 / events=482 | Task 1 |
| `_column_review` + disease_vars | Task 2 |
| 六模型 / age 35 / index_group=all / logistic | Task 3 |
| workers 10 启动 | Task 4 |
| 不做 all_vars / cox / 额外模型 | Global Constraints |

## Placeholder scan

无 TBD；config 中 `disease_vars` 由 Task 2 实填，不可留注释占位上线。
