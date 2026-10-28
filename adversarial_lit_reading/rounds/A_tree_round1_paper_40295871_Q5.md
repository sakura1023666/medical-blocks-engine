# AI-A Decision Tree Round 1
paper_id: paper_40295871
question_id: Q5
question: 参数假设、划分、缺失？

## Evidence Map
|E1|Methods|80/20划分; SMOTE train; 四种插补比较选优; MinMax|
|E2|Fig.1 caption|写70/30——与Methods矛盾|
|E3|Outcomes|二分类；无PH/Cox假设（非生存回归主分析）|

## Provisional Answer
分类任务：关键假设为划分可复现、插补合理、SMOTE仅训练、MinMax。缺失：四法比较后选优（正文强调LR-MI较好）。文内划分比例矛盾须披露。无NHANES加权。ML超参见随机搜索。插补/缩放是否严格train-only原文未完全写清——迁移必须train-only。

## Uncertainty
U1 插补器外推；U2 70/30 vs 80/20
