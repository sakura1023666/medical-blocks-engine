---
name: ml-small-sample
description: >-
  Small-sample ML pipeline (prognosis/incidence × single-index/all-vars): Table 4/5
  bootstrap CI, Youden threshold, Figure 4 2×4, Python model train. Use when starting
  a small-n ML study, writing config_ml_small_sample, consolidating all_vars_ml scripts,
  or asking 小样本 ML / 全指标 / 单指标 / Table 4 bootstrap / Figure 4 复用.
---

# 小样本 ML 复用套路

## 代码在哪（主仓，不在 G 盘研究目录）

| 模块 | 路径 | 作用 |
|------|------|------|
| 指标 + Bootstrap | `R/ml_small_sample_metrics.R` | Youden、ml_bootstrap_metrics、ml_load_all_probs |
| Table 4/5 | `R/ml_small_sample_table45.R` | `ml_write_table45()` |
| 后处理入口 | `run/ml/run_ml_small_sample_pub.R` | 读 config → 写表 + Figure 4 |
| Python 训练 | `python/ml_small_sample_train.py` | 5×10 CV + val → ml_python_results.csv |
| Figure 4 | `python/ml_figure_combined_2x4.py` | ROC/校准/指标CI/DCA |
| Python 指标 | `python/ml_small_sample_metrics.py` | 与 R 侧逻辑对齐 |
| Config 模板 | `configs/templates/config_ml_small_sample.template.R` | **写 config 时改这里两个键** |

## config 必填模式（写 config 时说一声）

```r
ml_small_sample = list(
  outcome_kind = "prognosis",   # prognosis | incidence
  feature_mode = "all_vars",    # single_index | all_vars
  index_var = NULL,             # single_index 时填 "AnionGap" 等
  bootstrap_B = 1000L,
  ...
)
```

### 四种组合

| outcome_kind | feature_mode | 跑什么 |
|--------------|--------------|--------|
| prognosis | single_index | `run_ml_dual_batch.R` → `run_ml_small_sample_pub.R` |
| prognosis | all_vars | 研究目录 step 链（VIF/特征/ML）→ `run_ml_small_sample_pub.R` |
| incidence | single_index | 同上，config 换发病 outcome |
| incidence | all_vars | 全变量 step 链 + 发病结局列 |

**Table 4/5 + Figure 4 四种组合共用同一套后处理**，不要在新课题里复制 bootstrap 代码。

## 研究目录应保留什么

- **只在 G 盘 / 产出目录**：`Tables/`, `Figures/`, `*.rds`, `ml_*.csv`, `config.R`
- **不要复制** `rebuild_logic_format.R` 里的 Table 4/5 大段；改为 source 主仓或调 `run_ml_small_sample_pub.R`

### all_vars_ml 薄封装示例

`rebuild_logic_format.R` 末尾 Table 4/5 段替换为：

```r
repo <- Sys.getenv("MEDICAL_BLOCKS_ROOT", "/mnt/e/01block/01Block-new-Final")
source(file.path(repo, "R/ml_small_sample_metrics.R"))
source(file.path(repo, "R/ml_small_sample_table45.R"))
ml_write_table45(out_dir, tab_dir, d = d, cfg = list(
  ml_small_sample = list(bootstrap_B = 1000L)
), feature_label = feats, ...)
```

`run_ml_python.py` → 调主仓：

```bash
python %MEDICAL_BLOCKS_ROOT%/python/ml_small_sample_train.py \
  --matrix ml_matrix.csv --out ml_python_results.csv
```

`step09_fig4_ml.py` → 调 `python/ml_figure_combined_2x4.py --root ... --out ...`

## 与 ml_dual_batch 的关系

- **single_index**：特征来自引擎 `by_index/`；后处理用本 skill 的 Table 4/5（Youden + bootstrap），替代旧版 0.5 切点表。
- **all_vars**：引擎暂无官方 block；step01–05 仍在研究目录，**但 metrics/表/图必须走主仓**。
- 未来可把 all_vars step 迁入 `Blocks/24_ml_dual/`；在此之前不要在新课题新建 `rebuild_*` 副本。

## 检查清单（新课题）

- [ ] `config$ml_small_sample$outcome_kind` / `feature_mode` 已写明
- [ ] `MEDICAL_BLOCKS_ROOT` 指向主仓
- [ ] Table 4/5 脚注含 bootstrap B 与 Youden 说明
- [ ] 未在 G 盘复制 bootstrap / youden 函数体
- [ ] 发病课题：`analysis_exclusion$disease_vars` 已审列（见 review-raw-covariate-columns skill）
- [ ] **Cox/Logistic 协变量**：勿写死 `model1_factors`/`model2_factors`；交给 `ml_assoc_covariate_resolve`

## Cox / Logistic 协变量铁律（全项目默认）

| 模型 | 协变量 |
|------|--------|
| **Model 1** | **Age 强制**（不论单因素是否显著） |
| **Model 2** | Age + **单因素显著（tb1）且未进入最终 ML 特征** 的变量（嵌套） |

排除：暴露指标本身、已进 ML 的变量、结局/时间列。

实现：
- `R/ml_assoc_covariate_rule.R`
- block `ml_assoc_covariate_resolve`（FS 之后、assoc 之前）
- 流水线顺序：`uni → VIF → FS → resolve → Cox/Logistic → ML 训练`

config：
```r
config$assoc_covariate <- list(
  enable = TRUE,
  force_model1 = "Age",
  uv_source = "tb1",
  max_model2_extra = Inf,  # 小样本可设 1～2
  allow_m2_eq_m1 = TRUE
)
```

## 反例（禁止）

- 每个课题一份 `step09_fig4_ml.py` 全量复制
- 在验证集上搜 F1 最优切点写进主表
- G 盘改代码、主仓不更新（下课题又分叉）
- **APSIII + SOFA + GCS（或 SAPSII/OASIS）同时进 ML**（成分重叠）
- **验证集单独做一套 VIF** 覆盖训练集筛选结果
- **DCA 纵轴画到负数**（应 `dca_y_min=0` 截断）
- **缺验证集插补前后表**（`export_table_s1_validation=TRUE`）
- **NRI P=NA 空白格不处理**（应填 — 并脚注说明分类完全一致）
- **Cox 精简 Model2（Age+GCS）写回全局 Model2Factors**，导致后续 LASSO 候选只剩 1–2 个 →「候选特征不足」。`ml_feature_selection_bundle` 会在进特征选择前从 `vif_screen_pass` 恢复 ML 池。
- **写死 `cox_tertile$model2_factors = c("Age","GCS")`**，绕过「UV 显著且未进 ML」铁律

## 评分重叠速查（进 ML 前）

| 评分 | 与谁重叠 | 默认保留优先 |
|------|----------|--------------|
| APSIII | SAPSII/OASIS/SOFA/GCS | **第 1** |
| SAPSII | 同上 | 第 2 |
| OASIS | 同上 | 第 3 |
| SOFA | 同上 | 第 4 |
| GCS | 以上全部的 CNS 成分 | 第 5（仅当无其他评分时） |

实现：`R/ml_severity_score_overlap.R` → `ml_feature_selection_bundle` 末尾自动去重。
config：`feature_selection$dedupe_overlapping_severity_scores = TRUE`。

## VIF

`multicollinearity$selection_on = "train"`（默认）。验证集不再重筛。

## Table S11 空值说明

CatBoost vs XGBoost 等出现 `NRI=0 [0,0]`、P 空白：**不是导出 bug**，是两模型在 hold-out 上 0.5 切点分类完全相同，无再分类。引擎现填 `—`，脚注说明即可。