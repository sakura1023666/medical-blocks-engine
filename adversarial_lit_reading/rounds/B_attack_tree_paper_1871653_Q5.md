<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-11-18T14:46:02 | request_id=msg_2b7b5bb3-8fb3-425d-8073-69b7b6ce12ed | usage={"input_tokens": 13720, "output_tokens": 3593, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 768, "prompt_tokens_details": {"cached_tokens": 768}} | char_len=7187 -->
# AI-B Tree Attack

paper_id: paper_1871653
question_id: Q5
review_target: @rounds/A_tree_round1_paper_1871653_Q5.md
source_file: adversarial_lit_reading/chunks/paper_1871653_fcimb_temperature_jlcm.md

## 1. Attack Summary

总体判断：**部分可信（需重大修改）**

主要问题：
1. **N1 节点存在关键偷换概念**。原文 Weibull 基线风险是用于 `survival submodel`（JLCMM 的生存部分），而 AI-A 将其表述为「L1 JLCMM：Weibull+类模型假设」——未区分纵向子模型的 spline 设定与生存子模型的 Weibull 假设，这两者是 JLCMM 中两个不同组件的最优建模选择，而非某个单一内聚的「Weibull 假设」。
2. **N8 节点的迁移问题严重**。AI-A 声称「寻引擎铁律 m=5 + Rubin」，但操作手册的 m=5 是 **AI 推理引擎的通用铁律**，而论文原文的 MICE 是统计学上的多重插补，两者性质完全不同——原文是用 R 做统计插补（作者自述 RStudio 环境），不是 AI 推理引擎。AI-A 将论文中的 MICE 与「AI 引擎机制」混为一谈，构成跨越性质的过度迁移。
3. **E2 证据位置错误**。KM 交叉曲线出现在 Results 3.2（Figure 2a，Page 7），不是 Methods 2.5.1——方法部分只描述了「将使用 piecewise Cox」，实际「发现违反 PH」的证据在结果部分。
4. **N8 节点内容混杂**。AI-A 将「日级实验室 vs 6h 体温」迁移与「m=5 铁律」两个完全无关的内容塞进同一个节点，且两者性质不同（前者为数据分辨率问题，后者为 AI 引擎参数问题），应拆分。

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| B-N1-01 | N1 | 「Weibull 基线风险；潜类别局部独立性/类内混合模型假设（标准 JLCMM）」 | AI-A 将 Weibull 假设混入「JLCMM 类模型假设」的整体表述中，未区分 **纵向子模型**（spline）与 **生存子模型**（Weibull）是两个独立组件。且「潜类别局部独立性」在原文中未被明确表述为假设，只是 JLCMM 的标准模型设定，AI-A 是在套用标准方法学模板。 | 原文 Page 3-4：`natural cubic splines of time`（纵向）与 `a Weibull baseline hazard function was assumed`（生存）分属两个子模型描述。 | 拆分为两个独立节点：N1a「纵向子模型：自然三次样条」；N1b「生存子模型：Weibull 基线风险」。 | 中 |
| B-N2-01 | N2 | 「PH 违反→分段 Cox」 | 表述「发现违反」精确，但引用位置「Methods 2.5.1」不正确。方法部分只写了「piecewise Cox 将用于处理时间依赖系数」，实际 KM 交叉曲线证据在 **Results 3.2**。另注意：AI-A 未标注「optimal cut point = day 5 by highest log-likelihood」这一决策依赖的参数假设。 | 原文 Page 7 Results 3.2：`Crossing survival curves indicated potential violation of the proportional hazards`；Page 4 Methods 2.5.1 只有设计描述。 | ① 移动证据位置至 Results 3.2/Figure 2a；② 在 claim 中补充「cut point=day5 由 log-likelihood 选优」这一隐含假设。 | 中 |
| B-N4-01 | N4 | 「MAP 硬分配忽略分配不确定性」 | 对方法学描述的「MAP 硬分配」是正确的——原文 `patients were assigned to the class with the highest posterior probability`。但 AI-A 称「Algebraic/AvePP≥5%」为「选 K 规则」的一部分，实际上 AvePP>0.70（不是 ≥5%）在 Supplementary Table 4，且 ≥5% 是类规模下限（class size），不是 AvePP 的阈值。 | 原文 Page 4：`Each class was required to contain at least 5% of the study population`；Page 5：AvePP `>0.70`；补充材料不在此 chunk 中。 | 指标语义需澄清：≥5% 指类规模下限，非 AvePP 阈值；AvePP>0.70 在补充材料中，不在此 chunk 内，需标注。 | 中 |
| B-N8-01 | N8 | 「寻引擎铁律 m=5 + Rubin」 | **严重概念混淆**。操作手册的「AI 引擎 m=5 + Rubin」是 AI 推理引擎的鲁棒性配置规则，而论文中 MICE 是 **统计插补方法**（R 环境运行，m 值未在论文中明确给出）。AI-A 将两个不同领域的「m」混为一谈，并声称「遵循引擎铁律」——这在论文中没有对应依据，且性质不同。 | 原文 Page 11 仅提及 `Missing values in covariates were handled using multiple imputation by chained equations (MICE)`。论文的 m 值未披露。 | 删除「引擎 m=5 铁律」归属，改为：原文对 MICE 的 m/maxit/seed 等参数**未披露**，构成方法学报告缺口。若需迁移至用户研究，应注明「论文未报告 m 值，需向作者确认或自查」。 | 高 |
| B-N7-01 | N7 | 「院内死亡口径规避出院后失访」 | 归因精确，但「出院存活作竞争语境」措辞模糊——原文主分析是 **cause-specific hazard（出院存活=删失）**，敏感分析用 Fine-Gray（出院=竞争风险）——AI-A 未区分主分析中「删失」与敏感分析中「竞争事件」的差别。 | 原文 Page 4（2.5.5）/Page 8：`discharge alive before day 28 treated as censoring`（主分析）；`Fine-Gray... treating discharge as a competing risk`（敏感分析）。 | 在 claim 中补充「主分析删失 vs 敏感分析竞争事件」的区分。 | 中 |
| B-N5-01 | N5 | 「MICE；纵向测量机制未详」 | claim 本身正确，但 N5 将「协变量 MICE」与「纵向体温测量缺失」混在同一个节点——前者是协变量的交叉截面缺失，后者是重复测量的时间点不规则性，两者机制不同。原文确实对纵向测量机制`未深入研究`，但 AI-A 的节点表述可能误导读者认为 MICE 处理的是纵向体温缺失。 | 原文 Page 3 Table 1 显示多个基线协变量有缺失；Page 8 讨论提到 `temperature measurements may be subject to heterogeneity in measurement sites... recording frequency`。 | 辨明两类缺失：基线协变量缺失（MICE）vs 纵向测量频率不规则（采样机制，原文未建模）；两类机制不同，不可混合表述。 | 中 |
| B-N6-01 | N6 | 「非 NHANES 加权；多中心回顾队列」 | 「无 survey 加权」对 MIMIC-IV 是准确的。但「外验套用发现集参数」表述不够精确——原文外验是**两部分**：① 轨迹分类用发现集参数（后验概率）；② 时间-温度关联用「相同框架重新估计」而非直接套参数。 | 原文 Page 4（2.5.4）：`Posterior class-membership probabilities were estimated using model parameters derived from the MIMIC-IV cohort`（套用）；`Time-varying temperature-mortality associations were also re-estimated using the same modeling framework`（重新估计）。 | 将「套用参数」限定为「轨迹分类仅套用参数」；时间-温度关联部分是重估不是套用。 | 中 |

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| B-EDGE-01 | N1→N2 | AI-A 将「JLCMM 假设」作为「PH 检查」的前驱节点，但逻辑上两者是**并列分析模块**而非因果链——JLCMM 估计轨迹类，KM/piecewise Cox 比较轨迹类间生存差异，两者服务于互补的分析目的，`N1 不「导致」N2`。 | 将 N1→N2 改为并行关系（或标注为「互补分析模块」），而非顺序依赖。 | 中 |
| B-EDGE-02 | N4→N5 | MAP 硬分配作为 `output` 与 MICE 缺失处理作为 `input` 之间存在逻辑顺序混叠——N4 是模型输出的后处理，N5 是协变量的预处理，两者不存在先后推理关系。 | 拆为两条独立分支或用「并行」标注，而非箭头传递。 | 中 |
| B-EDGE-03 | N7→N8 | 从「院内死亡口径」过渡到「日级实验室 vs 6h 体温」的迁移问题，缺中间推理步骤——为什么结局口径会导致分辨率迁移问题？两者之间需要「结局定义→数据采集频率→测量尺度」的递进逻辑。 | 在 N7 与 N8 之间补充分辨率/测量尺度的中间推理链。 | 低 |
| B-EDGE-04 | N5→N6→N7 | 依赖链「缺失→加权→结局口径」缺少原文依据——原文没有对这些机制之间的关系进行因果论证，AI-A 的箭头暗示了未经验证的因果路径。 | 将 N5/N6/N7 标注为「并列设计特征」而非因果链。 | 低 |

## 4. Evidence Problems

| 问题类型 | 具体问题 | target | 建议 |
|---|---|---|---|
| **证据位置错误** | E2（KM 交叉）标注为「Methods 2.5.1」，但实际出现在 Results 3.2/Figure 2a（Page 7-8）。 | E2 | 移至 Results 3.2 |
| **证据位置模糊** | E5（MICE）无具体段号，且被混入纵向缺失——需指明 MICE 的位置（Cohen 缺失处理在 Page 4 底部 Methods 2.5.2），且区分两类缺失。 | E5 | 明确页码/段落；拆分两类缺失 |
| **证据位置错误** | E1（Weibull）引用「Methods 2.5.1」正确，但未区分纵向 spline vs 生存 Weibull——两者在同一小节但属于不同子模型 | E1 | 在标语中注明「生存子模型」 |
| **过度引用仿真结果** | N2 将结果部分的「KM 交叉 → PH 违反」作为方法决策的充分证据，但未标注「KM 交叉 只是 PH 违反的启发式证据，非正式检验」——AI-A 未提及原文未进行 Schoenfeld 残差检验。 | N2 | 补充「KM 交叉作为启发式；未报告正式 PH 检验」 |
| **引用补充材料** | N4 称 AvePP>5%，但 AvePP 阈值为 0.70 且「在补充材料中」——本 chunk 不含补充材料，AI-A 不应在此 chunk 中标注为 `Methods` | N4 | 标注为「补充材料，不在当前 chunk」 |

## 5. Missing Branches

| 缺失分支 | 原因 | 建议 | severity |
|---|---|---|---|
| **landmark 时间点选择（1-14天）** 的假设 | 原文每天定义 landmark，但「landmark 时间点与分析窗口的嵌套」未作为假设分支出现在树中 | 增加分支：landmark 选择如何影响 AUC 估计的有效性 | 中 |
| **Schoenfeld 残差未报告** | 原文只通过 KM 交叉判断 PH 违反，未做正式检验 | 增加分支：PH 检验的方法学缺口 | 中 |
| **内时间-温度相互作用的样条维度/自由度未报告** | 原文提到 `penalized splines` 但未给出惩罚项具体设置 | 增加分支：样条参数选择透明性缺口 | 中 |
| **温度聚合为区间最大值的信息损失** | 原文用区间最大值（而非均值/中位）表示 6h 体温——「峰值选择」是一种信息丢失性聚合 | 增加分支：max 聚合 vs mean/median 敏感性 | 中 |
| **Fine-Gray 结果差异的分歧** | 原文示 Classes 4/5 在 Fine-Gray 与 cause-specific 之间差异明显（Page 8）——AI-A 未在分支中体现 | 增加分支：竞争风险模型的稳健性分歧需解读 | 中 |
| **排除 ICU 停留 <5 点体温的样本**（survivorship bias） | 原文细致讨论了排除患者「更高死亡率/更短 ICU 停留」的 survivorship bias（Page 11），AI-A 的树中未提及 | 增加分支：排除标准导致的**可能幸存者偏倚** | 高 |
| **外验的轨迹分布一致性** | 原文在补充材料中报告了外验队列的模型拟合；但 AI-A 未提及跨队列轨迹类分布可能存在差异 | 增加分支：外验类分布差异 | 低 |

## 6. Required Fixes

1. **【高】【N8】删除「引擎 m=5 铁律」迁移归属**。原文 MICE 是统计方法，AI 引擎的 m=5 是推理配置——两者不可混同。改为「原文未报告 MICE 的 m、maxit、seed」，标注为方法学报告缺口。

2. **【中】【N1】拆分 JLCMM 假设**为「纵向子模型：自然三次样条 + 类特定随机效应」与「生存子模型：Weibull 基线风险」。

3. **【中】【N2】修改证据位置**：将「KM 交叉 → PH 违反」的证据移至 Results 3.2 / Figure 2a，并补充「Schoenfeld 残差未报告」的缺口。

4. **【中】【N4】澄清指标语义**：≥5% 是类规模下限（class size 约束），不是 AvePP 阈值；AvePP>0.70 在补充材料（不在本 chunk 内）。

5. **【中】【N5】拆分两类缺失**：协变量 MICE（基线交叉截面）vs 纵向体温测量频率（信息采样机制）——原文对前者使用了 MICE，对后者未建模。

6. **【中】【N6】区分「套参数」vs「重估」**：轨迹分类用发现集参数计算后验概率；时间-温度关联是「重新估计」而非直接套参数。

7. **【高】【新增分支】增加「排除患者 → 幸存者偏倚」分支**。原文明确讨论了排除患者的偏倚（更高死亡率、更短 ICU 停留），但 AI-A 树中完全缺失这一关键限制。

8. **【中】【N3】补充 PAMM 样条参数缺口**：原文未报告惩罚样条的惩罚项设置、区间切分长度等参数细节——AI-A 已标 `risk_tag=证据不足`，但建议在「Provisional Answer」中明确这一问题的影响程度。

9. **【中】【N7】区分「删失」vs「竞争风险」**：主分析是 cause-specific Cox（出院存活 = 删失），敏感分析才用 Fine-Gray（出院 = 竞争）——口径不能混淆。

10. **【低】【N8】拆分 N8**：将「日级实验室 vs 6h 体温」分辨率迁移问题与「m=5 Rubin」分开——前者是数据特性迁移，后者是 AI 引擎配置，不应合并在同一节点。