# De Ritis 指标分析结果问题清单

> **表号已按 2026-08-13 发表目录重对**（删 ROC 附表后 S 号顺延；括号已从文件名去掉）。
>
> | 清单旧号 | 现发表表 |
> |---------|---------|
> | Table S3 ROC | **已从发表 Tables 删除**；对应 **Figure S2**（ROC；Figure S1=Boxplot） |
> | Table S4 单因素 | **Table S3** |
> | Table S6 多因素（全） | **Table S5** |
> | Table S7 VIF final | **Table S6** |
> | Table S8 最终模型 | **Table S7**（*Final multivariable model*） |
> | Table S9 实验室关联 | **Table S8** |
> | Table S10 中介 | **Table S9** |

---

# De Ritis 指标分析结果问题清单（原文）

**检查目录**：`【success】De_Ritis`
**数据库**：MIMIC-IV
**样本量**：N=262（清理前 399）
**结局**：ASCVD（病例 55 / 对照 207）
**疾病队列**：Rheumatoid Arthritis（PMID 38341157）
**生成日期**：2026-08-13

---

## 一、严重问题（需立即核查）

### 1. ★ 高血压方向相反（最严重）

| 位置 | 数值 | 解读 |
|------|------|------|
| Table 1 基线 | ASCVD 组 HTN Yes=11 (20.00%) vs Non-ASCVD Yes=95 (45.89%)，p<0.001 | ASCVD 组高血压反而**更少** |
| Table S3 单因素 | OR=0.29 (0.14-0.60) | 表现为"保护因素" |
| Table S5 多因素 | OR=0.39 (0.16-0.96, p=0.039) | 保护因素 |
| Table S7 最终模型 | OR=0.23 (0.11-0.48, p<0.001) | 强保护因素 |

**问题**：高血压是 ASCVD 明确危险因素，OR 应 >1，当前结果方向完全相反。

**核查结论（引擎）**：原始 dabiao `Hypertension` 在 n=399 全队列即为 ASCVD Yes 16/70 vs Non-ASCVD 163/329，**非标签反转、非引擎错绑**。属队列选择性偏倚 / 数据源问题，**不改引擎、不翻编码**。

---

### 2. 共病计数巧合可疑

ASCVD 组（N=55）内出现完全相同的阳性计数：

| 配对变量 | ASCVD 组 Yes 数 | 怀疑 |
|----------|----------------|------|
| Heart Failure / Acute Renal Failure | **34 / 34** | 同一批患者共病簇 or 变量错绑 |
| T2DM / CKD | **21 / 21** | 同一批患者共病簇 or 变量错绑 |

**核查结论（引擎）**：2×2 非 100% 重叠（HF∩ARF=26；T2DM∩CKD=12），边缘计数碰巧相同，**非变量错绑**。

---

### 3. Table 2 表头误导 — **已修（引擎）**

- 旧："Case (%)" 列实际填的是每四分位区间总样本数
- **现**：表头统一为 `Events / N (%)`（组内事件数/组样本量）
- 全项目：`pub_glm_group_n_header()` + logistic quartile/tertile/binary/quintile

---

## 二、统计一致性问题

### 4. Figure S1 ROC 协变量集与主分析不一致 — **已修（引擎）**

| 表 | 协变量 |
|----|--------|
| Table 2 / Table S7（锁定） | Age, Hypertension, Hyperlipidemia |
| Figure S1 ROC（旧） | 13 项 config 扩列 |

**现规则**：
- `roc_simple$covariate_source = "locked"`（默认）
- `simple_ROC` 放在 `multivariate_incidence_harmonized` **之后**
- 发表 Tables **不再导出** ROC xlsx（仅 Figure S1）

---

### 5. Table S9 中介负比例 — **已修（引擎）**

脚注：`A negative proportion mediated indicates a suppression (masking) effect, not a mediated fraction.`

---

### 6. Table S8 LD β=0.000 — **已修（引擎，标准化）**

实验室 LM / 中介路径默认 `standardize_mediator=TRUE`，报告 **β per 1-SD**，避免量纲过大导致 β≈0 或 path a 爆炸。

---

### 7. Table S9 路径系数过大 — **已修（同上）**

---

## 三、可改进项

### 8. Table S2 正态性与 Table 1 — **已一致**

Table 1 按 S2 Shapiro 结果自动选 t.test / Wilcoxon，无需改。

### 9. Table S1 高缺失率变量 — **已修（引擎）**

- `missing_col_threshold = 0.4`：缺失 **>40% 删列**
- Height/Weight/BMI **不再**列入插补缺失保护（`pipeline_imputation_missing_protect_vars` 仅保护结局/暴露/ID/Age/Gender）
- Height 41.98% → 应被剔除，不再进 MICE / Table S1

---

## 四、内部一致性（通过 ✓）

| 检查项 | 结果 |
|--------|------|
| De Ritis 主效应方向、量级跨表一致 | ✓ Crude 1.305 → 调整后 1.45 |
| 四分位切点（1.07 / 1.45 / 2.06）与 Table 1 IQR 对应 | ✓ |
| 样本量 399 → 262 与 _index_summary.csv 一致 | ✓ |
| RCS 截断 1.4495 与中位数 1.45 接近，131/131 分割 | ✓ |
| `mimic_branch=quartile` 与 Table 2 主分析方案一致 | ✓ |

---

## 五、图表对应关系（现发表目录）

| 图 | 对应数据 | 状态 |
|----|---------|------|
| Figure 1 Flowchart | N=399→262 | ✓ |
| Figure 2 RCS | 截断 1.4495 | ✓ |
| Figure 3 亚组森林 | P-interaction | ⚠ 脚注 |
| Figure S1 Boxplot | De Ritis 分布 | ✓ |
| Figure S2 ROC | 锁定协变量 AUC（= Table S7 / Model2） | ✓ |
| Figure S3 中介路径 | Table S9 | ✓ |

---

## 六、优先修复建议（状态）

| 优先级 | 问题 | 状态 |
|--------|------|------|
| P0 | 高血压方向相反 | **数据如此，不改引擎** |
| P0 | HF/ARF 与 T2DM/CKD 计数相同 | **非错绑（2×2 已核）** |
| P1 | Table 2 表头 | **已修 → Events / N (%)** |
| P1 | ROC 协变量不一致 | **已修 → locked + 流水线后置** |
| P2 | 负比例中介脚注 | **已修** |
| P2 | LD / 路径量纲 | **已修 → 1-SD 标准化** |
| P3 | Table1 vs S2 | **已一致** |
| P3 | Height >40% | **已修 → 删列** |

**附：共享层回归防护（2026-08-13）**
- 空 Gate A keep + `Ventilation` 别名不得把 105 列削成 1 列
- `--db mimic` 也必须注入 Gate A
- 共享层结束后 mapped `<10` 列直接 `stop`

---

## 七、附：De Ritis 效应量跨表汇总

| 表 | 模型 | OR (95% CI) | p |
|----|------|-------------|---|
| Table 2 | Crude continuous | 1.305 (1.042-1.657) | 0.0223 |
| Table S3 | 单因素 | 1.31 (1.04-1.64) | 0.022 |
| Table S5 | 多因素（全） | 1.41 (1.09-1.83) | 0.009 |
| Table S7 | 最终模型 | 1.45 (1.14-1.84) | 0.002 |
| Table 2 | Model 2 Q4 vs Q1 | 4.169 (1.603-11.981) | 0.0049 |
| Binary RCS | Model 2 (≥1.4495) | 2.673 (1.394-5.29) | 0.0037 |

**结论**：De Ritis 与 ASCVD 正向关联稳健；高血压反向为原始数据现象，解释时需谨慎。引擎侧清单问题已按上表闭环。
