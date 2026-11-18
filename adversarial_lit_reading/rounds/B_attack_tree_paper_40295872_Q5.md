<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-11-03T11:34:34 | request_id=msg_ecdea96e-dd1c-4381-9ff7-a41c9b930e57 | usage={"input_tokens": 19865, "output_tokens": 4813, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 768, "prompt_tokens_details": {"cached_tokens": 768}} | char_len=10150 -->
# AI-B Tree Attack

paper_id: paper_40295872
question_id: Q5
review_target: @rounds/A_tree_round1_paper_40295872_Q5.md
source_file: adversarial_lit_reading/chunks/paper_40295872_jin2025_shr_sofa_af_mortality_cardiovasc_diabetol.md

## 1. Attack Summary

总体判断：**部分可信，需要重大修改**

主要问题：决策树整体框架覆盖了 Q5 的核心维度（PH 假设、非线性、缺失、加权、预测工具假设），但存在多处**证据推断过度、因果误读、术语概念偷换**。最关键的三处：N3 将「Methods 声明 validated」等价为「PH 假设满足」存在跳跃；N7 将「MAR 假设 + MissForest」等同于「规范多重插补」存在过读；N11 对 nomogram 的「logistic vs Cox 似然不同」论述在原文证据基础上无法完整支撑。此外，**N14 对 tertiles/quartiles 与 SOFA median/cutoff=5 的冲突标记为「逻辑跳跃」过重**——两者可能并不矛盾（摘要先用 quartiles 后文用 tertiles 是前后不一致，但这是「表述不一致」而非「逻辑跳跃」）。缺失分支方面，决策树未覆盖**中介分析假设**（counterfactual 序贯可忽略性）与 **时依混杂/竞争风险**。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A1 | N3 | 「PH 假设用 Schoenfeld 残差验证」 | N3 声称「PH 假设使用 Schoenfeld 检验验证」，但原文 Methods 仅一句 `assumptions of proportional hazards were validated using Schoenfeld residual analysis`，**没有任何数值结果、违例变量清单或后续处理**。AI-A 将「Methods 声明已做」与「假设满足」之间画等号——这是**证据推断过度**。评分 `confidence=medium` 合适，但节点 claim 本身需加限定「Methods 声明已做，但无法独立核验 PH 是否满足」。 | 原文 Methods 确实提到 Schoenfeld（P4），但 Results 无对应数值 → **部分支持** | N3 claim 改为：「Methods 声明已用 Schoenfeld 验证 PH，但 Results 未报告检验结果，无法独立确认 PH 是否满足」 | **高** |
| A2 | N4 | 「Results 未给出 Schoenfeld P/违例变量 → 声明有、数值不可核」 | 这条**构述合理**，但问题在于 N4 是「limitation」类型节点却被 N3 的 `contradicted_by` 边连接。`contradicted_by` 表示证据间矛盾，但 N3 与 N4 并非逻辑矛盾——N3 是「Methods 声明」，N4 是「Results 未报告」，两者是**文本层面缺失而非矛盾**。 | 原文确实无 Schoenfeld 数值 → **支持** | N4 节点类型改为「uncertainty」或「missing_evidence」，而非 contradiction | **中** |
| A3 | N5 | 「非线性用 RCS 四 knots + 阈值似然比 P<0.05 后 piecewise Cox」 | N5 基本准确，但**「四 knots」的位置**未说明（原文也未说明 knots 所在百分位）。此外，threshold effect 检验的描述——原文是 `Significant threshold effects (P<0.05 by likelihood ratio test) were quantified through piecewise Cox regression`——AI-A 复述为「阈值效应用似然比检验 P<0.05 后做 piecewise Cox」，**准确**。但未指出该检验的**局限性**：threshold 检测易受 knots 位置影响。 | 原文 Methods P4「RCS with four knots」+「likelihood ratio test」→ **完全支持** | N5 可补充「knots 位置未说明」作为 caveat | **低** |
| A4 | N6 | 「Low SOFA 1 年非线性 NS」（P=0.168） | N6 引用的 P 值准确（原文 P4: `1-year mortality (P nonlinear=0.168)`），但 N6 作为 `claim` 类型节点，其表述「非线性结论依赖 SOFA 层与时点」**隐含了**「不同 SOFA 层、不同时点的非线性模式不同」这个更全面的结论，而 AI-A 只引用了 Low SOFA 1 年的 NS 作为例子。**需要补充 High SOFA 组持续 J 型（P<0.001）这一对称证据**。 | 原文 P4 支持 | N6 增加 High SOFA 各时点 P<0.001 的证据 | **低** |
| A5 | N7 | 「缺失：>20% 删变量；<20% MissForest，假设 MAR」 | N7 本身**准确**，但 AI-A 的 Evidence Map E6 标注了「两处重复」（Data extraction 与 Statistical analysis 都有描述），这是事实。但 N7 claim 的**危险**在于后续 N8 的解读——N8 说「原文未明确说明 m / 结局入模 / Rubin」，但 **N7 自身说「multiple imputation」并不等于规范 MI**，AI-A 在 N8 中应更明确区分「算法名称（MissForest）与推断框架（MI）的混淆」。 | 原文 P3-P4 两处描述一致 → **完全支持** | N7 应加 caveat：「MissForest 在 `missForest` R 包中是单次填充，原文'多重插补'的用词与 R 包默认行为不一致」 | **中** |
| A6 | N8 | 「插补 m、结局是否纳入预测矩阵、推断层是否 Rubin 合并：原文未明确说明」 | **这是决策树中最强的一条批评**，但 AI-A 给了 `risk_tag=方法误读`——这个标签**有误导性**。原文未明确说明这些细节不是「AI-A 误读」，而是「原文不透明」。应该标为「原文不透明 / 迁移需谨慎」而非「方法误读」。 | 原文确实未写 m、Rubin 合并等 → **完全支持** | 修正 risk_tag 为「原文不透明」 | **中** |
| A7 | N9 | 「非复杂抽样；无权重/PSU/分层估计」 | N9 判断**正确**——原文确实为 MIMIC-IV 单中心便利队列，未提及 survey 权重。但更精确的表述应是「**原文未提及任何复杂的抽样设计**」（而非「非复杂抽样」）。AI-A 将「未报告」等价于「不存在」——这在单中心回顾性队列的语境下可以接受，但严格来说**没有明确排除**设计权重的可能性（如 ICU admission 的选择概率）。 | 全文未出现 sampling weights → **支持** | N9 加「原文未提及 survey 设计」，删除「非复杂抽样」的绝对断言 | **中** |
| A8 | N11 | 「预测工具假设为 logistic 死亡概率（非 Cox 累积风险）」 | 这**正确**——nomogram 基于 multivariable logistic regression（P3 Abstract 和 P7 Results 均写明）。但 AI-A 的边 `N11 → N12 supported_by E11` 中，E11 标注了「bootstrap 校准（先后写 200 / 1,000 resamples）」。这里的问题：⑤ 原文虽然两处数字矛盾，但**E11 把它和 N12 连在一起**时，N12 的 confidence=high 有点过高——因为 calibration 次数不一致会影响校准质量评估。 | 原文 P4「200 resamples」vs P7「1,000 bootstrap resamples」→ **部分支持但存在矛盾** | N12 confidence 降至 medium，并标注两处数字冲突 | **中** |
| A9 | N13 | 「directed cyclic graph 路径未展示」 | **准确攻击点**。但 AI-A 的表述「cyclic graph（非常规 DAG 表述）」——原文确实是 `directed cyclic graph model`（P3），这可能是个笔误（应为 DAG），AI-A 指出来了。但 `risk_tag=证据不足` 是**保险的**。 | 原文 P3「directed cyclic graph」→ **支持** | 保留 | **低** |
| A10 | N14 | 「Abstract quartziles vs Methods tertiles；KM median vs cutoff=5」 | **AI-A 在这里过度解读了。** 摘要首句写 `stratified by SHR quartiles`，但 Methods 通篇用 tertiles——这是**摘要与正文的表述不一致**，但不构成「分层逻辑冲突」。SOFA「categorized at the median」（KM）与「cutoff=5」——SOFA 中位数是 4（Table 1），cutoff=5 并不等于 median！所以这两处确实**矛盾**——但 AI-A 的主语是「Abstract vs Methods」与「KM vs cutoff=5」，前者是表述错误，后者是切点不一致，**两者性质不同，不能混为一谈**。 | 原文 Abstract P1 quartiles；Methods P4 tertiles；KM P4 median；SOFA cutoff P4 = 5 → **部分支持** | 将 N14 拆分为两个节点：N14a（quartiles vs tertiles 表述不一致，severity=低）；N14b（SOFA median vs cutoff=5 口径冲突，severity=高，可能影响分组） | **高** |
| A11 | N15 | 「迁移须强制落盘 cox.zph 表；插补改 m=5+Rubin」 | **方法迁移合理**，但「引擎铁律」的表述带有规范性而非建议性——对用户研究的要求，如果用户的研究目标与原文不同（如描述性而非推断），此铁律可能不适用。 | 用户研究约束 | N15 加「若迁移为推断性研究」限定 | **中** |
| A12 | N16 | 「加权模板不适用；外验是第二库而非 survey」 | **判断正确**——eICU 外验 ≠ survey 设计。但 AI-A 将 N9→N16 的边标记为 `transfer_to`，**未在正文中说明为什么需要这个边界**。建议在 Provisional Answer 中补充一句「eICU 外验是外部验证而非加权推断」。 | 用户研究约束 | N16 加 brief justification | **低** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E1 | N3 → N4（`contradicted_by`） | 前面 A2 已指出：N3 是 Methods 声明、N4 是 Results 未报告，两者是「文本缺失」而非「逻辑矛盾」。`contradicted_by` 暗示两节点之间存在直接的不一致，但这里只是一个「未被验证的声明」与「未报告的数值」之间的差距。改为 `unverified_by` 或 `evidence_gap`。 | 将边关系改为 `not_be_verified_by` 或删除 contradiction 标记 | **高** |
| E2 | N1 → N3（`because`） | 「主推断=Cox PH」→「PH 用 Schoenfeld 检验」——这个 `because` 关系**逻辑合理**，但缺失了一步：**Schoenfeld 检验是 Cox 模型假设的验证方法**。AI-A 跳跃了「Cox 模型需要 PH 假设 → Schoenfeld 是其检验方法」这一推导。 | 在 N1→N3 之间插入注释节点「Cox PH 假设需验证」 | **中** |
| E3 | N5 → N6（`if`） | N5（RCS 方法）到 N6（非线性结论依赖 SOFA 层与时点）——`if` 的含义是「条件分支」。但 N6 说「RCS 不显著 → 不作阈值结论」——这其实是一个**后验**判断（基于 Results 数据），不是先验条件。N6 不是 N5 的 if-branch，而是「RCS 结果的时点/组间差异」这一 observation。建议改 `leads_to` 或 `informs`。 | 将 N5→N6 边关系改为 `leads_to` | **低** |
| E4 | N4 → N15 与 N8 → N15（`transfer_to`） | 两条边汇聚到 N15 本身没问题，但 N15 是「迁移约束」——它同时承接了「Schoenfeld 未落盘」（N4）与「MI 细节不明」（N8）两个**证据缺口**。问题在于 N15 是把两者合并成一条「迁移须强制……」的规则——这合理，但要明确「两个缺口对应两个不同的迁移操作」。 | 建议 N15 拆成 `N15a`（cox.zph 输出）与 `N15b`（MI 规范化） | **低** |

---

## 4. Evidence Problems

| problem_id | evidence | issue | suggested fix | severity |
|---|---|---|---|---|
| P1 | E2（N3） | AI-A 将「Methods 说 validated」直接用作 N3 node 的 `supported_by`，但 N3 的 claim 是「PH 用 Schoenfeld 检验」——这应该是**方法声明**而非「已满足」。E2 与 N3 之间缺乏「是否真正满足」的判别。 | 在 N3 下方加一个 `uncertainty` 子节点：「Schoenfeld 是否满足仅凭声明不可判」 | **高** |
| P2 | E6（N7） | AI-A 将 Data extraction 与 Statistical analysis 两处描述合并为一条证据，标注「双处重复」。但原文两处并不完全一致——Data extraction 说「Variables with 20% missing were eliminated」，Statistical analysis 说「Data with missing values exceeding a 20% threshold were excluded」。**用词差异**（`>20%` vs `exceeding 20%`）可能无害，但 AI-A 没有指出原文**并未说明**插补是对 Cox 模型使用前一次性完成，还是在每层模型中分别处理。 | 补充证据位置与跨层处理细节的说明 | **低** |
| P3 | E10（N12） | AI-A 的 E10 同时包含「bootstrap 200 resamples」与「1,000 bootstrap」两处数字——**但 E10 没有指出这两处的具体位置**（前者在 Statistical analysis 的 calibration 段，后者在 Results 的 Validation 段）。AI-A 在 Uncertainty U3 中确实提了「200 vs 1,000」，但 Evidence Map 的证据标注位置仅写了「Methods Statistical analysis + Results nomogram」——不够精确。 | E10 拆为 E10a（Methods calibration 200）与 E10b（Results validation 1000） | **低** |
| P4 | E11（N13） | AI-A 将「directed cyclic graph」描述为「非常规 DAG 表述」——这是解释而非证据。E11 的位置标注为「Methods」，若更精确应指向 P3 Data extraction 段。 | 精确定位至 P3 | **低** |
| P5 | E13（N14） | AI-A 的 E13 写「KM 'SOFA scores categorized at the median' 与 SOFA cutoff=5 并存——切点语义是否等同原文未明确说明」。AI-A 指出问题但没有指出**SOFA 中位数实际= 4**（Table 1）——也就是说**median 切点=4，而 cutoff=5** → 两者确定不等。AI-A 用「是否等同未明确说明」的措辞弱化了实际矛盾。 | E13 改为「SOFA median=4（Table 1）与 cutoff=5 不等——KM 分组与四分组定义逻辑不一致」 | **高** |

---

## 5. Missing Branches

| branch_id | missing_point | why it matters | suggested addition | severity |
|---|---|---|---|---|
| M1 | **中介分析假设**（counterfactual 序贯可忽略性） | 原文做 bootstrap 中介分析（P4），但未写**无中介–结局混杂、无暴露–中介交互**等识别假设。这是 Q5「关键参数假设」中的**重要遗漏**——Q5 不仅涵盖 Cox/RCS/缺失/加权，还涵盖中介分析。 | 新增节点 N17：`L4 uncertainty: 中介分析假设（序贯可忽略性/无未测混杂）未被原文检验` | **高** |
| M2 | **时依混杂与竞争风险** | 原文 1-year 死亡率随访 365 天，但未使用竞争风险模型（如 Fine-Gray）处理 ICU 出院竞争事件。MIMIC 出院后死亡可能受出院状态影响。 | 新增节点：「365 天终点未用竞争风险模型——可能存在随访偏倚」 | **中** |
| M3 | **Model 2 校正变量的时依性** | Model 2 校正了实验室值（如 bicarbonate），但原文未说明这些协变量是基线值还是时变值。Cox 若用基线值，时依混杂风险高；若用时变值，则需扩展 Cox。 | 新增 caveat 节点：Model 2 协变量时间口径（基线 vs 时变）未明确说明 | **中** |
| M4 | **样本量 vs 事件数（EPV）** | 1 年死亡 2598 例（Table 1），事件数相对充足；但在 65 岁以下亚组的事件数可能不足（原文 P6 提到「few underpowered subgroups」）。AI-A 未提及 EPV 在不同亚组的充分性。 | 可加更细亚组 EPV 的 note | **低** |
| M5 | **RCS knots 位置与敏感性检验** | 原文未说明四 knots 的百分位位置，也未做 knots 数量敏感性分析。RCS 结论可能对 knots 位置敏感。 | 加 caveat：原文未报告 knots 位置、未做敏感性分析 | **低** |

---

## 6. Required Fixes

1. **【高】修改 N3 claim**：将「PH 假设用 Schoenfeld 检验验证」改为「Methods 声明已用 Schoenfeld 验证 PH，但 Results 未独立报告检验数值 → PH 满足仅凭声明不可判」。同时将 N3 的 confidence 降为 low-medium。

2. **【高】拆分 N14**：N14a「quartiles vs tertiles 表述不一致」（severity=低，原文表述失误）与 N14b「SOFA median=4 vs cutoff=5 确实矛盾」（severity=高，影响 KM 分组与 Cox 四分组的分组逻辑一致性）。

3. **【高】修正 N3→N4 边关系**：从 `contradicted_by` 改为 `evidence_gap` / `unverified_by`。两者并非直接矛盾，而是文本声明与结果报告之间的差距。

4. **【中】新增 M1 中介分析假设分支**：Q5 问「该分析依赖哪些参数假设」——中介分析识别假设（序贯可忽略性、无未测混杂、无暴露-中介交互）是原文**完全没有检验**的假设，必须在迁移时打标。

5. **【中】新增 M2 竞争风险遗漏分支**：1 年死亡终点若无竞争风险模型，死亡概率可能被高估（ICU 出院后的死亡风险人群变化）。

6. **【中】修正 N8 的 risk_tag**：`方法误读` → `原文不透明/迁移需谨慎`。原文未说明 m、Rubin 合并等，是**原文作者**的不透明，而非 AI-A 的误读。

7. **【中】修正 N11→N12 的证据矛盾标注**：E10 仅标注「200 / 1,000 并存」不够精确——应在 Evidence Map 中拆为 E10a（Methods）与 E10b（Results），并指出「校准质量评估受 bootstrap 次数差异影响」。

8. **【低】修正 E13 证据位置**：精确到 Table 1（SOFA median=4）与 Methods（cutoff=5）→ 直接指出**切点不等而非「是否等同未说明」**。

---

## 7. Final Verdict

**决策树需要重大修改后方可迁移。** 核心判断（Cox+PH 声明、RCS 四 knots+piecewise、MAR+MissForest、非加权、nomogram=logistic）**均基本正确**，但存在三类系统性缺陷：

| 缺陷类型 | 实例 | 对结论的影响 |
|---|---|---|
| **推断过度** | N3「Schoenfeld 声明=PH 满足」 | 影响 N15 迁移规则的可信度 |
| **分类/标注错误** | N14「表述不一致 vs 切点冲突」未区分；N8 「方法误读 vs 原文不透明」未区分 | 影响严重度分级与处理优先级 |
| **覆盖遗漏** | 未覆盖中介分析假设、竞争风险、时依协变量 | 影响 Q5「参数假设」的回答完整性 |

**迁移到用户研究的最后一条建议**：在用户应用本文方法前，必须（a）落盘 Schoenfeld 的全局与逐变量 P 值；（b）明确插补的 m 与 Rubin 合并规则；（c）补做竞争风险模型；（d）检验中介分析的识别假设。否则本文的方法不构成「已满足 PH+缺失+shape 假设」的可迁移模板。