# 分析决策树 — 竞争风险（缺血性脑卒中 · 默认 AKI，28天）

> Run：`run_study.sh <研究> --routine competing`  
> 引擎入口：`run/competing_risk/run_competing_risk_chf_batch.R`  
> 方法学：Lai 2025 Cardiovasc Diabetol (PMID 40119388) 移植  

## 主事件

默认 **AKI**（相对 day1 肌酐 ↑≥0.3 或 ×1.5）；竞争：死亡 / 出院；删失：28 天。  
糖尿病版：切换 `derive_competing_diabetes_28d` 与 `disease_exclusion_vars`（HbA1c 相关）。

## 指标层主链

`imputation → competing_index_exposure → analysis_exclusion → LMM+mclust → flowchart → Table1 → LMM → Table3(+早停) → univariate → LASSO → RF → Fine-Gray/Cox Model1–6 → … → pub_export`
（**不挂** `trim_index_extreme`）

硬排除（AKI）：`Creatinine` / `BUN` / `UreaNitrogen` 及含其组分的复合指标。

## 关键产出

Figure 1–9 / Table 1–4；`by_unit/【success|failed】{Index}`。
