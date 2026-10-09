<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-09-30T14:09:44 | request_id=msg_35a31c1f-e8b5-4d34-942c-cde2c864887e | usage={"input_tokens": 19749, "output_tokens": 3418, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=6955 -->
# AI-B Tree Attack

paper_id: paper_024
question_id: Q1
review_target: @rounds/A_tree_round1_paper_024_Q1.md
source_file: `adversarial_lit_reading/chunks/paper_024_nomogram_alz_13872877261424471.md`

---

## 1. Attack Summary

**总体判断：需要重大修改**

**主要问题：**

1. **Evidence Map 中 E7 的标注为「论文间接暗示」存在锚定问题**：AI-A 在 N3c 节点称「方向: 结果示正向关联, Methods未预声明必须正向」,这一表述将 Q1 的「是否假设方向」问题与「是否预先声明方向」混淆——前者是一个**研究者先验设定**的问题,后者是**论文报告充分性**的问题,两者不能混为一谈。
2. **树结构遗漏了「预测段和非预测段」的分界**。Q1 问的是「预设了几个分组/亚型/类别」,AI-A 把 N5（train/val split）与 N6（LASSO 选特征）作为独立分支放在树中,但这二者**不是「分组/亚型/类别」**——它们是样本划分与特征选择,放在 Q1 的回答结构中容易误导读者认为它们也是「分组」。
3. **RCS 检验的节点缺少「先验还是后验」的关键说明**。原文只说「A restricted cubic spline (RCS) with four knots was employed」,未说明 RCS 是探索性分析还是预先指定的主要分析。AI-A 未在树中标注这一不确定是否算「预设」。
4. **缺少对「p-MCI 阈值 ≥1 SD」是否为「多重检验校正后」的说明**。原文只用「≥1 SD below the average of the population」而未说明是考量的单一认知域还是三个认知域的组合直接取均值标准化——树中未追问。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| N-01 | N1a | 「二分类: 复合Z阈值 ≥1SD,研究者指定阈值」 | 核心正确,但缺少一个关键限定：原文说「composite z-scores falling ≥1 standard deviation (SD) below the average of the population」,但**未说明 composite Z 是按三个亚测验等权平均还是按域加权**。如果三测验权重不均,则「≥1SD」对于不同认知域的含义不同。该节点应加注「阈值定义域未说明」的不确定性。 | 原文 Page 2「Domain-specific Z-scores from individual neuropsychological assessments were standardized and aggregated to derive a composite metric」——「aggregated」未说明加权方式。 | 在 N1a 加注：composite Z 的加权方式未说明 | 中 |
| N-02 | N1b | 「非临床诊断MCI,心理测量代理」 | 判断正确,但**「非临床诊断」标签放在树中仅作为 limitation 连接（N1a→N1b 的 relation 是 limitation）,而 Q1 问的是「预设了几个分组」——非临床诊断这个属性不是「分组数」本身**。该节点应作为 N1a 的限定条件（限定符）,而非一个独立的分组节点。 | 原文 Page 2-3 明确：「reflects a psychometric classification rather than a clinical diagnosis」 | 将 N1b 从节点改为 N1a 的注解(annotation),不单独成节点 | 低 |
| N-03 | N2a | 「先验指定5个人体测量指数,非聚类/LCA」 | AI-A 判断正确,但该节点的表述「非聚类/LCA」是**多余的对比**——原文从未提到聚类/LCA,这个对比是 AI-A 为了回应 Q1 中「数据驱动(如聚类定 K)」的措辞而加入的,但放进树中可能使读者误以为原文有过聚类尝试。 | 原文仅列出 5 个指数的计算公式,无任何聚类/LCA 内容。 | 改为「先验指定5个人体测量指数」,删除「非聚类/LCA」,或在 node 注释中说明「原文未提及聚类/LCA」 | 低 |
| N-04 | N3c | 「方向: 结果示正向关联,Methods未预声明必须正向」 | **这里有概念混淆**。Q1 问「是否假设了暴露-结局关系的方向(线性、单调、U型)」——这是一个研究者先验问题,应回答「原文未明确声明假设了正向关系」即可。但 AI-A 的表述把「未预声明必须正向」与「结果示正向」并置——前者是**先验宣称**的缺位,后者是**后验发现**——两者不能作为同一节点的并列属性,要点是**原文没有直接证据证明研究者预设了正向**,而非「结果示正向」本身。 | 原文 Objective：「This study aimed to establish and verify a model」,未声明方向假设。 | 将 N3c 改为：**「方向假设: Methods 未声明先验方向;结果的

正向关联为后验发现」**,并把「结果示正向」单独拆为后验验证节点。 | 高 |
| N-05 | N6N6a | 「列线图特征数: LASSO+多因素筛选,数据驱动保留」 | AI-A 未说明一个关键限制：原文的 LASSO 只对 ABSI、WWI、CoI 三个预筛选指数 + 协变量做筛选,而 ABSI/WWI/CoI 的初筛本身是**基于前述关联分析和 RCS 的结果**。所以「数据驱动」是**两阶段驱动**：第一阶段（关联结果）与第二阶段（LASSO）都参与了特征选择。树中未区分这两步。 | 原文 Page 6：「Based on the findings from multiple logistic regression analyses, RCS regression analyses, subgroup analyses, and multiple imputation analyses, ABSI, WWI, and CoI were retained for predictor selection. The LASSO regression with cross-validation identified 12 candidate predictors」 | 拆为 N6a（基于关联分析初筛3指数）与 N6b（LASSO从候选池选择12个初始预测因子）两个子节点,并标注这是两阶段选择 | 中 |
| N-06 | N4N4a | 「亚组切点先验,非数据驱动定类数」 | AI-A 表述基本正确,但未区分「亚组分析中的分层」与 Q1 问的「分组/亚型/类别」——亚组分层是**effect modification** 的探测,而非「预设结局类别」。应明确标注「亚组是分析策略,不是分组设定」。 | 原文 Page 5-6：亚组分析列出一系列人口学/临床分层变量。 | 在 N4 节点回答前加注：**亚组分析 ≠ 分组/亚型设定** | 中 |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E-01 | N1a → N1b (relation: limitation) | **误用 relation 类型**「limitation」用于连接「阈值指定」和「非临床诊断」两个属性节点。两个节点不是推理链条上的先后关系,而是对同一现象（p-MCI 定义）的不同属性描述。「limitation」应指向对**分析结论的限制**（如外推风险）,而非对节点的修饰。 | 改为 annotation/attribute 关系,或删去该边,把 N1b 作为 N1a 的属性注解 | 中 |
| E-02 | N3a → N3b (relation: leads_to) | 「RCS 检验 → 结果线性」逻辑成立,但**缺一个中间节点**：RCS 检验的结果是「p for nonlinearity > 0.05」,这是一个**阴性检验结果**,只能说明「未发现非线性证据」,不等价于「证明线性」。中间的推断步骤（无证据反对 → 接受线性假定）是隐含假设,应在树中显式标注。 | 在 N3a 和 N3b 之间加显式推断节点：**「未发现非线性迹象(p>0.05) → 采用线性解释」**。 | 中 |
| E-03 | N3a → N3c (relation: if) | **关系类型错误**。「if」应表示条件分支（如果 A 则 B）,但 RCS 检验与「方向未预声明」之间不存在条件关系——它们是**并列的两个独立属性**（检验形态 vs 方向假设）。 | 改为「N3a and N3c are parallel attributes of N3」,不形成推理边 | 低 |
| E-04 | N0 → N5 与 N0 → N6 | **这两个分支的引入需更明确交代与 Q1 的关系**。Q1 的问法组合了「分组数 + 数据驱动 vs 主观指定 + 关系方向」三个子问题。train/val split 与 LASSO 选择是样本划分与特征选择,不是「分组/亚型/类别」——在本树中加入这两个分支,需要界定它们归属 Q1 的哪个子问题。AI-A 未在 N5/N6 的节点描述中交代这一点。 | 在 N5/N6 的描述中先回答「这属于 Q1 的哪个子问题」,否则建议将 N5/N6 移到补充说明而非主树分支。 | 高 |

---

## 4. Evidence Problems

1. **E8 证据强度标注为「论文明确证明」但实际为部分推断**。E8 声称「最终列线图纳入哪些指数：由 LASSO+多因素筛选决定（数据驱动选择）,候选池含多指数与协变量」,但该 claim 的 **LASSO 之前的初筛步骤**（基于关联分析与 RCS 结果保留 ABSI/WWI/CoI）是论文报告的两阶段选择流程,并非「候选池含多指数与协变量」——候选池的构成是给定 5 个指数 + 协变量,但 E8 的表述把「数据驱动」框定在 LASSO 单步,忽略了初筛。需修正为两阶段表述。

2. **E7 证据位置标注「Objective + Results」但引用 Objective 的原文不足以支持「是否假设方向」的判断**。Objective 写「establish and verify a model」——这句话既不能证明「预设了正向」,也不能证明「未预设正向」；它只是描述了建模目标。以此作为 E7 的证据来源,证据强度应降至「原文未明确说明该项」。

3. **E3 与 E6 的证据位置可能存在重叠但不一致**。E3 引用 Statistical analysis / Page 5–6 与 Fig2 注,说 Model3「全校正」；E6 引用同一段 Statistical analysis,说亚组切点先验。但 Fig2 注引用的校正变量清单**与 Page 5 的 Statistical analysis 段不一致**(后者写「all the potential confounding variables identified above」,没有列出具体变量)。AI-A 应在证据表中标注「Fig2 注与 Statistical analysis 正文存在清单不一致(正文未列出 Model3 完整变量),需以 Fig2 注为准」。

---

## 5. Missing Branches

| branch_id | missing content | relevance to Q1 | severity |
|---|---|---|---|
| M-01 | **复合 Z 得分的构成细节**：原文「standardized and aggregated」但未说明是否对三测验等权平均、是否校正年龄。若等权平均是假设,那么「≥1 SD 阈值」就是一个研究者指定 + 规范化假设的产物。AI-A 未在 N1a 中标注此不确定性 | 直接关系结局分组数是否真正「研究者指定」 | 高 |
| M-02 | **RCS 的先验/后验性**：原文未说明 RCS 检验是预先计划的主要分析还是探索性补充。若为探索性,「结果线性」的结论是「后验发现」而非「预设检验」。 | 直接影响 N3a-N3b 边的可信度 | 中 |
| M-03 | **p-MCI 结局的「p-MCI vs 非」，是否含中间类**：原文只是 Z ≥ 1SD 为 p-MCI,其余为「非」,但未考虑「低于 1SD 但不满足 ≥1SD」是否归入非。树中 N1a 只写了二分类,未提及「是否含 borderline 组」 | 影响分组数的回答完整性 | 中 |
| M-04 | **外部验证的 p-MCI 定义一致性**：原文承认 CHARLS 使用不同认知测验,但未说明 p-MCI 的阈值在 CHARLS 中是如何定义的——这直接影响「p-MCI」这一结局类别在外部验证中的一致性,间接影响「N1a 结局分组设定」是否在主库与外库间可移植。 | 影响 Q1 对「类别数」的跨库一致性判断 | 中 |
| M-05 | **LASSO 阶段的 λ 选择是否在验证集上做**：原文「LASSO regression analysis was conducted on the training cohort」,但未说明 10-fold CV 是只在 train 内做还是与 validation 集交互。若在 train 内 10-fold,则「数据驱动选特征」是严格train内框架——但如果需要用 validation 的模型调参,则「数据驱动」的程度需重估。 | 影响 N6「数据驱动」claim 的严格性 | 低 |

---

## 6. Required Fixes

1. **修正 N3c 节点的表述**（高）——将「方向: 结果示正向关联,Methods未预声明必须正向」改为「方向假设:原文未声明先验方向假设;结果的正向关联为后验发现,不等同于先验预设」。避免将「未预声明」与「结果正向」混为同一节点的并列属性。

2. **合并/降级 N5 与 N6 分支**（高）——train/val split、external validation、LASSO 特征选择不是 Q1 问的「分组/亚型/类别」。若保留在树中,必须在节点描述中先回答「这属于 Q1 的哪个子问题」，否则建议移至补充说明（Part 5 之后）,从主树移除。

3. **强化 N6 为两阶段选择**（中）——将「LASSO+多因素筛选」拆分为「基于关联分析初步保留 ABSI/WWI/CoI → LASSO 从候选池选 12 个 → 多因素选出 10 个」三阶段,避免把「数据驱动」简化为一句话。

4. **补充 N1a 关于 composite Z 得分构成的注释**（中）——标注「composite Z 的加权/平均方式原文未说明」,并说明「≥1SD 阈值本质上是研究者指定（非数据驱动）」。

5. **修正 E3 的证据标注**——在 Evidence Map 中新增「Model3 完整校正变量以 Fig2 注为准,Statistical analysis 正文未列出完整清单」的不一致说明。

6. **在树的 N3a 处新增先验/后验性标注**——「原文未明确 RCS 是否预先计划」这一不确定性应显式出现在树中,而非仅在 Uncertainty List 中。

7. **删除 N1a→N1b 的「limitation」关系,改为 annotation**——N1b 不是独立推理节点,是 N1a 的属性限定。