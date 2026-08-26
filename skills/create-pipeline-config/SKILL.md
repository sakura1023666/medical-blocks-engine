---
name: create-pipeline-config
description: >-
  Creates study-type pipeline configs (config_survival, config_incidence, etc.)
  for Medical Blocks: inspect data, map old config keys to split sub-blocks,
  define config + pipeline blocks list, pair with run_*.R. Use when the user
  asks to write a new config, new analysis routine, config_survival,
  config_incidence, or migrate from monolithic config.R.
---

# 新建 Pipeline Config 规范

为 Medical Blocks 项目编写**按研究类型拆分**的配置文件（如 `configs/config_survival.R`），替代旧版巨型 `config.R` + 硬编码 `run_survival.R`。

**必读**：`BLOCKS_USAGE_GUIDE.md`、`.cursor/skills/split-medical-block/SKILL.md`

---

## 何时用本 skill

- 新建一套分析「套路」（预后 / 发病 / NHANES / ML / 轨迹等）
- 从兄弟项目复制 `config.R` 迁入 `Block-new`
- 用户说「写 config_survival」「新 config」「换数据跑流水线」

**不要**用本 skill 写 Block 实现代码——那是 `split-medical-block` 的事。

**部署给程序员时**：config 写完后用 `deploy-programmer-interface` skill 搭研究区（`medical-blocks-studies`、薄 config、`run_study`）。

---

## 核心分工（红线）

| 放哪里 | 内容 |
|--------|------|
| `configs/config_<type>.R` | `config` 对象：路径、结局、各 block 统计参数 |
| 同文件或 `run_<type>.R` | `pipeline` 对象：要跑哪些 block、顺序、检查点、双库 |
| `R/pipeline_runner.R` | block 名 → 源文件映射、通用执行引擎 |
| **禁止** | 在 config 里写 `run_block()` 可执行代码 |
| **禁止** | 在 block config 里加 `data_source` 切换数据集 |

块内只读 `ctx$config`；对象名**必须叫 `config`**（文件名可以是 `config_survival.R`）。

---

## 工作流（按顺序，不可跳步）

### 0. 向用户确认（必问）

1. **研究类型**：`prognosis` / `incidence` / NHANES 加权 / 其他？
2. **配置文件名**：如 `config_survival.R`、`config_incidence_nhanes.R`
3. **数据文件**：路径、RData 对象名、ID/结局/时间列
4. **要跑的 block 列表**：完整套路还是阶段性（如仅 clean→baseline）？
5. **是否双库**（`multi_db$enable`）？
6. **`mirror_pub_outputs_to_root`**：是否将各 `stepNN_*` 子目录下已落盘的发表表/图复制到 `<output_dir>/Tables` 与 `<output_dir>/Figures` 根目录？（实现见 `R/utils.R` 的 `mirror_pub_output_to_root`；**须用户明确确认**后再写入 `config$project`，常见为 `TRUE`）
7. **参考模板**：是否从 `预后block/config.R`、`03block-ML/config.R` 等复制？

未确认前**不要**写 config；**尤其** `mirror_pub_outputs_to_root` 不得在未问用户时默认写入。

### 1. 探查数据（只读）+ **疾病列审阅（强制）**

在项目根执行（或让用户提供结果）：

```r
env <- new.env()
load("Data/xxx.RData", envir = env)
# 列出对象、dim、colnames、结局分布、缺失率
```

记录：`rawdata_obj`、行数列数、ID/结局/时间列名、二分类水平数、高缺失列（>30%）。

**紧接着必须**按 `skills/review-raw-covariate-columns/SKILL.md` 对**每一列**做保留/排除审阅，
写出 `Data/_column_review.md`，并把排除名单写入 `analysis_exclusion$disease_vars`
（糖尿病课题须覆盖尿白蛋白 `Albumin_Urine` 等，不能只抄 HbA1c）。未完成审阅
**禁止**进入下一步写 config。

### 2. 选定 config 文件名与模板

| 研究类型 | 推荐文件 | 必含 config 段 | 不要放入的段 |
|----------|----------|----------------|--------------|
| MIMIC/eICU 预后 | `config_survival.R` | `survival`, `cox_*`, `rcs_prognosis`, `baseline_binary` | `logistic_*`, `incidence` |
| 发病 Logistic | `config_incidence.R` | `incidence`, `logistic_*`, `baseline_binary` | `survival`, `cox_*` |
| NHANES 加权 | `config_incidence_nhanes.R` | `nhanes`, `obj`, `baseline_nhanes`, `univariate_nhanes` | 普通 MIMIC cox |
| ML 预测 | `config_prediction.R` | `splitting`, `ml_*`, `ROC`, `shap` | 无关 cox |
| 轨迹 | `config_trajectory.R` | `trajectory` | 全套 baseline/cox |

优先从**同类型**旧 config 复制，再删节 + 改名，不要从空文件重写 800 行。

### 3. 填写 `config` 骨架

最小可跑四步（clean → map → impute → baseline）：

```r
config <- list(
  data = list(
    rawdata_path   = "Data/xxx.RData",
    rawdata_obj    = "rt",
    outcome_column = "fustatus",   # 或 Disease
    id_column      = "subject_id",
    outcome_path   = NULL,
    strip_id_columns_after_imputation = c("ID", "subject_id")
  ),
  project = list(
    study_type      = "prognosis",
    disease         = "COPD",
    database        = "MIMIC",
    analysis_group  = "Non-survivor",
    reference_group = "Survivor",
    output_dir      = "Output/xxx",
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE   # 须阶段 0 向用户确认后再定 TRUE/FALSE
  ),
  survival = list(          # prognosis 必填
    time_var  = "futime",
    event_var = "fustatus",
    index_var = "RAR"       # 核心暴露指标
  ),
  data_clean       = list(missing_threshold = 0.3, age_filter = NULL, drop_columns = NULL),
  column_mapping   = list(enable = TRUE, database_type = "MIMIC"),
  imputation       = list(method = "cart", m = 5L, max_iter = 5L, seed = 1234L),
  baseline_binary  = list(sig_cutoff = 0.05, exclude_vars = character(0), pause_on_min_sig_vars = FALSE)
)
```

**规则**：
- 每个要跑的 block 必须有同名 config 段：`run_block(ctx, "baseline_binary")` → `config$baseline_binary`
- config 键名 = `register_block` 名（见 [examples.md](examples.md) 对照表）
- 旧键必须迁移：`baseline` → `baseline_binary`；`univariate_multivariate` → `univariate_prognosis` + `multivariate_prognosis`；`cox` → `cox_binary` 等

### 4. 填写 `pipeline`（声明式，非可执行）

与 `config` 放在同一文件末尾，或单独 `pipelines/survival_standard.R`：

```r
pipeline <- list(
  name   = "survival_mimic_standard",
  blocks = c(
    "data_clean", "column_mapping", "imputation",
    "baseline_binary"
    # 按需追加: "boxplot", "univariate_prognosis", ...
  ),
  render_tables_after  = c("imputation", "baseline_binary"),
  render_figures_after = character(0),
  dual_db    = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = "checkpoints")
)
```

**block 顺序约束**：
- `data_clean` 必须在 `column_mapping` 之前（先加载数据）
- `imputation` 在 `baseline_*` / 回归块之前
- NHANES：`obj` 在 `baseline_nhanes` 之前
- `train_validation` 在 `ml_*` / `ROC` / `shap` 之前
- `multicollinearity` 在依赖 `Model2Factors` 的块之前

### 5. 配对 `run_<type>.R`（薄入口）

```r
root <- normalizePath(getwd(), winslash = "/")
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/config_survival.R"))
run_pipeline(root, config = config, pipeline = pipeline)
```

`pipeline_runner.R` 维护 `.block_sources` 映射；**改 block 路径只改 runner，不改 config**。

### 6. 验证清单（完成前必过）

- [ ] `rawdata_path` / `rawdata_obj` 与 RData 实测一致
- [ ] `study_type` 与 block 变体一致（prognosis 不用 `logistic_quartile_glm` 除非刻意）
- [ ] 结局列存在于数据中；二分类 baseline 用 `baseline_binary`（恰好 2 水平）
- [ ] `pipeline$blocks` 中每个名已在 runner 注册且源文件存在
- [ ] 未包含本套路不需要的旧 config 段（减少干扰）
- [ ] 无 `data_source` / 无 config 内 `run_block` 代码
- [ ] 首次试跑：`pause_on_min_sig_vars = FALSE` 或 `pause_enable = FALSE` 便于调试
- [ ] `output_dir` 不与别的项目冲突
- [ ] 已向用户确认 `mirror_pub_outputs_to_root`，且 `config$project$mirror_pub_outputs_to_root` 与确认一致

### 7. 交付物

1. `configs/config_<type>.R`（含 `config` + `pipeline`）
2. `run_<type>.R`（若新建）
3. 更新 `R/pipeline_runner.R` 中缺失的 block 映射（若有新 block）
4. 简短说明：改了哪些相对模板的字段、推荐试跑命令

---

## 旧 config.R → 新 config 速查

| 旧键 / 旧 block | 新键 / 新 block |
|-----------------|-----------------|
| `baseline` | `baseline_binary` / `baseline_multiclass` / `baseline_nhanes` |
| `univariate_multivariate` | `univariate_prognosis` + `multivariate_prognosis`（或 incidence 变体） |
| `COX` / `cox` | `cox_binary` / `cox_quartile` / … |
| `rcs` | `rcs_prognosis` / `rcs_incidence` / `rcs_nhanes` |
| `weightcox` | `segmented_cox_binary` / `_quartile` / … |
| `subgroup` | `subgroup_prognosis` / `subgroup_incidence` / … |
| `mediation_pro` | `mediation_prognosis` / `mediation_incidence` |
| `ml_models` | `ml_dt`, `ml_rf`, … + `ml_aggregate` |

详细 block 列表见 [examples.md](examples.md)。

---

## Agent 行为约束

- 先读数据再写 config，禁止猜列名
- 从最近似模板复制，最小 diff
- 不创建通用 `config.R`（除非用户明确要求兼容层）
- 不修改 Block 源码来适配错误 config——改 config
- 写完后给出 `Rscript run_xxx.R` 试跑命令
