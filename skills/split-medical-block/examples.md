# split-medical-block 示例：baseline 拆分

## 拆分前（单块）

- 文件：`Blocks/block_baseline.R`
- 注册：`register_block("baseline", block_baseline, ...)`
- 配置：`config$baseline`
- 逻辑：`n_groups == 2` 用 t/wilcox，否则 aov/kruskal；NHANES 在 wrapper 末尾追加

## 目录序号（拆分前必问用户）

向用户确认两位前缀后再建目录，例如：

- 用户：「baseline 用 04，前面 imputation 等是 01–03」
- Agent：`mkdir Blocks/04_baseline` 或 `mv baseline 04_baseline`
- 勿在未确认时创建 `Blocks/baseline/`

## 拆分后（三块 + 可选保留父块）

| 场景 | run_block | config 段 |
|------|-----------|-----------|
| MIMIC / 二分类 Table 1 | `baseline_binary` | `baseline_binary` |
| 三组及以上 Table 1 | `baseline_multiclass` | `baseline_multiclass` |
| NHANES 仅加权+非加权表 | `baseline_nhanes` | `baseline_nhanes` + 主 config 的 `nhanes` |

## config2.R 片段（示意）

```r
baseline_binary = list(
  sig_cutoff   = 0.05,
  strata       = NULL,
  include_vars = NULL,
  exclude_vars = c("ID", "SEQN", ...),
  table1_label_overrides = list(Age = "Age (years)", ...),
  pause_enable             = TRUE,
  pause_on_table1_fail     = TRUE,
  pause_on_min_sig_vars    = TRUE,
  pause_min_sig_vars       = 3L
),

baseline_nhanes = list(
  sig_cutoff = 0.05,
  table1_label_overrides = list(...),
  pause_on_missing_design      = TRUE,
  pause_on_weighted_table_fail = TRUE,
  pause_min_sig_vars           = 3L
),

# 仍留在主 config（非 baseline_*）
nhanes = list(survey_weight = "new_weight", exclude_cols = ...),
data = list(outcome_column = "Disease", ...),
project = list(study_type = "incidence", ...),
```

## 编排示例

```r
# 发病 + MIMIC 二分类
source(file.path(root, "Blocks/04_baseline/01block_baseline_binary.R"))
ctx <- run_block(ctx, "baseline_binary")

# NHANES 队列（不跑 binary）
source(file.path(root, "Blocks/block_obj.R"))
ctx <- run_block(ctx, "obj")
source(file.path(root, "Blocks/04_baseline/03block_baseline_nhanes.R"))
ctx <- run_block(ctx, "baseline_nhanes")
# 下游仍可读 ctx$results$sig_vars（来自加权表）
```

## 拆 subgroup / COX 时的映射思路

1. 列出父块内**互斥模式**（如 `analysis_mode = "standard"` vs `"subphenotype"`）。
2. 每种模式一个 `Blocks/subgroup/0Nblock_subgroup_<mode>.R`。
3. 配置键：`subgroup_standard`、`subgroup_subphenotype`，块内 `bl_cfg <- cfg$subgroup_standard %||% list()`。
4. 共用 `config$subgroup` 的字段若仍需要，可只在主 config 保留一份，子块只读自己的 `subgroup_<mode>`；不要两套键混读。

## 硬约束示例（logistic / univariate / baseline）

与 `BLOCKS_USAGE_GUIDE.md` 红线 §5–§6 一致。

### 不抽公共 block

- `Blocks/10_logistic/`：各 `NNblock_logistic_*` 内嵌 Tb / 随机搜索，无 `block_logistic_common.R`。
- `Blocks/06_univariate/`：`01`–`04` 内嵌 `.uvp01_*` / `.uvi02_*` / `.uvi03_*` / `.uvn04_*`；`block_multicollinearity.R` 内嵌 `.mcol_*`。
- `Blocks/04_baseline/`：`01`–`03` 各自 `.bb01_*` / `.bb02_*` / `.bb03_*`，无公共 helper 文件。

### Pipeline 决定数据，块内不选源

```r
data <- ctx$data$imputed %||% ctx$data$cleaned
design <- ctx$results$nhanes_design   # NHANES，须先 obj
```

- 子块 config 不加 `data_source`；由 pipeline 顺序决定数据槽位。
