# 设计：缺血性卒中 ANLR × 28 天全因死亡（MIMIC+eICU 平权 prognosis_v2）

日期：2026-11-05  
状态：待用户审阅后进入实现计划  
对标交付：`G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results`  
数据根：`G:/02block_result/11_ischemic stroke/prognosis_v2_41904528/data/{mimic,eicu}`  
输出根：`G:/02block_result/11_ischemic stroke/prognosis_v2_41904528/summary_results`（新跑；不覆盖 `prognosis_38902748`）

---

## 1. 研究问题与地基

- **问题**：入院后可算的 ANLR 对缺血性卒中患者 **28 天全因死亡** 的关联与预测价值。
- **地基**：预后（survival / prognosis_v2），**加法**复用 Hip 已沉淀的文献宽表 / Rubin Cox / 分位级联 / 中介 / 发表收口。
- **不做**：竞争风险 Fine–Gray（死因不可得，与 Hip 一致，无主文 Table 4）；不把既有 `prognosis_38902748/【success】ANLR` 当交付根（可作对照，不直接 remirror 交差）。

## 2. 已锁定口径

| 项 | 决定 |
|----|------|
| 人群 | 缺血性卒中 ICU；**Age ≥ 18** |
| 暴露 | **ANLR** = `Albumin / (NeutrophilCount / Lymphocytes)`（引擎名映射到 `Neutrophil_Count`） |
| 主终点 | **28 天全因死亡**（`Mortality_28d` + `survival_time_28d`，截尾于 28） |
| 数据库 | **MIMIC + eICU 平权** |
| 特征 | **双库列交集**；禁止 MIMIC-only（如 CHARLSON、SAPSII、HbA1c、Language…）与 eICU-only 进主分析/Table1 |
| 中介流水线 | **先相关、后中介**（预后套路）：共享实验室/严重度池 → **Table S7 相关性** → **Table S8 中介** → **Fig6 路径图**；路径图中介锁 **SOFA**；S7/S8/Fig6 同闸门（`mediation_gate_lab_assoc` / `.mi02_mediation_should_export`） |
| 敏感性 S5 | **院内全因死亡**（`is_hosp_dead` / `hosp_survival_day`；替代 Hip 的 90 天） |
| 插补 | MICE **m=5**；推断 Cox **Rubin**；图/Boruta/ROC 可用 complete#1 |
| 分位 | `quantile_scheme_cascade`（quartile→tertile→binary，`pass_rule="all"`）；锁定后 T2/T3/KM/亚组同 scheme |
| 协变量方案 | 对齐 Hip 文献三层精神：**Model1 未调整；Model2 Age+Gender；Model3 = 共享临床候选 ∩ UV ∩ VIF**（严重度评分是否进 Model3：默认 **SOFA 作中介则主文 Model3 不含 SOFA**；APSIII/OASIS 可进候选但须双库都有且过 VIF） |

预估完整病例（Age≥18 + ANLR 可算 + 结局完备）：MIMIC ≈862（183 事件），eICU ≈1860（299 事件）。

## 3. 架构（方案 A）

```text
data/mimic|eicu/D02_rt_Stroke_surv28.RData
        │
        ▼
run/prognosis_v2/run_prognosis_v2_stroke_anlr.R   # 薄：读数、ANLR、Age≥18、双库循环
        │
        ├─ 共享特征池锁定（intersect colnames + 黑名单）
        ├─ 每库：MICE → Rubin Cox 宽表 → Boruta/SHAP → KM/RCS/ROC → 亚组 → PH
        ├─ 中介块（顺序固定，不可颠倒）：
        │     ① 共享指标池 LM/相关筛 → 写出 **S7 Correlation**
        │     ② 以 SOFA 为中介做 Cox 路径 → 写出 **S8 Mediation**
        │     ③ 门控通过后再画 **Fig6**；失败则 unlink S7+S8+Fig6（同生共死）
        ├─ 敏感性：院内死亡宽表（同切点）
        │
        ▼
run/prognosis_v2/remirror_stroke_anlr_pub.R      # 薄：命名、拼图、Methods、finalize、pv2_pub_p0_gate
        │
        ▼
summary_results/{Tables,Figures,Methods_*.md|txt}
        │
        ▼
发表 QC（pub-qc + nature P0）→ 中期 PDF → prune
```

**引擎复用（禁止课题私改算法）**：

- `R/quantile_scheme_cascade.R`
- `R/pv2_literature_pub_tables.R` / `run/prognosis_v2/pv2_mi_cox.R`
- `R/pv2_pub_p0_gate.R` + `R/pub_prognosis_v2_methods.R`
- `R/pub_figure_export.R` / `R/attrition_log.R` / `R/dual_db_combine_figures.R`
- 中介（预后套路入口）：
  - 多库：`Blocks/20_mediation/13block_mediation_multi_db_cox.R` → `mediation_multi_db_write_xlsx`（先 correlation CSV/表，再 mediation 表）
  - 薄封装参考：`run/prognosis_v2/pv2_s7_s8_nonlipid.R` / `_rebuild_s6_s7_s8_hip_aki.R` / `pv2_mediation.R`
  - 公共闸门：`.mi02_mediation_should_export` / `.mi02_unlink_mediation_exports` / `.mi02_resolve_lab_indicator_pool`
  - **禁止** LM 筛时提前 `export_sci_table` 关联表；**禁止**只出 S8/Fig6 不出 S7，或门控失败仍留 S7
  - 协变量脚注写实（默认同 Table3 Model2；SOFA 不进自身 path 调整集）

**课题仅薄封装**：路径、指标名 ANLR、中介 SOFA、共享协变量名单、表图标题文案。

## 4. 特征统一（硬门控）

1. 起点表两库 `intersect(names)`；再剔疾病泄漏与暴露成分：
   - `disease_vars` 至少含：`Stroke`（结局人群已全是卒中，勿当协变量）、及明显诊断泄漏列
   - 暴露成分硬排除出 Model：`Albumin`、`NeutrophilCount`/`Neutrophil_Count`、`Lymphocytes`、以及派生 `NLR`（若存在）
2. Table1 / S6 / UV / VIF / Model3 / 亚组 / S7 候选池 = **同一共享名单**。
3. 亚组：`var_source=required`；`age_cutoff=65`（森林二分类 `< 65` / `≥ 65`）；暴露对比 = 锁定 scheme 的最高 vs 最低；**全分析集** N。
4. remirror 后若一侧多出单库变量行 → 删行对齐（对标 `dual_db` 交集铁律）。

## 5. 交付物清单（与 Hip 一一对应，双库平权）

### 5.1 Tables（每库一份；文件名带 `-MIMIC` / `-eICU`）

| 角色 | 文件名模式 | 相对 Hip 的差异 |
|------|------------|-----------------|
| T1 | `Table 1-*. Baseline characteristics.xlsx` | 人群改卒中；列=共享池 |
| T2 | `Table 2-*. Incidence of all-cause mortality.xlsx` | 28 天 |
| T3 | `Table 3-*. Cox proportional hazards models.xlsx` | ANLR；M1–M3 |
| S1 | `Table S1-*. Definitions.xlsx` | ANLR 公式 + 28d 定义 |
| S2 | `Table S2-*. Assessment of multicollinearity.xlsx` | 共享 VIF |
| S3 | `Table S3-*. Cox model including additional severity/comorbidity (Model 4).xlsx` | 无 CHARLSON 时用共享共病计数或 OASIS/APSIII 扩展（两库同规格） |
| S4 | `Table S4-*. Predictive performance for 28-day all-cause mortality.xlsx` | 28d AUC/Youden |
| S5 | `Table S5-*. Sensitivity analysis using in-hospital all-cause mortality.xlsx` | **院内**，非 90d |
| S6 | `Table S6-*. Baseline characteristics before and after imputation.xlsx` | |
| S7 | `Table S7-*. Correlation between ANLR and other indicators.xlsx` | **先出**：ANLR 与共享实验室/严重度（含 SOFA）相关/加权关联；候选池=双库交集 |
| S8 | `Table S8-*. Mediation analysis.xlsx` | **后出**：在 S7 之后；中介=**SOFA**；Direct/间接/比例与 Fig6 同源 |
| S9 | `Table S9-*. Proportional hazards assumption.xlsx` | cox.zph |

**中介块顺序与门控（写进实现计划，不可跳）**：

1. 解析共享指标池（Table1 Laboratory + `lab_indicator_vars` + 严重度如 SOFA/APSIII/OASIS 中双库都有者）→ pin `best_mediator = "SOFA"`。
2. 拟合并暂存 correlation（S7 内容）与 mediation（S8 内容），**先不落盘或仅写 ctx**。
3. `.mi02_mediation_should_export`：Direct / 比例等未过门槛 → **S7+S8+Fig6 全不导出**并 unlink；通过 → 按 Hip 编号先写 S7、再写 S8、再画 Fig6。
4. Fig6 底边箭 = S8 Direct HR 字符串级一致；path a 方向 = 暴露→SOFA。

### 5.2 Figures（拼图进汇总 `Figures/pdf/`；面板标库名）

| 图 | 内容 |
|----|------|
| Fig1 | CONSORT 双栏纳排（Age≥18、缺 ANLR 成分、结局缺失等真实原因） |
| Fig2 | Boruta confirmation + SHAP（每库或 A/B） |
| Fig3 | KM / 累积死亡（锁定 scheme） |
| Fig4 | RCS（P-linear + P-nonlinear） |
| Fig5 | 28d ROC |
| Fig6 | SOFA 中介路径（Direct= S8 Direct，禁止 Total 冒充） |
| Fig7 | 亚组森林（High vs Low 或锁定对比 + P-int） |

另需：`Methods_statistical_analysis.md`、`Methods_software_versions.txt`；Nature P0 清零后中期 PDF；交付根白名单 prune。

## 6. 标准路径门控（pipeline-foundation）

实现写 config / 开跑前必须：

1. **列审阅** → `data/_column_review.md` + `analysis_exclusion$disease_vars`
2. **对抗阅读**：至少 Q4/Q5/Q8（对标文献或用户指定 PDF；无指定则用 Hip 方法学包 + 本题口径做迁移阅读，并落盘 `adversarial_lit_reading/`）
3. **分析决策树** `Decisiontree/decision_tree_stroke_anlr_prognosis_v2.md` → 用户确认
4. 跑批 → remirror/finalize → `run_pub_qc_after_project.R` → nature Layer D → 中期

## 7. 错误处理与验收

- ANLR 或结局缺失行：Fig1 Exclude 写实，不进分析集。
- 分位级联锁定 binary 时：Fig3 仅 Low/High；Fig7 轴标不得残留 Q4 vs Q1。
- `pv2_pub_p0_gate(summary_root)` 失败即停交付。
- 验收：Hip 清单 12 表角色 + 7 图角色双库齐全（或中介门控跳过时 S7/S8/Fig6 双侧同时省略并在 Methods 说明）；无单库独有协变量列；Cox 脚注含 Rubin。

## 8. 明确不做

- 不把 `prognosis_38902748` 直接改名交差
- 不在结果目录堆长期 hotfix（一次性进 `_archive_oneoff/`）
- 不把 CHARLSON 强塞进 eICU
- 不把暴露成分或 `Stroke` 标签进 Model3
- 默认不导出 png/tiff（PDF + image_information）

---

## 变更记录

- 2026-11-05：用户确认终点=28d、双库平权+特征统一、Age≥18、中介=SOFA、方案 A；S5 默认院内死亡。
- 2026-11-05：用户明确中介块按预后套路 **先相关性(S7) → 再中介(S8/Fig6)**，同闸门同生共死。
