# AI-B Tree Attack

paper_id: paper_003
question_id: Q1
review_target: @rounds/A_tree_round1_paper_003_Q1.md
source_file: adversarial_lit_reading/chunks/paper_003_2024_zhou_2024_association_between_cardiometabolic_index_and_depression_national_health_and_nutrition_examination.md

## 1. Attack Summary

总体判断：**部分可信（需修改）**

AI-A 的核心回答方向是正确的、证据位置也基本准确——本文确为一项**横断面关联研究**，未使用聚类/LCA 等"数据驱动定 K"的亚型发现，而是并行使用多套先验切分（抑郁二分、tertile 三分位、Wakabayashi 文献界值二分）与一套 RCS 拐点三分段；并正确地把"U 型"限定为引用文献中的饮酒-CMI 关系、把因果方向限定为横断面无法确立。**没有发现事实性硬错误**（数值、OR、AUC、界值均与原文一致）。

但树存在四类系统性问题，足以削弱其严谨性与可读性：

1. **边语义混乱（最严重）**：`supported_by` 在 N8/N9/N6→N2 上方向反了（应"claim 由 evidence 支撑"，而非 evidence supported_by claim）；`N2 --contradicted_by--> N14` 把"横断面不能定因果"说成"反驳正相关"，语义过强，可能误导读者以为关联本身被推翻；`N1 --because--> N3..N10` 用因果连词描述聚合关系。
2. **"数据驱动"纯度被高估**：N7 把 RCS 三分段标为纯"数据驱动"，但 RCS 的**结点数量（knots）是研究者预设的**，且决定可识别拐点数上限；原文从未披露结点数与放置准则（见 U1），故"数据驱动"须加限定。
3. **内部矛盾未被刻画**：N9 声称连续 logistic"隐含单调正向"，而本文自己的 RCS 检出显著非线性（P<0.001）——单调性假设已被证伪，但树把 N9 与 N7/N8 并列为 N2 的并列支持，没有刻画这一张力。
4. **关键缺失分支**：多重比较/事后合并饮酒类别、选择偏倚（剔除 14,054+1,265）、反向因果替代、亚组内倒 U 型（never/former 饮酒者 OR 在 CMI≈1.5 达峰后回落）均无对应分支。

修订后可升至"可信"。当前不可判"需重大修改/不可信"，因为核心结论与证据链未被推翻。

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| NA1 | N7 | "RCS 拐点三分段 ≤0.9522 / 0.9522–1.58 / ≥1.58 — 数据驱动" | "数据驱动"被绝对化。RCS 的**结点数量（knots）由研究者预设**，直接决定可识别拐点数的上限（3 结点最多 2 拐点，恰与本文"两个拐点"吻合）。拐点**位置**是数据驱动，但拐点**个数受结点数约束**属先验设定，且原文未披露结点数。 | 原文 §3.3 仅给拐点数值 0.9522/1.58，§2.4 未披露 RCS 结点数/放置准则（AI-A 自身 U1 也承认）。 | 改为"拐点位置数据驱动，但可识别拐点数受预设结点数约束，结点数未披露"。并在节点加 risk_tag"可重复性存疑"。 | 中 |
| NA2 | N9 | "连续 logistic 隐含单调正向（每单位 CMI OR 升高 28%–34%）" | 线性 logit 连续模型确实"隐含单调"，但本文 RCS 检出显著非线性（P for nonlinearity<0.001），意味着该单调性假设**被本文自己的证据证伪**。N9 把单调正向当作对 N2 的干净支持，掩盖了"线性模型假设 ↔ RCS 非线性"的内部张力。 | §3.2 给出 34%/28%/34%（范围 28–34%，数值准确）；§3.3 RCS P<0.001 否定线性。 | 在 N9 增加："此单调性为线性 logit 的模型假设，与 §3.3 显著非线性结论相矛盾，仅作主模型默认设定、非关系形态的最终判断"。并补一条 N9↔N7/N8 的矛盾边（见 EA4）。 | 中 |
| NA3 | N12 | "摘要/结论**先验**表述 positive correlation / increased risk" | "先验"用词不准。研究目标原文为"aims to **explore** the association"（非方向性探索），正向关联是**结果**而非预先声明的方向性假设。把结果说成"先验表述"会让 Q1 第三问（是否假设方向）被误读为"作者事前就锁定了正向"。 | §1/Abstract objective: "explore the association between CMI and depression"（非方向）；正向表述出现在 Results/Conclusion。 | 把"先验表述"改为"结果/摘要表述为 positive correlation"。如要论证"方向性假设"，应引 Introduction 中脂代谢紊乱→抑郁的机制论述，而非 Abstract 结论。 | 中 |
| NA4 | N2 / N12 | "较高 CMI 与抑郁**风险增加**相关" / "increased risk" | "风险增加（increased risk）"在横断面设计中是**前瞻性/因果性措辞**。原文确实这么写（故 AI-A 属忠实转述），但 Q1 第三问正是问"方向假设"——AI-A 在 claim 层面直接复刻了这一因果化语言，仅在 risk_tag 与 N14 处间接提示，节点本体未加限定。 | Abstract/§5 原文用 "increased risk for developing depression"；§4 Limitations 自述无法建立 causality。 | N2 claim 改为"较高 CMI 与抑郁**发生 Odds 升高**相关（横断面关联，非发病风险）"，把"risk"降格为"association/odds"。 | 中 |
| NA5 | N15 | "可借鉴「先验切点 + tertile + RCS 拐点」双轨分组策略"（适用 NHANES 加权横断面关联研究） | 迁移过宽。RCS 拐点 **0.9522/1.58 是本研究样本特定估计**，未经外部验证，不能作为可迁移阈值；策略（每数据集重新拟合 RCS）可迁移，但**具体数值不可迁移**。此外该 risk_tag"可迁移性不足"已存在，却未把"数值不可迁移"写进 claim。 | §3.3 拐点来自单样本 RCS；§4 Limitations 提到样本限于特定人口、样本量相对小。 | 拆为两层：策略层（可借鉴多编码并行的分析框架）与数值层（0.9522/1.58 不可外推、需在新队列重新拟合并做 bootstrap 稳定性检验）。 | 中 |
| NA6 | N10 | "文献界值二分（高血糖/糖尿病 cut-off）— 先验文献指定" | 概念错配未被指出。Wakabayashi 0.799/0.800（女）、1.625/1.748（男）是**高血糖/糖尿病**的判别界值，原文却拿来做**抑郁**的二分。用"疾病 A 的切点"切分"疾病 B"在生物学上缺乏依据，这比单纯的"AUC 偏低（N10L）"更根本，但树只记了结果不显著、未记概念错配。 | §3.3 原文："The cut-off values of CMI for **hyperglycemia and diabetes** were determined to be 0.799 and 0.800 in female..." 随后"can serve as reference values to **discriminate depression**"。 | N10 增补限定："该界值原为高血糖/糖尿病判别值，用于抑郁二分属跨结局借用，概念依据不足，敏感性分析全调整后不显著亦印证"。 | 中 |
| NA7 | N8 | "非线性形态为分段递增/阈值后上升，非 U 型主关联" | 对**总体**描述准确（无攻击）；但树遗漏了亚组内存在倒 U 型：never/former 饮酒者中 OR 在 CMI≈1.5 达峰后**回落**，属非单调。N8 的"非 U 型"若被读者泛化到所有亚组会失真。（此项更宜作为缺失分支 MB7，仅在此提示 N8 的范围限定不足。） | §4 Discussion：never/former drinkers 组"in the subgroup of never and former drinkers group, the OR for depression **decreases smoothly** as CMI exceeds the value of approximate 1.5"。 | N8 增加范围限定："总体形态为分段递增、非 U 型；但在 never/former 饮酒亚组内呈近似倒 U（≈1.5 达峰后回落）"。 | 低 |

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| EA1 | `N2 --contradicted_by--> N14` | "contradicted_by"语义过强。N14（横断面无法确立因果）**并不反驳** N2 的正相关关联本身，仅限制"因果解读"。字面理解会让人误以为阳性关联被设计本身推翻，直接影响 Q1"方向假设"问的结论可信度。 | 改为 `N2 --limited_by/caveated_by--> N14`，或新增 `N2 --cannot_infer_causality--> N14`，保留关联结论、仅切断因果推断。 | 中 |
| EA2 | `N8 --supported_by--> N2`、`N9 --supported_by--> N2`、`N6 --supported_by--> N2` | 方向相反、与树内其他边不一致。树中其余 `A --supported_by--> Evidence`（如 N3→E2、N6→E6、N7→E7）均表示"**节点**由**证据**支撑"。这里却让 evidence/结果节点（N8/N9/N6）指向 claim（N2）并标 supported_by，等于说"证据 supported_by 结论"，主客体颠倒。 | 二选一：(a) 反向为 `N2 --supported_by--> N8/N9/N6`；(b) 保留方向但改标签为 `N8 --supports--> N2`。务必与 N3→E2 等边的语义统一。 | 中 |
| EA3 | `N1 --because--> N3`、`N4`、`N5`、`N6`、`N7`、`N10` | "because"是因果/推导连词，但 N1 与 N3..N10 实为**聚合/组成**关系（N1 = 多套方案的总体陈述，N3..N10 是其组成分量）。用"because"暗示 N3..N10 是 N1 的原因，逻辑跳跃。 | 改为 `N1 --composed_of/aggregates--> N3..N10`，或反向 `N3..N10 --component_of--> N1`。 | 低 |
| EA4 | 缺失边：`N9 ↔ N7/N8` | 连续 logistic 的单调性假设（N9）与 RCS 显著非线性（N7/N8，P<0.001）相互矛盾，但树把三者并列作为 N2 的独立支持，未刻画该张力，读者会误以为"单调正向"与"非线性"相容。 | 新增 `N9 --assumption_violated_by--> N7`（或 `N9 --tension_with--> N8`），并在 N9 标注其单调性为被证伪的模型假设。 | 中 |
| EA5 | `N5 --if 探索关系形态--> N7` | 边本身可接受，但 N7 实为 RCS 的**结果**（数据驱动的拐点），而 N5 是**方法预设**。把"方法预设"直接连到"数据驱动结果"易让人忽略中间还缺一个"结点数先验设定"的环节（见 NA1/MB1）。 | 在 N5 与 N7 之间显式插入中间节点"RCS 方法（结点数先验、位置数据驱动）"，再连到 N7 结果，避免方法↔结果混淆。 | 低 |

## 4. Evidence Problems

- **EP1（概念偷换/跨结局借用，对应 NA6）**：E9 与 N10 把 Wakabayashi 界值标注为"高血糖/糖尿病 CMI 界值"本身无误，但未点破其被**跨结局用于抑郁二分**的概念错配——这是该敏感性分析不显著（N10L）的更深层原因，树只记了结果、漏了机制。
- **EP2（"数据驱动"过度引用，对应 NA1）**：E7/E8 仅证明**拐点位置**由 RCS 拟合产生，不证明拐点**个数**纯数据驱动（受预设结点数约束）。N7 引用 E7/E8 作"数据驱动"支撑属于证据外延。
- **EP3（AUC 来源含混）**：N10L 称文献界值方案"AUC（0.640/0.625）低于 RCS 方案"，但原文只说低于"CMI_RCS（sFig.2）"，**未在正文给出 CMI_RCS 的 AUC 数值**（sFig.2 内容未在 chunk 中呈现）。AI-A 写"低于 RCS 方案"无错，但建议注明该数值来自补充图、当前 chunk 不可核验，避免读者误以为正文已给出对比值。
- **EP4（无凭据质疑声明）**：本审查未发现 AI-A 捏造或无原文依据的节点；所有数值（3794、8.51%、34%/28%/34%、0.9522/1.58、0.799/0.800、1.625/1.748、0.640/0.625、AUC 0.748）均能在原文对应位置核对通过。

## 5. Missing Branches

- **MB1（RCS 结点数先验）**：缺一条限定 N7 的分支——RCS 结点数为研究者预设、原文未披露，决定可识别拐点数上限，故"纯数据驱动三分段"不成立（需复查原文补充材料确认结点数与选择准则）。
- **MB2（多重比较）**：本文并行运行连续/tertile/RCS-3/文献-2 四套暴露编码 + 约 13 项协变量亚组与交互检验，全文未见多重比较校正声明。缺一条限制 N11（及整体阳性发现）的"多重比较/假阳性膨胀"分支。
- **MB3（事后合并饮酒类别）**：§3.4 先按 3 类做交互得"marginal"，再合并非饮酒者（never+former）为 2 类得"significant"——合并方向与显著性变化高度提示**事后根据 p 值调整**。缺一条限定 N11 的"事后探索/数据挖掘"分支（AI-A 仅在 U4 提及，未进树）。
- **MB4（反向因果替代）**：N14 只笼统说"无法确立因果方向"，未枚举具体替代解释：抑郁→代谢恶化（反向）、或第三因素（如炎症/应激）同时驱动两者。缺一条暴露-结局方向的双向分支，正是 Q1 第三问的关键。
- **MB5（选择偏倚）**：剔除 14,054（CMI 缺失/不可靠）+1,265（PHQ-9 缺失）后仅余 3,794，完整病例分析与多重插补并存但未交代插补模型。缺一条限定外推性的"选择/无应答偏倚"分支。
- **MB6（事件数/统计效能）**：实际抑郁病例仅 323（加权患病率 8.51%），亚组与交互检验在多协变量分层下事件数稀疏，效能有限。缺一条限定 N11 亚组结论稳定性的"小事件数/低效能"分支。
- **MB7（亚组内倒 U 型，对应 NA7）**：never/former 饮酒者中 OR 在 CMI≈1.5 达峰后**下降**，呈近似倒 U。N8 的"非 U 型"仅对总体成立，缺一条刻画亚组非单调形态的分支，否则"非 U 型"被过度泛化。
- **MB8（tertile 权重口径）**：tertile 三分位是在加权还是未加权分布上计算，原文未说明（AI-A U2 已记但未进树）。加权/未加权分位点不同会影响分类与 OR，缺一条限定 N6 的分支。

## 6. Required Fixes

1. **[边-高优先] 修正 `N2 --contradicted_by--> N14`** → 改 `limited_by/caveated_by`；避免读者误读为"阳性关联被横断面设计推翻"。
2. **[边-高优先] 统一 `supported_by` 方向（EA2）**：把 `N8/N9/N6 --supported_by--> N2` 反向为 `N2 --supported_by--> N8/N9/N6`，或改标签 `--supports-->`，与 N3→E2 等边语义一致。
3. **[节点-中] N7 去"纯数据驱动"化（NA1）**：补"拐点数受预设结点数约束、结点数未披露"，加 risk_tag"可重复性存疑"。
4. **[边-中] 新增矛盾边（EA4）**：`N9 --assumption_violated_by--> N7/N8`，显式刻画线性单调假设被 RCS 非线性证伪；并在 N9 注明其为被证伪的模型假设。
5. **[节点-中] N9/NA2、N3-中] N12/NA3 修订**：N9 增非线性矛盾限定；N12"先验表述"→"结果/摘要表述"。
6. **[节点-中] N2/N12 因果语言降格（NA4）**："increased risk / 风险增加"→"odds 升高 / 关联"，横断面不称发病风险。
7. **[节点-中] N10 增概念错配（NA6/EP1）**：标注 Wakabayashi 界值为高血糖/糖尿病判别值、跨结局用于抑郁属借用、依据不足。
8. **[节点-中] N15 拆分策略层/数值层（NA5）**：策略可迁移，0.9522/1.48 数值不可外推。
9. **[缺失分支] 补 MB1–MB8**：至少把 RCS 结点数先验、多重比较、事后合并饮酒类别、反向因果替代、选择偏倚、小事件数六条作为限定分支接入 N7/N11/N14/N15。
10. **[边-低] EA3/EA5 标签清理**：`because`→`composed_of/aggregates`；N5→N7 之间显式插入"RCS 方法（结点数先验）"中间节点。

> 底线声明：本文件仅写入 `rounds/B_attack_tree_paper_003_Q1.md`，未修改 AI-A 的任何文件，未写 labels。
