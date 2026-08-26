# 一键对抗阅读 Runbook

## 前置（按顺序，一次性）
0. 先建好脚本与 Skill（见操作文档 §4/§5/§6）：adversarial_lit_reading/scripts/glm_call.py、升级 batch_adversarial_run.py、.cursor/skills/adversarial-lit-reading/SKILL.md。
1. 项目根建 `.env`，写 `ZHIPU_API_KEY=...`；并把 `.env` 加入 `.gitignore`。
2. 自测 key（跨平台，先写临时文件再 --user-file）：
   printf '请只回复 OK 两个字' > /tmp/glm_test.txt
   python3 adversarial_lit_reading/scripts/glm_call.py --user-file /tmp/glm_test.txt --out /tmp/glm_out.md
   cat /tmp/glm_out.md   # 首行 provenance 头，下方 OK 即成功
3. 重启 Cursor，确认技能列表出现 adversarial-lit-reading。

## 单篇一键
在 Cursor Agent 输入：
> 使用 adversarial-lit-reading skill，对 paper_001 的 Q1 执行一键对抗阅读。

## 全流程（含 Block）
> 使用 adversarial-lit-reading skill：paper_id=paper_001, qid=Q1, 含 Block 抽取。

## 批量（无 Cursor）
cd adversarial_lit_reading
python3 scripts/batch_adversarial_run.py --papers paper_001,paper_002 --questions Q1,Q2,Q4,Q5,Q8 --sleep 2
python3 scripts/validate_jsonl.py --input labels/training.jsonl --strict

## 验收
6 文件齐 → B_*.md 首行 provenance 头 → 修正改了树结构 → validate PASS → score==sum → 六字段齐全 → 低分进 review_needed 不进 training.jsonl。
