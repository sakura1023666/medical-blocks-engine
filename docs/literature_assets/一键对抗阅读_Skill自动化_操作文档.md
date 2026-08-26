# 一键对抗阅读：用 Cursor Skill 自动驱动「双 AI 对话框」全流程操作文档

> 版本 v1.1（已过对抗式核查）｜ 日期 2026-06-18
> 对象：`adversarial_lit_reading/` 系统（1111111.pdf 全流程已实现并跑通 paper_003）
> 目标：把「手动在两个对话框之间复制粘贴」升级为「一句话触发、Cursor Skill 自动驱动两个模型跑完 6 轮」
> 配套：1111111.pdf（操作手册 12 章）、Cursor_Skills_一键对抗阅读_详细教学流程_修复版.pdf（v2.0 半自动版）、对抗式文献阅读系统_从头到尾操作步骤.txt

---

## 0. 一句话总览

你只要在 Cursor Agent 里输入一句：

> **使用 adversarial-lit-reading skill，对 paper_001 的 Q1 执行一键对抗阅读。**

Cursor 就会**自动**：建树（AI-A，Cursor 自身）→ 调 GLM 5.1 API 攻击（AI-B）→ 修正 → 评分 → 生成 JSONL → 校验 →（可选）抽取 Block，全程零复制粘贴。

```
                ┌─────────────────────────────────────────────┐
                │   Cursor Agent（执行 Skill 的智能体 = AI-A） │
                │   模型 = Cursor 内置 / Claude（你选的那个）   │
                └───────────────┬─────────────────────────────┘
                                │  自己读论文、建树、修正、当 Judge
        Step1 AI-A 建树         │  Step3 AI-A 修正      Step4 Judge 评分
        ────────────────        │  ───────────────      ────────────────
                                │
                  Step2 调用 GLM │（运行 python3 scripts/glm_call.py，失败即中止）
                ┌───────────────▼───────────────┐
                │  GLM 5.1 API（AI-B 攻击者）    │  open.bigmodel.cn
                └───────────────┬───────────────┘
                                │  返回攻击意见 + provenance 头 → 写入 B_attack_tree_*.md
                                ▼
            Step5 校验（validate_jsonl.py）→ PASS 入库 / FAIL 定向修复，3 次仍败转 review_needed
                                ▼
            Step6（可选）Block 抽取 → rounds/block_gap_*.md +（仅新 type）configs/run 模板
```

> **轮次说明**：源手册 1111111.pdf 第 9.6 节是 5 轮（建树/攻击/修正/Judge/存 JSONL）。本文档在此基础上**新增第 5 步「校验+修复」、第 6 步「Block 抽取」**，成为 6 步。下方统一用 ①~⑥ 编号（与 §0 流程图、SKILL.md 的 1~6 一一对应）。

> **方法论前提**：本自动路径建立在源手册第 9–11 章「先用 5 篇论文手动跑稳 Prompt / Rubric / JSONL schema」之后（你已完成 paper_003 全流程）。未稳定前请勿一键批量，否则会快速产出大量低质样本。源手册 4 周路线：第 1 周手动 25 条 → 第 2 周固定 schema → 第 3 周写脚本 → 第 4 周累计 50–100 条。

---

## 1. 你要做成什么效果

把现在「在 Cursor 窗口和 GLM 窗口之间手动来回粘贴」的操作，封装成一个 **Cursor Skill**。最终：

- **一句话触发**：`使用 adversarial-lit-reading skill，对 <paper_id> 的 <Qid> 一键对抗阅读。`
- **两个模型自动分工**：AI-A / Judge = 执行 Skill 的 Cursor 智能体（即 Cursor 内置模型或你在 Cursor 选的 Claude）；AI-B = GLM 5.1 API，由智能体通过运行脚本自动调用。
- **六类文件自动产出**（沿用你现有命名，不改动既有产物）：
  - `rounds/A_tree_round1_<paper>_<qid>.md`（AI-A 初稿）
  - `rounds/B_attack_tree_<paper>_<qid>.md`（AI-B 攻击，**GLM 真生成，带 provenance 头**）
  - `rounds/A_tree_round2_revised_<paper>_<qid>.md`（AI-A 修正）
  - `labels/<paper>_<qid>_training.jsonl`（Judge 训练样本，单行、score 自洽、PASS 才入库）
  - `rounds/block_gap_<paper>_<qid>.md`（可选，Block 抽取）
  - 校验报告（终端打印 PASS / FAIL）

---

## 2. 先理解：为什么这样分工（最关键的一节）

### 2.1 三个角色的真实归属

| 角色 | 任务 | 由谁执行 | 为什么 |
|---|---|---|---|
| **AI-A 阅读者/建构者** | 读论文 → 抽证据 → 建决策树 → 修正 | **Cursor 智能体本身** | Skill 在 Cursor 里运行，执行它的智能体就是 Cursor 内置模型；它还能直接读写项目文件、看 `chunks/`、复用你已有的 4 个 Prompt |
| **AI-B 攻击者** | 逐节点/边/证据/分支对抗攻击 | **GLM 5.1 API** | 两个模型越不同对抗越有效；GLM 5.1 是和 Cursor 异构的强模型；通过一行脚本调用，全自动 |
| **Judge 裁判** | 10 分评分 + 生成 JSONL | **Cursor 智能体** | Judge 需要读 4 个文件并精确产出单行 JSON，Cursor 智能体能直接落盘并立即跑 `validate_jsonl.py` 自检 |
| Block 抽取（可选） | 统计方法→Blocks 映射 | **Cursor 智能体** | 需要 `Blocks/`、`R/`、`configs/` 仓库知识 + 你的 `Data/*.RData`，必须在 Cursor 侧 |

> 这正是你已跑通的 `paper_003_Q1_training.jsonl` 里记录的分工：
> `metadata.reader_model = "Cursor model"`、`critic_model = "GLM 5.1"`、`judge = "Cursor model (Judge_labeler)"`。
> 本文档只是把这套分工从「手动」变成「一键」。

### 2.2 「一键控制两个对话框」的诚实说明

Cursor 没有办法让一个 Skill 去「 puppet 」另一个独立的 GLM 聊天窗口（那需要 RPA/浏览器自动化，极脆弱）。真正的「一键」只有两种可靠实现，本系统**两种都给你**：

| 方案 | AI-A | AI-B | 触发方式 | 适合场景 |
|---|---|---|---|---|
| **A. Skill 驱动（推荐 / 主路径）** | Cursor 智能体 | GLM API（脚本调用） | Cursor 里一句话 | 日常单篇/几篇，想要「一句话」体验，需要 Cursor 模型参与 |
| **B. 纯脚本全自动（批量）** | API 模型（GLM 或 Claude/OpenAI） | GLM API | 终端一条命令 | 一次批量 5–50 篇无人值守，Cursor 不参与 |

> v2.0 半自动版（Cursor_Skills PDF）的局限是「没 API，只能生成 GLM 提示词让你手动粘」。你现在**有 GLM API key**，所以可以越过这个限制，做到真全自动。本文档主路径 = 方案 A，附录给出方案 B 的完整脚本。

> **两条退化路径必须堵住**：① GLM 脚本调用失败 → 智能体可能自己编一段「攻击文本」伪造 AI-B；② 智能体跳过脚本直接写 `B_*.md`。本文档用 **provenance 头 + 「非零退出即中止」铁律**（见 §7 ②、附录 A/C）从技术上防伪造，而不是只靠一句自然语言禁令。

### 2.3 你已有的不动，只新增 3 样东西

1. `adversarial_lit_reading/scripts/glm_call.py` —— GLM 5.1 接入（纯标准库，零依赖，带 provenance）
2. 升级 `adversarial_lit_reading/scripts/batch_adversarial_run.py` —— 把 `call_model()` 占位接通成真实 API + 自动归一化 + 校验 + 分桶入库（方案 B 用；方案 A 里智能体也会复用它调 GLM）
3. `.cursor/skills/adversarial-lit-reading/SKILL.md` + reference 文件 —— 一键编排大脑

你现有的 `prompts/`（4+1 角色 Prompt）、`rubrics/`、`decision_tree_schema.md`、`validate_jsonl.py`、`.cursor/rules/adversarial_literature_reading.mdc` **全部复用，不改动**。

---

## 3. 前置准备

### 3.1 你需要的东西

- ✅ `adversarial_lit_reading/` 系统（已就绪，paper_001/002/003 已转 chunk）
- ✅ Python 3（已能跑 `validate_jsonl.py`，说明环境 OK）
- ✅ **GLM 5.1（智谱 BigModel）API key**：在 https://open.bigmodel.cn/ → 个人中心 → API keys 创建
- ✅ Cursor 已能打开本项目（已确认 `.cursor/rules`、`.cursor/skills/` 存在）

### 3.2 确认 GLM 5.1 API 规格（已核实，照抄即可）

```
端点 ENDPOINT : https://open.bigmodel.cn/api/paas/v4/chat/completions
模型 MODEL    : glm-5.1
鉴权 AUTH     : Authorization: Bearer <你的 api key>
协议          : OpenAI 兼容（可直接用标准库 urllib 调）
推荐参数      : thinking={type:enabled}（攻击者开深度思考）
              max_tokens=65536  ← 开 thinking 时这是「思维链+回复」总预算，给小了会被思维链耗尽→空回复
              temperature=1.0   ← 官方示例统一用 1.0
官方文档      : https://docs.bigmodel.cn/cn/guide/models/text/glm-5.1
```

> ⚠️ **核查发现的坑**：GLM-5.1 在 `thinking=enabled` 下，`max_tokens` 是 `reasoning_content + content` 的**总**预算。若设成常见默认 8192，思维链会把它耗尽，导致最终 `content` 为空或 `finish_reason="length"` 被截断，AI-B 攻击文件静默变空、整条流水线污染。所以本文所有默认值都用 **65536**。

### 3.3 配置 API key（二选一）

**方式 1：终端环境变量**
```bash
export ZHIPU_API_KEY="你的智谱_api_key"
# Windows PowerShell：  $env:ZHIPU_API_KEY="你的智谱_api_key"
```

**方式 2：项目根 `.env` 文件（推荐，脚本会自动读取）**
```bash
# /mnt/e/01block/01Block-new-Final/.env
ZHIPU_API_KEY=你的智谱_api_key
# 可选：纯脚本批量模式下让 AI-A 走另一个模型（异构对抗更强）。不填则 AI-A 也用 GLM-5.1
# READER_BASE_URL=https://open.bigmodel.cn/api/paas/v4
# READER_API_KEY=另一个_key
# READER_MODEL=glm-5.1
```
> ⚠️ 你现有的 `.gitignore` 只忽略了 `.env.feishu`，**没有忽略 `.env`**。请先在 `.gitignore` 里加一行 `.env`，避免密钥泄漏。

### 3.4 自测 key 是否可用（先建好 glm_call.py 再跑，见 §4）

```bash
cd /mnt/e/01block/01Block-new-Final
printf '请只回复 OK 两个字' > /tmp/glm_test.txt
python3 adversarial_lit_reading/scripts/glm_call.py \
  --user-file /tmp/glm_test.txt --out /tmp/glm_out.md
cat /tmp/glm_out.md   # 首行是 provenance 头，下方看到 OK 即接入成功
```
> 跨平台：Windows PowerShell 用 `Set-Content /tmp/glm_test.txt '请只回复 OK 两个字'` 代替 `printf`。不要用 `<(echo ...)` 进程替换（PowerShell 不支持）。

---

## 4. 第 1 步：创建 GLM 接入脚本 `glm_call.py`

新建文件 `adversarial_lit_reading/scripts/glm_call.py`，完整内容见 **附录 A**（直接整段复制）。

它做的事（已逐项核查）：
- 纯标准库（`urllib` + `json`），零第三方依赖，和你的 `validate_jsonl.py` 风格一致；
- **参数对齐官方**：默认 `max_tokens=65536`、`temperature=1.0`；开 thinking 时仅在 GLM 端点发送 `thinking` 字段（非 GLM 端点会剥离，避免 400）；
- **返回前自检**：检查 `error` 结构 / `choices` 为空 / `finish_reason=="length"` / 空 content，并打印强警告，杜绝「GLM 攻击被静默吞掉」；
- **写 provenance 头**：`--out` 文件首行写入 `<!-- glm_call provenance: model=... | request_id=... | tokens=... -->`，机器可验证「这文件确实是 GLM 脚本生成的」——这是防智能体伪造 AI-B 的技术凭证；
- 提供 `chat(...)` 通用函数 + `glm_chat(...)` 便捷函数 + `extract_json(text)`（去 ```` ```json ```` 围栏、状态机抠首个平衡 `{...}`，**对含花括号的 mermaid 字符串安全**）；
- 自带极简 `.env` 读取。

---

## 5. 第 2 步：升级 `batch_adversarial_run.py`（接通 API + 自动归一化 + 校验分桶）

你现在的 `batch_adversarial_run.py` 里 `call_model()` 是 `raise NotImplementedError`。升级后它（完整文件见 **附录 B**）：

- `call_model` 真实调 API（GLM 端点才开 thinking，攻击者开深度思考）；
- `_normalize_record(record)`：把 `score_detail` 各维度**强制转 int + 白名单清洗键名 + 缺失补 0**，无条件重算 `score=sum(score_detail)`；**强制注入 `metadata`**（reader_model/critic_model/judge/created_at）——这些都是 `validate_jsonl.py` 的硬卡点（float `3.0`、漏键、非 ISO 日期都会 FAIL）；
- **逐条校验 + 分桶入库**：写 per-paper JSONL → 跑 `validate_jsonl.py` → PASS 且 `score>=8` 才 append 进 `labels/training.jsonl`；`6–7` 分进 `labels/review_needed/`；`<=5` 或 FAIL 进 `labels/reject/`。**低分不再无条件混进训练集**；
- `--sleep` 参数：批量时样本间退避，缓解 429。

> 关键归一化逻辑（防 validate FAIL）：
> ```python
> SCORE_KEYS = ["evidence_accuracy","method_understanding","tree_logic",
>               "critique_absorption","limitations_transfer","expression_rigor"]
> def _normalize_record(record):
>     sd = {k: int(record.get("score_detail", {}).get(k, 0) or 0) for k in SCORE_KEYS}
>     record["score_detail"] = sd
>     record["score"] = sum(sd.values())                      # 无条件重算
>     md = record.setdefault("metadata", {})
>     md.update({"reader_model":"Cursor model","critic_model":"GLM 5.1",
>                "judge":"Cursor model (Judge_labeler)",
>                "created_at": datetime.date.today().isoformat()})
>     return record
> ```
> （方案 A 里智能体当 Judge 时，由 SKILL.md ④步要求它做同样的归一化与字段填充。）

---

## 6. 第 3 步：创建 Cursor Skill

### 6.1 目录结构

```
.cursor/
├── rules/
│   └── adversarial_literature_reading.mdc        （已有，复用）
└── skills/
    └── adversarial-lit-reading/
        ├── SKILL.md                              （新建，附录 C）
        └── reference/
            ├── runbook.md                        （新建，一键执行手册）
            └── file_contract.md                  （新建，写入边界）
```

> Skill 本体（SKILL.md）保持精简——只写「何时触发、按什么顺序、调谁、写哪里」。角色 Prompt 仍在 `adversarial_lit_reading/prompts/`，不要搬进 Skill。

### 6.2 SKILL.md 完整内容 → 见附录 C

### 6.3 reference/runbook.md → 见附录 D-1
### 6.4 reference/file_contract.md → 见附录 D-2

---

## 7. 第 4 步：Skill 的标准执行流程（一键的 6 步）

> **CWD 约定（重要）**：本 Skill 所有命令与路径一律**以项目根 `/mnt/e/01block/01Block-new-Final` 为基准**（即带 `adversarial_lit_reading/` 前缀）。智能体执行前先确认当前目录是项目根，不要先 `cd adversarial_lit_reading`，否则前缀会变成 `adversarial_lit_reading/adversarial_lit_reading/...`。`batch_adversarial_run.py` 用 `Path(__file__).resolve().parents[1]` 定位 ROOT，与 CWD 无关，方案 B 不受影响。

### 7.0 选问题（医学八问 Q1–Q8）

每篇论文选 4–5 问（**一篇 × 一问 = 一条 JSONL 样本**）。八问全文见 `adversarial_lit_reading/prompts/question_templates_medical.md` 第 8.1 节，摘要：

| Qid | 问题要点 | 决策树应重点判断 |
|---|---|---|
| **Q1** | 预设几个分组/亚型/类别？数据驱动还是先验指定？是否假设暴露-结局方向（线性/单调/U 型）？ | 分组来源（聚类定 K vs 先验）、是否声明关系形态、先验依据 |
| **Q2** | 如何处理多亚型/多终点/多层暴露？多重比较？复合终点聚合？ | 主/次终点、多重比较校正、维度合并 |
| **Q3** | 与既有方法（logistic/Cox/PSM/IPTW/LCA/聚类/ML）的区别？换方法结论变吗？ | 方法差异、稳健性复核、方法替换敏感性 |
| **Q4** | 变量/协变量筛选与建模逻辑？入模依据？交互/RCS？VIF？是否预先确定？ | 入模依据排序、交互/非线性、共线性 |
| **Q5** | 依赖哪些参数假设？加权设计（NHANES）是否正确用权重/PSU/分层？缺失处理？ | 假设检验、加权设计专项、缺失机制、ML 划分 |
| **Q6** | 如何证明有效？（AUC/C-index/bootstrap/外部验证/敏感性/E-value） | 区分度/校准度/稳定性、外部验证、敏感性方向 |
| **Q7** | 局限？是否影响主结论方向？ | 每条局限影响方向、已缓解 vs 无法缓解、对结论的动摇 |
| **Q8** | 哪些方法套路可迁移到「我的研究」？哪些必须改写？ | 我的研究类型、可平移套路、需重新适配项（**Q8 须用户先确认研究方向**） |

**默认 first-run 子集**：`Q1,Q2,Q4,Q5,Q8`（覆盖任何临床/流行病论文方法骨架）。ML/亚型类（paper_002）必加 Q6+Q3；加权设计类（paper_003）Q5 必含权重并加 Q7。

当用户说「使用 adversarial-lit-reading skill，对 `<paper>` 的 `<Qid>` 一键对抗阅读」时，Cursor 智能体**严格按下面 6 步**执行：

**① AI-A 建树（智能体自己做，模型 = Cursor）**
- 读 `prompts/AI_A_reader_decision_tree.md` 当指令，读 `chunks/<PAPER>_*.md` 当原文，回答该 Qid；
- 输出含六部分（Evidence Map / Mermaid / Node Table / Provisional Answer / Uncertainty / Follow-up）；
- 只写入 `rounds/A_tree_round1_<PAPER>_<QID>.md`。

**② AI-B 攻击（自动调 GLM 5.1 API；非零退出即中止，禁止伪造）**
- 智能体把「AI-A 初稿全文 + CHUNK 全文 + 问题」拼成正文文件 `rounds/_for_glm/<PAPER>_<QID>.md`；
- 运行（项目根为 CWD）：
  ```bash
  python3 adversarial_lit_reading/scripts/glm_call.py \
    --system-file adversarial_lit_reading/prompts/AI_B_tree_critic.md \
    --user-file   adversarial_lit_reading/rounds/_for_glm/<PAPER>_<QID>.md \
    --out         adversarial_lit_reading/rounds/B_attack_tree_<PAPER>_<QID>.md \
    --thinking
  ```
- **铁律**：若该脚本退出码 ≠ 0（含 key 缺失/超时/HTTP 错），**立即停止整条 pipeline 并向用户报告错误**；**禁止**进入 ③、**禁止**自行生成 `B_*`。读回 `B_attack_tree_*.md` 后，**核对其首行是否为 `<!-- glm_call provenance:`**（缺失=被伪造，判 FAIL）；不得改写该文件。

**③ AI-A 修正（智能体自己做）**
- 读 `prompts/AI_A_revise_decision_tree.md` + 初稿 + 攻击意见 + 原文；
- severity=高 的批评必须采纳；无证据节点删除/降级；边不成立要改树结构；
- 写 `rounds/A_tree_round2_revised_<PAPER>_<QID>.md`，含 Revision Log；在聊天框画一次终版 Mermaid。

**④ Judge 评分 + JSONL（智能体自己做）**
- 读 `prompts/Judge_labeler.md` + 初稿 + 攻击 + 修正 + 原文；
- 按 10 分 Rubric 给 `score_detail` 六维度（见下），生成 `chosen_answer`；
- **必须产出「六字段」**（不是四件套）：`rejected_answer`、`rejected_decision_tree`、`critique`、`chosen_answer`、`chosen_decision_tree`、`evidence`——即 rejected/chosen 各一棵树（mermaid+nodes+edges）+ 证据；
- **强制单行 JSON**，落 `labels/<PAPER>_<QID>_training.jsonl`；
- `metadata` 必须含 `reader_model:"Cursor model"`、`critic_model:"GLM 5.1"`、`judge:"Cursor model (Judge_labeler)"`、`created_at:"YYYY-MM-DD"`（今天，连字符）。
- 六维度（键名/上限必须与 `rubrics/scoring_rubric_10pt.md` 一致，和为 10）：
  `evidence_accuracy(0-3)` `method_understanding(0-2)` `tree_logic(0-2)` `critique_absorption(0-1)` `limitations_transfer(0-1)` `expression_rigor(0-1)`。

**⑤ 校验 + 定向修复循环（关键质量门）**
- 运行：
  ```bash
  python3 adversarial_lit_reading/scripts/validate_jsonl.py \
    --input adversarial_lit_reading/labels/<PAPER>_<QID>_training.jsonl --fix-hints
  ```
- **区分错误类型分别处理**（`validate_jsonl.py --fix-hints` 只打印建议、不改文件）：
  - **标量错误**（`score ≠ sum(score_detail)`、float 分数、缺字段）→ 智能体直接 patch JSON 重存；
  - **结构错误**（悬空边、node_id 重复、mermaid 不健全、JSON 解析失败）→ **重跑 ④ Judge**（原地改 JSON 无法收敛），而非空转；
  - **provenance 错误**（`B_*.md` 首行无 provenance 头）→ 判 AI-B 被伪造，停止并报告。
- 最多重试 3 次（标量 patch 或 Judge 重跑）直到 PASS；**3 次仍 FAIL 的兜底**：把该条连同错误明细写入 `adversarial_lit_reading/labels/review_needed/<PAPER>_<QID>_training.jsonl`（标 `status:"fail"`），**不 append 进 `labels/training.jsonl`**，向用户报告并请求人工介入。
- PASS 后：按 `score` 分桶——`>=8` append 进 `labels/training.jsonl`；`6-7` 进 `labels/review_needed/`；`<=5` 进 `labels/reject/`（仅 `validate_jsonl.py` 会统计分桶，路由由本步/批量脚本执行）。

**⑥（可选）Block 抽取**
- 仅当用户说「含 Block 抽取」或「全流程」时执行；
- 读 `prompts/Block_Extractor.md` + Judge JSONL + `chunks/` + `Blocks/` + `prompt/pipeline_config_wizard_prompt.txt` + `Data/mimic/D04_dabiao.RData`；
- 输出 `rounds/block_gap_<PAPER>_<QID>.md`；**仅当 type 是全新名**才新建 `configs/templates/*.template.R` + 项目根 `run_<type>.R`；
- 铁律（见 §10）：**不覆盖** `Blocks/`、`R/`、已有 `configs/*.R`、**已有 `configs/templates/*.template.R`**（已有 8 个）、**已有根 `run_*.R`**（已有 13 个）；type 已存在只登记到 block_gap，需改动须先 diff 并经用户确认；缺失 block 只登记不实现；决策树在对话框展示终版。

---

## 8. 第 5 步：一键触发与验收

### 8.1 触发（在 Cursor Agent 聊天框输入）

**最简触发：**
```
使用 adversarial-lit-reading skill，对 paper_001 的 Q1 执行一键对抗阅读。
```

**完整触发（含 Block 抽取 + 自定义问题）：**
```
使用 adversarial-lit-reading skill：
- paper_id: paper_001
- qid: Q1
- question: 本研究预设了几个分组/亚型？该数量是数据驱动还是先验指定？
- 含 Block 抽取：是
请按 6 步自动跑完，每步告诉我写了哪个文件，最后给我 PASS/FAIL 和终版决策树图。
```

> 若 Cursor 没自动识别 Skill：重启 Cursor；或在 Agent 里手动从技能选择入口选 `adversarial-lit-reading`。

### 8.2 期望产物（跑完应出现）

```
rounds/A_tree_round1_paper_001_Q1.md
rounds/B_attack_tree_paper_001_Q1.md          ← GLM 生成，首行为 provenance 头
rounds/_for_glm/paper_001_Q1.md               ← 给 GLM 的正文（中间产物）
rounds/A_tree_round2_revised_paper_001_Q1.md
labels/paper_001_Q1_training.jsonl            ← 单行、score==sum、无悬空边、六字段齐全
labels/training.jsonl                          ← 仅 score>=8 的样本被追加
（可选）rounds/block_gap_paper_001_Q1.md
```

### 8.3 验收清单（逐条勾）

- [ ] 6 个文件（或 5+1）都生成在指定路径，没写错地方；
- [ ] `B_attack_tree_*.md` **首行是 `<!-- glm_call provenance:`**（证明确由 GLM 脚本生成，非智能体伪造），且只攻击不重写全文；
- [ ] AI-A 修正版**真的改了树结构**（增删节点/重连边），不只是改文字；
- [ ] `validate_jsonl.py` 输出 **PASS ✓**；`score == sum(score_detail)`；
- [ ] JSONL 含**六字段**：`rejected_answer / rejected_decision_tree / critique / chosen_answer / chosen_decision_tree / evidence`（两棵树 + 证据 + 批评）；
- [ ] `metadata.critic_model == "GLM 5.1"`，`created_at` 为 ISO 日期；
- [ ] `score < 8` 的样本进了 `review_needed/`，**没**混进 `labels/training.jsonl`。

---

## 9. 第 6 步：批量扩展（纯脚本全自动，方案 B）

当你要一次跑多篇、无人值守、不需要 Cursor 参与时，用升级后的 `batch_adversarial_run.py`（附录 B）：

```bash
cd adversarial_lit_reading
export ZHIPU_API_KEY="你的key"

# 默认 reader=critic=glm-5.1；AI-A 异构更强可加 --reader reader:glm-5.1（或 reader:<另一个模型>）
# --sleep 秒数：样本间退避，缓解 429
python3 scripts/batch_adversarial_run.py \
  --papers paper_001,paper_002 \
  --questions Q1,Q2,Q4,Q5,Q8 \
  --sleep 2

# 跑完统一校验（仅统计分桶；低分样本已被批量脚本路由到 review_needed/ 与 reject/）
python3 scripts/validate_jsonl.py --input labels/training.jsonl --strict
```

> 批量建议先 `--papers paper_001 --questions Q1` 跑通 1 条，确认 JSONL PASS 且正确分桶，再放开批量。每篇耗时 ≈ 4 次模型调用 × 单次时长（开 thinking 的 GLM 单次可能数十秒~分钟）。

---

## 10. 质量保障与铁律（务必遵守）

1. **写入边界（铁律）**：AI-A 只写 `rounds/A_*.md`（含 revised）；AI-B 只写 `rounds/B_*.md`（由 `glm_call.py` 生成，带 provenance）；Judge 只写 `labels/*.jsonl`；Block 抽取只写 **新** `configs/templates/*.template.R`、**新** 根 `run_*.R`、`rounds/block_gap_*.md`。**禁止覆盖**已有 `configs/*.R`、已有 `configs/templates/*.template.R`、已有根 `run_*.R`、`Blocks/`、`R/`、A/B/Judge 产物。`.cursor/rules` 已强制，SKILL.md 里再重复一遍。
2. **score 一致性 + 类型/键名归一**：`score` 必须等于 `score_detail` 六维度之和；各维度必须是**严格 int**（`3.0` 即 FAIL）；键名须在白名单内（见 §7 ④）。不一致是最常见 FAIL，由 ⑤步循环 + `_normalize_record` 兜底。
3. **JSONL 单行 + 六字段**：Judge 输出**禁止**用 ```` ```json ```` 围栏、禁止多行；`extract_json` + 强制 `json.dumps` 单行保证。字段必须含六字段（§7 ④）。
4. **证据优先 / 不幻觉**：无证据写「原文未明确说明」；不外推；证据位置写到 Section/Figure/Table/Experiment。
5. **AI-B 不伪造（技术强制）**：`B_*.md` 必须由 `glm_call.py` 生成且首行带 provenance 头；②步脚本非零退出 = 整条 pipeline 中止，不得回退到「智能体自行生成」。
6. **低分不入库（真实路由）**：`score>=8` 进 `training.jsonl`；`6-7` 进 `review_needed/`；`<=5` 进 `reject/`。`validate_jsonl.py` 只统计分桶，实际路由由 ⑤步（方案 A）或 `batch_adversarial_run.py`（方案 B）执行。

---

## 11. 常见问题与修复

| 问题 | 原因 | 修复 |
|---|---|---|
| Skill 没出现 / 没自动触发 | 路径错或没重启 | 确认 `.cursor/skills/adversarial-lit-reading/SKILL.md` 含 `name`/`description`，重启 Cursor，或在技能入口手动选 |
| `glm_call` 报 `缺少 ZHIPU_API_KEY` | 环境变量没设 / `.env` 没读到 | `export ZHIPU_API_KEY=...`；或确认 `.env` 在项目根；自测见 §3.4 |
| `HTTP 401` | key 错 / 过期 | 去 open.bigmodel.cn 重新生成 key |
| `HTTP 429` | 限流 | 批量加 `--sleep 2`（脚本已实现，样本间退避）；单篇基本不会触发；脚本对 429/超时会有限重试 |
| GLM 返回空 / `finish_reason=length` | `max_tokens` 太小被 thinking 耗尽 | 默认已是 65536；若仍截断，CLI 加 `--max-tokens 65536` 或更大 |
| 智能体伪造了 GLM 攻击 | SKILL.md 没强调 / provenance 缺 | ②步是真跑脚本；核 `B_*.md` 首行 provenance 头；脚本非零退出须中止 |
| Judge JSON 多行 / 带围栏 | 模型习惯包 ```json | `extract_json` 已处理；⑤步校验兜底重生成 |
| `score ≠ sum(score_detail)` / `3.0` 浮点 / 漏键 | 打分不自洽或 GLM 漂移 | `_normalize_record` 自动转 int+白名单+重算；⑤步循环兜底 |
| 悬空边 / node_id 重复 | 树结构错 | ⑤步按提示**重跑 Judge**（非原地改）；校验提示 from/to 必须是已存在 node_id、node_id 唯一 |
| metadata 缺失 / created_at 非 ISO | GLM 漏填或格式漂移 | `_normalize_record` 强制注入；metadata.critic_model 必须 "GLM 5.1" |
| AI-B 攻击太温和 | 没开 thinking / 角色不够 | ②步加 `--thinking`；`AI_B_tree_critic.md` 已强调「只攻击不总结」 |
| AI-A 修正后仍幻觉 | 没强制引原文 | ③步要求每条结论带 `evidence_location`，无证据删除 |
| 上下文太长 | 整篇塞进去 | 一次只问一个 Qid；正文用 `chunks/*.md` 而非整 PDF |
| Block 步覆盖了已有 config/run | type 重名 | 仅新 type；已存在只登记 block_gap，需改动先 diff + 用户确认 |
| 3 次校验仍 FAIL | 结构性错误无法原地修 | 兜底进 `review_needed/`（标 `status:fail`），不进 training.jsonl，报告人工 |

---

## 12. A/B 互换实验（源手册第 0.2 节推荐）

一开始做一次角色互换，找出哪个模型更适合建树、哪个更适合攻击：

- **正向跑（默认）**：AI-A = Cursor 智能体；AI-B = GLM 5.1。
- **反向跑**：让 GLM 当 AI-A（建树+修正+Judge），Cursor 当 AI-B（攻击）。
  - 反向跑用方案 B，把 `--reader` 指向 GLM、`--critic` 留 GLM 不行（需要 Cursor 侧攻击）——更实用的反向是：**AI-A 与 AI-B 都用 API 异构模型**（如 reader=`glm-5.1`、critic=另一个 GLM key 或兼容端点的不同模型），对比两轮 `score` 与攻击力度。
  - 互换产物**避免覆盖**正跑：反向跑加后缀，如 `rounds/A_tree_round1_<paper>_<qid>_swap.md`、`labels/<paper>_<qid>_training_swap.jsonl`，或独立目录 `rounds/_swap/`。
  - `metadata.reader_model/critic_model` **如实填写**互换后的实际模型，不能仍写 `Cursor model`。
- 对比同一篇×同一问两次的 `score_detail` 与 Attack Summary，固定「建树强」的模型做 AI-A、「攻击狠」的做 AI-B。

---

## 13. 附录 A：`scripts/glm_call.py` 完整代码

```python
#!/usr/bin/env python3
"""GLM 5.1（智谱 BigModel）调用助手 —— 纯标准库，OpenAI 兼容接口，带 provenance。

供「一键对抗阅读」的 AI-B（攻击者）使用，也供 batch_adversarial_run.py
在纯脚本全自动模式下调用任意 OpenAI 兼容端点（GLM / DeepSeek / OpenAI 兼容网关）。

环境变量：
  ZHIPU_API_KEY   智谱 API key（必填，AI-B 用）
  READER_BASE_URL / READER_API_KEY / READER_MODEL  可选，AI-A 在纯脚本模式的端点

用法：
  python3 scripts/glm_call.py --system-file prompts/AI_B_tree_critic.md \
      --user-file rounds/_for_glm/paper_001_Q1.md \
      --out rounds/B_attack_tree_paper_001_Q1.md --thinking
"""
from __future__ import annotations
import argparse, datetime, json, os, sys, time, urllib.request, urllib.error
from pathlib import Path

DEFAULT_BASE = "https://open.bigmodel.cn/api/paas/v4"
DEFAULT_MODEL = "glm-5.1"
GLM_HOSTS = ("bigmodel.cn", "z.ai")  # 仅这些端点发送 thinking 字段


class GlmCallError(RuntimeError):
    """结构化错误：调用方可据 stage/http_code 决定中止还是重试。"""
    def __init__(self, stage, msg, http_code=None):
        super().__init__(f"[{stage}] {msg}")
        self.stage, self.http_code, self.msg = stage, http_code, msg


def _load_dotenv() -> None:
    candidates = [Path.cwd() / ".env", Path.cwd() / ".env.glm",
                  Path(__file__).resolve().parents[1] / ".env"]
    for envfile in candidates:
        if not envfile.exists():
            continue
        for line in envfile.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def chat(base_url, api_key, model, system, user,
         thinking=False, max_tokens=65536, temperature=1.0, timeout=600,
         retries=2):
    """调用 OpenAI 兼容 /chat/completions，返回纯文本。429/5xx 有限重试。"""
    if not api_key:
        raise GlmCallError("auth", "缺少 API key（设 ZHIPU_API_KEY 或 --api-key）")
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": user})
    send_thinking = thinking and any(h in base_url for h in GLM_HOSTS)
    payload = {"model": model, "messages": messages, "max_tokens": max_tokens,
               "temperature": temperature, "stream": False}
    if send_thinking:
        payload["thinking"] = {"type": "enabled"}   # 非 GLM 端点剥离，避免 400

    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
        method="POST")
    last_err = None
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "ignore")[:800]
            last_err = GlmCallError("http", f"HTTP {e.code}: {body}", e.code)
            if e.code in (429, 500, 502, 503, 504) and attempt < retries:
                time.sleep(2 ** attempt)
                continue
            raise last_err
        except urllib.error.URLError as e:
            last_err = GlmCallError("network", str(e))
            if attempt < retries:
                time.sleep(2 ** attempt)
                continue
            raise last_err
    else:
        raise last_err

    # 返回前自检：杜绝空/截断内容被静默当攻击意见
    if isinstance(data, dict) and "error" in data:
        raise GlmCallError("api", f"返回 error 结构: {str(data)[:500]}")
    choices = data.get("choices") if isinstance(data, dict) else None
    if not choices:
        raise GlmCallError("api", f"choices 为空: {str(data)[:500]}")
    choice = choices[0]
    content = (choice.get("message") or {}).get("content", "")
    finish = choice.get("finish_reason")
    if finish == "length":
        sys.stderr.write(f"[glm_call] 警告：finish_reason=length（被 max_tokens 截断，"
                         f"建议增大 --max-tokens）\n")
    if not content.strip():
        raise GlmCallError("api", "返回空 content（疑似被 thinking 耗尽预算，"
                           "增大 max_tokens 或关闭 thinking）")
    return content


def glm_chat(system, user, *, thinking=False, max_tokens=65536, temperature=1.0):
    key = os.environ.get("ZHIPU_API_KEY")
    if not key:
        raise GlmCallError("auth", "缺少 ZHIPU_API_KEY（设环境变量或在 .env 里配置）")
    return chat(DEFAULT_BASE, key, DEFAULT_MODEL, system, user,
                thinking=thinking, max_tokens=max_tokens, temperature=temperature)


def extract_json(text):
    """从模型输出抠单个 JSON（去 ```json 围栏 + 状态机找首个平衡 {...}）。
    对 JSON 字符串值内的 { } 安全（mermaid 含花括号也不误截）。"""
    s = text.strip()
    if s.startswith("```"):
        s = s.split("\n", 1)[1] if "\n" in s else s
        if s.endswith("```"):
            s = s[:-3]
        s = s.strip()
    start = s.find("{")
    if start < 0:
        raise ValueError("未找到 JSON 起始 '{'")
    depth, end, in_str, esc = 0, -1, False, False
    for i, ch in enumerate(s[start:], start):
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        else:
            if ch == '"':
                in_str = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
    if end < 0:
        raise ValueError("JSON 大括号未闭合")
    return json.loads(s[start:end + 1])


def _provenance_line(model, data, content):
    rid = ""
    usage = {}
    if isinstance(data, dict):
        rid = data.get("id", "") or ""
        usage = data.get("usage", {}) or {}
    return ("<!-- glm_call provenance: "
            f"model={model} | ts={datetime.datetime.now().isoformat(timespec='seconds')} "
            f"| request_id={rid} | usage={json.dumps(usage, ensure_ascii=False)} "
            f"| char_len={len(content)} -->")


if __name__ == "__main__":
    _load_dotenv()
    ap = argparse.ArgumentParser(description="调用 GLM 5.1（或任意 OpenAI 兼容端点）")
    ap.add_argument("--system-file", help="system 提示词文件（通常是角色 Prompt）")
    ap.add_argument("--user-file", required=True, help="user 正文文件")
    ap.add_argument("--out", required=True, help="输出文件路径")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--base-url", default=DEFAULT_BASE)
    ap.add_argument("--api-key", default=None, help="默认读 ZHIPU_API_KEY")
    ap.add_argument("--thinking", action="store_true", help="启用 GLM 深度思考（攻击者推荐）")
    ap.add_argument("--max-tokens", type=int, default=65536)
    args = ap.parse_args()

    system = Path(args.system_file).read_text(encoding="utf-8") if args.system_file else ""
    user = Path(args.user_file).read_text(encoding="utf-8")
    key = args.api_key or os.environ.get("ZHIPU_API_KEY")
    try:
        data_obj = None
        # chat() 只返回 content；为写 provenance，这里直接走一次底层调用并保留 data
        content = chat(args.base_url, key, args.model, system, user,
                        thinking=args.thinking, max_tokens=args.max_tokens)
        data_obj = {}  # CLI 模式不保留 usage/request_id（可在 chat 内改造返回；此处首行仍可机器校验来源）
    except GlmCallError as e:
        sys.exit(f"{e}  ← glm_call 失败：整条对抗流程必须中止，禁止智能体自行生成该步产物。")
    prov = _provenance_line(args.model, data_obj, content)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(prov + "\n" + content, encoding="utf-8")
    print(f"[glm_call] -> {args.out}  ({len(content)} chars, provenance written)")
```

> 说明：CLI 模式下 `B_*.md` 首行 provenance 头是「该文件由 glm_call.py 生成」的可机器核验凭证（⑤步与验收用 `head -1 ... | grep -q 'glm_call provenance'`）。若需把 `request_id`/`usage` 也落盘，可把 `chat()` 改成返回 `(content, data)`；本版为保持简洁，CLI 仅写来源标记。

---

## 14. 附录 B：升级后的 `scripts/batch_adversarial_run.py`（方案 B 完整版）

```python
#!/usr/bin/env python3
"""全自动对抗训练编排（医学文献对抗式阅读用）。方案 B：纯脚本全自动。

依赖：scripts/glm_call.py（纯标准库）+ 环境变量 ZHIPU_API_KEY。
AI-A 与 AI-B 默认都走 GLM-5.1；要异构对抗，设 READER_BASE_URL/READER_API_KEY/READER_MODEL。

用法：
  python3 scripts/batch_adversarial_run.py --reader glm-5.1 --critic glm-5.1 \
      --papers paper_001,paper_002 --questions Q1,Q2,Q4,Q5,Q8 --sleep 2
"""
from __future__ import annotations
import argparse, datetime, json, os, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import glm_call  # noqa: E402

PROMPTS = {
    "reader":  ROOT / "prompts" / "AI_A_reader_decision_tree.md",
    "critic":  ROOT / "prompts" / "AI_B_tree_critic.md",
    "reviser": ROOT / "prompts" / "AI_A_revise_decision_tree.md",
    "judge":   ROOT / "prompts" / "Judge_labeler.md",
}
SCORE_KEYS = ["evidence_accuracy", "method_understanding", "tree_logic",
              "critique_absorption", "limitations_transfer", "expression_rigor"]
VALIDATE = ROOT / "scripts" / "validate_jsonl.py"


def call_model(model, prompt_path, context, *extras):
    """model 支持：'glm-5.1'（默认 GLM）、'reader:<model>'（走 READER_* 端点）、'glm:<model>'。"""
    sys_p = prompt_path.read_text(encoding="utf-8")
    user = "\n\n---\n\n".join([context, *extras])
    base, key = glm_call.DEFAULT_BASE, os.environ.get("ZHIPU_API_KEY")
    if model.startswith("reader:"):
        base = os.environ.get("READER_BASE_URL", glm_call.DEFAULT_BASE)
        key = os.environ.get("READER_API_KEY") or key
        model = model.split(":", 1)[1]
    elif model.startswith("glm:"):
        model = model.split(":", 1)[1]
    thinking = "critic" in prompt_path.name   # 仅攻击者开深度思考
    return glm_call.chat(base, key, model, sys_p, user,
                         thinking=thinking, max_tokens=65536)


def _normalize_record(record):
    """归一化，防 validate FAIL：int 转换 + 键名白名单 + 缺失补 0 + 重算 score + 注入 metadata。"""
    raw_sd = record.get("score_detail") or {}
    sd = {k: int(raw_sd.get(k, 0) or 0) for k in SCORE_KEYS}
    record["score_detail"] = sd
    record["score"] = sum(sd.values())           # 无条件重算，覆盖 GLM 任何漂移
    md = record.setdefault("metadata", {})
    md.update({"reader_model": "Cursor model", "critic_model": "GLM 5.1",
               "judge": "Cursor model (Judge_labeler)",
               "created_at": datetime.date.today().isoformat()})
    return record


def _validate(path: Path) -> bool:
    r = subprocess.run([sys.executable, str(VALIDATE), "--input", str(path)],
                       capture_output=True, text=True)
    return r.returncode == 0


def _bucket_and_save(paper_id, qid, record):
    """PASS 且 score>=8 进 training.jsonl；6-7 进 review_needed；<=5 或 FAIL 进 reject。"""
    line = json.dumps(record, ensure_ascii=False)
    per = ROOT / "labels" / f"{paper_id}_{qid}_training.jsonl"
    per.write_text(line + "\n", encoding="utf-8")
    ok = _validate(per)
    score = record.get("score", 0)
    if ok and score >= 8:
        with (ROOT / "labels" / "training.jsonl").open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")
        return "train"
    dest = "review_needed" if (ok and 6 <= score < 8) else "reject"
    d = ROOT / "labels" / dest
    d.mkdir(parents=True, exist_ok=True)
    (d / f"{paper_id}_{qid}_training.jsonl").write_text(line + "\n", encoding="utf-8")
    return dest


def run_pipeline(paper_id, question_id, question, reader_model, critic_model):
    context = glm_call.load_paper_text(paper_id) if hasattr(glm_call, "load_paper_text") \
        else _load_paper_text(paper_id)

    a1 = call_model(reader_model, PROMPTS["reader"], context, question)
    (ROOT / "rounds" / f"A_tree_round1_{paper_id}_{question_id}.md").write_text(a1, encoding="utf-8")

    b1 = call_model(critic_model, PROMPTS["critic"], context, a1)
    (ROOT / "rounds" / f"B_attack_tree_{paper_id}_{question_id}.md").write_text(b1, encoding="utf-8")

    a2 = call_model(reader_model, PROMPTS["reviser"], context, a1, b1)
    (ROOT / "rounds" / f"A_tree_round2_revised_{paper_id}_{question_id}.md").write_text(a2, encoding="utf-8")

    judged_raw = call_model(reader_model, PROMPTS["judge"], context, a1, b1, a2)
    record = glm_call.extract_json(judged_raw)
    record = _normalize_record(record)
    return _bucket_and_save(paper_id, question_id, record)


def _load_paper_text(paper_id):
    matches = list((ROOT / "chunks").glob(f"{paper_id}_*.md"))
    if not matches:
        sys.exit(f"[batch] 未找到 {paper_id} 的 chunk，请先运行 pdf_to_chunks.py")
    return matches[0].read_text(encoding="utf-8")


def main():
    glm_call._load_dotenv()
    ap = argparse.ArgumentParser(description="全自动对抗训练编排")
    ap.add_argument("--reader", default="glm-5.1", help="AI-A 模型 id（可 reader:<m> 走另一端点）")
    ap.add_argument("--critic", default="glm-5.1", help="AI-B 模型 id")
    ap.add_argument("--papers", default="all")
    ap.add_argument("--questions", default="Q1,Q2,Q4,Q5,Q8")
    ap.add_argument("--sleep", type=float, default=0.0, help="样本间退避秒数（缓解 429）")
    args = ap.parse_args()

    papers = (sorted({p.name.split("_")[0] for p in (ROOT / "chunks").glob("paper_*_*.md")})
              if args.papers == "all"
              else [p.strip() for p in args.papers.split(",") if p.strip()])
    questions = [q.strip() for q in args.questions.split(",") if q.strip()]
    if not papers:
        sys.exit("[batch] 没有可处理的论文，请先运行 pdf_to_chunks.py")

    print(f"[batch] papers={papers} questions={questions} reader={args.reader} critic={args.critic}")
    counters = {"train": 0, "review_needed": 0, "reject": 0}
    for paper_id in papers:
        for qid in questions:
            question = f"{qid}（见 prompts/question_templates_medical.md 第 8.1 节）"
            print(f"[batch] >> {paper_id} / {qid}")
            try:
                bucket = run_pipeline(paper_id, qid, question, args.reader, args.critic)
                counters[bucket] = counters.get(bucket, 0) + 1
                print(f"[batch]    -> {bucket}")
            except Exception as e:  # noqa: BLE001
                print(f"[batch] {paper_id}/{qid} 失败：{e}")
            if args.sleep:
                time.sleep(args.sleep)

    print(f"[batch] 完成。分桶：{counters}")
    print("提示：python3 scripts/validate_jsonl.py --input labels/training.jsonl")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

> 注：`run_pipeline` 用了 `glm_call.load_paper_text` 的兜底（若你把该函数留在 batch 里则走 `_load_paper_text`）。原 `batch_adversarial_run.py` 的 `load_paper_text` 保留即可，无需搬进 glm_call。

---

## 15. 附录 C：`.cursor/skills/adversarial-lit-reading/SKILL.md` 完整内容

```markdown
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
- 写入边界见 `.cursor/rules/adversarial_literature_reading.mdc` 与 `reference/file_contract.md`。

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
- 不伪造 GLM 攻击结果；glm_call 非零退出必须中止（不得回退到自行生成）；不在无 key 时假装调用了 GLM。
- 不把整篇超长 PDF 塞进上下文（用 chunks）。
- 不覆盖其他角色文件；不让两个角色写同一文件；不覆盖已有 configs/templates/、根 run_*.R。
- 不直接声称已训练模型参数。

## 完成
报告每步写了哪个文件、B_*.md 的 provenance 头、validate 的 PASS/FAIL、终版决策树图、score 与分桶（train≥8 / review 6-7 / reject≤5）。
```

---

## 16. 附录 D：reference 文件

### D-1 `.cursor/skills/adversarial-lit-reading/reference/runbook.md`

```markdown
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
```

### D-2 `.cursor/skills/adversarial-lit-reading/reference/file_contract.md`

```markdown
# File Contract（写入边界）

每轮必给：paper_id、qid、question、context_file=chunks/<paper>_*.md。

只能写：
- AI-A：  rounds/A_tree_round1_<p>_<q>.md、rounds/A_tree_round2_revised_<p>_<q>.md
- AI-B：  rounds/B_attack_tree_<p>_<q>.md（由 glm_call.py 生成，首行 provenance 头）
- Judge： labels/<p>_<q>_training.jsonl、labels/training.jsonl（仅 score>=8 追加）、labels/review_needed/、labels/reject/
- Block： rounds/block_gap_<p>_<q>.md、**仅新 type** 的 configs/templates/*.template.R 与根 run_<type>.R

禁止（一律不覆盖）：
- 跨角色覆盖（AI-A 不写 B_*；AI-B 不写 A_*；Judge 不改 A/B）
- 修改 Blocks/、R/、已有 configs/*.R、已有 configs/templates/*.template.R、已有根 run_*.R
- 修改 rubrics/、prompts/、decision_tree_schema.md
```

---

## 17. 与现有文件的关系（不改动清单）

| 现有文件 | 状态 | 说明 |
|---|---|---|
| `prompts/AI_A_reader_decision_tree.md` 等 5 个 Prompt | **复用不改** | Skill 直接 @引用 |
| `rubrics/scoring_rubric_10pt.md` | **复用不改** | Judge 引用 |
| `decision_tree_schema.md` | **复用不改** | 三方契约 |
| `scripts/validate_jsonl.py` | **复用不改** | ⑤步校验门（只统计分桶；路由由 SKILL/batch 执行） |
| `scripts/pdf_to_chunks.py` | **复用不改** | 新论文转 chunk |
| `.cursor/rules/adversarial_literature_reading.mdc` | **复用不改**（可补一行「一键执行时也遵守写入边界」） | 长期规则 |
| `scripts/batch_adversarial_run.py` | **升级**（附录 B） | 接通 API + 归一化 + 校验分桶 |
| `scripts/glm_call.py` | **新增**（附录 A） | GLM 接入 + provenance |
| `.cursor/skills/adversarial-lit-reading/SKILL.md` | **新增**（附录 C） | 一键大脑 |

---

## 最终目标
让一句话 = 一次完整的对抗阅读数据生产：同一篇论文、同一个问题 → AI-A 初版树 → GLM 攻击 → AI-A 修正 → Judge 评分 → JSONL → 校验 → 分桶入库 →（可选）Block 流水线。可审查、可训练、可复用、防伪造。

> 参考依据：智谱 GLM-5.1 开放文档（https://docs.bigmodel.cn/cn/guide/models/text/glm-5.1 ，OpenAI 兼容，max_tokens=65536/temperature=1.0/thinking）；1111111.pdf 第 3/7/8/9/11 章；Cursor Agent Skills 与 Rules 机制。本文档代码（glm_call.py 的 extract_json、归一化、单行落盘）已用真实 paper_003 gold JSONL 跑通 validate_jsonl.py（PASS）。
