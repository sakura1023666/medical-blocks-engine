<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-09-30T11:25:52 | request_id=msg_6446b260-29d5-411c-88a4-d6c4e60de939 | usage={"input_tokens": 6738, "output_tokens": 2500, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=5150 -->
# AI-B Tree Attack

**paper_id:** paper_022
**question_id:** Q5
**review_target:** @rounds/A_tree_round1_paper_022_Q5.md
**source_file:** adversarial_lit_reading/chunks/paper_022_2026_wang_ckm_cum_egdr_stroke.md

---

## 1. Attack Summary

**总体判断：部分可信（需要中等程度修改）**

**主要问题：**

1. **N1 存在关键误读**：AI-A 声称 "logistic 稀有事件近似 HR"，但摘要中报告的是 **OR**（odds ratio），并非 HR。原文明确报告 "OR 0.43, 95% CI: 0.31–0.58" 等，AI-A 将 OR 误传为近似 HR 的假设，混淆了效应量表述。原文通篇使用 logistic 回归，报告 OR 是常规做法，并不等同于 "稀有事件近似 HR" 的假设。
2. **N4 过度推断**：AI-A 声称 "非复杂抽样加权设计"，但原文明确说明 CHARLS "utilised a multistage, stratified sampling approach"。多阶段分层抽样是复杂抽样设计的一种，需要加权处理。AI-A 将 "未明确报告加权" 说成 "非加权设计"，属于偷换概念。
3. **N6 无依据-证据层级混乱**：AI-A 声称 "Cox PH 等假设检验原文未详述"，但原文研究方法为 logistic 回归和 RCS，并未提及 Cox 模型或 PH 假设检验。这是对方法的误解，将不相关的内容作为 limitation。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A1 | N1 | "logistic稀有事件近似HR" | 原文报告的是 OR（odds ratio），并非 HR。logistic 回归直接报告 OR，不需 "稀有事件近似" 假设来转换为 HR。这是概念混淆。 | 摘要明确 "OR 0.43, 95% CI: 0.31–0.58"；无 HR 报告 | 改为 "logistic 回归报告 OR；未提及 Cox 模型或 PH 假设" | **高** |
| A2 | N2 | "k-means假设球状簇/距离；种子未说明" | 原文未提及种子问题，AI-A 推断合理但需标注为推断；更重要的是，原文已说明 elbow 方法及 k=4 的选择过程，AI-A 未充分展示原文已报告的细节。 | Methods 明确 "elbow method...clear elbow was observed at k=4" | 补充原文已提供 elbow 细节的说明；种子问题标注为 "原文未报告" | 低 |
| A3 | N4 | "非复杂抽样加权设计" | 原文明确说明 CHARLS "utilised a multistage, stratified sampling approach"，属于复杂抽样设计。AI-A 将 "原文未明确报告加权处理方法" 等同为 "非加权设计"，属于过度推断/偷换概念。 | Methods: "utilised a multistage, stratified sampling approach" | 改为 "CHARLS 采用多阶段分层抽样；原文未明确报告是否使用 survey weights" | **高** |
| A4 | N6 | "Cox PH等假设检验原文未详述" | 原文未使用 Cox 模型，"PH 假设检验" 不适用。这是对方法的不当预设。RCS 的线性检验（P for nonlinearity=0.259）原文已有报告，而非 "未详述" | 摘要明确 RCS "P for nonlinearity = 0.259"；全文使用 logistic 回归 | 删除 N6 或改为 "logistic 回归的模型拟合诊断（如 Hosmer-Lemeshow）原文未报告" | **高** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E1 | N0→N1 | N1 本身存在概念错误（OR vs HR），该边传导了错误信息 | 修正 N1 后，N0→N1 可保留但需修正节点内容 | **高** |
| E2 | N1→\|supported_by\|E1 | E1 概括为 "logistic；稀有事件近似HR"，但原文无 "稀有事件近似" 的陈述，证据概括不准确 | E1 改为 "logistic 回归报告 OR；事件数 336/5248≈6.4%" | **高** |
| E3 | N2→\|limitation\|N6 | 从 k-means 方法跳跃到 "PH 假设检验未详述"，两个概念无逻辑关联（k-means 不涉及 PH 假设） | 删除该边；如需 limitation，应连接到 k-means 自身的可复现性问题（如种子） | **中** |
| E4 | N5→\|because\|N3 | 逻辑关系 "because" 不准确：纳排剔除了关键暴露/结局缺失，是**后验样本构成**的问题，与 "主分析采用完整病例" 是不同层面的处理；N3 涉及的是协变量缺失的 MICE 插补，N5 涉及的是纳排标准，两者逻辑链不直 | 改为 N3→\|related_to\|N5 或分别独立说明 | 中 |

---

## 4. Evidence Problems

### 4.1 证据位置错误/偷换概念
- **P1（高）**：E1 声称 "稀有事件近似HR"，但摘要报告的是 OR。偷换概念：OR≠HR，logistic 回归无需 "稀有事件近似" 即可计算 OR。
- **P2（高）**：E4 声称 "CHARLS 非 NHANES 复杂抽样加权"，但原文明确 CHARLS 为 "multistage, stratified sampling"，属于复杂抽样设计。将 "未报告加权" 等同于 "无加权" 是概念误读。

### 4.2 过度引用/超出原文范围
- **P3（中）**：E6 声称 "原文未报告 PH 假设检验"，但原文采用 logistic 回归，不涉及 PH 假设。这是不相关证据的引入。

### 4.3 证据遗漏
- **P4（中）**：原文报告了 RCS 的线性检验结果（P for nonlinearity = 0.259），这是参数假设的一部分（线性 vs 非线性），AI-A 未提及，遗漏了重要证据。

---

## 5. Missing Branches

| missing_branch_id | missing_content | why it matters | suggested addition | severity |
|---|---|---|---|---|
| M1 | **CKM 分期作为调节/分层变量** | 原文按 CKM stages (0–4) 进行分层分析，这是重要的假设检验分支：模型是否在不同 CKM 分期下保持一致？ | 添加 "CKM 分期分层分析 vs 整体分析" 分支 | **中** |
| M2 | **连续型累积 eGDR 的线性假设** | 原文报告 RCS 显示线性关系（P for nonlinearity=0.259），这是重要的参数假设验证结果 | 添加 N8: "RCS 确认累积 eGDR 与卒中风险呈线性关系" | **中** |
| M3 | **结局事件的竞争风险** | 卒中结局存在死亡竞争风险，logistic 回归无法处理竞争风险，这是方法局限 | 添加 "竞争风险模型（如 Fine-Gray）未考虑" 分支 | **中** |
| M4 | **时变协变量/时间更新** | 累积 eGDR 基于 2012 和 2015 两个时间点，但 2015–2018 随访期间协变量是否更新未说明 | 添加 "协变量是否时变更新" 分支 | 低 |
| M5 | **MICE 的插补模型细节** | 原文未说明 MICE 的变量清单、迭代次数、链数，AI-A 也未追问 | 添加 U4: "MICE 插补模型变量清单及迭代参数未报告" | 低 |
| M6 | **模型区分度与校准度** | 原文未报告 AUC/C-statistic 或校准检验，logistic 模型的性能未评估 | 添加 "模型性能评估（区分度/校准度）缺失" 分支 | 低 |

---

## 6. Required Fixes

| fix_id | severity | required action | target | description |
|---|---|---|---|---|
| F1 | **高** | **修改节点 N1 和证据 E1** | N1, E1 | 删除 "稀有事件近似 HR" 表述；改为 "logistic 回归报告 OR（odds ratio），未使用 Cox 模型" |
| F2 | **高** | **修改节点 N4 和证据 E4** | N4, E4 | 改为 "CHARLS 采用多阶段分层抽样（复杂抽样设计）；原文未明确报告 survey weights 的使用" |
| F3 | **高** | **删除节点 N6** | N6 | 原文不涉及 Cox 模型/PH 假设；删除或改为 "logistic 模型拟合诊断（如校准度/区分度）未报告" |
| F4 | **中** | **修正边 E3** | E3 | 删除 N2→N6 的 limitation 边；如需要，添加 k-means 自身的可复现性 limitation |
| F5 | **中** | **添加节点 N8** | 新增 | 添加 "RCS 确认线性关系（P for nonlinearity=0.259）" 节点，并连接到 N1 |
| F6 | **中** | **补充 CKM 分期分支** | 新增 | 添加 "CKM 分期分层分析" 分支，说明模型是否跨分期一致 |
| F7 | **低** | **优化边 E4** | E4 | 将 N5→\|because\|N3 改为 \|related_to\|，明确说明两者是不同层面（纳排 vs 协变量缺失），避免逻辑混乱 |
| F8 | **低** | **将 U1 升级为分支** | U1 | 原文未报告失访率及失访分析，选择偏倚需作为独立分支处理 |

---

## 7. 严重性汇总

| severity | count | items |
|---|---|---|
| **高** | 3 | F1 (N1/E1), F2 (N4/E4), F3 (N6) |
| **中** | 4 | F4, F5, F6, M1/M2/M3 |
| **低** | 4 | F7, F8, M4/M5/M6, A2 |

---

## 8. 结论

AI-A 决策树的核心框架（K-means 方法 + logistic 回归 + 完整病例主分析 + MICE 敏感性）方向正确，但存在**三个高严重度问题**：

1. **OR/HR 概念混淆**（N1/E1）；
2. **对 CHARLS 抽样设计的误读**（N4/E4）；
3. **对不存在的 Cox/PH 假设进行 "未详述" 的批判**（N6/E6）。

这些问题直接影响结论的准确性和可信度，需按上述 F1-F3 优先修改。修改后，该决策树可作为后续方法学讨论的基础。