# AI-A Decision Tree Round 1
paper_id: paper_40295871
question_id: Q8
question: 迁移到本人研究（脓毒症∩AKI，Age≥18，MIMIC+eICU）？

## Provisional Answer
可迁移：五步特征规则、七模型+TOPSIS、SMOTE train、内验定权、外验冻结、校准/DCA/SHAP。必须改写：纳排=脓毒症∩AKI ICD交集+Age≥18；开发/外验=MIMIC/eICU；结局列映射hosp28；特征取双库可算交集；强制train-only防泄漏；放弃儿科验证叙事。不适用：原文院内三中心原数据与中文指标名。
