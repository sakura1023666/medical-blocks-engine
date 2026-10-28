<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-19T11:23:33 | request_id=msg_281794ff-2320-4b97-89ef-accc51b89634 | usage={"input_tokens": 23357, "output_tokens": 2344, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=5847 -->
# AI-B Tree Attack

paper_id: paper_004
question_id: Q7
review_target: @rounds/A_tree_round1_paper_004_Q7.md
source_file: adversarial_lit_reading/chunks/paper_004_ewas_new.md

## 1. Attack Summary

**总体判断：需要重大修改**

**主要问题：**

1. **错误引用原文**：N2 节点声称「牙周病也可能改变行为/检测」，但这不是原文表述。原文只说「cannot rule out reverse causality」，并未具体说明反向因果方向。
2. **中介比例引用错误**：N9 节点声称中介比例 5%–11%，但原文 Results 3.6 报告的是 5.050%–11.494%，且 Discussion 中描述为「relatively modest (5%-11%)」。AI-A 使用「5%–11%」低估了实际数值，且来源标注为「Results 3.6」而非 Discussion。
3. **关键局限遗漏**：3.7 敏感性分析中「most pollutants were substantially attenuated after additional adjustment for smoking status」这一关键局限未被 AI-A 纳入决策树，这是影响 FDR 显著毒物稳健性的重要证据。
4. **碰撞偏倚节点表述不精确**：N8 声称「尼古丁代谢物与共因可能碰撞偏倚」，但原文明确限定是「when nicotine metabolites and other environmental exposures are simultaneously included as predictor variables」时才可能诱发碰撞偏倚，AI-A 未交代这一条件。
5. **E-value 节点因果表述过度**：N7 声称「E-value 使『全部由未测混杂解释』较难」，但原文只报告了 E-values 在补充表，未在正文给出具体数值，AI-A 的「较难」判断缺少原文数值支撑。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A1 | N2 | 「牙周病也可能改变行为/检测」（风险标签：因果过度） | 原文只说「cannot rule out reverse causality」，没有具体说明是「改变行为/检测」。AI-A 将原文的「无法排除」替换为具体机制，属于超出原文的 SPECIFIC 表述。 | 原文 P11：「The cross-sectional design of NHANES precludes causal inference and cannot rule out reverse causality.」无「behavior」「detection」字样。 | 改为：「横断面设计无法排除反向因果，但原文未指明具体机制」 | 中 |
| A2 | N9 | 「中介比例约 5%–11%」 | 原文 Results 3.6 报告具体值为 5.050%–11.494%，Discussion 写「5%-11%」。AI-A 使用了 Discussion 的粗略表述但标注来源为 Results 3.6，且「5%–11%」与准确值 5.05%–11.49% 存在出入。 | 原文 P4/P10：「5.050 %, 11.494 %, 10.188 %, 6.317 %, 5.710 %, 7.351 %」（Results 3.6）；「relatively modest (5%-11%)」（Discussion） | 修正为「5.05%–11.49%」并标注来源为 Results 3.6 与 Discussion；或统一为 5%–11% 并标注 Discussion。 | 低 |
| A3 | N8 | 「尼古丁代谢物与共因可能碰撞偏倚」 | 原文明确指出碰撞偏倚发生条件：「when nicotine metabolites (Total Cotinine, Total Hydroxycotinine, TNE-2) and other environmental exposures are simultaneously included as predictor variables in regression models」。N8 的表述未交代此条件，可能被理解为「只要有尼古丁代谢物就有碰撞偏倚」。 | 原文 P8：「when nicotine metabolites ... and other environmental exposures are simultaneously included as predictor variables in regression models, conditioning on these variables—which share "smoking" as a common cause—may induce collider bias」 | 补充限定：「当尼古丁代谢物与其他暴露同时纳入回归模型时」 | 中 |
| A4 | N5 | 「73 种只是暴露组的一部分」（risk_tag 证据不足） | 原文「the 73 toxicants investigated represent only a fraction of the human exposome」确认了此节点，但 N5 缺少上下文：原文紧接着建议「future studies would benefit from broader suspect screening or non-targeted analytical techniques」，建议补充。 | 原文 P11：「the 73 toxicants investigated represent only a fraction of the human exposome; future studies would benefit from broader suspect screening」 | 补充「未来需更广谱筛查」；确认证据充分 | 低 |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| B1 | N1 → N2 (limitation) | AI-A 用「limitation」标签连接 N1 到 N2，但 N1 是「结论应停在关联」，N2 是「反向因果」。边本身逻辑合理（反向因果是限制关联升为因果的局限），但 N2 的具体内容需要修正（见 A1）。 | 修正 N2 后此边可通过；建议边标签改为「支持 claim 不升为因果」的「limitation」语义。 | 中 |
| B2 | N1 → N7 | N7 声称「E-value 使『全部由未测混杂解释』较难」，但原文只在 Discussion 末尾一句提及「E-values suggest that unmeasured confounding is unlikely to fully explain the observed associations」（P11），无具体 E-value 数值。AI-A 的「较难」是对原文「unlikely to fully explain」的转述，可接受但建议标注「根据原文表述，未报告具体值」。 | 在 N7 中补充「原文未报告具体 E-value 数值」 | 低 |
| B3 | N0 → N1 | N0 是问题「局限是否翻转主关联方向」，N1 是「主结果是关联不是因果」。但 AI-A 的 Provisional Answer 中说「原文未显示它们把 FDR 显著毒物的关联符号整体反转」——这句话在决策树中没有对应节点，应加入。 | 将 Provisional Answer 中的「关联符号未反转」判断纳入决策树作为叶子节点。 | 中 |

---

## 4. Evidence Problems

| 问题编号 | 问题类型 | 位置 | 批评 | 修正建议 | 严重程度 |
|---|---|---|---|---|---|
| E1 | 过度具体化 | N2 | 「牙周病也可能改变行为/检测」非原文表述；原文只说「cannot rule out reverse causality」 | 改为「无法排除反向因果，原文未指明具体机制」 | 中 |
| E2 | 遗漏关键证据 | 全面 | 3.7 节「most pollutants were substantially attenuated after additional adjustment for smoking status」是评估毒物关联稳健性的重要信息，未被 AI-A 纳入决策树 | 新增节点：「吸烟调整后多数毒物关联显著减弱，仅 lead/2HPMA/2-Naphthol 在非吸烟者中仍显著」 | 高 |
| E3 | 中介比例来源混淆 | N9 | 使用「5%–11%」但标注来源为 Results 3.6；准确值为 5.05%–11.49% | 统一为准确值并正确标注来源 | 低 |
| E4 | 碰撞偏倚条件缺失 | N8 | 未说明碰撞偏倚的触发条件（同时纳入尼古丁代谢物与其他暴露） | 补充限定条件 | 中 |
| E5 | E7 与 N5 的证据位置标注模糊 | N5 | 原文第 11 页 Discussion 第 4 条局限，AI-A 只写「Discussion」未标注 P11 | 统一标注页码 | 低 |

---

## 5. Missing Branches

| 分支编号 | 遗漏内容 | 原文依据 | 被遗漏的影响 | 严重程度 |
|---|---|---|---|---|
| M1 | **吸烟调整后多数毒物关联减弱** | P9：「the associations of most pollutants were substantially attenuated after additional adjustment for smoking status」 | 这是评估 FDR 显著毒物稳健性的关键局限，直接影响「关联方向是否翻转」的结论。若不纳入，决策树对「局限是否影响结论」的回答不完整。 | **高** |
| M2 | **非吸烟者亚组结果** | P9：「analysis restricted to the subpopulation of never-smokers identified lead, 2HPMA, and 2-Naphthol as being significantly and positively associated with periodontitis risk」 | 说明部分毒物在排除吸烟混杂后仍显著，支持「关联方向未被翻转」；但也说明多数 FDR 显著毒物在非吸烟者中不稳健。 | **高** |
| M3 | **无加权分析的理由** | P3：「we reported unweighted results to maintain methodological consistency with prior investigations and to avoid potential over-adjustment bias」 | 这是方法局限，部分审稿人可能质疑未加权 ExWAS 的代表性。 | 低 |
| M4 | **牙线/就诊变量可能为中介而非混杂** | P2-3 列出的协变量包含「time since last dental visit, mouthwash use, flossing frequency」；Discussion 未讨论这些变量是否为中介而非混杂 | 若这些变量是中介，调整后过度调整可能低估关联。 | 中 |

---

## 6. Required Fixes

1. **修正 N2**：删除「牙周病也可能改变行为/检测」的具体机制表述，改为「横断面设计无法排除反向因果，原文未指明具体机制」。

2. **新增节点 M1 与 M2**：在决策树中增加「吸烟调整后多数毒物关联减弱」「非吸烟者仅 lead/2HPMA/2-Naphthol 仍显著」两个节点，并说明其对「关联方向是否翻转」的影响。

3. **修正 N8**：补充碰撞偏倚的触发条件（「当尼古丁代谢物与其他暴露同时纳入回归模型时」）。

4. **修正 N9**：将中介比例改为「5.05%–11.49%」，确认证据来源标注为 Results 3.6 与 Discussion 两处。

5. **在 N7 中补充说明**：原文仅提及「E-values suggest unmeasured confounding is unlikely to fully explain observed associations」，未在正文报告具体 E-value 数值；如需具体数值应引用 Supplementary Table 11。

6. **将 Provisional Answer 的核心判断「原文未显示局限使 FDR 显著毒物的关联符号整体反转」纳入决策树**作为显式节点，使结论源自树结构而非文本段落。