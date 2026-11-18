<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-10T15:47:13 | request_id=msg_89f5c4a4-a8cc-4e86-8b80-1df3c202b654 | usage={"input_tokens": 12111, "output_tokens": 2974, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=6643 -->
# AI-B Tree Attack

paper_id: paper_025
question_id: Q7
review_target: @rounds/A_tree_round1_paper_025_Q7.md
source_file: pp. 1-8, Discussion / Supp excerpt Methods

## 1. Attack Summary

**总体判断：需要重大修改**

**主要问题**：
- AI-A 的决策树将「RLoS定义/封顶简化」遗漏为限制条件，这是**重大遗漏**（原文 Supp Methods 明示 RLoS 封顶至10天，预测值「10」意味着「超过10天」，且训练时纳入死亡患者但评估时排除死亡患者——这种条件性输出本身是一大局限）
- 节点 N5 声称「未推翻『池化优于单源』的方向」，但原文 Table 3 显示：**池化在 MIMIC-IV 特化上 Mcomposite=0.97 劣于单源 MIMIC-IV 的 0.89（+9.0%）**——AI-A 未将此权衡纳入分支，方向性结论的证据力度低于所声称的水平
- E1 证据位置过于笼统（仅标「Disc」），但捷径学习的具体证据在 Discussion 倒数第二段（AmsterdamUMC 药物暴露特征→泛化差距）和 Results「Comparison of internal and external validations」段均有原文支持
- 决策树对「观察性回顾」的限制描述不够精细——原文 Ethics 是「preexisting ethical approvals or exemptions」，且 Supp Materials 明确指出数据是 MNAR 结构，这在限制层次上比 AI-A 所述「回顾观察性」更强
- 关键遗漏：**前瞻部署与临床决策影响**——AI-A 在 Uncertainty 部分提到但**未纳入决策树主体结构**，且作者明确主张「开放本地数据」的**前提**是「较小但本地数据也可有效」，这一因果链条被遗漏

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| N-1 | N1 (捷径学习) | 「站点特异特征捷径」 | 用「捷径」概括原文关切基本准确，但过度收窄——原文所谓「shortcut learning」特指 AmsterdamUMC-trained 模型在 RLoS 上的泛化失败（MAPE+51.8%），而非所有站点模型。AI-A 未说明这是**站点特定发现**而非一般性结论 | 原文 Disc 段「It is plausible that the model learned to rely on site-specific patterns... This form of shortcut learning... our data cannot fully characterize」——原文使用「plausible」和「cannot fully characterize」，属推测，非确证 | 在 N1 后限缩为「AmsterdamUMC-trained模型可能依赖站点特征捷径（原文为推测性）」，并标注原文不确定性 | 中 |
| N-2 | N2 (域偏移) | 「外部验证性能下降」 | 基本正确，但 AI-A 未解释该下降的**非对称性**：AmsterdamUMC 训练集在外部验证中 AUROC 反而 **+4.4%** 上升（Table 2），这意味着「域偏移导致下降」**并非普遍规则**，存在反例 | Table 2 中 AmsterdamUMC AUROC 内部 0.774→外部 0.808 (+4.4%) | 在 N2 中补充「但存在例外：AmsterdamUMC-trained 模型外部 AUROC 不降反升」，将「下降」改为「通常下降」 | **高** |
| N-3 | N3 (观察性回顾) | 「观察性数据库；既有伦理豁免」 | 遗漏关键限制维度：数据是 **MNAR** 结构（缺失依赖于数据来源和患者病情），且原始诊断数据不可用（「Diagnoses were not included」）。这两个限制对结论可外推性的影响大于「观察性回顾」本身 | Supp Methods「Missing data in this study are best characterized as Missing Not At Random (MNAR)...」；pp. 3「Diagnoses were not included, as they are not consistently available」 | 在 N3 下添加分支：N3a「MNAR缺失模式+前向填充简化」、N3b「诊断数据不可用」 | **高** |
| N-4 | N5 (claim) | 「未推翻『池化优于单源』方向」 | 过度收窄「单源」——池化对 AmsterdamUMC 特化显著优于单源（1.07 vs 1.41），但对 **MIMIC-IV 特化反而劣于单源**（0.97 vs 0.89, +9.0%）。这不是「未推翻方向」而是「方向有条件成立」。AI-A 的 medium 置信度低估了这一权衡的重要性 | Table 3「data pooling incurred a performance cost for specialization on MIMIC-IV: its Mcomposite (0.97) was 9.0% higher than that of the MIMIC-IV single-source model (0.89)」 | 将 N5 改为「池化在泛化上一致最优，且对 AmsterdamUMC 特化不劣；但对 MIMIC-IV 特化有明确成本」，并增加条件变量「源集规模/异质性」 | **高** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E-1 | N1 → N5 | N1 的捷径学习被用作支持「主结论方向不变」的证据之一，但原文对捷径学习明确标注「our data cannot fully characterize」——**一个未充分表征的现象不能作为「未推翻主结论」的论据** | 在 N1→N5 边上标注「推测性支持（原文明确不确定性）」或直接删除该支持路径，改造为「N1 削弱 AmsterdamUMC-trained 模型的可移植性，但影响范围有限」 | **中** |
| E-2 | N2 → N5 | 域偏移的存在（N2）与「池化优于单源」的结论（N5）之间缺少中介步骤：需要说明「域偏移→池化通过多源训练缓解→因此方向成立」。AI-A 逻辑跳跃 | 在 N2 与 N5 之间添加中间节点：「池化通过多源训练针对性缓解域偏移（Table 3 Generalization 列）」 | **中** |
| E-3 | N0 → N3 | N0「局限」连接到 N3「观察性回顾」缺少中间解释——观察性回顾本身不一定是局限，真正的局限是**无法建立因果效应**和**回顾性偏差**。AI-A 未展开因果链 | 在 N0→N3 间标注「观察性设计限制因果推断的强度」 | 低 |
| E-4 | N4 (transfer) 无入边 | N4 节点「transfer:开放数据主张」在 Mermaid 图中**无关联入边**——它作为一个孤立节点出现。AI-A 将其标记为「transfer」但未说明它与局限性分析的关系 | 添加 N4 的入边来源：从 N3（本地数据价值）或新增节点「本地小数据亦可有效（Discussion）→开放数据主张」 | **中** |

---

## 4. Evidence Problems

1. **E1 证据位置过于笼统**：仅标「Disc」，但捷径学习的具体证据应定位到 Discussion 倒数第二段（「It is plausible...」）——AI-A 的 Evidence Map 未细化到段落级。
2. **E2 证据混淆**：将「域偏移导致外验下降」作为一条证据，但原文 Table 2 明确显示 AmsterdamUMC 外部 AUROC **不降反升**——AI-A 的证据定位未包含这一例外。
3. **遗漏 RLoS 封顶简化**：原文 Supp Methods「RLoS was capped to 10 days; a prediction of 10 was equivalent to 'RLoS is more than 10 days'」——这是一个**明确的方法简化限制**，但 AI-A 仅在 Provisional Answer 中以「RLoS定义/封顶简化」一句话带过，未纳入节点结构。
4. **观察性限制表述不完整**：原文 Supp Materials 详细说明 MNAR 结构（缺失概率取决于数据来源和患者病情），这是比「回顾观察性」更具体的限制维度。
5. **遗漏「死亡患者排除条件」**：原文 Supp Methods「when evaluating performance, length-of-stay predictions are not included for patients who have died」——RLoS 评估排除死亡患者是另一个重要方法限定，AI-A 未提及。

---

## 5. Missing Branches

| missing_branch_id | missing content | original evidence | suggested action | severity |
|---|---|---|---|---|
| M-1 | **RLoS 封顶至10天**：预测值封顶，10天以上视为同一类别 | Supp Methods「RLoS was capped to 10 days...」 | 新增节点「N6：RLoS封顶简化」连入 N0 | **高** |
| M-2 | **RLoS 评估排除死亡患者**：预测是条件性的（假设存活至出院） | Supp Methods「length-of-stay predictions are not included for patients who have died」 | 合并入 N6 或新增 N7 | 中 |
| M-3 | **诊断数据不可用**：四库未统一，诊断未纳入输入 | pp. 3「Diagnoses were not included, as they are not consistently available」 | 新增分支「输入缺失诊断→预测能力受限」 | 中 |
| M-4 | **MNAR 缺失 + 前向填充简化假设**：假设两次测量间生理值稳定 | Supp Methods「this approach rests on the simplifying assumption that physiological values remain stable between measurements」 | 新增节点「缺失处理简化假设」 | 中 |
| M-5 | **池化在 MIMIC-IV 特化上的成本** | Table 3「Mcomposite (0.97) was 9.0% higher than that of the MIMIC-IV single-source model (0.89)」 | 在 N5 下添加反例分支 | **高** |
| M-6 | **地理偏差**：北美队列主导，亚非无大型开放ICU库 | pp. 8「No large open-access ICU databases currently exist from Asian or African healthcare systems」 | 新增节点「地理代表性偏差限制泛化主张范围」 | **高** |
| M-7 | **样本量阈值的局限性**：15,000 阈值基于特定数据集组合，外推需谨慎 | pp. 7「a minimum threshold of 15,000 patients is necessary...」 | 作为不确定性补充，加入 Uncertainty 部分 | 低 |
| M-8 | **前瞻部署未验证**：作者主张「开放数据 + 本地验证」，但论文本身未做前瞻性部署研究 | 全文未见前瞻验证设计 | 在 N4 transfer 节点旁标注「主张与证据差距」 | 中 |

---

## 6. Required Fixes

1. **【必修-高】补充 RLoS 封顶限制**：在决策树主体中新增节点「N6：RLoS封顶至10天+评估排除死亡患者」，连入 N0，并标注「方法简化限制」。
2. **【必修-高】修正 N2 的表述**：从「域偏移导致下降」改为「域偏移通常导致下降，但 AmsterdamUMC-trained 模型外部 AUROC 反升 +4.4%（Table 2 例外）」，以准确反映证据。
3. **【必修-高】修正 N5 的「主结论方向」**：删除「未推翻『池化优于单源』」的表述，改为「池化在**泛化**上最优，且对 AmsterdamUMC 特化不劣于迁移学习；但对 MIMIC-IV 特化有改善成本（Mcomposite 0.97 vs 0.89）」，并确认「方向性结论有条件成立」。
4. **【必修-中】补充 MNAR 缺失模式与诊断数据不可用**：新增节点分支，说明数据限制不仅是「观察性回顾」，更具体的是 MNAR 缺失结构（依赖数据来源和患者状态）和诊断信息缺失。
5. **【必修-中】补充地理偏差**：新增节点「地理代表性偏差——北美/西欧队列主导，亚非无大型开放 ICU 数据库，限制泛化主张范围」。
6. **【必修-中】修复 N4 孤立节点**：为「开放数据主张」添加入边——原文 Discussion「This suggests that high-quality, specialized local repositories may be more valuable...」提供逻辑支持。
7. **【推荐-低】细化 E1 证据位置**：将 N1 的证据定位到引用具体段落（Discussion 倒数第二段「It is plausible that the model learned to rely on site-specific patterns...」），并标注原文不确定性（「our data cannot fully characterize」）。
8. **【推荐-低】在 N1→N5 边上标注证据强度**：因原文对捷径学习明确标注「cannot fully characterize」，该证据对「未推翻主结论」的支持力度应为弱支持，而非默认支持。

---

> **AI-B 说明**：当前决策树的主要缺陷不在于节点数量，而在于**节点表述的精确性**（N2 的例外遗漏、N5 的过度泛化）、**关键分支的遗漏**（RLoS封顶、MNAR、地理偏差），以及**证据与结论之间缺少梳理条件**。修正上述6项必修项后，决策树的可信度可从「需要重大修改」提升至「基本可信」。