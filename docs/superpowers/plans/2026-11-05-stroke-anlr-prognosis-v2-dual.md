# 缺血性卒中 ANLR × 28d 死亡 · MIMIC+eICU 平权 prognosis_v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `11_ischemic stroke/prognosis_v2_41904528` 按 Hip `summary_results` 清单交付 ANLR 对缺血性卒中 28 天全因死亡的双库平权预后分析（表图一个不少）。

**Architecture:** 方案 A——新建双库 prognosis_v2 薄 runner + remirror；算法进/复用引擎（Rubin Cox、分位级联、Boruta/SHAP、RCS、ROC、S7→S8 中介、PH、发表收口）。不覆盖 `prognosis_38902748`。

**Tech Stack:** R；`run/prognosis_v2/*`；`R/pv2_*`；`Blocks/20_mediation/13block_mediation_multi_db_cox.R`；`R/pub_*`；MICE m=5 + Rubin。

**Spec:** `docs/superpowers/specs/2026-11-05-stroke-anlr-prognosis-v2-dual-design.md`

## Global Constraints

- 暴露：**ANLR** = Albumin / (NeutrophilCount / Lymphocytes)
- 终点：**28 天全因死亡**（`Mortality_28d` + `survival_time_28d`）
- 人群：缺血性卒中；**Age ≥ 18**
- 库：**MIMIC + eICU 平权**；特征 = **列交集**（禁 CHARLSON/SAPSII/HbA1c 等 MIMIC-only）
- 中介流水线：**先 S7 相关 → 再 S8 中介 → 再 Fig6**；路径中介锁 **SOFA**；三者同闸门同生共死
- 敏感性 S5：**院内全因死亡**
- 插补：MICE **m=5**；Cox **Rubin**；图/Boruta/ROC = complete#1
- 分位：`quantile_scheme_cascade` quartile→tertile→binary，`pass_rule="all"`
- 亚组：`age_cutoff=65`；最高 vs 最低；全分析集 N；双库同一 `required_subgroup_vars`
- 交付根白名单；Nature P0 清零后中期；默认 PDF-only
- **禁止**改 Hip 旧交付；**禁止**结果目录长期 hotfix

---

## 文件与职责

| 路径 | 职责 |
|------|------|
| `G:/…/11_ischemic stroke/prognosis_v2_41904528/data/{mimic,eicu}/` | 只读 D02 + 实验室 |
| `…/prognosis_v2_41904528/data/_column_review.md` | 列审阅 + disease_vars |
| `…/prognosis_v2_41904528/summary_results/` | 唯一交付根 |
| `run/prognosis_v2/run_prognosis_v2_stroke_anlr.R` | 双库读数→ANLR→Age≥18→MICE→主分析产物 |
| `run/prognosis_v2/remirror_stroke_anlr_pub.R` | Hip 清单命名、拼图、S7→S8、Methods、finalize、P0 gate |
| `Decisiontree/decision_tree_stroke_anlr_prognosis_v2.md` | 分析决策树 |
| `adversarial_lit_reading/…` | 至少 Q4/Q5/Q8（对标 Hip 方法学包迁移） |
| 引擎：已有 `pv2_mi_cox.R`、`pv2_literature_pub_tables.R`、`13block_mediation_multi_db_cox.R`、`pv2_pub_p0_gate.R` | **只调不抄算法** |

---

### Task 1: 列审阅 + 共享特征池落盘

**Files:**
- Create: `…/prognosis_v2_41904528/data/_column_review.md`
- Create: `…/prognosis_v2_41904528/data/shared_feature_pool.json`（或 `.rds`）

**Produces:** `shared_covars`、`disease_vars`、`lab_indicator_pool`、`exclude_exposure_components`

- [ ] **Step 1:** 读两库 `D02_rt_Stroke_surv28` 列名，写交集 / mimic-only / eicu-only
- [ ] **Step 2:** 按 `review-raw-covariate-columns` 落盘 `_column_review.md`；`disease_vars` 至少含 `Stroke` 及诊断泄漏；暴露成分 `Albumin`/`NeutrophilCount`/`Lymphocytes`/`NLR` 进硬排除
- [ ] **Step 3:** 锁定共享协变量候选（人口学+生命体征+共病 Yes/No+APSIII/OASIS+共享实验室；**不含 SOFA 进 Model3**——SOFA 留给中介）
- [ ] **Step 4:** 验收打印：交集列数、Age≥18+ANLR 可算 N（期望 MIMIC≈862 / eICU≈1860）

---

### Task 2: 对抗阅读门控（Q4/Q5/Q8）+ 决策树

**Files:**
- Create/Update: `adversarial_lit_reading/rounds/*`（本题迁移）
- Create: `Decisiontree/decision_tree_stroke_anlr_prognosis_v2.md`

- [ ] **Step 1:** 对标文献/方法包切块（用户 PDF 或 Hip Methods + 本题口径）；跑 adversarial Q4/Q5/Q8
- [ ] **Step 2:** 写决策树：人群/暴露/终点/平权/特征交集/分位级联/M1–M3/S7→S8(SOFA)/S5 院内/交付清单
- [ ] **Step 3:** 聊天里贴决策树摘要；**等用户确认**后再 Task 3（若用户已在本对话确认设计，可视为授权，决策树仍须落盘）

---

### Task 3: 分析就绪表（每库）

**Files:**
- Create: `…/data/analysis_ready_ANLR_28d_mimic.rds`
- Create: `…/data/analysis_ready_ANLR_28d_eicu.rds`
- Create: `…/data/Flowchart_attrition_{mimic,eicu}.csv`

- [ ] **Step 1:** 自 D02 计算 ANLR；映射 `futime`/`fustatus`；筛 Age≥18、ANLR>0 有限、futime>0、结局非 NA
- [ ] **Step 2:** 院内敏感性字段：从 `mimic预后数据-all.csv` / eICU 对应表 join `is_hosp_dead`/`hosp_survival_day`（缺则记 AUTHOR_INPUT 并降级 S5）
- [ ] **Step 3:** 写出 attrition CSV（池→Age≥18→缺成分→结局缺失→分析集）
- [ ] **Step 4:** 验收：事件数、ANLR 分布、共享列无单库泄漏

---

### Task 4: Runner — MICE + 分位级联 + Table1–3 / S2 / S4 / S6 / S9 骨架

**Files:**
- Create: `run/prognosis_v2/run_prognosis_v2_stroke_anlr.R`
- Writes: `summary_results/Tables/imputed_*.rds`、宽表草稿、Boruta/SHAP rds

**Consumes:** Task 1 pool + Task 3 ready rds  
**Produces:** 每库 complete#1 + mids；锁定 scheme；Cox M1–M3 Rubin 宽表

- [ ] **Step 1:** 脚手架：路径、双库循环、source `pv2_front`/`pv2_mi_cox`/`quantile_scheme_cascade`
- [ ] **Step 2:** 每库 MICE m=5（暴露/futime/fustatus 不入插补）；落盘 `imputed_dbs.rds` / `imputed_mids.rds` / before
- [ ] **Step 3:** 联合或分库级联锁定 grouping（双库须 **同一 scheme**；以更严或预先在合并策略上约定：推荐在 MIMIC 锁定后 **强制 eICU 同 scheme 切点规则**——分位切点各库自算，**水平数/对比名一致**）
- [ ] **Step 4:** Table1、Table2（28d 人时/率）、Table3 M1–M3（Rubin）、S2 VIF、S6 插补前后、S4 ROC 指标、S9 cox.zph
- [ ] **Step 5:** Boruta + SHAP 对象落盘供 Fig2
- [ ] **Step 6:** 干跑日志无 CHARLSON；Model3 无 SOFA/Albumin/Neutrophil/Lymphocytes

---

### Task 5: Remirror — Fig1–5、Fig7 + S1/S3/S5

**Files:**
- Create: `run/prognosis_v2/remirror_stroke_anlr_pub.R`（可先建主链，中介留 Task 6）
- 参考：`remirror_hip_aki_pub.R`（双库扩展，勿整文件复制堆逻辑）

- [ ] **Step 1:** Fig1 `attrition_draw_dual_panel_pdf`；Exclude 文案=真实原因
- [ ] **Step 2:** Fig2 Boruta|SHAP 双栏拼图；Fig3 KM（锁定 scheme）；Fig4 RCS（P-linear+P-nonlinear）；Fig5 28d ROC
- [ ] **Step 3:** Fig7 亚组森林（双库拼图；Age_Group 65；最高 vs 最低；P-int）
- [ ] **Step 4:** S1 Definitions；S3 Model4（共享共病计数或 APSIII/OASIS 扩展，两库同规格）；S5 院内死亡宽表（同切点）
- [ ] **Step 5:** 文件名 `Table N-MIMIC.` / `Table N-eICU.`；图进 `Figures/pdf/` + `pub_figure_ensure_formats`

---

### Task 6: 中介块 S7 → S8 → Fig6（同闸门）

**Files:**
- Modify/Extend: `remirror_stroke_anlr_pub.R` 或薄 `_rebuild_s7_s8_stroke_anlr.R`
- Source: `Blocks/20_mediation/13block_mediation_multi_db_cox.R`、`run/prognosis_v2/pv2_mediation.R`

**Order (硬):**

1. `.mi02_resolve_lab_indicator_pool` + 双库交集 + pin `best_mediator="SOFA"`
2. 拟合 correlation → mediation（暂存）
3. `.mi02_mediation_should_export`；失败 → `.mi02_unlink_mediation_exports`（S7+S8+Fig6）
4. 通过 → 先写 **S7**，再写 **S8**，再画 **Fig6**（Direct=S8 Direct）

- [ ] **Step 1:** 接入 multi_db Cox 中介；协变量默认 Table3 Model2（Age+Gender）；SOFA 不进自身调整集
- [ ] **Step 2:** 门控日志含「不导出中介表、路径图与实验室关联表」文案（失败时）
- [ ] **Step 3:** 成功时核：`pdftotext` Fig6 Direct ∈ S8；S7 变量均为共享池
- [ ] **Step 4:** 双库都有 S7/S8 或双侧同时省略

---

### Task 7: Methods + finalize + P0 gate + QC + 中期

**Files:**
- `summary_results/Methods_statistical_analysis.md`
- `summary_results/Methods_software_versions.txt`
- Reports under `…/prognosis_v2_41904528/reports/`

- [ ] **Step 1:** `finalize_delivery_root.R --study-type prognosis_v2`（或 `pub_prognosis_v2_methods`）
- [ ] **Step 2:** `pv2_pub_p0_gate(summary_root)` 必过
- [ ] **Step 3:** `Rscript run/pub/run_pub_qc_after_project.R --project <project_root>`
- [ ] **Step 4:** Agent Layer D nature-statistics + nature-figure；修清 P0
- [ ] **Step 5:** 中期 PDF（`Aiya-NB004-midterm-report`）→ 再 prune
- [ ] **Step 6:** 对照 Hip 清单勾选：T1–3、S1–9、Fig1–7（中介失败则 S7/S8/Fig6 双侧省略并 Methods 说明）

---

## 验收清单（交付前）

```
[ ] summary_results 在 prognosis_v2_41904528 下，未改 prognosis_38902748
[ ] 表名带 -MIMIC/-eICU；图为拼图或成对齐全
[ ] Table1 无 CHARLSON/SAPSII/Language 等单库列
[ ] Model3 无 SOFA、无 ANLR 成分
[ ] 分位 scheme 双库水平数一致；Fig3/Fig7 同对比名
[ ] S7 先于 S8；Fig6 Direct = S8 Direct
[ ] Cox 脚注 Rubin；S9 有 cox.zph
[ ] S5 为院内死亡（非 90d）
[ ] Nature P0=0；中期 PDF 在交付根；白名单以外已 prune
```

---

## 执行入口（实现完成后）

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript run/prognosis_v2/run_prognosis_v2_stroke_anlr.R
Rscript run/prognosis_v2/remirror_stroke_anlr_pub.R
Rscript run/pub/run_pub_qc_after_project.R --project "/mnt/g/02block_result/11_ischemic stroke/prognosis_v2_41904528"
```

---

## 变更记录

- 2026-11-05：用户确认 design；中介先相关后中介；本计划落盘。
