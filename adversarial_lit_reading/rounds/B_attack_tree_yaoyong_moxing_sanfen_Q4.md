<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-09T16:37:00 | request_id=msg_ac15a950-afa6-4a6b-8897-fbab98f735f2 | usage={"input_tokens": 12751, "output_tokens": 5514, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=11200 -->
# AI-B Tree Attack

paper_id: yaoyong_moxing_sanfen
question_id: Q4
review_target: @rounds/A_tree_round1_yaoyong_moxing_sanfen_Q4.md
source_file: adversarial_lit_reading/chunks/yaoyong_moxing_sanfen.md

## 1. Attack Summary

总体判断：**部分可信 / 需要重大修改**

主要问题：

- **高严重度**：N1 声称「非单因素 p / LASSO 驱动」，但用「未见描述」作为「否定存在」的证据（「No adjustments...」≠「No variable selection performed」），且 `all eleven potential confounders as shown in Table 1` 究竟是「全部 Table 1 中列出的变量」还是「Table 1 中所有潜在混杂」，原文存在解读空间。
- **高严重度**：N8（十一项 vs 九项不一致）方向正确，但 N6 将「敏感性多因素 Cox」当作「加性模型形式」的证据不充分——原文只说 `multivariable Cox regressions with the aforementioned risk factors`，没有明确说明是否含交互项，也未说明这是 **模型形式** 还是仅仅是 **敏感性策略**。
- **中严重度**：N3（SMD≤0.1 阈值）是平衡性诊断，不是变量筛选机制，树中把 N3 接到 N1→（because）N2 导致逻辑链混淆。缺失了关键的 **变量进入机制（IPW 中倾向评分的变量选择先验性）** 与 **STEPP 六参数选择的「人为性」** 的分析。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| B-N1-1 | N1 | 协变量进入以临床病理先验清单为主，非单因素p/LASSO驱动 | N1 将「原文未描述」当作「否定存在」：原文只说 "No adjustments were made for multiple comparisons"，而未说「未做变量选择」；且 `all eleven potential confounders shown in Table 1` 并不排除**在 logistic 内部做了某种筛选**（原文未报告步骤）；误用「类比」从「多重比较未校正」推断「无LASSO/逐步」。 | E6 只支持「未做多重比较」；E2 支持「预先列出变量清单」，但清单 ≠ 「无自动选择」；E1 的 `incorporating all eleven potential confounders` 是**叙述性**描述，不等于「没有选择」。 | 改写为：**N1 claim 应该表述为「原文未描述变量选择（LASSO/逐步/DAG/VIF）机制，但叙述上呈现『一次性纳入 Table 1 全部潜在混杂』的先验固定调整集」**；不要在「证据未提及」与「事实不存在」之间划等号。 | 高 |
| B-N1-2 | N1 | 入模以临床病理混杂集为主，非单因素p/LASSO驱动 | Q4 问的是「变量入模依据」：单因素 p 值、文献、DAG、VIF 哪个是依据？AI-A 说「临床病理先验清单为主」，但**原文没有交代清单的来源**——究竟是数据驱动（如表1中 p 值显著的变量被选入）还是文献驱动？原文只列变量清单，未说明为何选择这些变量、为什么排除另一些变量（如分子亚型未进 IPW 但进亚组）。 | E2 列出变量清单但**无选择依据说明**。 | N1 应加 `uncertainty` 标注，改为「原文未报告变量选择的依据（文献/临床/数据驱动），仅呈现 Table 1 预先列出的变量；分子亚型仅用于亚组而非 IPW”。 | 高 |
| B-N2-1 | N2 | 全部 Table1 混杂进 logistic 估 PS | 原文精确表述为 `incorporating all eleven potential confounders as shown in Table 1`——这里有两个问题：(1) **Table 1 中有多少变量？** 若把 cT 与 cN 分开，表格中有 11 个特征（含列联表形式），但 Table 1 的「变量」可能实际上是**类别变量（如年龄有3层）**，AI-A 的「十一项」= 11 个变量而非 11 个参数，需分清；(2) 原文未说明**是否加了任何自动选择机制**。且 N2 `because` N1 的关系不成立：N2 是 N1 的**证据**，不是 N1 的原因。 | E1: `all eleven potential confounders` 原文有；E2: 「study variables」是列出的基线特征，但 `eleven` 的计数**未被原文明示**（AI-A 是数出来的，不是原文直接写的）。 | N2 应注明 `eleven` 为 AI-A 读全文后计数**推断**的结果，非原文直接明示；「eleven」在原文出现于 p.3 Methods（`all eleven potential confounders`）与 p.4（`adjustment for eleven baseline characteristics`），而在 Results 变为「nine selected」，N2 应标注此张力的出处，不要把 N2 作为 N1 的**唯一原因**。 | 高 |
| B-N3-1 | N3 | IPW + SMD≤0.1 平衡诊断 | SMD≤0.1 是**平衡性检查（balance check）**，不是「变量筛选/建模逻辑」，Q4 问的是「变量如何入模」，IPW+平衡诊断回答的是「PS 如何被使用」，不是「协变量如何被选择」。N3 没有独立回答 Q4 的任一维度（进入依据/模型形式/变量选择）。 | E1 支持 SMD 平衡诊断存在，但没有回答「为什么选中这些变量进 PS」。 | N3 应从「方法」重构为「balance 诊断」分支，不直接回答 Q4；保留 SMD 作为 `IPW 流程的平衡性验证`，不要成为 N1→(because)→N2→... 链条的一部分。 | 中 |
| B-N4-1 | N4 | 亚组 IPW + 交互检查；不平衡则多因素 Cox 回退 | AI-A 的 `risk_tag` 标注为「方法误读」但实际没有严谨检查 E3/E7：Fig.3 caption 明确写「multivariable Cox regression based on imputed datasets was instead applied」，但 **Methods 说「missing values on baseline characteristics 被排除」**——这是自相矛盾的，AI-A 只将其当作「uncertainty」列在 U2，但没有在树中建立 `N4→limitation→N7` 的连接；且 N4 的 `fallback` 说法暗示是**预先设计的**，但原文是**事后发现不平衡才改**，不一定是分析前计划。 | E7 确实显示 imputed datasets；E3 的「rebalanced within each subgroup」后确实是 fallback。但原文**没有**说这个 fallback 是分析前预先指定的。 | N4 应增加风险标注 `fallback 的预先指定性无法确认`，并附加分支到 N7（作为 limitation）或新增节点「subgroup fallback 的计划性未知」。这个改动会影响 Q4 的「是否分析前预先确定」的结论。 | 高 |
| B-N5-1 | N5 | STEPP 六参数 Cox 加性构分 | AI-A 称「加性构分」——原文确实写了 `summing the model parameter estimates`，所以「加性」有证据，但问题在于：**六参数的选择标准是什么？为什么是 age/pT/HR/ERBB2/cT/cN，而不包含 grade / ethnic / Charlson / diagnosis year？** AI-A 已把这放到 U4（uncertainty），但没有在树节点中标注这个「选择」是分析前设定的还是 STEPP 方法默认参数。且「复合风险」是用 Cox 构的，但它是**用于分层/滑动窗**的，不是「变量选择方法」，N5 在对 Q4 的回答中应避免把 STEPP 当作「变量入模逻辑」来呈现。 | E4 支持六参数被使用，但没有支持这些参数的**选择依据**；文献引 [21-23] 可能提供 STEPP 参数标准，但原文没有展开。 | N5 应添加 `风险标注：六参数选择依据未知（是否分析前预设的 composite risk 未说明）；且应删除「加性构分」的确定性表述，改为「原文描述通过 summing 参数估计得到 composite risk」`。补充迁移：STEPP 的复合风险构建范式与新用户的变量选择问题**不完全对应**。 | 中 |
| B-N6-1 | N6 | 敏感性=多因素 Cox 加性校正（非 IPW） | (1) 原文 p.3 的敏感性分析描述是 `with the aforementioned risk factors (i.e., adjustment for eleven baseline characteristics)`，**这是灵敏度的描述**；而 Results p.5 突然写 `nine selected risk factors`——AI-A 的 N8 指出了这一点，但 N6 的 claim 里「加性校正」**(1)** 原文没有说「加性、无交互」；(2) `nine selected risk factors` 中的 `selected` 是可疑的：它暗示了一种**选择机制（虽然是「selected」但那可能只是措辞）**，不能轻率地把它归为「非自动选择」；(3) N6 的 risk_tag「方法误读」没有点出**具体**误读了什么——AI-A 自己没意识到 N6 在回答 Q4 时混淆了「敏感性分析（模型验证）」与「模型形式（加性/交互/RCS）」两个不同层面。 | E5 确实指向方法与结果不一致；但 N6 `加性` 的 claim 原文没有说「加性、无交互」。 | N6 改为「敏感性分析=多因素 Cox（原文未明确模型形式、未说明'加性'；且九项 selection 过程不明）；「加性」一词应删除或标注为**推断**；`nine selected` 的 `selected` 一词需要特别标注（可能暗示有选择机制）。 | 高 |
| B-N7-1 | N7 | 未见 DAG/VIF/RCS/LASSO/逐步；多重比较未校正 | (1) 把「未见」与「不存在」等同是严重问题：原文 Methods 只详细写了主要流程，很多细节在**补充材料**（Supplementary）里，AI-A 只看了 chunks（可能是全文，但也可能漏了补充材料）——「未见报告」只能说明「在当前本文中未明确呈现」，不能断言「未做」；(2) 多重比较未校正这点的定位不准确：N7 是 limitation 节点，但它也承载了 Q4 的「是否预先确定」问题的部分回答——「未调整多重比较」不等于「未预先确定建模逻辑」。 | E6 中 `No adjustments were made for multiple comparisons` 可以支持「未校正」，但它没有说「没做任何变量选择」。E8 的完整病例取向支持「缺失直接排除」的推断，但 Methods 并没有明确写 `complete-case only`，只是排除维度这样描述。 | N7 拆分为两个节点：N7a「未报告 DAG/LASSO/VIF/RCS/逐步——不等于不存在，补充材料未知」；N7b「多重比较未校正（已明示）」。不要把「未报告」当「没做」。 | 高 |
| B-N8-1 | N8 | Methods 十一 vs Results 九，原文未说明如何选 | N8 本身是有效的 `uncertainty` 节点，但位置不对：(1) AI-A 把 N8 接到 `N6 → if → N8`，暗示「若敏感性是 Cox 则出现不一致」——这个 edge 太弱，更合理的做法是把 N8 直接提升为 **核心不确定性** 放在 N6 旁级；(2) N8 的 `severity` 没有标「高」——它是最可能的学术严谨性攻击点，应标为高。 | E5 确实支持「Methods 十一 vs Results 九」的张力。 | N8 的 `severity` 标为高，建议把 N8 从 `if` 连接改为独立的不确定性分支（N8 直接连接 N0 或 N6 平级）。 | 中 |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| B-E1-1 | N1 → because → N2 | N2 是 N1 的证据，不是 N1 的逻辑因为（`because`）。「入模以临床病理清单为主」不会「因为」「PS 用十一项混杂估」而成立——N2 是 N1 的**支撑**，不是 N1 的**原因**。应改为 `supported_by`。 | 把该边从 `because` 改为 `supported_by`。 | 高 |
| B-E2-1 | N1 → leads_to → N3 | N3（IPW+SMD 平衡诊断）并不由 N1（变量进入逻辑）推出：SMD 是平衡性诊断，是 IPW 流程的一环，不是变量选择的结论。 | 删除该 `leads_to` 边，改为 `N2 → leads_to → N3`（PS 估计完成后做平衡诊断），或在 N3 前新增「PS 估计」节点。 | 中 |
| B-E3-1 | N0 → leads_to → N4 | 亚组 IPW 与交互检验确实存在于原文，但该节点与 Q4「变量入模」的关联未建立：亚组分析是在回答「治疗效应异质性」，而不是「变量如何被选入模型」。 | 在 N4 前新增一个分支（如「Q4 相关维度：治疗×特征异质性评估」），或把 N4 降级为 context 不直接回答 Q4。 | 中 |
| B-E4-1 | N6 → if → N8 | N8 并不由 N6 的「敏感性为多因素 Cox」**条件性**产生；N8 是**贯穿 Methods 与 Results 的口径不一致**，适用于 N2、N6、N7 等所有涉「名单」的节点。 | 把 N8 从 `if` 改为 `limitation`（N6 → limitation → N8）或直接平级于 N0。 | 中 |
| B-E5-1 | N7 → supported_by → E6 | E6 中「No adjustments were made for multiple comparisons」是**原文明确陈述**，但 N7 的 claim 里「未见 DAG/VIF/RCS/LASSO/逐步」不是 E6 能支持的——E6 只支持「未校正多重比较」这一项。AI-A 在此用一条 evidence 支撑了多个不同内容。 | 拆开 E6 支持的节点内容：E6 支持「多重比较未校正」；「未见 LASSO/逐步/DAG/VIF/RCS」需要新的 evidence（或标注为「对原文与补充材料全文检索后的 **absence** 推断」）。 | 高 |

---

## 4. Evidence Problems

1. **「No adjustments...」≠「No variable selection」**：原文方法段落末尾的 `No adjustments were made for multiple comparisons` 是在说明统计检验的校正策略，不是变量选择的说明。AI-A 用它来支撑「未见 LASSO/逐步/DAG/VIF/RCS」是过度推断。N7 需要的证据是「AI-A 阅读补充材料后仍未发现这些方法的描述」，而非「原文在道义上宣告自己未做这些调整」。

2. **N2 中「全部 Table 1 混杂进 PS」**：原文 `incorporating all eleven potential confounders as shown in Table 1` 确实在 p.3 Methods 出现，但 Table 1 里呈现的分类变量（如 Age、Ethnicity）多以类别层次而非单一变量呈现，`eleven` 是 AI-A 计数推断的结果。原文没有直接写「Table 1 中有 11 项」。这是「数出来的」而非「原文明示的」。

3. **N6 的「加性」缺乏支撑**：原文在描述敏感性分析时只说 `multivariable Cox regression` 与 `adjusted for eleven baseline characteristics`，没有说「加性、无交互」；AI-A 在 N6 的 claim 里直接用「加性」两字是对「Cox 通常默认加性」的领域经验套用，不是原文证据。

4. **「imputed datasets」的來源问题（E7）**：Fig.3 caption 中确实出现 `multivariable Cox regression based on imputed datasets was instead applied`，但全文 Methods 的 missing 处理策略是「排除缺失基线特征者」（Study cohort exclusion criteria），二者存在冲突。AI-A 在 U2 中标注了此不确定性，但 N4 的 confidence 仍标为 high——自相矛盾。如果一个证据在 U 中说明「原文未展开」，该节点不应同时保持 high confidence。

5. **对 N8 的 evidence 使用是合理但薄弱的**：E5 能支撑「Methods 说 eleven、Results 说 nine」的张力，但 N8 未引用 P5 描述「敏感性分析 with nine selected risk factors」具体所在哪一段。应精确到「Results 第一段，p.5, sensitivity analysis 部分」。

---

## 5. Missing Branches

| branch_id | missed branch | why it matters for Q4 | suggested fix |
|---|---|---|---|
| M-B1 | **变量进入的「先验性」无法确证** | Q4 直接问「该逻辑是否在分析前预先确定？」AI-A 只在 provisional answer 中以「叙述上像预先确定」带过，但缺乏系统分析：预注册（pre-registration）、SAP、NCDB 分析通常无预注册——应明确标注为「不可证实」。 | 新增一个节点 `N9`：「原文未使用预注册/SAP 语言，变量清单的'先验性'无法从文本确证；仅能从措辞 'as shown in Table 1' 推断是分析前固定」。 |
| M-B2 | **Table 1 与 PS 的变量映射关系** | N2 声称「全部 Table 1 混杂进 PS」，但 Table 1 有多个层级变量（如 Age 3级、Ethnicity 4类），logistic 中会编码为 dummy variables；「全部 Table 1 混杂」不一定是「全部 11 个变量」——需要确认原文表注是否为「11个变量」的明确说法。 | 节点 N2 加注 `uncertainty`：eleven 的计数是 AI-A 推断的，Table 1 中变量层级结构与「十一项」之间的映射需复查。 |
| M-B3 | **STEPP 的复合风险选择是否分析前预定** | 如果六参数是分析前预设的，则其「变量入模依据」来自 **方法文献（[21-23]）** 而非本文临床判断——这是 Q4 的重要回答维度。 | 新增分支在 N5 下：「STEPP 六参数的来源：原文引用 [21-23] 的 STEPP 步骤，未说明为何恰选这六项」。 |
| M-B4 | **「分子亚型 / cN」在 IPW 与亚组之间的不对称** | 原文 IPW 用了 Table 1 的十一项（包含 cT/cN），但**分子亚型（HR/ERBB2/grade 的组合）只在亚组分析中出现，不在 IPW 主模型中**。AI-A 的树没有捕捉到这个「模型间变量差异」。 | 应新增节点：N10「IPW 主分析未纳入分子亚型（由 HR 与 ERBB2 组合构成），亚组分析才涉及；原文未解释为何」。 |
| M-B5 | **缺失值处理（complete-case vs imputed datasets）** | Methods 的 exclusions（missing baseline 排除）暗示 complete-case 主分析；但 Fig.3 caption 说亚组 fallback 用 `imputed datasets`——这是 IPW 主分析的**补充材料**（AI-A 没看），说明 AI-A 的证据覆盖不完整：补料（supp）里可能有缺失值插补流程，对「变量入模」与「缺失处理」造成新的解读。 | 新增节点 N11：「主分析采用 complete-case（排除缺失基线的患者）；但 sub-analysis fallback 使用 imputed datasets（fig.3 caption）——原文未说明插补流程和是否需要分析前预设」。 |
| M-B6 | **cN2-3 亚组中 PS 的再用** | 原文在 cN2-3 亚组（N=511）报告 HR=0.55, P-interaction=0.024；亚组分析通常会用亚组内重新拟合 PS 或只用主模型 PS 权重——原文只说 `following the previously described methods`（p.3），未说明**亚组内 PS 是否重新估计**。这直接影响「变量入模逻辑」在不同层次的划分。 | 应在 N4 中标注：「亚组 IPW 是否用亚组内重估 PS 或沿用主 PS 权重——原文使用 'following the previously described methods' 模糊处理」。 |

---

## 6. Required Fixes

1. **【高 · 必须】** 将 N1 的用词从「非单因素 p / LASSO 驱动」修正为「原文未描述自动变量选择机制」（把「不存在」改为「未描述/未报告」），并显式在 risk_tag 中标注「absence of evidence ≠ evidence of absence」；在 provisional answer 的「是否预先确定」部分改为「原文未使用预注册/SAP 措辞，无法从文本确证 '预先确定'；只能从措辞（'as shown in Table 1'）推断为固定调整集」。

2. **【高 · 必须】** N6 删除「加性」这一未经证实的表述，改为「多因素 Cox（原文未明确模型形式含交互与否）」，并在 N6 的 risk_tag 中说明「`nine selected risk factors` 中的 `selected` 暗示可能存在选择机制——原文未说明」。同时将 N8 从 `if` 边调整为 `limitation` 边（N6 → limitation → N8）。

3. **【高 · 必须】** 修改边 B-E1-1：N1 → N2 从 `because` 改为 `supported_by`；修改边 B-E2-1：删除 N1 → N3 的 `leads_to`，改为 N2 → leads_to → N3。

4. **【中 · 需要】** 新增节点 N9（变量清单「先验性」不可确证）与 M-B4（IPW 未含分子亚型），分别回答 Q4 的「是否预先确定」与「变量清单的选择依据」两个子问题；同时将 N7 拆分为 N7a（未报告变量选择方法——不等于不存在，补充材料未知）与 N7b（多重比较未校正，已明示）。

5. **【中 · 需要】** N4 的 confidence 从 high 降为 medium，因为 Fig.3 caption 的 `imputed datasets` 与 Methods 的 complete-case 排除存在未解释的张力，而 N4 依赖 E7；同时新增 M-B5 节点（缺失值处理不一致性），将 N4 → limitation → N11 连接，并说明补充材料是验证该问题的关键。

6. **【中 · 需要】** N5 增加风险标注「STEPP 六参数选择依据未知（是否分析前预设不可确证）；加性表述应替换为原文措辞 'summing the model parameter estimates'」。

7. **【低 · 可优化】** N8 的位置移动（从 `if` 改为 `limitation`），并补充 E5 精确到 Results 第一段 sensitivity analysis 行；N3 加上「SMD 是平衡性诊断，但不是 Q4 所问的变量选择机制」的注释，且与 N2 独立编号。

8. **【低 · 可优化】** U4 提升到主树：STEPP 六参数与 PS 十一项的子集关系——如果这是刻意子集，那「变量入模依据」可能是「STEPP 文献惯例」而非「临床选择」——这直接影响 Q4 的第一个问题。建议在树中直接反映该讨论。

---

**备注**：本次攻击没有依赖原文之外的外部信息；`imputed datasets` 在 Fig.3 caption 中出现过但 Methods 未展开，AI-A 没有标记为「需结合补充材料复查」，此为其一主要疏漏。所有 evidence 均引用自输入 chunks 中可见内容。