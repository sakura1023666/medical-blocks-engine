<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-09-30T11:26:44 | request_id=msg_012230c5-18fd-4b36-99e5-b280c3b8885b | usage={"input_tokens": 6671, "output_tokens": 1916, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=4017 -->
# AI-B Tree Attack

**paper_id:** paper_022
**question_id:** Q7
**review_target:** @rounds/A_tree_round1_paper_022_Q7.md
**source_file:** adversarial_lit_reading/chunks/paper_022_2026_wang_ckm_cum_egdr_stroke.md

---

## 1. Attack Summary

**总体判断：需要重大修改**

**主要问题：**

AI-A 决策树在 N5 节点上存在严重的逻辑跳跃和证据误用。该节点声称"局限可能偏倚幅度，但主方向在敏感性中仍负向"，并引用 E4（Results）作为支持。然而：

1. **E4 的证据位置标注模糊**——仅标注"Results"，未定位到具体敏感性分析段落
2. **N5 的 claim 超出了原文明示范围**——原文未明确说明敏感性分析是否涵盖所有关键局限（如竞争风险未建模）
3. **N5→N2 的边缺乏支撑**——缺乏"自报结局的验证效度"是否已被敏感性分析覆盖的证据

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| B-N1 | N5 | "局限可能偏倚幅度，但主方向在敏感性中仍负向" | **逻辑跳跃**：原文并未在 Discussion 中明确声明"敏感性分析覆盖所有局限"。AI-A 将"多模型结果一致"扩展为"对局限稳健"，属于过度推断 | 原文摘要提及多模型/敏感性（"In fully adjusted models...OR 0.43, 0.29, 0.66"），但敏感性分析具体覆盖范围未在提供 excerpt 中明确 | 改写为："主方向在多模型调整中一致负向，但原文未明确敏感性分析是否覆盖所有已讨论局限（如竞争风险）" | **高** |
| B-N2 | N1 | "观察性残留混杂"归为 limitation | 证据位置与事实相符，但 risk_tag 标注"因果过度"与节点本身的 limitation 陈述矛盾——limitation 节点不应标"因果过度" | E1 指向 Discussion Limitations，合理 | 移除 risk_tag "因果过度"或在 N5 上标注该 tag | **低** |
| B-N3 | N3 | "分期操作化/期3测量限制在复现包中突出" | **证据不确定**：E2 标注指向"Methods/数据"和"复现包"，但原文 excerpt 中未见"复现包"相关内容。REPRODUCIBILITY 问题可能来自论文正文外的补充材料 | 原文 excerpt 截断于方法与结果，未包含复现包相关内容。需复查原文全文 | 标注"需复查原文"，确认复现包存在及期3测量限制的具体描述 | **中** |
| B-N4 | N4 | "两波聚类≠真实连续轨迹" | 表述基本准确，但未与原文中"These patterns...provide a basis for subsequent subgroup analyses" 的措辞紧张关系做区分——原文承认两波数据的局限，但未将其作为主要 limitation 展开 | 原文 Fig.2C 提及"using two-time point data"，methods 中 k=4 来自 elbow method | 补充原文对两波聚类的态度："作者将其作为分析方法而非 limitation 展开讨论，AI-A 将其识别为 limitation 合理但需标注此为 reviewers' interpretation" | **低** |
| B-N5 | N6 | "竞争风险/失访" | **证据缺失**：E5 标注"全文"作为证据来源，但原文 excerpt 中**未出现**"competing risk"、"death"、"mortality"或"失访"相关表述。此节点可能是 AI-A 从"stroke 作为结局"推断的，而非原文明示 | 原文 excerpt 中无竞争风险讨论的直接证据 | 标注"需复查原文"，确认原文是否讨论了死亡竞争风险；若无，则将此节点标记为"reviewer-inferred limitation"而非原文 limitation | **高** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| B-E1 | N1→N5 | **逻辑跳跃**：从"存在残留混杂"直接跳至"局限不改变主方向"。原文在摘要中报告多模型调整结果，但 Discussion 是否明确声明"残留混杂不影响方向"？若未明示，此边不成立 | 在 N5 上增加条件："仅当敏感性分析覆盖关键混杂时，方向稳健性才能成立"；或拆分 N5 为 N5a（多模型调整稳健）和 N5b（对所有局限稳健），后者需更高证据标准 | **高** |
| B-E2 | N5→E4 | E4 未定位到具体敏感性分析段落。"Results"标注过泛，无法验证"敏感性分析覆盖局限"这一结论 | E4 需引用具体敏感性分析方法（如 E-value、PS 匹配、排除事件）及其结果 | **中** |
| B-E3 | N6→E5 | E5 证据位置为"全文"，不可验证。竞争风险未建模是从"stroke 结局+有死亡风险"推断的，但原文是否承认此局限未明 | 改为："原文未讨论竞争风险。此为 reviewer 推断的 method logical gap，非原文 limitation" | **高** |

---

## 4. Evidence Problems

1. **E4 位置过泛**：仅标注"Results"，无法区分是主分析还是敏感性分析结果。主分析一致 ≠ 敏感性覆盖所有局限。
2. **E5 不可验证**：标注"全文"作为证据来源，但原文 excerpt 中未见竞争风险相关讨论。此节点可能不是原文 limitation，而是 AI-A 的方法学补全。
3. **E2 与原文不对应**：excerpt 中无"复现包"相关内容。若复现包在论文正文外的 supplement，需明确标注引用链路。
4. **N5 证据混用**：将"多模型调整方向一致"（主分析）与"对局限稳健"（需敏感性分析支持）混同一处。

---

## 5. Missing Branches

| missing_branch_id | gap | rationale | suggests_to_add |
|---|---|---|---|
| B-M1 | 外推性限制（CHARLS 仅中国≥45岁人群） | 原文摘要明确"CHARLS"为人群来源，但 AI-A 节点中未包含外推性限制作为独立 limitation 节点 | 在决策树中加入 N7："limitation: CHARLS 仅覆盖中国≥45岁，外推至其他人群受限" |
| B-M2 | 两波数据时间间隔（2012→2015）与结局窗口（2015→2018）的错位 | 暴露评估（2012-2015）早于结局随访（2015-2018），但 AI-A 未讨论此时间结构对因果解释的约束 | 在 N5 中增加限制条件："暴露-结局时间序支持 temporal 关系，但未排除反向因果（如未诊断卒中前状态改变 eGDR）" |
| B-M3 | 自报卒中的验证效度 | 原文提及"自报卒中"作为 limitation，但 AI-A 未扩展此节点是否被敏感性分析（如排除自报病例）覆盖 | N2 后分支：是否做了 sensitivity analysis 排除自报？若无，则 N2 对方向的威胁未消解 |

---

## 6. Required Fixes

1. **[高] 拆分 N5**：将"主方向稳健"与"对局限稳健"分离为两个节点。主方向稳健由 E4（多模型调整）支持；对局限稳健需单独证据。若无证据，N5 应加"unverified" tag。
2. **[高] N6 重新定性**：若原文未讨论竞争风险，则 N6 为"reviewer-inferred limitation"，不能在决策树中与其他原文 limitation 并列。需加 distinct 标记。
3. **[高] E5 证据标注修正**：从"全文"更正为"inferred by reviewer"，并注明需复查原文。
4. **[中] E4 细化定位**：标注具体敏感性分析名称（如 E-value、排除病例、PS 匹配等）及结果。
5. **[中] 补充外推性 N7**：CHARLS 人群限制应作为独立 limitation 节点出现。
6. **[低] N1 risk_tag 移除**：limitation 节点不应标"因果过度"，此 tag 应移至 N5 或其他 claim 节点。
7. **[低] 添加 N2 分支**：自报结局是否有验证效度/敏感性排除，缺失则分支不完整。