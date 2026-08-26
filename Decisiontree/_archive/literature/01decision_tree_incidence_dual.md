# Zhou 2024 — CMI × 抑郁（方法决策树 · 纯逻辑）

- **文献**: Zhou X, et al. *Association between cardiometabolic index and depression: NHANES 2011–2014.* **J Affect Disord** 2024.
- **DOI**: [10.1016/j.jad.2024.02.024](https://doi.org/10.1016/j.jad.2024.02.024)
- **归档名**: `01decision_tree_zhou2024_cmi_depression_nhanes`
- **数据库**: NHANES（复杂抽样加权）· 横断面发病（Logistic）

> 本文档仅描述**分析逻辑**，不含具体样本量、效应值、变量清单或 Table/Figure 映射。

---

## 1. 纳入 / 排除逻辑

```mermaid
flowchart TD
  A[原始队列] --> B{暴露可计算?}
  B -->|否| X1[排除]
  B -->|是| C{结局可判定?}
  C -->|否| X2[排除]
  C -->|是| D{必要协变量完整?}
  D -->|否| X3[排除]
  D -->|是| F[最终分析队列]
```

---

## 2. 方法总流程

### 2.1 NHANES 单库

```mermaid
flowchart LR
  S1[① 数据清洗] --> S2[② 复杂加权]
  S2 --> S3[③ 单因素]
  S3 --> S4[④ VIF]
  S4 --> S5[⑤ 多因素]
  S5 --> S6[⑥ VIF]
  S6 --> S7[⑦ 逻辑回归]
  S7 --> S8[⑧ RCS]
  S8 --> S9[⑨ 亚组]
  S9 --> S10[⑩ 中介]
```

### 2.2 普通单库

```mermaid
flowchart LR
  S1[① 数据清洗] --> S3[② 单因素]
  S3 --> S4[③ VIF]
  S4 --> S5[④ 多因素]
  S5 --> S6[⑤ VIF]
  S6 --> S7[⑥ 逻辑回归]
  S7 --> S8[⑦ RCS]
  S8 --> S9[⑧ 亚组]
  S9 --> S10[⑨ 中介]
```

**唯一差异**：NHANES 在 ① 之后增加 **② 复杂加权**；其后各步均在 survey design 下加权估计。普通库无此步。

---

## 3. 分步逻辑（NHANES）

| 步骤 | 做什么 | 输出 / 下游依赖 |
|------|--------|----------------|
| **① 数据清洗** | 缺失排除 · 变量衍生 · 插补 | 干净分析数据集 |
| **② 复杂加权** | 构建 survey design（权重 / PSU / 层） | 后续全部加权模型共用 |
| **③ 单因素** | 暴露、协变量与结局逐一关联；基线组间比较 | 描述性表；候选协变量池 |
| **④ VIF** | 共线性初筛，剔除高 VIF 变量 | 入模变量集 v1 |
| **⑤ 多因素** | 多变量筛选 / 递进模型定协变量 | Model 1 → 2 → 3 |
| **⑥ VIF** | 终模共线性复核 | **终模协变量集** → 供 ⑦⑧⑨⑩ |
| **⑦ 逻辑回归** | 暴露 → 结局 OR；连续 + 分位 + P for trend | 主效应表 |
| **⑧ RCS** | 检验非线性；识别拐点；拐点分段后**重跑逻辑回归** | 剂量–反应曲线 + 分段 OR 表 |
| **⑨ 亚组** | 按预设变量分层 + 交互检验 | 森林图 / 交互 P 值 |
| **⑩ 中介** | 暴露 → 中介 → 结局；path a/b/c | 中介比例 / 路径图 |

---

## 4. 分步逻辑（普通单库）

| 步骤 | 与 NHANES 的差异 |
|------|------------------|
| ① 数据清洗 | 同左；无 survey weight 要求 |
| ②–⑨ | 对应 NHANES 的 ③–⑩；模型为 **glm / 常规 VIF / 非加权** |

---

## 5. ⑦ 逻辑回归 — 子逻辑

```mermaid
flowchart TD
  LOG[逻辑回归] --> F1[暴露：连续变量]
  LOG --> F2[暴露：分位变量 + P for trend]
  F1 --> M1[Model 1 粗模型]
  F1 --> M2[Model 2 人口学调整]
  F1 --> M3[Model 3 全调整]
  F2 --> M1
  F2 --> M2
  F2 --> M3
  M3 --> OUT[OR + 95% CI]
```

- **Model 1**：未调整  
- **Model 2**：+ 年龄 / 性别 / 种族（或等价人口学集）  
- **Model 3**：+ 终模协变量（来自 ⑥ VIF 终筛）  
- NHANES 版：**svyglm**；普通库：**glm**

---

## 6. ⑧ RCS — 子逻辑

```mermaid
flowchart TD
  RCS[RCS 回归] --> NL{P for nonlinearity<br/>显著?}
  NL -->|是| CUT[识别拐点]
  NL -->|否| LIN[按线性报告 ⑦ 结果]
  CUT --> SEG[按拐点分段暴露]
  SEG --> RELOG[重跑 ⑦ 逻辑回归<br/>分段分类变量]
  RELOG --> OUT[分段 OR 表]
```

- RCS 在 **Model 3 协变量** 下拟合  
- 拐点分段后的 Logistic 属于 RCS 步骤延伸，不另设第 11 步

---

## 7. ⑨ 亚组 — 子逻辑

```mermaid
flowchart TD
  SUB[亚组分析] --> STR[按预设分层变量拆分]
  STR --> FIT[各层内：连续暴露 + Model 3]
  FIT --> INT[交互检验<br/>暴露 × 分层变量]
  INT --> OUT[森林图 + P for interaction]
```

---

## 8. ⑩ 中介 — 子逻辑

```mermaid
flowchart LR
  EXP[暴露] -->|path a| MED[中介变量]
  MED -->|path b| OUT[结局]
  EXP -->|path c| OUT
```

- 中介模型调整集 **不含** 中介变量本身  
- NHANES 版：加权 mediation + bootstrap  
- 普通库：常规 mediation + bootstrap

---

## 9. 总流程图（NHANES · 纯逻辑）

```mermaid
flowchart TD
  DC[① 数据清洗] --> WGT[② 复杂加权]
  WGT --> UV[③ 单因素]
  UV --> VIF1[④ VIF 初筛]
  VIF1 --> MV[⑤ 多因素]
  MV --> VIF2[⑥ VIF 终筛]
  VIF2 --> LOG[⑦ 逻辑回归]
  LOG --> RCS[⑧ RCS]
  RCS --> SUB[⑨ 亚组]
  SUB --> MED[⑩ 中介]
```

---

*文档版本 v3 · 纯逻辑 · 2026-06-15*
