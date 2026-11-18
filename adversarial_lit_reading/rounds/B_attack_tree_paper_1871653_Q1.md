<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-11-18T14:42:54 | request_id=msg_6b41c93a-6ec1-497c-beec-de35e80284b9 | usage={"input_tokens": 14297, "output_tokens": 4677, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 768, "prompt_tokens_details": {"cached_tokens": 768}} | char_len=9383 -->
# AI-B Tree Attack

paper_id: paper_1871653
question_id: Q1
review_target: @rounds/A_tree_round1_paper_1871653_Q1.md
source_file: adversarial_lit_reading/chunks/paper_1871653_fcimb_temperature_jlcm.md

---

## 1. Attack Summary

**总体判断：需要重大修改**

AI-A 的决策树整体框架基本符合原文（数据驱动选 K、PAMM 允许非线性、阈值病种特异），但存在若干将「方法能力」误作「结果证据」、将「未提及」误作「否定」、以及将「单一病种场景」过度迁移的问题。核心结论方向不错误，但多个节点需要补充限定条件或修正证据引用。

**主要问题：**
1. **N6 证据链断裂**：Fig5 展示 PAMM 的非线性 U 型结果，但该图只展示「连续温度暴露」的关联，**不支持**「阈值/占比/累积负担」四个互补指标（那是 Supp Table 9 的内容）。
2. **N7 证据位置错误**：KM 曲线交叉在 Results 3.2（Fig2），但 AI-A 将其放在 Methods 2.5.1 —— 那只是方法描述的位置，不是证据位置。
3. **N3 信息不完整**：BIC 在五类最低，但 entropy 在四类最高 —— AI-A 未完整呈现「BIC 与 entropy 之间的张力」，直接锁 5 类过于简化。
4. **N9 迁移过度**：原文只在**单一病种（脓毒症）**、**单一暴露（体温）** 场景验证。AI-A 的 N9 直接给出「复合指标亦数据驱动选K；U型不可先验强加；阈值须重定或降级为连续PAMM」 —— 部分建议（重定阈值）合理，但「U型不可先验强加」这一表述暗示了因果/可迁移性判断，超出原文证据范围。
5. **E8 阈值引用缺失页码/具体出处**：AI-A 引用了 Methods 2.5.3（L348–356），但原文中阈值定义在 Methods 2.5.3 的**后半段**（约 L350 之后），L348 附近可能还未到该内容 —— 需要精确到句。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| N-A1 | N1 | 「轨迹类=数据驱动潜类别，非先验二分类暴露」 | 前半正确，但「非先验二分类」是正确表述，没问题。但「数据驱动」应限定为「基于 JLCMM + 多准则判定」，而非纯数据驱动 —— 因为「临床可解释性」是主观准则，不是纯数据驱动。 | Methods 2.5.1 L294–298：「最优类数依据 BIC、后验类别概率、entropy、临床可解释性」——「临床可解释性」不是客观数据指标。 | 将「数据驱动」改为「数据驱动为主，辅以临床可解释性判定」 | **中** |
| N-A2 | N3 | 「主文锁定5类（BIC+可解释）」 | 遗漏关键信息：entropy 在四类最高，五类下降。AI-A 未展示 BIC 与 entropy 之间的权衡张力，直接说「锁定5类」过于简化。实际上原文是权衡后选定，不是无争议选择。 | Results 3.2 L421：「Although entropy peaked in the four-class model and declined slightly in the five-class model」→ 原文承认 entropy 在四类最优。 | 补充「entropy 四类最优但五类仍可接受 + 五类死亡风险分离更清晰」的双面信息 | **中** |
| N-A3 | N4 | 「形态命名 + MAP；非先验暴露组」 | 正确。原文 Results 3.2：「Trajectory patterns were visualized... 五类按轨迹形态命名」。MAP 在原文指「class with the highest posterior probability」（L298），非 Mean Arterial Pressure —— 本质上正确，但需注意容易与 MAP（平均动脉压）缩写混淆。 | Methods 2.5.1 L298：「patients were assigned to the class with the highest posterior probability」→ 确实用了 posterior probability 进行分配（即 MAP）。 | 无重大修改；可加脚注说明 MAP 在此语境指 Maximum A Posteriori 而非 Mean Arterial Pressure | 低 |
| N-A4 | N5 | 「方法允许非线性(PAMM样条)，不锁死线性/单调」 | 正确。但「不锁死」是一种表述策略 —— 原文 PAMM 使用惩罚样条，确实灵活建模非线性。但需注意：PAMM 只是**方法选择**，不保证结果一定是非线性。AI-A 的 N6 已经在处理这一点，N5 本身可保留。 | Methods 2.5.3 L336–347：「Penalized splines were used to flexibly model the nonlinear relationship」→ 确实允许非线性。 | 无需修改 | 低 |
| N-A5 | N6 | 「结果呈现U型；原文未写『事先假设U型』」 | 证据引用不准确。AI-A 将 E6 标注为「Results 3.4 / Fig5（正文）」，但 Fig5 只展示连续温度暴露的 PAMM 结果；阈值/占比/累积负担在 Supp Table 9。若 N6 只指「U型」，可接受，但 E6 的 evidence_summary 将「结果呈现」与「非事先锁死」混在一起，需要区分。 | 正文 L256–257（Results 3.4）确实描述「non-linear U-shaped association」；Fig5a 展示。但 AI-A 的 E6 描述「结果呈现非事先锁死 U 型假设」—— 后者是推断，不是原文直接引用。 | 将「非事先锁死U型」改为「原文未报告事先假设，方法允许非线性；结果为U型」——区分「方法能力」与「结果呈现」 | **中** |
| N-A6 | N7 | 「因 KM 曲线交叉提示 PH 可能违反，用分段 Cox 估时变 HR」 | **证据位置错误**：KM 曲线交叉在 Results 3.2（Fig2），AI-A 标注为「Methods 2.5.1」。原文 Methods 2.5.1 确实描述了分段 Cox 方法，但「因交叉而使用」的证据在 Results。 | Results 3.2（L425）：「Crossing survival curves indicated potential violation of the proportional hazards」→ 在 Results，不在 Methods。 | 将 N7 的证据位置从 Methods 2.5.1 改为 Results 3.2 / Fig2 + Methods 2.5.1 | **中** |
| N-A7 | N8 | 「四套互补暴露度量；阈值病种特异」 | 「病种特异」是 AI-A 的推断 —— 原文只说阈值「in accordance with commonly used definitions in critical care literature」（L357），并没有明说「病种特异」。这个限定词是合理的推断（体温阈值对脓毒症的定义），但需要标注为推断而非原文直接陈述。 | Methods 2.5.3 L348–356：「Hypothermia was defined as temperature ≤36 °C and hyperthermia as temperature ≥39 °C... commonly used definitions in critical care literature」 | 将「病种特异」改为「面向脓毒症重症人群的常用定义」，或标注为 AI-A 的推断 | **中** |
| N-A8 | N9 | 「迁移：复合指标亦数据驱动选K；U型不可先验强加；阈值须重定或降级为连续PAMM」 | 前两点可接受；「阈值须重定或降级为连续PAMM」是给用户的**行动建议**，但原文只说阈值是「designed to enhance clinical interpretability rather than identify optimal cutoffs」（Discussion，L439–440）。AI-A 的「重定」建议合理，但「降级为连续PAMM」把 PAMM 置于「阈值」之上，而原文只说它们是互补的（「complementary exposure metrics」）。另外，原文阈值「不寻找最优 cutoffs」是有意设计 —— 迁移到复合指标时，不应默认原始阈值不适用就需要「重定」—— 也可能是「重新评估」而非「重定」。 | Discussion 4：「threshold-based and cumulative exposure analyses were designed to enhance clinical interpretability rather than identify optimal cutoffs」 | 将「阈值须重定」改为「阈值须重新评估是否适用于新指标；若作为优化目标，需独立确定」；将「降级为连续PAMM」改为「连续 PAMM 与阈值分析定位不同，互为补充」 | **中** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E-A1 | N1 → N2 | N2「ng=1 起步 → 递增类数 grid search + 多随机起始」确实是 N1「数据驱动潜类别」的合理方法支撑。但「递增类数」未明确上限 —— 原文只说「models with increasing numbers of latent classes」（L288），未说明搜索范围（如 1–6？1–10？）。AI-A 也未标注该上限不明。 | 在 Node Table 或 Uncertainty List 中补注「grid search 的类数范围原文未明确」 | 低 |
| E-A2 | N3 → N4 | N3「锁定5类」→ N4「形态命名 + MAP」成立。但 N3 的「BIC 最低 + 可解释」未充分体现「entropy 四类最优」的张力，过渡到 N4 时读者容易误以为「5类完全无争议」。 | 在 N3 的 node_description 中补充「entropy 四类最优但五类仍可接受；五类风险分离更清晰」 | **中** |
| E-A3 | N5 → N6 | N5「方法允许非线性」→ N6「结果为U型」**逻辑跳跃**：方法允许非线性，不必然推导出结果为 U 型 —— 结果是数据本身呈现的。AI-A 的 N6 正确指出「结果呈现 U 型，原文未写事先假设」，但 N5→N6 的边应标注为「结果呈现」，而非「因方法允许，所以结果是 U 型」。实际上 AI-A 已经处理了这一点（N6 明说「结果呈现」），但边的连接方式容易让读者误解为「方法 → 结果」的因果链。 | 在 N5→N6 边上加注「结果由数据呈现，非方法预设」；或为 N5 增加一条边「方法能力」→「不保证结果形态」 | **中** |
| E-A4 | N6 → N7 | 从「暴露-结局呈现U型」直接跳转到「轨迹类间用分段 Cox」**逻辑断裂**：N6 讲的是 PAMM 的连续暴露关系，N7 讲的是轨迹分类后的类间生存比较。两者使用不同方法（PAMM vs 分段 Cox），处理不同对象（连续暴露 vs 离散轨迹类）。原决策树没有在 N6→N7 之间标注「轨迹类间生存」与「连续暴露关联」的区别。 | 增加中间节点：「轨迹类间生存比较另用分段 Cox（因 KM 交叉）」；或在 N6 与 N7 之间标注「分析对象变更：连续暴露 → 离散轨迹类」 | **高** |
| E-A5 | N7 → N8 | N7「分段 Cox」→ N8「阈值/占比/累积负担」**方法语境切换不清**：N8 的四套互补度量属于 PAMM 框架（Methods 2.5.3），不是分段 Cox 的延伸。AI-A 的树中 N7 是「方法」节点，N8 也是「方法」节点，但 N7（分段 Cox）和 N8（四套度量）之间没有明确「这是两个独立分析分支」。 | 在 N7 与 N8 之间标注「平行分析方法」；或将 N8 直接从上文 N6（PAMM）引出 | **中** |
| E-A6 | N8 → N9 | N8「阈值/占比/累积负担为互补暴露定义；阈值数值病种特异」→ N9「复合指标亦数据驱动选K；U型不可先验强加；阈值须重定或降级为连续PAMM」。**迁移跳跃**：原文只说阈值「是为临床可解释性设计，不寻最优 cutoffs」（Discussion），AI-A 推断「复合指标须重定阈值」—— 这一推断合理但有风险：复合指标可能不需要阈值（如仅用连续暴露），也可能需要（如便于临床解读）。AI-A 直接给出「须重定或降级」的建议，缺乏中间推理。 | 在 N8→N9 之间补注「迁移决策取决于用户研究目标是临床可解释（需阈值）还是机制探索（连续暴露）」 | **中** |

---

## 4. Evidence Problems

| attack_id | location | problem | severity |
|---|---|---|---|
| EP-1 | N3 的 E3 | E3 描述「BIC 在五类最低；四类 entropy 更高但五类仍可接受」—— 正确。但 E3 说「五类死亡风险分离更清晰」，这一信息来自 Results 3.2（L421-422：「the five-class solution provided clearer separation in mortality risk」），而 AI-A 在 E3 的「evidence_summary」中将其压缩为「BIC+entropy+≥5%+meanPP」—— 丢失了「五类风险分离更清晰」这一关键判定依据。 | 中 |
| EP-2 | N7 的 E7 | E7 标注「Methods 2.5.1（L311–313）」，但 KM 曲线交叉的证据在 Results 3.2（Fig2），Methods 2.5.1 只描述分段 Cox 方法本身。AI-A 将「证据」与「方法」混在同一行，导致证据位置标注错误。 | **高** |
| EP-3 | N8 的 E8 | E8 标注「Methods 2.5.3（L348–356）」，但阈值定义（≤36/≥39 °C）在 2.5.3 的后半部分；L348 是否为「四套互补度量」的起始位置需要核实。 | 低 |
| EP-4 | N6 的 E6 | E6「结果呈现 U 型」正确，但「非事先锁死 U 型假设」是 AI-A 的推断（原文未明说「我们未事先假设 U 型」）—— 原文 Discussion 只说「阈值分析是为可解释性设计」，未说「未预设 U 型」。AI-A 将推断与证据混在 E6 的 evidence_summary 中。 | 中 |
| EP-5 | N9 的 E9 | N9 是「迁移节点」（transfer_node），没有直接原文证据。AI-A 将 N9 的 evidence_location 留空 —— 合理，但「U型不可先验强加」这一结论**未经过论证**：原文没有说「不可先验假设 U 型」，只说「用了惩罚样条灵活建模」—— 灵活建模 ≠ 禁止先验假设。AI-A 应区分「原文未假设」与「研究者不应该假设」。 | **中** |
| EP-6 | E8「阈值数值」 | AI-A 在 E8 中引用「阈值在体温论文为 ≤36 / ≥39 °C」—— 这正确，但 E8 本身位于 Evidence Map 中，而 Evidence Map 应该**纯描述原文**，不包含「病种特异」之类的推断性定语。建议将「病种特异」移到 Node Table 或 Uncertainty List。 | 低 |

---

## 5. Missing Branches

| attack_id | missing_branch | why it matters | suggested_revision | severity |
|---|---|---|---|---|
| MB-1 | **entropy 与 BIC 的张力分支** | 原文 Results 3.2 明确提到 entropy 在四类最高、五类下降（L421）。AI-A 的树直接 N3→「锁定5类」，未展示这一权衡过程。读者可能误以为「5类无争议」。 | 在 N3 增加分支：「entropy 四类最优，五类略降但仍可接受 → 因五类风险分离更清晰而选五类」 | **中** |
| MB-2 | **25 年外验证证模型可能不匹配** | 原文 2.5.4「external validation... Posterior class-membership probabilities were estimated using model parameters derived from the MIMIC-IV cohort」—— 外验证证使用的是推导模型的参数，但这些参数是否在新数据上重新拟合了 trajectory 就没说。AI-A 的树完全没有涉及「外验证证」分支，而这一分支对「类别是否数据驱动」的判断有影响（外验证证中的「类别」是固定参数，不是重新选 K）。 | 增加「验证队列中的类数沿用推导队列的 5 类 —— 非重新选 K」说明 | **中** |
| MB-3 | **Fine-Gray 灵敏度分析** | 原文 3.5 说明 Fine-Gray 结果与 cause-specific Cox 在 Class 4、5 有差异（L432-435）。AI-A 的树未涉及，但这一分支对「类别-死亡关联是否因果」的解读有影响。 | 在 N7（分段 Cox）后补充「同一分析在 Fine-Gray 下 Class 4/5 估计有差异」 | **中** |
| MB-4 | **PAMM 的因果限定** | 原文 Discussion 4「residual confounding and reverse causation cannot be excluded」—— PAMM 的 U 型是**关联**，不是**因果**。AI-A 的树未明确标注「关联 vs 因果」的限定。 | 在 N6 增加标注「关联（observational），非因果证明」 | **高** |
| MB-5 | **稳定性/敏感性（28天 vs 住院内）** | 原文 3.5 报告 28 天死亡率结局下轨迹模式「similar」（L432）。AI-A 的树未提及 28 天 vs 住院内死亡定义对轨迹选择的影响。该分支影响「5 类是否结局定义无关」。 | 增加「按 28 天死亡率重估 → 轨迹模式相似 → 5类稳健」分支 | 低 |
| MB-6 | **排除标准与选择偏倚** | 原文 Discussion「patients with insufficient temperature measurements were excluded」→ 可能引入选择偏倚（L436–438）。AI-A 的树未列出这一局限，但它对「类别是否完整代表脓毒症人群」有影响。 | 在 N1 下方或 N4 下方增加「排除短 ICU 住院/早期死亡者可能引入选择偏倚」标注 | 低 |

---

## 6. Required Fixes

1. **【必须】** 修正 N7 的证据位置：KM 曲线交叉在 **Results 3.2 / Fig2**（不是 Methods 2.5.1）。
2. **【必须】** 在 N6 增加「关联非因果」标注：PAMM U 型是观察性关联，原文明确承认 residual confounding 和 reverse causation 不能排除。
3. **【必须】** 在 N3 补充「entropy 四类最优但五类仍可接受」的权衡过程，避免读者误以为「5类无争议」。
4. **【必须】** 区分 E6 中的「结果呈现」与「推断」：原文只说结果呈 U 型，未明说「未预设 U 型」—— 后者是 AI-A 的推断，需标注。
5. **【必须】** 修正 N6→N7 的逻辑断裂：PAMM 连续暴露关联与轨迹类间生存比较是两个不同分析，增加过渡节点说明。
6. **【应当】** N8 的「病种特异」改为「脓毒症重症人群常用定义」或标注为 AI-A 推断。
7. **【应当】** N9 的「阈值须重定或降级为连续PAMM」改为「阈值是否适用取决于用户研究目标；连续 PAMM 与阈值分析为互补关系，非替代关系」。
8. **【应当】** 在 Uncertainty List 中增加「grid search 的类数范围原文未明确」。
9. **【建议】** N4 加脚注：MAP 在此为 Maximum A Posteriori（后验概率最高），非 Mean Arterial Pressure。
10. **【建议】** 在 Missing Branches 中增加 Fine-Gray 灵敏度分析分支（Class 4/5 与 cause-specific Cox 有差异）。
11. **【建议】** 补充外验证证分支：验证队列类数沿用推导队列的 5 类，非重新选 K。