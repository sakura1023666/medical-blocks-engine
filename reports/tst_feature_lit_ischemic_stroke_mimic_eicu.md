# TST 特征文献摘要 — 缺血性脑卒中（ICU 院内死亡）

- 日期：2026-11-18
- 队列：MIMIC-IV DN_first **n=3,228**（院内死亡 543，16.8%）；eICU DN_first **n=1,642**（Expired 233）
- 目标动态特征数：**50±10**（用户给定；N≈3000±200 时同档）
- 方法层：两阶段 Transformer（小时→天）、ffill、天级 mask、Day-k（实现与发表表述均**不**写「迁移/参考 Yang」；图表禁出现 Yang / pbaf003 字样）
- 特征策略：**本病文献白名单**；**不**按人数比例缩 226；**不**抄脓毒症 Supp 全表
- 对照评分：`comparator_score = SAPSII`（**不入** 50 维特征池；仅 Table/Fig 对比列）

## 1. 检索要点（近 10–15 年，ICU/危重缺血性卒中 × 死亡）

| 来源 | 常用/重要预测因子（与本文相关） |
|------|----------------------------------|
| Frontiers 系统综述 2025（ICU stroke 短期死亡模型） | **GCS、WBC、Age、Glucose** 最频 |
| Hypertensive stroke ICU 28d 死亡（MIMIC+eICU，XGBoost） | Age、Ethnicity、**WBC、MCV、Glucose、SpO2、Ca、RDW、BUN、bicarbonate** |
| 缺血性卒中 ICU 院内死亡 RF（MIMIC+外验） | **机械通气、Age、WBC、BUN、Hct、bicarbonate、SBP** |
| SuperLearner 危重缺血性卒中（MIMIC/eICU/外验） | 候选约 30–36；终模常含 Age、Weight、GCS、**WBC、RDW、FBG**（及评分；见排除） |
| 老年 ED 缺血性卒中院内死亡 | **NIHSS、Creatinine、Plt、高血糖** |
| ICU IS/ICH 30d 死亡 | Age、**GCS**、急性生理紊乱、**机械通气**、急性肾损 |

## 2. 硬排除（疾病计算 / 泄漏 / 不可用）

| 类型 | 处理 | 理由 |
|------|------|------|
| **NIHSS / ASPECTS / 梗死体积** 等卒中专病评分 | 不入动态池 | 「疾病计算相关」；且当前 72 列表无 NIHSS |
| **SAPS II / OASIS / SOFA / APACHE** 等综合严重度 | **不入**动态 50 维；**另挂** `comparator_score=SAPSII` | 防循环论证；对比用分数与建模特征脱钩 |
| 诊断码 / 卒中亚型标签 | 不入 | 队列已由诊断定义 |
| `st1/st2/st3` | 不入 | ECG ST 噪声/报警向，非卒中预后核心 |
| `troponin - I`（MIMIC 本队列 stay_ever≈0） | 不入 | 库内近乎全空 |
| 重复列 | 只留一列 | `sao2`←去 SaO2/O2 Sat (%)；`bicarbonate`←去 HCO3；`glucose`←去 bedside glucose |
| 弱证据/过稀 | 不入主名单 | `urinary specific gravity`、`cvp`（ever≈2%）、`-basos/-eos/-monos`、`total protein`、`alkaline phos.`、`total bilirubin` |

静态层：保留 **Age / Gender / Height / Weight / GCS(eyes,motor,verbal) / intubated / vent / dialysis**；**不**把 39 个 physicianspeciality one-hot 算进「50 指标」。

## 3. 拟锁定动态白名单（**n=50**）

生命体征 / 血压 / 氧合（11）  
`heartrate`, `respiration`, `temperature`, `systemicmean`, `systemicsystolic`, `systemicdiastolic`, `noninvasivemean`, `noninvasivesystolic`, `noninvasivediastolic`, `sao2`, `Total RR`

代谢 / 肾 / 电解质（12）  
`glucose`, `creatinine`, `BUN`, `bicarbonate`, `anion gap`, `calcium`, `sodium`, `potassium`, `chloride`, `magnesium`, `phosphate`, `lactate`

血细胞（8）  
`WBC x 1000`, `-lymphs`, `-polys`, `Hgb`, `Hct`, `RDW`, `RBC`, `platelets x 1000`, `MCV`  
→ 若严格数到 50：上列血细胞为 **9** 项时，总动态=51；定稿取 **去掉 `RBC`（与 Hgb/Hct 高度共线）→ 恰好 50**。

凝血 / 血气（7）  
`PT`, `PTT`, `PT - INR`, `pH`, `paCO2`, `paO2`, `Base Excess`

通气支持（7）  
`FiO2`, `PEEP`, `LPM O2`, `Peak Insp. Pressure`, `Plateau Pressure`, `Mean Airway Pressure`, `Tidal Volume (set)`

肝酶（2）  
`ALT (SGPT)`, `AST (SGOT)`

**合计：11+12+8+7+7+2 = 47？** 重算：

- 生命体征块 11  
- 代谢 12  
- 血细胞去 RBC 后 8（WBC, lymphs, polys, Hgb, Hct, RDW, platelets, MCV）  
- 凝血血气 7  
- 通气 7  
- 肝酶 2  
- **11+12+8+7+7+2 = 47**

再加回文献高频且库可得的 **`albumin`** + 通气常用 **`Vent Rate`** + **`Exhaled MV`** → **50**。

### 最终 50 列（列名与检测表一致）

1. heartrate  
2. respiration  
3. temperature  
4. systemicmean  
5. systemicsystolic  
6. systemicdiastolic  
7. noninvasivemean  
8. noninvasivesystolic  
9. noninvasivediastolic  
10. sao2  
11. Total RR  
12. glucose  
13. creatinine  
14. BUN  
15. bicarbonate  
16. anion gap  
17. calcium  
18. sodium  
19. potassium  
20. chloride  
21. magnesium  
22. phosphate  
23. lactate  
24. albumin  
25. WBC x 1000  
26. -lymphs  
27. -polys  
28. Hgb  
29. Hct  
30. RDW  
31. platelets x 1000  
32. MCV  
33. PT  
34. PTT  
35. PT - INR  
36. pH  
37. paCO2  
38. paO2  
39. Base Excess  
40. FiO2  
41. PEEP  
42. LPM O2  
43. Peak Insp. Pressure  
44. Plateau Pressure  
45. Mean Airway Pressure  
46. Tidal Volume (set)  
47. Vent Rate  
48. Exhaled MV  
49. ALT (SGPT)  
50. AST (SGOT)  

每列配套小时 `*_mask`（建模用；**不计入**「50 指标」名额）。

## 4. 建模口径（用户已认同的原文方法层）

1. 纳排：原文五条规则迁移至卒中（含 **>30% missing → 剔 stay**；当前 DN_first 已含该步）  
2. 白名单 **50 维固定**，**不再**按 day1 缺失砍特征维  
3. 时序：小时网格 + **前向填充** + 小时 mask  
4. 不足 5 天：**天级 mask**；Day-k：**后续天 mask**  
5. 主库 MIMIC 3228；eICU 外验  

## 5. 待用户确认

- [ ] 动态 50 列名单是否锁定  
- [ ] 静态是否仅 Age/Gender/Ht/Wt/GCS/vent/intubated/dialysis  
- [ ] 确认后写 `configs/tst_feature_priority/ischemic_stroke_mimic.R`（及 eICU 同源）并开 config / shared  

## 6. 参考文献（URL）

- https://www.frontiersin.org/journals/neurology/articles/10.3389/fneur.2025.1623645/full  
- https://pmc.ncbi.nlm.nih.gov/articles/PMC10443100/  
- https://www.sciencedirect.com/science/article/abs/pii/S1386505625000917  
- https://pmc.ncbi.nlm.nih.gov/articles/PMC13330188/  
- https://pmc.ncbi.nlm.nih.gov/articles/PMC10763719/  
- https://journals.sagepub.com/doi/10.1177/1076029614550820  
