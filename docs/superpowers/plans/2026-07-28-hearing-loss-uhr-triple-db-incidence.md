# Hearing Loss UHR Triple-DB Incidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `15_hearing_loss/incidence_38341157` 用对齐后的 NHANES（加权）+ CHARLS + 李玲三库，只跑 UHR 发病分析，并锁定同一套协变量。

**Architecture:** 一次性 prep 产出三份 harmonized `dabiao` + `covariate_lock.json`；NHANES+CHARLS 走现有 `run_incidence_dual_batch.R --only-index UHR`；李玲走新建薄入口 `run_incidence_single.R` + single config，强制同一 lock。不改 Blocks 核心、不扩展三库引擎。

**Tech Stack:** R, `R/pipeline_runner.R`, `R/dual_db_harmonize.R`, `configs/templates/config_incidence_dual_batch.template.R`, `configs/templates/config_incidence_single.template.R`, `jsonlite`

## Global Constraints

- 产出根：`G:/02block_result/15_hearing_loss/incidence_38341157`（WSL：`/mnt/g/02block_result/15_hearing_loss/incidence_38341157`）
- 仅指标 **UHR**；禁止跑 dual_safe 全表
- 结局：`Hearing_Loss` / `Normal`；`analysis_group=Hearing_Loss`，`reference_group=Normal`
- 李玲单位：尿酸 `/59.48`，HDL `*38.67`（`HDL>10` 不换）
- NHANES 加权：`auto_new_weight=TRUE`；CHARLS/李玲不加权
- 不修改 `Blocks/01–70` 业务逻辑；不改 `dual_db` 为三库引擎
- 不用 `D01_baseline_NHANES_0728.RData` 作分析库
- **除非用户明确要求 git commit，否则跳过所有 commit 步骤**

## File Structure

| 路径 | 职责 |
| ---- | ---- |
| `scripts/prep_hearing_loss_uhr_triple.R` | 读原始三库 → 单位/结局/列名对齐 → 写 harmonized + lock + QC |
| `.../data/harmonized/*.RData` | 分析用 dabiao（obj 名一律 `dabiao`） |
| `.../data/harmonized/covariate_lock.json` | 三库协变量交集（含 M1/M2 预设） |
| `.../config_incidence_dual_batch.R` | NHANES+CHARLS dual batch |
| `.../config_incidence_liling.R` | 李玲单库 |
| `run/incidence/run_incidence_single.R` | 薄入口：`--config` → `run_pipeline` |

预估 lock 临床列（映射后交集，实现以脚本实测为准）：  
`Age, Gender, Height, Weight, Marital_Status, Hypertension, TC, TG, LDL, Creatinine, BUN, WBC, Platelet_Count, Hematocrit`  
（当前预览无 `Diabetes`：NHANES dabiao 可能缺该列）

---

### Task 1: Prep — 三库 harmonize + covariate lock

**Files:**
- Create: `scripts/prep_hearing_loss_uhr_triple.R`
- Create (runtime): `/mnt/g/02block_result/15_hearing_loss/incidence_38341157/data/harmonized/` 下 3×RData + `covariate_lock.json` + `prep_qc.csv`

**Interfaces:**
- Produces: `dabiao` data.frames；JSON 字段  
  `covariates`（全 lock）、`model1`（人口学）、`model2`（model1+临床）、`common_model_factors`（= model2 \\ model1）、`n_by_db`、`created_at`

- [ ] **Step 1: 写 prep 脚本骨架与路径**

```r
#!/usr/bin/env Rscript
# scripts/prep_hearing_loss_uhr_triple.R
suppressPackageStartupMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop("需要 jsonlite")
})

study_root <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
# Windows 下若该路径不可用，回退：
if (!dir.exists(study_root)) {
  study_root <- "G:/02block_result/15_hearing_loss/incidence_38341157"
}
raw_dir <- file.path(study_root, "data")
out_dir <- file.path(raw_dir, "harmonized")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

load_obj <- function(path, obj) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  if (!exists(obj, envir = e, inherits = FALSE))
    stop("对象不存在: ", obj, " in ", path)
  e[[obj]]
}

recode_outcome <- function(x) {
  if (is.null(x)) return(NA_character_)
  if (is.numeric(x) || is.integer(x)) {
    return(ifelse(is.na(x), NA_character_,
                  ifelse(as.integer(x) == 1L, "Hearing_Loss", "Normal")))
  }
  s <- trimws(as.character(x))
  s[s %in% c("1", "Hearing Loss", "Hearing_Loss")] <- "Hearing_Loss"
  s[s %in% c("0", "Normal")] <- "Normal"
  s[!(s %in% c("Hearing_Loss", "Normal"))] <- NA_character_
  s
}
```

- [ ] **Step 2: 实现列映射、李玲单位换算、写出三库**

核心映射（不够再按实测补）：

```r
# NHANES N
# Disease_Group 0/1 → Hearing_Loss/Normal
# UricAcid → Uric_Acid; HDL 已是 mg/dL；保留 SDMVPSU, SDMVSTRA, WTMEC2YR, WTMEC4YR, ID

# CHARLS C
# Disease → Disease_Group（Hearing Loss/Normal）
# Uric_acid_mg_dL → Uric_Acid
# Direct_HDL_Cholesterol_mg_dL → HDL
# Blood_Urea_Nitrogen_mg_dL → BUN
# Creatinine_refrigerated_serum_mg_dL → Creatinine
# Total_Cholesterol_mg_dL → TC; Triglycerides_... → TG; LDL_... → LDL
# White_blood_cell_count_1000_cells_uL → WBC; platelet_count → Platelet_Count

# 李玲
ua <- dabiao$UricAcid
hdl <- dabiao$HDL
ua_mg <- ua / 59.48
hdl_mg <- ifelse(!is.na(hdl) & hdl > 10, hdl, hdl * 38.67)
dabiao$Uric_Acid <- ua_mg
dabiao$HDL <- hdl_mg
# Disease_Group 0/1 → 同上
# UreaNitrogen → BUN; PlateletCount → Platelet_Count
```

写出：

```r
save(dabiao, file = file.path(out_dir, "D04_NHANES_hearing_45_69.RData"))
save(dabiao, file = file.path(out_dir, "D04_CHARLS_hearing_45_69.RData"))
save(dabiao, file = file.path(out_dir, "D04_Liling_hearing_45_69.RData"))
```

每库在写盘前：去掉结局 NA；若 `Uric_Acid` 或 `HDL` ≤0/NA 则该行在 QC 中标记（仍可留给插补，但若李玲有效 n&lt;50 则 `stop`）。

- [ ] **Step 3: 算三库交集 lock 并写 JSON**

```r
drop_cols <- c(
  "Disease_Group", "Uric_Acid", "HDL", "UHR", "ID", "SEQN",
  "SDMVPSU", "SDMVSTRA", "WTMEC2YR", "WTMEC4YR", "new_Weight", "Source_File"
)
# 候选 = 映射后三库列名交集 \\ drop_cols
# model1 <- intersect(c("Age","Gender"), covariates)  # 至少这两个
# 若 length(setdiff(covariates, model1)) < 1 → stop（少于 3 个非指标协变量：要求 length(covariates) >= 3）
# model2 <- covariates
# common_model_factors <- setdiff(model2, model1)

lock <- list(
  covariates = covariates,
  model1 = model1,
  model2 = model2,
  common_model_factors = common_model_factors,
  n_by_db = list(NHANES = nrow_n, CHARLS = nrow_c, Liling = nrow_l),
  created_at = as.character(Sys.time())
)
jsonlite::write_json(lock, file.path(out_dir, "covariate_lock.json"),
                     auto_unbox = TRUE, pretty = TRUE)
```

同时写 `prep_qc.csv`：每库 n、事件数、`Uric_Acid`/`HDL` 中位数、换算前后李玲摘要。

- [ ] **Step 4: 运行 prep 并验收**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript scripts/prep_hearing_loss_uhr_triple.R
```

Expected:
- 三份 RData 存在；
- `covariate_lock.json` 含 ≥3 个 covariates，含 `Age`/`Gender`；
- 李玲 `Uric_Acid` 中位数约 3–7；`HDL` 中位数约 40–60；
- 三库 `Disease_Group` 仅 `Hearing_Loss`/`Normal`。

快速核验：

```bash
Rscript -e '
out<-"/mnt/g/02block_result/15_hearing_loss/incidence_38341157/data/harmonized"
lock<-jsonlite::fromJSON(file.path(out,"covariate_lock.json"))
print(lock$covariates)
for (f in c("D04_NHANES_hearing_45_69.RData","D04_CHARLS_hearing_45_69.RData","D04_Liling_hearing_45_69.RData")) {
  e<-new.env(); load(file.path(out,f), envir=e); d<-e$dabiao
  cat(f, "n=", nrow(d), "UA med=", median(d$Uric_Acid,na.rm=TRUE),
      "HDL med=", median(d$HDL,na.rm=TRUE), "\n")
  print(table(d$Disease_Group, useNA="ifany"))
}'
```

- [ ] **Step 5: Commit（仅当用户要求）**

```bash
# 用户要求时再执行
git add scripts/prep_hearing_loss_uhr_triple.R
git commit -m "feat: prep hearing-loss UHR triple-db harmonized dabiao"
```

---

### Task 2: Dual config — NHANES + CHARLS，仅 UHR

**Files:**
- Create: `/mnt/g/02block_result/15_hearing_loss/incidence_38341157/config_incidence_dual_batch.R`  
  （由 `configs/templates/config_incidence_dual_batch.template.R` 复制后改）

**Interfaces:**
- Consumes: Task 1 的 harmonized 路径与 `covariate_lock.json`
- Produces: 可被 `run_incidence_dual_batch.R --config ... --only-index UHR` 加载的 `config` + pipelines

- [ ] **Step 1: 复制模板并改根路径 / 项目元数据**

```r
.batch_project_root <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
# 若在 Windows R 中跑，改为 "G:/02block_result/15_hearing_loss/incidence_38341157"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")
.harm_dir           <- file.path(.batch_project_root, "data", "harmonized")

# project
project = list(
  name = "hearing_loss_uhr_triple",
  disease_code = "15",
  disease = "hearing_loss",
  literature_pmid = "38341157",
  database = "NHANES",
  database_type = "nhanes",
  study_type = "incidence",
  classification_mode = "binary",
  analysis_group = "Hearing_Loss",
  reference_group = "Normal",
  output_dir = .batch_project_root,
  use_step_prefixed_block_dirs = TRUE,
  block_steps_prefix = "step",
  mirror_pub_outputs_to_root = TRUE,
  root = NULL
)

# data / incidence outcome
data$outcome_column <- "Disease_Group"
incidence$outcome_var <- "Disease_Group"
```

- [ ] **Step 2: 挂两库路径 + 读入 lock 写入 Gate B 预设**

```r
.lock <- jsonlite::fromJSON(file.path(.harm_dir, "covariate_lock.json"))
.m1 <- as.character(.lock$model1)
.m2 <- as.character(.lock$model2)
.cmf <- as.character(.lock$common_model_factors)

dual_db$primary <- list(
  name = "NHANES",
  db_type = "nhanes",
  rawdata_path = file.path(.harm_dir, "D04_NHANES_hearing_45_69.RData"),
  rawdata_obj = "dabiao",
  id_column = "ID",
  column_mapping_type = "NHANES"
)
dual_db$secondary <- list(
  name = "CHARLS",
  db_type = "regular",
  rawdata_path = file.path(.harm_dir, "D04_CHARLS_hearing_45_69.RData"),
  rawdata_obj = "dabiao",
  id_column = "ID",
  column_mapping_type = "CHARLS"  # 若模板仅认 NHANES/MIMIC，改用 "NHANES" 并依赖已对齐列名
)

dual_db$harmonization$lock_covariates_preset <- TRUE
dual_db$harmonization$common_model_factors <- .cmf
dual_db$harmonization$harmonized_model1_nhanes <- .m1
dual_db$harmonization$harmonized_model2_nhanes <- .m2
dual_db$harmonization$harmonized_model1_mimic  <- .m1
dual_db$harmonization$harmonized_model2_mimic  <- .m2
```

注意：`dual_db_preset_gate_b` 要求 M2 严格长于 M1；若 `.cmf` 为空会跳过预设——prep 必须保证 `model2` ⊃ `model1`。

- [ ] **Step 3: NHANES 权重、飞书、batch 仅 UHR**

```r
nhanes$auto_new_weight <- TRUE
nhanes$survey_weight <- "new_Weight"
nhanes$survey_cluster <- "SDMVPSU"
nhanes$survey_strata <- "SDMVSTRA"

index$enable <- TRUE
incidence_batch$index_vars <- "UHR"   # 双保险；CLI 仍传 --only-index UHR
incidence_batch$db_mode <- "both"
incidence_batch$output_base <- .batch_project_root
feishu$enable <- FALSE
```

`data$rawdata_path` 与 primary 指向同一 NHANES harmonized 文件。

- [ ] **Step 4: Smoke 启动 dual（可先 shared-only 再全量）**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript run/incidence/run_incidence_dual_batch.R \
  --config "/mnt/g/02block_result/15_hearing_loss/incidence_38341157/config_incidence_dual_batch.R" \
  --only-index UHR --db both --workers 1
```

Expected:
- 仅创建 `by_index/UHR/`（无其它指标目录）；
- NHANES 分支使用 `*_nhanes_weighted` logistic；
- `_batch_status.json` 最终非硬失败（或明确写出可接受的降级原因）。

验收：

```bash
ls /mnt/g/02block_result/15_hearing_loss/incidence_38341157/by_index/
# 应只有 UHR
test -f /mnt/g/02block_result/15_hearing_loss/incidence_38341157/by_index/UHR/_batch_status.json && echo OK
```

- [ ] **Step 5: Commit（仅当用户要求）** — 研究目录 config 通常在 G: 盘，可不进 git；若把 prep/runner 改动入库再 commit。

---

### Task 3: 薄入口 `run_incidence_single.R` + 李玲 config

**Files:**
- Create: `run/incidence/run_incidence_single.R`
- Create: `/mnt/g/02block_result/15_hearing_loss/incidence_38341157/config_incidence_liling.R`  
  （自 `configs/templates/config_incidence_single.template.R`）

**Interfaces:**
- Consumes: Task 1 lock + Liling harmonized；`run_pipeline(root, config, pipeline)`
- Produces: `by_index/UHR/Liling/` 下基线与 logistic 主表

- [ ] **Step 1: 实现薄入口**

```r
#!/usr/bin/env Rscript
# run/incidence/run_incidence_single.R
.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) return(normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/"))
  normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
env_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (nzchar(env_root)) {
  root <- normalizePath(env_root, winslash = "/", mustWork = TRUE)
} else if (basename(script_path) == "incidence" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  root <- script_path
}
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
config_path <- NULL
only_index <- NULL
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--config" && i < length(args)) {
    config_path <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--only-index" && i < length(args)) {
    only_index <- trimws(args[[i + 1L]]); i <- i + 2L
  } else i <- i + 1L
}
if (is.null(config_path) || !nzchar(config_path))
  stop("--config 必填", call. = FALSE)
config_path <- normalizePath(config_path, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(config_path)

if (!is.null(only_index) && nzchar(only_index)) {
  config$incidence$index_var <- only_index
  config$logistic$index_var <- only_index
  if (!is.null(config$prediction)) config$prediction$index_vars <- only_index
  if (!is.null(config$index)) {
    config$index$enable <- TRUE
    config$index$only <- only_index
  }
}

if (!exists("pipeline")) stop("config 未定义 pipeline", call. = FALSE)
options(warn = 1, cli.hyperlink = FALSE)
run_pipeline(root, config = config, pipeline = pipeline)
```

- [ ] **Step 2: 写李玲 config 关键键**

```r
.study <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
.harm  <- file.path(.study, "data", "harmonized")
.lock  <- jsonlite::fromJSON(file.path(.harm, "covariate_lock.json"))

config$data$rawdata_path <- file.path(.harm, "D04_Liling_hearing_45_69.RData")
config$data$rawdata_obj <- "dabiao"
config$data$outcome_column <- "Disease_Group"
config$data$id_column <- "ID"   # 若无 ID，prep 时生成 ID <- seq_len(nrow)

config$project$disease_code <- "15"
config$project$disease <- "hearing_loss"
config$project$database <- "Liling"
config$project$database_type <- "regular"
config$project$analysis_group <- "Hearing_Loss"
config$project$reference_group <- "Normal"
config$project$output_dir <- file.path(.study, "by_index", "UHR", "Liling")

config$incidence$outcome_var <- "Disease_Group"
config$incidence$index_var <- "UHR"
config$logistic$index_var <- "UHR"
config$prediction$index_vars <- "UHR"

config$column_mapping$database_type <- "NHANES"  # 列已对齐，走通用映射即可
config$index <- list(enable = TRUE, only = "UHR", digits = 4L)

# 强制协变量：required_predictors = lock；缩小搜索空间
config$univariate_incidence_binary$required_predictors <- as.character(.lock$covariates)
config$univariate_incidence_binary$excluded_predictors <- character(0)
config$multivariate_incidence_binary$required_predictors <- as.character(.lock$covariates)

# pipeline：在 imputation 后插入 index；保留 regular logistic（非 nhanes_weighted）
pipeline$blocks <- c(
  "data_clean", "column_mapping", "imputation", "index",
  "baseline_binary", "simple_ROC", "boxplot",
  "univariate_incidence_binary", "multicollinearity_screen",
  "multivariate_incidence_binary", "multicollinearity_final",
  "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
  "rcs_incidence",
  "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
  "subgroup_incidence", "mediation_incidence"
)
pipeline$checkpoint$dir <- file.path(.study, "checkpoints", "Liling_UHR")
pipeline$dual_db <- list(enable = FALSE)
```

若李玲无 `ID`：在 Task 1 prep 中 `dabiao$ID <- seq_len(nrow(dabiao))`。

亚组/中介：保持模板默认；失败不阻断（`pause_enable=FALSE` 已在多数 logistic；mediation `pause_enable=FALSE`）。主路径至少拿到 logistic 表。

- [ ] **Step 3: 跑李玲并验收**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript run/incidence/run_incidence_single.R \
  --config "/mnt/g/02block_result/15_hearing_loss/incidence_38341157/config_incidence_liling.R" \
  --only-index UHR
```

Expected:
- `by_index/UHR/Liling/` 下有 baseline / logistic 相关 step 目录或表；
- 多因素候选不超出 `covariate_lock.json` 的 `covariates`（VIF 后可更少）。

- [ ] **Step 4: Commit（仅当用户要求）**

```bash
git add run/incidence/run_incidence_single.R
git commit -m "feat: add incidence single-db runner for Liling UHR"
```

---

### Task 4: 三库对照验收

**Files:**
- Read-only 检查产出；可选写：`.../data/harmonized/acceptance_note.txt`

- [ ] **Step 1: 核对目录与指标范围**

```bash
find /mnt/g/02block_result/15_hearing_loss/incidence_38341157/by_index -maxdepth 2 -type d
# 期望：by_index/UHR/NHANES, CHARLS, Liling（名称以 dual primary/secondary$name 为准）
```

- [ ] **Step 2: 核对 lock 一致性（脚本）**

```r
lock <- jsonlite::fromJSON("/mnt/g/02block_result/15_hearing_loss/incidence_38341157/data/harmonized/covariate_lock.json")
# 读 dual Gate B cache（若存在）与 Liling multivariate 输出，确认无 lock 外变量
# Gate B: checkpoints/_global_harmonization/gate_b_covariates.rds
```

- [ ] **Step 3: 记录验收结果**

写入 `acceptance_note.txt`：三库 n/事件数、UHR 中位数、主模型 OR 文件路径、已知跳过步骤（亚组/中介）。

---

## Spec coverage（自检）

| Spec 要求 | Task |
| ---- | ---- |
| 三库文件与不用 D01 | Task 1 |
| 单位换算 A / 结局 A | Task 1 |
| covariate lock 交集 | Task 1 |
| NHANES+CHARLS dual + 仅 UHR | Task 2 |
| NHANES 加权 | Task 2 |
| 李玲单库 + run_incidence_single | Task 3 |
| 验收与非 UHR 目录检查 | Task 4 |
| 不扩展三库引擎 | 全局约束 |

无 TBD/TODO 占位；李玲 `ID` 缺失在 Task 1/3 已写明生成方式。
