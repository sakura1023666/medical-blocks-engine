<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-11-03T11:35:42 | request_id=msg_a970d3d1-4260-46c5-b152-2ce421bf9bcb | usage={"input_tokens": 20111, "output_tokens": 5643, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=11254 -->
# AI-B Tree Attack

paper_id: paper_40295872
question_id: Q6
review_target: @rounds/A_tree_round1_paper_40295872_Q6.md
source_file: adversarial_lit_reading/chunks/paper_40295872_jin2025_shr_sofa_af_mortality_cardiovasc_diabetol.md

## 1. Attack Summary

总体判断：**需要重大修改**

主要问题：
1. **N3（亚组一致性）被用作"稳健性/外推"证据过度**：原文仅报告亚组内 HR 方向一致、交互项不显著，但未报告亚组分析的预先注册性质、多重比较校正或交互检验的统计功效。AI-A 将其标为 medium confidence 且作为"关联稳健"支撑，忽略了交互检验不显著 ≠ 效应一致（可能只是功效不足）。
2. **N4（RCS）与 E4 的证据标签偷换**：AI-A 将 RCS 列为"evidence"类型，但 RCS 是分析方法而非证据。更重要的是，原文明确报告**低 SOFA 组的 1 年死亡率非线性关联不显著（P=0.168）**，而 AI-A 的 N4 表格未报告这一关键阴性结果——这是选择性报告。
3. **N5（bootstrap 次数）的证据冲突未充分标注**：原文 Methods 写 200 resamples，Results 写 1,000 bootstrap resamples。AI-A 虽标注了"方法误读"风险，但未进一步讨论这是否影响校准估计的可信度，也未建议查证附录或联系作者。
4. **N12 的"双轨"框架将"关联"与"预测"作为并行有效性主张，但原文未明确区分**：原文的讨论与结论将两者交织，且用预测 nomogram 的 C-index 反向支持 SHR-SOFA 的关联强度——这是概念混用。AI-A 的框架虽合理，但未指出原文本身有此混用。
5. **N10 的证据标签不精确**：AI-A 将"未报告 E-value/阴性对照/敏感性"标为 `uncertainty` 类型并给 high confidence，但"全文未报告"是一个**需要穷尽式检索的负面断言**，而非基于某一处证据。当前 chunk 未包含全部补充材料（Table S1–S3 仅被引用未展开），因此需标注"需复查完整补充材料"。
6. **N13/N14（迁移节点）基于用户口头确认而非原文证据**，且 N14 中"禁 HbA1c 轴"的建议与原文 SHR 定义（FBG/[28.7×HbA1c−46.7]）直接冲突——若禁 HbA1c，则无法计算 SHR。这是方法层面的事实错误，必须修正。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| B-N01 | N3 | "亚组验证风险排序在 MI、心衰、肾衰等队列一致；交互项多不显著" + medium confidence | ① 原文仅一句叙述"Subgroup analysis validated the consistent ranking...with non-significant interaction terms"，未给出交互 P 的具体数值或完整矩阵。[chunk 第 6 页] ② "交互不显著"不能等价于"效应一致"——低功效亚组的不显著交互可能掩盖异质性。③ AI-A 未标注亚组是否预先指定、是否做过多重比较校正。 | 原文 Table S1–S3 未包含在当前 chunk 中，无法核验交互 P 完整矩阵。 | 明确标注"亚组分析为探索性，交互项统计功效未报告"；将 confidence 降为 low–medium；在 Uncertainty 中补充"表 S1–S3 未在当前 chunk 内，需查证" | **高** |
| B-N02 | N4 | "RCS 提供非线性与阈值的图形+检验"（evidence 类型，high confidence） | ① RCS 是**方法**而非证据，E4 标签应为 `method` 而非 `evidence`。② AI-A 漏报关键阴性结果：低 SOFA 组 1 年死亡率 P-nonlinear=0.168（不显著）。③ "阈值/理想 SHR 点（1.0/1.2）"混同两种统计概念："threshold effect at SHR=1.0"是分段回归切点，而"ideal SHR of 1.2"是 J 形曲线最低点——两者含义不同。 | 原文[第 7 页]明确写"this nonlinear association was not statistically significant for 1-year mortality (P nonlinear=0.168)"；"threshold effects at SHR=1.0"与"ideal SHR of 1.2"确实并存。 | ① 改为 `method` 类型节点。② 补充低 SOFA 组 1 年 P-nonlinear=0.168 的阴性结果。③ 区分"分段回归切点"与"J 形曲线最低点"，可用两行说明。 | **高** |
| B-N03 | N5 | "预测工具内部验证=bootstrap 校准；200/1000 次数表述不一" + 标注"方法误读" | AI-A 已注意到 Methods(200) 与 Results(1000) 的冲突并标注了风险，但未讨论该不一致对校准可信度的影响。此外，原文 Results 中"optimism-corrected calibration curve"与 Methods 中"bootstrapping-corrected calibration curves (Brier scores with bootstrap validation and 200 resamples)"是否指同一流程不明确——Brier 分与校准曲线的 bootstrap 次数可能不同。 | 原文[第 4 页 Methods]写"200 resamples"；[第 8 页 Results]写"1,000 bootstrap resamples"。确实存在冲突。 | 明确列出该冲突；在 Uncertainty 中追加"Methods(200) vs Results(1000) 的 bootstrap 次数冲突是否影响校准/Brier 估计需查证附录或联系作者" | **高** |
| B-N04 | N7 | "SHAP 解释≠外部验证；属可解释性证据" + medium confidence | SHAP 是模型解释工具，作为"可解释性证据"的定位基本正确。但 AI-A 未指出：SHAP 的 feature importance 是**模型内部的**，不能独立支撑"预测有效性"——它只说明模型用了哪些特征，不说明预测是否准确。AI-A 的树将其挂在 N12 之下（"双轨有效性"），容易让人误以为 SHAP 贡献了有效性证据。 | 原文[第 8 页]SHAP 分析仅描述特征贡献，未声称 SHAP 验证预测性能。AI-A 的树结构[图]确实将 N7 直接挂在 N12 下。 | 建议在 N7 旁加注"可解释性 ≠ 有效性证据，仅增强临床可信性"；或在树中移动 N7 使其不从 N12 直接引出 | **中** |
| B-N05 | N8 | "中介间接效应有 bootstrap CI；比例随时间下降" + high confidence | 数值准确（22.7%→21.7%→17.2%）。但 AI-A 未指出中介分析的因果假设（无未测量混杂、时序正确）在观察性设计中无法检验。原文[第 9 页]的 a×b 点估计与 CI 均远离 0，但未讨论 E-value 或负对照。 | 原文[第 9 页]确实报告了 22.7%/21.7%/17.2% 与 CI；原文的 Limitations 部分未作中介假设检验。 | 在 N8 旁标注"中介分析基于强因果假设，观察性数据无法排除未测量混杂；原文未作敏感性检验" | **中** |
| B-N06 | N10 | "无 E-value、阴性对照结局、完整病例 vs 插补头对头敏感性表" + 标注"证据不足" + high confidence | ① "全文未报告"是穷尽式负面断言，但当前 chunk 未包含 supplementary materials（Table S1–S3、Figure S1–S3 仅引用未展开）。② 原文确实未在 Discussion/Limitations 中提及 E-value；但 AI-A 未区分"原文提及但没有做"与"原文根本没提（可能做了但没写）"两种可能。 | 当前 chunk 仅含主文与 References，不含补充材料内容。 | 将 N10 标注为"基于主文 10 页文本的检查；补充材料完整内容未在当前 chunk 中，E-value/阴性对照的最终确认需查 Supplementary Material 1" | **高** |
| B-N07 | N12 | "有效性分「关联」与「预测」两轨"（claim 类型）+ high confidence | 框架本身合理（原文确实同时做了 Cox 关联分析与 nomogram 预测），但 AI-A 未指出**原文自身将两轨混用**——例如在 Discussion 中用 nomogram 的预测性能论证 SHR-SOFA 的临床重要性，这属于概念跳跃。 | 原文[第 9 页 讨论]"The developed nomogram...offers a novel tool"与"SHAP analysis confirms SHR and SOFA as key predictors"确实在结论中将两者合并；原文未清晰区分"关联稳健"与"预测工具性能"是不同有效性主张。 | 在 N12 下加注："原文未明确区分关联与预测的有效性标准，二者对证据的要求不同（关联需控制混杂/因果；预测需外部校准/验证）" | **中** |
| B-N08 | N6 | "区分度 C-index + 校准 MAE" + high confidence | 数值准确（0.807/0.792/0.722；MAE 0.020/0.009/0.021）。但 AI-A 将 C-index 归为 "evidence" 类型，而 C-index 实际是模型验证**指标**，是从模型评估产出的统计量，不应与"原文文本证据"并列。此外，原文 C-index 是否有进行 optimism-correction 是存疑的——原文只说"1,000 bootstrap resamples"用于校准曲线，C-index 的 CI 是否来自同一 bootstrap 未说明。 | 原文[第 8 页]报告 C-index 与 CI；Methods[第 4 页]只写了校准用 bootstrap，C-index 的 CI 计算方法未说明。 | 将 N6 改为 `method` 或 `statistic` 类型；在 Uncertainty U2 已有表述，但建议明确"原文未说明 C-index CI 是否来自 optimism-corrected bootstrap" | **中** |
| B-N09 | N13 | "用户计划 eICU 外验可补齐原文最大验证缺口" + high confidence | ① 此节点非论文内容，而是用户研究计划的推断——应明确标注来源为"用户确认"而非论文证据。② AI-A 将其放在树中 `transfer_to` 边下，但缺少"迁移可行性分析"：eICU 与 MIMIC-IV 的人口学/临床实践/编码体系差异是否会影响 SHR 定义与 SOFA 评分可比性？③ 原文 SHR 基于 FBG+HbA1c，eICU 是否有匹配的 HbA1c 测量？ | 原文[第 4 页]定义 SHR 公式；eICU 的变量可得性在原文之外的领域问题 | 将 N13 标注为"外部建议，非原文结论"；增加"需核验 eICU 中 SHR 所需变量（FBG、HbA1c）的可得性与测量一致性" | **高** |
| B-N10 | N14 | "迁移应补暴露改写/complete-case/禁 HbA1c 轴等敏感性" + high confidence | **方法矛盾**：原文 SHR 定义为 FBG / [28.7×HbA1c − 46.7]，若"禁 HbA1c 轴"则无法计算 SHR——这不是敏感性分析而是更换暴露定义。AI-A 未解释在禁用 HbA1c 后如何构造替代指标（如单纯 FBG、葡萄糖-胰岛素抵抗指数等）。 | 原文[第 4 页 Methods]给出 SHR 公式 | 将"禁 HbA1c 轴"改为"可替代暴露定义（如单纯 FBG 或 HOMA-IR 代理）的敏感性分析，但需重新定义研究问题"；或解释如何在保留 SHR 定义的前提下做剔除 HbA1c 极端值的敏感性分析 | **高** |
| B-N11 | N1 | "KM 显示四层生存可分" + evidence 类型 + high confidence | 基本准确。但未指出 KM 的局限：log-rank P<0.001 只能说明四组生存分布不全相同，不能说明四组**逐对**有差异或排序完全正确，且 KM 未调整混杂。原文说"intermediate groups maintaining the hierarchy of low SHR and high SOFA > high SHR and low SOFA at all intervals (P<0.001)"，这个 P 值是配对比较还是全局检验未说明。 | 原文[第 6 页]仅给 log-rank P<0.001，未说明配对比较详情。 | 在 N1 下加注"KM/log-rank 未调整混杂，四组间差异可能受年龄、合并症等影响"；询问配对比较是否做过多重校正 | **中** |
| B-N12 | N2 | "多时点多因素 Cox" + evidence 类型 + high confidence | Table 2 报告了多时点 HR/CI，数值准确。但 AI-A 将 N2 标为 `evidence` 类型，而 Cox 模型是统计分析方法。此外，原文 Model II 的调整变量列表与 AI-A 的 E2 摘要未对应——Model II 含 30+ 变量，但 AI-A 只写了 "Q4 最高风险"，未报告调整后 HR 的实际范围。 | 原文[第 6-7 页]Table 2；Model II 调整变量列表在表格下方 | 改 N2 类型为 `method`；补充 Model II 的调整变量集简表；将"Q4 最高风险"对应到具体 HR 值（如调整后 4.06/3.23/2.45） | **低** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| B-E01 | N0 → N12 | "leads_to"关系可从问题直接推出 AI-A 的框架，但 N12 的"双轨"是 AI-A 的**人为分类**，不是原文明确的结构。原文并未以"关联效度"与"预测效度"二分组织其分析。 | 将 N12 改为 "AI-A 解释框架"，并附注"原文未以双轨结构呈现，此为客户解读" | **中** |
| B-E02 | N3 ↔ N12 | "亚组一致性 → 支撑关联稳健"的边缺少中介限定：原文未明确亚组是预先指定还是数据驱动的探索性分析。若为探索性，则"亚组一致性"对稳健性的支持力显著下降。 | 在边上加注"探索性亚组，支持力有限"；或将 N3 的 confidence 降为 low | **高** |
| B-E03 | N4 ↔ N12 | RCS 提供的"非线性形态"被 N12 用作"关联轨"证据，但 RCS 也有阴性结果（低 SOFA 组 1 年不显著）。若该阴性结果被报告，则 N4 → N12 的边应标注"部分支持"而非完整支持。 | 在 E3（若边有编号）或 N4 上增加"低 SOFA 组 1 年 P-nonlinear=0.168"的分支条件 | **高** |
| B-E04 | N5 → N6 | 边关系是"bootstrap 校准 → C-index/MAE"，但 AI-A 的表格将两者分为 method 与 evidence 节点，暗示 N6 是 N5 的产物。实际上 C-index 与校准是**并列的验证维度**，并非 C-index 由 bootstrap 校准产生。 | 将 N5 与 N6 的边改为 `parallel_with`（或并列关系）而非 `supported_by` | **中** |
| B-E05 | N9 → N13 | "tranfer_to"关系合理（用户计划补外部验证），但缺少**迁移条件检验**——从"原文无外验"到"用户应补外验"并非自动成立，需先确认 eICU 数据能否复现 SHR 与 SOFA 定义 | 在 N13 上加注"迁移前置条件：SHR 与 SOFA 变量在 eICU 中的可比性需先行核验" | **高** |
| B-E06 | N10 → N14 | 从"原文未做敏感性"跳转到"用户应做敏感性"的逻辑不完整——缺少中间步骤：为什么用户的暴露定义改写对**用户自己的研究**重要？AI-A 未论证用户研究的暴露定义与原文的差异 | 在 N14 前增加一个中间节点："用户研究暴露定义 vs 原文 SHR 定义的差异审查" | **中** |
| B-E07 | N9 → N11 | AI-A 将"作者自认需前瞻验证"作为 limitation 的标准引用，但与 N9（无外部验证）之间的逻辑链条缺少一环：作者说"需前瞻亚组验证"与"无外部验证"是两个独立的局限声明，AI-A 将其串联为"因为无外验所以作者呼吁前瞻"——原文并未明确将两者因果关联 | 可改为并列关系，或删除因果暗示 | **低** |

---

## 4. Evidence Problems

| problem_id | target_node | issue type | description | suggested fix | severity |
|---|---|---|---|---|---|
| B-P01 | N4 | 选择性报告 | AI-A 未报告低 SOFA 组 1 年死亡率非线性不显著（P=0.168）的阴性结果，导致 N4 证据解释不完整 | 在 N4 或 E4 中补充该阴性结果 | **高** |
| B-P02 | N5/N6 | 概念混用 | C-index 与 MAE 是"模型性能指标"，不应标为 `evidence` 类型；bootstrap 是"验证方法"，AI-A 将方法与产出并列 | 区分 `method` vs `statistic` 类型 | **中** |
| B-P03 | N3 | 过度引用 | "交互项多不显著"被 AI-A 引作稳健性证据，但交互检验低功效时不显著 ≠ 效应一致 | 在 N3 标注"交互检验功效未报告，不显著不等于一致" | **高** |
| B-P04 | N10 | 证据来源空泛 | E10 标注为"全文"，但具体检查范围（哪些部分查看了？哪些补充材料未查看？）未记录 | 将 E10 的 location 改为"主文 10 页文本；Supplementary Material 未纳入检查" | **高** |
| B-P05 | N8 | 因果假设未标 | 中介分析的比例未标注其因果假设强度（需无未测量混杂） | 在 N8 下加辅助说明 | **中** |
| B-P06 | N13/N14 | 非原文证据 | AI-A 将"用户确认"作为迁移节点的 evidence_location，未区分论文证据与外部用户输入 | 在节点表格中新增"evidence_source: user_input" 列 | **高** |

---

## 5. Missing Branches

| missing_branch_id | related_node | gap description | why important | suggested addition | severity |
|---|---|---|---|---|---|
| B-M01 | N5 | **Brier 分数缺失**：原文 Methods 明确提及 Brier scores，但 AI-A 的树与证据地图完全未提到 Brier——这是校准的另一种指标，且与 MAE 是互补的 | 缺乏 Brier 使得校准证据链不完整；Brier 与 MAE 含义/量纲不同 | 在 N5 或 E5 中补充 "Brier scores (bootstrap validation)" 证据项 | **中** |
| B-M02 | N4 | **低 SOFA 组 1 年死亡率的 RCS 阴性结果分支缺失**：原文明确报告 P-nonlinear=0.168，但 AI-A 树中未反映 | 选择性报告会高估方法的支持力，且该结果对用户做 1 年预测时有直接影响 | 新增一个 `if` 分支：低 SOFA 组 1 年 → 不显著 → 该亚组 1 年预测信心降级 | **高** |
| B-M03 | N8 | **中介分析的其他路径未验证分支缺失**：原文在讨论中提到不加捕获的炎症标志物/内皮功能障碍可能是额外路径，AI-A 树中无此分支 | 该分支说明中介比例（17.2–22.7%）可能被高估，因为未测量的中介变量未纳入 | 在 N8 下新增 "limitation: 未测量中介路径（炎症/内皮）可能性" | **中** |
| B-M04 | N3 | **亚组中"少数功效不足亚组"的 CI 含空值**：原文提到"all confidence intervals excluding the null value except for a few underpowered subgroups"，AI-A 未报告 | 这是亚组一致性 claim 的关键限定条件——不是所有亚组都显著 | 在 N3 的 evidence 摘要中补上"少数功效不足亚组 CI 含空值" | **中** |
| B-M05 | N9 | **时间趋势/时代效应分支缺失**：原文在 Limitations 中提及"temporal changes in clinical practice over the long study period may affect generalizability"，但 AI-A 的 N9 只关注"单中心/外部验证" | 即使内部验证充分，时间推移的实践变化也可能削弱泛化 | 在 N9 下新增 "limitation: 2008–2022 时间跨度的实践变化未建模" | **低** |
| B-M06 | N6 | **C-index 与 SOFA/SAPS-II 的比较缺失**：原文未报告 C-index 与 SOFA 或 SAPS-II 单独预测性能的比较，AI-A 也未追问——若 SHR 增量增益未量化，则"优于传统评分"的 claim 无直接支持 | Discussion 声称 SHR+SOFA 组合"beyond traditional ICU prognostic models"，但无对照性能数据 | 在 Follow-up Questions 中新增"是否有 C-index 增量比较（SHR+SOFA vs SOFA alone）" | **中** |

---

## 6. Required Fixes

1. **（必须）** 修正 N4：补充低 SOFA 组 1 年死亡率 P-nonlinear=0.168 的阴性结果；将 RCS 节点类型由 `evidence` 改为 `method`；区分"分段回归切点（SHR=1.0）"与"J 形曲线最低点（SHR=1.2）"两个概念。
2. **（必须）** 修正 N5：将 bootstrap 次数冲突（Methods: 200 vs Results: 1000）从"不确定"升级为"需向作者/附录确认的正式不确定性"；补充 Brier 分数作为独立校准指标。
3. **（必须）** 修正 N7 与 N6 的类型标注：将 C-index/MAE 改为 `statistic` 类型，将 SHAP 改为"可解释性方法（不代表有效性证据）"；在树中调整 N7 使其不从 N12 直接引出或加注限定。
4. **（必须）** 修正 N3：将 confidence 降为 low–medium；明确标注"亚组分析为探索性，交互功力未报告，低功效亚组 CI 含空值"；并提出"交互不显著 ≠ 效应一致"的限定。
5. **（必须）** 修正 N10：标注"基于主文 10 页文本检查；Supplementary Material 未纳入，E-value/阴性对照的最终确认需查补充材料"。
6. **（必须）** 修正 N14：移除"禁 HbA1c 轴"建议或重构为"剔除 HbA1c 极端值敏感性分析"，因 SHR 公式依赖 HbA1c，禁 HbA1c 则无法计算 SHR；对 N13/N14 的来源标注为 `user_input`。
7. **（必须）** 在证据地图中新增"Brier scores"项；新增"亚组 CI 含空值"限定项。
8. **（建议）** 新增缺失分支 M01–M06：Brier、RCS 阴性、中介未测量路径、亚组不显著限定、时间趋势效应、SHR+SOFA 增量性能比较。
9. **（建议）** 在 Follow-up Questions 中新增：① 亚组交互 P 完整矩阵；② 是否存在 C-index 增量比较分析；③ 是否做过时间分段验证（2010s vs 2020s）。

---

> 审阅人：AI-B（对抗审稿人/决策树攻击者）
> 审阅日期：2026-改造版
> 严重程度汇总：**高** × 12，**中** × 11，**低** × 4