# AI-A Decision Tree Round 2 (Revised)
paper_id: paper_025
question_id: Q2
revision_of: A_tree_round1_paper_025_Q2.md
attack_source: B_attack_tree_paper_025_Q2.md

## Revision Log
采纳 AI-B 高严重度批评并写入终答。摘要：高: 损失是MSLE非MAPE；条件级联非并列联合；需补多亚型/二值药暴露/RLoS cap分支。

## Provisional Answer（终版）
双终点为条件级联设计：先死亡概率，再在存活条件下预测RLoS；训练损失为条件性 BCE+α·MSLE（α=20），评估用MAPE（勿与损失混淆）。不是临床复合终点聚合；Mcomposite仅跨配置排序。原文未做多重比较校正。无正式患者亚型分析；Table1有unit type描述且HiRID缺失；药物暴露为二值有/无，非多层剂量。RLoS cap=10天。

## Note
完整节点表以终答为准；训练样本见 labels/paper_025_Q2_training.jsonl。
