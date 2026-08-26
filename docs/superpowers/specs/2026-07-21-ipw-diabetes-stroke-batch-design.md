# IPW 糖尿病 × 重症缺血性卒中（28 天全因死亡 / 复合指标并行）设计规格

> 状态：待用户审阅  
> 方法学来源：Jin et al. 2026 Breast Cancer Res Treat（用药模型三分.pdf；PMRT × IPW）  
> 研究问题：糖尿病（HbA1c≥6.5%）与重症缺血性卒中患者 28 天全因死亡风险的关联（MIMIC，逆概率加权）  
> 数据/产出根：`BLOCK_RESULT_ROOT/11_ischemic stroke/Medication_regimen_model_42118193/`  
> 已确认方案：方案 1（发病同构 batch + `Blocks/69_ipw_diabetes_stroke_full`）

## 0. 已锁定决策

| 项 | 选择 |
|----|------|
| Batch 单元 | 复合指标并行（糖尿病暴露固定） |
| Worker 同构 | 共享层算全指标；worker 内糖尿病 IPW 主链 + 当前指标进协变量链 |
| 糖尿病定义 | `HbA1c ≥ 6.5`（%） |
| 项目目录 | 沿用 `Medication_regimen_model_42118193` |
| 硬排除 | 与竞争风险同构（`T1DM/T2DM/Diabetes/HbA1c` + 含病变量指标不入队 + 组成变量删除） |
| 新模块 | `Blocks/69_ipw_diabetes_stroke_full/` |
| 飞书 | `app_token = RBjfb2iwmamW14s4WhKcS7kwnie` |
| 发表镜像 | `mirror_pub_outputs_to_root = TRUE` |
| R | `"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"` |

## 1. 研究问题（方法学映射）

| 维度 | 原文（Jin 2026） | 本项目 |
|------|------------------|--------|
| 队列 | NCDB 乳腺癌 cN+→ypN0 | MIMIC 重症缺血性卒中 |
| 暴露分组 | 放疗 vs 未放疗 | 糖尿病 vs 非糖尿病（HbA1c≥6.5） |
| 倾向评分 | 11 项基线 logistic | 人口学、合并症、卒中严重程度 + 筛选协变量（含当前复合指标，不含暴露定义列） |
| 加权 | IPW | IPW；敏感性另做重叠权重 |
| 结局 | 总生存（OS） | 28 天全因死亡 |
| 主分析 | 加权 KM + IPW-Cox | 同左 |
| 亚组 | 年龄、分子分型、cN 等 | 年龄、性别、卒中严重程度等（config 可扩） |
| STEPP | 5 年 OS × 复合风险 | **28 天生存率** × 复合风险 |
| 敏感性 | 多变量 Cox | 多变量 Cox + 重叠权重 |

暴露派生默认在 **MICE 插补后** 由 HbA1c 计算；原始 HbA1c 不进入 PS/协变量（硬排除）。

## 2. 产出清单（每指标一套；图/表一个都不能少）

| 原文 | 本项目文件键 | 实现 |
|------|--------------|------|
| Fig.1 CONSORT | `Figure_1_Flowchart` | `ipw_diabetes_flowchart`（69） |
| Table 1 基线 + 未加权/加权 SMD | `Table_1_Baseline_IPW` | `iptw_balance`（34）+ 发表导出 |
| Fig.2 IPW-KM | `Figure_2_IPW_KM` | `ipw_weighted_km_pub`（69） |
| Fig.3 亚组森林 + P-interaction | `Figure_3_Subgroup_Forest` | `subgroup_iptw_weighted` + `subgroup_treatment_forest`（18） |
| Fig.4 关键亚组 KM | `Figure_4_Subgroup_KM` | `ipw_subgroup_km_pub`（69）；严重程度二分类对应原文 cN 分层 |
| Fig.5 STEPP | `Figure_5_STEPP` | `stepp_prognosis`（32），终点改为 28 天 |
| 敏感性：多变量 Cox | `Table_Sens_Multivariable_Cox` | `cox_binary`（10） |
| 敏感性：重叠权重 | `Table_Sens_Overlap_Weights`（+可选 KM） | `ipw_overlap_weights`（69） |
| Supp Fig.S1 缺失热图 | `Figure_S1_Missing` | `imputation`（项目新增；原文无） |
| Supp Fig.S2 PS+SMD | `Figure_S2_PS_SMD` | `iptw_balance`（对齐原文 Fig.S1） |
| Supp Fig.S3 未加权 KM | `Figure_S3_Unweighted_KM` | `ipw_weighted_km_pub`（对齐原文 Fig.S2） |
| Supp Fig.S4 校准+ROC | `Figure_S4_Calibration_ROC` | `ipw_surv_calibration_roc`（对齐原文 Fig.S3） |
| Supp Table.S1 STEPP 系数 | `Table_S1_STEPP_Composite` | `stepp_prognosis` |
| Batch 汇总 | `Indicator_availability` / `Batch_summary` | runner + 飞书 |

P 值发表格式：`<0.001` / 三位小数 / `>0.999`；CSV 保留原始值。

## 3. 架构

### 3.1 三层 batch（发病同构）

```
层 A 共享（1 次）
  data_clean → column_mapping → index
  Gate：剔除公式含 T1DM/T2DM/Diabetes/HbA1c 的复合指标
  → checkpoints/_shared/

层 B Worker（每复合指标一路并行）
  复制 shared → 只留当前指标 → 滤 NA
  → imputation
  → ipw_diabetes_exposure          # 先由 HbA1c 派生 Diabetes_HbA1c
  → analysis_exclusion             # 再硬删 HbA1c/诊断列；保留 Diabetes_HbA1c
  → trim_index_extreme             # 可选
  → univariate_prognosis
  → feature_selection_lasso
  → feature_selection_random_forest
  → iptw_balance → iptw_association
  → ipw_diabetes_flowchart
  → ipw_weighted_km_pub            # Fig2 + S2
  → subgroup_iptw_weighted + subgroup_treatment_forest
  → ipw_subgroup_km_pub            # Fig4
  → stepp_prognosis                # Fig5 + Table S1
  → cox_binary                     # 多变量敏感性
  → ipw_overlap_weights
  → ipw_literature_targets
  → ipw_pub_export
  → 【success】/【failed】{Index} + _batch_status.json

层 C 汇总
  Indicator_availability + Batch_summary → 飞书（新 base）
```

### 3.2 路径约定

| 项 | 路径 |
|----|------|
| 结果根 | `{BLOCK_RESULT_ROOT}/11_ischemic stroke/Medication_regimen_model_42118193/` |
| 数据 | `{结果根}/data/` |
| Config 模板 | `configs/templates/config_ipw_diabetes_stroke_batch.template.R` |
| 项目 config | `{结果根}/config_ipw_diabetes_stroke_batch.R`（部署时从模板复制） |
| Run | `run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R` + `_worker.R` |
| 决策树 | `Decisiontree/decision_tree_ipw_diabetes_stroke.md` |
| 新 Block | `Blocks/69_ipw_diabetes_stroke_full/` |
| 编排 | 复用 `R/study_batch_runner.R` |

`BLOCK_RESULT_ROOT` 优先环境变量，否则 `/mnt/g/02block_result`（与现有 `.env.feishu` 一致）。

### 3.3 硬排除

```r
analysis_exclusion = list(
  disease_vars = c("T1DM", "T2DM", "Diabetes", "HbA1c"),
  component_scope = "current_transitive",
  exclude_other_composite_indices = TRUE,
  exclude_exposure_if_uses_disease_var = TRUE
)
```

- **顺序强制**：`ipw_diabetes_exposure` 必须在 `analysis_exclusion` **之前**，否则 HbA1c 被删后无法派生暴露
- 保留派生暴露列 `Diabetes_HbA1c`（排除名单作用于原始疾病/HbA1c 列，不删除暴露二分类）
- 含病变量的复合指标单元不进入 shared 后任务队列
- `time_var` / `event_var` / 亚组严重程度列名：实现前用 `data/` 实测填入 config，规格中的 `NULL` 仅表示「待实测」，不是运行时允许为空

### 3.4 复用 vs 新建

**复用（不改源码）：** `data_clean`、`column_mapping`、`index`、`imputation`、`analysis_exclusion`、`univariate_prognosis`、`feature_selection_lasso`、`feature_selection_random_forest`、`iptw_balance`、`iptw_association`、`km_*`、`cox_binary`、`subgroup_iptw_weighted`、`subgroup_treatment_forest`、`stepp_prognosis`、`trim_index_extreme`。

**新建 `69_ipw_diabetes_stroke_full/`：**

| 文件 | register_block |
|------|----------------|
| `01block_ipw_diabetes_exposure.R` | `ipw_diabetes_exposure` |
| `02block_ipw_flowchart.R` | `ipw_diabetes_flowchart` |
| `03block_ipw_weighted_km_pub.R` | `ipw_weighted_km_pub` |
| `04block_ipw_overlap_weights.R` | `ipw_overlap_weights` |
| `05block_ipw_subgroup_km_pub.R` | `ipw_subgroup_km_pub` |
| `06block_ipw_literature_targets.R` | `ipw_literature_targets` |
| `07block_ipw_pub_export.R` | `ipw_pub_export` |

在 `R/pipeline_runner.R` **仅追加**上述映射，不改动既有条目。

## 4. Config 关键字段（草案）

```r
config$project <- list(
  name = "IPW_Diabetes_Stroke_MIMIC",
  disease_code = "11",
  study_type = "prognosis",
  literature_ref = "Jin2026_IPW_PMRT_mapped",
  database = "MIMIC",
  output_dir = .batch_project_root,
  mirror_pub_outputs_to_root = TRUE
)

config$ipw_diabetes <- list(
  hba1c_var = "HbA1c",
  hba1c_threshold = 6.5,
  exposure_var = "Diabetes_HbA1c",
  followup_days = 28L,
  time_var = NULL,   # 以 data/ 实测列名为准写入
  event_var = NULL
)

config$study_batch <- list(
  index_vars = NULL,
  parallel_workers = "auto",
  skip_existing = TRUE
)

config$feishu <- list(
  enable = TRUE,
  app_token = "RBjfb2iwmamW14s4WhKcS7kwnie"
  # table_id 在飞书建表后写入
)
```

亚组默认：`Age`、`Gender`、卒中严重程度变量（列名以数据实测为准，写入 config，禁止块内写死）。

## 5. 并行、错误处理与运行命令

- Windows R：`processx` 派发 worker；目录标签 `【success】` / `【failed】`
- `_batch_status.json` 记录 `failed_stage`、`error_message`、协变量、耗时
- Batch 默认 `pause_enable = FALSE`
- 缺 R 包装进 R-4.5.1 library；R 无法实现的算法再接既有 ML python 环境

```bash
R="/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
"$R" run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R \
  --config ".../config_ipw_diabetes_stroke_batch.R" --shared-only --no-skip
"$R" run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R \
  --config "..." --only-unit NLR --workers 1 --no-skip
"$R" run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R \
  --config "..." --workers 20 --no-skip
```

## 6. 验收标准

1. NLR 单指标：Fig1–5、Table1、Sens（多变量 Cox + 重叠权重）、S1/S2/S1表 文件齐全  
2. 硬排除审计通过（表/PS/筛选无 HbA1c 原列与诊断泄漏；含病指标未入队）  
3. 协变量链可复现；发表 P 值格式正确  
4. 可启动多路并行；根目录有 `Indicator_availability`  
5. 飞书新 base 有套路/结果记录  
6. 决策树、config 模板、run 入口齐全；未改动 `55`/`58` 等既有项目  

## 7. 不在范围

- 不修改既有 `58_medication_regimen_*`、`55_competing_risk_*` 及其他已完成项目源码  
- 不强制覆盖全局 `.env.feishu`（本项目 config 覆盖新 base）  
- 数据路径未挂载时只 scaffold，不伪造分析结果  
- 不追求与 Jin 原文数值一致（队列与暴露均不同）  
- 本规格阶段不做对抗式文献阅读 JSONL（除非用户另开任务）

## 8. 方案对比（归档）

| 方案 | 描述 | 结论 |
|------|------|------|
| **1（采用）** | 发病同构 batch + 69 专用块 + 复用 34/27/10/18/32/19 | 选中 |
| 2 | 几乎全复用、少建块 | 难满足文献完整深度 |
| 3 | 先单指标再补 batch | 与「都要 batch」交付不一致 |
