<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-09-30T11:23:21 | request_id=msg_2e1188b3-fbc5-4b3c-8758-36566ccf8f95 | usage={"input_tokens": 9307, "output_tokens": 4227, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=8044 -->
# AI-B Tree Attack

paper_id: paper_022
question_id: Q2
review_target: @rounds/A_tree_round1_paper_022_Q2.md
source_file: adversarial_lit_reading/chunks/paper_022_2026_wang_ckm_cum_egdr_stroke.md

## 1. Attack Summary

总体判断：**部分可信，需要重大修改**

主要问题：
1. **N6（未报告多重比较校正）证据不足**：AI-A 将「原文未报告」标记为高置信度 limitation，但未考虑「未报告」≠「未做」，且 Supp 表格中大量亚组 HR 与小 P 值的组合本身即可作为判断多重比较问题严重性的线索——AI-A 未利用可见表格来推断实际风险规模。
2. **N7（多层暴露=同一科学问题的互补编码）逻辑跳跃**：原文从未声明三类暴露是「互补编码」，AI-A 以推测性解释替代原文证据，且该推测直接影响对 Q2（多重比较膨胀）的回答方向。
3. **N1 存在偷换概念**：AI-A 将「单一主终点=新发卒中」直接等同于「无多重比较问题」，但 Q2 的多重比较来源不仅在于终点数量，更在于**亚组×多暴露×多模型**的检验数量——AI-A 的 N1 回答收窄了问题范围。
4. **N4 证据错误**：Fig.3 指代不明。正文 Fig.3 是 RCS 图，但 Supp Fig.S1 才是分三面板的 RCS（全体/0-2/3-4）。AI-A 将 Supp 内容标注为 Fig.3，且未指明是 Supp 图。
5. **N5 证据不完整**：Table 3 在原文中为**基线特征表**（Table 1），亚组分析实际在 Supp Table S2/S3/Fig.S2/S3。AI-A 将 Table3/Supp S2 混为一谈，位置标引混乱。

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| N-A1 | N1 | 「单一主终点=新发卒中」 | 偷换概念：原文确为单一终点，但 Q2 关注的多重比较压力并非仅由终点数量决定。即使只有一个终点，亚组×暴露编码×模型族的组合仍构成大量检验。N1 的表述容易被理解为「无多重比较问题」。 | 原文确实只有 stroke 一个终点（确认）；但结论部分不应由「单一终点」直接跳转到「无多重比较风险」。 | 修改 claim：明确区分「终点单一」与「检验族规模」，说明单终点≠无多重比较问题。 | 高 |
| N-A2 | N2 | 「多层暴露并行：聚类类/连续累积/三分位」 | 暴露编码的表述基本准确，但遗漏关键细节：三分位（tertile）实际在敏感性分析（Table S1/S3）中与主分析分离，且聚类类之间的对比为 4 类**非独立两两比较**（3 个 dummy 对比），其多重比较结构与连续暴露不同。 | 原文：累计 eGDR 分为连续 + 三分位（正文 Method）；k-means 4 类（正文 Method）。三分位用于敏感性（正文 Method 说明敏感性分析含重新分类为三分位）。 | 补充：三类暴露编码的检验结构不同（类别对比 vs 连续趋势 vs 敏感性），多重比较压力各异，需分别讨论。 | 中 |
| N-A3 | N3 | 「主模型logistic；Cox/MICE=敏感性」 | **方法攻击：Cox 并非纯粹敏感性**。原文正文明确：「Cox proportional hazards models as sensitivity analyses」，但因卒中发生率为 6.4%（低事件率），logistic OR 近似 HR 的前提是 rare disease assumption——Cox 在此不仅为敏感性，也承担**验证 OR 近似有效性**的角色。AI-A 将 Cox 简单归为「敏感性」会误导读者忽略其验证 logistic 假设的功能。 | 正文 Methods Statistical analysis 段：「Cox proportional hazards models as sensitivity analyses... under the rare disease assumption」——原文明确说 logistic OR 近似 HR，Cox 用于验证。 | 修改：区分「Cox=假设验证型敏感性」与「MICE=缺失值处理型敏感性」，说明 Cox 是检验 rare disease assumption 的合理性与 OR-HR 近似度的工具。 | 中 |
| N-A4 | N4 | 「RCS 分层面板（全体与分期层）」 | **证据位置错误**：正文 Fig.3 不存在该表述；实际是 Supp Fig.S1（A=全部，B=0-2，C=3-4）。AI-A 将 Supp Fig.S1 标注为 Fig.3，且未指明 Supp。正文的图号对应错误，影响可追溯性。 | 原文正文未出现三面板 RCS；Supp Fig.S1 明确三面板（全体/0-2/3-4）。 | 将证据位置改为 Supp Fig.S1，并在说明中区隔正文/补充材料。 | 中 |
| N-A5 | N5 | 「Table3/Supp S2：亚组多分层+交互P」 | **证据位置错误**：正文 Table 3 不存在（正文仅有 Table 1 基线特征表）。亚组分析实际在 Supp Table S2（Cox HR 亚组）与 Supp Fig.S2/S3（HR/OR 亚组森林图）。AI-A 将 Supp 内容与不存在的 Table 3 混标，损害证据可核验性。 | 原文正文：Table 1 为基线特征；Table 2 为 logistic 结果（AI-A E1 引为「Table2」——实际为 DOCX_TABLE_0，即 Supp Table S1）；Table 3 不存在。Supp Table S2 为 Cox 亚组分析。 | 重新定位：亚组分析=Supp Table S2 + Supp Fig.S2/S3；删除「Table3」指称。同时注意交互 P 值检验方法（LRT），AI-A 未确认交互项的类型与数量。 | 中 |
| N-A6 | N5 | 未标记的交互 P 数量 | AI-A 将「多亚组+交互检验」作为 method 节点但不量化检验数量：正文 Method 列出 8 个亚组（年龄/性别/教育/吸烟/饮酒/CKM 分期/糖尿病/高血压/血脂异常——注意实际上列举了 9 个分组变量，AI-A 未逐一列出）。检验数量直接影响多重比较风险评估。 | 原文 Method：「stratified analyses across these subgroups: age (<60 vs. ≥60), sex, educational attainment, behavioural factors (tobacco/alcohol), CKM stage (0–2 vs. 3–4), presence of diabetes, hypertension, dyslipidaemia」——共 8 个变量，其中行为因素拆为吸烟和饮酒两个。 | 明确亚组数量和交互检验次数（8 组×多种暴露编码），为 N6 的多重比较判断提供量化基础。 | 中 |
| N-A7 | N6 | 「未报告Bonferroni/FDR/假设族校正」 | **攻击核心**：「原文未报告」是从方法部分缺失推断的。但 Supp Table S2 有 6 个亚组 × 3 类暴露 × 多模型 = 数十个小 P 值；Table S1 同样。原文 Method 语句「significance set at two-tailed P<0.05」是唯一校正说明。AI-A 将「未报告校正」表述为 limitation 但未做两层区分：(1) 未报告 ≠ 未做，可能只是未写；(2) 即使未做，在原始研究中这是常见做法，不等于不可接受。AI-A 的「high confidence + 证据不足」风险标签冲突。 | 原文 Method：「statistical significance set at two-tailed P < 0.05」——这是唯一 P 值阈值说明，未表明任何族误差控制。Supp 未提供校正版本的结果。 | 修改措辞：改为「原文仅设定两尾 P<0.05 阈值，未描述任何多重比较校正程序；考虑到亚组与多暴露编码数量，多重比较膨胀风险存在但无法从原文直接量化」。将 confidence 从 high 降为 medium。 | 高 |
| N-A8 | N7 | 「多暴露口径属同一科学问题的互补编码，非独立终点族」 | **逻辑跳跃——本攻击最核心的节点**：原文从未说明三类暴露是「互补编码」；这是 AI-A 的推测性解释。该推测直接决定了 Q2 的回答方向：如果是「同一假设的互补编码」，则多重比较压力小；如果不是，则可能构成独立的假设族。原文没有提供任何关于预设假设族的说明。AI-A 将推测当作结论，且标注为「逻辑跳跃」却仍保留在决策树中作为 N2→N7 的理由——这是将不确定推测嵌入主链的严重问题。 | 原文引言：「This study examined how longitudinal eGDR variations are related to stroke incidence across all stages」——这是科学意图的表述，但未说明三类暴露是「互补」还是「独立」假设。 | 二选一：(a) 删除 N7 或降级为「推测」标识；(b) 或改为「原文未区分假设族——三类暴露的关系未定义，多个口径并行呈现需考量是否为探索性分析」。当前表述不可接受。 | 高 |
| N-A9 | N8 | 「Supp Cox/MI 扩展同一关联问题」 | Cox 验证作用未明确（同 N-A3）；MICE 是对缺失协变量的处理而非「扩展同一关联问题」——MICE 后的分析仍是同一模型，只是纳入补全后的数据。AI-A 将「敏感性」写作「扩展同一关联问题」有过度解释之嫌。 | Supp Table S3/S4：MICE 后 Cox/logistic 回归，模型设置与 Table S1 相同。 | 修正为：「Supp 的 Cox/MICE 复现主析分析，验证结论稳健性」。避免使用「扩展」一词。 | 低 |
| N-A10 | N2 | 聚类实验——四类对比是否使用多重比较校正 | 图 2B/2C 的 k-means 聚类最好有稳定性检验（如 bootstrapping）；AI-A 未检查 IV 是否提及聚类数选择验证。AI-A 根本未评估「k-means 超参数选择」（如随机种子、初始中心）对结果的影响。原文使用肘部法（elbow method）确定 K=4，但未说明稳定性验证。 | 原文：「The optimal number of clusters was determined using the elbow method」——未提稳定性验证。 | 在决策树中增加对 k-means 的敏感性 / 稳健性分支（例如重新采样、改初始种子后是否仍然 K=4）。这是方法层面的重要缺口。 | 中 |

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E-A1 | N1 → N6（结论跳转） | AI-A 的 N1 确立「单一终点」后，N6 直接说「未报告多重比较校正」——但两者之间缺乏连接：即使单一终点，亚组×多暴露的检验数量仍然庞大。N1 应该与「多重比较压力分析」相连，而不是直接挂在 N6 上。 | 增加中间节点：「单一终点+多暴露编码+多亚组 → 检验空间=N(暴露类型)×N(亚组)×N(模型族)」，再连到 N6。否则 N1 的存在弱化了 N6 的紧迫性。 | 高 |
| E-A2 | N2 → N7（暴露→推测） | N7 是推测性解释（见 N-A8），却作为 N2 的存在理由。N2（事实）→N7（推测）的推理链污染了主链。 | 移动 N7 到「推测/讨论」分支，不作为 N2 的直接因；或改用「暴露多元性→多重比较问题」的直接原因链。 | 高 |
| E-A3 | N5 → N6（亚组→多重比较） | N5 的亚组分析涉及多组检验，但 AI-A 未说明检验总数，使 N5→N6 的推理缺乏量化支持。 | 补充：亚组数量（8 组）、每组的交互 P 检验次数、每组的暴露编码对比次数，计算大致检验族规模，再支撑 N6。 | 中 |
| E-A4 | N3 → N8 | N8 标注为「Supp通扩展同一关联问题」，但 N3 的 logistic 主模型与 Supp 的 Cox/MI 的关系不完全是「扩展」——Cox 同时承担验证 OR 近似度的功能（见 N-A3）。 | 修正边语义：N3→N8 应为「验证性扩展」（Cox 验证 OR 假设 / MICE 验证缺失数据处理）。 | 低 |
| E-A5 | N0 → N1/N2 分支 | Q2 问的是「多亚型/多终点/多层暴露」，N0→N1 的分支将「多终点」问题收窄为「单一终点」——但 Q2 中「多终点」的提问本身就预设了「可能有多个终点」的潜在情况。AI-A 仅通过确认单一终点来回答多终点维度，忽略了对「为什么」的解释（即该研究设计为何只选卒中作为唯一终点，是否可能遗漏其他终点如心梗）。 | 增加对「终点选择的合理性 / 为何未采用复合终点」的讨论节点；若原文未展开，则明确标注「原文未解释」。 | 中 |

## 4. Evidence Problems

1. **N4 证据位置混乱**（Fig.3 vs. Supp Fig.S1）：正文与 Supp 区分不清晰。将 Supp Fig.S1 标注为 Fig.3，属于引证错误。修正为 Supp Fig.S1，并注明是补充材料而非正文图。
2. **N5 证据位置混乱**（Table3 与 Supp S2 混标）：正文没有 Table 3。亚组分析实际位于 Supp Table S2（Cox 亚组）和 Fig.S2/S3（HR/OR 亚组）。需要重新定位。
3. **N6「未报告」的不可证实性**：AI-A 以「原文未报告」作为 limitation 的证据，但「未报告」本身是负命题，无法绝对证明。N6 的证据状态应标注为「推断」，而非「原文证据确认」。更稳妥的说法是「原文未描述多重比较校正程序」。
4. **过度维持在「E1」的定位**：E1 标注为「Abstract/Table2」——实际主终点在 Abstract（stroke），但 Table 2 在正文大概率不存在（正文的 Table 1 为基线特征，结果表是 Supp Table S1）。AI-A 的 E1 定位表可能也是 Supp 表误标为 Table 2。需核查。
5. **N7 推测的证据空白**：N7 使用的「互补编码」概念完全没有原文依据——这是 AI-A 的注脚式解释，不是原文观点。该 claim 没有 evidence_location 可填，说明其非原文内容。

## 5. Missing Branches

1. **缺失分支：未检查 k-means 的稳定性和聚类数选择的敏感性**。AI-A 完全忽略聚类方法的稳健性讨论（如有无 bootstrap 验证、K=4 是否稳定）——这是方法层的重大遗漏。即使原文未做，也应标注「原文未检验聚类稳定性」作为分支。
2. **缺失分支：多终点的替代讨论**。Q2 问「多终点」，但 AI-A 只回答了「单一终点的确定」，未考虑原文是否记录其他潜在终点（如心梗）而不作为主要分析。检查原文确认无其他终点后，应明确：「本文仅有卒中终点，其他终点（心梗/心血管死亡等）无从考量」。
3. **缺失分支：交互检验的 → 探索性 vs. 确认性分类**。交互揭示了亚组差异可能存在的 CKM 分期（stage 0-2 vs 3-4）变量选择，可能反映作者的先验假设。5/8 个亚组中 CKM 分期的交互显著与否，决定了亚组分析是探索性还是预设性。AI-A 未讨论。
4. **缺失分支：未讨论转换的「P 值阈值」是否为预设**。原文「P<0.05 双边」可能是预注册（无）或无预注册的单边阈值的默认。AI-A 未考察。

## 6. Required Fixes

1. **【高】修正 N7**：删除「互补编码」推测表述或以「推测」明示隔离，不允许将推测作为主链理由。改为：「原文未定义三类暴露之间的关系；从设计看，k-means 聚类包含聚类数与 k 个类别数的预设决策（K=4 经肘部法），连续累积暴露测量是独立回归——两者属于同一假设还是不同假设未说明」。
2. **【高】修正 N6 的证据状态与置信度**：从「high + 证据不足」改为「medium confidence + 推断」。统一为：「原文 Methods 仅声明双边 P<0.05 阈值，未描述任何族误差校正（Bonferroni/FDR 均未提及）。补充材料中大量亚组与敏感性检验提示检验总数大，但真实的多重比较风险无法从原文完全量化」。
3. **【高】修正 N1 的语义**：明确「单一终点」≠「无多重比较问题」，增加中间节点说明检验空间的构成。
4. **【中】修正 N4 和 N5 的证据位置**：N4 指向 Supp Fig.S1，N5 指向 Supp Table S2 + Supp Fig.S2/S3，去除不存在的「Fig.3」「Table3」指称。
5. **【中】修正 N2 的暴露编码描述**：明确三分位是敏感性分析的一部分（不在主分析中），且类别对比（k-means 4 类）的非独立性有特殊的多重比较含义。
6. **【中】增加 N6 的量化基础**：补充检验数量估算——约 8 个亚组 × 每亚组 3 类暴露（必要时分开处理） × 3 个模型（Model 1/2/3）的检验数目估计。
7. **【中】新增 k-means 稳定性的分支标注**：原文未汇报聚类稳定性（如 bootstrap），在决策树方法层标记该假设。
8. **【低】修正 N3/N8 边语义**：Cox 的作用不仅是敏感性验证，还验证 rare disease assumption 下 OR/HR 近似度的有效性。修改为「Cox 验证 OR 近似有效性；MICE 验证缺失数据处理稳健性」。

---

**对可行动建议的总结**：在 AI-A 修订版中，请优先处理 N7（推测污染）、N6（证据不足与表述）、N1（单终点≠无多重比较），并补齐证据位置、检验数量估算和 k-means 稳定性分支。