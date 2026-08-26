# Block Extraction Report

paper_id: paper_003  
question_id: Q1  
judge_source: @labels/paper_003_Q1_training.jsonl（score=10；取 `chosen_decision_tree` + `evidence` + `critique`）  
paper: @chunks/paper_003_2024_zhou_2024_association_between_cardiometabolic_index_and_depression_national_health_and_nutrition_examination.md  
user_data_probe: @Data/mimic/D04_dabiao.RData（只读探查，未写实例 config）  
reuse_template: configs/templates/config_incidence_nhanes.template.R → **已落地** `config_association_nhanes.template.R`  
run_entry: `run_association_nhanes.R`

---

## 0. Judge 定稿要点（驱动 block 抽取）

| 来源 | 要点 |
|---|---|
| chosen 决策树 N1 | 无聚类/LCA 定 K；并行多套切分（先验 + RCS **混合驱动**） |
| N5a / N7 | RCS 结点数先验设定；拐点**位置**数据驱动；结点数未披露 |
| N6 / N22 | tertile 三分位主观指定；加权分位点口径原文未说明 |
| N9 ↔ N7/N8 | 连续 logistic 单调假设 vs RCS 显著非线性（内部张力） |
| N10 / N10L | Wakabayashi 高血糖/糖尿病界值跨结局借用；全调整后不显著 |
| N11 / N17 / N21 | 亚组+饮酒交互；3→2 类合并疑似事后；never/former 亚组倒 U |
| N14–N20 | 横断面、选择偏倚、多重比较未校正、小事件数等限定 |
| critique | 边语义/数据驱动纯度/内部张力/缺失分支已在 Round2 吸收；GAP 聚焦库能力 |

---

## 0b. 用户数据只读探查（wizard 阶段 2）

| 项 | 实测 |
|---|---|
| 路径 | `Data/mimic/D04_dabiao.RData` |
| 对象 | `dabiao`（3306 × 70）、辅助对象 `p`（character） |
| ID 列 | `subject_id`（非 NHANES `SEQN`） |
| 结局列 | `Disease_Group`：`Continent Urinary_Incontinence` 2910 / 另一水平 396 |
| NHANES 设计列 | **无** `WTMEC2YR` / `SDMVPSU` / `SDMVSTRA` |
| 文献核心列 | **无** `CMI` / `PHQ-9` / `VAI` / `LAP` / `TyG` |
| 高缺失示例 | `TT`/`U_ALB`/`UACR` 等 >99% 缺失 |

**结构差异（须在 wizard 确认）：**

- paper_003 套路 = **NHANES 加权横断面关联**；`D04_dabiao` = **MIMIC 队列、无调查权重**。
- 本步产出为**研究型通用模板**（`config_association_nhanes.template.R`），**不能**直接把 `D04_dabiao` 填入该模板试跑。
- 若目标为「用 MIMIC 数据做类似分析」，须另定 `study_type`（如 `incidence` 非加权 logistic + `rcs_incidence`），并等 wizard 确认疾病/结局/指标后再写实例 config。

---

## 1. 统计方法 → Block 映射（按 Results 顺序）

> Methods 与 Results 不一致时以 Results 为准。顺序对齐 Section 3.1 → 3.2 → 3.3 → 3.4。

| step | 文献分析 | 模型/检验 | 预期表/图 | 对应 block | 状态 |
|---|---|---|---|---|---|
| 0 | 缺失处理 | MICE/CART（m=5） | — | `data_clean` → `column_mapping` → `imputation` | 已有 |
| 1 | 基线（抑郁 vs 非抑郁） | 加权 t / 加权 χ² | Table 1 | `baseline_nhanes` | 已有 |
| 2 | 主暴露连续 CMI | 加权 logistic（Model 1–3，每单位 OR） | Table 2 连续行 | `logistic_binary_nhanes_weighted`（`include_continuous_row=TRUE`） | 已有(需适配) |
| 3 | 主暴露 tertile | 加权 logistic + P for trend | Table 2 分类行 | `logistic_tertile_nhanes_weighted` | 已有(需适配) |
| 4 | 多指标 ROC 对比 | CMI/VAI/LAP/TyG 同图 ROC + AUC | sFig 1 | — | **缺失 GAP1** |
| 5 | 非线性探索 | RCS（结点数先验 + 拐点位置拟合；P nonlinearity<0.001） | Fig 2 | `rcs_nhanes` | 已有(需适配：`knot_quantiles=c(0.1,0.5,0.9)`) |
| 6 | 拐点三分段验证 | 按 RCS 拐点分组加权 logistic | Table 3 | `logistic_binary_nhanes_weighted_rcs` + `logistic_tertile_nhanes_weighted_rcs` | 已有 |
| 7 | 外部文献界值敏感分析 | Wakabayashi 性别特异界值二分 + logistic + AUC | sTable 2 / sFig 2 | — | **缺失 GAP2** |
| 8 | 亚组 + 交互 | 分层 + 交互 P（饮酒修饰） | Table 4 / sTable 3 | `subgroup_nhanes_weighted` | 已有(需适配：饮酒交互/事后合并见 GAP4) |
| 9 | Youden 切点（前置） | 单指标 ROC 最优切点 | cutoff 步产出 | `cutoff` + `obj` | 已有（≠ 文献 sFig1 多指标对比） |
| 10 | （Judge 衍生）拐点 bootstrap 稳定性 | 结点数披露 / bootstrap | — | `rcs_nhanes` 无稳定性输出 | 分析细节 GAP3 |
| 11 | （Judge 衍生）饮酒 3→2 事后合并 | 交互 P 驱动重分类 | sTable 3 | `subgroup_nhanes_weighted` 不支持运行时合并 | 分析细节 GAP4 |

**刻意未纳入 pipeline（相对 incidence 模板）：**

- `univariate_nhanes` / `multicollinearity_nhanes_*` / `multivariate_nhanes`：论文用**固定协变量全模型**，非逐步筛选（Judge N5 + critique）。
- `mediation_nhanes_weighted`：横断面关联，无中介（Judge N14）。
- `logistic_quartile_*`：论文未用四分位。

---

## 2. pipeline$blocks 顺序（建议）

```r
c(
  "data_clean", "column_mapping", "imputation", "cutoff", "obj",
  "baseline_nhanes",
  "boxplot",                                    # 可选；模板保留
  "logistic_binary_nhanes_weighted",            # step 2：连续
  "logistic_tertile_nhanes_weighted",           # step 3：tertile
  # "roc_multi_indicator",                      # GAP1 未实现
  "rcs_nhanes",                                 # step 5
  "logistic_binary_nhanes_weighted_rcs",        # step 6
  "logistic_tertile_nhanes_weighted_rcs",
  # "logistic_external_cutoff_nhanes_weighted", # GAP2 未实现
  "subgroup_nhanes_weighted"                    # step 8
)
```

顺序约束：`cutoff`/`obj` 在 `baseline_nhanes` 前（沿用 NHANES 模板）；RCS 在 logistic 主表之后；亚组最后。

---

## 3. 缺失 Block 清单

| gap_id | 文献做法 | 建议新 block | 建议目录 | 严重度 | 影响主结论? | 备注 |
|---|---|---|---|---|---|---|
| GAP1 | CMI/VAI/LAP/TyG 多指标同图 ROC + AUC（CMI 0.748 vs 0.51–0.57） | `roc_multi_indicator` | `Blocks/13_roc/` | **高** | **是** | 现有 `ROC` 仅 ML；`simple_ROC`/`cutoff` 仅单指标 |
| GAP2 | Wakabayashi 性别特异 CMI 界值二分 + 加权 logistic + AUC | `logistic_external_cutoff_nhanes_weighted` | `Blocks/11_logistic/` | 中 | 否 | 敏感性；全调整后不显著（Judge N10L） |
| GAP3 | RCS 拐点 bootstrap / 结点数准则披露 | 扩展 `rcs_nhanes` | `Blocks/15_rcs/` | 低 | 否 | `knot_quantiles` 已隐含 3 结点；缺稳定性表 |
| GAP4 | 饮酒 3→2 类事后合并 | 扩展 `subgroup_nhanes_weighted` 或预处理 | `Blocks/18_subgroup/` | 低 | 否 | 宜 wizard 前人工重编码，非必建新 block |

---

## 4. 模板复用 / 最小 diff

**复用** `configs/templates/config_incidence_nhanes.template.R` → **已新建** `configs/templates/config_association_nhanes.template.R`

| diff 项 | incidence 模板 | association 模板 |
|---|---|---|
| 语义 | NHANES 加权发病（BMI×OA） | 横断面关联（CMI×抑郁）；`study_type` 仍 `"incidence"` 以复用 NHANES block |
| `index_var` | BMI | `<CMI>` 占位 |
| `outcome_column` | Disease_Group | `<Depression_Binary>` 占位 |
| 筛选链 | 单因素→VIF→多因素 | **注释关停**（论文固定协变量） |
| 分位 | quartile+tertile+binary | **仅** binary+tertile（对齐 Table 2/3） |
| 中介 | 有 | **移除** |
| GAP1/GAP2 | — | **注释占位** `# TODO(GAP1/GAP2)` |
| RCS | knot 0.1/0.5/0.9 | 同（3 结点→2 拐点，对齐 Judge N5a/N7） |

**run 薄入口：** `run_association_nhanes.R`（默认 `--config configs/templates/config_association_nhanes.template.R`）

**未写论文级实例 config**；占位符须经 wizard 回填。

---

## 5. config / run 骨架（已落地，占位符待 wizard）

### config 关键占位符（❓ 须交互确认）

```r
config$data$rawdata_path     = "Data/nhanes/<TO_CONFIRM>.RData"
config$data$rawdata_obj      = "<TO_CONFIRM>"
config$data$outcome_column   = "<Depression_Binary>"
config$incidence$index_var   = "<CMI>"
config$project$analysis_group / reference_group
config$project$output_dir
config$project$mirror_pub_outputs_to_root   # TRUE/FALSE 须确认
config$pipeline$checkpoint$dir
```

### run 建议命令（**未执行**）

```bash
Rscript run_association_nhanes.R --list-checkpoints
Rscript run_association_nhanes.R --to imputation    # wizard 试跑 smoke test
```

---

## 6. runner 映射核对

| block | 注册? | 源文件 |
|---|---|---|
| `data_clean` / `column_mapping` / `imputation` | ✓ | Blocks/02,01,03 |
| `cutoff` / `obj` | ✓ | Blocks/14,12 |
| `baseline_nhanes` | ✓ | Blocks/04/03block_baseline_nhanes.R |
| `logistic_binary_nhanes_weighted` | ✓ | Blocks/11/15block_logistic_binary_nhanes_weighted.R |
| `logistic_tertile_nhanes_weighted` | ✓ | Blocks/11/14block_logistic_tertile_nhanes_weighted.R |
| `logistic_*_nhanes_weighted_rcs` | ✓ | 同上（`_rcs` 后缀） |
| `rcs_nhanes` | ✓ | Blocks/15/03block_rcs_nhanes.R |
| `subgroup_nhanes_weighted` | ✓ | Blocks/18/03block_subgroup_nhanes_weighted.R |
| **`roc_multi_indicator`（GAP1）** | **✗ 未注册** | 须新建 Blocks/13_roc/ + 补 `pipeline_block_sources()` |
| **`logistic_external_cutoff_nhanes_weighted`（GAP2）** | **✗ 未注册** | 须新建 Blocks/11_logistic/ + 补映射 |

---

## 7. wizard 交互门待办（写实例 config 前）

1. **确认研究目标**：复现 paper_003（需 NHANES 数据） vs 用 MIMIC `D04_dabiao` 做类似关联（需非 NHANES block 变体）？
2. **确认疾病/结局/指标**：列名、病例组/对照组标签、主暴露指标（不得照搬文献 PHQ-9/CMI）。
3. **确认** `mirror_pub_outputs_to_root`、`output_dir`、pipeline 范围。
4. **输出并确认分析决策树**（见对话 mermaid）后再写 `configs/config_*.R` 实例。
5. **用户同意试跑**后再执行 `Rscript`。

---

> **强制规则确认**：只写/更新 `configs/templates/config_association_nhanes.template.R`、`run_association_nhanes.R`、`rounds/block_gap_paper_003_Q1.md`；未改动 Blocks/、R/、已有 configs、A/B/Judge 产物；缺失 block 只登记不实现；**未试跑**。
