<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-09-30T11:25:25 | request_id=msg_c0452bb7-faa4-4b32-8f0c-565aa09a6e27 | usage={"input_tokens": 6761, "output_tokens": 2636, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=5262 -->
# AI-B Tree Attack Report

**paper_id:** paper_022  
**question_id:** Q4  
**review_target:** `@rounds/A_tree_round1_<paper_022>_<Q4>.md`  
**source_file:** `adversarial_lit_reading/chunks/paper_022_2026_wang_ckm_cum_egdr_stroke.md`

---

## 1. Attack Summary

### 总体判断：**需要重大修改**

### 主要问题

AI-A 决策树在 `N1`（"入模以递进临床先验为主"）上存在**证据过度推断**——原文并未明确说明协变量选择是"预先锁定"或"临床先验驱动"，仅呈现了递进调整的 Model 结构。将"未报告自动选择方法"等价为"预先指定"属**因果跳跃**。此外，`N4` 对交互检验的描述不完整（Table3 中的交互机制未充分说明），`N6` 对暴露编码的解读存在概念混杂（聚类识别出的"类"并非研究者预设的"类别暴露"）。最后，**VIF 缺失的定性**被标注为"证据不足"但未区分"报告缺失"与"实际未做"的差异。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| N-A1 | N1 | "入模以递进临床先验为主，非p值/LASSO驱动" | AI-A 将"原文未报告自动选择"推断为"采用了临床先验"，但原文**无任何语言明确说明协变量选择是先验锁定的**；"递进调整"是呈现方式，不等于选择机制 | E6 引用为"全文"，但这是**推断性描述**而非直接引用原文语言 | 将该 claim 改写为："原文呈现递进式调整序列（M1→M2→M3），但未明确说明协变量是先验指定还是数据驱动选择——两种可能性均存在" | **高** |
| N-A2 | N3 | "非线性用RCS" | AI-A 在 Node Table 中标为该 claim 的 evidence_location 为"Methods/Fig3"，但 excerpt 中 RCS 仅出现在 Abstract（"Restricted cubic spline analysis confirmed a linear inverse relationship...P for nonlinearity=0.259"），未见 Fig3 的具体方法描述（节点数、位置未说明） | U2 已识别此不确定性，但 Node Table scoring 中 N3 的 confidence 仍标为 "high"，与 uncertainty 矛盾 | 将 confidence 降至 "medium"；明确 RCS 的 evidence_location 为 Abstract 而非 Methods，且附录说明检验结果（P-nonlinearity=0.259） | **中** |
| N-A3 | N4 | "交互用LRT" | Table3 在 excerpt 中未完整呈现；AI-A 引用的"交互用似然比检验"在可见文本中仅有"subgroup analyses"提及，未见具体检验统计量；AI-A 将"亚组分析"推断为"LRT交互检验" | 可见文本中搜索"likelihood ratio"无直接命中；"subgroup analyses"出现在 p.5 两处，但均为对聚类结果的描述，非交互检验说明 | 标注"需复查原文 Table3 交互检验方法描述"；若无可证实证据，降为 N4 为中置信 | **中** |
| N-A4 | N5 | "未报告VIF/DAG/自动变量选择" | AI-A 将此节点列为"limitation"并标风险 tag "证据不足"，但语义不清：原文未报告 ≠ 研究者未进行；另，将 DAG 与 VIF 并列为"未报告"项，未区分"共线性诊断缺失"与"结构因果模型缺席"的不同含义 | E4 引用"Methods"但只是对原文缺项的归纳 | 拆分为：N5a（未报告共线性诊断如 VIF——确认缺失）；N5b（未见 DAG 描述——但 DAG 非所有流行病学研究的报告要求）；并注明"缺失报告≠未执行" | **中** |
| N-A5 | N6 | "暴露编码：类参照/连续/三分位趋势" | AI-A 未区分两种本质上不同的暴露概念：(1) 基于**K-means聚类**识别出的 4 个 eGDR 变化模式（类属变量，以 Class2 为参照）；(2) 作为**连续变量**的累积 eGDR 及三分位趋势检验。前者来自无监督学习，非"研究者预设的类别"；N6 中"暴露三种编码"混淆了两种不同来源的变量 | E5 引用中提及"参照类=Class2；连续每1单位；三分位趋势"，但未区分"聚类派生类别"与"研究者定义的暴露编码" | 将 N6 拆分为：N6a（聚类派生类别，参照 Class2）；N6b（连续累积 eGDR）；N6c（三分位趋势检验）；并说明 N6a 中的"类"来自 K-means，非预设分组 | **高** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E-A1 | N1 → N2 ("because") | AI-A 将"N1（临床先验递进）"作为 N2（三套模型）的先验理由，但更合理的逻辑是反向的：N2 的模型结构是 N1 推论的**启示性证据**，而非"因为先验所以有三套模型"。原文并未声称是先验导致三套模型设计 | 将 N1 与 N2 之间的关系改为 "N1 _________________________________ inferred_from N2"，即从模型结构推断潜在逻辑，而非因果推论 | **高** |
| E-A2 | N1 → N5 ("limitation") | N5 标注为 N1 的 limitation，但"N1 临床先验驱动"与"N5 未报告 VIF/DAG"联系不自然——若协变量集是预指定的，VIF 缺失是补充诊断而非该 claim 的必要局限 | 将 N5 独立为总体方法学局限，而非 N1 的附属 limitation；或者在 N1 中增加"若为临床先验驱动，则 VIF 缺失的严重性取决于预指定集是否包含共线变量" | **中** |
| E-A3 | N0 → N6 ("leads_to") | N0（协变量筛选与建模）连接到 N6（暴露编码）的路径不够直接——暴露编码属于"暴露的定义与操作化"，与"协变量筛选"强调重点不同；更合理的连接是 N0 → N1/N2（协变量建模）和 N0 → N3/N4（模型形式），而 N6 作为暴露相关方法单独分支 | 重构：N0 → N6 改为"暴露基础信息"分支，或在 N0 下拆分"协变量建模"与"暴露编码"两个子主题 | **低** |

---

## 4. Evidence Problems

| problem_id | evidence_ref | problem type | description | suggested fix |
|---|---|---|---|---|
| P1 | E6 | 过度推断 | 将"模型呈现为递进调整"解读为"预先指定"——原文无 "pre-specified"、"a priori" 或类似语言 | 改为"原文未说明协变量集是否预先锁定；呈现方式暗示固定调整集，但无直接证据" |
| P2 | E2 | 位置不准确 | RCS 的证据被标注为 "Methods"，但可见文本中 RCS 仅在 Abstract 呈现（"Restricted cubic spline analysis confirmed..."），且 p.5 截图处被截断 | 若 Methods 中有 RCS 具体描述，应标注精确位置；若仅在 Abstract，应如实标注"Abstract 报告，Methods 待确认" |
| P3 | E3 | 引用不完整 | "Table3 亚组交互"在可见文本中无法找到具体 Table3 说明；仅见"subgroup analyses"提及 | 标注"需复核原文 Table3 及其脚注"，给出精确行/段引用 |
| P4 | E5 | 概念混杂 | 将"聚类识别类别"与"预设暴露分组"混为一谈：Class 1–4 来自 K-means 无监督聚类，非研究假设预设的暴露水平 | 在证据描述中区分"无监督聚类派生分组"与"研究假设中的暴露变量" |

---

## 5. Missing Branches

| branch_id | missing_branch | description | severity |
|---|---|---|---|
| B1 | **聚类方法对建模的嵌套影响** | AI-A N6 分析暴露编码时未体现在 K-means 聚类是协变量调整前的主分析步骤——聚类结果定义暴露，再以此为因/自变量，形成"聚类派生暴露 + logistic回归"的两阶段建模；这一结构对 N1（"临床先验"）的判定有直接影响。 | **高** |
| B2 | **eGDR 公式成分变量与协变量的重叠** | eGDR 本身由 WC、HTN、HbA1c 构成，而这些（或其代理）可能也出现在 Model3 协变量集中（如 BMI、高血压、糖尿病）。这是结构性共线问题，AI-A 的 U3 提及但未将其纳入决策树分支 | 在 N5 中补充结构共线的潜在来源分支 | **中** |
| B3 | **RCS 非线性检验结果未纳入树结构** | 原文 Abstract 明确报告 P-for-nonlinearity = 0.259（支持线性），AI-A 的 N3 只提"用 RCS 检验非线性"，未加入"检验结论为支持线性关系"这一结果节点 | 在 N3 下增加结果分支："非线性检验 P=0.259，支持线性建模" | **中** |
| B4 | **Model 3 高血压变量的不确定性** | AI-A U1 中提及 Model3 是否含高血压的不确定，但未将其作为决策树中的协变量选择分支处理；由于 HTN 同时是 eGDR 公式组成成分，该不确定性对因果解释有实质影响 | 在 N2 或 N5 下增加 U1 分支 | **低** |

---

## 6. Required Fixes

1. **将 N1 claim 从"临床先验驱动"改为"递进调整呈现，选择机制未明确说明"**——避免将缺失报告等价为先验指定，区分"呈现方式"与"选择机制"两个不同层次。

2. **N6 拆分为 N6a（聚类派生类别）、N6b（连续累积 eGDR）、N6c（三分位趋势检验）**——两种暴露来源在概念上不可混并；N6a 中"类别"来自 K-means 无监督学习，非假设预设。

3. **N3 和 N4 的置信度从 "high" 降为 "medium"**——RCS 的 evidence_location 不精确（Abstract vs Methods 未确认），Table3 交互检验信息不完整，需在最终报告中如实标注信息缺口。

4. **E-A1 中 N1 → N2 的逻辑方向从 "because" 改为 "inferred_from"**，避免因果倒置；同时 N5 应从 N1 的附属 limitation 提升为独立方法学局限节点。

5. **在决策树中增加 B1（聚类→暴露→建模的两阶段结构）分支**——这是理解全文方法学的关键链条，当前树结构完全缺失该逻辑。

6. **U1（Model3 是否含高血压）作为协变量选择分支纳入树结构**，而不是仅作为脚注不确定性列出；由于 HTN 是 eGDR 的成分变量，该不确定性的影响超越协变量名单本身，涉及暴露的结构效度。

---

*报告完成。如需详细引用位置核对或对 Tree 修改稿的意见，可要求二次评审。*