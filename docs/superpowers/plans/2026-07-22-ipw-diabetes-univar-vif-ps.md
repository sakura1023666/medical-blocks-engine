# IPW 糖尿病：单因素→VIF→PS 实施计划

> 对应 design：`docs/superpowers/specs/2026-07-22-ipw-diabetes-univar-vif-ps-design.md`

## 文件

| 文件 | 改动 |
|------|------|
| `Decisiontree/decision_tree_ipw_diabetes_stroke.md` | 更新主链 |
| `configs/templates/config_ipw_diabetes_stroke_batch.template.R` | pipeline + baseline + multicollinearity；去 lasso/RF |
| live `config_ipw_diabetes_stroke_batch.R` | 同上 |
| `Blocks/34_IPTW/01block_iptw_balance.R` | `from_model2` 解析 |
| `Blocks/69_.../06block_ipw_literature_targets.R` | Table1 审计 |
| `.superpowers/sdd/progress_ipw_diabetes.md` | 进度 |

## 任务

1. iptw_balance：`from_model2` = Model2Factors ∪ 当前 unit（排除暴露/结局）
2. 配置 + 决策树 + 审计
3. NLR 冒烟（可从 trim/univar ck 或 --no-skip 单 unit）
