<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-10T15:44:30 | request_id=msg_a59904e1-d27a-49b7-a00e-49610aad41e2 | usage={"input_tokens": 12255, "output_tokens": 6215, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=14233 -->
# AI-B Tree Attack

**paper_id:** paper_025  
**question_id:** Q3  
**review_target:** @rounds/A_tree_round1_paper_025_Q3.md  
**source_file:** paper_025 (Allyn et al. 2026) + MOESM2 (Supp)

---

## 1. Attack Summary

**总体判断：需要重大修改**

**主要问题：**

1. **核心节点 N2 证据过度外推**：AI-A 声称"Table S2 多数优于 LSTM/TF"，但原文仅说"TPC outperformed both alternatives on most subsets and both prediction tasks"，且未提供具体数字——这是**方向正确但强度过度**的表述，且没有指出"多数子集"≠"所有子集"的边界。
2. **N1 定位不完整**：AI-A 将 TPC 定位为"处理静态+动态"架构正确，但**遗漏了 TPC 被引用的核心依据**——Rocheteau et al. 的原始论文（引用 [25]），以及本文"采用 TPC 前的预基准测试"这一关键动机。
3. **N4 节点严重缺失**：AI-A 声称"池化常最优"过于含糊——Table 3 中**池化在 MIMIC-IV 专业化上反而最差（Mcomposite 0.97 vs 单源 0.89）**，这是明显的**反例节点**，AI-A 完全没有提及。
4. **N3 的"线性"类比不够精确**：原文指的是**基于生理评分的线性回归**（SOFA/SAPS II/APACHE），不是一般意义的"线性模型"——AI-A 的表述有**偷换概念**风险。
5. **方法层面严重遗漏**：Q3 问的是"**换方法结论会变吗？**"，AI-A 的 Uncertainty 只提到"训练策略 × 架构未网格化"，但**完全遗漏了更深的危机**——本文所有实验都在 TPC 单架构上完成，**没有任何证据表明池化优势在 LSTM/Transformer 下仍然成立**，且原文明确承认"site-specific features acted as shortcuts"（站点特征作为捷径），这意味着架构更换可能导致完全不同的结论。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A-N1-01 | N1 | "method:TPC处理静态+动态" | 不完整——遗漏了 TPC 的**来源依据**（Rocheteau et al. 原文 [25]）和本文采用 TPC 前的预基准测试流程（benchmarked LSTM/TF/TPC on all four databases） | 原文 Methods: "We used the Temporal Pointwise Convolution (TPC) architecture, a deep learning model specifically designed for ICU time series data that has demonstrated superior performance over alternative architectures" + "Prior to adopting TPC, we benchmarked three state-of-the-art architectures" | 补充：TPC 为 Rocheteau 提出的 ICU 专用架构；本文在四个库上都先做了三架构基准测试后才选定 TPC | **中** |
| A-N1-02 | N1 | "method:TPC处理静态+动态" | 原文对 TPC 架构的静态/动态处理能力有**更具体表述**：supp 说 "This architecture was introduced to handle both static (tabular) and dynamic (temporal) data"——AI-A 正确但不够精确 | Supp Methods: "This architecture was introduced to handle both static (tabular) and dynamic (temporal) data, which is essential when dealing with data from electronic medical records" | 补充"tabular + temporal"的精确表述，并指出这是 TPC 与纯序列模型（LSTM）的关键架构差异 | **低** |
| A-N2-01 | N2 | "evidence:TableS2多数优于LSTM/TF" | **强度过度**——原文只说 "most subsets"（多数子集），不是"大多数任务/库"；且原文未给出具体数字，AI-A 无法从 Table S2 直接验证"多数"的范围。更关键的是，**eICU 死亡预测的 AUROC 例外**（AI-A 在 N2b 中已有提及）**在原文中只有"可能是"级别的暗示**——原文根本没有明确说 TPC 在 eICU 死亡上"非最优"，这是 AI-A 从 Table S2 自身的推断，但 AI-A 没有标注这是推断而非原文明确结论 | 原文: "TPC outperformed both alternatives on most subsets and both prediction tasks; full results are provided in Additional File 2 (Table S2)" | 改为："Table S2 显示 TPC 在大多数子集和两个任务上优于 LSTM 和 Transformer；但 AI-A 从 Table S2 中观察到的'多数'具体范围（如多少个子集、哪些任务）需以 MOESM2 表格的完整内容为准，AI-A 未能访问完整表格，故'多数'的具体含义存疑" | **高** |
| A-N3-01 | N3 | "claim:相对既往线性LOS假设改用时序模型" | **偷换概念**——原文的"线性"特指**基于生理评分（SOFA/SAPS II/APACHE）的线性回归模型**和**多元线性回归**，不是一般意义的"线性模型"；原文也提到 random forest / gradient boosting 也用于非时序数据（同样是静态输入），AI-A 的简化表述会误导读者以为对比对象只有"线性 vs 非线性" | Supp: "including simple linear regression models based on physiology scores (SOFA, SAPS II, APACHE) and multiple linear regression models... Machine learning models, such as random forest and gradient boosting methods, have also been utilized for non-temporal data" | 改为："相对基于静态评分的线性回归（SOFA/SAPS II/APACHE）和静态机器学习（RF/GBM），本文采用小时级时序深度学习（TPC），实现动态风险更新" | **中** |
| A-N3-02 | N3 | "claim:相对既往线性LOS假设改用时序模型" | 遗漏了**本文为何需要动态更新**的论证——原文在 Introduction 中给出了**明确的临床动机**："Unlike static admission-time prediction scores, our model updates predictions continuously and hourly throughout the ICU stay, providing a dynamic trajectory of risk rather than a single estimate"——这对"为何选这种方法"是**关键支持**，AI-A 的节点太简略 | Introduction: "Unlike static admission-time prediction scores, our model updates predictions continuously and hourly throughout the ICU stay, providing a dynamic trajectory of risk rather than a single estimate of a non-actionable outcome" | 补充节点："动态小时级更新提供了风险轨迹而非单一估计，这是相对静态评分的核心临床价值" | **中** |
| A-N4-01 | N4 | "evidence:Results Table3池化优于/不劣于迁移与单源（视任务）" | **过于含糊且遗漏反例**——"视任务"三个字掩盖了两个关键事实：(1) **在 MIMIC-IV 专业化上池化反而最差**（Mcomposite 0.97 vs 单源 MIMIC 0.89，9.0% 劣势），这不是"不劣于"而是"劣于"；(2) **在 AmsterdamUMC 专业化上池化与迁移几乎无差异**（Mcomposite 1.07 vs 1.08，AUROC 0.75 vs 0.76，CI 重叠）——这不是"池化突出"。AI-A 的"池化突出"表述只对**泛化**成立 | Table 3: "data pooling incurred a performance cost for specialization on MIMIC-IV: its Mcomposite (0.97) was 9.0% higher than that of the MIMIC-IV single-source model (0.89)" + "The two strategies, data pooling and transfer learning, performed virtually identically on mortality discrimination" | 拆为两节点：(1) 泛化（eICU+HiRID）上池化最优；(2) 专业化上池化在 MIMIC-IV 上**劣于**单源、在 AmsterdamUMC 上与迁移**几乎无差异**（仅 RLoS-MAPE 有非重叠 CI 的优势） | **高** |
| A-N4-02 | N4 | "evidence:Results Table3池化优于/不劣于迁移与单源（视任务）" | **遗漏了池化 vs 迁移在 RLoS 上的关键差异**——原文认为这是"可能更有操作意义"的发现（"arguably the more operationally sensitive of the two outputs"），AI-A 完全忽略了这一解释性论述 | Result: "data pooling demonstrated a meaningful advantage over transfer learning for RLoS prediction specifically, with a MAPE of 84.49 compared to 89.24... arguably the more operationally sensitive of the two outputs" | 补充：池化对 RLoS 的改善（MAPE 84.49 vs 89.24，非重叠 CI）被作者强调为操作上更敏感的指标，这是池化优于迁移的关键证据 | **中** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| A-E-01 | N0 → N1 (Q3 为何TPC → method:TPC处理静态+动态) | 该边**跳过了"TPC 在预基准测试中胜出"这一关键前提**——本文不是主观选择 TPC，而是先在四个库上跑了三架构基准测试才选 TPC。AI-A 的 N1 没有反映这个**选择过程** | 在 N0 与 N1 之间插入节点："预基准测试：在 BlendedICU 全部四个子集上比较 Transformer/LSTM/TPC，TPC 在大多数子集和两个任务上胜出（Table S2）" | **中** |
| A-E-02 | N1 → N2 (TPC处理静态+动态 → TableS2多数优于LSTM/TF) | 这条边**暗示 N2（Table S2 证据）是对 N1（方法定位）的支持**，但逻辑上 N1 是"TPC 能处理静态+动态"，N2 是"TPC 优于 LSTM/TF"——这两个声称的证据来源不同（一个是架构设计特征，一个是经验比较），AI-A 没有区分。更严重的是 N2 作为 N1 的证据不充分：**即使 Table S2 未证明 TPC 最优，也不否定 TPC 能处理静态+动态数据** | 将 N1 和 N2 拆为平行分支：N1 用架构设计描述支持（supp），N2 用 Table S2 经验证据支持；注明"即使经验比较不能推广，架构设计仍支持 TPC 的适用性" | **中** |
| A-E-03 | N0 → N4 (Q3 为何TPC → claim:训练策略比较池化常最优) | **逻辑断裂**——Q3 问的是"为何选 TPC"，N4 说的是"训练策略比较中池化最优"，这两者之间没有直接推理关系。AI-A 没有解释为什么一个关于"为何选这个架构"的问题需要回答"训练策略哪个好"。真正必要的推理是：**训练策略的比较结果会如何影响结论的稳健性**——即如果换架构是否改变池化优势 | 将 N4 重新定位为"训练策略比较的结论是本文核心发现的一部分，但其是否依赖 TPC 架构未验证"——这才是 Q3 真正相关的问题 | **高** |
| A-E-04 | N2b → Provisional Answer | AI-A 在 Provisional Answer 中给出了"eICU死亡TPC非最优"的**例外**，但原文没有明确写出这一例外——原文只说 "TPC outperformed both alternatives on most subsets and both prediction tasks"（注意"most"而非"all"）。AI-A 的例外陈述**方向正确但来源不透明**——这是 AI-A 从 Table S2（MOESM2）中观察到的推断，还是原文明确说？如果是推断，必须标注 | 在 Provisional Answer 中标注："eICU 死亡例外为 AI-A 根据 Table S2 的推断，原文未明确提及此例外" | **中** |

---

## 4. Evidence Problems

### 4.1 证据位置与可及性问题

| problem_id | problem | severity |
|---|---|---|
| **P-01** | **Table S2 不可及性**：AI-A 将 E2 定位为 "MOESM2 Table S2"，但 AI-A 只访问了原文和 Supp 的部分内容（`paper_025 + MOESM2` 中只包含 Methods 部分，没有 Table S2 的具体数据）。AI-A 声称"多数库/任务 TPC 更优"和"eICU 死亡 AUROC 例外非最优"，**这些具体推断需要实际访问 Table S2 才能验证**。如果没有访问完整 Table S2，应标注"推断存疑，需复查原文" | **高** |
| **P-02** | **N2 的"多数优于"是强度过度**：原文在正文中只说 "most subsets"（`most` 而非 `all`）和 "both prediction tasks"——这个表述本身就暗示了**存在例外**。AI-A 把 "most subsets" 扩展为"多数库/任务 TPC 更优"没有问题，但 **没有提到 eICU 死亡 AUROC 例外出现在 "most" 的边界内**——这正是"most"的语义学含义（非全部） | **中** |
| **P-03** | **N4 的"池化优于/不劣于"措辞有偷换**：AI-A 说"池化优于/不劣于迁移与单源（视任务）"，但 Table 3 明确显示**池化在 MIMIC-IV 专业化上劣于单源 MIMIC**（Mcomposite 0.97 vs 0.89，9.0% 劣势）——这不是"不劣于"，是"劣于"。AI-A 用"视任务"三个字掩盖了一个重要反例 | **高** |
| **P-04** | **E3 的证据位置过于宽泛**：E3 定位为 "Intro/Methods"，但"相对静态评分/线性LOS模型：用时序小时更新"这一表述是 AI-A 从 Supp 的 Experimental designs 部分和原文 Intro 拼合出来的——这两个位置的说法**有不一致**：原文 Intro 只说 "Unlike static admission-time prediction scores"，而 Supp 才提到 "linear regression models based on physiology scores (SOFA, SAPS II, APACHE)... and multiple linear regression models" | **中** |
| **P-05** | **N2b 的证据强度问题**：AI-A 将 N2b（eICU 死亡非最优）标为 evidence E2 并在 conf 中标记为 high ——**但 Table S2 没有被 AI-A 实际访问**。如果 AI-A 没有看到 Table S2 中 eICU 死亡的具体数字，这个"例外"声称为"high confidence"是不合理的 | **高** |

### 4.2 偷换概念清单

| problem_id | concept | issue | severity |
|---|---|---|---|
| **P-06** | "线性" | AI-A 在 N3 中说"相对既往线性LOS假设"——原文所说的"线性"是**基于生理评分（SOFA/SAPS II/APACHE）的线性回归**和**多元线性回归**，但 AI-A 的表述会让读者误以为对比的是"一般线性模型"。更准确的说法应包含 RF/GBM 等静态 ML 也在对比范围内 | **中** |
| **P-07** | "优势" vs "所有设置" | AI-A 在 Provisional Answer 中说"多数设置 TPC 更优"——原文说 "most subsets"（多数子集），AI-A 的表述**方向正确**但需要明确"多数≠所有"且具体数字需要 Table S2 验证 | **中** |
| **P-08** | "方法" vs "训练策略" | AI-A 把"为何选 TPC"和"训练策略比较（池化 vs 迁移）"放在同一个决策树中，且没有明确区分这是**两个不同层面的问题**——架构选择（TPC vs LSTM/Transformer）和训练策略（单源 vs 池化 vs 迁移）是正交的，AI-A 的树结构没有体现这种正交性 | **高** |

---

## 5. Missing Branches

### 5.1 关键缺失分支

| missing_branch_id | missing_content | evidence_location | severity |
|---|---|---|---|
| **M-01** | **TPC 预基准测试分支**：AI-A 遗漏了"作者在采用 TPC 前先做了三架构基准测试"这一关键事实——这是"为何选 TPC"最直接的证据 | 原文 Methods: "Prior to adopting TPC, we benchmarked three state-of-the-art architectures - Transformer, LSTM, and TPC - on our two-stage prediction task across all four BlendedICU databases." | **高** |
| **M-02** | **Rocheteau 先验知识分支**：AI-A 遗漏了 TPC 是**Rocheteau 等人提出的**既定架构（引用 [25]），且 supp 明确说 "The TPC architecture is the current reference for predicting ICU mortality and ICU remaining length of stay"——这意味着作者选择 TPC 部分基于**文献先验**，而非仅靠此文的实验 | Supp Methods: "Rocheteau et al. introduced the Temporal Pointwise Convolution (TPC) architecture, which outperformed LSTM and Transformer architectures for predicting the length of stay and mortality on MIMIC-IV and eICU datasets (25). The TPC architecture is the current reference..." | **中** |
| **M-03** | **池化在 MIMIC-IV 专业化上的反例分支**：AI-A 完全没有提及 Table 3 中"池化在 MIMIC-IV 上劣于单源"这一重要反例——这个反例才是本文"训练策略比较"真正有趣的发现，也是"换方法结论变不变"的关键线索 | Table 3: "data pooling incurred a performance cost for specialization on MIMIC-IV: its Mcomposite (0.97) was 9.0% higher than that of the MIMIC-IV single-source model (0.89)" | **高** |
| **M-04** | **"捷径学习"（shortcut learning）分支**：原文在 Discussion 中详细讨论了"site-specific features 如 药物暴露 作为 shortcuts degrading portability"——这与 Q3 的"换方法结论会变吗"**直接相关**：如果模型学到了站点特异性捷径，那么**换架构（从 TPC 到 LSTM/Transformer）可能无法解决根本的 domain shift 问题**，甚至可能因架构不同而放大或缩小捷径效应 | Discussion: "Site-specific features such as drug exposure acted as 'shortcuts' degrading portability." | **高** |
| **M-05** | **样本量效应分支**：原文 Fig. 2 显示"少于 5,000 患者表现显著退化，超过 15,000 出现平台期"——这与 Q3 的"换方法结论会变吗"间接相关：**如果 TPC 需要至少 15,000 患者才能稳定，那么换用 LSTM/Transformer 是否需要类似/不同的数据量？** AI-A 完全没有提及 | Results: "models trained on fewer than 5,000 patients exhibited significant performance degradation... a performance plateau was observed beyond 15,000 patients" | **中** |
| **M-06** | **TRIPOD + AI 指南 / 两阶段预测设计分支**：AI-A 完全没有提及本文采用**两阶段设计**（先预测死亡率，再预测存活者的 RLoS），这是"方法"的一部分——对 Q3 的"为何选 TPC"来说，**可能需要说明 TPC 是否最适合两阶段任务** | Supp Methods: "a two-step process was chosen. First, the model predicts the probability of patient mortality before discharge from ICU, and then the model predicts a patient's time-to-discharge assuming survival." | **中** |
| **M-07** | **eICU 例外节点的解释分支**：N2b 说 "eICU 死亡 TPC 非最优"，但缺少解释——为什么在 eICU 死亡上 TPC 不最优？是 eICU 数据结构特殊，还是 TPC 在该任务上有已知局限？AI-A 提供 N2b 但不解释因果 | Table S2 (MOESM2) | **中** |

### 5.2 被遗漏的边界条件

| boundary_id | boundary_content | severity |
|---|---|---|
| **B-01** | **本文仅在 4 个库（AmsterdamUMC, MIMIC-IV, eICU, HiRID）上验证**——不含 MIMIC-III（虽然 BlendedICU 含 MIMIC-III，但本文只用这 4 个）。"TPC 优于"的结论不能推广到全部 ICU 数据库 | 中 |
| **B-02** | **池化 / 迁移策略仅在 AmsterdamUMC + MIMIC-IV 上测试**——**eICU 和 HiRID 始终是 unseen**。池化优势只在"从 AmsterdamUMC + MIMIC-IV 泛化到 eICU + HiRID"这个特定方向上验证，不能推广到其他多源组合 | 高 |
| **B-03** | **RLoS 预测被截断为 10 天**（"RLoS was capped to 10 days"）——这意味着 MAPE 反映的是截断后的误差，不是完整 RLoS 分布。换架构后是否在 >10 天 RLoS 上有不同表现未测量 | 中 |
| **B-04** | **诊断（diagnoses）未包含在输入特征中**——"Diagnoses were not included, as they are not consistently available across all four databases"——这意味着模型**缺失了一个关键临床预测因子**。换架构后，缺失诊断的影响可能不同 | 中 |

---

## 6. Required Fixes

### 必须修复（高严重度）

1. **【高】N2 证据过度外推——需修正"多数优于"的表述强度和证据透明度**：
   - 当前表述："Table S2 多数优于 LSTM/TF"
   - 问题：原文只说 "most subsets"（非全部），且 AI-A 未实际访问完整 Table S2
   - 修正：改为 "Table S2 中大多数子集和两个任务上 TPC 更优，但具体范围（多少子集、多少任务）需以 MOESM2 完整表格为准；AI-A 未能访问完整表格，无法精确验证'多数'的边界"
   - 同时：将 N2b 的 confidence 从 "high" 降为 "medium"，并标注"eICU 死亡例外为 AI-A 根据 Table S2 推断，原文未明确提及"

2. **【高】N4 反例缺失——需拆分为多节点并补充反例**：
   - 当前表述："池化优于/不劣于迁移与单源（视任务）"
   - 问题："视任务"掩盖了 MIMIC-IV 专业化上的显著劣势（Mcomposite 0.97 vs 0.89，9.0%劣于单源）
   - 修正：拆为三个子节点：
     - N4a：泛化（eICU+HiRID）——池化最优（△4.2% vs Amsterdam 单源、△8.0% vs MIMIC 单源）
     - N4b：AmsterdamUMC 专业化——池化与迁移几乎无差异（仅 RLoS-MAPE 有非重叠 CI 的优势）
     - N4c：MIMIC-IV 专业化——池化劣于单源（Mcomposite 0.97 vs 0.89，9.0%劣势）

3. **【高】Q3 回答不完整——"换方法结论变吗"未回答**：
   - 当前 Uncertainty 只提到"未对每策略全架构网格"，但没有指出更深的危机
   - 修正：在 Uncertainty 中补充："本文所有结论（池化最佳、内部验证高估等）均在 TPC 单架构下获得——没有任何证据表明池化优势在 LSTM/Transformer 下仍然成立。原文的 shortcut learning 发现（site-specific features 如 药物暴露）进一步表明，换架构可能改变捷径学习的具体形式，但不确定是否改变池化相对优势的整体方向。需额外实验验证。"

4. **【高】N4 的边逻辑断裂**：
   - 当前：N0(Q3 为何TPC) → N4(训练策略比较池化常最优)
   - 问题：中间缺少"为何训练策略比较与架构选择相关"的推理
   - 修正：在 N0 和 N4 之间插入节点："N4-pre：由于本文所有实验均在 TPC 架构上完成，训练策略结论是否依赖架构选择未验证——这是'换方法结论变不变'的关键"

### 建议修改（中严重度）

5. **【中】N3 的"线性"概念精确化**：
   - 当前表述："相对既往线性LOS假设"
   - 修正："相对基于生理评分（SOFA/SAPS II/APACHE）的线性回归和静态 ML（RF/GBM），本文采用小时级时序深度学习（TPC），实现动态风险更新"

6. **【中】N3 补充临床动机**：
   - 补充："原文强调动态 updates 提供了风险轨迹而非单一估计，这是相对静态评分的核心临床价值（可触发监测升级或目标关怀讨论）"

7. **【中】N1 补充 TPC 的文献先验**：
   - 补充："TPC 为 Rocheteau 等人提出的架构，已在 MIMIC-IV/eICU 上证明优于 LSTM/Transformer，是当前 ICU 死亡率与 RLoS 预测的参考架构"

8. **【中】N1 补充预基准测试流程**：
   - 在 N0 → N1 的边上补充中介节点："Before adopting TPC, authors benchmarked Transformer/LSTM/TPC on all four databases——TPC 在大多数子集胜出所以被选为正式架构"

### 建议优化（低严重度）

9. **【低】N2b 的 confidence 从 high 降为 medium**，理由：AI-A 未实际访问完整 Table S2

10. **【低】在 Provisional Answer 中补充截断条件**："RLoS 预测被截断为 10 天（>10 天一律编码为 10），MAPE 反映的是截断后的误差"

---

## 7. Verdict 总结

| 维度 | 评估 | 严重程度 |
|---|---|---|
| **N1（TPC 定位）** | 方向正确，但遗漏来源依据和预基准测试流程 | 中 |
| **N2（Table S2 证据）** | 强度过度——"多数"≠"所有"，且具体范围未验证 | **高** |
| **N2b（eICU 例外）** | 方向正确但来源透明性不足——需标注为 AI-A 推断 | **中** |
| **N3（动态时序优势）** | 方向正确但"线性"概念不精确，临床动机缺失 | 中 |
| **N4（池化优势）** | **遗漏 MIMIC-IV 专业化反例**，且"视任务"含糊 | **高** |
| **边逻辑** | N4 与 Q3 的关联断裂，需插入中间推理 | **高** |
| **关键缺失分支** | 缺少：预基准测试、Rocheteau 先验、MIMIC-IV 反例、shortcut learning 映射、样本量效应 | **高** |
| **Q3 核心问题** | "换方法结论会变吗"——**完全未回答** | **高** |

**最终判断：决策树需要重大修改后方可作为 AI-A 的最终输出。**