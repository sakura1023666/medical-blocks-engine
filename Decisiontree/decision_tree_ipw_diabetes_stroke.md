# 分析决策树 — IPW 糖尿病 × 重症缺血性卒中（28天）

> 程序员入口：`studies/<研究>/config.R` + `run_study.* --routine ipw`  
> Runner：`run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R`  
> 方法学：Jin 2026；暴露 HbA1c≥6.5；结局 28 天全因死亡；**无实验室复合指标并行**  
> STEPP：VIF 后 Model2Factors → Cox LP = `composite_risk`（非 NLR）  
> 规格：`docs/superpowers/specs/2026-07-23-ipw-jin-composite-risk-no-index-design.md`

## 共享层
`data_clean → column_mapping`（`index` 关闭）

## 主链（unit = main）
`imputation → ipw_diabetes_exposure → analysis_exclusion（allow_no_index） → univariate → VIF → ipw_jin_composite_risk → iptw_balance → iptw_association → flowchart → KM → subgroup → STEPP(composite_risk) → Cox sens → overlap → calib-ROC → pub_export`

## 发表产出
- 图：Fig1–5；Supp S1–S4  
- 汇总表精简：Table 1 sIPTW；S1 Uno C-index；S2 插补前后；S3 单因素；S4 VIF  
- 整理脚本：`run/ipw_diabetes_stroke/curate_tables_jin_order.R`
