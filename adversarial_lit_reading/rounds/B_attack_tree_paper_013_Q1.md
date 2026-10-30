<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-30T15:34:46 | request_id=msg_22e0f0c0-c56a-4cfa-966f-5efff31f0f90 | usage={"input_tokens": 25557, "output_tokens": 4323, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=8471 -->
# AI-B Tree Attack

paper_id: paper_013
question_id: Q1
review_target: @rounds/A_tree_round1_paper_013_Q1.md
source_file: adversarial_lit_reading/chunks/paper_013_joint_traj_tyg_cvd_elsa.md

## 1. Attack Summary

总体判断：**部分可信，但 Node N3 和 N7 存在严重的证据链断裂，需要重大修改。**

主要问题：

1. **AI-A 严重过度解读了 N3 的"K=4 由六项准则共同选定"**：原文只说 "The optimal number of groups was determined by comparing BIC, AIC, entropy, AvePP... and clinical interpretability"，但本文 Methods (L296-298) 也明确说 "Models were estimated for K=2 through K=6 groups"。AI-A 把它解读为"六准则同时满足"，但原文实际采用了标准的模型选择流程：先基于 AIC/BIC 最低选 K=4，再用熵和 AvePP 等指标验证质量。这不是"六准则共同决定 K"，而是"K 由 AIC/BIC 主选，其余指标后验验证"。这是偷换概念。

2. **N7 声称"未预设暴露-结局方向"严重过度**：GBMTM 本身就假设了暴露（轨迹类）与结局（CVD）之间的关系是通过 Cox 模型估计的，而 Cox 模型假设暴露-结局关系为**乘性比例风险**（proportional hazards）。此外，轨迹类内的时间函数被设定为二次多项式，这意味着每个类内的暴露轨迹形状被预设为抛物线——认为"未预设方向"是在认知上把方向和轨迹形状这两个问题混为一谈。

3. **N4 中"最低风险组为参照"的说法与 N7 的"未预设方向"矛盾**：参照组的选择其实是一种方向性假设——研究者预先指定了"最低风险组"为参照，这意味着方向被预设为从低到高的单一方向。

4. **AI-A 结论中"剂量-反应梯度完全由数据显现"的说法过度**：Cox 模型输出的 HR 梯度确实来自数据，但模型的**结构**已经预设了方向（参照组+单调比较），梯度只是在这个预设框架内的显现。

5. **严重缺失分支：完全忽略年龄组间轨迹差异**：原文正文明确说 "the point estimates were somewhat attenuated in participants aged ≥65 years"，但 AI-A 将其仅仅作为涉 NP 的亚组分析处理，而忽略了其在 N1 声明"两类分类体系"中的潜在混合效应——65 岁是 BMI 轨迹方向的潜在转折点。

6. **严重缺失分支：未识别"轨迹稳定性"的局限**：原文 Methods 讨论部分指出 "the identified trajectories remained relatively stable across waves, suggesting that the groups may primarily reflect different baseline risk strata rather than meaningful longitudinal evolution"。这条信息直接挑战了 N1 的"数据驱动的轨迹类别"的概念意义——如果轨迹只是基线水平的分组，那"轨迹类"的说法在认知上是欺骗性的。

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A1 | N3 | "K=4 两法 AIC/BIC 最低; entropy 0.75/0.74, AvePP 0.82/0.81(≥0.80), 最小类占比≥11.7%, 临床可解释" | 将"比较 BIC, AIC, entropy, AvePP, OCC, minimum class proportion, clinical interpretability"解读为"六准则共同决定 K"高度可疑。原文仅说这六项作为比较维度，未指明是主选还是后验验证。本文 L296-298 仅说 K=2 至 K=6，然后在 L300-302 "The optimal number of groups was determined by comparing..."。在传统 GBMTM（Nagin, 2005）中，BIC 是首要指标，其余是用来验证选定模型质量的。 | 部分正确：原文确实提到了六项指标。但 AI-A 加了"共同决定"和"阈值"的解读——原文只说 "threshold ≥0.80" 是 AvePP 的比较阈值，而不是 K 的选择标准。 | 改为："K=4 由 AIC/BIC 最低选定，entropy/AvePP/OCC/最小类占比/临床可解释性作为后验验证指标（AvePP 阈值≥0.80）" | **高** |
| A2 | N4 | "组命名按基线画像升序；MAP 分配；最低组为参照" | AI-A 说"最低风险组为参照"是正确的，但这其实是**方向性假设**——预选参照组意味着研究者预设了暴露-结局方向为从低到高。这一隐含假设与 N7 的"未预设方向"直接矛盾。 | 原文 L308-309 "The lowest-risk trajectory group served as the reference category in all models" 准确。 | 修改 N4 为："最低风险组为参照（隐含方向性假设：低→高风险梯度），组命名升序基于基线画像" | **高** |
| A3 | N6 | "分配不确定性：MAP 硬分配忽略后验概率→敏感性(6)用概率加权 Cox 修正" | AI-A 正确识别了 MAP 硬分配的问题，但将"敏感性分析"表述为"修正"是过度表述。敏感性(6)是稳健性检验，不是"修正"——如果存在大的分配不确定性，敏感性分析只能发现它，不能修复它。原文 Results 部分只说 "Nearly identical estimates (HR 4.78 vs 4.84)"，AI-A 将敏感性结果作为"修正有效性"的证据，而将其作为"支持稳健性"更准确。 | 部分准确：原文 L303-307 说的是 Sensitivity(6) 用概率加权 Cox "account for uncertainty in trajectory group assignment"。 | 改写为："MAP 硬分配忽略后验概率；敏感性(6)用概率加权 Cox 检验稳健性（结果与原分析接近）" | 中 |
| A4 | N7 | "不预设方向；单调梯度为实证结果" | **严重问题**：GBMTM+Cox 结构本身预设了"方向"——Cox 模型的比例风险假设是乘性效应模型，轨迹类被当作"暴露"输入模型，输出 HR——这是在预设了方向的前提下才可能的。且设定最低风险组为参照本身就暗含方向性。AI-A 把"方向"这个概念仅理解为"线性/单调/U型的函数形状"，偷换了概念。 | 原文 Results L755-810 确实显示单调梯度，但原文并未声称"未预设方向"——这只是 AI-A 的推断。原文没有这个问题，但 AI-A 把"预设方向"这个问题从"轨迹类内部的时间形状"转移到了"暴露-结局关系"层面。 | 修改为："暴露-结局关系由 Cox 比例风险模型估计（乘性效应假设），参照组为最低风险组；类内时间函数为二次多项式，未单独检验线性/单调/U型方向假设" | **高** |
| A5 | N8 | "类内时间函数二次；线性/三次仅敏感性" | 这里把"暴露-结局方向"和"类内时间形状"明确分离是好的，但 AI-A 把"未假设方向"解释为"未预设线性/单调/U型"时，仅考虑的是轨迹内部的形状，而未考虑 Cox 模型本身的乘性方向假设。N8 只有在与 N7 "方向"独立的语境下才成立——但这个独立性没有证明。 | 原文 L294-296 "Quadratic polynomial functions of time were specified within each trajectory class" 成为了 Linear/Cubic 敏感性。 | 改为更精确表述："类内轨迹形状为二次多项式（敏感性为线性/三次）；Cox 模型采用乘性比例风险框架，参照组为最低风险组——这是独立于轨迹形状的方向性假设" | **中** |
| A6 | N9 | "亚组维度（年龄/性别/教育/DM/HTN/吸烟）先验指定，界值65岁常用切点" | AI-A 声称"常用切点"是外加的、无原文依据。原文仅说 "stratified by age group (<65 vs. ≥65 years)"，未说明切点出处。AI-A 不应自行断言"常用"。 | 原文 Methods L343-350 确实提到这些分层变量，但未标"常用"或"先验"。L320 只说 "Covariates were selected a priori based on clinical relevance..." — 但这是 covariates 而非 subgroup 分层变量。 | 修改为："亚组为研究者指定的分层变量（原文未说明切点依据，需复查原文或补充文献支持）" | 低 |

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E1 | N1 → N2 | N1 声称"两层分类体系"但 N2 只说明方法的输入/输出，并未将两个层次变成一层"轨迹组×结局终点"的交叉分类。N1→N2 的关系是断的。 | 增加一个中间节点表明："结局终点是独立事件类型变量（主/次终点），不构成与轨迹分类并列的第二层分类体系"；或删除 N1 的"两层"表述。 | **高** |
| E2 | N3 → N4 | N3 说"K=4 最优"→N4 说"MAP 硬分配"：这中间缺少"如何从 K=4 到组识别"的一环。MAP 分配是分配规则，但类**被定义/解释**（如"正常体重-低 TyG"）依赖人工判读均值轨迹——这是 AI-A 未涵盖的"主观性"步骤。 | 建议在 N3→N4 之间增加节点： "类命名基于基线画像人工判读（主观性未被量化）" | 中 |
| E3 | N6 → N7 | N6 说"硬分配丢不确定性"→N7 说"未预设方向"——这两者之间没有逻辑必然性。"未预设方向"是独立主张，不依赖分配不确定性。 | 删除该边，让 N6 独立为局限性，N7 独立为主张 | 中 |
| E4 | N5 → N6 | N5 说"结局先验定义"→N6 说"分配不确定性"——边缘关系无力："结局先验定义"与"分配不确定性"无因果关系。 | 删除改边或重新定位 N6（N5 与 N6 的分层关系不成立） | 低 |
| E5 | N4 → N5 | N4 的"最低风险组为参照"与 N5 的"结局先验定义"之间无因果链。"参照组"是 Cox 分析的设置，与结局定义无关。 | 删除边，或在 N4 与 N5 之间加连接："Cox 模型纳入主/次终点，参照组适用于所有终点" | 低 |
| E6 | N7 → N8 | N7 说"未预设方向"→N8 说"类内时间函数二次"：N7 的声明可能过度但没有通过 N8 来证明。"多边形时间函数"不证明"未预设方向"，因为暴露-结局方向（Cox 乘性效应）是由 N7 之外的模型结构预设的。 | 改写 N7→N8 边为："类内时间形状假设不代表暴露-结局方向假设——但暴露-结局方向由 N7 被 Cox 模型结构预设" | **高** |
| E7 | N8 → N9 | N8 "类内时间形状"与 N9 "亚组分层"之间无逻辑必然性。 | 删除该边，或重设为："N8 与 N9 都是对模型假设的限定，但互相独立" | 低 |

## 4. Evidence Problems

| problem_id | evidence | issue description | severity |
|---|---|---|---|
| P1 | E1 → N3 | **证据位置错误**：E1 只是方法描述（L283-315），并未提供 K=4 最优的证据。把方法描述当作"K=4 最优"的证据是张冠李戴。 | 高 |
| P2 | E2 → N3 | **证据位置错误**：E2 说的是方法中"如何选K"的流程，但 K=4 在原文是经 E3 的 Results 数据验明。E2 放在 N3 是"把方法当作证据"的经典错误。 | 高 |
| P3 | E4 → N4 | **偷换概念**：E4 是 Results（L455-468）中的组命名和类占比，但 AI-A 的 N4 还声称"MAP 分配""最低组参照"——这些证据来源是 Methods（L308-310），不是 Results。E4 不能同时支撑 N4 的全部主张。 | 中 |
| P4 | E7 → N7 | **因果过度**：E7 显示 HR 梯度（2.31→2.72→5.06）是 Cox 模型输出。但 AI-A 用它来"证明"未预设方向——这不能证明，因为 Cox 模型本身预设方向（参照组+乘性效应）。最多能证明"未预设暴露-结局的函数形状"。 | 高 |
| P5 | E9 → N8 | **过度引用**：E9 提到"二次多项式"和"线性/三次敏感性"，但 N8 还额外声称"不假设单调暴露-结局方向，类间关系不预设形状"——这后半句没有原文依据。原文没有讨论"类间关系形状"。 | 高 |
| P6 | E3 → N3 | **数据正确但解读过度**：E3 显示 K=4 的 AIC/BIC 最低（这符合原文），但 AI-A 将 entropy 和 AvePP 也当作"N3 选K的证据"之一——原文只说这些数据被报告，没有说它们用于 K 选择。 | 中 |

## 5. Missing Branches

| missing_id | missing_branch | issue description | severity |
|---|---|---|---|
| M1 | **K 选择的主观性** | AI-A 完全没有提到：K=2-6 的拟合范围是研究者自定义的，没有依据证明 6 是上限、2 是下限。如果真实 K 可能是 1、7 或更多呢？——K 的范围预设本身就是主观性。 | 高 |
| M2 | **65 岁及以上人群轨迹差异** | 原文正文承认 "trajectories remained relatively stable across waves" 且用于 "the groups may primarily reflect different baseline risk strata rather than meaningful longitudinal evolution"——AI-A 完全没有涵盖这一重要局限性，它是 N1 的"数据驱动分组"概念的直接反面对手。 | 高 |
| M3 | **多重复测量的最小时间点问题** | 原文仅用 3 个时间点（Wave 2/4/6）进行 GBMTM——3 个点对二次多项式拟合是刚好（3 个点确定二次），但也是最少可行点。这种最小信息条件下的"类"非常不稳定，K=4 的可靠性因此存疑。AI-A 未提及。 | 中 |
| M4 | **缺失数据的协变量调整** | 原文采用 MICE 插入多个数据集（20 imputed datasets）——AI-A 完全没有处理这个分支，但该问题影响 K 的稳健性——每个插补集估算的 K 可能不同，但原文未报告各插补集的一致性。 | 中 |
| M5 | **轨迹稳定性对概念分类的挑战** | 原文承认 "trajectories remained relatively stable"——如果轨迹只是基线水平的反映，那么"轨迹"的实质可能是"基线风险分层"而非"纵向变化轨迹"。AI-A 未讨论这一重要概念性问题。 | **高** |
| M6 | **处理缺失 TyG 数据的潜在偏倚** | 原文最大排除原因为 TyG 缺失（n=4125），最终保留 1808（19%）。AI-A 没有将 19% 的保留率纳入"数据驱动分组"结论的可靠性评估。 | 中 |
| M7 | **肥胖悖论反向分支** | 原文在讨论部分明确说 "BMI can decline after age 65 due to loss of lean muscle mass, even as central and visceral adiposity increases"——如果轨迹模型把 BMI 下降误读为"好转"，则"正常体重-低 TyG"参照组可能包含因肌少症而 BMI 下降的老年人。AI-A 完全没有覆盖这一反例分支。 | **高** |
| M8 | **AvePP/OCC 逐 K 数值表缺失证据分支** | AI-A 在不确定性清单中已提出 U1，但需强调这是"选 K 证据链的不可验证性"而非简单的不确定性——如果 Supp Table 4 中其他 K 的 AvePP 也达标，则 K=4 的"优越性"更弱。 | 中 |

## 6. Required Fixes

1. **【高】修订 N3**：将 "K=4 由六准则共同选定" 改为 "K=4 由 BIC/AIC 最低选定，entropy/AvePP/OCC/最小类占比/临床可解释性用于验证选定模型的质量"——在 N3 中明确 BIC/AIC 的主选地位和其他指标的后验验证功能。

2. **【高】修订 N4 与 N7 的关系**：N4 中"最低风险组为参照"是一种方向性假设——在 N4 或 N7 中明确声明这一隐含方向性预设，修改 N7 为"未预设暴露-结局的函数形状（线性/单调/U型），但预设了方向（参照组为最低风险组，Cox 乘性效应）"。

3. **【高】增加新节点 N10（或合并到 N1/N2）**：处理"轨迹稳定性"分支——"原文承认轨迹在 Waves 间基本稳定，提示组别可能反映基线风险分层而非纵向变化；这一声明挑战'数据驱动轨迹类'的概念意义，应在结论中恰当限定"。

4. **【高】增加新节点 N11（或合并到 N9）**：处理"65 岁以上肌少症反向偏倚"分支——"本文讨论中明确：BMI 可能在 65 岁后因肌少症下降，而中央性肥胖增加；该偏倚可能导致'正常体重-低 TyG'参照组混入代谢不良个体，影响 K=4 的分组解释"。

5. **【中】修订 N6**：将"敏感性(6)用概率加权 Cox 修正"改为"敏感性(6)用概率加权 Cox 检验分配不确定性对结果的影响（未发现实质改变）"，避免"修正"的暗示。

6. **【中】在 N3 附近增加缺失数据与插补分支**：MICE 插补的 20 个数据集未见逐集 K 选择一致性报告——需要将这一不确定性放入 N3 的 evidence check。

7. **【中】区分输入/输出方向假设与功能形状假设**：在 N7 和 N8 之间明确区分（a）暴露-结局关系的函数形状（未预设）和（b）暴露-结局关系的方向（预设为参照组+乘性效应）。添加说明："类内时间二次多项式设定与暴露-结局方向是不同层次的问题"——但 N7 不能宣称"未预设方向"。

8. **【低】把 N9 的"常用切点"改为"未见文献支持，需复查原文"**，不要将研究者未声明的"常用"读入原文。