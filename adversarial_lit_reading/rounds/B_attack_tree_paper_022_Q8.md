<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-09-30T11:27:33 | request_id=msg_5b5f9911-00ed-4479-b1bc-b6b7218c222e | usage={"input_tokens": 6876, "output_tokens": 3625, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=6870 -->
# AI-B Tree Attack Report

**paper_id:** paper_022  
**question_id:** Q8  
**review_target:** `@rounds/A_tree_round1_paper_022_Q8.md`  
**source_file:** Wang et al. 2026, Cardiovascular Diabetology 25:78

---

## 1. Attack Summary

**总体判断：需要重大修改**

**主要问题：**

1. **核心缺陷**：N3 声称"发表键一对一复现清单可原样对齐"，与原文存在关键操作矛盾——原文的 `Class 2 (persistent low)` 为参照组，但 N3 未提及经典聚类后类排序的非确定性，且 E2 误将 `logistic M1-3` 列为可平移套路（原文为单一调整模型，非递进三模型）。
2. **因果过度**：N2 "单库 batch" 表述正确但 N1 → N2 推理跳跃（见边攻击），且 AI-A 未捕获原文方法中累积暴露时间乘子的关键细节（2012–2015 间隔作为乘子，期 3 不可测是合理推断但需确认）。
3. **证据定位问题**：E2 的证据位置笼统标注 `Methods`，未具体到原文节段（如 Cumulative eGDR 计算式、k-means 输入特征定义），违反了证据可追溯原则。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A1 | N1 | 发病地基 + 聚类累积暴露后缀（3B） | 原文 CKM 分期为基线（2012）测量，非"地基"；用户地基框架（incidence-foundation）是外部约束，原文未验证此结构。N1 的 claim 将外部工程约束与原文设计混合，属节点属性混淆 | 原文：CKM stage baseline (Wave 1, 2012)，eGDR 2012/2015 两时间点 → 不是"发病地基+后缀"结构 | 添加限定：N1 反映的是用户工程框架，非原文设计。在 node 中拆分为 `用户约束` 与 `原文证据` 两个子节点 | **高** |
| A2 | N2 | 单库 CHARLS 并行 batch | 正确——原文确实仅用 CHARLS 单队列。但 N2 的 confidence 标注为 "high" 缺乏对 batch 并行单元（按暴露口径还是按 CKM 层）的说明，ashamedly U2 在 follow-up 才提出 | 原文：明确 CHARLS 唯一数据源（"single cohort"） | N2 保留，但需声明 batch 划分尚无原文依据，为工程决策 | **低** |
| A3 | N3 | 图/表键一对一复现清单可原样对齐 | **严重问题**：原文 Fig 2 的四个聚类标签（Class 1–4）为 k-means 结果，类编号本身不确定（k-means 随机初始化、类排序非语义化）。FOLLOW 复现时要保证类标签与语义对应（如 "persistent low" + "rapid decrease"），需额外校验——AI-A 的 "一对一" 暗示直接映射，实际需要重映射逻辑 | 原文：k-means 随机初始化 + elbow k=4 → 类排序依赖种子 | "原样对齐" 改为 "需设计类标签映射（基于每类均值变化方向语义）后再对齐"。明确 k-means 种子/标准化为必须改写的工程项 | **高** |
| A4 | N4 | 必须按本数据改写纳排/分期与 N 口径 | 正确，但不够具体。原文纳排：5248 人（≥45岁，CHARLS）。期 3 不可测应在 N4 中明确列示（原文 Methods 对分期定义：Stage 3 = subclinical CVD，CHARLS 缺乏无症状动脉粥样硬化/左室功能数据） | 原文：Stage 3 定义依赖影像学/超声 → CHARLS 无此数据 | 补充 `期3不可测` 的具体缺失字段（如颈动脉超声、LVEF），列出处理策略（合并/排除/敏感性） | **中** |
| A5 | N5 | Blocks 复用优先；新建 k-means 后缀 | 方向正确。但 E4 声称 Block 库 "缺 k-means+elbow 专用后缀块" 未提供证据支持（如库文件列示）。应区分 Blocks 缺具体抽象与缺实现 | 原文：k-means + elbow（WCSS）方法在 Fig 2 有完整步骤 | 在新块中明确：输入 = 两时间点 eGDR（2012/2015）宽表；输出 = 四类标签 + elbow 图。用原文公式给出标准化/特征定义 | **中** |
| A6 | N6 | 不可把 LCMM 轨迹发病块冒充本文 k-means | **正确且重要**——原文方法明确为 k-means 两步输入（2012 与 2015 两个时间点），不是 LCMM（latent class mixed model）。但 N6 的 confidence "high" 与 limitation 类型混淆：N6 是工程排除项，不是可迁移性不足，应为 `NN`（negative）节点 | 原文：`k-means clustering ... eGDR values from both 2012 and 2015 as input features` | 保留 N6 但改节点类型 —— 工程禁令节点，同时补充正面表达："确认 52_trajectory_incidence 中方法为 LCMM，本文应选 k-means" | **低** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| A7 | N1 → N2 | "单库 CHARLS" 并非 N1 的推论——这是原文数据来源的固有属性，不是"地基+后缀"结构的逻辑后果。边标注 `leads_to` 不成立 | 改边类型：N2 直接从 E1 证据（用户确认）导出，而非 N1 → N2 | **中** |
| A8 | N1 → N3 | "原样对齐" 与 N1 的工程约束冲突——N1 要求挂本地基 + 后缀，而原文设计是直接 eGDR→聚类→回归，无地基层。边应体现"需加适配层而非对齐层" | 修改边语义：N1 → N3 改为 `requires_adaptation`（需适配），而非无条件的 `leads_to` | **高** |
| A9 | N3 → E2 | **严重证据错位**：N3 声称"一对一复现清单对齐"由 E2 支持，但 E2 的 `logistic M1-3` 与原文不符（见攻击 A10、A11）。E2 中列出"k-means+elbow"在原文 Fig 2 有据，但 N3 的表述过于简化 | E2 需拆分：分方法项（logistic 模型、RCS、k-means 流程的具体原文行）与发表物项（Fig/Table 编号）分开呈现 | **高** |
| A10 | N3 → `logistic M1-3` | **原文无 M1-3 递进模型**——摘要显示单一"fully adjusted model"（调整年龄、性别、婚姻状况），Methods 未提三个递进模型。AI-A 的 E2 误导用户以为原文有多模型套路可复用 | 核对原文 Methods 确切模型描述；若确为单模型，则 E2 改写为 "logistic（本数据的递进 M1-3 为自定义设计，非原文迁移）" | **高** |
| A11 | E2 → "RCS" | 原文：RCS 确认线性关系（P-nonlinearity = 0.259），但 RCS 未报告多模型（M1-3）比较。原文 RCS 是验证线性的辅助，不是独立分析维度 | E2 增加限定：RCS 在原文只做线性检验，未做多模型分层 RCS。迁移时需声明范围 | **中** |
| A12 | N4 → E3 | E3 声称 "期3不可测"，但原文对 Stage 3 定义需要影像学（无症状动脉粥样硬化）；CHARLS 缺乏对应变量。此推论合理，但引用原文证据不足——原文定义 vs 数据缺失是两回事，应分开表示 | 在 E3 拆分为：`原文定义`（Stage 3=subclinical CVD）与 `用户数据缺失`（CHARLS 无对应测量）两个证据 | **中** |

---

## 4. Evidence Problems

- **P1（严重）**：`E2` 中 "logistic M1-3" 无原文依据——原文为单一多元模型（"fully adjusted model"），未报告模型 1、2、3 递进过程。若用户要复现原文，应报告单模型 + 敏感性；若自建递进，为自定义设计，不能标为"可平移"。
- **P2（严重）**：`E2` 将 Table 1、Fig 1–3 笼统归为可对齐，未指出 Fig 2 中 k-means elbow 的 WCSS 曲线是否为可复现的标准（原文未提供 elbow 图数据、只说明 k=4 选择逻辑）。复现时需要用户自定义 WCSS 计算与肘部判读的稳定规则。
- **P3（中）**：N5 声称 Block 库 "缺 k-means+elbow 专用后缀块"，但 E4 来源为 `Blocks库`，未列出用户 Blocks 库中现有块清单。AI-A 依据的库描述可能不完整，无法独立验证。
- **P4（中）**：`E1`（用户确认）作为证据用于 N1 的 `supported_by` 不合适——用户确认（外部约束）不等于论文证据。证据分层应区分 `原文证据` 与 `用户需求证据`。
- **P5（低）**：Mermaid 中 N3 只挂 E2 一条证据，但 N3 内容包含 Fig1/Table1→3/S1–S4/FigS1–S3 的完整复现清单，原文结果中的 Figures/Tables 位置应精确到页面（Fig1 = page 5 流程；Fig2A/B/C 分布不同页；Table1 = page 6），建议精确页码以利追溯。

---

## 5. Missing Branches

| missing_branch_id | missing context | source evidence | suggested addition | severity |
|---|---|---|---|---|
| M1 | **k-means 输入标准化与聚类稳定性**：原文输入为 2012/2015 两时间点 eGDR 原始值（不同分布、均值不同），未提标准化；但 eGDR 单位/变异范围一致。复现需决定是否 Z-score，及多个种子是否做稳定性评估 | 原文：`k-means clustering using eGDR values from both 2012 and 2015 as input features`（无标准化说明） | 在 N5 前加决策节点：输入特征是标准值还是原值，种子数/多轮一致性校验；引用常见 k-means 稳定性实践 | **高** |
| M2 | **累积暴露的计算口径**：原文 `(eGDR2012 + eGDR2015)/2 × (2015–2012)` —— 时间乘子为 3 年；若用户数据暴露窗口不同（如 2015–2020），需改写乘子与单位。AI-A 在 Provisional answer 中提了"乘子口径"但树中无对应节点 | 原文 Methods 明确公式 | 新增节点：暴露窗口长度（年）作为参数化设置，并作为敏感性分析变量 | **中** |
| M3 | **结局时间窗与竞争风险**：原文随访 2015–2018（3年），未报告竞争风险模型（死亡）。用户 CHARLS 若随访更长（2015–2020+），需考虑死亡竞争与随访截止差异。AI-A 仅在敏感性列了 Cox/MICE，未讨论竞争风险 | 原文：follow-up 2015–2018，336 例 | 增加分支：结局窗口设置 + 竞争风险模型（Fine-Gray）作为敏感性 | **中** |
| M4 | **CKM 分期在 eGDR 与结局关系中的角色**：原文做了 "across all CKM stages (0–4)" 的分层/调整分析，即分期可能是效应修饰因子。AI-A 树未提及 CKM 分期在模型中的角色（分层 vs 调整 vs 交互） | 原文：标题含 "stages 0–4"，结论提到 "across all stages" | 增加决策节点：CKM 分期在分析中是协变量（调整变量）、分层因子、还是效应交互项——三种处理对应不同模型解释 | **高** |
| M5 | **eGDR 公式的缺失值处理**：`HTN`（presence=1）需要三要素（诊断/用药/≥140/90），HbA1c 缺失时如何处理（原文未注明），CHARLS 结构需按数据缺失分支 | 原文 HTN 定义三要素 → 缺失时该变量如何归 | 在 N4 纳排改写下增加缺失分支：HTN 三要素任一缺失是否排除；HbA1c 缺失 imputation 策略（MICE 在敏感性已列，需提前指定变量级处理） | **中** |

---

## 6. Required Fixes

1. **[高] 修正 E2 的 `logistic M1-3` 表述**——原文只有单一 fully-adjusted model，需改为单模型迁移，或明确标注 M1-M3 为自定义扩展，不属于"原样平移"范围。同时在 N3 对应显示该局限。
2. **[高] 将 N3 的"一对一复现"改为"需类标签语义映射 + k-means 稳定性校验"**——k-means 类编号非语义化（随机种子影响类顺序），需要额外设计对照规则：基于每类均值（2012/2015）方向与水平做语义标签（如 persistent low / rapid decrease），确保与原文 Fig 2 语义对应。
3. **[高] 在树中添加 M4 分支**——CKM 分期在所设计模型中的角色（调整 vs 分层 vs 交互），因原文明确涉及分期分级并可能检测效应差异。
4. **[中] 在 N4 或新节点中具体化"期3不可测"**——列出具体缺失字段（如颈动脉超声、LVEF），并给出处理策略（排除期3 / 合并压缩 / 敏感性）。
5. **[中] 在 N5 的 Blocks 复用中明确 k-means 新块的 I/O**——输入（两时间点 eGDR 宽表）、参数（k、种子数、标准化）、输出（四类标签、elbow 图、轨迹图）、校验（多个种子下的类分配一致性）。同时在 E4 中补充库清单佐证。
6. **[中] 修正图/表复现清单的页码标注**——按原文逐项映射（Fig 1 为流程图、Fig 2A elbow、2B 两时间点均值线、2C 分布热/箱图），避免"一对一对齐"的笼统表述，并为每项标注所需输入数据与代码块的对应关系。
7. **[中] 在省略分支中补充累积暴露乘子参数化**——暴露窗口长度、时间单位、干预时间（原文为 2012–2015），对长随访需作为敏感性维度。
8. **[低] 重质 N5 的 Blocks 声明**——"缺 k-means 后缀块"应从"Block 库含/不含"的实证性描述中取证，并在不确定时标注 `需复核库清单`，避免在无证据情况下下结论。

---

**一致性说明**：所有攻击均基于原文提供的摘要、Methods 片断（图 1–3 方法，结果部分，Fig 1/Fig 2 有页级证据）进行逐项比对。待补的证据（如 CHARLS 数据缺失变量的完整清单、Blocks 库内部清单）已在对应攻击中标注 `需复核原文/库`。