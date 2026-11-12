<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-11-12T14:47:19 | request_id=msg_da44c84e-fb88-4b2a-a171-5f1381ad4779 | usage={"input_tokens": 20870, "output_tokens": 6846, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=13733 -->
# AI-B Tree Attack

## paper_id: paper_42898695
## question_id: Q4
## review_target: @rounds/A_tree_round1_paper_42898695_Q4.md
## source_file: adversarial_lit_reading/chunks/paper_42898695_t2dm_mimic_eicu.md

---

## 1. Attack Summary

**总体判断：部分可信（需重大修改）**

**主要问题：**

AI-A 决策树整体框架正确（PS匹配 + 双重稳健结局模型），且对原文核心方法（PS固定协变量、DR调整、LMM、敏感性规格）的还原基本准确。但存在**五个关键问题**：

1. **N16 分支过度推断**：AI-A 将「\|SMD\|>0.10 变量入 DR 模型」解释为「半规则半数据驱动」，但原文并非如此——这是**匹配后数据驱动的结果介入设定**，而 AI-A 将其描述为「数据驱动成分」过于温和，且未能点明这是**post-matching, pre-specified rule** 的矛盾。
2. **N4 逻辑跳跃**：从「暴露例数有限」推导到「用双重稳健而非扩 PS」，原文确实写明，但 AI-A 未点出这是**设计选择而非被迫**——扩 PS 虽受限，但可减少匹配变量或换用其他匹配方法，作者只是选择了一条路径。
3. **N2 因果风险披露不足**：AI-A 虽然提到 eGFR/SOFA 为暴露后测量，但未将其**标注为因果结构问题**（overadjustment/collider bias），而原文在 Section 2.4 和 4.1 中明确讨论。AI-A 将 N2 标记为 high confidence 缺乏对因果风险的 caveat。
4. **N12 死亡模型叙述不完整**：原文明确指出「调整全部 20 个残余不平衡协变量产生完全分离」，AI-A 虽然提及但未说明**实际报告的死亡模型是否仅用匹配设计（条件logistic/GEE）而未做多变量调整**——这是重要缺失。
5. **E6/E10 证据映射粒度不够**：AI-A 将「八种规格」放在一个节点，但没有区分**哪些规格是主分析的必要稳健性，哪些是探测性**（如 log 变换 vs. 随机斜率 vs. RCS），下游用户无法据此判断每个规格在证据链中的权重。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A-N1 | N1 | 「PS 匹配协变量为固定临床名单（非 UV-p 筛选）」 | 描述正确但不够精确：原文确实写明5变量（年龄、BMI、男性、24-h SOFA、day-1 eGFR），但 AI-A 未突出「匹配在**库内**进行」这一跨库可比性决策的含义（severity scoring 不可比） | ✅ 原文 Section 2.4 支持 | 补充「匹配在库内进行」及原因（severity scoring 不可比性） | 低 |
| A-N2 | N2 | 「eGFR 入模因对照药肾功能禁忌差异；SOFA 作严重度」 | **因果结构问题未标注**。eGFR 和 SOFA 均为暴露后测量，原文 Section 2.4 明确承认 overadjustment 和 collider bias 风险，并在 4.1 讨论。AI-A 将其纯化为「临床先验」选择，忽略了原文自己的质疑 | ✅ 原文 Section 2.4 + 4.1 支持 | 在 N2 下补充「作者自认 eGFR/SOFA 为部分暴露后测量，存在 overadjustment/collider bias 风险，主规格保留为可比性」 | **中** |
| A-N3 | N3 | 「库内 1:3 最近邻、无放回、logit-PS、卡钳 0.25 SD」 | 准确，但未指出**原文未写匹配是否带替换的细节**——虽写 no replacement，但卡钳 0.25 SD 是标准做法，AI-A 未标注这是原文明确说明还是推断 | ✅ 原文 Section 2.4 明确「without replacement」「caliper of 0.25 standard deviations」 | 建议标注「原文明确」而非推断 | 低 |
| A-N4 | N4 | 「暴露例数限制 → 用双重稳健而非扩 PS」 | **逻辑跳跃**：原文说「With 116 exposed patients, the number of covariates a propensity model can support is limited, so residual confounding was addressed by doubly robust estimation」——这不是「因为限制所以用 DR」，而是「因为不扩 PS，所以用 DR 解决残余混杂」。AI-A 表述模糊，未区分「PS 模型保持精简」这一决定与「DR 用于解决残余混杂」的先后关系 | ✅ 原文 Section 2.4 支持 | 重写为：「PS 模型保持 5 变量精简（暴露例数有限），残余混杂通过双重稳健结局模型解决，而非扩大 PS 协变量」 | **中** |
| A-N5 | N5 | 「结局模型额外校正来源库、共病、并用降糖药、day-1 实验室等」 | 准确，但未指出原文 Section 2.4 列出的 DR 调整集是**预先指定**的（Methods 列出），而 Results 3.1 还提到「每个 \|SMD\|>0.10 的变量也带入」——AI-A 的 N5 没有区分这两层来源 | ✅ 原文 Section 2.4 + 3.1 | 拆分为：N5a（预设 DR 调整集）与 N5b（匹配后 SMD 闸门，见 N16） | **中** |
| A-N6 | N6 | 「匹配后 \|SMD\|>0.10 变量带入结局模型；Love plot/Table1」 | 正确但未标明「这是 Results 中的事后声明，且与 Section 2.4 预写规则的关系需要澄清」——是否有变量同时在预设 DR 集和 SMD 闸门内？原文未明确说 | ✅ 原文 Results 3.1 明确 | 补充：需对照 Section 2.4 预设 DR 集与 Results 3.1 SMD 闸门是否有重叠（AI-A 的 U1 已提出此问题，但未在 N6 标注） | 低 |
| A-N7 | N7 | 「病程/HbA1c/他汀等未测 → E-value 量化」 | 准确，但 AI-A 未标注 E-value 在 ALP 信号上的具体取值（2.49）及**置信区间跨越 1 的事实**——原文 3.3 已澄清 E-value 保护的不是统计显著关联（因为 CI 含 1）。AI-A 泛化为「量化未测混杂」但未说明该方法的局限是该研究中 E-value 的保护对象本身不显著 | ✅ 原文 Section 2.5 + 3.3 | 补充：E-value 应用于 ALP 信号（点估计保护值 2.49），但因置信区间含 0，E-value 的解读受限——AI-A 应标注「原文 EHR 的 E-value 结论仅适用于明确的点估计」 | **中** |
| A-N8 | N8 | 「LMM：group×day 交互为轨迹主关注项」 | 正确，但 AI-A 未指出原文明确「主结局是 bilirubin 轨迹，**ALP 是唯一被放在 FDR 族里的第二个分析物**」——N9 已经在旁边，但 N8 没有标注「主结局」不等同于「所有分析物都进入 FDR」。AI-A 的 N8 描述准确但与 N9 的逻辑顺序应更清晰 | ✅ 原文 Section 2.3 + 2.5 | 补充：主结局 = 总胆红素轨迹；ALP 仅在 FDR 族作为第二个分析物 | 低 |
| A-N9 | N9 | 「BH-FDR 仅限胆红素+ALP 族；其余探索」 | 正确，但 AI-A 未指出原文**还做了**「cross full set of tested trajectory outcomes」的敏感性 FDR——即虽然主分析只对两分析物做 FDR，但补充材料报告了对所有轨迹应用 BH 的结果。AI-A 的「其余探索」表述不精确 | ✅ 原文 Section 2.3 | 补充：主分析 FDR 限于两分析物族，但补充报告了「full set」FDR 敏感性 | 中 |
| A-N10 | N10 | 「敏感性规格含对 day 的 RCS、随机斜率、log 变换、DR 调整等」 | 准确但**未区分「规格的层次」**：原文将「log 变换 + 线性 day」列为主规格的变体，而「随机斜率」「分类 day」「RCS」是改变协方差结构/时间形式的敏感性。AI-A 将这些并列，但下流节点需要知道哪些规格是本研究的「核心稳健性」，哪些是「边界测试」 | ✅ 原文 Section 2.5 列出九种规格 | 建议标注层次：指定层次（log vs raw, DR adj vs non-DR）+ 协方差结构层次（随机截距 vs 随机斜率）+ 时间形式（线性 vs 分类 vs RCS) | **中** |
| A-N11 | N11 | 「多规格与 IPOW/完整测量子集等敏感性报告」 | 正确但遗漏**关键限定**：原文明确 ALP 信号在 IPOW 下点估计更大但精度降低（p=0.166），且「仅限至少 3 次测量」保留显著，「仅限存活出院」则不显著。AI-A 将「IPOW/完整测量子集」并列而未标注这些分析的方向性结果 | ✅ 原文 Section 3.2 明确 | 补充：区分「稳健保留」（log/log-DR/source-adjusted）与「不稳健」（IPOW/限制随访/限制存活） | **中** |
| A-N12 | N12 | 「死亡用匹配设计下的条件 logistic / GEE Poisson」 | 正确但**严重遗漏**：原文表明「调整全部 20 个残余不平衡协变量的模型产生完全分离且未解释」——AI-A 虽然提及但未点明这是**死亡率结论的证据缺口**：原文报告的死亡率（RR 1.56 / OR 1.74 / GEE 1.55）均为**未做协变量调整的匹配设计分析**，而非 DR 调整模型。AI-A 应明确指出这一点 | ✅ 原文 Section 2.5 + 3.3 | 补充：明确「调整型死亡率模型因完全分离未报告，报告的是匹配设计下未调整协变量的估计」 | **高** |
| A-N13 | N13 | 「无注明日期的 SAP；主结局「拟合前指定」不可独立核实」 | 准确且保守，但 AI-A 未指出**原文在 Section 2.3 明确说明**「primary outcome and the two-analyte family were specified before models were fitted, but this cannot be independently verified」——AI-A 正确地标注为「不可核实」，但未点出「作者声明」vs「可验证」的区分，这在 Q4 的「预先指定」问题上很关键 | ✅ 原文 Section 2.3 | 保留，但建议区分「作者声称」与「可验证证据」 | 低 |
| A-N14 | N14 | 「非主族轨迹、复合指数、死亡标为探索性」 | 正确但 AI-A 未指出**「探索性」标签及其对 Q4 的含义**：如果结局是探索性的，那么「预先指定」的压力也相应更低——AI-A 未在 N14 上给出这一推理 | ✅ 原文 Section 2.3 + 4.1 | 补充：「探索性结局的协变量筛选要求低于主结局」的推理链 | 低 |
| A-N15 | N15 | 「未见 UI-p 入模 / DAG / VIF / LASSO/逐步」 | **需复查原文**：AI-A 声明「未见」，但从我审阅的 chunk 看，原文确实未出现这些 термины。但 AI-A 应标注这是「该筛选策略的 absent 证据」，而不是「不存在该策略」——AI-A 的 N15 高置信度但未区分「未提及」与「明确不使用」 | ✅ 从 chunk 看未见 | 标注为「原文未明确说明，不能等价于「不使用」；但如果 Method 描述完整，可视为「非该策略」」 | 低 |
| A-N16 | N16 | 「最终 DR 调整项是否全部预锁定 vs 按 SMD 数据驱动——原文写了规则但部分依赖匹配后 SMD」 | **逻辑跳跃严重**：AI-A 将「按其 SMD 闸门」与「数据驱动」等同，但原文的规则是**预定义**的——「|SMD|>0.10 的变量带入 DR」是 Methods 中明确写出的规则，**不是事后按数据挑变量**。AI-A 把「按 SMD 结果决定哪些变量入模」混淆为「数据驱动」，过度推断 | ✅ 原文 Methods 2.4 写「pre-specified DR set」，Results 3.1 写「every \|SMD\|>0.10 carried into DR」 | 重写：区分「预定义 SMD 闸门规则」（尽管应用结果依赖匹配后数据）与「事后数据驱动选变量」；AI-A 应改述为「原文提供了预定义规则（SMD 闸门），但规则的应用结果依赖匹配后数据」 | **高** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| A-E1 | N1 → N4 | 「变量进入」（N1）→「if暴露n有限」（N4）之间缺乏「暴露例数限制」的逻辑来源。AI-A 的边逻辑是因果性的：「因为暴露 n=116，所以不扩 PS」——但这只是原文给出的**解释**，并非「如果 n 够大就会扩 PS」的如果-那么逻辑。原文从未写「如果 n 够大我们会扩 PS」，这是 AI-A 的**因果重构** | 改为「N1 → N4 due_to」（与 N4 → N5 paired），不是 if-then 而是 because-of | **中** |
| A-E2 | N13 → N16 | 从「无 SAP」推导到「DR 调整集部分是数据驱动」（N13 → N16）存在**逻辑跳跃**：原文 Section 2.4 明确列出预设 DR 集 + Results 3.1 列出 SMD 闸门规则——两者都是 Methods 预写的。AI-A 将「SAP 缺失」与「DR 调整集可能是数据驱动」关联，但原文 2.4 的规则本身是预定义的 | 切断 N13 → N16 的直接因果，改为「N0 → N16 直接询问」，并在 N16 内部区分「预定义规则」与「规则应用的数据依赖」 | **高** |
| A-E3 | N0 → N15 | AI-A 将 N15（未见 UV-p/DAG/VIF/LASSO）标为 limitations 连接到根问题 N0——这合理但过度：未提及 ≠ 不存在。原文 2.4–2.5 的 Methods 描述足够详细，如果连 UV-p 都没提到，更可能是「非该策略」而非「漏报」。AI-A 应降低置信度 (high) 明确改为「未提及，可能非该策略」 | 添加限定：「Methods 描述充分但未提及上述变量筛选方法 → 强烈提示非该策略」 | 低 |
| A-E4 | N8 → N9 | 从 LMM 模型「group×day 交互」到「BH-FDR 仅限两分析物族」的边 `supported_by` 是站得住的，但 AI-A 未标注**主结局与 FDR 族的关系**——FDR 族包括 bilirubin（主结局）和 ALP（第二分析物），不是「两分析物族」这样一个无差别集合。该边应有更多因果说明（为什么是这两个？因为可能的两条生物学路径） | 补充「主结局指定在先，ALP 作为第二分析物进入同一 FDR 族」 | 低 |
| A-E5 | N10 → N11 | 「八规格」（N10）到「敏感性报告」（N11）的边是 `supported_by`——但 AI-A 未**区分「规格」与「敏感性分析」**：原文有 8 种规格（specifications）+ 4 种观测缺失敏感性分析（IPOW、≥3测量、存活出院、截断第4天）+ 2 种暴露定义敏感性（仅入院前）+ 2 种 PS 敏感性（去 eGFR、去 eGFR+SOFA）。AI-A 的 N11 将「IPOW/完整测量子集」与「多规格」并列，但它们是不同层级 | 将 N10/N11 边拆为「规格的敏感性报告」与「观测缺失的敏感性报告」两路 | 中 |
| A-E6 | N12 无入边 | N12（死亡模型）直接连到 N0（根问题），但 N12 在原文中与 N8/N10 的轨迹模型是**并列而非从属**；AI-A 将其放在 if 后面不错，但**没有从 N4（残余混杂）→N12（死亡模型调整）** 的连接，导致下流用户无法看到「死亡模型尝试调整但失败」这一重要失败节点 | 增加 N4 → N12 边（残余混杂处理在死亡模型中的失败：完全分离） | **中** |

---

## 4. Evidence Problems

### 4.1 证据位置错误 / 误引用

| problem_id | AI-A claim | evidence location | problem | severity |
|---|---|---|---|---|
| P1 | N10 标为「方法」high confidence，证据定位至「Section 2.5」 | 原文 **Section 2.5** 确实列出九种规格 | 误将「规格列表」标为单一证据——实际上原文既有 Methods 的规格枚举，又有 Results 3.2 的规格执行结果报告。AI-A 的 evidence_summary 未区分「规格声明」与「规格执行」 | 低 |
| P2 | N7 evidence 定位至「Section 2.4–2.5」 | 原文 Section 2.4 列出未测变量清单 + Section 2.5 写明 E-value 方法 | location 正确，但 AI-A 的 E-value 在 mortality 上的具体应用（3.3：点 E-value = 2.49，置信区间限值 E-value = 1.00）与轨迹上的应用方式不同——未区分 | 中 |
| P3 | N16 标为「logic jump」，evidence 定位至「Section 2.4 + 3.1」 | 原文 Section 2.4 预写 DR 集规则；Results 3.1 报告 SMD 闸门应用 | AI-A 引用这两个位置**正确**，但其解读（「半规则半数据驱动」）**过度**——将「参数由数据决定」与「选择规则本身是 pre-specified」混淆 | **高** |
| P4 | E8 定位「Section 2.3 Outcomes + 2.5」 | 原文 Section 2.3 写「No dated SAP…primary outcome…specified before models were fitted, but this cannot be independently verified」 | location 正确——但 E8 与 N13/N14 关联时，AI-A 将「no dated SAP」与「主结局拟合前指定但无法核实」并列，**未区分「没有 SAP」与「主结局声明不可核实」是两个独立的证据点** | 低 |
| P5 | E6 引用「另八种规格」但未含「七种」的完整列表 | 原文 Section 2.5 写「five further specifications」之后又列出 3 种，共 8 种（加上 log变换线性day共九种） | 正确但需要更精确——原文说「each was refitted under eight further specifications」之后列了 (i)–(viii)，加上主规格共九种。AI-A 的「另八种规格」**数量正确**但未指出「八种」是 `further than primary`，而不是总数 | 低 |

### 4.2 偷换概念（Conflation）

| problem_id | AI-A claim | conflated with | explanation | severity |
|---|---|---|---|---|
| P6 | N10「敏感性规格含对 day 的 RCS」 | RCS 在 N10 是「敏感性」→ 但原文只是将该规格列为 nine specifications 之一，**并未明确标注「敏感性」vs「主分析」的优先级**。AI-A 将其归为「敏感性」是合理的推断，但原文从未使用「敏感性」一词描述这些规格 | 需标注 AI-A 的「敏感性」标签是**推断**而非原文术语 | 低 |
| P7 | N4「用双重稳健而非扩PS」→ 被 AI-A 连接至 N5「DR 结局模型校正」 | AI-A 将「不扩 PS」与「DR 调整」**连接**为因果链（N4→N5），但原文只说「so residual confounding was addressed by doubly robust estimation」——这是同一段中的解释，AI-A 的链接没有错，但需确保读者理解这一因果关系是**设计选择**而非**逻辑必然** | 在 N4→N5 边上标注「原文 stated correspondence」而非「因为→所以」 | 低 |
| P8 | N15「未见 VIF/LASSO/逐步」→ AI-A 将该「未见」视为「筛选逻辑缺失」的证据 | **「未报告」≠「未执行」**。虽然原文 Methods 详细且很可能完整，但 AI-A 将其标为「uncertainty」并对下游用户提示「原文未说明」——这合理。但 N15 的 risk_tag「证据不足」可能误导下流模型认为「有潜在缺失」，而非「原文未提及即大概率未执行」 | 将 risk_tag 从「证据不足」改为「原文未提及，按方法描述完整性推断大概率未执行」 | 低 |
| P9 | N9「BH 仅两分析物族」→ 被连接至 N0「Q4: 模型形式/预指定」 | AI-A 将 BH-FDR 作为「建模逻辑」的一部分，但 BH 是**多重比较校正**，不是协变量筛选或模型规格。放在 Q4 树中需要明确：FDR 是「推断逻辑」而非「建模逻辑」 | 在 N9 附近增加「注：BH-FDR 属于推断校正，不属于协变量筛选/模型形式」 | 中 |

---

## 5. Missing Branches

| missing_id | missing branch | importance | evidence from原文 | suggested addition | severity |
|---|---|---|---|---|---|
| M1 | **完全分离导致死亡模型未报告调整估计** | 该分支是「死亡模型」叙述的重要缺口 | Section 3.3：「A model additionally adjusting for all 20 residually imbalanced covariates produced complete separation against 62 events and was not interpreted」 | 添加节点：N17「调整型死亡模型因完全分离未解释；报告的是匹配设计下未调整协变量的估计」 | **高** |
| M2 | **ALP 信号的 three-way dependency** | AI-A 只说了「ALP 信号脆弱」，但未分解原文的三个依存条件：(a) 依赖线性 day 项，(b) 依赖随机截距-only 结构，(c) 依赖含 eGFR 的 PS 模型 | 原文 Section 3.2 + 4.1：「The effect is located specifically in the linear day term of a random-intercept-only covariance structure」「the contrast does not survive omission of eGFR」 | 添加节点：在 N11 下方细化「ALP 信号的三个依存条件」 | **高** |
| M3 | **MELD-Na 的探索性与非肝解读** | AI-A 未提及 MELD-Na 虽然在轨迹层面显著，但被原文解读为「severity signal rather than hepatic」——对 Q4 来说，这是「变量进入模型后错误解读」的风险案例 | 原文 Section 4：「MELD-Na is a function of bilirubin, INR, creatinine and sodium; with the bilirubin term null, the divergence necessarily arise from the renal/coagulation/electrolyte components」 | 添加：N18「MELD-Na 复合指数显著但被解读为严重度信号而非肝损伤」 | 中 |
| M4 | **双敏感性：暴露定义敏感性** | AI-A 只提到「暴露例数有限」，但未包含暴露定义敏感性（pre-admission vs admission-recorded）对结论的影响——即「暴露测量不确定性」作为协变量/暴露定义的变异性 | 原文 Section 2.2 + 3.1：「A sensitivity analysis restricts exposure to records documented before admission…reported for primary and ALP outcomes」 | 添加节点：N19「暴露定义敏感性（限入院前暴露记录）是结论可信度的关键检验」 | 中 |
| M5 | **缺失分层**：性别/族裔/年龄的亚组分析 | AI-A 未提及原文声称无法做性别分层（Section 4.1「The exposed arm was too small for a sex-stratified analysis」）——这不是「变量筛选」分支，但对 Q4 下游用户有价值：如果 n 太小导致无法分层，也应考虑「建模决策的可行性约束」 | 原文 Section 4.1 | 添加节点：N20「暴露组太小无法做性别分层——亚组分析不在本设计范围内」 | 低 |
| M6 | **跨库异质性与 leave-one-out** | AI-A 的 N11 提及敏感性但未涵盖「跨库异质性」这一敏感性的重要维度——如果用户在 Q4 下关注「来源库」作为协变量的角色，需知道 eICU/MIMIC/NWICU 的贡献与 leave-one-out 的作用 | 原文 Section 3.2：「no single database reached significance in isolation…statistical significance of pooled estimate depended on inclusion of MIMIC-IV」 | 添加节点：在 N11/N5 之间补充「来源库作为协变量 + 跨库异质性/leave-one-out 是主结论的依赖条件」 | 中 |
| M7 | **E-value 的实际取值与应用限制** | AI-A 的 N7 泛化了 E-value 策略但未给出原文中的具体数值和限制——E-value 点估计 2.49 vs 置信区间 E-value 1.00（因为 CI 含零） | 原文 Section 3.3：「An unmeasured confounder would need an association of at least 2.49…the corresponding E-value for the confidence limit is 1.00」 | 在 N7 或新增节点中补充 E-value 的具体取值与「CI 含零时 E-value 保护的不是统计显著的关联」的限制 | 中 |
| M8 | **MIMIC-IV 的 30/90 天死亡率仅限 MIMIC** | AI-A 的 N12 未提及 30/90 天死亡率的数据库限制（仅 MIMIC-IV）及其不可代表性（「MIMIC-IV patients were older and had higher in-hospital mortality」） | 原文 Section 3.3：「Thirty- and 90-day mortality were therefore assessed in MIMIC-IV only」 | 在 N12 下补充：30/90 天死亡率为 MIMIC-only，样本量为 35/105，不代表整个匹配队列 | 中 |

---

## 6. Required Fixes

1. **【高】修改 N16**：移除「半规则半数据驱动」的表述。重组为：「Methods 预定义了 SMD 闸门规则（|SMD|>0.10 入 DR）与预设 DR 调整集；规则的应用结果依赖匹配后数据，但**选择规则本身是 pre-specified**，不能等同于事后数据驱动选变量。」同时断开 N13 → N16 的直接因果边。

2. **【高】补充 N12 的调整失败分支**：添加节点或修改 N12 的 evidence 位置，明确指出「调整全部 20 个残余不平衡协变量的死亡模型产生完全分离且未解释；实际报告的死亡估计（RR 1.56/OR 1.74/GEE 1.55）均未调整协变量」。这一缺失会误导下游用户以为「匹配 + 条件 logistic/GEE 是充分调整」。

3. **【高】补充 ALP 信号的三个依存条件**：在 N11 下方新增一个「依存性」节点，拆分「线性 day 项」「随机截距-only 结构」「含 eGFR 的 PS 模型」三个具体条件，并标注每个条件的原文敏感性证据。

4. **【中】修改 N4 的表述**：从「if exposure n有限 → 用 DR 而非扩 PS」改为「PS 保持精简（暴露例数有限）→ DR 用于解决残余混杂」，避免「因为→所以」的因果过度推断。

5. **【中】E6 证据分级**：将八种规格按层次重组而非并列——指定层次（log vs raw, DR adj vs non-DR）、协方差结构（随机截距 vs 随机斜率）、时间形式（线性 vs 分类 vs RCS）。并标注 N9 的 BH 是「推断校正」而非「建模逻辑」。

6. **【中】补充 E-value 细节**：N7 下应标注 E-value 点估计（2.49）与置信区间 E-value（1.00）的差异，以及「CI 含零时 E-value 不保护显著关联」的限制，避免下游用户误读 E-value 的作用。

7. **【中】简化证据表映射**：N5 拆分为「预设 DR 调整集」与「SMD 闸门」两层；N10/N11 引用区分「规格声明」与「规格执行」。避免多重证据堆叠在一个节点。

8. **【低】标记 N15 的推断性质**：将 「未见 UV-p/DAG/VIF/LASSO」 标注为「原文 Methods 详尽但未提及上述方法 → 大概率未执行，但不能严格排除漏报」，而非「证据不足」。

9. **【低】完善 N2 因果风险披露**：在 N2 下增加「eGFR/SOFA 为部分暴露后测量，作者承认 overadjustment/collider bias 风险；主规格保留为跨库可比性 —— 敏感性分析去掉这两个变量后 ALP 信号消失，需标注」——这将 N2 与后续敏感性建立联系。

---

> **攻击完成**：共 9 条节点攻击、6 条边攻击、9 条证据问题、8 条缺失分支、9 条修复建议。