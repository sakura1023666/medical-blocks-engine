<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-19T11:19:09 | request_id=msg_1aad5e42-c738-489a-89a1-2b51ffdaba40 | usage={"input_tokens": 23770, "output_tokens": 4490, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=8301 -->
# AI-B Tree Attack

paper_id: paper_004
question_id: Q1
review_target: @rounds/A_tree_round1_paper_004_Q1.md
source_file: adversarial_lit_reading/chunks/paper_004_ewas_new.md；补充材料 Methods（docx 抽取）

## 1. Attack Summary

总体判断：**需要重大修改**

主要问题：
- 树结构混乱：N0 的问题被自己的分支（N1→N2→N3）反复回答，N5/N7 的 question 节点没有真正拆分出多条分支（age/sex 分层是否数据驱动的问题被 N6 中位数切点回答，但没有任何分支处理了「切点 60 岁是否出自结果而非 Methods」的核心判断差异）
- N8 的 evidence 只写了「每 IQR 的 OR」和「RCS P-nonlinear=0.348」，但 AI-A 在 Provisional Answer 里写的是「主分析假设每 IQR 的对数优势比可线性解释」——这里把「报告每 IQR 的 OR」偷换成「假设线性」，对应问题 3 是**重大误读**
- 重要证据缺失：没有把「轻/中/重程度数据在正文中的唯一一次出现」与「分析时合并为二分类」连起来（E1 引到了 Methods 2.2，但树里 N11 limitation 的逻辑是「原文未把轻/中/重作为有序结局主分析」，而原文确实在 2.2 里写了合并，这个 limitation 更像 AI-A 在替原文立一个未说出的目标）
- N1「全 Methods 无 K/BIC/轮廓系数」，证据位置是「Methods 全文无」——这种空证据（absence of evidence）没有定义搜索范围，也没有说检查的版本/页，无法证实

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A-01 | N1 | 「类别数不是聚类/LCA 选出」 | 这是「没有证据」的结论。AI-A 没有定位到 K/BIC/轮廓系数在论文中可能出现的所有位置（正文+补充材料），用「Methods 全文无」作为证据本身不可证伪。而且「无数据驱动定类」和「研究者先验指定」是两个不同命题，N1 把前者当后者在回答 | 正文 2.2 只给了 CDC/AAP 的分类定义，没有给 K、BIC 或轮廓系数；但 AI-A 无法排除补充材料中（docx 抽取）是否出现这些字眼 | 把 N1 改为「无证据表明做过聚类定类；结构化分类为 CDC/AAP」；证据位置标注「Methods 2.2 + 补充材料阅后未见」，严重度中 | **中** |
| A-02 | N6 | 「ERS 高/低=中位数切点，研究者指定」 | 切点在 Methods 2.5 确实写明「dichotomized into high/low ERS groups based on median value」。但 AI-A 的树没有把「中位数切点」与「是否数据驱动」直接关联——中位数切点本身是数据驱动（由样本分布决定），只是这不是「定类」意义上的数据驱动。N6 的结论「研究者指定」与原文「based on median value」矛盾 | 2.5: 「Participants were dichotomized into high/low ERS groups based on median value」 | N6 改称「ERS 二分切点为样本中位数（数据驱动），但分组数（高/低两组）为研究者先验」；原 N6 将「切点来源」与「组数来源」混为一谈 | **高** |
| A-03 | N8 | 「主分析按 IQR 线性对数优势比；RCS 检验非线性且未拒绝线性」 | 原文 2.5 写的是「报告 ORs per IQR increase」，这与「假设线性」**不是一回事**。报告每 IQR 的 OR 不隐含线性假设；而 RCS 的结果（P-nonlinear=0.348）是**事后诊断**，不是先验假设的检验。AI-A 将「报告方式」偷换成「分析假设」，又把「RCS 诊断结果」等同于「预先假设线性」，涉及两个逻辑跳跃 | 2.5 只写「report odds ratios per IQR increase」；3.5 写「RCS analysis revealed no evidence of nonlinearity (P for nonlinear=0.348)」——原文并没有说「我们假设线性」 | 将 N8 拆成两个节点：N8a「主分析报告每 IQR 的 OR（不必然隐含线性假设）」与 N8b「RCS 检测到非线性证据不足（P-nonlinear=0.348）」；不要把「线性」作为主分析预设 | **高** |
| A-04 | N2 | 「结局为先验二分类，轻中重合并」 | 原文 2.2 用 CDC/AAP 分类后合并为「有牙周炎 vs 无」，合并规则在 2.2 写清楚。但「先验」指向不明：CDC/AAP 是定义「轻/中/重」的结构，合并发生在分析之前；因此「先验」应指「在建模前已定」，而非「研究者任意指定」。N2 与 N6 的区别没有在树上表达 | 2.2: 「participants were categorized as having periodontitis (mild, moderate, or severe) or non-periodontitis」 | 明确「先验=建模前已固定」；把「研究者指定」限于「分组数 2」，「组内程度（轻/中/重）由 CDC/AAP 定义」 | **中** |
| A-05 | N5 | 「年龄/性别分层是数据驱动吗？」 | N5 是 question 节点，但它的后继只有 N6（且 N6 是 ERS 的分组切点，**与年龄/性别分层无关**）。年龄切点 60 的来源（Results 3.4 给出、Methods 未论证）没有被单独讨论，N5 → N6 的边是错位的 | Results 3.4 明确写了「more...among men (25 toxicants) and individuals younger than 60 years (32 toxicants)」；Methods 没有为 60 提供先验理由 | 把 N6 从「ERS 中位数二分」改为「年龄/性别分层切点来源」；把 ERS 二分另设节点 | **高** |
| A-06 | N11 | 「原文未把轻/中/重作为有序结局主分析」 | 原文 2.2 确实只用了二分类，但「未做有序主分析」不等于「原文默认可做有序主分析却被忽略」。N11 的 limitation 是 AI-A 替原文立了一个目标（有序分析）再指出原文没做到，这是稻草人 | 2.2 只写到合并分类；Results 没有任何有序模型 | 删除 N11，或在 N11 里明确「有序严重度在正文既未定义为主结局，也未在结果部分报告」并标注高不确定性 | **中** |

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| A-07 | N1 → N2 | N1「无数据驱动亚型/聚类 K」→ N2「结局为先验二分类」：这是两个独立事实。N1 是「没有 K」，N2 是「用二分类」。没有 K、用二分类，不能推出「分组是研究者指定」，因为 CDC/AAP 是外部诊断标准，不是研究者自己的选择。这个边把「外部标准定义」说成「研究者主观」，逻辑跳跃 | 改为「外部诊断标准（CDC/AAP）定义三分类；分析时合并为二分类」；「研究者主观指定」这个标签删除 | **高** |
| A-08 | N2 → N3 | N2「结局为先验二分类」→ N3「合并规则写明」是 supported_by：确实支持「合并规则」这一事实，但 N3 的 evidence 并没有回到 N2 里「先验」一词。N3 能证明「合并」，不能证明「先验」，边在证明强度上不匹配 | 在 N3 的 evidence summary 里加一句「2.2 无『因缺乏统计功效而合并』或类似说法」；否则 N2 与 N3 之间只能标注「支持合并规则，不支持先验性」 | **中** |
| A-09 | N7 → N9 | N7「是否预先假设线性或 U 型？」→ N9「WQS 假设混合物分位同向加权，不是 U 型搜索」：N9 讲的是 WQS 的方法假设（混合效应同向），与「单暴露的剂量-反应形态」是两回事。WQS 的「同向」指的是混合物中每个组分权重非负，而不是说暴露-结局关系是线性或 U 型。这条边把「混合物成分同向」与「剂量-反应线性」混淆 | 删掉 N7→N9，或把 N9 改写成「WQS 作为互补混合物方法，不回答单一暴露的形态问题」；把 WQS 放在「补充分析」分支而非「形态假设」分支 | **中** |
| A-10 | N7 → N8 (leads_to) | N7「是否预先假设线性或 U 型？」→ N8「主分析按 IQR 线性对数优势比；RCS 检验非线性且未拒绝线性」：N8 的 evidence 没有回答「预先假设」这个问题。RCS 是事后诊断；「每 IQR 报告 OR」是报告格式。这条边的 leads_to 语义不成立 | 在 N8 的 claim 里明确「原文未声明先验形态假设；RCS 是诊断性分析，非检验先验假设」 | **高** |
| A-11 | N1 → N10 | N1「无聚类定类」→ N10「检出限二分类是测量规则，不是疾病亚型」：N10 的原文内容是毒物处理，与「疾病亚型数」无关。这条边把「暴露变量的二分化（因检出限）」与「结局变量的分组」混淆，属于概念偷换 | 删除 N10，或在树上标注「该证据属于暴露处理，不属于结局先验分组」 | **低** |

## 4. Evidence Problems

| problem_id | evidence_id (AI-A) | problem | detail | severity |
|---|---|---|---|---|
| E-01 | E1 | 位置准确，但解读过度 | E1「牙周状态按 CDC/AAP：重/中/轻定义后，分析时合并为『有牙周炎 vs 无牙周炎』二分类」——原文 2.2 只写了「mild, moderate, or severe」合并为「periodontitis or non-periodontitis」，没有「重/中/轻」三个等级的详细阈值在 Methods 2.2 全文给出。AI-A 把「分类定义」写进 E1，但 E1 的 evidence_summary 里没有标明「轻/中/重」的 CAL/PPD 阈值在 2.2 的哪一段，引用不精确 | 建议 E1 明确「严重/中度/轻度定义在 2.2 给出，合并规则在同段尾句」 | **低** |
| E-02 | E2 | 引用位置不准确 | E2 标注「Methods 2.1 / Fig.1」，但原文 Fig.1 在 Page 2 的图注里没有列出 n=1210 的每一步排除数字，Methods 2.1 写了「final sample of 1210 participants」。AI-A 把「n=1210」归给「Methods 2.1 / Fig.1」两个位置，但 Fig.1 本身（正文部分）只显示流程图，没有数字说明 | 建议 E2 只保留「Methods 2.1」；如引用 Fig.1 需指明图注 | **低** |
| E-03 | E4 | 证据缺失「未加权」细节 | E4「ERS 按中位数分为高/低两组；连续 ERS 另报每 IQR」——原文 2.5 同时写了 ERS 关联分析用「weighted logistic regression」，但 AI-A 在 E4 里没有记录「加权」这一限定。对于「ERS 高低分组是否受抽样权重影响」的问题，这是关键信息 | E4 加「ERS-periodontitis 关联用加权 logistic 模型（Model 1 未调整，Model 2 调整协变量）」 | **低** |
| E-04 | E6 | 只写了 WQS 参数，漏了关键限制 | E6「WQS：分位数=4，bootstrap 1000；作为混合物互补分析」——原文 3.7 写明 WQS 与 ERS 结果互相印证，但 WQS 本身「各组分权重之和=1、权重非负」的约束在 Methods 没有明确写出。AI-A 的 E6 没提「权重非负」这一事实，而它恰恰与「是否假设同向效应」直接相关 | E6 补充「WQS 默认权重非负，即假设组分效应同向」；并在树中标注「该假设在原文 Methods 未明确说明，来自 gWQS 方法默认」 | **中** |
| E-05 | E5 | evidence 位置与 claim 不匹配 | E5「主关联报每 IQR 的 OR；RCS 3 结点检验 ERS 非线性，P for nonlinear=0.348」——这里把「RCS 检验非线性」和「主关联报每 IQR」作为一条证据，但这两者回答不同的问题。RCS 的证据在 Results 3.5，「每 IQR」在 2.5。合并为一条 evidence 导致后续节点（N8）引用时区分不了哪一半在支撑哪句话 | 拆成 E5a（2.5: 每 IQR OR 报告惯例）与 E5b（3.5: RCS 3 结点，P-nonlinear=0.348） | **中** |
| E-06 | E1 (N11 使用) | N11 以 E1 为「逻辑跳跃」的锚点但 E1 不能支撑 limitation | N11「原文未把轻/中/重作为有序结局主分析」依据 E1（Methods 2.2），但 2.2 只是定义了分类与合并；未报告有序模型 ≠ 未作有序模型 ≠ 未考虑。E1 无法支持「limitation」的结论 | N11 的 evidence 标注为「Results 3.1–3.7 未设有序模型小节」并结合全文搜索「ordinal」「proportional odds」 | **中** |

## 5. Missing Branches

| missing_id | missing_branch | why it matters | suggested addition | severity |
|---|---|---|---|---|
| M-01 | **轻/中/重三分类是否曾被用于任何敏感性分析或描述性统计** | 原问题 1 问「预设了几个分组」，如果轻/中/重只在定义时出现、从未参与任何分析，则「预设分组数量」本质是「1 个二分类结局 + 1 个三分类定义（未进入下游分析）」。AI-A 的树没有把「定义中出现但分析中未使用」这一状态区分出来 | 增加分支：`N3e →? 轻/中/重是否进入任何下游分析（描述/敏感性/亚组）→ 否 → 结论：轻/中/重仅用于定义，不构成分析中的分组` | **高** |
| M-02 | **WQS 的权重非负约束未在原文 Methods 明确** | 原问题 3 问「是否假设了暴露-结局关系的方向」，WQS 的「同向」假设是重要的「方向」假设，但它在原文 2.5 只写了「设置分位数=4、bootstrap=1000」，没有描述权重非负。AI-A 的 N9 断言 WQS「不是 U 型搜索」是正确的，但没有指出「WQS 默认同向，这本身就是一种方向假设」 | 增加分支：`N9 → 注：WQS 权重非负 → 同向假设 → 这不是 U 型搜索但确实是方向假设`以覆盖「方向」问题 | **中** |
| M-03 | **RCS 的 knot 位置与自由度** | 原文只在 2.5 写「restricted cubic splines with 3 knots」；AI-A 的 N8 引用了 P-nonlinear=0.348，但没有把「3 knots 是最小可检验非线性的设置」这一限制纳入。对于「未检测到非线性」这一结论，3 knots 只允许一个拐点，不能排除 U 型（需要 ≥4 knots 才能捕捉两个拐点） | 增加分支：`N8 → 限制：3 knots 仅捕捉单一拐点；不能排除更复杂形态（如双谷）` | **中** |
| M-04 | **年龄切点 60 的来源没有单独分支** | 原问题 2 问「数量是数据驱动还是研究者主观指定」，年龄分层切点 60 在 Results 3.4 出现（「individuals younger than 60 years」），但 Methods 没有说为什么是 60。AI-A 的 U1 提到了这一点，但树上没有为「切点来源」设计分支 | 增加分支：`N5 → age cut 60 来源 → Methods 无先验声明 → 不确定（可能为常规分组） ` | **中** |
| M-05 | **没有讨论「暴露方向」与「结局方向」的区别** | 问题 3 的「暴露-结局关系的方向（线性/单调/U 型）」被 AI-A 只解读为「剂量-反应形状」；但原问题也可能指「暴露→结局 vs 结局→暴露」的方向性问题（反向因果）。原文确实在 Discussion 承认「cross-sectional design...cannot rule out reverse causality」。AI-A 的树完全没有处理这个维度 | 增加分支：`N0 → 方向性含义1（剂量-反应形态） vs 含义2（因果反向）→ 反向 → 原文 Discussion 4 承认反向因果不可排除 ` | **高** |

## 6. Required Fixes

1. **拆分「报告每 IQR OR」与「假设线性」**：N8 必须改写为「原文主分析采用每 IQR OR 的报告惯例（2.5），不必然说明线性假设；RCS 3 结点（3.5）是诊断性分析，P-nonlinear=0.348 不支持非线性，但未证明线性」。高严重度。
2. **修正 N6 的分组逻辑**：把「ERS 中位数二分＝组数先验、切点数据驱动」写清楚；年龄分层切点 60 的来源单独设节点（M-04）。
3. **删除/重写 N5 → N6 边**：N5 的 age/sex 分层问题不能由 ERS 中位数切点回答；把分层切点问题独立出来。
4. **拆 E5 为 E5a/E5b**：让 N8 引用 E5b（3.5 的 RCS），E5a 单独用于描述报告惯例。
5. **增加 M-01 分支**：明确轻/中/重定义只出现在 Methods 2.2，从未进入下游分析，这是「预设分组数量」问题的关键限定。
6. **增加 M-05 分支**：处理「因果反向」维度，引用 Discussion 对反向因果的承认。
7. **N1 的「无 K/BIC/轮廓系数」改为「未见 K/BIC/轮廓系数字样」**，并注明检索范围（正文+补充材料 docx），避免空证据表述。
8. **N10 从 N1 分支中移除**，或明确标注「暴露处理规则，不回答结局分组」。
9. **删除 A-06 的 N11 limitation**，或改写为「原文未报告有序模型，但这不等于原文遗漏；建议查阅补充材料确认是否存在」。