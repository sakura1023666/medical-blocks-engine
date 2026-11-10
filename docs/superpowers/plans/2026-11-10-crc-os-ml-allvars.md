# CRC 术后 OS 全变量预后 ML Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `31_crc/ml_40395549` 落地与 EMs 交付角色对齐的单库全变量预后 ML，config 无 EMs 残留，插补为先划分再 `fit_on=train`。

**Architecture:** 复用 EMs `run_ml.R` + `config.R` 骨架与 `ml_dual_*` overrides；数据先清洗为 `data/D02_Model_Data.RData`；pipeline 改为 `train_validation → imputation(fit_on=train)`；表图命名改为 `CRC Single`。

**Tech Stack:** R Medical Blocks pipeline、MICE、LASSO-Cox、六模型生存 ML、Python SHAP/Shiny 既有块。

**Spec:** `docs/superpowers/specs/2026-11-10-crc-os-ml-allvars-design.md`

## Global Constraints

- 结局：`Death` + `OS_Months`；ID：`Study_ID`
- `age_cutoff = 65`；`surv_horizon = 60`；`train_ratio = 0.75`
- `imputation$fit_on = "train"`；禁止 `fit_on = "all"`
- 禁止 config 出现 AMH / rAFS / Is_Recurrence / RFS_Months / Pt_ID / age 45 / horizon 48 / EMs 病名
- Fig6 首跑可不钉暴露；LASSO 后按验证表现钉死再重跑亚组
- 交付根只留 Figures/Tables/Methods md/软件 txt/中期 PDF
- 未经用户要求不 `git commit`

---

### Task 1: 清洗原始 xlsx → 分析 RData + 列审阅

**Files:**
- Create: `/mnt/g/02block_result/31_crc/ml_40395549/scripts/prepare_crc_model_data.R`
- Create: `/mnt/g/02block_result/31_crc/ml_40395549/data/D02_Model_Data.RData`
- Create: `/mnt/g/02block_result/31_crc/ml_40395549/Data/_column_review.md`
- Create: `/mnt/g/02block_result/31_crc/ml_40395549/Data/_column_review_raw.txt`

**Interfaces:**
- Consumes: `DATA/数据3j.xlsx` sheet `数据3g`
- Produces: `model_data` data.frame；列名英文短名；`Death` 为 0/1；`OS_Months` numeric

- [ ] **Step 1: 写准备脚本（列映射表内嵌）**

映射（管道列 → 短名）：

| 原列 | 新名 |
|------|------|
| Study_ID | Study_ID |
| Age_years | Age |
| Sex｜性别（0女 1男） | Sex |
| Smoking｜吸烟（0从不 1既往） | Smoking |
| Hypertension｜高血压（0无 1有） | Hypertension |
| Diabetes｜糖尿病（0无 1有） | Diabetes |
| R0_Resection｜R0切除（0否 1是） | R0_Resection |
| Tumor_Size_cm | Tumor_Size_cm |
| Differentiation｜分化（1高 2中 3低 4未明确） | Differentiation |
| Vascular_Invasion｜脉管侵犯（0无 1有） | Vascular_Invasion |
| Perineural_Invasion｜神经侵犯（0无 1有） | Perineural_Invasion |
| T_Stage | T_Stage |
| M_Stage | M_Stage |
| TNM_Stage | TNM_Stage |
| NEU｜术前 … CRP｜术前 | NEU, LYM, MON, PLT, ALB, CEA, CA199, NLR, PLR, LMR, SII, WBC, HGB, CRP |
| Death｜死亡（1死亡 0存活） | Death |
| OS_Months | OS_Months |

丢弃：住院号、全部日期、OS_Days、Death_*y、Followup_*、Loss_*、死亡原文/年份、生存时间口径、空表头列。

二分类 0/1 列转为 factor 水平 `"0","1"` 或引擎可读标签；`Death` 保持 0/1 整数并在 config 设 `analysis_group="1"` / `reference_group="0"`（或清洗时写成 `Dead`/`Alive` 并同步 config——**本计划采用清洗为 `Dead`/`Alive` 字符因子，与 EMs 可读结局一致**）。

- [ ] **Step 2: 运行准备脚本**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript /mnt/g/02block_result/31_crc/ml_40395549/scripts/prepare_crc_model_data.R
```

Expected: 打印 `n=523`、`events≈135`、列数约 30、写出 RData。

- [ ] **Step 3: 落盘列审阅**

`_column_review.md` 逐列：保留/排除/理由；`disease_vars = character(0)`（预测任务，病理分期保留为特征）。

- [ ] **Step 4: 核对**

```r
e <- new.env(); load(".../data/D02_Model_Data.RData", e)
stopifnot(exists("model_data", e))
stopifnot(all(c("Study_ID","Age","Death","OS_Months") %in% names(e$model_data)))
stopifnot(!any(grepl("AMH|rAFS|Is_Recurrence", names(e$model_data))))
```

---

### Task 2: 研究目录入口文件（engine.env + run_ml.R）

**Files:**
- Create: `/mnt/g/02block_result/31_crc/ml_40395549/engine.env`
- Create: `/mnt/g/02block_result/31_crc/ml_40395549/run_ml.R`

**Interfaces:**
- Consumes: `MEDICAL_BLOCKS_ROOT`
- Produces: 可 `Rscript run_ml.R --dry-run`（若支持）或 `--to data_clean`

- [ ] **Step 1: engine.env**

```
MEDICAL_BLOCKS_ROOT=E:/01block/01Block-new-Final
```

- [ ] **Step 2: 复制 EMs `run_ml.R`，改注释与 `options(crc.config_path = config_path)`（或通用 `study.config_path`）**

config.R 内用：

```r
.cfg_path <- getOption("crc.config_path") %||% getOption("ems.config_path")
```

保证 setwd 引擎根后仍能定位研究目录。

---

### Task 3: 写干净 `config.R`（CRC，无 EMs 残留）

**Files:**
- Create: `/mnt/g/02block_result/31_crc/ml_40395549/config.R`
- Reference only: `/mnt/g/02block_result/35_EMs/ml_40395549/config.R`

**Interfaces:**
- Consumes: `data/D02_Model_Data.RData` / `model_data`
- Produces: `config`, `pipeline` 对象

- [ ] **Step 1: 骨架**

```r
source(file.path(.engine, "configs/psoriasis/config11.R"))
source(file.path(.engine, "configs/ml_dual_shared_overrides.R"))
config <- ml_dual_apply_feature_selection_overrides(config)
config <- ml_dual_apply_ml_models_overrides(config)
config <- ml_dual_apply_train_validation_batch_overrides(config)
```

- [ ] **Step 2: 项目/数据键（必须）**

```r
config$data <- list(
  rawdata_path = file.path(.study_root, "data/D02_Model_Data.RData"),
  rawdata_obj = "model_data",
  outcome_column = "Death",
  id_column = "Study_ID",
  strip_id_columns_after_imputation = c("Study_ID")
)
config$project <- modifyList(config$project %||% list(), list(
  name = "CRC_OS_ML_prognosis_allvars",
  disease = "Colorectal_Cancer_OS",
  disease_code = "31_crc",
  literature_pmid = NULL,
  database = "CRC_Single",
  study_type = "prognosis",
  classification_mode = "binary",
  analysis_group = "Dead",
  reference_group = "Alive",
  output_dir = .study_root,
  use_step_prefixed_block_dirs = TRUE,
  block_steps_prefix = "step",
  mirror_pub_outputs_to_root = TRUE
))
config$survival <- modifyList(config$survival %||% list(), list(
  time_var = "OS_Months",
  event_var = "Death",
  index_var = NULL
))
```

- [ ] **Step 3: 插补与划分顺序**

```r
config$imputation <- list(
  missing_col_threshold = 0.2,
  method = "cart",
  m = 5L,
  max_iter = 5L,
  seed = 1234L,
  export_missing_fig = TRUE,
  export_table_s1 = TRUE,
  fit_on = "train",
  rubin_pool = TRUE
)
config$methods <- list(mi_before_split = FALSE, primary_ml_metric = "td_auc_bootstrap")
config$train_validation <- modifyList(config$train_validation %||% list(), list(
  enable = TRUE,
  train_ratio = 0.75,
  base_seed = 42L,
  p_strict = 0.05,
  max_resplit_iter = 2000L,
  comparison_vars = "Age"
))
```

- [ ] **Step 4: 预后 ML / 性能**

调用 `ml_dual_apply_prognosis_ml_overrides(config)`；关闭 survivalsvm/mboost；  

```r
config$performance_ml <- modifyList(config$performance_ml %||% list(), list(
  enable = TRUE,
  surv_horizon = 60,
  surv_horizon_unit = "month",
  combined_panel = TRUE,
  bootstrap_ci_table = TRUE,
  bootstrap_B = 1000L,
  bootstrap_seed = 42L
))
```

- [ ] **Step 5: 关联/图（无 AMH）**

```r
config$force_factor_vars <- c("Differentiation", "T_Stage", "M_Stage", "TNM_Stage")
.cont_ml <- c("Age", "Tumor_Size_cm", "NEU", "LYM", "MON", "PLT", "ALB",
              "CEA", "CA199", "NLR", "PLR", "LMR", "SII", "WBC", "HGB", "CRP")
config$rcs$vars <- .cont_ml
config$rcs_prognosis <- modifyList(config$rcs_prognosis %||% list(), list(
  enable = TRUE, index_var = NULL, vars = NULL,
  exclude_vars = config$force_factor_vars,
  figure_number = 2L, nk_range = 3:5
))
config$cox_ml_continuous_batch <- list(
  enable = TRUE, method = "quartile",
  time_var = "OS_Months", event_var = "Death",
  exclude_features = config$force_factor_vars
)
config$km_strata <- modifyList(config$km_strata %||% list(), list(
  time_var = "OS_Months", event_var = "Death",
  export_combined = TRUE, combined_ncol = 2L, combined_nrow = 2L,
  combined_filename = "Figure 3-CRC Single. Combined KM Plots.pdf",
  xlab = "Time (months)"
))
config$subgroup <- modifyList(config$subgroup %||% list(), list(
  enable = TRUE,
  age_cutoff = 65L,
  level_order = list(Age_Group = c("< 65", "\u2265 65")),
  figure_number = 6L,
  figure_kind = "main_figure"
))
config$feature_selection_lasso_cox <- modifyList(
  config$feature_selection_lasso_cox %||% list(),
  list(force_include = c("Age"), pause_enable = FALSE)
)
config$analysis_exclusion <- list(
  enable = TRUE, allow_no_index = TRUE, index_var = NULL,
  disease_vars = character(0),
  exclude_other_composite_indices = FALSE,
  exclude_exposure_if_uses_disease_var = FALSE
)
config$attrition <- list(
  enable = TRUE, draw_pdf = TRUE, db_label = "CRC Single",
  figure_name = "Figure 1-CRC Single. Inclusion exclusion flowchart.pdf",
  outcome_breakdown = TRUE
)
```

- [ ] **Step 6: pipeline blocks（注意顺序）**

```r
pipeline <- list(
  name = "crc_os_ml_prognosis_allvars",
  blocks = c(
    "data_clean", "column_mapping", "analysis_exclusion",
    "train_validation",
    "imputation",
    "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "ml_feature_selection_bundle",
    "cox_ml_continuous_batch", "rcs_prognosis", "km_continuous_router",
    "subgroup_prognosis",
    "ml_models_bundle", "performance_ml", "supplementary_ml",
    "shap", "shiny_ml_app",
    "attrition_flowchart"
  ),
  logistic_gate = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.study_root, "checkpoints"))
)
```

- [ ] **Step 7: 禁抄扫描**

```bash
rg -n "AMH|rAFS|Is_Recurrence|RFS_Months|Pt_ID|Endometriosis|EMs_|surv_horizon = 48|fit_on\s*=\s*\"all\"|age_cutoff = 45" \
  /mnt/g/02block_result/31_crc/ml_40395549/config.R
```

Expected: 无匹配（注释里写「禁止」的句子除外；若有则删掉敏感字面量）。

---

### Task 4: 冒烟跑至插补结束

**Files:** 研究目录 `step*` / `Tables` / `logs`

- [ ] **Step 1:**

```bash
cd /mnt/g/02block_result/31_crc/ml_40395549
# 经 WSL 转发 Windows R（与 EMs run_ml.R 一致）
Rscript run_ml.R --to imputation
```

Expected: `train_validation` 写出 train/val；日志含 `Imputation fit_on=train`；无 stop。

- [ ] **Step 2: 核对人数**

train+val = 523（或清洗后分析集 n）；S1 脚注意图含 train-fit。

---

### Task 5: 全量跑至 summary_results

- [ ] **Step 1:**

```bash
Rscript run_ml.R
```

Expected: 六模型完成；Figure 4/5；Tables 1–5 + S1–S7 角色存在（允许文件名含 CRC Single）。

- [ ] **Step 2: 角色清单 diff**

对照 spec §6，列出缺失角色；缺失则修 config/重跑对应 `--from` block。

---

### Task 6: Fig6 暴露钉死 + 亚组重跑

- [ ] **Step 1:** 从 LASSO 入选特征筛连续变量，在 validation 上比较 TD-AUC 或 UV C-index，选定 `index_var`
- [ ] **Step 2:** 写入 `config$survival$index_var`、`config$logistic$index_var`、亚组图题
- [ ] **Step 3:** `Rscript run_ml.R --from subgroup_prognosis --to subgroup_prognosis`（或等价）
- [ ] **Step 4:** 确认 Figure 6 图题无 AMH，暴露为本病变量

---

### Task 7: 发表收口 + 质控 + 中期

- [ ] **Step 1:** 确保 `summary_results` 含图/表/Methods；`pub_figure_ensure_formats`；prune 白名单
- [ ] **Step 2:**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript run/pub/run_pub_qc_after_project.R --project /mnt/g/02block_result/31_crc/ml_40395549
```

- [ ] **Step 3:** Agent Layer D nature-statistics + nature-figure；修清 P0
- [ ] **Step 4:** PASS/WARN 后按 Aiya-NB004 出中期 PDF，再 prune

---

### Task 8: 决策树薄文档（复用 EMs 套路）

**Files:**
- Create: `Decisiontree/decision_tree_crc_os_ml_allvars.md`

写明：地基=预后 + ML 后缀；对抗阅读以「复用 EMs all_vars 套路决策树 + CRC 数据实例化」备案；引用本 spec。

---

## Spec coverage self-check

| Spec 节 | Task |
|---------|------|
| §2 锁定决策 | Task 3 |
| §4 列审阅 | Task 1 |
| §5 pipeline 顺序 | Task 3 Step 6, Task 4 |
| §6 交付清单 | Task 5–7 |
| §7 禁抄 | Task 3 Step 7 |
| §8 Fig6 | Task 6 |
| §9 质控中期 | Task 7 |

无 TBD 占位；commits 仅当用户要求时执行。
