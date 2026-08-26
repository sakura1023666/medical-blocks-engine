# Block Extraction Report

paper_id: paper_004  
question_id: Q1  
judge_source: @labels/paper_004_Q1_training.jsonl（score=9；取 `chosen_decision_tree` + `evidence` + `critique`）  
paper: @chunks/paper_004_mmc7.md  
user_data_probe: @Data/mimic/D04_dabiao.RData（只读探查，未写实例 config）  
reuse_template: `configs/templates/config_survival_sae.template.R` + `configs/templates/config_incidence_iptw.template.R` → **已新建** `config_survival_iptw_pooled.template.R`  
run_entry: `run_survival_iptw_pooled.R`

---

## 0. Judge 定稿要点（驱动 block 抽取）

| 来源 | 要点 |
|---|---|
| chosen N1 | 无聚类/LCA 定 K；核心分组均为先验/外部标准（Yes/No、有效性 good/poor+参照、World Bank 收入、probable dementia 算法） |
| chosen N3 | 有效性 = **使用者内 2 类** + 非使用者参照；分析共 3 比较组（非「3 类有效性」） |
| chosen N7 | IPTW + Cox PH + **cohort shared frailty**；PH 仅图形检验；**无 RCS/剂量反应** |
| chosen N10/N12 | pooled/HIC：仅有效组保护、无效组 null；**MIC：有效组与无效组均显著保护（HR≈0.70）** — 方向结论有国别异质性 |
| chosen N_SEL | selection-into-effectiveness 混杂；有效→低风险不能仅归因干预 |
| chosen N14/N_SA1/N_EV | 观察性无法确立因果；作者已用 SA1（排除前 3 年）+ E-value 缓解/量化残余混杂 |
| critique | 初版遗漏 frailty、E-value、分层 MIC 无效组、选择混杂分支；修正版已吸收 |

---

## 0b. 用户数据只读探查（wizard 阶段 2）

| 项 | 实测 |
|---|---|
| 路径 | `Data/mimic/D04_dabiao.RData` |
| 对象 | `dabiao`（3306 × 70） |
| ID 列 | `subject_id` |
| 结局列 | `Disease_Group`：`Continent` 2910 / `Urinary_Incontinence` 396 |
| 生存列 | **无** `futime` / `fustatus` / `time` / `event` |
| 文献核心列 | **无** 助听器使用 / 有效性自评 / probable dementia / 队列标识 / 国家收入 |
| 可映射暴露 | `MCV`（连续实验室指标，≠ 文献助听器暴露） |
| NHANES 设计列 | **无** 调查权重/PSU/分层 |

**结构差异（须在 wizard 确认）：**

- paper_004 套路 = **7 队列 harmonized 纵向生存 + IPTW-Cox + shared frailty + 收入分层 + 有效性三分比较 + 大量敏感性分析**。
- `D04_dabiao` = **MIMIC 横断面二分类结局、无随访时间、无 IPTW 暴露定义**。
- 本步产出为**研究型通用模板**（`config_survival_iptw_pooled.template.R`），**不能**直接把 `D04_dabiao` 填入试跑。
- 若目标为「用 MIMIC 做类似关联」，更接近已有 `run_incidence_iptw.R`（Logistic+IPTW），而非本 survival 模板；须 wizard 确认研究设计与数据列。

---

## 1. 统计方法 → Block 映射（按 Results 顺序）

> Methods 与 Results 不一致时以 Results 为准。顺序对齐：Population characteristics → Use（Fig 2/3）→ Effectiveness（Fig 4/5）→ 敏感性（Fig S3/S5）。

| step | 文献分析 | 模型/检验 | 预期表/图 | 对应 block | 状态 |
|---|---|---|---|---|---|
| 0 | 7 队列纳入与 harmonization | 预设纳入标准 + 变量对齐 | Fig S1 | `dual_db_column_harmonize` + `dual_db_covariate_harmonize` | 已有(需适配：生存结局/暴露 harmonization) |
| 1 | 多重插补（仅协变量） | MICE/CART | — | `data_clean` → `column_mapping` → `imputation` | 已有 |
| 2 | 基线描述（按收入分层） | 加权/未加权描述统计 | Table 1 / S12 | `baseline_binary`（`strata` 按收入/队列） | 已有(需适配：分层变量预设) |
| 3 | IPTW 平衡（使用 vs 未使用） | 二元 logistic PS → IPTW；SMD≤0.1 | Table S13 | `iptw_balance` | 已有(**runner 未注册**) |
| 4 | IPTW 平衡（有效性三分） | **multinomial** logistic PS → IPTW | Table S14 | — | **缺失 GAP3** |
| 5 | 主分析：助听器使用 vs 痴呆 | **IPTW-weighted Cox PH + shared frailty** | Fig 2 pooled | — | **缺失 GAP1** |
| 6 | 收入国分层（高/中） | 分层 IPTW-Cox | Fig 2 HIC/MIC | — | **缺失 GAP7** |
| 7 | E-value（使用暴露） | E-value 量化未测混杂 | Fig 2 脚注 | — | **缺失 GAP5** |
| 8 | 队列别补充分析 | 分队列 IPTW-Cox | Fig S2 | `cox_binary`（无 IPTW/无 frailty） | 已有(需适配；**不能复现主分析**) |
| 9 | 敏感性分析包（使用） | SA1–SA10（排除前 3 年、≥60 岁、≥2 波次等） | Fig S3 | — | **缺失 GAP6** |
| 10 | 亚组 + 交互（使用） | 预设分层 + 乘积项 LRT；Bonferroni | Fig 3 | `cox_interaction` 或 `subgroup_prognosis` | 已有(需适配；`cox_interaction` **runner 未注册**；无 IPTW 权重) |
| 11 | 主分析：有效性 good/poor vs 参照 | IPTW-Cox 三分比较 + frailty | Fig 4 pooled | — | **缺失 GAP2** |
| 12 | 有效性收入分层 | 分层 IPTW-Cox（MIC 两组均显著） | Fig 4 HIC/MIC | — | **缺失 GAP7** |
| 13 | E-value（有效性） | E-value | Fig 4 脚注 | — | **缺失 GAP5** |
| 14 | 队列别有效性 | 分队列 Cox | Fig S4 | `cox_binary` / `cox_subphenotype` | 已有(需适配) |
| 15 | 敏感性分析包（有效性） | SA1–SA11（含竞争风险 SA11） | Fig S5 | — | **缺失 GAP6** |
| 16 | 亚组 + 交互（有效性） | 预设分层 + SDI 交互 | Fig 5 | `cox_interaction` / `subgroup_prognosis` | 已有(需适配) |
| 17 | PH 假设 | log-cumulative hazard 图（无 formal test） | Methods | （扩展现有 Cox block 参数） | 分析细节 |
| 18 | 竞争风险模型 | SA11：死亡竞争风险 | Fig S5 SA11 | — | **缺失 GAP8** |
| — | RCS/剂量反应 | **未做**（Judge N11） | — | `rcs_*` | **刻意排除** |
| — | 聚类/LCA 定 K | **未做**（Judge N1） | — | `lca` / `unsupervised_clustering_table` | 不适用 |

**刻意未纳入 pipeline（相对 survival_sae 模板）：**

- `cox_quartile` / `cox_tertile` / `cox_gate` 降级链：论文暴露为**先验二分/三分**，非数据驱动分位探索（Judge Q1）。
- `rcs_prognosis` / `rcs_iptw_weighted`：原文明确无 RCS（N11）。
- `univariate_*` / `multicollinearity_*` / `multivariate_*`：论文**固定全协变量 IPTW+Cox**，非逐步筛选（类比 paper_003）。
- `logistic_*_iptw_weighted`：文献主分析为 **Cox 生存**，非横断面 Logistic（库内仅有 Logistic IPTW，模型族不匹配）。

---

## 2. pipeline$blocks 顺序（建议）

```r
c(
  "data_clean",
  "column_mapping",
  "dual_db_column_harmonize",       # step 0：多队列 harmonization
  "dual_db_covariate_harmonize",
  "imputation",                     # step 1
  "baseline_binary",                # step 2：Table 1
  "iptw_balance",                   # step 3：二元 PS（Table S13）
  "iptw_association",
  # "iptw_balance_multinomial",     # GAP3：有效性 PS（Table S14）
  # "cox_binary_iptw_weighted",     # GAP1：Fig 2 pooled
  # "stratified_cox_preset",        # GAP7：Fig 2/4 收入分层
  # "e_value_cox",                  # GAP5：E-value
  "cox_binary",                     # 占位近似（无 IPTW/frailty；待 GAP1 替换）
  # "cox_effectiveness_3group_iptw",# GAP2：Fig 4
  "cox_interaction",                # step 10/16：交互（runner 待补映射）
  "subgroup_prognosis",             # step 10/16：森林图分层
  # "sensitivity_cox_suite",        # GAP6：SA1–SA11
  # "competing_risk_cox"            # GAP8：SA11
)
```

顺序约束：`data_clean` → `column_mapping` → harmonize → `imputation` → `baseline_*` → IPTW → 主 Cox → 分层/亚组/交互 → 敏感性；**无 RCS**；VIF/单因素链可选关停。

---

## 3. 缺失 Block 清单

| gap_id | 文献做法 | 建议新 block | 建议目录 | 严重度 | 影响主结论? | 备注 |
|---|---|---|---|---|---|---|
| GAP1 | IPTW-weighted Cox PH（使用 vs 未使用）+ cohort **shared frailty** | `cox_binary_iptw_weighted` | `Blocks/10_cox/` | **高** | **是** | 现有 `cox_binary` 无 IPTW 权重、无 frailty；`logistic_binary_iptw_weighted` 模型族错误 |
| GAP2 | IPTW-Cox 有效性 **3 比较组**（good / poor / 参照） | `cox_effectiveness_3group_iptw` | `Blocks/10_cox/` | **高** | **是** | Fig 4 主分析；需参照组编码与使用者内 2 类暴露 |
| GAP3 | **Multinomial** IPTW（no/good/poor）+ SMD 平衡 | `iptw_balance_multinomial` | `Blocks/34_IPTW/` | **高** | **是** | 现有 `iptw_balance` 仅二元 Index_Group（logistic PS） |
| GAP4 | Cox **shared frailty**（队列随机效应） | 扩展 `cox_binary_iptw_weighted` 或 `cox_frailty_shared` | `Blocks/10_cox/` | **高** | **是** | 多队列 pooled 模型骨架（Judge A3） |
| GAP5 | **E-value** 量化未测混杂（pooled/HIC/MIC） | `e_value_cox` | `Blocks/35_sensitivity/`（新建） | 中 | 否（因果防御） | Judge N_EV/E16；库内完全缺位 |
| GAP6 | 敏感性分析套件 SA1–SA11（排除前 3 年、竞争风险等） | `sensitivity_cox_suite` | `Blocks/35_sensitivity/` | 中 | 否（稳健性） | SA1 已缓解反向因果（Judge N_SA1） |
| GAP7 | 按**预设外部分层**（高/中收入国）重复主 Cox | `stratified_cox_preset` | `Blocks/10_cox/` 或 `Blocks/18_subgroup/` | 中 | **是**（MIC 异质性） | MIC 无效组亦显著保护，分层为 Q1 核心修正点 |
| GAP8 | 竞争风险 Cox（死亡为竞争事件，SA11） | `competing_risk_cox` | `Blocks/10_cox/` | 低 | 否 | 敏感性之一 |
| GAP9 | 生存结局 harmonized 操作定义（probable dementia 算法） | 扩展 `dual_db_*` 或预处理 | `Blocks/00_dual_db/` | 中 | 是（结局定义） | 认知+功能双损或医生诊断；宜 wizard 前人工派生 |
| GAP10 | selection-into-effectiveness 混杂敏感性 | 扩展 `sensitivity_cox_suite` 或 E-value 分层 | `Blocks/35_sensitivity/` | 低 | 否 | Discussion 讨论点（Judge N_SEL）；非独立主分析 block |

**分析细节（不需新建 block）：**

- PH 假设仅图形检验、无 Schoenfeld 统计量 → 现有 Cox block 加 `ph_test_mode="graphical"` 参数。
- Bonferroni 亚组校正 → `subgroup_prognosis` / `cox_interaction` 加 `p_adjust="bonferroni"`。
- 单时点 baseline 暴露、interval censoring、问法 harmonization 差异 → 数据预处理/局限说明，非 block。

---

## 4. 模板复用 / 最小 diff

**复用** `config_survival_sae.template.R`（Cox 生存骨架）+ **借鉴** `config_incidence_iptw.template.R`（IPTW 段）→ **已新建** `configs/templates/config_survival_iptw_pooled.template.R`

| diff 项 | survival_sae 模板 | survival_iptw_pooled 模板 |
|---|---|---|
| 语义 | 单库 MIMIC 预后 Cox（RAR×SAE） | 多队列 pooled **IPTW-Cox**（暴露×时间至事件结局） |
| `study_type` | `prognosis` | `prognosis`（保留 Cox/KM block 族） |
| 暴露/结局 | `RAR` / `fustatus`+`futime` | `<Exposure_Use>` / `<Outcome_Event>`+`<Time_Var>` 占位 |
| 筛选链 | 单因素→VIF→多因素 | **注释关停**（论文固定协变量全模型） |
| Cox 分位链 | quartile→tertile→binary gate | **移除**（先验二分/三分暴露） |
| RCS/KM | 有 | RCS **移除**；KM 可选保留 |
| IPTW | 无 | 加入 `iptw_balance` + `iptw_association`（二元）；GAP3 注释占位 |
| dual_db | 关闭 | **启用** harmonize 段（多队列） |
| 主 Cox | `cox_binary`（无权重） | 注释 `cox_binary_iptw_weighted`（GAP1）；暂留 `cox_binary` 占位 |
| 亚组/交互 | `subgroup_prognosis` | + `cox_interaction`；`subgroup_iptw_weighted` 待 GAP1 后启用 |
| GAP1–GAP8 | — | `# TODO(GAP*)` 注释占位 |

**run 薄入口：** `run_survival_iptw_pooled.R`（默认 `--config configs/templates/config_survival_iptw_pooled.template.R`）

**未写论文级实例 config**；占位符须经 wizard 回填。

---

## 5. config / run 骨架（已落地，占位符待 wizard）

### config 关键占位符（❓ 须交互确认）

```r
config$data$rawdata_path          = "Data/<TO_CONFIRM>/harmonized_cohorts.RData"
config$data$rawdata_obj           = "<TO_CONFIRM>"
config$data$outcome_column        = "<Outcome_Event>"      # 非文献列名
config$data$time_column           = "<Time_Since_Baseline>"
config$data$id_column             = "<Subject_ID>"
config$data$cohort_column         = "<Cohort_ID>"          # shared frailty
config$survival$index_var         = "<Exposure_Use>"      # 或有效性变量
config$project$analysis_group     = "<Case_Label>"
config$project$reference_group    = "<Ref_Label>"
config$project$output_dir         = "Output/<Study_Name>"
config$project$mirror_pub_outputs_to_root   # TRUE/FALSE 须确认
config$iptw_balance$exposure_var  = "<Exposure_Use_Binary>"
config$pipeline$checkpoint$dir
```

### run 建议命令（**未执行**）

```bash
Rscript run_survival_iptw_pooled.R --list-checkpoints
# wizard 试跑 smoke test（须先补 runner 映射 + 实例 config）:
# Rscript run_survival_iptw_pooled.R --to imputation
```

---

## 6. runner 映射核对

### 6a. 文献所需 block — 注册状态

| block | Blocks/ 源文件存在? | `pipeline_block_sources()` 注册? | 备注 |
|---|---|---|---|
| `data_clean` / `column_mapping` / `imputation` | ✓ | ✓ | |
| `dual_db_column_harmonize` / `dual_db_covariate_harmonize` | ✓ | ✓ | |
| `baseline_binary` | ✓ | ✓ | |
| `iptw_balance` / `iptw_association` | ✓ | **✗ 未注册** | `Blocks/34_IPTW/` 已实现 |
| `cox_binary` | ✓ | ✓ | 无 IPTW/frailty |
| `cox_interaction` | ✓ | **✗ 未注册** | `Blocks/10_cox/06block_cox_interaction.R` |
| `subgroup_prognosis` | ✓ | ✓ | 无 IPTW 权重 |
| `subgroup_iptw_weighted` | ✓ | **✗ 未注册** | 待 GAP1 后配套 |
| `logistic_binary_iptw_weighted` 等 | ✓ | **✗ 未注册** | 模型族不匹配文献 |
| **`cox_binary_iptw_weighted`（GAP1）** | **✗** | **✗** | 须新建 + 注册 |
| **`cox_effectiveness_3group_iptw`（GAP2）** | **✗** | **✗** | 须新建 + 注册 |
| **`iptw_balance_multinomial`（GAP3）** | **✗** | **✗** | 须新建 + 注册 |
| **`e_value_cox`（GAP5）** | **✗** | **✗** | 须新建 + 注册 |
| **`sensitivity_cox_suite`（GAP6）** | **✗** | **✗** | 须新建 + 注册 |
| **`stratified_cox_preset`（GAP7）** | **✗** | **✗** | 须新建 + 注册 |
| **`competing_risk_cox`（GAP8）** | **✗** | **✗** | 须新建 + 注册 |

> **系统性缺口**：`config_incidence_iptw.template.R` 引用的 `iptw_balance`、`logistic_*_iptw_weighted`、`subgroup_iptw_weighted`、`rcs_iptw_weighted` 均**已在 Blocks/ 实现但未写入 `R/pipeline_runner.R`**。本步**不修改 R/**，须在后续开发中统一补映射。

---

## 7. wizard 交互门待办（写实例 config 前）

1. **确认研究目标**：复现 paper_004（需 harmonized 纵向数据 + 生存列） vs 用 MIMIC `D04_dabiao` 做**横断面 Logistic+IPTW**（走 `run_incidence_iptw.R`）？
2. **确认疾病/结局/暴露/时间列**：不得照搬文献「助听器/痴呆」列名；`D04_dabiao` 当前无生存列。
3. **确认** `mirror_pub_outputs_to_root`、`output_dir`、是否启用 dual_db。
4. **输出并确认分析决策树**（见对话 mermaid）后再写 `configs/config_*.R` 实例。
5. **补 runner 映射 + 缺失 block 开发**后，用户同意试跑再执行 `Rscript`。

---

> **强制规则确认**：只写/更新 `configs/templates/config_survival_iptw_pooled.template.R`、`run_survival_iptw_pooled.R`、`rounds/block_gap_paper_004_Q1.md`；未改动 Blocks/、R/、已有 configs、A/B/Judge 产物；缺失 block 只登记不实现；**未试跑**。
