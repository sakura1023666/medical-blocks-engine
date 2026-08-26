---
name: adversarial-lit-reading
description: One-click adversarial literature reading. Drives TWO models automatically — the Cursor agent acts as AI-A (reader/reviser/judge) while GLM 5.1 API acts as AI-B (critic) — to produce evidence-bound decision trees, attacks, revisions, a 10-pt Judge score, and JSONL training data. Use when the user says "一键对抗阅读 / adversarial reading / 对 paper_X 的 Q_n 跑对抗".
---

# Adversarial Literature Reading（一键对抗阅读）

## CWD 约定
所有命令与路径一律**以项目根为基准**（带 adversarial_lit_reading/ 前缀）。执行前确认当前目录是项目根，不要 cd 进 adversarial_lit_reading。

## 目标
一句话把一篇论文×一个问题跑成可复核、可训练的对抗记录，全程不手动复制粘贴。

## 角色分工（铁律）
- AI-A（建树/修正/Judge）= **你自己**（执行本 Skill 的 Cursor 智能体）。
- AI-B（攻击）= **GLM 5.1 API**，必须通过运行 `scripts/glm_call.py` 真实调用，**绝不伪造 GLM 输出**。
- 写入边界见 `.cursor/rules/adversarial_literature_reading.mdc` 与 `reference/file_contract.md`：AI-A 只写 `rounds/A_*.md`，AI-B 只写 `rounds/B_*.md`，Judge 只写 `labels/*.jsonl`。

## 输入（从用户消息解析）
paper_id（如 paper_001）、qid（Q1~Q8）、question（若缺，按 qid 从 `prompts/question_templates_medical.md` 第 8.1 节取）、是否含 Block 抽取（默认否）。

## 执行步骤（严格按序）
设 PAPER、QID、CHUNK=adversarial_lit_reading/chunks/<PAPER>_*.md。

1. **建树**：以 `prompts/AI_A_reader_decision_tree.md` 为指令，读 CHUNK 回答该 qid，写 `rounds/A_tree_round1_<PAPER>_<QID>.md`（六部分齐全，每节点有 node_id，边标关系）。
2. **攻击（调 GLM，非零退出即中止）**：把「初稿全文 + CHUNK 全文 + 问题」写入 `rounds/_for_glm/<PAPER>_<QID>.md`；运行：
   `python3 adversarial_lit_reading/scripts/glm_call.py --system-file adversarial_lit_reading/prompts/AI_B_tree_critic.md --user-file adversarial_lit_reading/rounds/_for_glm/<PAPER>_<QID>.md --out adversarial_lit_reading/rounds/B_attack_tree_<PAPER>_<QID>.md --thinking`
   **若退出码 ≠ 0：立即停止整条 pipeline 并报告错误，禁止进入 3、禁止自行生成 B_***。读回后核对首行为 `<!-- glm_call provenance:`（缺失=伪造，判 FAIL），不得改写。
3. **修正**：以 `prompts/AI_A_revise_decision_tree.md` 为指令，读初稿+攻击+原文，severity=高必采纳，写 `rounds/A_tree_round2_revised_<PAPER>_<QID>.md`（含 Revision Log），并在聊天框画终版 Mermaid。
4. **评分（六字段 + metadata）**：以 `prompts/Judge_labeler.md` 为指令，读初稿+攻击+修正+原文，给 10 分 score_detail 六维度，**同时产出两棵树** rejected_decision_tree 与 chosen_decision_tree（各含 mermaid+nodes+edges）+ rejected_answer/critique/chosen_answer/evidence；强制单行 JSON 写 `labels/<PAPER>_<QID>_training.jsonl`。metadata 含 reader_model="Cursor model"、critic_model="GLM 5.1"、judge="Cursor model (Judge_labeler)"、created_at=今天(YYYY-MM-DD)。保证 score==sum(score_detail)、各维度为 int、键名在白名单、edges 无悬空、node_id 唯一。
5. **校验+修复**：运行 `python3 adversarial_lit_reading/scripts/validate_jsonl.py --input adversarial_lit_reading/labels/<PAPER>_<QID>_training.jsonl --fix-hints`。标量错误（score≠sum、float、缺字段）直接 patch 重存；结构错误（悬空边/重复 node_id/解析失败）重跑第 4 步 Judge 而非原地改；最多 3 次。仍 FAIL 则写入 `labels/review_needed/<PAPER>_<QID>_training.jsonl`（标 status:"fail"）不进 training.jsonl 并报告。PASS 后按 score 分桶：>=8 追加进 labels/training.jsonl；6-7 进 review_needed/；<=5 进 reject/。
6. **（可选）Block 抽取**：仅当用户要求。以 `prompts/Block_Extractor.md` 为指令，读 Judge JSONL+CHUNK+Blocks/+prompt/pipeline_config_wizard_prompt.txt+Data/mimic/D04_dabiao.RData，写 `rounds/block_gap_<PAPER>_<QID>.md`（**仅新 type** 才新建 configs/templates/*.template.R + 根 run_<type>.R；已有 config/template/run_*.R 一律不覆盖，需改动先 diff + 用户确认）。不碰 Blocks/、R/；缺失 block 只登记；展示终版决策树。

## 不做的事
- 不伪造 GLM 攻击结果；glm_call 非零退出必须中止（不得回退到自行生成）；不在无 key 时假装调用了 GLM（应提示用户配 ZHIPU_API_KEY）。
- 不把整篇超长 PDF 塞进上下文（用 chunks）。
- 不覆盖其他角色文件；不让两个角色写同一文件；不覆盖已有 configs/templates/、根 run_*.R。
- 不直接声称已训练模型参数。

## 完成
报告每步写了哪个文件、B_*.md 的 provenance 头、validate 的 PASS/FAIL、终版决策树图、score 与分桶（train≥8 / review 6-7 / reject≤5）。
