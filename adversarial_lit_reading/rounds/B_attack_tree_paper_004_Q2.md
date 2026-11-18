<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-19T11:19:57 | request_id=msg_227919c4-9019-4f50-b0f0-4a5c4b82d11e | usage={"input_tokens": 23560, "output_tokens": 3700, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=7255 -->
# AI-B Tree Attack

paper_id: paper_004
question_id: Q2
review_target: @rounds/A_tree_round1_paper_004_Q2.md
source_file: adversarial_lit_reading/chunks/paper_004_ewas_new.md

## 1. Attack Summary

**总体判断：部分可信，需要重大修改**

主要问题：

1. **N2 与 N5 之间逻辑交叠**：AI-A 把「逐一回归 + BH-FDR」与「弹性网 ERS」设为并列分支，但原文中两者是**阶段关系**（先 ExWAS 筛选，再 ERS 聚合），不是互斥选择。树结构暗示二选一，对用户有误导。
2. **N3 与 N4 的边标记错误**：原文 Results 3.3 明确 family-wise FDR 是「Sensitivity analysis」，N3→N4 的边却写 `if 类别内再校正`，把敏感性分析描述为可选分支，弱化了原文的肯定语气。
3. **N7「次要表型」推断过度**：Fig.4F 只是 ERS 与牙数/PPD/CAL 的相关性展示（线性回归），没有证据表明作者把这些变量定位为「次要表型」（secondary phenotype），AI-A 自己加了「次要」标签。
4. **N9 对中介的多重性校正批评有失偏颇**：原文明确把中介分析标为「exploratory」，6 个中介全部显著；AI-A 的 N9 说「原文未做再次校正」是事实，但未指出作者已经用「探索性」声明消除部分校正确必要性，攻击过于严苛。
5. **缺少「多个主终点 / 复合结局」分支**：原文主分析只有二分类牙周炎一个主终点，但 AI-A 没有明确指出「本研究不存在多主终点问题」，这对用户理解文献方法时是个关键信息。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| AN-01 | N2 | 73 个独立回归，逐一 ExWAS | 表述准确，但缺少关键细节：73 个暴露中 16 个二分类、57 个 ln 变换，二元与连续毒物在同一 FDR 家族是否合理未讨论（AI-A 在 U3 已提到，但节点本身没有反映） | ✅ 原文 Methods 2.5「fitting independent regression models for each exposure」 | 在 N2 补充「16 二分类 + 57 ln 变换」，并加条件分支「连续/二分类是否同族 FDR」 | 中 |
| AN-02 | N3 | BH-FDR，q<0.05 | 正确，但缺少 q-value 的实际解读（29 个显著毒物跨 9 类），且未指明 FDR 是对 73 次检验还是对 89 次初始检验 | ✅ 原文 Results 3.3「FDR-corrected q-value < 0.05」 | 在节点中补充「73 个毒物→29 个显著」；同时回应 U3（该 FDR 家族是否包含 73 或 89） | 中 |
| AN-03 | N4 | 类别内 family-wise FDR 敏感性 | 原文为「sensitivity analysis implementing family-wise FDR **within each chemical class**」，AI-A 未指明「within each class」的具体含义，也未强调这是类内而非跨类 | ✅ Results 3.3「family-wise FDR control within each chemical class」 | 将节点改为「敏感性：每类内 family-wise FDR（非跨类）」，并在节点表中增加对结论的解释 | 中 |
| AN-04 | N5 | ERS 是 17 个优先毒物的弹性网 | 正确的，但 AI-A 说 ERS 是「降维方式」，这对用户有误导；更准确地说是「多暴露聚合风险评分」——不是降维到成分，而是加权组合。弹性网的目标是变量选择+系数收缩，不同于 PCA 的降维 | ✅ 原文「adaptive elastic net regularization…17 priority pollutants」 | 把「降维」改为「多暴露聚合」；添加说明「弹性网是变量选择+收缩，不是主成分式降维」 | 高 |
| AN-05 | N6 | 六个中介是否主终点？ | N6 设置问题「是否都当主终点」后又用 N9 回答「未做再次校正」，但 N6→N7 的边把中介与次要表型连起来了，三个节点混在一起 | ⚠️ 原文中介在 Methods 2.5 标记为「exploratory」，Fig.5 展示 | 删除 N6→N7 的边；把 N6 改为独立节点「六个中介=探索性分析」 | 中 |
| AN-06 | N7 | 牙数/PPD/CAL 为「次要连续表型」 | **严重过度推断**——原文只说「higher ERS values correlated with decreased tooth count and increased probing pocket depth and clinical attachment loss (Fig. 4)」，「次要」staging 是 AI-A 自己加的；原文没有用「secondary outcome」或「secondary phenotype」的字眼 | ❌ 原文没有「次要表型」的说法，仅为 Fig.4F 的相关性展示 | 将 claim 改为「ERS 与牙数/PPD/CAL 存在关联（Fig.4F 线性回归）」；删掉「次要表型」词 | 高 |
| AN-07 | N8 | 相关热图：只描述共暴露，不替代 FDR | 节点claim 本身正确——热图确实不替代 FDR——但 N8 放在「N5 supported_by N8」的位置暗示'ERS 需要热图佐证'，逻辑不清；Supp Fig.2 展示相关结构是为描述暴露间相关性，并非为 ERS 提供支持 | ✅ 原文「varying degrees of correlation existed」（Fig.4A/Supp Fig.2） | 将 N8 从 N5 的 supported_by 移出，改写为「暴露相关性结构（Supp Fig.2）独立展示，与 FDR/ERS 决策无关」 | 中 |
| AN-08 | N9 | 中介六标志未再做族错误率校正 | **批评合理但表述太硬**——原文明确把中介作探索性，且六个指标全部显著（间接效应 p<0.05），在这种情形下再批评「未校正」有点苛刻；AI-A 未提 mediation 的 medsens 敏感性分析是额外稳健性证据 | ✅ 原文确实未做中介 FDR 校正；但 Methods 2.5 已声明 exploratory + medsens | 改写为「中介六指标未进行族错误率校正，但作者已声明所有中介分析为 exploratory，且进行 medsens 敏感性分析」 | 低 |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| AE-01 | N2→N3 | 边标签「leads_to」无问题，但缺少限定「**在 ExWAS 框架内**」才能用 BH-FDR；如果用户误把 N2 扩展为所有多暴露回归，BH-FDR 不一定适用 | 加限定：「仅对 73 个独立回归（各一暴露）执行 FDR」 | 中 |
| AE-02 | N2→N5 | 这是**最大问题边**——AI-A 把 ExWAS 与 ERS 的关系画成并列（`N2 --> N5`），但原文是**阶段**关系：先 ExWAS 筛选（得到 29 个显著毒物），再接弹性网得到 17 个 priority pollutants。两者不是「可选的两种办法」而是「先后使用的两个步骤」 | 把 `N2 --> N5` 改为 `N3 --> N5`（BH-FDR 后进入 ERS 构建），并在边上标注「先筛选再聚合」；或在图上加一个 N4.5「ExWAS显著集→弹性网输入」 | **高** |
| AE-03 | N3 → N4 | 边标签「if 类别内再校正」暗示这是条件分支，但原文是做了一次敏感性分析「did corroborate」，不是可选 if。 | 改为「敏感性分析：类内 family-wise FDR 证实 ExWAS 结果（非可选）」，并用实线而非虚线 | 中 |
| AE-04 | N5→N8 | N8「相关热图」被画为 ERS 的 supported_by 证据，但热图只是在 Fig.4A 与 ERS 同图展示，不构成「支持 ERS」的证据 | 删除此边；如果保留则改为「N5 独立展示，N8 仅描述共暴露结构」 | 中 |
| AE-05 | N6→N7 | N6 是「是否当主终点」的问题，N7 是「次要表型」的 claim，之间没有逻辑链；「探索性中介」与「牙数/PPD/CAL 次要表型」是两个完全不同的概念 | 删除 N6→N7；把 N7 独立挂到 N0 或 N5 后 | 中 |
| AE-06 | N6→N9 | 边合理（N9 是对 N6 的限定），但缺少「原文 exploratory 声明」作为 N6 的反驳证据 | 在边上加「counterevidence: Methods 2.5 明确 exploratory」 | 低 |

---

## 4. Evidence Problems

| problem_id | problem_type | detail | location | suggested revision | severity |
|---|---|---|---|---|---|
| EP-01 | **偷换概念** | AI-A 把「弹性网 ERS」称为「复合终点」（composite endpoint）的替代方案（Provisional Answer：「不是复合终点，而是弹性网环境风险评分」），但**原文从未将 ERS 与「复合终点」对照**——复合终点是通常指结局变量的（如 MACE），而 ERS 是暴露侧聚合，两者不在同一维度；AI-A 自造了一个不存在的二分法 | Provisional Answer 第 3 句 | 删除「复合终点」的对照表述，改为「ERS 是暴露侧的聚合评分，不是对终点做 PCA/复合」 | **高** |
| EP-02 | **证据引用不精确** | N7 的 evidence_location 是「Fig.4F」，但 Fig.4F 只展示三连续结局（牙数/PPD/CAL）与 ERS 的线性回归结果，不能支撑 AI-A 的「次要表型」说法——证据点与 claim 不匹配 | N7 / Fig.4F | 要么把 claim 降级为「相关展示」，要么找原文是否在别处明确「secondary phenotype」 | **高** |
| EP-03 | **边缘引用不足** | AI-A 的 N9 说「原文未明确说明中介族的再次校正」，但补充材料里有没有说？AI-A 的 source 只提了「补充材料 ExWAS/ERS 段」，没提中介部分补充材料 | N9 | 检查 Supplement Table 6 / 中介部分是否有 FDR 说明；如无再保留 N9，但在 uncertainty 注明缺补充材料证据 | 中 |
| EP-04 | **忽略 smoking 混杂与 collider bias** | 原文 Discussion 讨论了「同时包含尼古丁代谢物与吸烟共因变量 → collider bias」，AI-A 的树完全没有这个分支；这对「多暴露同时回归」是方法学关键警告 | Page 8 讨论段 | 在 N2 后加条件分支「注意：暴露间共享共因（吸烟）→ 潜在 collider bias」 | 高 |
| EP-05 | **缺失 unweighted ExWAS 的说明** | 原文特别解释「ExWAS 不加权」的原因（避免过调整），AI-A 全文未提；这对用户判断「该文献如何权衡复杂抽样与多重暴露」是个关键信息点 | Methods 2.5「we reported unweighted results…avoid…over-adjustment」 | 在 N2 或 N3 下加注释「ExWAS 未用抽样权重（原文给出理由），不同于文中其它分析」 | 中 |

---

## 5. Missing Branches

| missing_id | missing_branch | why needed | how to add | severity |
|---|---|---|---|---|
| MB-01 | **暴露间共因（smoking）导致的 collider bias** | 原文在讨论 Section 明确写了该限制，对「多暴露同时回归」是核心风险；AI-A 完全遗漏 | 在 N2 后插入「风险」节点：「尼古丁代谢物与其他暴露共享 smoking 共因 → 同时回归可能相撞偏倚」 | **高** |
| MB-02 | **多主终点处理（是否存在于原文）** | 问题 Q2 先问「多终点」，AI-A 未给出「本研究不存在多主终点；主终点只有二分类牙周炎一个」，这对用户理解文献的适用性是关键信息 | 在 N1 后添加「结论节点」：「本研究只有 1 个主终点，无多终点校正问题（次要表型与中介都非主终点）」 | **高** |
| MB-03 | **E-value 分析** | 原文用 E-value 检验未观测混杂强度（Supp Table 11），AI-A 只字未提；对「错误率控制」之外的多重检验话题，E-value 是原文的额外稳健性证据 | 在 N3 或 N4 后加「robustness」分支：「E-value 量化未观测混杂所需强度（Supplementary Table 11）」 | 中 |
| MB-04 | **Unweighted vs. Weighted 的边界** | 原文明确：ExWAS 不加权，但描述统计、RCS、亚组、中介用复杂抽样；AI-A 树对所有节点统一「survey-weighted」印象，不准确 | 在 N2 加备注「ExWAS 不加权」；在 N6（中介）加备注「中介用调查加权」 | 中 |
| MB-05 | **WQS 作为敏感性分析** | 原文用 WQS 作为互补混合物分析（结果与 ERS 一致），AI-A 未提及；对「多暴露聚合」的多种方法选择有参考价值 | 在 N5 后加分支「互补方法：WQS（q=4, B=1000）与 ERS 结论一致」 | 低 |

---

## 6. Required Fixes

1. **[高] 重构 N2–N5 边关系**：把 `N2 --> N5` 改为阶段关系——先 ExWAS（N2→N3）再 ERS（N5），明确标注「先筛选后聚合」；这是本树最关键的逻辑修正。

2. **[高] 删除或降级「次要表型」（N7）**：原文无「次要表型」说法，仅 Fig.4F 有相关性展示；改写 claim 为「ERS 与牙数/PPD/CAL 存在关联（Fig.4F 线性回归）」，不要用「次要」标签。

3. **[高] 修正「复合终点」对照（Provisional Answer）**：ERS 是暴露聚合评分，不应与「复合终点」（结局侧概念）对照；删除此二分法，改为「ERS 是暴露聚合评分，不是对终点做主成分」。

4. **[高] 增加 collider bias 分支**：在 N2 后插入「暴露间共享共因（吸烟）」风险节点，引用原文 Discussion。

5. **[高] 增加"无多主终点"的结论节点**：在 N1 后加「主终点唯一 → 此问题不适用多终点多重校正」，直接回应 Q2 的前半部分。

6. **[中] 修正 N4 的边标记**：family-wise FDR 敏感性不是「if」条件分支，而是已执行的敏感性分析，用实线表示。

7. **[中] 删除 N5→N8 的边**：相关热图（Supp Fig.2/Fig.4A）不「支持」ERS，仅描述共暴露结构；若保留则改为平行展示。

8. **[中] N2 节点补充方法细节**：加「16 二分类 + 57 ln 变换」「ExWAS 不加权（原文给出理由）」两个子注释。

9. **[低] 改写 N9**：加入原文「exploratory + medsens 敏感性分析」作为抗衡证据，使批评更公平。

10. **[低] 增加 E-value / WQS 分支**：作为原文的额外稳健性分析证据，丰富树的完整性。