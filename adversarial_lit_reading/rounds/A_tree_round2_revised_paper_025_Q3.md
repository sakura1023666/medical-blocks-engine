# AI-A Decision Tree Round 2 (Revised)
paper_id: paper_025
question_id: Q3
revision_of: A_tree_round1_paper_025_Q3.md
attack_source: B_attack_tree_paper_025_Q3.md

## Revision Log
采纳 AI-B 高严重度批评并写入终答。摘要：高: TableS2证据强度；池化MIMIC专化反例；架构vs策略正交；换方法未答。

## Provisional Answer（终版）
选TPC前先做Transformer/LSTM/TPC三架构基准（Methods）；MOESM2 Table S2显示多数子集两任务TPC更优，但需以完整表为准，eICU死亡AUROC存在TPC非最优例外。架构选择与训练策略（单源/池化/迁移）正交：池化在未见库泛化常最优，但MIMIC专化上池化劣于单源MIMIC（Mcomposite 0.97 vs 0.89）；Amsterdam专化上池化与迁移接近。换架构是否仍保持池化优势：原文未做全网格，不能外推；捷径学习提示换架构未必消除域偏移。

## Note
完整节点表以终答为准；训练样本见 labels/paper_025_Q3_training.jsonl。
