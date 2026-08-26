# IPW 糖尿病卒中：单因素→VIF→PS（取消 LASSO/RF）设计

> 状态：已确认（用户 2026-07-22）  
> 承接：`2026-07-21-ipw-diabetes-stroke-batch-design.md`  
> 变更：去掉 LASSO/RF；trim 后 `baseline_binary` 正式 Table 1（按 Diabetes_HbA1c）；PS 协变量来自 VIF 后 Model2Factors

## 锁定决策

| 项 | 选择 |
|----|------|
| 正式 Table 1 | `iptw_balance` Jin 同构：Overall / 两组 N(%) / P / SMD未加权 / SMD加权 |
| Love plot | Figure S1（Supp） |
| 特征筛选 | `univariate_prognosis` → `multicollinearity_screen`（无 LASSO/RF）；均在**未加权**样本 |
| PS 协变量 | `ps_covariates = "from_model2"`：`Model2Factors` ∪ 当前复合指标 |
| `feature_selection$enable` | `FALSE`（VIF 用严格阈值） |
| baseline_binary | **不进 pipeline**（避免抢 Table 1 序号） |

## Worker 主链

```
imputation → ipw_diabetes_exposure → analysis_exclusion → trim_index_extreme
  → univariate_prognosis
  → multicollinearity_screen
  → iptw_balance（Jin Table 1） → iptw_association → flowchart → KM → subgroup → STEPP
  → cox_binary → overlap → literature_targets → pub_export
```

## 审计

- `Table_1_Baseline_IPW`：匹配 `Table 1` / Baseline；`result_key` → `sig_vars`（baseline_binary）
- IPTW 平衡表不再作为 Table 1 键
