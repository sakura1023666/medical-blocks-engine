<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-10T15:46:35 | request_id=msg_2a4050d6-2476-47a5-b109-3632c1783ce3 | usage={"input_tokens": 12182, "output_tokens": 3653, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=7946 -->
# AI-B Tree Attack

paper_id: paper_025
question_id: Q6
review_target: @rounds/A_tree_round1_paper_025_Q6.md
source_file: @papers/paper_025.pdf (Results Table2-3 Fig.2 MOESM2)

## 1. Attack Summary

总体判断：部分可信，但需要重大修改

主要问题：决策树将五个证据节点并列，未区分证据层级（如"方法描述"与"实证结果"混为一谈）；对AUPRC结果及"shortcut learning"这一关键机制发现严重遗漏；N2节点将表3的多策略对照概括为"池化改善泛化/专化权衡"，但原文结果远为复杂——池化在MIMIC-IV专化上实质**劣于**单源训练（Mcomposite 0.97 vs 0.89）；此外，N5将DeLong/bootstrap标记为"method"类型，与N1-N4的"evidence"类型并列，存在类型混淆。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| N-01 | N1 | "内验不能代替外验" | 表述过于笼统。原文的关键发现不仅是"内验高估外验"，还包括**例外情况**：AmsterdamUMC训练的模型在外部数据上AUROC反而**上升+4.4%**。N1将此结果简化为单向"高估"，丢失了重要条件。 | 原文Table2：AmsterdamUMC AUROC内验0.774→外验0.808（+4.4%）。E1证据位置正确但概括不完整。 | 修改为："内验通常高估外验，但存在例外——AmsterdamUMC训练的模型在外部AUROC反升+4.4%，提示不同训练源的外推潜力存在差异。" | **中** |
| N-02 | N2 | "池化改善泛化/专化权衡" | 严重过度简化。原文Table3显示：池化在AmsterdamUMC专化上确实优于单源训练（Mcomposite 1.07 vs 1.41），但在MIMIC-IV专化上**劣于**单源训练（0.97 vs 0.89，即"9.0% higher"）。"改善权衡"意味着两全其美，但原文明确说这是"expected trade-off"。 | 原文第6页："data pooling incurred a performance cost for specialization on MIMIC-IV: its Mcomposite (0.97) was 9.0% higher than that of the MIMIC-IV single-source model (0.89), reflecting the expected trade-off" | 拆分为两个节点：(a) 池化在AmsterdamUMC专化和泛化上优于单源训练；(b) 池化在MIMIC-IV专化上劣于单源训练，存在资源规模不对称时的权衡成本。 | **高** |
| N-03 | N3 | "更大数据有帮助" | 过于简化。原文Fig.2的核心发现是**非线性关系**：<5,000患者严重退化；15,000患者是**稳定基线的最低阈值**；>15,000后进入**平台期**。"更大数据有帮助"忽略了平台期，可能误导用户认为数据越多越好。 | 原文p.7："models trained on fewer than 5,000 patients exhibited significant performance degradation... a performance plateau was observed beyond 15,000 patients, where additional data yielded only marginal gains" | 修改为："样本量效应呈非线性：<5,000患者性能显著退化，15,000为稳定基线阈值，>15,000收益边际递减（平台期）。" | **中** |
| N-04 | N4 | "TPC基准" | N4的E4证据仅来自MOESM2（Table S2），但原文p.3明确说明TPC基准是**预先验证步骤**，而非核心有效性证据。此外，AI-A将N4与其他有效性证据并列，忽略了TPC基准是**模型选择依据**而非**分析有效性证据**。 | 原文p.3："Prior to adopting TPC, we benchmarked three state-of-the-art architectures - Transformer, LSTM, and TPC" | 将N4降级为模型选择背景，或明确标注其角色：TPC基准支持"模型选择合理"，但不直接支持"分析有效"。 | **中** |
| N-05 | N5 | "DeLong/bootstrap" | 类型混淆。N5标记为"method"，但它并不是对Q6的直接回答——置信区间方法是**统计严谨性的体现**，属于支持性信息，不应与N1-N4（实质性结果）并列。此外，遗漏了Mcomposite的bootstrap CI（1,000次）、AUPRC的bootstrap CI（10,000次）等细节。 | 原文Table2脚注："95% CI for AUROC were computed using the DeLong method; 95% CIs for MAPE and AUPRC were estimated by bootstrap resampling (10,000 iterations, percentile method)"。Table3脚注中Mcomposite CI为1,000次bootstrap。 | 将N5移至"支持性方法信息"，或与关键结果合并——核心是N1/N2的结论有CI支撑，而非CI方法本身构成独立证据。 | 低 |
| N-06 | **缺失节点** | **AUPRC结果** | 原文报告了**完整的AUPRC分析**，且发现内验→外验AUPRC降幅（-3.3%至-40.8%）**远大于AUROC降幅**（-2.5%至-13.8%），说明AUPRC对分布偏移更敏感。AI-A完全遗漏了AUPRC，这是有效性论证的重要组成部分。 | 原文第5页："The drop from internal to external validation was more pronounced for AUPRC than for AUROC, with drops ranging from −3.3% (AmsterdamUMC) to −40.8% (MIMIC-IV)" | 新增节点："AUPRC降幅显著大于AUROC（-3.3%至-40.8% vs -2.5%至-13.8%），说明内验乐观偏差在类别不平衡指标上更为严重。" | **高** |
| N-07 | **缺失节点** | **shortcut learning机制** | 原文发现了一个**关键的机制性解释**：AmsterdamUMC的site-specific特征（药物暴露）被模型用作"捷径"（shortcut），导致外验MAPE+51.8%的最大降幅。这是对"为什么内验不充分"的因果解释，是有效性论证的核心部分，AI-A完全遗漏。 | 原文p.8："It is plausible that the model learned to rely on site-specific patterns, such as local prescribing protocols or unit-type distributions, as proxies for RLoS trajectories... This form of shortcut learning... represents a known vulnerability of single-source training" | 新增节点："AmsterdamUMC外验MAPE+51.8%可能源于shortcut learning——模型利用药物暴露等site-specific特征作为RLoS的代理信号，这些特征不可跨机构迁移。" | **高** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E-01 | N0→N1 | 将Table2作为单一证据支持"内验不能代替外验"，但Table2同时包含例外（AmsterdamUMC AUROC+4.4%）和AUPRC的更大降幅。单一边将复杂结果压缩为单一结论。 | 拆分为两条边：一条指向"内验通常高估外验"（Table2 AUROC/MAPE），另一条指向"AUPRC降幅更大"（Table2 AUPRC）。 | 中 |
| E-02 | N0→N2 | N2的claim被表述为已解决的问题（"改善权衡"），但原文展示的是**有条件的结果**——池化在泛化上胜出，但专化上需看目标站点。AI-A的边暗示这是一个统一结论，实际是条件性发现。 | 将N2拆分为多个节点，边分别指向各自的条件结果。 | **高** |
| E-03 | N0→N5 | N5作为"method"类型节点与N1-N4（evidence）并列在Q6的主干上，暗示CI方法本身是有效性证据之一。但CI方法只是**统计严谨性的保障**，而非有效性的直接支持。 | 将N5从主链移至"辅助信息"分支，或将其标注为"方法学质量"而非"有效性证据"。 | 低 |
| E-04 | N1→N2 | 两条边之间缺少逻辑连接——N1说"内验不可靠"，N2说"池化好"，但原文的推理是：因为单源训练存在泛化脆弱性（N1），所以多源策略更好（N2）。AI-A没有建立这条因果链。 | 增加中间节点："单源训练的外验脆弱性驱动了对多源策略的需求"，并标注因果关系。 | 中 |

---

## 4. Evidence Problems

| problem_id | problem type | location | description | suggested fix | severity |
|---|---|---|---|---|---|
| P-01 | 证据不完整 | N1的E1 | 仅引用Table2的MAPE+51.8%和AUROC-13.8%，遗漏了Table2中AUPRC的关键数据（-3.3%至-40.8%），且未提及AmsterdamUMC的AUROC**正变例外**。 | 引用完整Table2，包含AUROC、AUPRC、MAPE三列及正负两个方向的变异。 | 高 |
| P-02 | 过度引用 | N2的E2 | 将Table3作为支持"池化改善权衡"的统一证据，但Table3数据显示池化在MIMIC-IV专化上劣于单源（0.97 vs 0.89）。 | 细化引用：区分"AmsterdamUMC专化上池化胜出"与"MIMIC-IV专化上池化失利"。 | **高** |
| P-03 | 偷换概念 | N3的E3 | 将Fig.2的发现概括为"更大数据有帮助"，但原文强调的是**阈值效应**（15,000平台起点）和**饱和**（>15,000边际递减）。"有帮助"暗示线性关系，与平台期矛盾。 | 使用原文的表述："minimum threshold of 15,000 patients is necessary to achieve stable baseline performance" + "plateau beyond 15,000"。 | 中 |
| P-04 | 缺失证据 | 未引用AUPRC | 原文Table2中AUPRC是内验/外验比较的重要组成部分（"-40.8% MIMIC-IV, -24.9% HiRID"），AI-A完全忽略。 | 新增节点或合并入N1，引用AUPRC数据。 | **高** |
| P-05 | 方法/证据混淆 | N5的E5 | 将"DeLong/bootstrap"作为证据（E5）列出，但它不是证据——它是统计方法，相当于"我们用了什么工具来计算CI"，而非"我们发现了什么"。 | 将N5从证据节点改为"方法学质量"标注，不参与有效性主体论证。 | 低 |
| P-06 | 位置准确但引用过窄 | 缺失shortcut learning | 原文Discussion中对shortcut learning的讨论是理解"why internal validation fails"的核心机制证据。AI-A未纳入。 | 从Discussion中引用以支持因果链。 | **高** |

---

## 5. Missing Branches

| branch_id | missing branch description | original evidence location | rationale for importance | suggested insertion point | severity |
|---|---|---|---|---|---|
| B-01 | **AUPRC敏感性**：内验→外验AUPRC降幅显著大于AUROC | Table2 | AUPRC对类别不平衡更敏感，在外验语境下更能揭示分布偏移的危害。遗漏AUPRC意味着低估内验乐观偏差的严重性。 | N1之后追加子节点 | **高** |
| B-02 | **Exogenous generalizability**：AmsterdamUMC训练的AUROC外验**提升**+4.4%（唯一正例外） | Table2，p.4 | "Internal validation generally overestimated"的表述需要限定"generally"——存在反例。遗漏此反例会误导为"always"。 | N1之后追加条件分支 | 中 |
| B-03 | **Transfer learning仅在AmsterdamUMC上评估** | Table3脚注 | 原文明确Transfer Learning只评估了specalization on AmsterdamUMC（"this model was not evaluated on other data sources"），未评估泛化。AI-A的N2未区分这一限制，可能让用户误以为transfer learning在泛化上也有数据支持。 | N2中添加限定条件 | 中 |
| B-04 | **地理偏差与数据代表性**：缺亚洲/非洲大样本ICU数据库 | p.8 Discussion | 用户问题含"证据强度"——外验仅在4个数据库（美2，欧2）进行，缺乏全球代表性。这影响证据外推强度。 | Provisional Answer不确定段 | 中 |
| B-05 | **Mcomposite的局限性声明** | Table3脚注 | "The composite metric is used for cross-configuration ranking only; AUROC and MAPE remain the primary performance metrics"。AI-A未说明Mcomposite的角色限制。 | N2节点中标注Mcomposite的角色 | 低 |
| B-06 | **无前瞻性验证** | AI-A的Uncertainty已有 | 已覆盖 | 无需修改 | - |

---

## 6. Required Fixes

### 必需修改（高优先级）

1. **拆分并重新表述N2**：将"池化改善泛化/专化权衡"改为条件性结论：(a) 泛化（eICU/HiRID）：池化最佳（Mcomposite=1.15，优于AmsterdamUMC单源4.2%，优于MIMIC-IV单源8.0%）；(b) AmsterdamUMC专化：池化≈迁移学习（1.07 vs 1.08，CI重叠），显著优于单源（1.41）；(c) MIMIC-IV专化：池化**劣于**单源（0.97 vs 0.89）——数据量不对称时的权衡成本。

2. **新增AUPRC节点**：引用Table2中AUPRC降幅数据（-3.3%至-40.8%），说明内验乐观偏差在AUPRC上更严重。

3. **新增shortcut learning节点**：引用Discussion中AmsterdamUMC训练模型外验MAPE+51.8%的机制解释，增强因果论证。

4. **N1添加例外条件**：明确AmsterdamUMC AUROC外验+4.4%的正向例外，修正"内验不能代替外验"的绝对表述。

### 建议修改（中优先级）

5. **N3细化非线性关系**：改为"样本量效应呈非线性：<5,000显著退化，15,000为稳定基线阈值，>15,000边际收益递减"。

6. **N4重新定位**：标注为"模型选择依据"而非"有效性证据"，区分TPC基准与Q6应答之间的关系。

7. **补充Transfer Learning评估范围限制**：注明transfer learning仅评估了AmsterdamUMC专化，未评估泛化（原文Table3脚注）。

8. **B-04地理偏差**：在Provisional Answer或Uncertainty中增加"外验仅覆盖北美（2）和欧洲（2）数据集，无亚洲/非洲代表"的限定。

### 可选修改（低优先级）

9. **N5改为"辅助方法信息"**：不再与N1-N4并列。

10. **Mcomposite角色标注**：注明"仅用于跨配置排序，AUROC/MAPE为主指标"（Table3脚注）。

---

## 7. 总结性判断

AI-A的决策树识别的证据位置（Table2, 3, Fig.2, MOESM2）均准确，但存在三个严重影响结论可信度的问题：(1) **N2的过度简化**——将池化的条件性优势概括为无条件的"改善权衡"；(2) **AUPRC完全遗漏**——原文的关键发现之一（AUPRC降幅>AUROC）未纳入；(3) **shortcut learning机制被遗漏**——这是"为什么内验不充分"的因果解释核心。修正以上三项后，决策树可从"部分可信"提升至"基本可信"。