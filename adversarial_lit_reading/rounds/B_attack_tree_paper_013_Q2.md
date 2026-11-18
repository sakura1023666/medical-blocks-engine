<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-30T15:35:36 | request_id=msg_4362e16b-7c57-49d2-85c1-003e1fa513af | usage={"input_tokens": 25084, "output_tokens": 3690, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=7301 -->
# AI-B Tree Attack

paper_id: paper_013
question_id: Q2
review_target: @rounds/A_tree_round1_paper_013_Q2.md
source_file: adversarial_lit_reading/chunks/paper_013_joint_traj_tyg_cvd_elsa.md

## 1. Attack Summary

总体判断：**需要重大修改**

主要问题：
1. **E4 证据误置**：AI-A 将 BH-FDR 错误描述为仅用于“轨迹组间比较”，但原文明确称其用于“multiple comparisons across trajectory groups”，且这一环节仅在 Cox 回归之后出现，FDR 是否覆盖全部 72 个 HR（含 Model 1–3 及各结局）确实不明——AI-A 的 U1 说得对，但 N6 的“假设族边界未声明”定位为“低严重度”明显过低。
2. **N5 存在关键偷换**：AI-A 断言“BH-FDR 用于轨迹组间多重比较校正”且“Fig 5 注明所有关联经 BH 后仍存活”——后者正确（原文确有 “All associations survived correction…”），但前者的问题是：**原文未说明 FDR 是对 Model 4 只有，还是对所有 4 个模型分别做**。这属于原文模糊处，AI-A 没有如实标注为原文未明确说明，而是直接断言。
3. **N2 的因果链有问题**：AI-A 把“卒中仅最高组显著”归因于“并集聚合掩盖组分异质性”，但原文明确提出卒中仅最高组显著的原因解释是 “limited statistical power”。AI-A 将并集聚合作为更优解释，文本不符原文归因。
4. **E8 对应 node 不完整**：E8 证据被标记为 only used_by N8，而 N8 本身是“敏感性分析未校正”的 limitation。但 E8 其实同时证明了**敏感性分析(6)的稳健性**，是正面证据，不应只作 limitation 用。
5. **“72 个 HR”未经原文直接验证**：AI-A 在 Provisional Answer 中给出“≈72 个 HR”（6 体系×3 结局×4 模型×3 暴露组？），但原文没有直接给出 72 这个数。AI-A 自己计算得出此数应标注为“AI-A 计算估计”，不能与原文信息混在一起。

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| B-N1 | N1 | 复合 CVD=五组分并集聚合为主终点 | 基本正确，但表注（Table 1 脚注）与 Methods Outcome 定义措辞不完全一致——表格注列了六项（含心律 disorder），与 Methods 列出的五类不完全对应。原文也有语义重叠（heart disease 包含 heart attack/heart failure/angina/rhythm disorder，而 stroke 是其另一组分）。建议准确引用原文定义，不应自创“五组分”表述。 | Methods L211–227：primary outcome 定义为 heart disease 或 stroke 的复合；而 heart disease 本身又包含四个子类。故应是“五类事件”而非“五组分并集”。 | 改为准确引用原文定义：主终点=新发心梗/心衰/心绞痛/心律异常/卒中的复合（“新发心脏病或卒中”），并说明表注术语与正文不完全一致。 | 中 |
| B-N2 | N2 | 并集聚合掩盖组分异质性 | 原文从未使用“掩盖异质性”的说法，也没有直接支持这一因果主张的证据。原文对卒中解释为 limited statistical power，而非并集聚合问题。AI-A 将此作为 N1→N3 的中间推理，属性为“逻辑跳跃”正确，但在 tree 中的因果链 N2→N3 缺乏原文支撑。 | Results L786–793：原文用 post-hoc power 解释卒中；讨论部分也说 stroke 仅最高组显著与 limited power 一致。唯 Fig 5 注明确“所有关联经 BH 后仍存活”，即未说卒中分析中被掩盖的组分单独建模。 | 将 N2 改为：原文对卒中不足的解释为功效有限（65.2%/81.3%），未做组分单独建模；并集聚合的代价是异质性不可见——这是 AI-A 的推断而非原文声明，请标注为“推断”而非“claim”。 | 高 |
| B-N5 | N5 | BH-FDR 校正轨迹组间比较 | 原文 Statistical analyses 说 “Benjamini–Hochberg false discovery rate (FDR) procedure was applied to adjust for multiple comparisons across trajectory groups.” 但**没有说明是否对所有模型和所有结局分别做**。AI-A 的 E4 说“轨迹组间多重比较校正”不错，但 Provisional Answer 里说“多重比较仅对轨迹组间比较做了 BH-FDR”则过于绝对——原文未说明交互和敏感性的校正，但也未说明它们被排除于校正之外；S5 是全部 72 个 HR 的表，无法确认 Fig5 只是 Model4 还是含全部模型。 | Methods L368–370；Fig 5 caption 未注明模型数量 | N6 正确，但应升级其严重度至“高”，并建议 AI-A 将 Provisional Answer 中的结论“仅对轨迹组间比较做了 BH”改为“原文仅在 Fig 5 注中声明所有关联经 BH 后仍存活，但 FDR 族的具体范围（是否含 S5/S6/交互）原文未明确说明”。 | 高 |
| B-N7 | N7 | 次终点不显著用 post-hoc power 说明 | 原文确实这么做了——对 stroke 中间组用 65.2%/81.3% 功效解释。但 AI-A 在 node 表中把它定位为"evidence"并标注"因果过度"，这是对的。但在全 tree 里，把 post-hoc power 解释放在 N7 而 N5 之后，隐含认为这是 FDR 校正的补偿，原文并没有把两者联系起来。 | Results L786–793；Discussion 也提到 limited power for stroke 作为 limitation | 建议将 N7 明确定性为“作者的 post-hoc 解释，存在循环论证（用观察到的 HR 算功效）”，与 BH-FDR 分开，不应用 N5→N7 的先后关系暗示补偿关系。 | 中 |
| B-N8 | N8 | limitation 72 个 HR 的展示分层降低视觉多重比较 | 原文从未提到“视觉多重比较”或“展示分层降低视觉多重比较”。AI-A 此 claim 是从“主文只报 Model4+S5 全量”这一事实推理出的解释，但原文没有将其作为 limitation 讨论。此外“72 个 HR”为 AI-A 自算，原文无此数。 | 原文 Discussion limitations 未提及多重比较展示策略 | N8 应重命名为“AI-A 推断”，并去“原文 limitation”定位；同时将 FDR 族范围不明的归纳到 U1 而非 N8。 | 中 |
| B-N4 | N4 | 两法头对头：ΔC、NRI、IDI（SuppTable8），差异不显著 | 证据成立，但 Supp Table 8 原文未附正文中，AI-A 标注 Results L1275–1287 可能是错误定位（原文无 L1275-1287；正文对三结局的 C 统计量比较在 Results 后半段可见）。该处证据位置可能需要改为“Results Formal comparison…”；行号需复核。 | 原文 Results 段落有 “Formal comparison of discriminative performance… C-statistics … 0.003 (P=0.723)… NRI and IDI…P>0.8”；但无 L1275 等页码。 | 改写 evidence_location 为可核实位置，并说明 NRI/IDI 对三结局均不显著（P>0.8）。 | 低 |
| B-N3 | N3 | 多层暴露用双法并行（非合并成单一指数） | 方法描述正确，但缺乏证据支撑“非合并”的用意。原文确实并行运行两套 GBMTM，但从未说明这是为了“处理多层暴露”还是因为 WHtR/BMI 本就不能合并。AI-A 将其作为方法论判断，但没有错误——建议补充：合并不是原文考虑过的选项，因为两法各自解决不同科学问题（BMI vs 中心性肥胖）。 | Methods L286–290 | 在 N3 补充“原文未讨论过将两法合并为单一暴露”这一边界，避免把“并行”误当“主动设计的多层暴露策略”。 | 中 |

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| B-E1 | N1 → N2 | N1 是方法节点，N2 是推断节点。N1 对并集聚合的描述正确，但 N2 说“掩盖组分异质性”是从 N1 推断出的批评，原文没有直接在“并集聚合”与“卒中不显著”之间建立因果关系（原文用 limited power 解释）。Edge 上的逻辑是 AI-A 自己的推断，应标注。 | 在 edge 上标注“AI-A inference”，并建议将 N2 改为“原文解释为功效限制；并集聚合是否是原因不得而知”。 | 高 |
| B-E2 | N2 → N3 | N2 是推断，N3 是下一分支“多层暴露”。二者无语义联系，tree 结构上不应把 N2 直接指向 N3。N2 应导向“多重比较/次要终点报告规范”（N5/N7），而 N3 应该从 N1 分出或在 N0 下单独分支。 | 调整 tree 结构：N3 从 N0 直接分支（多层暴露维度）；N2 指向 N5 或 N7（组分异质性→次要终点报告）。 | 高 |
| B-E3 | N5 → N6 | N5 说“BH-FDR 用于轨迹组间比较”，N6 说“假设族边界未逐字声明”。两个节点是同一问题的两面。N5→N6 的 edge 语义有问题，因为 N5 先斩钉截铁，N6 再说“未声明”。若原文未声明 FDR 族边界，则 N5 就不应斩钉截铁。建议将 N5 改为“原文在 Fig5 注中声明所有关联经 BH 校正后仍存活，但未说明 FDR 族是否含 Model1–3/S5/S6”，然后 N6 是对其的补充。 | 改写 N5，让 N5 与 N6 并列而非因果。 | 高 |
| B-E4 | N6 → N7 | N6 是 uncertainty，N7 是作者 post-hoc power 解释。两者无因果。edge 暗示“FDR 族不明→因此次要终点只能用 post-hoc power 解释”，但原文没有建立此逻辑。 | 删除该 edge 或改为并列关系。 | 中 |
| B-E5 | N7 → N8 | N7 说卒中 limited power，N8 说 72 个 HR 展示分层。两者之间无因果，且 N8 本身是 AI-A 推断。 | 删除 edge；N8 作为独立 limitation 节点，或并入 U1。 | 中 |

## 4. Evidence Problems

1. **证据误置（E4/E5）**：AI-A 将 E4 归为“Benjamini–Hochberg FDR 用于轨迹组间多重比较校正”，但原文说法是 “applied to adjust for multiple comparisons across trajectory groups”，**没有明确是只对轨迹组间还是对全部结果**——AI-A 在 N5 将其绝对化，又在 U1 说边界不明，前后矛盾。
2. **证据位置不实（E8/N8）**：AI-A 用 E8 作为 N8 的“敏感性 9 项未校正”证据，但原文没有任何“未校正”的表述——原文只是没有说明是否校正，不能等价于“未校正”。这个证据是缺默（absence of evidence）而非“原文未做”。
3. **“72 个 HR”并非原文内容**：AI-A 的 Provisional Answer 断言“72 个 HR”（6 体系×3 结局×4 模型×3 暴露组），这是 AI-A 自己的计算，原文全文没有 72 这个数字。应明确标注为 AI-A 估计值。
4. **因果关系误置（E5）**：AI-A 将 E5（卒中仅最高组显著→post-hoc power 解释）作为“evidence”，但原文对卒中不显著的解释是 power。E5 作为 evidence 在 N7 里是原文章节描述，但 N7 的“因果过度”标注不充分——原文确实是在用 power 解释，没有把它当校正方案。

## 5. Missing Branches

| missing_branch | why it matters | suggested action |
|---|---|---|
| M1: **未提到卒中事件数少（83 例，4.6%）本身对 Cox 稳定性的影响** | 原文 Table 1/2/3 表明卒中事件数为 83（4.6%），严重低于复合 CVD。如此稀有的终点，即使只用最高组比较，HR=6.74 的 CI 极宽（2.75–16.54）。这一信息应作为“次要终点报告规范”分支的一部分，而不是只在 N7 提功效。 | 在 N7 分支补充卒中事件绝对数（83 例）对模型稳定性的限制。 |
| M2: **遗漏了“结局为自报医生诊断”这一关键限定** | 原文 outcome ascertainment 明确指出结局为 self-reported physician diagnoses，存在 misclassification。AI-A 的 tree 完全没有提到这一点。这一限定对“多终点处理”的解读有重要影响——复合 CVD 的组分并集依赖自报，可能高估或低估真实事件。 | 在 N1 或 Provisional Answer 中加入“结局为自报医生诊断，未采用医学记录/注册数据”的限定。 |
| M3: **遗漏了对时间函数（线性/三次多项式）敏感性分析的多重比较问题** | 原文敏感性分析(8)用替代时间函数重建轨迹；但该敏感性分析的结果（HR 4.88/4.94）是否经过 BH 校正不可知。AI-A 的 N8/N6 都没有包含这一层。 | 在 N6 分支中加入敏感性分析(8)的校正不确定性。 |
| M4: **遗漏了区间删失（interval censoring）问题** | 原文明确说事件在波次之间报告，数据本质上区间删失；补 log-log 是敏感性分析(7)。这对“多终点/多暴露”问题没有直接影响，但对 Cox HR 的解释（是否偏倚）有关。AI-A 的 tree 没有这一分支。 | 加入“区间删失”作为次要解释限定。若用户后续使用类似数据，应避免把 HR 当精确事件时间。 |

## 6. Required Fixes

1. **必须修改 N5 与 U1 的表述**：将“BH-FDR 用于轨迹组间多重比较校正”改为“原文在 Fig 5 注中声明所有关联经 BH 后仍存活，但 FDR 族是否含 Model 1–3/S5/S6/交互检验，原文未明确说明”。N5 的“高置信度”应降为“低/中”。
2. **必须修改 N2 的推理类型**：将“并集聚合掩盖组分异质性”从“claim”改为“AI-A inference”，并补充原文对卒中不显著的解释是 limited statistical power（65.2%/81.3%），而非并集聚合本身。
3. **必须修改 N7 的“因果过度”属性说明**：明确 post-hoc power 解释的循环性（用观察到的 HR 计算功效），并标注这是作者策略而非充分统计补偿。
4. **必须加入 M1、M2 两个分支**：卒中事件绝对数（83 例）与结局 self-reported 属性，二者直接影响对多终点结果的解读。
5. **必须将“72 个 HR”明确标注为 AI-A 估计值**，避免与原文混淆。
6. **必须校正 E4 的证据位置与内容**：原文 Statistical analyses 部分只有一句话 “Benjamini–Hochberg… across trajectory groups”，没有更细说明。AI-A 应以此为限，不要过度解读。
7. **必须调整 tree 结构**：N2→N3 的 edge 应删除或重定向至 N5/N7；N3 应从 N0 直接分支。