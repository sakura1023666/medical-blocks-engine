# IPW 用药套路：取消复合指标并行 + Jin 式 composite_risk STEPP

> 状态：已确认并实现（2026-07-23）  
> 日期：2026-07-23  
> 用户选择：方案 **C**（composite risk 协变量 = 单因素→VIF 筛出的预后集）  
> 前序：`2026-07-21-ipw-diabetes-stroke-batch-design.md`、`2026-07-22-ipw-diabetes-univar-vif-ps-design.md`  
> 结果根：`…/Medication_regimen_model_42118193/by_unit/【success】main/`

## 1. 目标

1. **去掉 NLR / 全部复合指标并行**：不再把复合指标当 batch 单元，也不再进入 PS / 协变量链。  
2. **STEPP 按 Jin 原文构建横轴**：用预后因子拟合 Cox，取线性预测值 `composite_risk` 作为 STEPP x 轴（非 NLR）。  
3. **清旧结果与检查点后整链重跑**（保留 `data/`）。

## 2. 方法学映射（Jin → 本项目）

| Jin 原文 | 本项目（方案 C） |
|----------|------------------|
| 暴露：放疗 vs 未放疗 | `Diabetes_HbA1c`（HbA1c≥6.5） |
| PS：11 项固定混杂 | 单因素（P&lt;0.10）→ VIF 后的 `Model2Factors`（**不含**复合指标、不含暴露） |
| STEPP 横轴：6 因子 Cox 的 LP（composite risk） | **同一套** VIF 后预后协变量拟合 28 天死亡 Cox → `composite_risk = LP`（**不含** `Diabetes_HbA1c`） |
| STEPP y：5 年 OS × 两臂 | 28 天生存率 × Diabetes No/Yes（沿用 `plot_style = "jin_treatment"`） |

说明：方案 C 故意让 STEPP 风险分与 PS 候选同源（可复现、少手工名单）；与 Jin「STEPP 因子 ⊆ 临床预后因子」一致。暴露不进风险分 Cox（对齐原文治疗不进 composite risk）。

## 3. 流水线变更

### 3.1 架构：单次主链（取消 index batch）

```
共享/主链（一次）
  data_clean → column_mapping
  →（index enable=FALSE）
  → imputation
  → ipw_diabetes_exposure
  → analysis_exclusion（仍硬排 HbA1c/糖尿病诊断；无当前复合指标依赖）
  →（去掉 trim_index_extreme）
  → univariate_prognosis → multicollinearity_screen（VIF）
  → ipw_jin_composite_risk   # 新增：用 Model2Factors 拟合 Cox → composite_risk
  → iptw_balance → iptw_association → flowchart → KM → subgroup → …
  → stepp_prognosis（index_var = composite_risk）
  → Cox sens → overlap → calib-ROC → literature_targets → pub_export
```

产出目录默认：`by_unit/【success】main/`（少改 pub 镜像习惯）。

### 3.2 新增 / 复用块

| 块 | 作用 |
|----|------|
| `ipw_jin_composite_risk`（69 新块） | 读取 VIF 后 `Model2Factors`（空则失败）；Cox → `composite_risk`；导出系数表对齐 Jin Supp Table S1 |
| `stepp_prognosis` | `index_var = "composite_risk"`；`plot_style = "jin_treatment"` |
| `iptw_balance` | `ps_covariates = "from_model2"`；**不再** ∪ 复合指标 |
| `ipw_surv_calibration_roc` | `include_index = FALSE`；协变量仍 from_model2 |

### 3.3 明确不做

- 不再跑全部复合指标 `study_batch$units`  
- 不再保留 `【success】NLR` 等旧指标目录作为正式结果  
- STEPP 横轴不使用 NLR / 任一实验室复合指标原值

## 4. 清库范围（重跑前）

在 `Medication_regimen_model_42118193/` 删除（**保留 `data/`**）：

- `by_unit/`、`checkpoints/`、`_shared/`  
- 根目录 `Figures/`、`Tables/`、`logs/`、`step*` 块目录  

## 5. Config 关键字段（草案）

```r
index = list(enable = FALSE)
study_batch = list(units = "main", unit_mode = "fixed", ...)
analysis_exclusion$protect_vars = c(..., "composite_risk")
stepp_prognosis$index_var = "composite_risk"
ipw_jin_composite_risk = list(
  factors = "from_model2",
  exclude_vars = c("Diabetes_HbA1c"),
  time_var = "surv_time_28d",
  event_var = "surv_event_28d",
  out_var = "composite_risk"
)
ipw_surv_calibration_roc$include_index = FALSE
```

## 6. 验证

1. 分析表/PS/Love 图中无 NLR 及其他复合指标列。  
2. 存在 `composite_risk`；系数表非空且因子 ⊆ Model2Factors。  
3. Figure 5 STEPP x 轴为 composite risk；两臂为 Diabetes。  
4. 主分析 IPW-KM / Table 1 可出。

## 7. 风险与接受

- VIF 后因子 &lt;2 → composite risk 块失败（本次不自动回退手工名单）。  
- 同一套因子既进 PS 又建风险分：接受为方案 C 代价。  
- 取消按 NLR 滤 NA 后 N 可能变大：属预期。

## 8. 用户确认项

请确认本规格后开始实现并清库重跑：

- [ ] 方案 C（composite risk = Model2Factors Cox LP）  
- [ ] 删除上述结果/检查点（保留 data）  
- [ ] 单次 `main` 链、无复合指标并行
