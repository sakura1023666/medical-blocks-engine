<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-19T11:23:04 | request_id=msg_8ed03041-891c-44c3-bab6-ea08f41895a8 | usage={"input_tokens": 23421, "output_tokens": 3402, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=7558 -->
# AI-B Tree Attack

paper_id: paper_004
question_id: Q6
review_target: @rounds/A_tree_round1_paper_004_Q6.md
source_file: adversarial_lit_reading/chunks/paper_004_ewas_new.md

## 1. Attack Summary

总体判断：**部分可信，需要重大修改**

主要问题：
1. **N2 定义偏差**：将「bootstrap 纳入频率」称为「内部稳定性」有概念混淆——bootstrap 纳入频率衡量的是变量选择的稳定性，不是预测性能的稳定性，两者不可等同。
2. **N3 方法误读**：AI-A 称 5 折 CV「不是预测 AUC 主指标」，但原文只在 Methods 2.5 提到用 5-fold CV 选择 alpha/lambda，并未说明 AUC 是否曾被评估——AI-A 的「不是预测 AUC 主指标」是把「未报告」偷换为「不是主指标」。
3. **N4 分支遗漏**：类别内 FDR（family-wise FDR）只在 Results 3.3 一句话提及，且未报告具体结果数量或与主 FDR 结论的一致性程度——AI-A 用「相互印证」过度拔高。
4. **N8 因果过度**：AI-A 将 medsens 结果描述为「rho 增大时 ACME 仍讨论方向」是模糊表述，但节点表声称「中介分析被用于验证 ERS-牙周炎关联」——原文明确说中介是「exploratory」且不能建立因果路径，AI-A 的 Provisional Answer 未充分强调这一限制。
5. **N7 证据位置偏差**：E-value 是 Methods 2.5 的陈述，但具体数值在 Supp Table 11（AI-A 正确指出），然而 AI-A 没有说明 E-value 是否也被用于每个单个毒物（补充要点明确 E-value 见 Supplementary Table 11，但正文只提 ERS — 这可能暗示 E-value 仅对 ERS 计算，AI-A 未标注此不确定）。
6. **N5 分支遗漏**：N5 只提「未插补 ExWAS」，但原文 Results 3.7 还包含吸烟调整敏感性分析（Supp Table 8–9）和 WQS/ERS 一致性（Supp Fig.7），这些被 AI-A 完全遗漏。
7. **N6 证据问题**：AI-A 自己对 N6 的证据位置有疑虑（U1 提到 Supp Table 1 可能是笔误），但节点表仍标注 confidence=medium。建议 AI-A 应明确标注「原文自相矛盾，需查 Supp Table 1 实际内容」。

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| N2-1 | N2 | 「内部稳定性=bootstrap 纳入频率」 | 「稳定性」在此指变量选择的重复性，不是预测模型的稳定性（如 bootstrap 预测误差或校准）。概念混淆。 | 原文 Methods 2.5: "bootstrap analysis with 1000 resampling iterations and calculated the inclusion frequency for each variable" — 只验证变量选择稳定性 | 改为「变量选择稳定性=bootstrap 纳入频率（>80% 核心毒物）」 | **高** |
| N3-1 | N3 | 「5 折 CV 只调惩罚参数，不是预测 AUC 主指标」 | AI-A 把「未报告 AUC」偷换为「AUC 不是主指标」——原文根本没提 AUC，不能断言它「不是主指标」，只能说不清楚是否评估过。 | 原文 Methods 2.5: "The optimal parameter combination was identified through 5-fold cross-validation." 未提 AUC | 改为「5 折 CV 用于调 alpha/lambda；原文未报告预测性能指标（如 AUC/校准）」 | **高** |
| N4-1 | N4 | 「类别内 FDR 与主 FDR 相互印证」 | 「相互印证」过度拔高。原文只说 "sensitivity analysis implementing family-wise FDR control within each chemical class corroborated the robustness"，但未给出两类 FDR 下显著毒物列表是否完全一致。 | 原文 Results 3.3: "corroborated the robustness" — 主观措辞，无定量对比 | 改为「类别内 FDR 敏感性分析声称支持主发现，但未报告两类 FDR 显著毒物列表的一致性」 | **中** |
| N5-1 | N5 | 「未插补 ExWAS」 | 遗漏了同一节中的吸烟调整分析和 WQS/ERS 一致性分析。 | 原文 Results 3.7 有吸烟调整（Supp Table 8–9）和 WQS 一致性（Supp Fig.7） | 补充 N5b 「吸烟调整敏感性」和 N5c 「WQS/ERS 一致性」 | **中** |
| N7-1 | N7 | 「E-value 量化未测量混杂要多强才能解释掉关联」 | 表述正确，但未说明 E-value 是对 ERS 还是也针对每个单个毒物。补充要点提到 "E-value 见 Supplementary Table 11"，但正文只提 ERS 的稳健性。AI-A 的 Follow-up Question 2 已注意到但未在 Provisional Answer 中标注。 | 原文 Discussion: "although E-values suggest that unmeasured confounding is unlikely to fully explain the observed associations (Supplementary Table 11)" — 未明确作用对象 | 在 Provisional Answer 中标注「E-value 作用对象（ERS vs 每个毒物）原文不明」 | **中** |
| N8-1 | N8 | 「medsens：rho 增大时 ACME 仍讨论方向」 | AI-A 节点表声称中介「因果过度」risk_tag，但 Provisional Answer 没有充分说明中介是 exploratory。原文明确 "mediation analyses provide valuable mechanistic insights, they cannot establish definitive causal pathways"，AI-A 应强调这一点。 | 原文 Results 3.6: "exploratory" 且 "cannot establish definitive causal pathways" | 在 Provisional Answer 中增加「作者明确中介为探索性，不能建立因果路径」 | **中** |
| N8-2 | N8 | 「ACME 仍统计显著」 | 原文表述 "remained statistically significant across a wide range of ρ values" — 但 ρ 的范围没给出，AI-A 说「仍讨论方向」模糊了「显著性」vs「方向」的区别。 | 原文 Results 3.6: "remained statistically significant" | 改为「原文称 ACME 在 wide range of ρ 下仍统计显著，但未给出 ρ 具体范围」 | **低** |
| N9-1 | N9 | 「不能声称预测外部有效」 | 表述正确，但没强调「单周期横断面」和「无外部队列」是同一限制的两个层面：时间外推 vs 人群外推。可以更清楚。 | 原文 Discussion: "cross-sectional design of NHANES precludes causal inference" + "generalizability…limited" | 可拆分为「N9a: 时间外推受限（单周期）」和「N9b: 人群外推受限（无外部队列）」 | **低** |

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E-edge-1 | N0 → N2 | N0 问「有效性证据到哪一层」，N2 答「bootstrap 纳入频率」——但「有效性」在预测模型语境通常是区分度/校准，在关联研究语境是稳健性。AI-A 未先定义「有效性」的含义就跳到 bootstrap，边上有概念跳跃。 | 在 N1 和 N2 之间加一个节点「有效性在本研究的定义 = 关联估计对分析选择的稳健性（非预测性能）」 | **高** |
| E-edge-2 | N2 → N3 | N2（bootstrap 稳定性）与 N3（5 折 CV 调参）之间缺乏逻辑关系说明。两者是在 ERS 构建流程的先后步骤，不是推理链条。AI-A 的边含义不明。 | 改为「N2 → N3 为流程顺序关系，非逻辑推导」或干脆移除该边 | **中** |
| E-edge-3 | N0 → N7 | N0 问「有效性证据」，N7 答「E-value」——E-value 不是「有效性证据」而是「未测量混杂的稳健性」。AI-A 未区分「证据类型」与「稳健性分析」。 | 在 N0 下分两条分支：「证据类型：外部验证存在性」和「稳健性分析：E-value/medsens/敏感性」 | **中** |
| E-edge-4 | N1 → N9 | N1→N9 标注 `limitation`，但 N9 是「不能声称外部有效」，实际是 N1 的直接推论，不是一个新claim。AI-A 把同一限制拆成 claim+limitation 两层，造成冗余。 | 合并 N1 和 N9，或明确 N9 是「从无外部队列推导出的临床含义」 | **低** |

## 4. Evidence Problems

1. **N6 证据位置内部矛盾（AI-A 已自认）**：
   - AI-A 在 U1 指出 Supp Table 1 可能是笔误，但节点表仍写「evidence_location：结果3.7」。原文确实说 "Outlier assessment confirmed that the majority of pollutants exhibited acceptable outlier proportions (<10 %)…(Supplementary Table 1)" — 但 Supp Table 1 在 Methods 中被描述为「最初89种毒物的特征表」。这可能确实是表格编号不一致（或补充材料的多个版本），但 AI-A 应明确标注「存疑」而不是仅降 confidence 为 medium。

2. **N7 E-value 证据定位不足**：
   - AI-A 正确将 E-value 定位到 Methods 2.5 + Supp Table 11，但未检查 Supp Table 11 是只包含 ERS 的 E-value 还是也包含每个单个毒物。补充统计要点提到 "E-value 见 Supplementary Table 11"，但未明确作用对象。AI-A 应在 Follow-up Question 中明确这一项。

3. **N8 缺少对 medsens 参数细节的说明**：
   - 原文提及 "residual correlation coefficients (ρ)" 和 "R̃²_M/R̃²_Y"，但 AI-A 只提 ρ。R̃²_M 和 R̃²_Y 的敏感性分析也是证据的一部分，AI-A 遗漏。

4. **N8 因果限定不足**：
   - 原文 Methods 2.5 明确 "Mediation analysis was explicitly framed as exploratory and was conducted to generate hypotheses rather than establish causal pathways"，AI-A 在 N8 risk_tag 标了「因果过度」但其 Provisional Answer 没有复述这一限定，读者可能误解。

5. **N4 「相互印证」表述过度**：
   - 原文 "A sensitivity analysis implementing family-wise FDR control within each chemical class corroborated the robustness" — "corroborated" 是作者主观断言，没有给出具体数字（如多少毒物在两类 FDR 下都显著）。AI-A 应标注「原文称 corroborated，未提供定量对比」。

6. **N9 「不能当预测模型外部有效」措辞不当**：
   - 原文是横断面关联研究，根本没有构建预测模型。AI-A 说「不能当预测模型外部有效」暗示有人曾这么声称，但实际上没人声称。更好的表述是「该研究的 ERS 关联结果不具备外部预测效度」。

## 5. Missing Branches

1. **缺少「无区分度/校准度指标」分支**：
   - 原文没报告 AUC 或 C-statistic，也没报告校准（如 Hosmer-Lemeshow 或校准图）。AI-A 在 U2 标注了「未见 Hosmer-Lemeshow 或校准图」，但没有将这一缺失纳入决策树。

2. **缺少「吸烟调整敏感性分析」分支**：
   - 原文 Results 3.7 有吸烟调整分析：大多数关联在调整吸烟后衰减，且非吸烟者中仅 Lead、2HPMA、2-Naphthol 仍显著。这是很关键的敏感性分析，AI-A 完全遗漏。

3. **缺少「WQS/ERS 方法一致性」分支**：
   - 原文 Results 3.7 指出 WQS 高权重化合物与 ERS 非零系数高度一致（2-Naphthol、Lead、2-Aminonaphthalene），且 MeA-α-C、MHBMA2、TTCA 等被两种方法同时识别。这是方法学稳健性的证据，AI-A 遗漏。

4. **缺少「中介分析顺序可忽略性假设」分支**：
   - 补充要点提到 "中介：mediation 包，顺序可忽略性，medsens"。AI-A 的决策树完全没提「顺序可忽略性假设」这一关键假设，缺失意味着无法评估中介分析的可靠性。

5. **缺少「ExWAS 不加权」分支**：
   - 原文 Methods 2.5 明确 ExWAS "reported unweighted results to maintain methodological consistency with prior investigations and to avoid potential over-adjustment bias"。AI-A 未提 ExWAS 不加权。这是方法学敏感性的一个层面。

6. **缺少「LOD 处理」分支**：
   - 补充要点提到 LOD 有多种处理（剔除、二分类、ln），这是暴露测量层面的敏感性。虽然没有专门敏感性分析，但原始处理方式值得标注。

## 6. Required Fixes

1. **(高) 重新定义「有效性」**：AI-A 需在树中先明确「本研究中的有效性 = 关联估计对分析选择的稳健性」，而非「预测性能」。（解决 N2-1、E-edge-1）

2. **(高) N3 修正表述**：删除「不是预测 AUC 主指标」，改为「5 折 CV 用于调参；原文未报告 AUC/校准指标」。（解决 N3-1）

3. **(高) N4 淡化「相互印证」**：改为「类别内 FDR 敏感性分析声称支持主发现，但未提供两类 FDR 显著毒物列表的一致性对比」。（解决 N4-1）

4. **(中) 补充缺失分支**：加入「吸烟调整」「WQS/ERS 一致性」「无 AUC/校准」「中介顺序可忽略性假设」四个分支。（解决 N5-1、Missing Branches 1-4）

5. **(中) N8 强调中介探索性**：在 Provisional Answer 中复述「作者明确中介为 exploratory，不能建立因果路径」。（解决 N8-1）

6. **(中) N7 明确 E-value 作用对象**：标注「E-value 是只针对 ERS 还是也针对每个单个毒物，原文未明确」。

7. **(低) N6 证据位置标注存疑**：将 N6 的 evidence_location 改为「含矛盾表述的段落，需复查 Supp Table 1 实际内容」。（解决 AI-A U1）

8. **(低) N1/N9 合并或明确层理**：保留 N1→N9 但注明 N9 是推论而非独立限制。（解决 E-edge-4）

9. **(低) 决策树补充分支标注「未评估」**：在图中增加虚线节点或注释「无 AUC、无校准、无外部队列、单周期」作为证据缺口。