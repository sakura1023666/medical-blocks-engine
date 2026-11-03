<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-11-03T11:33:37 | request_id=msg_bc8823c2-c3bf-4244-b8a6-916ca6f0d2a7 | usage={"input_tokens": 20116, "output_tokens": 4373, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=9210 -->
# AI-B Tree Attack

paper_id: paper_40295872
question_id: Q4
review_target: @rounds/A_tree_round1_paper_40295872_Q4.md
source_file: adversarial_lit_reading/chunks/paper_40295872_jin2025_shr_sofa_af_mortality_cardiovasc_diabetol.md

## 1. Attack Summary

**总体判断：需要重大修改**

**主要问题：**

1. **N3 节点严重误读原文**——AI-A 声称原文使用「directed cyclic graph」识别因果路径，但原文实际为「directed **acyclic** graph」（DAG）。AI-A 将原文的 DAG 误抄为 cyclic graph，且赋予其「结构先验」的重要性，此为基础性错误。
2. **N2 节点证据过度解读**——原文只是引用 MissForest 方法的参考文献，并未明确声称「MAR 假设」是作者自己设定的分析假设。这一表述可能是文献综述，而非作者的分析决策。
3. **N5 节点与 N10/N15 节点存在内部矛盾**——N5 声称主规则为「单因素 P<0.05 进入多因素 Cox」，N10 声称预测阶段用「后退逐步 logistic」。两套变量筛选逻辑并存却未见 AI-A 明确说明二者关系（推理 vs. 预测）对 Q4 回答的影响。
4. **N14 节点判断「未见 VIF」过于绝对**——原文确实未明确提及 VIF，但 AI-A 的表述「未见明确报告」与「未做共线性筛查」应明确区分——因原文未报告不等于未做。
5. **迁移风险未标注**——AI-A 未说明该树中各方法的通用性：UV→MV 是传统方法，但 DAG 在本研究中并未展示如何落地到变量选择，AI-A 却将其列为「结构先验」。


## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A-N3-1 | N3 | 「文称cyclic graph识别路径」 | **术语错误且影响语义**：原文第4页写的是「directed acyclic graph」（DAG），AI-A 误写为「cyclic graph」。这不仅是笔误，更导致 N3→N4 边 的批评方向错误——AI-A 批评的是「cyclic graph 措辞」，而未批评原文真正的 DAG 落地不足。 | 原文第4页 Data extraction 段末：「A directed **acyclic** graph model was used to identify various causal pathways prior to statistical analysis.」（原文此处为 acyclic，AI-A 错写为 cyclic） | 将 N3 节点改写为「原文称使用 DAG 识别因果路径」；N3→N4 的边改为「批评 DAG 的构图细节未披露、未展示如何约束入模」。 | **高** |
| A-N2-1 | N2 | 「MAR + MissForest 非参数森林填补」 | **过度解读原文**：原文「based on the missing-at-random assumption [16,17]」中的 [16,17] 是指引用文献，说明 MissForest 方法本身基于 MAR 假设。AI-A 将其解读为「作者明确声明采用 MAR 假设」，但更准确的表述是「作者引用文献说明该方法基于 MAR」。此外，原文正文提到「multiple imputation」但 MissForest 通常被理解为单次填补算法，AI-A 未标注此矛盾。 | 原文第4页：「Multiple imputation was performed for variables with <20% missing values using the Miss Forest method, a non-parametric random forest technique based on the missing-at-random assumption [16, 17].」——作者确实写明了 MAR，但 AI-A 应区分「方法本身的假设」与「作者对该假设的认可」。 | 建议改写为「作者使用 MissForest（文献标注基于 MAR 假设）填补，但未说明 'multiple imputation' 是否意味着多次填补/如何合并」。 | **中** |
| A-N5-1 | N5 | 「Cox 入模主规则=单因素 P<0.05」 | **忽略了原文同段所述 Model 2 的调整策略**：原文第4页 Statistical analysis 段内写道「Model 2 applied extensive adjustments incorporating laboratory markers, therapeutic interventions, and further severity metrics.」而 Table 2 脚注明确列举了 Model II 的 21 个协变量。如果 Model II 的调整变量是**预先固定的临床/文献驱动列表**，则与「凡单因素 P<0.05 进入」的规则并不一致——AI-A 未在 N5 或 N6 中提示这一可能「双轨」机制。 | 原文第4页：「Model 2 applied extensive adjustments...」；Table 2 脚注：「Model II: Adjusted For Age; Gender; Heart Rate; Respiratory Rate; SAPSII; SIRS; PT; Sodium; Total Calcium; Potassium; Creatinine; PLT; WBC; Bicarbonate; Mean Blood Pressure; Congestive Heart Failure; Diabetes; AKI; Invasive Ventilation, Insulin; Aspirin; Statin.」 | 建议在 N5 或 N6 中增加分支标注：「Model II 的协变量列表是否来源于 UV 筛选结果，还是文献式固定调整集，原文未明确说明」。 | **中** |
| A-N8-1 | N8 | 「模型形式：分层/组合暴露 + RCS 非线性；非默认全交互模型」 | **「非默认全交互模型」表述模糊且可能引起误导**：原文完全没有提到「默认全交互模型」的概念。四组合分析本质上就是 SHR×SOFA 二分类交互的完全表示（2×2 table），AI-A 的表述「非默认全交互模型」暗示原文没有做交互分析，但四组合本身就是交互分析的等价形式。N13 提到「亚组交互非主模型默认项」与 N8 的表述有冲突。 | 原文第4页：「For the combined analysis, patients were categorized into four groups: Q1 (Low SHR + Low SOFA)... Q4 (High SHR + High SOFA).」 | 建议将 N8 改为「模型形式：分层 Cox（SHR 三分位、SOFA 二分、四组合）；非线性通过 RCS 评估；交互通过四组合与亚组分析体现」。 | **中** |
| A-N10-1 | N10 | 「预测阶段改后退逐步 logistic（α=0.05）」 | **遗漏关键上下文**：原文明确指出「Feature selection was conducted by backward stepwise regression analysis」是在 nomogram 开发阶段，但 AI-A 未说明该选择与主 Cox 模型的变量筛选（UV→MV）之间的关系。是两个完全独立的管道？还是 logistic 的变量来自 Cox 筛选？原文也未说明，但 AI-A 作为审稿人应标记此问题。 | 原文第7页：「Feature selection was conducted by backward stepwise regression analysis (retention significance level: α=0.05), which determined the optimum covariate combination for each mortality outcome.」 | 建议增加分支：「Nomogram 模型的变量是否来自主 Cox 模型入选变量，还是独立重新做逐步选择——原文未明确，需进一步澄清」。 | **中** |
| A-N15-1 | N15 | 「Methods 写规则；未见预注册；最终逐步子集数据驱动」 | **判断合理但证据支撑不足**：AI-A 判断「未见预注册」正确（原文未提），但将该发现标注为「证据不足」的 risk_tag 容易混淆——「未报告预注册」是一个事实判断而非「证据不足」。应区分「原文未报告」与「我们不能判断是否做了」。此外，AI-A 在 N15 中混入了两个不同维度：预注册（计划层面）与数据驱动（执行层面），应分开。 | 全文扫描：未见预注册声明。 | 建议将 N15 拆分为两个节点：「N15a: 未见预注册声明」「N15b: 最终逐步变量集由数据决定（P 值驱动）」。 | **低** |
| A-N16-1 | N16 | 「glmnet 是否用于主筛选原文未写清」 | **表述过于模糊**：原文 Methods 中提到 R 包 `glmnet`，但完全未描述 LASSO 路径的任何具体应用（如 lambda 选择、交叉验证）。AI-A 标注「未写清用途」合理，但应进一步指出：既然原文未报告任何 LASSO 结果，`glmnet` 可能只是被加载但未用于主分析，或用于未展示的敏感性分析。AI-A 未给出这种可能性分析的引导。 | 原文第4页：「All analyses were conducted using R v4.3.2 (survival, rms, **glmnet** packages)」——仅列包名，无 LASSO 方法描述。 | 建议改写为「glmnet 列为工具包但主文无 LASSO 路径的描述与结果——无法判断是否用于敏感性分析或仅加载未使用」。 | **低** |


## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| A-E1 | N0 → N1 | 从根问题 Q4（变量筛选与模型形式）到 N1（缺失数据处理）的「leads_to」关系可接受，但缺失处理只是变量筛选的前置条件，并非筛选逻辑本身。攻击点：N1 是否为 N5「UV→MV」的必要前置，还是独立步骤？AI-A 未在边上标注依赖关系类型。 | 建议将边改为「precondition」而不是「leads_to」，明确缺失处理是变量进入模型前的必经步骤。 | 低 |
| A-E2 | N3 → N4 | N4 是「limitation」标注，但 N3 本身因「cyclic graph」笔误而错误。攻击点：如果 N3 更正为 DAG 后，N4 批评点应从「cyclic graph 措辞不当」转向「DAG 如何落地到实际变量名单未披露」——AI-A 需重新定位该边的批判焦点。 | 修正 N3 后，N4 应改为「原文未披露 DAG 的构图过程、变量纳入标准、以及如何映射到最终调整变量集」。 | 高 |
| A-E3 | N0 → N15 | N0 直接到 N15（预先确定？）的边跳过了中间比较过程。攻击点：N15 的结论「最终变量集数据驱动」是 N5、N10 逐步筛选的自然推论，但 AI-A 将其作为独立节点直接连根——缺乏中间推理链。 | 建议将 N15 作为综合节点，承接 N1、N3、N5、N8、N10 等所有方法节点的「预定程度」评估，而非直接从 N0 连接。 | 低 |
| A-E4 | N5 → N14 | N5（UV→MV）到 N14（共线性未见 VIF）的「limitation」关系合理，但攻击点：原文未报告 VIF 不等于未做共线性检查（建模者可能做了但未写入）。AI-A 的表述「原文未见明确报告」与「未做」应清楚区分。 | 建议改为「原文未报告共线性诊断（如 VIF），无法判断是否执行——需在复现时自行检查」。 | 中 |
| A-E5 | N8 → N13 | N8（RCS/四组合）到 N13（亚组交互）的边标记为「if」，但原文中亚组分析是独立于主模型报告的，不完全是「N8 条件下」的结果。攻击点：亚组分析在原文中是对主结果的验证，不依赖 RCS 分析；AI-A 的条件关系不准确。 | 建议将边改为「complements」，表示亚组交互与 RCS 同为主模型之外的分层验证策略。 | 低 |


## 4. Evidence Problems

### 4.1 证据位置错误：N3 节点引用错误

AI-A 在 N3 声称「文称 cyclic graph 识别路径」，但原文（第4页 Data extraction 段末）写的是「A directed **acyclic** graph model was used to identify various causal pathways prior to statistical analysis.」AI-A 将「acyclic」误写为「cyclic」。这不仅是拼写错误，更导致 N3 的全部后续推理（N3→N4 的 limitation 批评）可能存在方向偏差。**severity: 高**

### 4.2 过度引用：N2 节点的 MAR 假设

原文第4页原文：「Multiple imputation was performed for variables with <20% missing values using the Miss Forest method, a non-parametric random forest technique based on the missing-at-random assumption [16, 17].」AI-A 在 N2 中将其概括为「MAR + MissForest 非参数森林填补」，并标注 confidence=high。

问题在于：原文「based on the missing-at-random assumption [16, 17]」中的 [16, 17]（Montez-Rath 2014, Stekhoven 2012）是方法的文献基础，即**该方法假设 MAR**，而非作者**明确为自己的数据集声明**采用 MAR。作者未说明该假设是否经过检验（如 MNAR 敏感性分析）。AI-A 将其表述为「作者的分析决策」有过度解读之嫌。**severity: 中**

### 4.3 表述不精确：N14「共线性未见 VIF」

AI-A 在 N14 中写「是否做 VIF/多重共线性筛查——原文未明确说明」，并在 risk_tag 标注「证据不足」。

问题：这是**原文缺失报告（absence of reporting）**，而非「证据不足」。如果 Cox 模型的协变量之间存在高共线性（如 SAPSII 与 SOFA 高度相关），HR 估计可能不稳定。AI-A 应区分「原文未报告」与「我们不能判断是否做了」。**severity: 低**

### 4.4 证据链断裂关系说明：N8 组合分析

AI-A 引用 N9「证据：Fig.1 RCS; Table2 Combined行」支撑 N8「模型形式含 RCS + 四组合」。但 Table 2 的「Combined」部分报告的是 Q1–Q4 四组的 HR，这是**分类变量编码**而非「模型交互项」。

问题：组合编码与**交互项**是两个不同的建模策略（前者隐含完全交互，后者只估计乘积项）。AI-A 将「四组合」说成「非默认全交互模型」不准确——2×2 组合编码本质上就是交互的饱和参数化。应明确说明「四组合编码是交互的饱和形式」。**severity: 中**

### 4.5 遗漏证据：原文也有「Model I vs Model II」的对比含义

AI-A 在 N6 中引用了 Model I / Model II 层次调整，但未讨论 Model I→Model II 的 HR 变化暗示了什么。例如，Q4 的 HR 从 Model I 的 3.92 降至 Model II 的 4.06（竟然不降反升），这说明调整变量集存在潜在的**负混杂**或**协变量结构变化**，AI-A 未讨论这一重要细节。**severity: 低**


## 5. Missing Branches

### 5.1 缺少「Model I → Model II 的 HR 变化模式」

AI-A 未注意到 Q4 的 HR 在调整后反而升高（Model I: 3.92; Model II: 4.06），这不符合常规混杂调整方向。这暗示：基础风险分层（4个组合）与 Model II 中调整的协变量之间存在交互/结构变化。缺失此观察导致树未展开——AI-A 未讨论「调整方向异常」这一可能的重要发现。

### 5.2 缺少「SOFA 二分化与 RCS 的 SHR 非线性的相互关系」

原文 SHR 的非线性分析是**按 SOFA 低/高分别做 RCS**（Fig. 1），即 SOFA 作为分层变量而非调整变量呈现非线性。AI-A 将「RCS」与「四组合」列为平行方法，但未指出 RCS 中的 SOFA 分层设计本身就是对「交互效应」的另一种表达。这影响了 N8 的模型形式表述是否完整。

### 5.3 缺少「三时点模型的差异一致性」

原文三个时间点（院内、30天、1年）的分析策略一致但结果强弱不同（如 1 年非线性的 P 不显著）。AI-A 未展开描述时点差异对「Q4 预先确定逻辑」的影响——如果某一时点的非线性不显著，是否意味着「预设 RCS 4 knots」在不同时点产生了不同的结论？这是方法学上值得展开的分支。

### 5.4 缺少「Cox 模型的 Schoenfeld 检验与 PH 假设」

原文提到「The assumptions of proportional hazards were validated using Schoenfeld residual analysis」但 AI-A 未将 PH 假设检验的结果（或缺乏结果）作为节点。如果 PH 假设被违反，原作者的措施（如分层/时变协变量）应被记录。AI-A 遗漏了该分支。

### 5.5 缺少「共线性的替代评估」

AI-A 只在 N14 提到 VIF 未见，但未考虑原文可能通过其他方式处理共线性——如逐步回归本身会剔除高共线变量、或 Model II 的固定调整集经过临床专家筛选。AI-A 应提供更完整的评估建议。


## 6. Required Fixes

1. **修正 N3 术语错误**：将「directed cyclic graph」修正为「directed acyclic graph（DAG）」，并同步调整 N3 内容、N4 的批判焦点、以及 Provisional Answer 中对这一部分的引用。**（高优先级）**

2. **区分 N2 的「方法假设」与「作者决策」**：将 N2 的表述从「MAR + MissForest」更改为「原文引用 MissForest 文献（基于 MAR），未说明是否做 MNAR 敏感性分析」，避免将方法文献的假设等同于作者的数据处理决策。

3. **澄清 N5 与 N10 的两套变量筛选逻辑的关系**：在树中增加分支节点，明确说明 UV→MV（Cox 推理）与 backward stepwise（logistic 预测）是**两个独立的筛选管道**，并提问：Nomogram 的变量集是否来自 Cox 的入选变量？原文未明确说明这一点，AI-A 应标注为不确定性。

4. **重写 N8 的模型形式描述**：将「非默认全交互模型」改为明确表述——「四组合编码（2×2）是交互的饱和参数化；RCS 分层分析揭示非线性的 SOFA 依赖模式」。避免使用「默认」等未在原文出现的概念。

5. **区分 N14 的「未报告」与「未做」**：将 N14 改为「原文未报告共线性诊断（如 VIF），无法判断是否执行——复现时应自行检查」，并同时在 U1 中增加「Model II 中 SAPSII 与 SOFA 的重叠优势」讨论。

6. **增加 Missing Branches 中的内容**：
   - 新增节点：「Model I → Model II HR 变化方向异常（Q4 不降反升）——调整效应方向讨论」；
   - 新增节点：「Schoenfeld 残差检验结果与 PH 假设处理」；
   - 在三时点 RCS 之间增加分支标注（如「1 年时不显著的非线性」）。

7. **更新 Provisional Answer 的表述**：AI-A 在回答第2问「是否分析前预先确定」时，应更明确地区分「规则预先定义」与「变量集合由数据决定」两个层面，并使用修正后的 DAG 表述。