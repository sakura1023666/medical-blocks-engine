<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-27T15:55:05 | request_id=msg_88a0b7cd-f9bf-410d-93c1-d6499f0f632a | usage={"input_tokens": 42, "output_tokens": 2311, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 13312, "prompt_tokens_details": {"cached_tokens": 13312}} | char_len=4808 -->
# AI-B Tree Attack

paper_id: paper_40295871
question_id: Q5
review_target: @rounds/A_tree_round1_paper_40295871_Q5.md
source_file: @chunks/paper_40295871_pages_1-9.md

## 1. Attack Summary

**总体判断：部分可信 / 需要重大修改**

主要问题：

1. **E1 与 E2 的矛盾被错误识别**：AI-A 将 Fig.1 caption 的「70/30」标为与 Methods 的「80/20」矛盾，但正文 Table 1 明确显示 Training set n=2760 与 Internal validation set n=691，合計 3451（即 80/20），而 Fig.1 写的 70/30 是疏漏。AI-A 的识别方向正确，但未核对 Table 1 数据，未确定哪个数字对应正文实际执行。
2. **E2（Fig.1）被当作「矛盾证据」但未注明该 caption 确为错误**：正文 Table 1 的 n=2760/691 清楚表明是 80/20 划分，AI-A 应将「矛盾」定性为「Fig.1 caption 印刷/编辑错误」，而非简单的「方法冲突」。
3. **关键假设遗漏**：AI-A 未提及 **TOPSIS 权重中六个指标等权假设**（w=1/6），这是融合模型的核心假设之一；也未提及 **0.5 分类阈值假设**。
4. **SMOTE 描述需限定**：原文是「SMOTE applied to training set as per 1:1 rule」，AI-A 说「SMOTE仅训练」正确，但「按1:1规则」这一关键细节被省略，可能影响迁移时对训练集类平衡的理解。
5. **划分比例矛盾需复核**：AI-A 未指出 Fig.1 文字与正文实际数字（Table 1, Methods n=2760/691）的对应关系，导致读者无法判断哪个是「实际执行」，哪个是「文本错误」。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| N1 | E1 | 「80/20划分; SMOTE train; 四种插补比较选优; MinMax」 | 正确但不够精确。未区分「划分比例」在正文与 Fig.1 中的矛盾，且未提及 SMOTE 是「1:1 规则」；也未提及 MinMax 应用到「建模或验证之前」。 | Methods（P8）：80/20；SMOTE 1:1；四种插补比较；min-max normalization before modeling or validation | 补充「1:1」与「min-max 在建模/验证前」；标注划分矛盾来源 | 中 |
| N2 | E2 | 「写70/30——与Methods矛盾」 | 方向正确，但未核实 Table 1 的 n=2760/691（合計3451），也未判断哪个数字是正文实际执行。 | Table 1（P3）：Training set n=2760, Internal validation n=691；Methods（P8）：80/20, n=2760/691 | 应注明「Table 1 与 Methods 一致为 80/20；Fig.1 的 70/30 为文本错误」 | 高 |
| N3 | E3 | 「二分类；无PH/Cox假设（非生存回归主分析）」 | 正确。但遗漏了「0.5 分类阈值」这一二分类假设。 | Outcomes（P8）：28-day all-cause death binary；TOPSIS fusion with 0.5 critical value（P8） | 补充「分类阈值为0.5」；确认无需 PH/Cox 假设 | 中 |
| N4 | Provisional Answer | 「文内划分比例矛盾须披露」 | 正确但未指明矛盾的具体内容与裁决方式。 | Fig.1 vs Table 1 vs Methods | 建议：披露矛盾且注明 Table 1/Methods 的 80/20 是实际执行 | 中 |
| N5 | Uncertainty U1 | 「插补器外推」 | 正确，但可补充：原文仅在训练集上进行插补器选择与比较，未说明插补器是否在验证集/外部集上重新拟合或沿用训练集参数。 | Methods（P8）：选择最佳插补策略，未明确是否 train-only | 可保留，但需注明「原文未明确说明插补器是否 train-only」 | 低 |
| N6 | Uncertainty U2 | 「70/30 vs 80/20」 | 正确，但未说明这是 Fig.1 文字与正文的冲突，而非方法本身的真实冲突。 | Fig.1 caption vs Methods/Table 1 | 修改为「Fig.1 caption 与正文不一致（70/30 vs 80/20），正文（Table 1/Methods）为 80/20」 | 高 |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E1 | E1 → E2 「矛盾」边 | AI-A 将 E1 与 E2 视为「矛盾」，但未说明矛盾的根源与哪一方是正文实际执行。Table 1 明确 n=2760/691 对应 80/20，Fig.1 的 70/30 应归为文本疏漏，而非方法层面的真实冲突。 | 标注「Fig.1 caption 错误」，将 E1 与 E2 的关系从「矛盾」改为「文本不一致」 | 高 |
| E2 | E1 → E3 「二分类」边 | E1 的方法描述与 E3 的「二分类」之间存在隐含的阈值假设（0.5），AI-A 未建立这一边。 | 增加边：E1 中的 TOPSIS 融合 → E3 的 0.5 阈值假设 | 中 |
| E3 | E1 → Provisional Answer 「SMOTE仅训练」边 | 正确，但可补充：SMOTE 是 1:1 规则，且仅应用于训练集，未提及验证集是否重采样。 | 补充「1:1 规则」与「验证集不做过采样」 | 低 |

---

## 4. Evidence Problems

| problem_id | evidence_location | problem_description | severity |
|---|---|---|---|
| P1 | Fig.1 caption（P2） | AI-A 将「70/30」作为与 Methods 的矛盾，但未核实 Table 1（P3）与 Methods（P8）的 n=2760/691 即 80/20。应判定为「Fig.1 文本错误」，而非「方法矛盾」。 | 高 |
| P2 | Methods（P8） | AI-A 未引用「min-max normalization before modeling or validation」这一关键细节，导致迁移时可能遗漏归一化时机。 | 中 |
| P3 | Methods（P8） | AI-A 未注明 SMOTE 的「1:1 规则」；原文为「SMOTE applied to the training set according to the 1:1 rule」。 | 低 |
| P4 | Methods（P8） | AI-A 未引用 TOPSIS 中「六个指标等权（w=1/6）」这一融合模型的权重假设。 | 中 |
| P5 | Methods（P8） | AI-A 未提及「0.5 分类阈值」为 TCF 的决策边界。 | 中 |

---

## 5. Missing Branches

| missing_branch_id | missing_branch_description | original evidence | suggested action | severity |
|---|---|---|---|---|
| M1 | **TOPSIS 等权假设（w=1/6）** | Methods（P8）：「Assign the same weights to the indices, the weight vector is (1/6, 1/6, 1/6, 1/6, 1/6, 1/6)」 | 增加节点：融合阶段的等权假设，用于迁移时说明权重来源 | 中 |
| M2 | **0.5 分类阈值假设** | Methods（P8）：「with 0.5 as the critical value to derive the classification result of TCF」 | 增加节点：分类决策边界为 0.5，迁移时可能需调整 | 中 |
| M3 | **MinMax 归一化时机** | Methods（P8）：「the data needs to be min-max normalized before modeling or validation」 | 补充 E1 细节：归一化在建模/验证前进行，迁移时必须保持相同时机 | 中 |
| M4 | **SMOTE 1:1 规则** | Methods（P8）：「according to the 1:1 rule」 | 补充 E1 细节：SMOTE 按 1:1 规则过采样训练集 | 低 |
| M5 | **插补器选择的具体方法** | Methods（P8）：四法比较后选择 AUC 最优（LR-MI AUC=0.844） | 补充：插补器选择基于 AUC，迁移时需说明「选优」的标准 | 低 |

---

## 6. Required Fixes

1. **【高】解决划分矛盾**：AI-A 必须引用 Table 1（n=2760/691）与 Methods（80/20）核实实际划分，将 Fig.1 的 70/30 定性为「文本错误」或「图注疏漏」，而非方法层面的真实冲突。建议在 E2 节点明确写出「正文 Table 1 + Methods 均为 80/20，Fig.1 caption 的 70/30 为不一致」。

2. **【高】增加关键假设节点**：AI-A 必须补充以下三个节点：
   - TOPSIS 六个指标等权（w=1/6）；
   - TCF 分类阈值为 0.5；
   - MinMax 归一化在建模/验证前执行。

3. **【中】补充 SMOTE 细节**：注明「SMOTE 按 1:1 规则仅应用于训练集」，并确认验证集/外部集不做过采样。

4. **【中】明确不确定性**：U1 应改为「原文未明确说明插补器是否仅基于训练集拟合；迁移时必须进行 train-only 验证」。

5. **【低】优化表达**：将 E2 的「矛盾」改为「文本不一致」，并说明「实际执行为 80/20」。