<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-30T15:38:48 | request_id=msg_6f2d50b7-3062-4b96-babb-faae4c58d37b | usage={"input_tokens": 25112, "output_tokens": 6143, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=12212 -->
# AI-B Tree Attack

paper_id: paper_013
question_id: Q5
review_target: @rounds/A_tree_round1_paper_013_Q5.md
source_file: adversarial_lit_reading/chunks/paper_013_joint_traj_tyg_cvd_elsa.md

---

## 1. Attack Summary

**总体判断：需要重大修改**

**主要问题：**

AI-A 的决策树对 Q5 的 6 个子问题（Cox PH、logit 线性、正态性/方差齐性、聚类数 K、LCA 局部独立性、缺失处理）有**两类根本性缺陷**：

1. **逻辑链接缺失（结构性问题和逻辑跳跃）**：问题 Q5 明确要求的是「该分析依赖哪些参数假设？**是否满足？**」。AI-A 的树用 `N2 → N3` 完成 Cox PH 的「假设 → 验证」链接，但从 N3 之后（N4、N5、N7）都**仅仅是描述方法的处理策略**，而非回答「假设是否被满足」。例如 N4 说 interval midpoint 用于事件时间，但从未回答「这个近似是否合理/是否被验证」，于是 N4 → N5 的边就是把「方法描述」当「假设验证」——这是**逻辑跳跃**。

2. **参数假设体系不完整（证据问题与分支问题）**：AI-A 的假设栈只有 4 层（混合高斯、Cox PH、事件时间、缺失），**漏掉了 `logit 线性` 假设**——但 Q5 的问题措辞明确问及「logit 线性」。虽然这篇论文没有显式说明 logit，但 `flexmix` 的 GBMTM 用高斯分布建模连续结局，**不涉及 logit 线性假设**——AI-A 应当明确说明「该假设不适用（因结局为连续型）」而不是沉默跳过。这就把「未提及」误读为「不适用」。同时，AI-A 对「聚类数 K 的假设」只停留在「用 BIC/AIC 选 K」，从未回答**「K 的假设是什么？是否满足？」**——K 的选择不是「假设满足与否」而是「建模选择与模型比较」，AI-A 的表述混淆了「模型选择」和「假设检验」两种方法论。

3. **未检验的重要假设被降级为「间接保证」**：AI-A 凭 L300–304 的拟合指标（entropy/AveP/OCC/min class proportion）来声明「正态性与局部独立未直接检验」，这一结论是对的，但 AI-A 的表述把「未检验」和「假设满足」混为一谈——那些拟合指标**根本不是检验正态性或局部独立性的统计检验**。决策树没有指出该用哪些检验（Shapiro-Wilk / 残差图 / LCA 的 BLRT 或 parametric bootstrap），因此对用户的实际操作价值有限。

4. **证据映射的错误**：AI-A 将 L293–295（GBMTM 方法）与 L342–345（Schoenfeld 检验）直接相连，但从未指出这两个步骤**是在两个完全不同的模型**（GBMTM 用于轨迹分类、Cox 用于事件关联）——决策树把它们接在同一条链路上，使「PH 满足」看起来像是「GBMTM 假设满足」的证据——这是**逻辑跳跃**。

5. **「复杂抽样加权」这一子问题处理不完善**：N6 声称「ELSA 非 survey 设计，未使用权重（正确）」，但 ELSA 实际上是**复杂抽样设计**（分层、多阶段抽样、PSU），作者未用权重**不代表设计不存在**。AI-A 应当说明「ELSA 是复杂抽样设计，但本文分析未使用权重——这是原文的潜在缺陷还是合理简化？」。AI-A 的表述不经意间把「原文未报告」和「设计不存在」混为一谈。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A-01 | N1 | 「双结局均假设高斯分布」 | 正确但**显著不够**。Q5 要求「假设是否满足」，N1 应补充**「高斯假设的验证方式」**。AI-A 评为 high confidence，但原文**从未检验**高斯假设（如 Shapiro-Wilk 或残差诊断），因此 confidence 应降至 medium 并加 limitation 标签 | ✅ 原文 L293–295 明确写了 Gaussian distributions assumed for both outcomes，但**全篇无检验** | 在 N1 下增加子节点：「高斯假设未检验（无 Shapiro-Wilk/残差诊断/QQ 图报告）」；confidence 降为 medium；加 risk_tag='假设未验证' | **高** |
| A-02 | N3 | 「混合模型充分性用 AIC/BIC/... 核查（局部独立与正态未显式检验）」 | 有**偷换概念**。N3 的表述把「模型选择指标（entropy/AveP/OCC）」当成「假设检验」，而这些指标检验的是**分类质量**，不是正态性或局部独立性。AvePP 0.82/0.81 只能说明类别可分性好，不能说明类内随机误差服从高斯分布 | ✅ 原文 L300–304 为「the optimal number of groups was determined by comparing BIC, AIC, entropy, AvePP, OCC, minimum class proportion」——与正态检验无关 | 将 N3 拆为两个子节点：N3a「模型选择：K=4（BIC/AIC 最优）」与 N3b「分布假设：高斯与局部独立未检验」；N3a 的证据为模型选择，N3b 标注「原文缺失检验」 | **高** |
| A-03 | N5 | 「4 变量 MICE m=20+Rubin；完整病例(敏感性4)平行报告→一致」 | **与 Q5 关系较弱**。Q5 问的是「缺失如何处理（多插补 vs 完整病例）」，AI-A 已正确回答。但**缺失机制的假设**（MCAR/MAR/MNAR）从未被 AI-A 提及——原文用 MICE 默认假设 MAR，这一假设是否合理？决策树没有评估 | ✅ 原文 L251–257 明确 MICE，但未提供 MAR 假设的诊断证据（如比较插补组与完整组的基线） | 增加子节点：「缺失机制假设 MAR 未检验；原文化比较了 included vs excluded（Table S1）但非 MAR 诊断」；指出 FVC 18.53% 的缺失率最高、且与结局相关的潜在偏倚方向 | **中** |
| A-04 | N6 | 「无复杂抽样加权：ELSA 非 survey 设计，未使用权重（正确）」 | **事实判断错误**。ELSA 是明确的分层多阶段概率抽样（HRS 的英国对应），具有 PSU/分层变量和权重。原文不使用权重≠ELSA 非调查设计。AI-A 把「原文未报告」说成「设计不存在」是逻辑错误 | ❌ 原文（Page 3 L14–16）确认「ELSA, a nationally representative panel study with face-to-face interviews」——nationally representative panel 暗示复杂抽样，且 ELSA 文档公开提供 survey weights | 改为：「ELSA 为复杂抽样设计（分层、多阶段、PSU），本文未使用 survey 权重/PSU/分层——此为本研究的一个报告缺陷；但考虑到交叉验证的敏感性分析结果稳健，影响可能有限」 | **高** |
| A-05 | N7 | 「暴露窗假设：事件后测点剔除；对 W2 即发病者处理原文未细化」 | **部分正确但没回答核心假设**。原文明说「only exposure data collected prior to the first reported CVD event were used」——AI-A 已经点出早发者的处理未细化，但没有指出这对**轨迹分类有偏**的后果：若 W2 后立即发病，只有 W2 数据用于轨迹，可能使这类个体被误分类 | ✅ 原文 L259–263 确实如此，但 AI-A 的 critique 不够深入 | 补充解释：「若个体在 W2–W4 之间发病，其 W2 后测点被剔除，轨迹仅基于 1–2 个点——可能导致轨迹类 membership 的估计不确定；建议 AI-A 将 N7 与 N3 的分类不确定性连接」 | **中** |
| A-06 | N8 | 「收敛准则/随机起始/空类检查未报告」 | **正确的 limitation，但放错了位置**。N8 位于树的末端（uncertainty 节点），但「收敛准则」问题实际上是**关于聚类数 K 的估计有效性的核心威胁**——如果不报告收敛，则「BIC 最低」的 K=4 可能只是局部最优。AI-A 把这个问题降级为「uncertainty」而非法分支 | ✅ 原文确实完全未提收敛准则 | 将 N8 上移作为 N3 的 sister node：「K 选择未报告收敛准则，存在局部最优风险」；同时在 follow-up 问题中建议复查 R 代码或补充材料 | **中** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| A-E1 | N1 → N2 | **逻辑跳跃**：N1 是「混合高斯假设」，N2 是「Cox PH 假设验证」。这两个假设**属于不同的模型**——GBMTM 用于分类，Cox 用于关联。AI-A 将两个独立模型的假设直接连成因果链，使「PH 满足」看起来像是「GBMTM 假设满足」的推论。实际上，它们验证的是完全独立的假设，且 N2 的 Schoenfeld 检验只是 PH 假设，**不能回答 N1 的高斯假设是否满足** | 拆分为两个分支：`N1（GBMTM 假设）→ N3（模型选择/未验证分布）` 与 `N2（Cox 假设）→ PH 验证`。两者之间不应有推理边 | **高** |
| A-E2 | N3 → N4 | **偷换主题**：N3 是「混合模型充分性/选择」，N4 是「事件时间假设 — interval midpoint」。这两个 node 讨论的是**完全不同的假设**——一个关于暴露（轨迹），一个关于结局（Cox 时间轴）。AI-A 的连线暗示它们是同一推理链的先后步骤，但实际上它们是并列的独立假设 | 改为使 N3 与 N4 为并行分支（分别回答「暴露侧假设」与「结局侧假设」），删除 N3→N4 的推理边 | **高** |
| A-E3 | N4 → N5 | **逻辑跳跃**：N4 说「区间中点 + cloglog 复核」，N5 说「MICE + CC 敏感性」。AI-A 未明确说明为什么「事件时间近似」的验证 → 「缺失处理」的结论。这两者同样是**相互独立的假设**——区间中点处理的是结局时间测量，MICE 处理的是协变量缺失——它们之间没有推理关系 | 将 N4 和 N5 作为树中的并行证据节点（均为假设栈的组成部分），删除 N4→N5 的方向性边 | **高** |
| A-E4 | N5 → N6 | **逻辑跳跃**：N5（缺失处理）与 N6（抽样加权）是**两个独立的设计维度**——缺失关注变量不完整，抽样加权关注入选概率不同。AI-A 用 N5→N6 的单向箭头暗示它们相关联，但原文并未说明两者存在交互。实际上，缺失与抽样权重**可能会交互**（如若无响应权重未被使用，则 MAR 假设在抽样框架下可能不成立）——但 AI-A 未讨论这一交互 | 将 N6 改为由 N0 直接分出的独立分支。在 follow-up 中讨论「MICE 插补模型是否包含 survey 权重变量（若 ELSA 提供）」 | **中** |
| A-E5 | N6 → N7 | **逻辑跳跃**：N6（抽样加权）与 N7（暴露窗）是关于不同维度的假设——一个是抽样设计，一个是时依暴露的测量。AI-A 的连线暗示它们属于同一因果链的先后步骤，但它们实际上是**垂直维度**（抽样/人群 vs 纵向测量）的独立问题 | 将 N6 → N7 的边删除，将二者作为并列的假设维度 | **中** |

---

## 4. Evidence Problems

| problem_id | evidence | problem_type | details | suggested revision | severity |
|---|---|---|---|---|---|
| P-01 | E1（L293–295） | **位置不完整** | AI-A 正确引用了高斯分布假设的证据位置。但 E1 只摘录了「假设高斯」，未摘录**方法文档中提到的 `z-score标准化入模`**——这一预处理步骤可能影响高斯分布假设的检验（标准化后的变量 vs 原始分布）。AI-A 节点 N1 未讨论标准化的影响 | 在 N1 下增加「z-score 标准化与高斯假设的关系：标准化可改善数值稳定性，但不会使非正态数据变为正态」 | **低** |
| P-02 | E2（L300–304） | **偷换概念** | AI-A 将「模型选择/Fit statistics」当作「假设检验指标」，这与统计学常规做法不符。BIC/AIC 是模型选择工具，entropy/AveP/OCC 是分类质量指标，它们**不能检验高斯性或局部独立性**。AI-A 把「间接指标」表述为「充分性检验」——这在概念上不严谨 | 修改 N3 表述：「作者报告了分类质量指标，但未对高斯分布与局部独立性进行任何形式检验（如残差图、Shapiro-Wilk、BLRT 等）」 | **高** |
| P-03 | E4（L226–228） | **证据引用不完整** | AI-A 正确引用了区间中点近似，但未引用**原文对近似合理性的辩护**（敏感性分析 7，cloglog）。AI-A 在 N4 中提及了 cloglog，但其 confidence 判定为 high 时，没有点评 cloglog 结果是否真的「支持」了区间中点近似——cloglog 只验证 Cox 模型假设，不能证明「区间中点」本身是准确的 | 在 N4 的 confidence 判定中注明：「cloglog 是另一模型族对事件时间的敏感性分析，不等同于对区间中点方法的验证」 | **中** |
| P-04 | E5（L251–257） | **部分证据缺失** | AI-A 正确报告了 MICE 的具体参数（m=20、Rubin、4 变量）。但**原文在 L251–257 提到「complete case analysis conducted as sensitivity」时，未说明 CC 分析的样本量或输出**。AI-A 的决策树 N5 说「两轨一致」但没有提供「CC 一致性」的证据来源（补充材料 Table S7 的哪些行？） | 在 N5 增加证据位置特异性：「Sensitivity(4) 结果在补充材料 Table S7 第 X 行」——若无具体行号，则应标注「需复查补充材料」 | **中** |
| P-05 | E6（全文） | **证据缺失但被用作 negative claim** | AI-A 声称「全文未提 survey 权重，故无加权」，这是**「缺席证明（argument from silence）」**。不能因为原文未报告就断言设计不存在。ELSA 的 cohort profile（原文 ref 19）以及 ELSA 官方文档明确列出了分层变量、PSU 和权重。AI-A 犯了「缺少证据 ≠ 证据缺失」的逻辑谬误 | 改写 N6：「原文未报告使用 survey 权重/PSU/分层——需复查 ELSA 数据文档确认加权变量的可用性；在分析未加权的情况下，参数估计可能受抽样设计影响」 | **高** |

---

## 5. Missing Branches

| missing_id | missing_branch | related Q5 sub-question | why important | suggested addition to AI-A tree | severity |
|---|---|---|---|---|---|
| M-01 | **「logit 线性」假设分支** | Q5 明确问及 logit 线性 | Q5 的问题措辞包括「logit 线性」——虽然该文用 GBMTM（高斯结果）而不涉及 logit 链接，但**用户明确提出该子问题**，说明用户可能在多个论文的对比阅读中需要知道「这一假设在本论文中是否存在」。AI-A 完全沉默是对用户问题的遗漏 | 新增分支 N_{logit}：「本分析结局为连续型（TyG、BMI、WHtR），不使用 logit 链接——因此该假设不适用；若用户在其他论文中遇到分类结局，才需评估 logit 线性」 | **高** |
| M-02 | **K 的「假设」与「选择」的区分** | Q5 问「聚类数 K」 | AI-A 说「K=2–6 比较选出 K=4」，但**从未说清「K 的假设是什么」**。K 不是「假设」，而是**建模选择**。Q5 的「假设是否满足」针对的是「GBMTM 中对 K 的估计是否可靠」——即 BIC 选择的 K=4 是否稳定、是否对随机起始敏感、是否有 bootstrap 支持。AI-A 只在 N8 提及「收敛未报告」但未与 K 构建联系 | 增加分支：「K=4 选择的稳定性未检验（无 bootstrap、无多起始交叉验证）——这是对 K 的建模选择的可靠性评估，而非假设检验」 | **高** |
| M-03 | **LCA 局部独立性——与高斯假设平行的检验** | Q5 明确问及「LCA 局部独立性」 | AI-A 在 N3 中提到「局部独立未检验」但**未解释什么是局部独立、为什么重要**。局部独立性要求「在给定类成员后，各结局之间相互独立」——但对于 GBMTM 双结局联合轨迹，**局部独立性可能根本不适用**，因为 TyG 与 BMI 在类内可能相关（代谢与肥胖本身就相关性高）。AI-A 应讨论这一矛盾：「如果类内 TyG 与 BMI 相关，那么高斯独立假设不成立，但 GBMTM 的 flexmix 可能默认使用非独立结构？原文未说明」 | 在 N3 下展开：「GBMTM 的联合密度是否假设类内独立未说明；若假设独立且不成立，则类别估计的顺序性可能有偏」 | **高** |
| M-04 | **方差齐性假设** | Q5 在问题中列出「正态性/方差齐性」 | AI-A 只讨论了「高斯分布」但未讨论「方差齐性」（类内方差是否跨波/跨类恒定）。GBMTM 的 flexmix 默认方差结构通常是 homogeneous，但原文**未说明**方差结构是否等于 constant 或 class-varying。若方差异质性被忽略，分类可能不正确 | 新增节点：「flexmix 的方差结构（constant vs class-varying）在原文未报告——需复查补充材料；若类间方差差异显著，恒定方差假设可能偏误」 | **中** |
| M-05 | **MICE 的变量范围限制** | Q5 问「缺失如何处理」 | AI-A 正确报告了 4 个变量有缺失，但**未说明轨迹建模的变量（TyG/BMI/WHtR）是否有缺失**。原文在 exclusion 处说「missing TyG n=4125」被排除——这意味着轨迹变量采用完整病例，仅协变量用 MICE。AI-A 未指出这一「变量特定」的缺失处理策略 | 在 N5 下增加：「轨迹变量缺失用 complete-case（排除 n=4125 TyG、n=1058 BMI、n=868 WHtR），仅协变量用 MICE——这一不对称性可能引入选择偏倚；建议讨论排除规模与敏感分析」 | **中** |
| M-06 | **「区间删失」的 Cox 有效性边界** | Q5 问「Cox PH 假设是否满足」 | AI-A 正确指出 cloglog 敏感性分析，但**未讨论「区间删失 + Cox」是否比「区间删失 + cloglog」的 PH 检验更合理**。Schoenfeld 检验对区间删失数据的适用性有限——若事件时间被 interval-censored，PH 检验的效力可能降低（type II error 增加）。AI-A 未讨论此边界 | 在 N2 下增加：「Schoenfeld 检验在区间删失数据中的效力有限——global P>0.05 可能只是检验力不足，而非假设满足」 | **中** |

---

## 6. Required Fixes

| fix_id | required_fix | priority | related_attack |
|---|---|---|---|
| F-01 | **重构决策树的逻辑骨架**：将「单一假设链」改为「四个独立的假设维度」并列结构——(a) 暴露侧 GBMTM（高斯+局部独立+方差齐性+K 选择+收敛）; (b) 结局侧 Cox PH（比例风险）; (c) 时间尺度（区间中点/cloglog）; (d) 数据缺失（MICE/CC）+ 抽样设计。删除 N1→N2→N3→... 的单向链式推理 | **P0** | A-E1, A-E2, A-E3, A-E4, A-E5 |
| F-02 | **为「假设 vs 检验 vs 选择」提供清晰区分**：对于每个假设，AI-A 应明确标注三者的关系——(1) 假设是什么; (2) 原文是否检验; (3) 检验方法是否充分。尤其是 N3 的 AIC/BIC 不能作为正态或局部独立的检验 | **P0** | A-02, P-02, M-01, M-03 |
| F-03 | **修正 N6 关于复杂抽样的处理**：ELSA 是复杂抽样设计。AI-A 应改为「原文未使用权重——这是潜在缺陷，但由于敏感性分析结果稳健，影响可能有限」——不能因为原文没报告就说「设计不存在」 | **P0** | A-04, P-05 |
| F-04 | **补充「logit 线性」与「方差齐性」的分支**：明确指出两个问题在本论文中的适用性（logit 不适用——结局连续；方差齐性未报告——flexmix 内部默认） | **P1** | M-01, M-04 |
| F-05 | **将 N8（收敛/随机起始）上移并与 K 选择构建联系**：说明 K=4 的 BIC 选择可能受局部最优影响；作为「K 的假设是否满足」的直接威胁 | **P1** | A-06, M-02 |
| F-06 | **补充「MICE 与抽样权重的交互」讨论**：若 ELSA 提供抽样权重且被忽略，那么 MICE 的 MAR 假设——在未加权的分析中——可能同时受「样本选择概率」影响 | **P2** | A-E4, P-04 |

---

## 7. 严重程度分布

| 严重程度 | 数量 | 条目 |
|---|---|---|
| **高** | 10 | A-01, A-02, A-04, A-E1, A-E2, A-E3, P-02, P-05, M-01, M-02, M-03 |
| **中** | 8 | A-03, A-05, A-06, A-E4, A-E5, P-03, P-04, M-04, M-05, M-06 |
| **低** | 1 | P-01 |

---

## 8. 已引用的原文证据检查记录（source verification）

| citation_id | AI-A 声称 | 原文实际内容 | 一致性判定 |
|---|---|---|---|
| E1 (L293–295) | 「双结局均假设高斯分布」 | ✅ 原文「Gaussian distributions assumed for both outcomes」（Page 4） | 一致 |
| E2 (L300–304) | 「混合模型充分性用 BIC/AIC/entropy/AvePP≥0.80/OCC/最小类占比」 | ✅ 原文「comparing BIC, AIC, entropy, average posterior probability (AvePP; threshold ≥0.80), odds of correct classification (OCC), minimum class proportion」 | 一致 |
| E3 (L342–345) | 「Cox PH 假设用 Schoenfeld 残差检验（逐协变量+全局）；所有模型全局 P>0.05」 | ✅ 原文「The proportional hazards assumption was assessed using Schoenfeld residual tests...all global P>0.05」 | 一致 |
| E4 (L226–228) | 「事件时间用两次访视区间中点」 | ✅ 原文「to the midpoint between the last event-free wave and the wave at which the event was first reported」（Page 4） | 一致 |
| E5 (L251–257) | 「MICE m=20 + Rubin；完整病例作敏感性(4)」 | ✅ 原文「multiple imputation...with 20 imputed datasets...pooled using Rubin's rules. A complete case analysis was conducted as a sensitivity analysis」 | 一致 |
| E6 (全文) | 「ELSA 无 survey 权重/PSU/分层」 | ❌ **不准确**。原文未报告使用权重，但 ELSA 设计是复杂抽样（nationally representative panel）。AI-A 混淆了「未报告」与「不存在」 | **需修正** |
| E7 (Sensitivity 7) | 「cloglog HR 5.14/5.20 与主模型一致」 | ✅ 原文「Complementary log–log models addressing interval censoring confirmed the robustness of the findings (HR 5.14 and 5.20)」（Page 10） | 一致 |
| E8 (Methods L259–263) | 「事件后测点剔除」 | ✅ 原文「only exposure data collected prior to the first reported CVD event were used for trajectory construction」（Page 3–4） | 一致 |
| E9 (全文) | 「收敛准则/随机起始/空类检查未报告」 | ✅ 原文未提及这些内容 | 一致 |

---

## 9. 核心结论与复现建议

AI-A 决策树回答了「**论文用了哪些假设**」，但未充分回答「**这些假设是否被满足**」。Q5 的目标是**假设验证的批判性阅读**，而 AI-A 的树大量停留在「方法描述」而非「假设检验」。特别是：

1. **高斯假设、局部独立、方差齐性**——这三个假设被归为「未直接检验」之后，AI-A 没有提供**检验方案**（即「应当用什么方法检验」），使决策树的实用价值有限。
2. **K 的选取不被当作「假设」来讨论**——K=4 是模型选择的结果，但其可靠性（收敛、随机起始、bootstrap 支持）从未被检验——这是对 K 假设的核心威胁。
3. **抽样权重问题被误判**——ELSA 是复杂抽样设计，AI-A 的「未使用权重（正确）」表述可能误导用户。

**给 AI-A 的修改优先级**：先重构树的结构（将单一链改为四分支并列），再修正 N6 与 N3 的表述，最后补充 logit/方差齐性/K 的可靠性。

---

**报告结束**，以上攻击作为 AI-B 对 AI-A 决策树 `@rounds/A_tree_round1_paper_013_Q5.md` 的正式审稿反馈。