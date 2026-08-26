# File Contract（写入边界）

每次运行必须提供：
- paper_id: 论文编号，例如 paper_001
- qid: 问题编号，例如 Q1（取值 Q1~Q8）
- question: 具体问题
- context_file: adversarial_lit_reading/chunks/<paper_id>_*.md

只能写：
- AI-A：  rounds/A_tree_round1_<p>_<q>.md、rounds/A_tree_round2_revised_<p>_<q>.md
- AI-B：  rounds/B_attack_tree_<p>_<q>.md（由 glm_call.py 生成，首行 provenance 头）
- Judge： labels/<p>_<q>_training.jsonl、labels/training.jsonl（仅 score>=8 追加）、labels/review_needed/、labels/reject/
- Block： rounds/block_gap_<p>_<q>.md、**仅新 type** 的 configs/templates/*.template.R 与根 run_<type>.R

禁止（一律不覆盖）：
- 跨角色覆盖（AI-A 不写 B_*；AI-B 不写 A_*；Judge 不改 A/B）
- 修改 Blocks/、R/、已有 configs/*.R、已有 configs/templates/*.template.R、已有根 run_*.R
- 修改 rubrics/、prompts/、decision_tree_schema.md
