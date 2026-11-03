<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-11-03T11:32:00 | request_id=msg_c3e3648f-8065-4182-8abc-e8792e7fde5d | usage={"input_tokens": 19718, "output_tokens": 5603, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=11019 -->
# AI-B Tree Attack

paper_id: paper_40295872
question_id: Q2
review_target: @rounds/A_tree_round1_paper_40295872_Q2.md
source_file: adversarial_lit_reading/chunks/paper_40295872_jin2025_shr_sofa_af_mortality_cardiovasc_diabetol.md

## 1. Attack Summary

**总体判断：部分可信 / 需要重大修改**

**主要问题：**

1. **多个节点存在过度解释原文的问题**——特别是 N1/N2 将「三个死亡时点」描述为「并行报告且摘要均称 primary」时，未能完全核实原文全部表述；N4 声称「分层暴露=三分位+器官二分+四组合在同框架复用三终点」实际上是对原文分析结构的一种推断性整理，原文中四组合分析（Q1-Q4）与三分位分析来自不同分层逻辑，不能简单归为「同一框架」。
2. **因果关系过度主张**——N9 将中介分析描述为「bootstrap 中介」，但未能区分原文中介分析是事后探索性分析还是预先假设检验；同时原文明确表示「retrospective design...precludes causal inference」，树中多处隐含因果主张与此冲突（如 N4→N6→N7 的推理链暗示暴露→结局的因果解释）。
3. **多重比较问题的处理过于绝对**——N11/N12 声称「未发现明确的校正表述」，但文中确实报告了亚组交互项不显著（Table S1-3），这至少暗示作者进行了交互检验，只是未报告校正方法；N12 直接推断「原文未明确说明校正」作为高置信度声明可能超出证据范围。
4. **证据定位不够精准**——部分节点（如 N7、N9）的证据定位含糊（"Results + Table S1–S3"），无法区分具体是哪个表格/图/段落支撑该节点声明。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| ATK-01 | N1 | 「三个死亡时点被并行当作主要终点族报告」 | 原文 Abstract 确实说三个时点为 primary endpoints，但正文 Results 中实际报告的顺序是院内、30天、365天，且数据来源（Death Master File）仅提及出院后 30 天和 365 天，院内死亡是住院期间记录的。N1 声称「并行报告」可能暗示三者在分析上被同等对待，但原文实际更偏向于将院内死亡作为主要、其余作为随访补充。 | 原文 P3：「The primary endpoints were in-hospital, 30-day, and 1-year mortality.”——确实有 primary 表述；但 Results 中对院内、30天、365天的讨论深度和篇幅不同。 | 修改为：「Abstract 将三个死亡时点（院内、30天、365天）并列称为 primary endpoints；但正文分析方法并未完全遵循同一优先级，可视为"并列主终点"（co-primary endpoints）但缺乏单一主终点裁定。」 | **高** |
| ATK-02 | N2 | 「方法: 院内 / 30天 / 365天 分时分析」 | 这是对原文方法的重述，但 N2 与 N1 的边界模糊。N2 被 N1 `because` 引用，但 N1 说的是「主张」，N2 说的是「方法」，两者逻辑关系是「主张 because 方法」——在这里，方法的描述不足以证明「三个时点被同等对待」这一主张，因为分时分析本身就是多时点分析的标准操作，不代表它们被同等看待。 | 原文确实是在三个时点上分别进行 KM、Cox、RCS 分析。但「分时分析」并不自动推出「同等对待」的结论。 | 将 N1→N2 的边类型从 `because` 改为 `context_of`（上下文关系），并明确指出：N1 的「primary共主/并列」主张需要额外的预先声明证据（原文只给了 Abstract 一句声明，不足够）。 | **中** |
| ATK-03 | N3 | 「证据: Study endpoint；终点定义与随访来源」 | 原文明确给出 30 天和 365 天的随访来源是 Death Master File，但院内死亡来源未具体说明（住院期间记录）。N3 作为证据节点本身准确，但它被 N1 和 N2 共同引用时，导致「三个时点=同等主终点」的主张被证据 E3 强化，而 E3 实际只提供了随访定义，并未证明三者被同等对待。 | 原文 P4：「Data regarding patient mortality post-hospital discharge was sourced from the United States Social Security Administration's Death Master File.」——原文只提到「post-hospital discharge」的死亡来源，院内死亡未说明来源。 | 在 N3 中增加限定：「院内死亡来源未明确，仅出院后死亡有 Death Master File 来源；这进一步说明三时点在数据采集上并不完全对等，不能无限制地为 N1 的‘并列主终点’主张背书。」 | **中** |
| ATK-04 | N4 | 「多层暴露=三分位 + 器官二分 + 四组合 在同框架复用三终点」 | 这个节点将三个暴露分层方案放在一起，暗示它们在分析框架中被对称复用于全部三个终点。但原文中三分位分析（Table 2 上半部分）和四组合分析（Table 2 下半部分）确实都报告了三个时点的 HR，但 KM 曲线（Figure S2）只画了四组合（Q1-Q4），三分位并未以 KM 展示。因此「同框架复用」的说法部分不准确。 | 原文 P6-7 + Table 2：三分位 SHR 和二分 SOFA 在三时点分别报告 HR；KM 只针对四组合。RCS 按 SOFA 分层。 | 修改为：「多层暴露结构（三分位/二分/四组合）在三终点上分别报告关联 HR，但 KM 生存曲线仅对四组合绘制；RCS 仅按 SOFA 层展示，未对三分位×时点横向完整展开。」 | **高** |
| ATK-05 | N6 | 「RCS 按时点×器官层分别拟合」 | 原图 Figure 1 的 RCS 确实分了三时点和 SOFA 低/高两组展示，但 AI-A 声称「分别拟合」——原文 Fig.1 分别展示了低 SOFA 和 高 SOFA 的 RCS 曲线，这一点是对的；但其「阈值效应」断言的依据是 likelihood ratio test P<0.05，这一点在回应中未标注。 | 原文 P7：「The adjusted RCS analysis revealed a varying dose response pattern of SHR on mortality among SOFA groups and at different time intervals」——但具体模型自由度（knots）等未在正文 Methods 给出（仅方法部分写 four knots；RCS 的 threshold 判定未见公式）。 | 建议在 N6 中增加：「RCS 阈值效应用 likelihood ratio test 判定 (P<0.05)，原文未报告具体的 knot 位置或每次检验的效应量。迁移时需注意 RCS 的多重比较问题由作者未处理。」 | **中** |
| ATK-06 | N7 | 「旁支: 临床亚组重复主排序; 交互不显著」 | 原文 Table S1-3 报告了亚组分析，并称「non-significant interaction terms」。但 AI-A 将这些交互检验作为「主排序一致性的验证」来引用，而这在原文中只是补充材料，未上正文表。是否经过多重校正也未提及。 | 原文 P7：「Subgroup analysis validated the consistent ranking of mortality risk across cohorts of myocardial infarction, heart failure, and renal failure, reflecting overall population trends with non-significant interaction terms (Table S1-3).」 | 修改为：「交互项未报告 P 值或置信区间，仅在补充表列出‘non-significant’字样，校正方法（是否调整过多重比较）不明——该节点不能作为强证据用于支持 N0 的'多层暴露是否会导致多重比较膨胀'这个核心问题。」 | **高** |
| ATK-07 | N9 | 「方法: 中介按三时点分别bootstrap」 | 中介分析（bootstrap 1000 次）确实针对三个时点，但 AI-A 未提及中介分析的 `c'`（直接效应）和 `a×b`（间接效应）的证据强度差异，也未区分中介分析在原设计中的定位是探索性还是确定性的。原文对中介的表述在 Method 中属于统计方法之一，但 Discussion 中用了「mechanistic linchpin」等较强因果描述——这是 AI-A 没有宽泛攻击的点。 | 原文 P9 中介结果：在某些时点效果的 95% CI 是否包含 1 未完全报告（如 365 天的直接效应 c'=0.274，CI 未见）。 | 建议在 N9 中标记：「中介分析结果只给出了点估计与 95% CI，但 CI 宽度、样本量的敏感性、假设的时序性（bicarbonate 测量是否在 SHR 之后）均未说明；不能将中介比例当作稳定机制证据来支持决策树分支。」 | **中** |
| ATK-08 | N10 | 「方法: 列线图与SHAP分时点各一套」 | 这部分准确，但值得注意的是 N10 被 N1 `leads_to`——即三个时点的列线图和 SHAP 被当作「三时点并列主终点」的一种延展证据。实际上，列线图和 SHAP 是预测建模工具，它们的效果验证（C-index）与「多终点」的统计推断问题是不同层面的。N1→N10 这条边可能将预测建模与因果推断混在一起。 | 原文确实对三个时点建模（Figure 2、Figure 3）。 | 建议调整：N10 与 N1 的边改为 `implied_by`（预测建模分时点是多终点分析的合理延伸，但不是独立证据）。 | **中** |
| ATK-09 | N12 | 「原文未明确说明: 无Bonferroni/FDR/族控」 | 这一节点将「原文未发现校正说明」作为接近确定性的声明（confidence=high），但「未发现」不能直接等同于「没有」。原文在「Statistical analysis」一节写的是「statistical significance established at two-sided P<0.05」——这本身是一种显著性阈值的声明，并不代表作者明确放弃了多重比较问题。部分期刊要求 RCS 或亚组交互项需要校正，而原文的「non-significant interaction」可能已暗含作者在解释时考虑到多重比较（即便未声明）。 | 原文 P4：「All analyses were conducted using R v4.3.2 (survival, rms, glmnet packages) with statistical significance established at two-sided P<0.05」——这是唯一的显著性声明，未出现校正字样。 | 修改为：「原文明确声明的显著性阈值为双侧 P<0.05，未在 Methods 中发现 Bonferroni/FDR/预先假设族控制的表述；但‘未声明’不能自动推导为‘未做’，需谨慎表述为‘未披露’而非‘没有’。」 | **高** |
| ATK-10 | N13 | 「主张: 未做复合终点或PCA聚合」 | 原文确实没有做复合终点或 PCA，这一点站得住脚。但 N13 引用 N3（证据）来支撑，而 N3 只说了终点定义和随访来源，并不能支撑「未做复合终点/PCA」这一声明。证据链断裂。 | 原文全文未报告复合终点或主成分分析——但这是一个「全文本审查」的结论，应该引用全文范围而非单一节点。 | 将 N13 的证据改为「Evidence: 全文范围」，不再单独引用 N3。 | **中** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| ATK-11 | N1→N2 (`because`) | 「N1: 三时点并行 primary」难以被「N2: 分时分析」所 because——分时分析是一种分析方法，并非对「主语意图」的证明。 | 改用上下文关系：N1 → `context_of` → N2。 | 中 |
| ATK-12 | N0→N4 (`leads_to`) | 从「如何处理多终点/多层暴露？」跳转到「暴露结构在三终点上重复应用」是合理的描述性分支，但遗漏了一个关键问题——四组合的「四层」是否与三分位+二分的「多层」形成冗余描述？这使分支不够紧凑。 | 在 N0→N4 之间加入一个 `if` 节点：暴露分层是否有多层定义与主效应预设？ | 中 |
| ATK-13 | N4→N6 (`leads_to`) | N4（暴露结构复用） → N6（RCS 按时点×器官层拟合） 缺少「为什么暴露复用的决定导致 RCS 分层」的过渡。RCS 分层是分析细节，不直接由「暴露结构复用」推导。 | 在 N4 与 N6 之间改边为 `entails`（分析上必然如此），否则对因果链阅读者不清晰。 | 中 |
| ATK-14 | N0→N11→N12 (`if→limitation`) | 从「是否校正多重比较？」到「原文未说明」的推理是清晰的；但从 N0 直接进入 N11 跳过了「多重比较风险」是否在原文讨论中被提及——原文 Discussion 的 limitations 并未讨论多重比较问题（它讨论了回顾性设计、单中心、缺乏生物标志物）。AI-A 引用 N11/N12 时已经判定了这是「未披露」，但没有在这个分支中区分「作者认识到的限制」与「作者未认识到的限制」。 | 在 N11 和 N12 之间加入一个节点：原文 limitations 是否讨论过多重比较？→ 若未讨论，则 N12 的『未披露』应升级为『未意识到或未处理』的判定。 | 高 |

---

## 4. Evidence Problems

### 4.1 证据定位含糊

| evidence_id | AI-A 声称的证据位置 | 实际最匹配的原文位置 | 问题描述 |
|---|---|---|---|
| E4 | “Results RCS Fig.1” | Fig.1 + P7 描述 | E4 的「非线性按时点×器官分层分别展示」被 N6 引用，而 N6 节点声明不仅包含「RCS 拟合」，还包含「阈值效应」判断。原文的阈值效应判断使用了 likelihood ratio test（P<0.05），但 E4 未区分「拟合」与「阈值检测」是两个不同的统计证据步骤。应拆分为两个证据：E4a（RCS 分层拟合证据）与 E4b（阈值效应检测证据）。 |
| E5 | “Results Subgroup + Table S1–S3” | Table S1–S3 是补充材料；正文 P7 仅一句描述 | E5 声称「验证风险排序一致；交互项不显著」，但原文 P7 只有一句话：「Subgroup analysis validated the consistent ranking of mortality risk…with non-significant interaction terms (Table S1-3)」。正文未给出各亚组的 HR 值或交互 P 值。将补充材料作为主证据引用时，应标注其为「补充材料证据，未见正文统计量」。 |
| E6 | “Mediation analysis + Fig.4” | P9 + Fig. 4 | E6 声称 `介导比例随时间下降（22.7%→21.7%→17.2%）`——这些数据来自正文结果。但 E6 没有说明这些中介比例是未经协变量调整的，且间接效应的 95% CI 在 365 天时点是否包含 0 未被 AI-A 报告。 |

### 4.2 过度引用与偷换概念

| attack_id | node | 问题 | 建议 |
|---|---|---|---|
| ATK-15 | N7 (亚组) | AI-A 将「亚组交互不显著」作为支持「暴露多层不影响主排序」的证据。但交互不显著在不同样本量下可能有不同含义（低功效时交互不显著不能证明无交互）；原文也未报告各亚组交互项的检验效能。 | 在 N7 中增加警示：「交互不显著 ≠ 无交互（需考虑功效），原文未报告功效/样本量分层」。 |
| ATK-16 | N12 | 「统计显著性 P<0.05，未见校正」被当作「多重比较控制情况不明」的充分证据——但原文确实报告了 `P nonlinear` 值（RCS），并用 `log-rank P<0.001` 描述 KM——这些检验都没有说明是否做了多重性调整，因此 AI-A 的正确解读是「未披露」，而 AI-A 当前的n12写法「原文未明确说明：无Bonferroni/FDR/族控」有偷换为「明确没有」的嫌疑。 | 将 N12 表述改为：「未发现多重比较校正策略的明确披露；不能由此推定作者已做或未做，判定为未报告。」 |

### 4.3 仿真/结果被当作方法假设

| trial | 描述 | 严重程度 |
|---|---|---|
| ATK-17 | N6 中「RCS 按时点×器官层分别拟合」是分析方法，但 N6 同时建议「阈值效应」exists（如 SHR=1.2）——这实际上是从结果（Fig 1 的 P nonlinear 值）中反推的，不是方法预设的阈值。AI-A 将该结果整合进「方法」节点 N6，导致「方法与结果混用」。 | **高** |

---

## 5. Missing Branches

### 5.1 缺失的关键条件分支条件

| attack_id | 缺失分支 | 说明 | 建议 | 严重程度 |
|---|---|---|---|---|
| ATK-18 | 多重比较校正不仅是「终点数」的问题，还包括**暴露层数**、**亚组数**、**RCS自由度**、**中介检验** 等全链条 | AI-A 的 N11 只问「终点数>1」是否校正，但原文实际检验超过了 3 个终点×4 组合×亚组×RCS 的乘法效应。 | 在 N11 下添加子节点：「暴露层数（3）、亚组数（≥5组×3时点）、RCS 自由度（4 knots）、中介检验（3个时点）是否也纳入多重比较考虑？」 | 高 |
| ATK-19 | 原文 **Table 1 出现「90 days」与「360 days」**，而 Methods/Abstract 使用「30-day」和「365-day」 | AI-A 在 Uncertainty List U2 注意到了这个不一致，但未将其纳入决策树分支。这个时点不一致如果持续存在，会导致「30天时点」这个核心节点在数据采集层面就不可靠。 | 在 N2（分时分析）下增加一个 `risk_tag`：「Table 1 中 Outcome 行出现 90/360 天标签，与 30/365 天的节目标签不一致——需要复查原文数据表是否用错了标签。」 | 中 |
| ATK-20 | **院内死亡 vs 出院后死亡的信息来源不同**——院内是住院记录，出院后是 Death Master File。不同信息源的死亡判定精度不同，可能导致 30 天与 365 天的终点判定偏倚。 | 原文明确写了出院后来源 30 天/365 天；但院内死亡和出院后死亡之间有「出院日到第30天」的窗口，可能有失访或记录延迟。 | 在 N3 下增加子节点：「院内 vs 出院后死亡的捕获精度差异→可能造成时点终点之间的系统偏差。」 | 中 |
| ATK-21 | **「四组合」与「三分位+二分」之间的重复建模** 是否引入了多重比较的额外负担——同一数据用了两种分层策略，各自独立检验 | N4 将三层结构并列，但未明确指出「三种分层方案在同一数据上重复检验」进一步放大了 I 类错误的可能性，且原文未报告不同分层方案下的校正（如 Simes procedure）。 | 在 N4 下增加子节点：「同一数据用不同暴露分层方案分别检验，各层间非互相独立 → 多重比较风险进一步上升。」 | 中 |

### 5.2 反例与局限

| attack_id | 缺失的局限/反例 | 说明 | 建议 | 严重程度 |
|---|---|---|---|---|
| ATK-22 | **365 天时点的 RCS 非线性** 在低 SOFA 组不显著 (P nonlinear=0.168)，而 AI-A 的 N6 强调「非线性按时点×器官层分别展示」，却没有标明「非线性」在低 SOFA×365岁时点失效 | 原文 P7 明确写了这个非显著结果。如果 AI-A 的 N4→N6→N7 分支被用于支持「多层暴露在长时点的非线性关系」，那么这个反例应被加入。 | 在 N6 下增加反例标记：「365天 RCS 在低 SOFA 层呈线性（P nonlinear=0.168），非线性主张仅适用于高 SOFA 层或短期时点。」 | 高 |
| ATK-23 | **亚组分析「few underpowered subgroups」**（原文 P7 承认） | AI-A 的 N7 说「亚组验证风险排序一致」，但原文承认有「few underpowered subgroups」，说明部分亚组检验功效不足——N7 的置信度（medium）应该更低或标注功效限制。 | 在 N7 中增加：「原文承认部分亚组功效不足（‘except for a few underpowered subgroups’），因此亚组一致性结论的效力有限。」 | 中 |
| ATK-24 | **中介分析本身的时效性**——碳酸氢盐是否在 SHR 之后测量？如果中介变量的测量时间不严格先于结局或后于暴露，则中介分析因果解释不成立 | 原文 Methods 只说「bootstrap-based mediation analysis」；未说明测量时序。AI-A 的 N9 将其当方法节点引用，未校验时序假设。 | 增加标记：「中介分析要求时序假设（暴露→中介→结局），原文未明确碳酸氢盐测量时点；在迁移到其他研究时应审查时序保障。」 | 中 |

---

## 6. Required Fixes

1. **【高】修正 N1/N2/N3 的节点声明**——将「三个时点=co-primary endpoints」的推断改为对原文更忠实的表述：「Abstract 三个时点并列 primary，但正文对三者处理并不对称」，并区分院内死亡（医院内捕获）vs 出院后死亡（Death Master File），避免「三终点平等」的过度宣称。

2. **【高】N6 方法节点重构**——将「RCS 拟合」与「阈值效应检测」拆分为两类证据；在 N6 下加入低 SOFA×365 天非线性不显著（P=0.168）的反例分支，防止把非线性关系泛化到所有时点×组。

3. **【高】N12 的表述从「未说明校正」升级为「未披露」而非「没有」**——全文只声明 `P<0.05` 显著性阈值的字面写法，未对多重比较做说明。AI-A 下一步迁移到用户流水线时，应提到「作者未报告校正手段，这本身的方法学缺陷，不可直接作为证明‘无膨胀’的证据」。

4. **【中】N4 增加「三种分层方案在同一数据上重复检验」的额外多重比较风险分支**——这不是 AI-A 已处理的问题（它只把多重比较归因于终点数），而原文实际上通过两种并行暴露构建策略和四种组合重复检验，进一步放大了此问题。

5. **【中】N7 的置信度降级**——加入「underpowered subgroups」与「未报告交互 P 值/功效」两处警示，标明交互不显著不等于无交互。

6. **【中】N13 的证据链替换**——不再单独引用 N3（终点定义）作为证据，改为「证据：全文系统审查」，因为「未做复合终点/PCA」是一个全文性结论。

7. **【中】在 N2 下增加 Table 1 标签不一致标记**——90/360 天 vs 30/365 天的不一致标签问题，应在决策树中可见，而非仅列入 Uncertainty List。

8. **【中】N9 中介节点增加时序与 CI 不完整标注**——原文未说明碳酸氢盐测量时点与暴露/结局的先后关系，且部分中介效应 95% CI 未报告完整；AI-A 不应将中介比例作为机制性证据迁移至用户研究。

9. **【低】N10 与 N1 的边改为 `implied_by`**——预测建模工具分时点是多终点分析的合理延伸，但不能作为「三终点平等」的证据。

10. **【低】全局：决策树中「方法」与「结果」节点要分开**——如 N6、N7、N9 均属结果驱动的分析节点；AI-A 应将它们标记为「result_interpreting_method」而非纯「method」，避免读者将结果反推为方法预设。