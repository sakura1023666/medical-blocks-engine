<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-10T15:48:00 | request_id=msg_f7c29ee6-4f00-4922-a51e-ab3eaa38c970 | usage={"input_tokens": 12276, "output_tokens": 3440, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=7155 -->
# AI-B Tree Attack

paper_id: paper_025
question_id: Q8
review_target: @rounds/A_tree_round1_paper_025_Q8.md
source_file: paper_025.pdf + RealExtraction交付说明

## 1. Attack Summary

**总体判断：需要重大修改**

AI-A决策树结构过于简化，将复杂迁移决策压缩为5个节点，遗漏了多个关键维度（OMOP映射、特征对齐、N构造一致性、与现有引擎的集成方式等）。证据映射表存在严重问题：E1和E3的概括过度简化，未能反映原文复杂的方法细节；E4指向"delivery 07 yaml"但未说明该配置与原文预处理Pipeline的对齐程度。最大问题在于——**决策树将"train/评估/出表脚本"标为直接transfer（N1），但未识别两个关键障碍：(1) BlendedICU 42变量+17药物方案 vs RealExtraction实际变量域是否对齐；(2) 原文类不平衡和MNAR处理是否能在本地数据上获得同等保障。**

**主要问题**：
1. **N1过度假设**：原样套用训练代码的前提是数据格式和变量对齐，但未验证
2. **证据映射不足**：关键证据（E1/E3）**未精确到位置**，且证据对claim支撑有限
3. **缺失分支**：未讨论OMOP→RealExtraction映射失败场景、变量缺失时的降级策略
4. **N4证据来源不透明**：'delivery 07 yaml'是本地交付物，不是论文证据，不能与论文证据并列
5. **Mermaid图语义混乱**：'transfer/adapt/reuse/rewrite'混在同一层级，无优先级或依赖关系

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A1 | N1 | "训练/表图优先公开代码" 可原样套用 | **逻辑跳跃**：代码可用≠可原样套用。原文代码是为BlendedICU 42变量+17药物的schema设计的，RealExtraction若变量域不一致（如缺少某项实验室值），训练code不能直接运行。且原文使用TPC，需要检查本地数据的时间采样频率是否满足hourly采样要求。**"原样套用"没有任何前置验证条件** | E1来自github，但决策树未检查原文对数据维度的说明（Supp: "BlendedICU dataset comprises... 42 time series variables, and exposure to more than 100 drugs"）。**未验证本地数据是否满足该维度要求** | 改为："在**数据变量域对齐**前提下，训练/评估脚本可复用；需先做变量映射审计，标注缺失变量及其对TPC输入维度的影响" | **高** |
| A2 | N2 | "数据用本地真实提取+适配" | 表述模糊，**"适配"的边界和粒度未定义**。适配是发生在（1）特征映射层？（2）数据存储层？（3）模型输入层？不同的适配层次影响完全不同的内容。且原文对数据做了特定预处理（forward-filling + missingness masks + q5/q95归一化），这些**数据处理规则**是否也随"适配"一起迁移？ | Supp明确说明预处理规则（clipping + q5-q95归一化 + forward-fill + masks）。RealExtraction若已有自己的预处理管线（如delivery yaml），需要**对比两个管线是否能产出兼容的训练数据** | 将"适配"拆分为具体子任务：（1）变量映射表（本地变量→TPC输入维度）；（2）预处理对齐（clipping范围、归一化规则）；（3）缺失值策略确认 | **高** |
| A3 | N3 | "实验设计对齐原文" 可复用 | **实验设计对齐 ≠ 自动可复用**。原文有3个实验目的：generalization评估、多源训练策略对比、数据量效应分析。本复现是否有同样目标？若只复现单中心场景，很多设计元素（如transfer learning对比组、外部队列评估）**需要裁剪**。"四策略+TPC+指标定义可对齐"过于笼统，未区分哪些**绝对需要保留**、哪些**可根据场景裁剪** | E3引用"Methods"，但Methods包含大量内容（TPC训练、两阶段推理、分类损失、模型评测），**没有证据具体定位到哪一部分** | 先定义复现目标，再映射到原文实验设计中的具体要素，进行保留/裁剪/替换决策 | **中** |
| A4 | N4 | "预处理按delivery配置改写" | flow：E4是用户本地交付物，**不是论文证据**。将其作为Evidence Map的条目与论文证据并列，会产生**证据混淆**。且只说"改写"，但改写方向（adapting to 本地 vs. aligning with 原文？）不明确 | 原文明确写了预处理细节（Supp: "Clipping thresholds were defined a priori... q5/q95 normalized to [-1,1], clipped to [-4,4]"）。delivery yaml的预处理是否遵循相同规则，**无从判断** | 将E4移出Evidence Map，单独标注为"本地约束"。改写时需**对照原文预处理规格**，检查每个步骤是否对齐 | **高** |
| A5 | N5 | "engine:挂预后地基+78后缀batch/飞书" | 这是**用户工程需求**，不是从论文中推断的结论。将其标注为transfer节点会使"论文→实践"的决策树**混入与论文无关的工程决策**。且"Medical Blocks 78 batch"来源不清，决策树未解释其与原文的关系 | 原文无任何相关内容。该节点完全来自用户交互，**不应出现在论文驱动的决策树中** | 在决策树中单独增加"本地工程层"分区，与论文迁移决策分离标注；或将其移到Follow-up部分 | **中** |
| A6 | N2类型标注错误 | N2标为"transfer" | **类型标注错误**：N2本质是adapt（适配），不是transfer。将需要适配的内容标为transfer，暗示"可原样套用"，严重误导 | 对照N0的问题（"哪些可原样套用、哪些必须改写"），N2属于"必须改写"类别 | 重分类N2为adapt，并在N2中列出具体适配项；修改整体transfer/adapt/reuse标签 | **高** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E1 edge | N1→N0 | **无前置条件验证**。N1声称"可原样套用"，但A1指出变量域差异可能使"原样"不成立。需要增加一个**变量审计节点**作为N1的先决条件 | 在N1和N0之间增加：`变量域审计→若对齐则transfer；若不对齐则adapt`的分支节点 | **高** |
| E2 edge | N3→N0 | N3声称"四策略可对齐"，但未讨论**数据量约束**。原文明确：<5,000患者性能显著退化，>15,000出现平台期。RealExtraction四个库的总样本量和每库样本量是否满足？如果不满足，四策略中的"数据池化"是否还有意义？ | 增加"样本量审计"节点，与实验设计节点相连，判断绩效是否可达到原文的稳定区间 | **高** |
| E3 edge | N2→N0 | "适配层"只说了"存在"，未定义适配的**具体输入输出接口**。从RealExtraction原始数据到TPC训练数据的转换逻辑是什么？缺失变量如何填充？**数据schema 42+17的映射表是否已建？** | 为N2增加子节点展开：变量映射、缺失策略、采样频率对齐 | **中** |
| E4 edge | N4→N0 | "改写"的驱动因素是"delivery配置"，而非"原文要求"。**改写方向不明确**：是让本地配置符合原文？还是让本地配置替换原文预处理？ | 明确"改写"目标是使预处理产物满足原文特征分布要求（clipping + q5/q95归一化） | **中** |
| E5 edge | N5→N0 | 从"论文迁移决策"到"本地工程需求"，**存在类别跳跃**，没有传递逻辑 | 拆分为：本地工程决策（batch/飞书）与论文迁移决策（模型/数据/指标）两个独立分支 | **低** |

---

## 4. Evidence Problems

| problem_id | evidence | problem | suggested fix |
|---|---|---|---|
| P1 | E1 | 只写"github"，**未精确到具体文件**（训练脚本名称？数据预处理脚本？出表脚本？），依赖"代码存在"推断"可套用"，**证据到结论的推理链断裂** | 列出实际代码文件结构，标注哪些脚本可直接运行、哪些需要修改 |
| P2 | E3 | 引用"Methods"**过于笼统**。Methods中包含：TPC架构、两阶段推理、loss函数设计、实验设计（四策略）、评估方法（AUROC/AUPRC/MAPE/Mcomposite）。"四策略+TPC+指标定义可对齐"是从Methods多个部分拼凑的，**没有单一证据位置支撑** | 精确到具体小节/步骤（如"Model"段落，或"Experimental designs"），分别引用 |
| P3 | E2 | "训练未跑"是**状态描述**而非证据。决策树中标注为evidences的条目应当是**可验证的原文内容**，"训练未跑"是对交付物的状态说明，应单独标注 | 将交付物状态与原文证据分开，分别在不同层级引用 |
| P4 | E4 | delivery yaml是**本地交付物**，不是论文证据。与E1-E3并列违反了证据分类逻辑 | 将E4移出"Evidence Map"，作为"本地配置"单独节列出 |
| P5 | E1 | 关键：**github仓库是否包含完整数据schema？** 若只含训练代码而不含数据定义，则"可原样套用"无法被验证 | 核对github中是否包含数据schema/dictionary文件；若无，需单独获取BlendedICU schema |

---

## 5. Missing Branches

| branch_id | missing branch | rationale | priority |
|---|---|---|---|
| M1 | **变量域对齐审计** | 原文输入：42时间序列变量+17药物+人口学+单元类型。RealExtraction实际能够从四库中提取哪些变量？是否存在**变量缺失**？缺失率有多高？这直接决定N1（transfer训练代码）能否成立 | **P0** |
| M2 | **样本量/患者数审计** | 原文明确"minimum threshold of 15,000 patients is necessary for stable baseline performance"。RealExtraction四库能提取多少符合条件的患者？（按原文 5h后入院、hourly预测等条件过滤后）若不足，实验设计需调整 | **P0** |
| M3 | **N构造一致性验证** | PI-3中N的定义是否与原文一致？原文RLoS定义：出院前的剩余时间（survival conditional），起始于入院5h后，上限10天。RealExtraction是否有相同的stay划分逻辑？**多ICU episode、转科、离院后复入院**的处理是否一致？ | **P0** |
| M4 | **Mcomposite计算粒度** | Mcomposite需同时有AUROC（mortality）和MAPE（RLoS），且要求**内部验证基线**。本地复现是否也有内部/外部划分？RealExtraction四库打算合并训练还是单独训练？**Mcomposite的基线定义直接影响其解释** | **P1** |
| M5 | **评价维度差异** | 原文评价同时关注specialization（训练上看过的站点）和generalization（未看过的站点）。本地只有四库，若将其合并训练，则无外部验证站点，**generalization无法评估**。这是一个重大实验设计差异 | **P0** |
| M6 | **数据分割单元** | 原文按patient-level分割（70/15/15）。RealExtraction是否存在同一个patient多次入ICU？若有，**是否按patient而非stay分割**？ | **P1** |
| M7 | **缺失值策略兼容性** | 原文用forward-fill + missingness masks + q5/q95归一化 + clipping。RealExtraction的处理管线是否完全一致？若不一致，训练数据的分布会偏移，**影响图像复现** | **P1** |
| M8 | **与现有地基引擎的接口** | 用户提到"挂预后地基"，但原文的TPC输出是每小时更新的二元时序。现有地基引擎能否支持这种时序输出，还是只能接受静态评分？**接口兼容性未检查** | **P1** |
| M9 | **数据许可/合规** | RealExtraction四库使用许可是否允许训练深度模型用于研究？MIMIC-IV有CITI培训要求，eICU有相应协议。**合规性未核查** | **P2** |
| M10 | **基线对比组** | 原文对比了transformer/LSTM/TPC。本地是否需要重新benchmark？还是直接采用TPC？若直接采用，将无法证明TPC在本地数据上的优异性 | **P2** |

---

## 6. Required Fixes

AI-A **必须**进行以下修改：

1. **【高】将N1的transfer改为条件化transfer**——必须先完成变量域对齐审计，确认RealExtraction特征集与BlendedICU 42+17 schema匹配，才能决策"原样套用"。

2. **【高】拆分N2为具体适配子任务**——列出变量映射表、缺失策略、采样频率对齐等具体任务，确保"适配"是可执行的工程任务而非模糊概念。

3. **【高】修正N2节点类型**——将N2从transfer改为adapt，确保决策树类型标注逻辑一致。

4. **【高】移除E4或单列"本地配置"节**——delivery yaml不是论文证据，不应与论文证据混同；同时明确改写目标是"对齐原文预处理规格"。

5. **【高】增加样本量审计节点**——根据原文>15,000 patient阈值，评估RealExtraction各库样本量是否满足。

6. **【高】讨论generalization评估维度**——明确本地四库合并后的validation策略（内部validation only vs. 有外部站点）。若无外部站点，需明确告知用户Mcomposite的generalization维度无法复现。

7. **【中】将N5移到"本地工程"分区**——与论文迁移决策分离，标注来源为用户需求而非论文。

8. **【中】补充N构造验证细节**——PI-3同规则重抽是否能保证与原文一致？需要列出具体的变量映射和过滤规则清单。

9. **【中】为N3补充实验目标裁剪说明**——若本地只追求复现单源训练效果，可裁剪transfer learning和generalization评估部分；若追求完整复现，则必须有外部验证站点。

10. **【中】核对github代码清单**——将E1精确到具体脚本，列出哪些可复用、哪些依赖BlendedICU schema可能需要改写。

---

**AI-B裁定**：当前决策树结构过于简单，主要问题集中在N1和N2——"可原样套用"的结论**未经验证**地下了。最重要的缺失分支是：**变量域对齐审计**和**四库样本量评估**——这两个条件若不满足，整个"原样套用"的结论都可能不成立。建议大改后进入下一轮。