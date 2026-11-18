# 分析决策树 — 交叉滞后 · 抑郁 × 虚弱（三库）

> 改编自 `decision_tree_cross_lagged_frailty.md`（PMID 40595747 髋部套路）  
> 产出根：`Output/22_depression_cross-laged_40595747` → sync `G:/02block_result/22_depression/cross-laged_40595747`  
> Prep：`scripts/prep_cross_lagged_depression_frailty.R`

## 研究设定

| 项 | 值 |
|---|---|
| 暴露 | 连续 `FI`（ELSA 剔除 CES-D/psced 后重算） |
| 结局 | `Disease_Group`：Depression / No_Depression（CES-D） |
| 基线 | CHARLS 2011；ELSA wave4；HRS 2012 |
| 插补 | **FI 与抑郁不进 MICE**；缺失 listwise；协变量可插补 |
| 表图对齐 | 髋部 `summary_result` MANIFEST（后续 phase 补齐） |

## 一期（已完成）

prep → data_clean → column_mapping → analysis_exclusion → imputation → **baseline_binary (Table 1)**

## 后续

按髋部 phase：VIF → Pooled → logistic/RCS/亚组 → 纵向/敏感性 → summary 对齐髋部表图清单。
