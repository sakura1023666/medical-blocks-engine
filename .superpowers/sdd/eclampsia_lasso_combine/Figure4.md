# Figure 4. LASSO feature selection

## 图面说明
LASSO 特征筛选拼图：A 为正则化系数路径（随 λ 增大系数收缩至 0）；B 为交叉验证曲线（标出选用 λ）。最终入选特征与下游 ML/SHAP 一致：UA_CR、ALT、Marital_Status、Hematocrit。

## 分析上下文
- 暴露: UA_CR
- 结局: DN（Case/Control）
- 样本量: n=509（训练集拟合 LASSO）
- Grouping: 与主文 Table 2 四分位闸门一致
- 数据库: MIMIC IV
- 是否拼图: 是（A/B）
- 候选来源: Table 1 变量池（candidate_source=table1）
