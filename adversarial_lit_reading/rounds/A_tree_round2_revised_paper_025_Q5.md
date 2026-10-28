# AI-A Decision Tree Round 2 (Revised)
paper_id: paper_025
question_id: Q5
revision_of: A_tree_round1_paper_025_Q5.md
attack_source: B_attack_tree_paper_025_Q5.md

## Revision Log
采纳 AI-B 高严重度批评并写入终答。摘要：中: MNAR/FF/划分正确；强调P0未闭合。

## Provisional Answer（终版）
MNAR+前向填充+缺失mask；生理clip后q5-q95归一并再clip；患者级70/15/15；非加权设计；α=20与RLoS cap=10为设计常量。FF时限等上游细节在本地RealExtraction仍有P0未闭合项。

## Note
完整节点表以终答为准；训练样本见 labels/paper_025_Q5_training.jsonl。
