# Adversarial Literature Reading

本项目用于**双 AI 对抗式文献阅读与决策树训练**。把一次文献阅读变成可复现、可评分、可沉淀的训练数据生产流程。

> 对应操作手册《双 AI 对抗式文献阅读决策树训练操作手册》(v1.0, 2026-06-16)。
> 当前 `papers/` 为**医学/流行病学文献**（心脏代谢指数、心脏骤停亚型、抑郁/NHANES），
> 因此问题模板（第 8 章）已改编为医学版，见 `prompts/question_templates_medical.md`。

---

## Workflow（核心流程）

```
同一篇文献 / 同一个研究问题
        ↓
AI-A：文献阅读者 / 决策树建构者   →  生成：证据表 + 决策树 + 节点解释
        ↓
AI-B：对抗审稿人 / 决策树攻击者   →  攻击：节点、边、证据、分支、结论迁移
        ↓
AI-A：修正者                       →  修正：删除无证据节点、改写边关系、补充不确定性
        ↓
Judge：裁判 / 标注员               →  评分：可信度、方法理解、树逻辑、证据绑定
        ↓
保存：Markdown + JSONL             →  用于：SFT / DPO / RAG 评测
```

四步落地（详见手册第 9 章）：

1. AI-A reads paper and builds **evidence-based decision tree** → `rounds/A_tree_round1_*.md`
2. AI-B critiques the tree at **node / edge / evidence / branch** levels → `rounds/B_attack_tree_*.md`
3. AI-A revises the tree and final answer → `rounds/A_tree_round2_revised_*.md`
4. Judge scores the revised output and saves JSONL → `labels/*_training.jsonl`

---

## Folder Rules

| 目录 | 用途 |
|---|---|
| `papers/` | 原始论文 PDF；`papers/index.md` 为 paper_id 清单（自动生成） |
| `chunks/` | PDF 转换后的 Markdown 分块文本（由 `scripts/pdf_to_chunks.py` 生成） |
| `prompts/` | 可复用 Prompt（AI-A / AI-B / Judge / 问题模板） |
| `rounds/` | 所有 A/B 输出 |
| `labels/` | JSONL 训练数据 |
| `rubrics/` | 评分标准（10 分 Rubric） |
| `scripts/` | 自动化脚本（PDF 切分、JSONL 校验、批处理） |

## File Permission Rules（写入权限，严格分区）

- **AI-A** writes only `rounds/A_*.md`
- **AI-B** writes only `rounds/B_*.md`
- **Judge** writes only `labels/*.jsonl`
- 评分标准只能写 `rubrics/*.md`
- Prompt 模板只能写 `prompts/*.md`
- 两个 Agent **不允许修改同一个输出文件**。

---

## Current Question Types（医学改编版 Q1–Q8）

| 编号 | 问题（简） |
|---|---|
| Q1 | 是否预设分组/亚型/类别数？数据驱动还是先验指定？ |
| Q2 | 如何处理多亚型/多终点/多层暴露？多重比较？ |
| Q3 | 与 logistic/Cox/PSM/IPTW/LCA/其他 ML 有何区别？ |
| Q4 | 变量筛选与建模逻辑？入模依据/交互/非线性/共线性？ |
| Q5 | 参数/假设依赖？（含 NHANES 加权、缺失处理） |
| Q6 | 如何证明有效？（区分度/校准/内部外部验证/E-value） |
| Q7 | 局限有哪些？（混杂、偏倚、因果、可重复性） |
| Q8 | 哪些可用于我的研究？（Q8 需先确认研究方向） |

> 完整三列表 + 各论文重点映射 + 建议跑法见 [`prompts/question_templates_medical.md`](prompts/question_templates_medical.md)。

---

## Quickstart

### 0. 一次性：把论文转成 Markdown 分块

```bash
pip install pymupdf
python3 scripts/pdf_to_chunks.py          # 处理 papers/ 下全部 PDF
```

产物：`chunks/paper_NNN_<slug>.md` + `papers/index.md`。

### 1. AI-A 生成第一版决策树（示例：paper_001 / Q1）

> 在 Cursor 模型对话框中引用论文 chunk 与 AI-A Prompt：

```
请使用 @adversarial_lit_reading/prompts/AI_A_reader_decision_tree.md
阅读 @adversarial_lit_reading/chunks/paper_001_*.md
回答 Q1（见 prompts/question_templates_medical.md 第 8.1 节）
只把结果写入： @adversarial_lit_reading/rounds/A_tree_round1_paper_001_Q1.md
不要修改其他文件。
```

### 2. AI-B 攻击第一版决策树

```
请使用 @adversarial_lit_reading/prompts/AI_B_tree_critic.md
审查 @adversarial_lit_reading/rounds/A_tree_round1_paper_001_Q1.md
并对照 @adversarial_lit_reading/chunks/paper_001_*.md
只把结果写入： @adversarial_lit_reading/rounds/B_attack_tree_paper_001_Q1.md
```

### 3. AI-A 修正

```
请使用 @adversarial_lit_reading/prompts/AI_A_revise_decision_tree.md
原始树: @rounds/A_tree_round1_paper_001_Q1.md
攻击意见: @rounds/B_attack_tree_paper_001_Q1.md
原文: @chunks/paper_001_*.md
输出到: @rounds/A_tree_round2_revised_paper_001_Q1.md
```

### 4. Judge 评分 + 生成 JSONL

```
请使用 @adversarial_lit_reading/prompts/Judge_labeler.md
读取 A_tree_round1 / B_attack_tree / A_tree_round2_revised + 原文 chunk
输出到: @labels/paper_001_Q1_training.jsonl（单行 JSON）
```

### 5. 校验 JSONL

```bash
python3 scripts/validate_jsonl.py --input labels/paper_001_Q1_training.jsonl
python3 scripts/validate_jsonl.py --input labels/training.jsonl --strict   # CI 用
```

---

## 文件命名规范

| 类型 | 命名 | 说明 |
|---|---|---|
| 论文 PDF | `papers/<原始文件名>.pdf` | 由 `pdf_to_chunks.py` 统一分配 `paper_NNN` |
| 论文文本 | `chunks/paper_001_<slug>.md` | PDF 转文字版 |
| AI-A 初始树 | `rounds/A_tree_round1_paper_001_Q1.md` | 第一轮决策树 |
| AI-B 攻击 | `rounds/B_attack_tree_paper_001_Q1.md` | 只批判，不改原文件 |
| AI-A 修正版 | `rounds/A_tree_round2_revised_paper_001_Q1.md` | 修正后的树与答案 |
| Judge 标注 | `labels/paper_001_Q1_training.jsonl` | 最终训练样本（单行 JSON） |

> 命名稳定很重要：JSONL 会引用 `paper_id`、`question_id` 与文件路径。建议**不用中文空格和括号**。

---

## 参考文档

- [`decision_tree_schema.md`](decision_tree_schema.md) — 决策树标准格式（L0–L5 / 节点字段 / 边关系 / Markdown 模板）
- [`rubrics/scoring_rubric_10pt.md`](rubrics/scoring_rubric_10pt.md) — 10 分评分 Rubric
- [`prompts/question_templates_medical.md`](prompts/question_templates_medical.md) — 医学改编八问
- [`papers/index.md`](papers/index.md) — 论文清单（自动生成）

## 最终目标

让 AI 不只是帮你读论文，而是帮助你生产**可审查、可训练、可复用**的文献推理数据：
同一个问题、同一篇论文 → 第一版错误树 → 对抗批评 → 修正版决策树 → Judge 评分 → JSONL 样本。
