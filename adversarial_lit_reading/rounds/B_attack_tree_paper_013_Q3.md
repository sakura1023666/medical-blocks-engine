<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-30T15:36:52 | request_id=msg_77b9ab58-c46f-4b83-adac-c27d39a807c3 | usage={"input_tokens": 25072, "output_tokens": 6284, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=12766 -->
# AI-B Tree Attack

paper_id: paper_013
question_id: Q3
review_target: @rounds/A_tree_round1_paper_013_Q3.md
source_file: adversarial_lit_reading/chunks/paper_013_joint_traj_tyg_cvd_elsa.md

## 1. Attack Summary

总体判断：**部分可信（需重大修改）**

AI-A 决策树抓住了论文的核心方法定位（GBMTM vs 传统方法），证据引用基本准确，但存在几处关键问题：N3 节点对 Cox 建模的表述有方法误读（AI-A 自己也标注了"方法误读"但未给出修正）；N4 节点过度解读了"HR 缩水"的因果含义（把效应量差异等同于"轨迹信息有增量"）；E8 节点作为"未对照"证据在决策树中位置不当，且 N7 结论过度延伸（原文未提及 PSM/IPTW 不代表"倾向评分可适用"）。此外，决策树遗漏了原文明确讨论的**年龄相关肌少症（sarcopenia）对 BMI 轨迹的混杂**这一关键分支，以及**前瞻性预测算法缺失（轨迹分组只能回顾性确定）** 这一重要的临床适用性局限。

主要问题清单：
1. N3 方法误读未修正（约 55% 的风险提示但无修订）
2. N4 把"HR 缩水"归因为"轨迹信息增量"，但原文自身给出另一种解释（交叉分类组内异质）
3. 遗漏原文 Discussion 明确讨论的 sarcopenia 混淆分支
4. E8/N7 将"原文未用 PSM"等同于"未采用因果建模"，忽略原文明确声明"associations should be interpreted as predictive rather than causal"
5. 未回应 Q3 第三问"换一种方法结论会变吗"——AI-A 用敏感性分析（Sens 6/8/9）回答了"换配置文件/分配规则/分类法"，但**未回答"换因果框架（如 TMLE/IPTW）结论是否变"**，且原文确实引用了 [10] Feng et al. 用 TMLE 做类似研究——这说明"换方法"的空间比 AI-A 呈现的更大。


## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| N-01 | N3 | "组标签作 Cox 分类自变量（一次性基线赋值）" | 表述"一次性基线赋值"易误导为"基线单点测量值"。原文明确：暴露数据使用 Wave 2/4/6 三次重复测量构建轨迹，组标签是纵向信息压缩的产物，不是"基线值"。B_attack 原文：普通 Cox 中组标签作为时间不变协变量，但其**输入是纵向轨迹的判别结果**，不能等同于"单点基线赋值"。 | Methods: "Both indicators were standardized... Quadratic polynomial functions of time... estimated for K=2 through K=6" / "Individuals were assigned to the trajectory group for which they had the highest posterior probability" | 改为"组标签作为时间不变分类协变量进入 Cox，但组身份由 3 次重复测量的纵向轨迹判别得出" | 高 |
| N-02 | N4 | "换传统中位数交叉分类：仍显著但 HR 缩至 ~3.5；轨迹信息有增量" | "轨迹信息有增量"是**推断**而非原文直接声明。原文只说"cross-classified analyses... supporting the concordance between the trajectory-based and categorical approaches"——即确认**一致性**（concordance），而非**增量**（increment）。HR 从 5.06→3.48 的差异可能反映：(a) 轨迹法捕捉纵向动态 → 增量；或 (b) 交叉分类组内异质稀释 → 纯分组粒度差异；或 (c) 轨迹组标签包含更多基线协变量信息（如性别、基线 BMI）→ 非纯粹纵向贡献。AI-A 在 U3 也承认了这一点，但 N4 表格中 risk_tag 为空且 confidence 标 high，自相矛盾。 | Results: "cross-classified analyses... supporting the concordance between the trajectory-based and categorical approaches" — 原文用 concordance 而非 increment/superiority | 删去"轨迹信息有增量"的因果表述；改为"轨迹法与中位数交叉分类法结论方向一致，但效应量不同——原文表述为'一致性'而非'增量'，两种解释（纵向信息增量 vs 分组粒度差异）未区分" | 高 |
| N-03 | N5 | "换模型细节（线性/三次时间函数、概率加权分配）→ HR 4.78–4.94 稳定" | 证据引用基本准确，但 Confusion：Sens(6) 是 posterior probability-weighted Cox（处理分组不确定性），Sens(8) 是时间函数替换。两者都在检验"轨迹建模步骤"的鲁棒性，但 Sens(6) 检验的是**分配不确定性**，Sens(8) 检验的是**函数形式**——两者检验的是不同层面的假设。AI-A 合并为一个节点表述"结论稳"，丢失了"稳在哪一层"的区分粒度。另：Sens(8) 的时间函数替换是在轨迹模型层面检验，而非 Cox 模型层面——AI-A 未指出此层次。 | Results: "Posterior probability–weighted Cox models... (HR 4.78 and 4.84). Complementary log–log models... (HR 5.14 and 5.20). Analyses using alternative time functions... (HR 4.88 and 4.94)" — 原文确有此细节 | 拆分为两个子节点：N5a（分配规则→加权 Cox）与 N5b（轨迹模型时间函数）；并在 N5b 注明"这是轨迹模型层而非 Cox 层的替换" | 中 |
| N-04 | N6 | "换暴露体系（BMI↔WHtR）→ C/NRI/IDI 无差" | 准确但需补充：原文用了 **C-statistic**（Harrell's C）而非 C-index（△C=0.003, P=0.723），AI-A 写作"C 差异"可接受但建议精确。更关键的问题是：AI-A 将"两方法预测性能无显著差异"解读为"换暴露体系结论不变"——但"无显著差异"不等价于"等价"（equivalence）。△C=0.003 且有 P=0.723，但 NRI/IDI 的 P>0.8——这三个指标一致指向无差异，但纯 frequentist 框架下"不显著"≠"证明等价"。 | Supp Table 8 / Results: "C-statistics 0.663 vs 0.660, difference 0.003 (P=0.723)" | 在 N6 标注"原文用 frequentist 检验（P>0.05）支持无差异，但未做等价性检验（如 TOST）——'无显著差异'≠'统计等价'" | 中 |
| N-05 | N7 | "未对照 PSM/IPTW/ML 类：观察性队列以嵌套 Cox 调整代替因果建模" | 两条问题：(1) 原文确实未用 PSM/IPTW/ML，但原文明确说"associations should be interpreted as predictive rather than causal"——所以"未采用因果建模"不是"局限"而是**有意的解释框架**。AI-A 将其列为"limitation"并说"非缺陷但限因果解释"——这一表述是准确的，但 N7 的风险标签"可迁移性不足"未展开说明对 Q3 回答的影响。(2) N7 在决策树中是终点节点（leaf），但"未使用 PSM"本身不是"区别"——所有没做 PSM 的论文都"未使用 PSM"。Q3 问的是"GBMTM vs 既有方法的区别"，N7 作为"未做 X"其实回答了问题 2（为何选此法而非彼法）的一个否定性侧面，但缺少肯定性论证（即为何 Cox 而非 PSM 在此场景是合理的）。 | 原文 Limitation: "because this is an observational study employing latent-class methodology, the associations reported should be interpreted as predictive rather than causal" | 将 N7 重新表述为："原文明确将关联定位为预测性而非因果性；选择嵌套 Cox 而非 PSM/IPTW/ML 与这一定位一致。因果框架（如 TMLE、IPTW）是替代路径但原文未采用——这限制了'换方法结论是否变'的回答范围" | 高 |
| N-06 | E8 | "原文无 PSM/IPTW、无 ML（RF/XGB）、无 RCS → 对照法清单中未出现" | 证据链正确，但 E8 是"缺失证据"——它不是原文中的证据，而是 AI-A 对"原文缺少什么"的观察。在 Evidence Map 中呈现没有问题，但在决策树中它被放在"证据"位置支撑 N7——这样会造成"原文没有 X"作为"为何不用 X"的证据，逻辑上滑。 | 全文检查确认无 PSM/IPTW/ML | 将 E8 标记为 "absence-of-evidence 类型"；N7 的论证改为引用原文 Discussion 的"predictive rather than causal"声明 + E8 的缺失观察 | 中 |
| N-07 | N1 | "既有研究多为基线单点测量或单一指标纵向轨迹；GBMTM 同时捕捉代谢+体型两指标的并发纵向变化" | Intro 支持"既有研究多为单点或单一指标轨迹"这一 gap 描述，GBMTM 的定位也准确。但例外：原文引用了 [10] Feng et al. 用 **longitudinal TMLE** 做 TyG-BMI 轨迹，[8] Zhu et al. 用 K-means 衍生轨迹。这些是既有研究中"纵向多指标"的先行者，不完全是 AI-A 所描述的"单一指标"。AI-A 的 N1 有过度简化 gap 的嫌疑。 | Introduction: "most have modeled TyG and obesity indicators as pre-combined products (e.g., TyG-BMI as a single variable)" / Reference [10] "longitudinal targeted maximum likelihood estimation" | 在 N1 补充："部分既有研究（如 Feng et al. [10] 用 TMLE）已做纵向轨迹，但本文的 gap 在于：联合建模而不使用预复合（pre-combined）指数" | 中 |
| N-08 | N2 | "GBMTM 属于半参数有限混合模型（纵向 LCA 扩展）" | "纵向 LCA 扩展"这一类比基本正确，但不精确：LCA（潜在类别分析）通常指横截面分类；GBMTM 更准确地说是**纵向潜类别模型（longitudinal LCA/LCGA 的多结局扩展）**。AI-A 在决策树图中也写了"LCGA/LCA 的纵向多结局扩展"，但在 Node Table 中只写"纵向 LCA 扩展"，表述不完整。另外"半参数"的定位需要小心：flexmix 中高斯分布 + 多项式时间函数，时间函数是参数形式，但分布选择可以从高斯推广到其他——"半参数"在这个语境指群体异质性通过有限混合建模（而非参数化整个分布）。 | Methods: "Group-based multi-trajectory modeling (GBMTM) using the flexmix package... Quadratic polynomial functions of time... Gaussian distributions assumed for both outcomes" | 修改为："GBMTM = 有限混合模型，具体为多结局纵向潜类别模型（LCGA 在双结局/多结局上的扩展）；时间函数为类内多项式，结局分布假设高斯" | 低 |


## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E-01 | N1 → N2 | N1 描述"gap（单点/单指标）"，N2 描述"GBMTM 是什么"。两者之间缺一个连接：**为何 GBMTM 是填补这个 gap 的合适工具**？Mermaid 图中 N1→N2 没有标注推理关系标签（如 "addresses" / "operationalizes"）。如果读者不熟悉混合模型，N1→N2 看起来像"因为别人没做多指标纵向，所以用混合模型"——逻辑跳跃。 | 在 N1→N2 边上标注 "b"（because：GBMTM 能在单一模型中同时估计两个结局变量的潜在轨迹，正好适配 gap）；并在 N2 节点补充一句"有限混合模型允许两个结局变量共享潜在类别结构→适合联合轨迹识别" | 中 |
| E-02 | N2 → N3 | N2 说 GBMTM 是聚类/分类模型，N3 说下游推断用 Cox。边界缺一个**"两步法"逻辑说明**：GBMTM 输出离散组标签 → 标签作为 Cox 的暴露变量。原文是"先聚类后回归"的 plug-in 两阶段流程，这一流程存在已知的方法学问题（如聚类不确定性未在第二步中传播；回归标准误未反映第一步的估计不确定性）。原文 Sens(6) 的 posterior probability–weighted Cox 是对此的部分缓解，但 AI-A 未在 N2→N3 的边上指出这个"两阶段 uncertainty propagation"问题。 | 在 N2→N3 边标注："b"（GBMTM 输出组标签作为 Cox 暴露——plug-in 两阶段流程）；在 N3 节点补充风险说明："两阶段法未在 Cox 中传播聚类不确定性；Sens(6) 的概率加权是部分缓解" | 高 |
| E-03 | N4 → N5 | N4（传统分类法）和 N5（时间函数/分配规则）都是敏感性分析，但它们在决策树中被串行为"层级递进"（N4→N5），给人"更高层次的稳健性检验"的暗示。但**这些敏感性分析之间没有逻辑递进关系**——它们是平行的稳健性检验维度。Mermaid 图中 N4→N5 的箭头造成误导。 | 将 N4→N5 改为并行分支（N4 和 N5 均从 N3 分叉），或标注 "parallel" 而不是因果箭头 | 中 |
| E-04 | N5 → N6 | N5 回答"换模型细节结论稳"，N6 回答"换暴露体系结论无差"——两者是不同维度的稳健性（前者=建模选择，后者=操作化选择）。但 N5→N6 也在 Mermaid 中被画成链式，同样暗示递进而非并列。 | 同上，改为并行分支 | 低 |
| E-05 | N6 → N7 | N6 说"换暴露体系无差"，N7 说"未用 PSM/ML"。两者之间无逻辑连接。N7 更像是一个附加限制/边界说明，而非 N6 的结果。Mermaid 中 N6→N7 的链式呈现让读者误以为"暴露体系替换→未采用因果建模"之间存在推理关系。 | N7 改为从 N3 直接分叉（作为方法选择的边界条件），或独立标注为 "scope note" 而非推理链的一部分 | 中 |
| E-06 | N1 内部 | AI-A 的 N1 声称"GBMTM 同时捕捉代谢+体型两指标的并发纵向变化"——这是**方法定义**，不是**选法动机**。N1 在 Node Table 中被标为 type=method，但其内容同时包含了"gap"描述（既有研究不足）和"GBMTM 的差异化特征"。两类内容混在同一个节点中，使树的推理不清晰。 | 将 N1 拆分为 N1a（gap 描述：既有研究多为单点/预复合指数）与 N1b（GBMTM 的差异化特征：联合建模 vs 预复合）——二者在证据类型上不同（N1a 需要文献证据，N1b 需要方法学证据） | 中 |


## 4. Evidence Problems

| problem_id | evidence_id | problem_type | description | suggested fix |
|---|---|---|---|---|
| P-01 | E1 | 过度简化 | AI-A 将 Intro 的 gap 描述简化为"既有研究多为基线单点或单一指标纵向轨迹"，但原文同时引用了 [8] Zhu（K-means 轨迹）、[10] Feng（TMLE 轨迹）、[9] Wang（TyG+obesity 轨迹）——这些是**纵向多指标**的先行研究。原文的精确 gap 是"most have modeled TyG and obesity indicators as pre-combined products (e.g., TyG-BMI as a single variable) rather than jointly modeling TyG and anthropometric measures as separate but concurrent trajectories"。AI-A 把"预复合"和"单指标"混为一谈 | 修改 E1 摘要："既有纵向轨迹研究多用预复合指数（TyG-BMI 作为单变量），本文 gap 在于联合建模 TyG 与人体测量指标为分离的并行轨迹" |
| P-02 | E3 | 位置不精确 | AI-A 引用 "Methods L328–333" 支撑"组标签作 Cox 分类自变量"。但 L328–333 主要描述的是 **Statistical analysis 的总体设计**（Model 1–4 的协变量调整），Cox 模型中轨迹组标签作为暴露变量的描述分散在 Statistical analysis 开头（"Cox proportional hazards regression models were used to estimate... association between trajectory group membership and incident CVD outcomes"）。引用位置偏离核心句子 | 将证据位置改为 Statistical analysis 开头段落（"Cox proportional hazards regression models... trajectory group membership"），并精确到该句子而非 L328–333 的序号 |
| P-03 | E4 | 因果偷换 | E4 摘要写"换传统分类法复核——高-高组 HR 3.48/3.62 仍显著，但弱于轨迹法最高组（5.06/5.12）"——这本身准确，但 AI-A 在 N4 中将其解读为"轨迹信息有增量"（见 N-02）。"HR 数值大小差异"在观察性研究中对比较绝不能被表述为"方法 A 比方法 B 更有效"——两者不可直接比较因为分组不同（4 组轨迹 vs 4 类交叉分类）、参考组不同、人群相同但分组方案不同 | 见 N-02 的 suggested revision |
| P-04 | E7 | 正确但需加限定 | E7 说"C 差异 0.003（P=0.723）"支撑"无差"——但原文的 P 值来自**差异检验**，未做等价性检验。'不显著'不提供"两法等价"的证据强度。另外 NRI/IDI 的 P 值原文报告为"all P > 0.8"（不是 AI-A 写的"无显著差异"单纯依赖 C 差异） | 在 E7 摘要补充"NRI/IDI 亦不显著（P>0.8），但未做等价性检验" |
| P-05 | E8 | 类型错误 | E8 不是原文证据，而是"缺失证据"。在 Evidence Map 中标注 "location: 全文" 且 evidence_summary 是"未出现"——这是 absence-of-evidence，不能与 E1–E7 的 existence-of-evidence 以同样的权重展示 | 将 E8 单独标注为 "absence-evidence" 类型，或在 Evidence Map 中移动到一个 "Absence of Evidence" 子表 |


## 5. Missing Branches

| missing_branch_id | missing_node | description | reason it matters | suggested addition |
|---|---|---|---|---|
| M-01 | 年龄相关肌少症（sarcopenia）对 BMI 轨迹的混杂 | 原文 Discussion 明确讨论：BMI 在 65 岁后因肌少症而下降，正常体重-low TyG 轨迹组可能不成比例地包含因肌少症而非代谢改善而 BMI 下降的老年人。这一混杂可能解释为何 BMI 与 WHtR 两法判别性能无差异。此分支直接关系到 Q3 的"换一种方法/换一种暴露体系结论会变吗"——暴露体系从 BMI 换成 WHtR 结论"无差异"的一个可能原因是 BMI 在老年人群中的肌少症偏倚恰好平衡了其信息量 | 这是原文作者本人提出的**自反性怀疑**，说明同类研究（BMI 轨迹 + 老年人群）存在一种系统偏倚可能。如果 AI-A 的决策树要回答"为何选 WHtR 而非 BMI"，必须包含此分支 | 在 N6 下方增加分支 N6a："原文自评：BMI 在老年人群易受肌少症影响（Discussion），可能使 BMI 轨迹误判为'代谢改善'；WHtR 受此影响更小——两种暴露体系无差异可能部分源于这一偏倚的平衡"；severity=高 |
| M-02 | 前瞻性预测的不可行性（轨迹分类只能回顾确定） | 原文 Clinical implications 指出："trajectory membership can only be determined retrospectively after repeated measurements over several years, and the clinical applicability of this approach would require the development and external validation of prospective prediction algorithms"。这是"GBMTM vs 既有方法"在**应用层面**的一个重要权衡：传统基线单点测量可以在基线时刻直接用于风险分层，而 GBMTM 需要 3 次随访测量才能确定轨迹组成员——这意味着该方法在临床实践中的可用性受限于"你得先等 8 年"的问题 | Q3 问"为何选此法而非彼法"——一个关键的权衡维度是**时间成本**。AI-A 的决策树完全未提及此维度 | 在 N7 后增加节点 N8："应用层面的方法差异：轨迹法需要多年重复测量才能确定分组（回顾性分类），而单点测量在基线即可分层——原文建议开发前瞻性预测算法以解决此问题"；severity=高 |
| M-03 | 未对照的"换因果框架"问题 | AI-A 在 N5/N6 回答了"换模型细节/换暴露体系结论变不变"，但**未覆盖"换因果推断框架"维度**。Q3 明确问"换一种方法结论会变吗"——完整回答应包括：如果换成 TMLE（如 [10] Feng 做的）、IPTW、或 G-computation，结论是否变？原文未做这些对照，AI-A 在 N7 提到了 PSM/IPTW/ML 未做，但未把这一"未做"转化为对 Q3 的正面回答："换因果框架结论是否变——原文没有证据回答" | 这是 Q3 的第三问"换一种方法结论会变吗"的核心范围界定：AI-A 必须明确"哪些替换做了、哪些没做" | 在 N7 下增加："原文未实施因果推断框架（TMLE/IPTW/G-computation）替换——'换因果框架结论是否变'无证据回答"；severity=中 |
| M-04 | 敏感性分析的边界（未覆盖：切点选择差异、人群异质性迁移） | AI-A 的 N4 只提到了"中位数切分"一种传统分类换法，但原文敏感性 9 的结果是以 HR 形式报告的，且只是单一中位数切点方案。AI-A 在 U2 中说"未测三分位/临床切点"——这是不确定性，但树中未给出对应分支 | 如果换用不同切点（如 WHO BMI 切点 25/30），交叉分类组的构成会变，HR 可能接近或远离轨迹法结果——这直接影响"轨迹法是否真的有增量"的判断 | 在 N4 节点下方标注："U2 的扩展——切点选择敏感性未测，'传统分类法弱于轨迹法'的结论受限于单一中位数切点方案"；severity=中 |
| M-05 | 成分维度：GBMTM 与现有 TyG 轨迹研究（[8][9][10]）的定量对比 | AI-A 的 N1 说"既有研究多为单点/单指标"，但未对比**本文的效应量（HR 5.06/5.12）与既有 TyG 纵向研究（如 [8] Zhu 的 K-means 轨迹、[10] Feng 的 TMLE 轨迹 HR~1.69）的差异**。原文 Discussion 承认"the magnitude of association is substantially amplified when longitudinal trajectory patterns rather than single baseline measurements are considered"——这是一个可量化的对照：轨迹法 HR 5.06 vs 既有纵向法 HR1.69。这个量化对照对 Q3 至关重要 | Q3 问"与既有方法的区别"——除了方法学差异，**结果大小的差异**（解释力）也是重要维度；AI-A 未量化呈现 | 在 N1 或 N4 补充："原文 Discussion 承认轨迹法效应量（HR 5.06）远超单点法（[10] 报告 HR~1.69），但这一跨研究数值对比受人群、调整协变量、参考组差异影响，不能直接解读为'轨迹法更优'"；severity=中 |


## 6. Required Fixes

1. **[高] 修正 N3**：将"组标签作 Cox 分类自变量（一次性基线赋值）"改为"组标签作为时间不变分类协变量进入 Cox——组身份来自 3 次纵向测量的轨迹判别，非基线单值"。同时在 N3 风险标签中说明"两阶段法中聚类不确定性未在 Cox 回归中传播；Sens(6) 概率加权是部分缓解"。

2. **[高] 修正 N4 的因果主张**：删除或弱化"轨迹信息有增量"的表述，改为"轨迹法与中位数交叉分类法结论方向一致，但效应量不同（原文用语为'concordance'）——纵向信息增量 vs 分组粒度差异两种解释未区分"。将 risk_tag 从空改为"因果过度"。

3. **[高] 增加 M-01（sarcopenia 分支）**：在 N6 下方增加分支，引用原文 Discussion 关于年龄相关肌少症对 BMI 轨迹的混杂讨论，说明"暴露体系换 BMI→WHtR 无差异"可能部分源于肌少症偏倚。

4. **[高] 增加 M-02（前瞻性预测不可行性）**：在 N7 后增加节点，说明轨迹法的临床可用性受限于回顾性分类→需要前瞻性预测算法。

5. **[中] 重构决策树结构**：
   - 将 N4、N5、N6 改为**并行分支**（从 N3 分叉），而非链式递进；
   - 将 N7 改为从 N3 分叉的边界条件说明，或独立标注为 "scope note"；
   - 在 N1→N2 边上标注 "b"（GBMTM 适配 gap 的逻辑）。

6. **[中] 修正 E8/N7 的论证方式**：E8 重新标注为 "absence-of-evidence" 类型；N7 改为同时引用原文"predictive rather than causal"声明 + E8 的缺失观察，明确"未采用因果框架是原文有意的选择（配合预测性定位），而非疏漏"。

7. **[中] 修正 E5（原 E5 摘要）**：将"换分配规则/时间函数"的描述拆分为"分配规则不确定性（Sens 6，加权 Cox）"与"轨迹函数形式（Sens 8，线性/三次）"，注明后者是轨迹模型层替换而非 Cox 层替换。

8. **[中] 回应 Q3 第三问"换方法结论会变吗"的范围界定**：在 Unvertainty List 中增加 U4："换因果框架（TMLE/IPTW）结论是否变——原文无证据回答；被引文献 [10] 用 TMLE 做类似轨迹分析，是可参考的替代路径"。

9. **[低] 汇总非关键修改**：N1 的 gap 描述精确化（"预复合 vs 联合建模"，而非"单指标 vs 多指标"）；N6 建议补充"未做等价性检验"；N2 的"纵向 LCA 扩展"改为"多结局纵向潜类别模型"；NRI/IDI 的 P 值报告（P>0.8）补全。