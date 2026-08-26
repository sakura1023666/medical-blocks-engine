# Design: SLE → AKI 发病+预后两阶段套路（单库 MIMIC batch）

**日期**：2026-08-26  
**状态**：已确认（2026-08-26）；进入 implementation plan  
**疾病编号 / 结果根**：`29_SLE` → `G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/`  
**文献**：`adversarial_lit_reading/papers/MIMIC数据库发病预后(2).pdf`、`MIMIC数据库发病预后2(2).pdf`（方法范式；背景人群改为 SLE，结局改为急性肾衰竭/AKI）

---

## 1. 目标与非目标

### 目标

- 一套两阶段流水线：SLE 背景人群中 AKI **发病** + AKI 后 **28 天死亡预后**。
- 图和表深度对齐上述 MIMIC 发病-预后文献（不少于文献核心图/表类型），并覆盖用户融合流程图 15 步「名义全绿」。
- 可并行 batch（按指标）；结果只落结果目录，不写引擎仓库根目录。
- 每个套路具备：决策树、config、run、飞书连接。
- 统计主链复用现有 Blocks；仅新增必要胶水/阈值块；旧课题默认行为不变。

### 非目标

- 不修改既有已跑通课题的 config / 产出。
- 不做双库（本期仅 MIMIC）。
- 不做自动 DAG 引擎（DAG 以决策树文档 + 强制协变量集落实）。
- 不把 Tables/Figures 镜像到 `/mnt/e/01block/01Block-new-Final` 代码树。

---

## 2. 已锁定决策摘要

| 项 | 选择 |
|----|------|
| 架构 | 一套两阶段套路（非两个独立项目） |
| 库 | 单库 MIMIC；`dual_db$enable = FALSE`；batch 按指标并行 |
| 队列 | `D01_baseline` ∩ `SLE.csv` 现场筛入；必出纳排图 |
| 发病结局 | 急性肾衰竭 / AKI（与 `ARF.csv` / `Acute_Renal_Failure` 对齐，窗定义见 §4） |
| 预后结局 | 28 天死亡；`futime = min(t, 28)`；未死则事件=0、时间=28（行政截尾） |
| 时间零点 | 规则 C：Stage1=ICU intime；Stage2=AKI 发生时刻（无则回退 ICU intime，脚注标明） |
| 暴露 | 文献营养/炎症指标 ∪ 现有指标库；缺的补指标库；越多越好 |
| ROC | Stage1 + Stage2 都做 |
| 补块边界 | 胶水 2 + 发病 `threshold_logistic` 1；其余复用 |
| 图 | 现有 Block 内门控 `pub_figure$profile = "mimic_inc_prog_sle_aki"`；仅本套路开启 |
| 产出根 | `G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/` |
| R | `"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"`；缺包装该 R；必要时 Python 走 ML 同款路径 |

---

## 3. 架构

```text
Shared/Stage0
  ip_cohort_sle_aki → attrition_flowchart → data_clean → column_mapping
  → index → analysis_exclusion → imputation
       │
       ▼
Stage1 发病（by_index worker）
  baseline_binary → boxplot → UV→VIF→MV→VIF final→harmonized
  → simple_ROC → logistic 闸门 → rcs_incidence → threshold_logistic
  → subgroup_incidence → (+ sensitivity)
       │
       ▼
  ip_stage2_cohort_28d
       │
       ▼
Stage2 预后（同一 index，AKI 亚队列）
  baseline_binary → UV_prog→VIF→MV_prog→VIF final→harmonized
  → simple_ROC → cox 闸门 → rcs_prognosis → km/plot_cutoff
  → segmented_cox_* → subgroup_prognosis → (+ sensitivity)
```

**实现风格**：`Blocks/72_incidence_prognosis_two_stage/` 编排胶水；runner 参考 incidence/survival dual-batch 的 shared + worker，但单库、两阶段顺序在同一 worker 内完成（避免两套无关 checkpoint）。

**禁止**：改旧项目目录；在未设 `pub_figure$profile` 时改变任何现有绘图默认路径。

---

## 4. 队列、时间窗、28 天定义

### 4.1 纳排（必出 Figure 1）

建议逐步（具体 n 以数据为准，写入 attrition CSV）：

1. MIMIC ICU baseline（`D01_baseline_*`）
2. 合并/限定 `SLE.csv`（subject_id / stay_id / hadm_id 键需在实现时校验唯一性）
3. 年龄 ≥18（若 baseline 未滤）
4. 排除基线已存在终末期肾病等（按 config `disease_vars` / 排除规则；审列后定稿）
5. 暴露/关键窗可计算者进入分析集
6. （脚注）与 `D04_dabiao` 交叉核对人数，差异写入日志，**主分析以现场筛入为准**

### 4.2 疾病发生时间窗（流程图 ④）

Config 必须写死，例如（实现前用数据与文献再确认一字不差的默认）：

- AKI/ARF：ICU 住院期间诊断或标志为阳性（与 `Acute_Renal_Failure` / `ARF.csv` 对齐）
- 若文献「早期」窗（如 48h）在数据中可操作，则作为敏感性；主分析窗在决策树写明

### 4.3 暴露基线窗（流程图 ③）

- 实验室/生命体征：ICU intime 后既有「首次/基线窗」惯例（与引擎 `index` / dabiao 一致）
- 禁止使用结局发生之后的实验室值作为暴露

### 4.4 Stage2 28 天

- 时间零点：`aki_time` if available else `icu_intime`
- `t =` 死亡时间 − 时间零点（天）；无死亡则用末次随访/出院等可得终点
- `fustatus = 1` if `t ≤ 28` 且死亡；否则 `0`
- `futime = min(t, 28)`（活着截在 28）
- 若仅有院内死亡信息：降级为「院内 28 天死亡」并脚注偏倚风险（优先用 `dead_time` 算真 28 天）

---

## 5. 新 Blocks（`72_*`）

| Block | 文件（建议） | 职责 |
|-------|--------------|------|
| `ip_cohort_sle_aki` | `01block_ip_cohort_sle_aki.R` | 读 baseline + SLE + ARF；产出分析集 + attrition 逐步计数表 |
| `ip_stage2_cohort_28d` | `02block_ip_stage2_cohort_28d.R` | AKI 阳性亚队列；并预后 CSV；规则 C 时间零点；写 `futime`/`fustatus` |
| `threshold_logistic` | `03block_threshold_logistic.R` | 发病侧 threshold / 平滑分段表+图（对标文献）；读 `pub_figure$profile` |

**不新增** logistic/Cox/KM/ROC/RCS/subgroup 统计引擎；一律 register 现有块。

---

## 6. Stage1 / Stage2 Block 序（复用）

### Stage0

`ip_cohort_sle_aki` → `attrition_flowchart` → `data_clean` → `column_mapping` → `index` → `analysis_exclusion` → `imputation`

### Stage1

`baseline_binary` → `boxplot` → `univariate_incidence_binary` → `multicollinearity_screen` → `multivariate_incidence_binary` → `multicollinearity_final` → `multivariate_incidence_harmonized` → `simple_ROC` → `logistic_quartile_glm` → `logistic_tertile_glm` → `logistic_binary_glm` → `logistic_quintile_glm` → `rcs_incidence` →（闸门对齐的 `logistic_*_glm_rcs`）→ `threshold_logistic` → `subgroup_incidence` →（可选 sensitivity）

### 衔接

`ip_stage2_cohort_28d`

### Stage2

`baseline_binary` → `univariate_prognosis` → `multicollinearity_screen` → `multivariate_prognosis` → `multicollinearity_final` → `multivariate_prognosis_harmonized` → `simple_ROC` → `cox_quartile` → `cox_tertile` → `cox_binary` → `rcs_prognosis` → `plot_cutoff` → `km_strata` → `km_binary` → `segmented_cox_*`（随闸门）→ `subgroup_prognosis` →（可选 sensitivity）

### 协变量综合（流程图 ⑤）

`Model 候选 = Stage1 入选 ∪ Stage2 入选 ∪ 文献 force 集` → 去重 → `analysis_exclusion` / VIF → 锁定；决策树附 DAG 说明（非自动软件）。

### 疾病硬排除

实现前按 `skills/review-raw-covariate-columns` 审 `dabiao`/baseline 全列，落盘 `Data/_column_review.md`（结果目录或课题 Data 约定路径）；SLE/AKI 相关诊断、肾标志物、结局泄漏列入 `disease_vars`。

---

## 7. 文献对齐图（现有 Block 门控）

```r
config$pub_figure <- list(
  profile = "mimic_inc_prog_sle_aki"  # 仅本套路
)
```

- `profile` 为 `NULL`/缺省：保持历史默认图。
- 本 profile：`attrition_flowchart`、`simple_ROC`/`ROC`、`rcs_*`、`subgroup_*`、`km_*`/`plot_cutoff`、`threshold_logistic` 走文献版布局（面板、标注、阈值点、森林图交互呈现等，以两篇 PDF 图为验收标准）。
- 改动方式：现有 Block 内 `if (identical(profile, "mimic_inc_prog_sle_aki"))` 分支；禁止删除旧路径。
- 验收：任选一个旧 incidence config 回归，图文件路径与样式无变化。

`image_information` 仍走 `R/pub_figure_export.R` 铁律（图面说明 + 分析上下文；纳排逐步 n）。

---

## 8. 指标库

- 文献优先：CONUT、PNI、GNRI、NLR、SII、SIRI、SIS、LMR、BMI 分类等。
- 并入引擎可算指标全集；缺公式写入 Indicator / index 公式库。
- 缺必要成分 → 该指标 skip + 日志，不中断整批。
- 成功指标 finalize 遵循 `index_success_code_bundle` 铁律（本套路若走 dual-batch 同类 finalize，则生成 `code/`）。

---

## 9. 表图清单（验收最少集）

| 类型 | Stage1 | Stage2 |
|------|--------|--------|
| Figure 1 Flowchart | ✅ | — |
| Table 1 | 按 AKI | 按 28d 死亡 |
| 主关联表 | Logistic | Cox（± 28d logistic 若文献需要） |
| ROC 图/表 | ✅ | ✅ |
| RCS | ✅ | ✅ |
| Threshold / piecewise | `threshold_logistic` | `segmented_cox_*` |
| 亚组森林 | ✅ | ✅ |
| KM | — | ✅ |
| 插补 / 缺失 | S1 | 同源 |
| 敏感性 | ✅ | ✅ |

全部位于结果根下 `Tables/`、`Figures/`、`by_index/【success|failed】<INDEX>/`。

---

## 10. 文件与飞书

| 产物 | 路径 |
|------|------|
| 决策树 | `Decisiontree/decision_tree_sle_aki_inc_prog.md` |
| Config | `configs/config_sle_aki_inc_prog_batch.R` |
| Template | `configs/templates/config_sle_aki_inc_prog_batch.template.R` |
| Run | `run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R` + worker |
| Blocks | `Blocks/72_incidence_prognosis_two_stage/` |
| 飞书 | `run/feishu/*`；多维表 [RBjfb2iwmamW14s4WhKcS7kwnie](https://lcn1in9jd6ie.feishu.cn/base/RBjfb2iwmamW14s4WhKcS7kwnie?from=from_copylink)；工作计划新编号 Bxx（实现时取下一空号）；结果扫描 `29_SLE` |

---

## 11. 流程图 15 步对照（全绿）

| # | 步骤 | 落实 |
|---|------|------|
| ① | MIMIC cohort | `ip_cohort_sle_aki` |
| ② | 时间零点 | Stage1 intime；Stage2 规则 C |
| ③ | 暴露基线窗 | index/基线窗约定 + 脚注 |
| ④ | 疾病时间窗 | config 写死 + attrition |
| ⑤ | DAG 混杂 | 决策树 DAG + force∪UV/MV |
| ⑥ | Table 1 | ×2 |
| ⑦ | Logistic | Stage1 闸门 |
| ⑧ | RCS | 两端 |
| ⑨ | threshold/piecewise | `threshold_logistic` + `segmented_cox_*` |
| ⑩ | subgroup+interaction | 两端 subgroup |
| ⑪ | ROC | 两端（本课题明确研究预测辅助） |
| ⑫ | 第二阶段 cohort | `ip_stage2_cohort_28d` |
| ⑬ | KM+Cox | Stage2（28 天窗，脚注非真长期） |
| ⑭ | MI | `imputation` |
| ⑮ | sensitivity | sensitivity_suite |

---

## 12. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 无 AKI 精确时刻 | 回退 intime + 脚注 |
| 仅院内死亡 | 真 28 天优先；否则脚注 |
| dabiao 271 vs 现场筛入人数差 | 以筛入为准；核对日志 |
| 图门控误伤旧课题 | profile 默认关闭 + 回归抽检 |
| 指标缺成分 | skip 单指标 |

---

## 13. 实现顺序（供 writing-plans）

1. 审列 + `disease_vars` + 数据键核对（SLE/ARF/baseline/预后）
2. 指标库补公式
3. 三个 `72_*` blocks + pipeline 注册
4. 现有 Block 图 profile 分支（最小 diff）
5. config / template / decision tree / run+worker
6. 飞书挂接与 batch 试跑 1～2 指标
7. 全指标并行 + 表图验收清单勾选

---

## Spec 自检

- [x] 无 TBD/TODO 占位（AKI 窗具体小时数实现前用数据确认，已规定必须写死 config）
- [x] 与用户选择一致（两阶段、单库、28 天、现场纳排、ROC、全绿+图门控）
- [x] 范围单一可写一份 implementation plan
- [x] 「旧课题不变」与「结果不落代码根」已写死
