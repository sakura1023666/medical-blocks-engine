# 缺血性脑卒中 × 糖尿病竞争风险（28天 / 复合指标并行）设计规格

> 状态：已落地（以 `configs/templates/config_competing_risk_stroke_batch.template.R` 为准）  
> 文献方法学来源：Lai 2025 Cardiovasc Diabetol (PMID 40119388)  
> 数据目录：`G:/02block_result/11_ischemic stroke/Competing_risk_model_40119388/data`（WSL：`/mnt/g/02block_result/...`）  
> 引擎入口：`run/competing_risk/run_competing_risk_chf_batch.R`  
> 协变量筛选细则另见：`docs/superpowers/specs/2026-07-21-competing-risk-sequential-feature-selection-design.md`

---

## 0. 总流程一览（从头到尾）

```
┌─────────────────────────────────────────────────────────────────────────┐
│  SHARED 层（整库只跑一次）                                                │
│  data_clean → column_mapping → dual_db_column_harmonize                  │
│    → index → trajectory_calc_28d_index                                   │
│  产出：清洗后基线 + 竞争结局列 + 基线复合指标 + data/mimic/12_{Index}.RData │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼ 按指标并行 worker（study_batch）
┌─────────────────────────────────────────────────────────────────────────┐
│  UNIT 层（每个复合指标一套 by_unit/【success|failed】{Index}）              │
│                                                                          │
│  ① 数据准备                                                              │
│     imputation                                                           │
│     → competing_index_exposure（基线值 / 四分位 / 28天长表）              │
│     → analysis_exclusion（疾病变量 + 组成变量 + 其他指标硬删）            │
│     → trim_index_extreme（两端 1% 裁剪）                                  │
│     → competing_trajectory_cluster（LMM BLUP + mclust → 轨迹分组）        │
│                                                                          │
│  ② 描述与早停门控                                                         │
│     competing_flowchart                                                  │
│     → competing_baseline_quartile（Table 1）                             │
│     → competing_lmm_trajectory（轨迹均值图）                             │
│     → competing_baseline_trajectory（Table 3 + 暴露不显著早停）           │
│                                                                          │
│  ③ 协变量筛选（严格串联，不可跳级）                                        │
│     univariate_prognosis  →  P<0.10 写入 univar_features                 │
│     → feature_selection_lasso（候选=单因素）                             │
│     → feature_selection_random_forest（候选=LASSO）                      │
│                                                                          │
│  ④ 主分析模型                                                             │
│     competing_finegray / competing_mixed_cox（辅助）                     │
│     → competing_models_123（主事件：Fine-Gray M1–3 + Cox M4–6）           │
│     → competing_models_123_death（死亡竞争：同结构）                      │
│     → competing_stratified / competing_rcs / competing_cif_plot          │
│     → competing_cox_sensitivity / competing_ph_calibration               │
│                                                                          │
│  ⑤ 补充与发表导出                                                         │
│     competing_supp_tables → competing_pub_export（Fig1–9 / Table1–4）    │
└─────────────────────────────────────────────────────────────────────────┘
```

**运行命令：**

```bash
# 1) 共享层
Rscript run/competing_risk/run_competing_risk_chf_batch.R \
  --config ".../config_competing_risk_stroke_batch.R" --shared-only --no-skip

# 2) 单指标冒烟
Rscript run/competing_risk/run_competing_risk_chf_batch.R \
  --config "..." --only-unit NLR --workers 1 --no-skip

# 3) 全量并行
Rscript run/competing_risk/run_competing_risk_chf_batch.R \
  --config "..." --workers 20 --no-skip
```

Worker 脚本：`run/study/run_study_batch_worker.R`（由 `config$study_batch$worker_script` 指定）。

---

## 1. 研究问题（方法学移植）

| 维度 | 原文（Lai 2025） | 本项目（糖尿病版） |
|------|------------------|-------------------|
| 队列 | 老年 CHF+T2DM | MIMIC 缺血性脑卒中（`dabiao.csv`） |
| 暴露 | TyG 基线四分位 + 纵向轨迹 | 过滤后的复合指标：基线四分位 + 28 天轨迹 |
| 主事件 | WHF（status=1） | **糖尿病**：28 天内首次 HbA1c ≥ 6.5%（status=1） |
| 竞争事件 | 全因死亡 | **死亡**（status=2）+ **出院**（status=3） |
| 删失 | 随访截尾 | **28 天**未发生上述事件（status=0） |
| 新发排除 | 原文有基线 T2DM 分析 | **不排除**基线糖尿病 |

> 同壳 pipeline 也可切到 AKI 主事件（`derive_competing_aki_28d`），见决策树  
> `Decisiontree/decision_tree_competing_risk_stroke.md`。本规格专述糖尿病版。

### 1.1 时间 / 事件编码（28 天）

由 `data_clean` 内 `pipeline_derive_competing_diabetes_28d()` 写入：

```
time   = competing_time_28d
status = competing_status_28d

status = 0  28 天内未达标且仍观测（右删失）
status = 1  首次 HbA1c ≥ 6.5%（主事件）且不晚于死亡/出院
status = 2  达标前死亡（hosp_day ≤ 28 且 is_hosp_dead=1）
status = 3  达标前出院（hosp_day ≤ 28 且非死亡）

competing_primary_event = 1{status==1}   # 供单因素 Cox / LASSO / RF 使用
```

**数据来源：**

| 用途 | 文件 / 列 |
|------|-----------|
| 队列 ID | `dabiao.csv` → `subject_id` |
| 基线 | `D01_baseline_MIMIC_ICU_frist_0626 (1).RData` |
| 预后 | `mimic预后数据-all.csv`：`hosp_day`、`is_hosp_dead` |
| HbA1c 日序列 | `mimic-实验室指标-all-1~30天.csv`：`lab{d}_laba1c`（d=1..28） |

---

## 2. SHARED 层（逐步）

| 顺序 | Block | 做什么 |
|------|-------|--------|
| 1 | `data_clean` | 合并基线 ∩ dabiao ∩ 预后；缺失率过滤；调用 `derive_competing_diabetes_28d` 写结局列 |
| 2 | `column_mapping` | MIMIC 列名规范化（`database_type = "MIMIC"`） |
| 3 | `dual_db_column_harmonize` | 本项目 `dual_db$enable = FALSE`，占位通过 |
| 4 | `index` | 按 `.test_units` 计算基线复合指标 |
| 5 | `trajectory_calc_28d_index` | 从实验室 CSV 算每日指标 → `data/mimic/12_{Index}.RData`（`index_df`：`subject_id` + `{Index}_1..28`） |

Checkpoint：`checkpoints/_shared/main/`。

### 2.1 哪些指标进入队列

```r
.disease_exclusion_vars <- c("T1DM", "T2DM", "Diabetes", "HbA1c")
.disease_related_index_units <- pipeline_indices_using_vars(
  .disease_exclusion_vars, .composite_index_vars
)
.test_units <- setdiff(.composite_index_vars, .disease_related_index_units)
```

- 全量定义约 **95** 个复合指标。
- 公式直接或递归使用糖尿病相关变量的指标（如 `SHR`、`HGI`、`HbA1c_HDL_C`、`eGDR` 等）**整单元剔除**，不进 shared 轨迹、也不进 worker。
- shared / unit / config 三处必须用同一份 `.test_units`。

---

## 3. UNIT 层（逐步）

### 3.1 数据准备

| Block | 输入 → 输出 | 关键规则 |
|-------|-------------|----------|
| `imputation` | cleaned → imputed | mice CART；`force_keep_columns = .test_units`；时间/结局/预后列不进 mice |
| `competing_index_exposure` | `12_{Index}.RData` | 首个非缺失日 = 基线 `{Index}`；四分位 `{Index}_quartile`；长表写入 `competing_index_long`。无数据 → `INDEX_NO_DATA_STOP`；基线 n 过小 → `INDEX_MIN_N_STOP` |
| `analysis_exclusion` | 分析副本硬删列 | 见 §5 |
| `trim_index_extreme` | 两端 `trim_quantile=0.01` | 裁剪后样本进入轨迹聚类与后续分析 |
| `competing_trajectory_cluster` | 仅 trim 后 ID | LMM（优先）BLUP intercept/slope + mclust 自动 K；类占比 &lt; `trajectory_min_class_prop`(0.05) 且不允许 tercile 回退 → 失败；可用 n&lt;40 → `TRAJECTORY_CLUSTER_FAIL`。写出 `{Index}_trajectory` |

### 3.2 描述与早停

| Block | 产出 | 门控 |
|-------|------|------|
| `competing_flowchart` | Fig 1 纳排/事件流 | — |
| `competing_baseline_quartile` | Table 1（按四分位） | — |
| `competing_lmm_trajectory` | 轨迹均值图 | — |
| `competing_baseline_trajectory` | Table 3（按轨迹） | 若 `early_stop_if_index_ns=TRUE` 且暴露连续值对主事件 Wilcoxon/组间 P ≥ `table3_sig_cutoff`(0.05) → **`BASELINE_INDEX_NS_STOP`**，目录标 `【failed】` |

### 3.3 协变量筛选（核心，不可改顺序）

严格串联：

```
univariate_prognosis → feature_selection_lasso → feature_selection_random_forest
```

**不跑** VIF / multicollinearity / consensus；已删除旧的 `competing_lasso_screen` / `competing_rf_screen`。

#### 3.3.1 单因素 `univariate_prognosis`

| 项 | 设定 |
|----|------|
| 时间 / 事件 | `competing_time_28d` / `competing_primary_event`（主事件=1，死亡与出院按删失） |
| 模型 | 单因素 Cox |
| `sig_cutoff` | 0.05（报告显著） |
| `screening_cutoff` | **0.10** → 写入 `ctx$results$univar_features` |
| 候选池排除 | 全部复合指标、时间、结局、预后列、ID（`univariate_prognosis$excluded_predictors`） |
| 失败 | 无变量 P&lt;0.10 → 阶段 `univariate_prognosis` 失败 |

完整单因素表仍导出；下游 LASSO 只吃 `univar_features`。

#### 3.3.2 LASSO `feature_selection_lasso`

| 项 | 设定 |
|----|------|
| `candidate_source` | **`"univariate"`**（只接收 `univar_features`，不走 Model2Factors） |
| 模型 | prognosis 路径 **Cox-LASSO**（`lasso_use_cox = TRUE`） |
| CV | `lasso_cv_times = 100` |
| 目标特征数 | `target_n_features_min/max = 1..8` |
| 输出 | `ctx$results$feature_selection_by_model$lasso` |
| 失败 | 无入选 → `feature_selection_lasso` |

#### 3.3.3 随机森林 `feature_selection_random_forest`

| 项 | 设定 |
|----|------|
| `candidate_source` | **`"lasso"`**（只接收 LASSO 集合） |
| 方法 | caret RFE + randomForest |
| 目标特征数 | 1..8 |
| 输出 | `feature_selection_by_model$random_forest` + 重要性序 `feature_selection_rf_rank` |
| 失败 | 无入选 → `feature_selection_random_forest` |

**RF 结果是正式效应模型的首选协变量源**；LASSO / 单因素仅作回退层（见下）。

### 3.4 Model 1–6 如何从筛选结果取协变量

实现：`Blocks/55_competing_risk_full/09block_competing_models_123.R`  
函数：`.competing_resolve_model_covs()`。

人口学池（config）：

```r
demographic_vars = c("Age", "Gender", "Race", "BMI")
# baseline_vars 另含 Hypertension/CHD/Smoking/Drinking，用于基线表，不自动等同 Model2
```

| 模型 | 方法 | 协变量 |
|------|------|--------|
| Model 1 | Fine-Gray（主事件 failcode=1） | **无调整** |
| Model 2 | Fine-Gray | **仅人口学** |
| Model 3 | Fine-Gray | Model 2 **全部** + **非人口学**（真超集） |
| Model 4 | Standard Cox（主事件=1，其余删失） | 同 Model 1 |
| Model 5 | Standard Cox | 同 Model 2 |
| Model 6 | Standard Cox | 同 Model 3 |

**Model 2 人口学来源（回退链，取首个非空层的全部人口学）：**

1. RF 入选 ∩ `demographic_vars`
2. 否则 LASSO ∩ 人口学
3. 否则 单因素 P&lt;0.10 ∩ 人口学
4. 三层皆空 → **`MODEL_COVARIATE_INSUFFICIENT`**（该指标失败）

**Model 3 非人口学来源（同一回退链）：**

1. 从 RF → LASSO → 单因素依次取「非人口学且不在 Model 2 中」的变量
2. 取首个非空层，并入 Model 2
3. 仍无非人口学可加 → **`MODEL_COVARIATE_INSUFFICIENT`**

约束：

- 暴露列（`{Index}` / `_quartile` / `_trajectory`）永不进协变量。
- 变量名从因子展开列映射回基列；顺序可复现（RF 按重要性，LASSO 按入选序，单因素按 P 升序）。
- `covs$demo_source` / `nondemo_source` 记录实际命中层，写入 footnote。
- 死亡竞争块 `competing_models_123_death` **复用同一套** `competing_model_covs`。

时间窗：每个模型在 **7 / 14 / 28 天** 三个 horizon 上重截断后拟合（`model_horizons`）。

### 3.5 其余分析块

| Block | 作用 |
|-------|------|
| `competing_finegray` | 辅助 Fine-Gray 表（历史块；主效应以 models_123 为准） |
| `competing_mixed_cox` | 混合效应 Cox 敏感性 |
| `competing_stratified` | 分层分析 |
| `competing_rcs` | RCS 剂量反应（主事件 + 死亡） |
| `competing_cif_plot` | CIF（默认 cause=死亡），按四分位/轨迹 |
| `competing_cox_sensitivity` | Cox 敏感性 |
| `competing_ph_calibration` | PH / 校准 |
| `competing_supp_tables` | Supp1–6：亚组、Handle/No-handle、MI 等 |
| `competing_pub_export` | 文献级 Fig 1–9 + Table 1–4 命名导出；P 值经 `pub_format_p()` |

---

## 4. 产出清单（对齐 Lai Fig1–9 / Table1–4）

| 原文 | 本项目 | Block |
|------|--------|-------|
| Fig 1 流程图 | 纳排 + 事件计数 | `competing_flowchart` |
| Table 1 基线（四分位） | 按 `{Index}_quartile` | `competing_baseline_quartile` |
| Table 2 / Fig 4 CIF 死亡 | CIF 死亡 × 四分位 | `competing_cif_plot` |
| Fig 2 主事件 HR（四分位） | 糖尿病 Fine-Gray+Cox M1–6 | `competing_models_123` + `pub_export` |
| Fig 3 RCS | 糖尿病 + 死亡 RCS | `competing_rcs` |
| Fig 5 死亡 HR（四分位） | 死亡竞争 M1–6 | `competing_models_123_death` |
| Fig 6 轨迹图 | 28 天轨迹 | `competing_lmm_trajectory` |
| Table 3 基线（轨迹） | 按 `{Index}_trajectory` | `competing_baseline_trajectory` |
| Table 4 / Fig 8 CIF 死亡×轨迹 | 同上 | `competing_cif_plot` |
| Fig 7 / 9 主事件/死亡 HR×轨迹 | models_123 / _death | 同上 |

目录约定：

| 项 | 路径 |
|----|------|
| Config | `.../Competing_risk_model_40119388/config_competing_risk_stroke_batch.R` |
| 指标产出 | `by_unit/【success\|failed】{Index}/Figures/` + `Tables/` |
| Checkpoint | `checkpoints/_shared/main/` + `by_unit/.../checkpoints/` |
| 批次汇总 | `Tables/Indicator_availability.csv`、`Batch_summary_all_units.csv` |

成功/失败：流程结束重命名目录为 `【success】{Index}` 或 `【failed】{Index}`；内部 `_batch_status.json` 记 `failed_stage`、原因、轨迹 K、最终协变量、耗时。

---

## 5. 疾病变量与组成变量硬排除

配置：

```r
analysis_exclusion = list(
  disease_vars = c("T1DM", "T2DM", "Diabetes", "HbA1c"),
  component_scope = "current_transitive",
  exclude_other_composite_indices = TRUE,
  exclude_exposure_if_uses_disease_var = TRUE,
  composite_index_vars = .composite_index_vars
)
```

在 `competing_index_exposure` 之后、`trim` / 表导出之前执行，从 raw/cleaned/imputed 分析副本删除：

1. 疾病相关变量；
2. **当前**指标全部直接 + 递归原始组成变量（例：`NLR` → Neutrophil_Count + Lymphocytes；`ALI` 再展开 Weight/Height/Albumin…）；
3. 除当前指标外的其他复合指标；
4. 对应派生泄漏列。

**必须保留：** 当前 `{Index}`、`_quartile`、`_trajectory`、ID、时间、主事件与竞争事件列。

解析失败 → `EXCLUSION_COMPONENT_RESOLVE_FAIL`。  
表级（Table S1 / Table1/3 / 单因素 / LASSO / RF / Model / Supp）均不得再现被删变量。

---

## 6. Config 关键字段（现行模板摘要）

```r
config$data_clean$derive_competing_diabetes_28d <- TRUE

config$univariate_prognosis <- list(
  sig_cutoff = 0.05,
  screening_cutoff = 0.10,
  fail_on_index_ns = FALSE,
  excluded_predictors = c(.composite_index_vars, "competing_time_28d",
                          "competing_status_28d", "competing_primary_event",
                          "hosp_day", "is_hosp_dead", "ID", "subject_id", ...)
)

config$feature_selection_lasso <- list(
  candidate_source = "univariate",
  lasso_use_cox = TRUE,
  lasso_cv_times = 100L,
  target_n_features_min = 1L,
  target_n_features_max = 8L
)

config$feature_selection_random_forest <- list(
  candidate_source = "lasso",
  target_n_features_min = 1L,
  target_n_features_max = 8L
)

config$competing_risk <- list(
  hba1c_threshold = 6.5,
  followup_days = 28L,
  time_var = "competing_time_28d",
  event_type_col = "competing_status_28d",
  primary_cause = 1L,
  death_cause = 2L,
  cif_cause = 2L,
  model_horizons = c(7L, 14L, 28L),
  early_stop_if_index_ns = TRUE,
  table3_sig_cutoff = 0.05,
  trajectory_min_class_prop = 0.05,
  trajectory_allow_tercile_fallback = FALSE,
  demographic_vars = c("Age", "Gender", "Race", "BMI"),
  baseline_vars = c("Age", "Gender", "Race", "BMI",
                    "Hypertension", "CHD", "Smoking", "Drinking"),
  trim_quantile = 0.01
)

pipeline_shared$blocks <- c(
  "data_clean", "column_mapping", "dual_db_column_harmonize",
  "index", "trajectory_calc_28d_index"
)

pipeline_unit$blocks <- c(
  "imputation", "competing_index_exposure", "analysis_exclusion",
  "trim_index_extreme", "competing_trajectory_cluster",
  "competing_flowchart", "competing_baseline_quartile",
  "competing_lmm_trajectory", "competing_baseline_trajectory",
  "univariate_prognosis", "feature_selection_lasso",
  "feature_selection_random_forest",
  "competing_finegray", "competing_mixed_cox",
  "competing_models_123", "competing_models_123_death",
  "competing_stratified", "competing_rcs", "competing_cif_plot",
  "competing_cox_sensitivity", "competing_ph_calibration",
  "competing_supp_tables", "competing_pub_export"
)
```

---

## 7. 协变量选择决策树（摘要）

```
候选池（插补后、已硬排除疾病/组成/其他指标）
        │
        ▼
  单因素 Cox，P < 0.10 ──无──► 失败 univariate_prognosis
        │有
        ▼
  Cox-LASSO（候选=单因素）──无──► 失败 feature_selection_lasso
        │有
        ▼
  RF-RFE（候选=LASSO）──无──► 失败 feature_selection_random_forest
        │有
        ▼
  ┌─ Model1/4: 空
  ├─ Model2/5: RF∩人口学 → 否则 LASSO∩人口学 → 否则 UV∩人口学
  │            仍空 → MODEL_COVARIATE_INSUFFICIENT
  └─ Model3/6: Model2 + (RF非人口学 → 否则 LASSO → 否则 UV)
               仍无非人口学 → MODEL_COVARIATE_INSUFFICIENT
```

原则：**不允许为显著性反复试选协变量**；顺序与来源必须可复现并落盘。

---

## 8. 常见失败码

| 码 | 阶段 | 含义 |
|----|------|------|
| `INDEX_NO_DATA_STOP` | index_exposure | 无 `12_{Index}.RData` 或日列空 |
| `INDEX_MIN_N_STOP` | index_exposure | 基线非缺失 n 过小 |
| `EXCLUSION_COMPONENT_RESOLVE_FAIL` | analysis_exclusion | 指标公式解不出组成变量 |
| `TRAJECTORY_CLUSTER_FAIL` | trajectory_cluster | trim 后可聚类 n&lt;40 或类占比过小 |
| `BASELINE_INDEX_NS_STOP` | baseline_trajectory | Table3 暴露不显著早停 |
| （空 univar） | univariate_prognosis | 无 P&lt;0.10 变量 |
| （空 lasso/rf） | feature_selection_* | 该层无入选 |
| `MODEL_COVARIATE_INSUFFICIENT` | models_123 | 无法构成合法 Model2/3 |

---

## 9. 验证计划

1. `--shared-only`：检查 `competing_time_28d` / `competing_status_28d` 分布（0–3）与队列行数。
2. `--only-unit NLR`：核对  
   `univar_features → lasso → random_forest → competing_model_covs`，且 Model2 ⊂ Model3。
3. 抽样手工核对 time/status（HbA1c 日 vs 死亡/出院日）。
4. 确认 Table/模型协变量中无疾病变量、当前组成变量、其他复合指标。
5. 含 HbA1c/Diabetes 组分的指标不在 `study_batch$units` 中。
6. 小批量 → 全量 `--workers 20`。

---

## 10. 不在范围

- 不修改 CHF 原模板 `config_competing_risk_chf_batch.template.R`。
- 不追求与 Lai 原文数值一致（队列不同）。
- 本规格不覆盖 AKI 版结局定义细节（共用 block 壳，换 derive / disease_vars 即可）。
- 不伪造结果；失败指标保留 `【failed】` 目录供汇总，不并入主结果。
