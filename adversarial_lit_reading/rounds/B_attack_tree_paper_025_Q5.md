<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-10T15:45:52 | request_id=msg_63f874ad-8cc5-4577-be20-69e87aed2ba6 | usage={"input_tokens": 12225, "output_tokens": 2938, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=5705 -->
# AI-B Tree Attack

paper_id: paper_025
question_id: Q5
review_target: @rounds/A_tree_round1_paper_025_Q5.md
source_file: Methods + MOESM1

## 1. Attack Summary

总体判断：**部分可信，需要重大修改**

---

主要问题：

1. **关键公式节点缺失**：AI-A 未将归一化公式（q5/q95 → [-1,1]，再 clip [-4,4]）和损失函数（L = BCE + α·MSLE）作为独立节点纳入树，导致"依赖哪些参数假设"回答不完整。
2. **N4 结论过度绝对化**：将"非 NHANES 加权"扩大为"无加权设计"，但原文对多源数据差异仅用分离式数据集划分处理，未明确声称完全放弃所有加权/重采样策略。
3. **E5 证据位置不明确**：α=20 的具体数值在正文未给出，需追溯至 Supplementary Material 才能确认，E5 引述不够精确。
4. **N1 对 MNAR 处理机制的解读不够精确**：原文说明 MNAR 的两个成因（采样差异 + 病情依赖），以及为什么 FF+mask 适用于 MNAR（对比 MAR 假设的其它方法），AI-A 未充分区分"描述 MNAR 结构"与"FF+mask 对该结构的适用性论证"。
5. **N3 划分机制细节不完整**：原文明确说明"按 source database 分区后，再在每个分区内按患者级 70/15/15 拆分"，而非全局患者级划分——这是重要细节差异。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A1 | N1 | "MNAR处理=FF+mask" | 表述将 MNAR 假设与处理方法混为一谈。原文先论证为何 MNAR（两个机制），再说明为何选择 FF+mask（避免 MAR 假设、保留时序结构、利用缺失信息）。AI-A 应区分假设本身与处理选择。 | 原文 Data preprocessing 段：明确描述 MNAR 两机制，再引入 FF+mask。 | 拆分节点：N1a (MNAR 假设：两机制论证) → N1b (FF+mask 作为处理策略及其合理性) | **中** |
| A2 | N2 | "双阶段clip/归一化" | 节点表述不够精确：实际流程是"先 clip 到生理合理范围 → 然后 q5-q95 归一化到 [-1,1] → 再 clip 到 [-4,4]"。是三阶段而非"双阶段"。且 q5/q95 是数据驱动的分位数（非固定值），AI-A 未指出这一数据依赖特性。 | 原文 Supp：明确三步流程，q5/q95 为数据分位数。 | 改为"生理clip→分位归一化(q5~q95→[-1,1])→二次clip[-4,4]"三步，并标注 q5/q95 为数据驱动参数。 | **高** |
| A3 | N3 | "70/15/15患者级" | 未说明划分是按 source database **分区后**再进行的患者级划分（而非全局随机划分）。这对"防泄漏"的含义理解有实质影响——分区划分是保证每个 partition 内部有独立的 train/val/test。 | 原文 MOESM1 Model evaluation 段："The BlendedICU dataset was partitioned using the source database of each patient. Each partition was split into..." | 补充"按 source 分区后患者级 70/15/15"的完整表述 | **高** |
| A4 | N4 | "非加权设计" | 结论过度放大：原文没有讨论加权问题，只说明"没有使用 survey 权重"——但 N4 声称"非加权设计"，暗示作者有意选择了非加权策略。应弱化为"未提及加权/重采样策略"。 | 原文无任何与"加权"相关的讨论。 | 改为"未见加权设计（原文未讨论）"或"N/A" | **中** |
| A5 | N5 | "α=20,cap=10 预先设定" | AI-A 将两个不相关参数捆绑在一个节点。α 是损失函数的加权系数（BCE+α·MSLE）；cap=10 是 RLoS 的上限预测值（capped 到 10 天），两者分属不同机制。且 α=20 数值在正文未出现，需要定位到 Supplementary 公式。 | 正文无 α 数值；MOESM1 中给出 α=20 及 RLoS cap 到 10 天的说明，但两者是独立超参。 | 拆分为 N5a (α=20 损失加权系数) 和 N5b (RLoS cap 10天；>10天预测等价于"≥10天") | **中** |
| A6 | —— | **缺失节点：归一化公式** | 归一化公式本身是"依赖哪些参数假设"的直接回答（依赖 q5/q95 数据分位数、[-1,1]、[-4,4]），作为方法节点应独立呈现。 | MOESM1 含完整公式。 | 新增节点 N2b：归一化公式 y'=(y−q5)/(q95−q5)·2−1，再 clip [−4,4] | **高** |
| A7 | —— | **缺失节点：损失函数设计** | 损失函数 L = BCE(yM, ŷM) + α·MSLE(yL, ŷL) 的条件应用（仅对存活患者计算 RLoS 损失）是方法核心参数假设，AI-A 完全遗漏。 | MOESM1 有公式和 α=20。 | 新增节点 N5c：两阶段联合损失，仅存活患者计入 RLoS 损失，加权系数 α=20 | **高** |
| A8 | —— | **缺失节点：两阶段预测设计** | RLoS 预测前提是"假设患者存活出院"（two-stage：先预测死亡率，再预测存活条件下的出院时间）。这一关键假设影响 RLoS 的语义。 | MOESM1：RLoS prediction assumed that the patient was discharged alive。 | 新增节点：RLoS 为条件预测（给定存活），两阶段流程 | **高** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| B1 | N0 → N1 | 从"Q5假设"直接连到"MNAR+FF+mask"暗示该假设成立，但缺失两层——①MNAR 的论证强度（依据引用而非实测验证）；②FF 的上游假设"生理值在测量间隔间稳定"（原文明确承认是简化假设）。 | 边应标注"假设+简化"性质；补充 N1b 的上游前提节点 | **中** |
| B2 | N0 → N2 | 未指出归一化参数 q5/q95 是**数据依赖**的（随训练集变化），即不同 source 或不同重采样下归一化参数不同。这影响跨库可比性。 | 补充说明 q5/q95 从训练集数据计算 | **中** |
| B3 | N0 → N4 | N4"非加权设计"是一个**缺席证据**（absence of evidence），原文未提起即为未涉足。将"原文没说"转化为"方法设计"属于过度解读。 | 降级处理，标注"N/A（原文未提及）"或删除 | **中** |
| B4 | N0 → N5 | 将"loss 加权参数 α=20"和"RLoS 预测 cap=10"合并在一个节点掩盖了两者分属不同机制（前者影响训练权重，后者影响预测输出语义）。 | 拆分为两条独立边。 | **中** |
| B5 | —— | **缺失边**：从"损失函数（含 α=20）"到"两阶段预测设计"——两者在实现上耦合：损失在存活条件下才计算 RLoS 项；但预测时对所有患者都输出死亡概率与 RLoS。AI-A 未呈现这一条件性。 | 补充条件损失与两阶段预测的关系边 | **高** |

---

## 4. Evidence Problems

| problem_id | issue | location | detail | severity |
|---|---|---|---|---|
| E-P1 | 证据位置不精确 | E5 | E5 标记为 "config/paper" 指向 α=20，但 α=20 在正文完全未出现，仅存在于 MOESM1 的损失函数定义中。应标记来源为 "MOESM1 (损失函数定义)" 而非 "config/paper"。 | **中** |
| E-P2 | 公式缺失 | MOESM1 | 归一化公式未作为节点呈现，但公式本身定义了 q5/q95 依赖的数据分布假设——这直接影响"依赖哪些参数假设"的回答完整性。 | **高** |
| E-P3 | 损失函数未入树 | MOESM1 | L = BCE + α·MSLE 且 RLoS 项仅在存活患者上计算，这是方法中最重要的条件假设之一，AI-A 完全遗漏。 | **高** |
| E-P4 | 过度引用 | Methods + MOESM1 | E4 引用 "Methods" 标为"非 NHANES 加权"，但 Methods 中从未讨论"加权"问题。该证据实为"原文未提及"，不应作为正面证据。 | **中** |
| E-P5 | 数据依赖未标注 | MOESM1 | q5/q95 分位数、clip 范围 [-4,4] 均为预设超参，但其数值依赖训练集分布（q5/q95 随数据变化）。AI-A 未标注此数据依赖特性。 | **中** |

---

## 5. Missing Branches

| branch_id | missing branch | importance | rationale |
|---|---|---|---|
| M1 | **归一化公式节点（独立）** | 高 | 归一化公式直接定义参数依赖：q5/q95（数据驱动）、[-1,1]目标区间、[-4,4]截断。Q5 问"依赖哪些参数假设"，这是直接回答。 |
| M2 | **损失函数节点（含α=20）** | 高 | 损失函数 L = BCE + 20·MSLE（条件：仅存活患者计入 RLoS）是"超参"问题的核心内容之一。 |
| M3 | **两阶段预测设计节点** | 高 | "RLoS 预测假设患者存活出院"是 RLoS 语义的关键前提，影响读者对 RLoS 预测值的理解。 |
| M4 | **生理clip阈值的先验设定分支** | 中 | 原文说明"clipping thresholds were defined a priori based on physiological plausibility"——这是"依赖哪些参数假设"的直接证据，AI-A 未提取。 |
| M5 | **特征选择分支（17种药物）** | 中 | 特征选择是参数假设的一部分（17药物的选择依据），AI-A 未涉及。 |
| M6 | **结果输出起始时间（5h后）分支** | 低 | 原文 "predictions from 5 h after admission onward" 是输出参数假设，AI-A 未包含。 |

---

## 6. Required Fixes

1. **拆分为独立节点并区分参数类型**：将超参分为三类并分别节点化——(a) 归一化参数：q5/q95 分位数（数据驱动）、范围 [-1,1]、clip [-4,4]；(b) 损失参数：α=20 加权系数、条件损失机制（存活患者才计入 RLoS）；(c) 输出/结构参数：RLoS cap 10 天、预测起始时间 5h、两阶段设计（先死亡率后存活条件下 RLoS）。
2. **修正 N2 的"双阶段"表述为三阶段流程**：生理 clip → q5/q95 归一化 → 二次 clip，并明确 q5/q95 为数据依赖参数。
3. **补充 N3 为"按 source 分区后患者级 70/15/15"**：明确划分是先按数据库分区、再在分区内做患者级分割，而非全局随机划分。
4. **N4 降级处理**：改为"N/A——原文未讨论加权/重采样策略"，并注明这是缺席证据而非设计决策。
5. **严格区分 N1 中的"MNAR 假设论证"与"FF+mask 处理策略"**：将 MNAR 的论证（两机制）与 FF+mask 的适用性推理分别成边，并标注 FF 的上游简化假设（生理值稳定假设）。
6. **新增两阶段预测设计节点**：明确 RLoS 的语义为"给定存活的条件预测"，这是理解整个方法框架的关键假设。
7. **修正证据引用精度**：α=20 应标记来源为"MOESM1 损失函数定义"，生理 clip 阈值依据为"MOESM1：a priori 基于生理合理性设定"。删除对"非 NHANES 加权"的正面证据标注。
8. **补充特征选择与输出起始时间**：将"17 种药物选择"和"5h 后开始预测"作为参数假设的补充节点低优先级纳入。