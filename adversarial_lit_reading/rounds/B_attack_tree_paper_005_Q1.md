# AI-B Tree Attack

paper_id: paper_005
question_id: Q1
review_target: @rounds/A_tree_round1_paper_005_Q1.md
source_file: adversarial_lit_reading/chunks/PMID40910275.xml

## 1. Attack Summary

总体判断：**部分可信（需中度修改）**

AI-A 的决策树整体严谨、证据落点基本准确，绝大多数节点能在原文找到支撑（EO-IBD<20 定义、ICD 编码、5 档 SDI、21 区域、204 国、1992 拐点、SII=0.83、BAPC 投影数值、UC/Crohn 未分层、<6 岁不可分析等均与原文一致）。未发现编造证据或重大因果过度。**不构成"不可信"，但也非可直接采用**——存在若干结构性误读、证据不完整与方法设定冲突被软化的问题，需 AI-A 中度修订后可信度才稳固。

主要问题（按影响排序）：

1. **结构性误读（N2）**：把"EO-IBD(<20)研究人群定义"当作"1 个二元亚组（EO-IBD vs 全龄 IBD 背景比较）"。原文并无 EO-IBD-vs-adult IBD 对照分析；全 IBD 仅在 Supp Fig 2 作比例分母。这会直接扭曲 Q1"预设几个分组"的计数。
2. **SDI 五档被静态化（N4）**：Methods §2 明确 SDI 取值"时变"，国家/地区在 1990–2021 内可在 quintile 间迁移，5 档并非固定互斥划分。AI-A 把它当静态 K=5 框架，遗漏与"预设类别数"直接相关的时变性质。
3. **方法设定冲突被软化（N16/N11/N12）**：SII 是 SDI 谱上的**线性**回归（DALYs 给出单一梯度 –1.06），而 DALYs"U 形"两端高负担恰恰违反线性单调假设。AI-A 正确指出 U 形是结果观察，却未点明"线性 SII 对 U 形数据设定失配"。
4. **推断当原文事实（N14）**：正文未出现"permutation test"，AI-A 将其当作原文方法陈述（实为所引 Kim et al. ref10 / 软件默认）。
5. **证据不完整（E2/E8/N11）**：ICD-9 具体码省略；Joinpoint 各指标段数主文未列（仅 1992）；Concentration Index=11% 遗漏。

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| NA1 | N2 | "核心研究对象预设 1 个年龄 cutoff 亚组：EO-IBD（<20 岁）vs 纳入分析的全 IBD 背景比较" | 把"研究人群纳入定义"重构为"二元亚组比较"。原文无 EO-IBD-vs-adult IBD 对照分析；全 IBD 仅作 Supp Fig 2 比例分母（incident 3.73%、prevalent 1.49%、death 1.55%、DALYs 4.06%）。属结构误读，扭曲 Q1"几个分组"计数。 | Methods §1："EO-IBD, defined as IBD diagnosed before 20 years of age"；Results §3/Supp Fig 2 仅给占全 IBD 比例。无对照分析。 | 改为"研究人群定义为 EO-IBD(<20)，属纳入阈值而非分组变量；全 IBD 仅作比例参照"；从 Q1 计数表移除或降级该项。 | 中 |
| NA2 | N4 | "SDI 分层预设 5 档 quintile（high→low SDI）" | Methods §2 明确"SDI values demonstrate temporal variability"——国家/地区 SDI 归属在 1990–2021 内随时间变化，5 档 quintile 并非固定互斥划分。AI-A 当静态 K=5 框架，遗漏与"预设类别数"直接相关的时变性质。 | Methods §2 原文："SDI values demonstrate temporal variability, reflecting dynamic socioeconomic changes"。 | N4 增限定"5 档为 GBD 框架，但成员归属时变、非固定聚类"；Q1 计数表标注"框架 K=5，非静态划分"。 | 中 |
| NA3 | N14 | "Joinpoint 拐点识别为数据驱动（permuation test 选段；无先验趋势形态假设）" | 正文只说"objectively identify... without a priori assumptions about trend patterns"，**未显式写 permutation test**。该机制来自所引 Kim et al.(ref10) 与 Joinpoint 软件默认，属 AI-A 合理推断而非原文陈述，不应作为原文方法事实。"数据驱动"结论本身成立，不影响主结论。 | Methods §3 原文 + ref10（Kim et al. 2000, permutation tests for joinpoint）。正文未出现"permutation"。 | 改为"软件(Kim et al. 算法/默认 permutation test)数据驱动选段"，标注来自引用/软件而非正文。 | 低 |
| NA4 | N16 | "U 形 SDI–DALYs 为 Results 观察到的形态；Methods 未预先假设 U 型/阈值/单调假设" | AI-A 正确区分"结果观察 vs 方法预设"，但低估内部矛盾：SII 为 SDI 谱**线性**回归（DALYs 单一梯度 –1.06），而 U 形两端高负担违反线性单调。若 DALYs 真为 U 形，则 SII 线性模型设定错误，–1.06 不能作为干净线性摘要。AI-A 并置二者却未指出设定失配。 | Methods §4（SII 线性）+ Results §4（DALYs U 形, SII_DALYs: 0.4→–1.06）+ Supp Fig 4。 | N16 增"线性 SII 与 U 形 DALYs 设定不一致，SII 对 U 形可能失配，需非线性检验（RCS/分段回归）"明确说明。 | 中 |
| NA5 | N11 | "SDI 与 incidence 正相关（SII=0.83）；与 DALYs 呈 U 形" | (a) 同一证据原文还报 Concentration Index=11%，AI-A 节点遗漏；(b)"正相关"是 Results 描述性用语，SII=0.83 是线性回归梯度，二者方向一致但概念不同，括号并列易被读成"SII 证明了正相关"。 | Results §4："the SII for incidence rate is 0.83, and the Concentration Index is 11%"。 | N11 补 Concentration Index=11%；区分"描述性正相关"与"线性 SII 梯度"。 | 低 |
| NA6 | N6 | "年龄按 GBD 5 年间隔组（Results 重点 <5 与 15–19 岁）" | Q1 直接问"预设几个分组"。EO-IBD(<20)内 GBD 5 岁年龄带应为 <5 / 5–9 / 10–14 / 15–19 共 4 档，AI-A 计数表写"多档（GBD 标准）"未给具体数，削弱对 Q1 的直接回答（U1 已标不确定，但 Node/Table 应给数）。 | Methods §5（5 年间隔）+ GBD 标准年龄结构。 | 计数表年龄行写明"EO-IBD 内 4 档（<5/5–9/10–14/15–19）"并标注来自 GBD 框架。 | 低 |
| NA7 | N17 | risk_tag="因果过度"；BAPC 预测方向来自模型外推 | BAPC 是趋势外推/预测，原文未声称因果（Discussion 反称"limited capacity for causal inference"）。AI-A 正文亦说"非 RCT 式暴露方向假设"，但 risk_tag 标"因果过度"与正文自洽性差，易误读为"论文做了因果过度声明"。 | Methods §5 + Results §2 + Discussion（BAPC limitations: limited capacity for causal inference and forecasting）。 | risk_tag 改为"预测外推·非因果"或"外推不确定"。 | 低 |
| NA8 | N1（Provisional Answer） | "数据驱动定 K/定类：仅 Joinpoint 时间拐点为数据驱动" | "定 K/定类"限定词使该表述在方法预设层面成立；但读者易把"数据驱动"窄化为仅此一项，而忽略原文结果层同样有数据涌现发现（U 形 SDI–DALYs、双峰年龄负担）——AI-A 在 N16 已正确区分二者，Provisional 措辞与该区分略不一致。 | Results §3（双峰）/§4（U 形）。 | Provisional 改为"方法预设的定 K 环节仅 Joinpoint；另有 U 形/双峰等为结果层涌现（非预设）"。 | 低 |

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| EA1 | N1 -->\|because\| N2 | "because" 边把"EO-IBD<20 纳入定义"当作"核心分层=GBD 框架/研究者先验"的证据支撑。受 NA1 影响，该推理链部分不成立（纳入定义≠分层亚组）。 | 若按 NA1 重定义 N2，则该边改为 `defines_population`（定义研究人群）而非 `because`（分层依据）。 | 中 |
| EA2 | N12 -->\|if SDI 不平等分析\| N11 | 边把"线性 SII 模型"与"incidence 正相关 / DALYs U 形"接在同一子树，却未标注 SII 线性对 DALYs U 形不适用（见 NA4）。虽有 N11-->limitation-->N16 部分补救，但 N12→N11 的 `if` 边掩盖了设定冲突。 | N12→N11 边加注"线性 SII 仅适用 incidence 正相关情形；DALYs U 形需另列非线性分析"。 | 中 |
| EA3 | N15 -->\|supported_by\| E8 | E8 摘要写"Joinpoint 识别 mortality/DALYs 拐点约 1992"，但原文仅 Results §1 报告 1992 单一拐点，incidence/prevalence 的 joinpoint 段数与 APC 未在主文列出。`supported_by` 把"数据驱动拐点（含段数 K）"当成已完整报告，实际 K 未披露。 | E8/N15 注明"仅 mortality/DALYs 报告 1992 拐点；其余指标 joinpoint 段数主文未列（见 U2）"。 | 低 |
| EA4 | N3 -->\|supported_by\| E2 | E2 摘要只列 ICD-10（K50–K52, K52.8–K52.9）与笼统"ICD-9"，省略 ICD-9 具体码（555–556.9, 558–558.9, 569.5）。`supported_by` 所引证据不完整。 | E2 补全 ICD-9 码："ICD-9 (555–556.9, 558–558.9, 569.5)"。 | 低 |

## 4. Evidence Problems

- **E2 不完整**：ICD-9 仅写"ICD-9 编码"，原文给出 555–556.9、558–558.9、569.5（见 EA4）。
- **E8 过度呈现**：把"1992 拐点"写成 Joinpoint 完整结果，实际主文仅披露 mortality/DALYs 单一拐点，其余指标段数 K 未列（见 EA3）。
- **E14 措辞混淆预设/结果**："摘要预先描述未来 incidence 增加..."——该方向是 BAPC 结果投影，非 a priori 假设；"预先描述"措辞与 AI-A 全程强调的"预设 vs 结果"区分相悖。
- **N11 指标遗漏**：原文同一证据含 Concentration Index=11%，节点未收录（见 NA5）。
- **E15 缺席证据（absence claim）**："全文未提及 K-means/LCA/silhouette/BIC/RCS"——经查正文确实无此类词，缺席主张成立；但应注明这是"正文 + 所读 chunk"范围，Supplement 未随文提供，存在盲区（需复查 Supplement）。

## 5. Missing Branches

- **MB1（SDI 时变成员归属）**：无节点/边捕捉"5 档 quintile 成员归属时变"——国家可在 1990–2021 内迁移 SDI 档，5 档非固定聚类。应新增独立 limitation 节点（支撑 NA2）。
- **MB2（上游数据为模型派生）**：N8 方法清单只列本研究分析链（Joinpoint/SII/BAPC/标化），未把"GBD 输入数据本身由 spatiotemporal Gaussian process regression、Bayesian regularization、trimmed meta-regression 产出"作为独立方法层。该层影响"数据驱动 vs 先验"判断的数据基底（Methods §1）。
- **MB3（迁移边界缺失）**：本文为全球聚合描述性负担研究，无可迁移到 (a) 个体水平亚型发现、(b) 未知类别数 K 的聚类问题、(c) 因果暴露-结局推断。AI-A 在 N21/Provisional 有暗示但未作为显式分支。建议新增 `migration_limit` 节点。
- **MB4（线性 SII vs U 形设定冲突）**：缺独立节点承载"线性 SII 对 U 形 DALYs 设定失配"（见 NA4），目前散落在 N16 限定语中。
- **MB5（K 未披露）**：缺"Joinpoint 段数 K 主文未报告"的限制节点，使"数据驱动定 K"主张无法从主文核验（仅 U2 不确定项带过）。

## 6. Required Fixes

1. **按 NA1 重定义 N2**：纳入定义（inclusion threshold）≠ 二元亚组；从 Q1 计数表降级或移除"研究对象亚组"行，相应改 EA1 边标签为 `defines_population`。
2. **按 NA2/MB1 补 SDI 时变限定**：N4 增"成员归属时变、非固定聚类"；新增 MB1 节点；Q1 计数表标注"框架 K=5，非静态划分"。
3. **按 NA3 修正 N14**：permutation test 归因到 Kim et al. ref10 / 软件默认，不作为原文方法陈述。
4. **按 NA4/MB4 显式标注设定冲突**：线性 SII 对 U 形 DALYs 失配，建议补非线性检验（RCS/分段回归）；新增 MB4 节点。
5. **按 NA5/EA4 补证据**：N11 补 Concentration Index=11%；E2 补 ICD-9 具体码（555–556.9, 558–558.9, 569.5）。
6. **按 MB3 增迁移边界分支**：新增 `migration_limit` 节点，明示不可迁移到个体亚型发现 / 未知 K / 因果推断。
7. **按 NA7 修正 N17 risk_tag**：改为"预测外推·非因果"或"外推不确定"，与正文一致。
8. **按 NA6 给年龄档数**：计数表年龄行写明"EO-IBD 内 4 档（<5/5–9/10–14/15–19）"。
9. **按 EA3/MB5 增"K 未披露"限制节点**：标注 Joinpoint 段数主文未列，"数据驱动定 K"需查 Supplement 方可核验。
