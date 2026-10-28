<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-10T15:45:15 | request_id=msg_60d49d49-0f5f-45ae-98a4-7d970dfcc403 | usage={"input_tokens": 12179, "output_tokens": 3726, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=7800 -->
# AI-B Tree Attack

paper_id: paper_025
question_id: Q4
question: 变量/协变量筛选与建模逻辑？入模依据？模型形式？是否预先确定？
review_target: @rounds/A_tree_round1_paper_025_Q4.md
source_file: MOESM1 Feature Selection + paper_025 main text

## 1. Attack Summary

总体判断：**部分可信（需重大修改）**

主要问题：
1. **N3（药暴露捷径）与 Q4 核心问题关联薄弱**。AI-A 将 Discussion 中的「shortcut learning」讨论作为 limitation 分支纳入 Q4 决策树，但该内容主要论证**单一来源训练→泛化失败**的训练策略问题，而非变量筛选逻辑本身。作为 limitation 分支可以保留，但需明确其定位是「后验讨论」而非「变量入模依据」。
2. **N2 断言「无传统协变量筛选管道」证据不足**。MOESM1 只描述了「demographic and time series variables...were included」和「a selection of 17 drugs」，未明确说明 demographic/time series 变量是否经过任何筛选过程。AI-A 的断言将「未在论文中叙述筛选」等同于「未做筛选」，存在**叙事空白≠事实否定**的逻辑问题。
3. **N1「固定纳入」表述精确但需补充**。「固定」的确切含义需要澄清——是指「预先确定」还是「不随时间变化」？在 TPC/深度学习语境下，变量集是预先固定的（非逐步筛选），但模型内部会随时间更新预测。N1 未区分「变量集固定」与「模型参数更新」两个层面。
4. **N4「非协变量调整模型」表述不完整**。TPC 虽然是非加性深度学习模型，但仍有协变量调整功能（输入变量中 demographic/vitals/labs 本质上就是协变量）。N4 的表述容易造成「TPC 不做任何调整」的误解。
5. **E3 定位为 evidence 但实际是「作者假设性解释」**。原文用 "It is plausible that..." 引导，属于推测性讨论而非实证结论，证据权重应降级。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| NA-01 | N1 | 「入模=固定临床变量集」 | 表述精确但「固定」含义模糊。原文明说「Demographic and time series variables in the BlendedICU dataset (version v0.3.2) were included, along with a selection of 17 drugs」。「固定」应理解为「预先确定/非逐步筛选」，而非「变量值不更新」。需明确区分「变量集固定」vs「模型预测随时间更新」 | MOESM1 Feature Selection 段支持变量集预先确定；但未区分变量集固定与模型动态更新 | 改写为：「入模变量集预先确定（BlendedICU v0.3.2 的人口学+时间序列+17药），非逐步筛选管道；模型内部权重经训练学习，预测随时间动态更新」 | 中 |
| NA-02 | N2 | 「无传统协变量筛选管道叙述」 | 1) 「无叙述」≠「未执行」，存在叙事空白（reporting gap）与事实否定（factual negation）的逻辑混淆；2) MOESM1 只描述了「a selection of 17 drugs」但未说明 selection 的具体标准；3) 原文未明确说「没有做 UV/VIF/LASSO」，只说没有叙述这些步骤。N2 需降置信度 | MOESM1 确无 LASSO/逐步/VIF 叙述；但未明确否定这些方法曾被使用 | 改为：「原文未报告 UV/VIF/LASSO/逐步等传统筛选步骤；17药的选择依据需对照 BlendedICU 配置或补充材料；demographic/time series 变量是否为全集未明确说明」 | 高 |
| NA-03 | N3 | 「药暴露可成站点捷径」 | 1) 原文原文："It is plausible that the model learned to rely on site-specific patterns, such as local prescribing protocols or unit-type distributions, as proxies for RLoS trajectories" — 明确标注为 plausible 推测，非实证结论；2) 该讨论针对 AmsterdamUMC 单源训练的泛化失败，是训练策略层面的后验讨论，与 Q4 的变量筛选逻辑关联有限；3) 作为 limitation 分支可保留，但需降低证据等级 | 原文用 "It is plausible that..."（推测性），非确定性陈述；且 Table 1 的药暴露差异是观察性数据，不能直接支持「模型确实利用了捷径」 | 保留为 limitation，但标注为「作者推测」，并注明其与 Q4 变量的关联是间接的 | 中 |
| NA-04 | N4 | 「DL多任务而非调整回归」 | 1) 「非调整回归」表述易误解——TPC 虽然不是 Cox/logistic 回归，但输入变量中 demographic/vitals/labs 本质上是协变量，模型进行了隐式调整；2) 更准确的说法是「非加性参数化协变量调整模型」；3) 需补充 TPC 的输入处理方式以说明「协变量如何被纳入」 | 原文确认 TPC 架构及多任务（mortality + RLoS）联合预测；但未说明「非调整」— TPC 接收协变量输入并隐式建模非线性关系 | 改为：「模型为 TPC 多任务深度学习架构（非 Cox/logistic 加性协变量模型），demographic/vitals/labs/药暴露作为输入特征，经非线性变换隐式调整」 | 中 |
| NA-05 | N1+ | 「含17药」 | 「17药」的筛选依据未说明。原文 "a selection of 17 drugs" 中的 selection 具体标准（频次阈值？临床相关性？统计筛选？）不明确。AI-A 在 Uncertainty 中已标注，但 N1 的 high 置信度可能误导读者认为 17 药的选择逻辑已完全清楚 | MOESM1 仅说 "a selection of 17 drugs"，无具体标准说明 | 在 N1 备注中注明：「17药的具体选择标准未在论文中说明，需对照 BlendedICU 配置」 | 低 |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| EA-01 | N0→N1 | 从「变量逻辑」到「特征清单固定纳入」直接结论，但 AI-A 没有从原文中区分「哪些变量来自 BlendedICU 全集」「哪些是子集选择」。MOESM1 原文结构为「Demographic and time series variables in the BlendedICU dataset (version v0.3.2) were included, along with a selection of 17 drugs」，说明 demographic/time series 是**全集纳入**（未筛选），drug 是**选择纳入**（有筛选）。N1 未区分这两种不同的纳入逻辑 | 拆分 N1 为两个子节点：N1a「demographic+time series=BlendedICU 全集纳入」；N1b「drug=17种选择纳入（选择标准未说明）」 | 高 |
| EA-02 | N0→N2 | 从「变量逻辑」到「无传统筛选管道叙述」的推理有问题。AI-A 的 N2 是**对整个变量筛选管道**的否定断言，但实际证据只支持「MOESM1 未叙述这些步骤」。原文没有报告 = 可能执行但未报告，或未执行。N0→N2 的边需要从「变量逻辑」补充限定：该断言的适用范围是「论文文本证据」而非「实际研究过程」 | 将 N2 改为「论文未叙述传统 UV/VIF/LASSO 管道；实际执行情况无法从论文确认」；或将 N2 从 claim 降级为 observation | 高 |
| EA-03 | N0→N3 | 从「变量逻辑」到 limitation 的跳跃。N3 的「药暴露捷径」是模型训练后的**后验讨论**，不是变量筛选阶段的设计逻辑。如果 Q4 问的是「入模依据」，N3 回答的是「入模后的风险」，两者之间存在时序与逻辑断层 | 保留 N3 为 limitation 分支，但添加标注：「该讨论基于模型训练后的表现推测，不构成变量入模依据」 | 中 |
| EA-04 | N1→N4 | 从「变量固定纳入」到「模型=TPC多任务」的边缺失中介推理。N1 描述输入侧，N4 描述模型架构，但缺少「为什么 TPC 选择这些输入」以及「这些输入如何被 TPC 处理」的桥接 | 在 N1→N4 之间补充说明：TPC 接收静态（demographic）+动态（时间序列）输入，17药作为时间序列的一部分输入；变量集与模型架构的关系需明确 | 中 |

---

## 4. Evidence Problems

| problem_id | issue | evidence | location | severity |
|---|---|---|---|---|
| EP-01 | **证据强度不匹配**：E1（MOESM1 Feature Selection）支持 N1 的「17药选择」部分，但 MOESM1 明确说 "a selection of 17 drugs"，selection 的标准未说明。E1 只能支持「预先确定」中的「预先」，不能支持「依据明确」 | AI-A 声称 E1「固定纳入人口学+生命体征+实验室+17药+GCS/尿量」 | MOESM1 Feature Selection 段 | 中 |
| EP-02 | **过度引用 Discussion 推测**：E3（Results/Disc）作为 N3 的证据，但原文是推测性语言（"It is plausible that..."），证据等级应为 conjectural 而非 empirical。AI-A 将其标记为 E3 且 N3 置信度为 medium，但 medium 对推测性内容仍偏高 | 原文第 8 页 Discussion：「It is plausible that the model learned to rely on site-specific patterns...」 | paper_025 Page 8, Discussion | 高 |
| EP-03 | **叙事空白≠实证否定**：E2（Methods）「无LASSO/逐步/VIF叙述」被 AI-A 用来支持 N2「无传统协变量筛选管道叙述」。但「Methods 未叙述」是 reporting observation，不等于「研究未执行」。AI-A 的 E2 证据标注「特征来自BlendedICU v0.3.2」实际上支持的是变量来源，而非「无筛选管道」 | MOESM1 原文只说变量 included + 17 drugs selection，没说「没有做筛选」 | MOESM1 Feature Selection 段 | 高 |
| EP-04 | **变量集描述不完整**：AI-A 的 E1 提到「GCS/尿量」，但 MOESM1 Feature Selection 段的原文只说 "Demographic and time series variables in the BlendedICU dataset (version v0.3.2) were included, along with a selection of 17 drugs"。GCS/尿量 是否属于 BlendedICU 时间序列变量未单独列出确认 | 需对照 BlendedICU v0.3.2 的变量清单确认 GCS/尿量 是否为该版本时间序列变量 | MOESM1 Feature Selection 段 + BlendedICU 文档 | 低 |

---

## 5. Missing Branches

| missing_id | missing branch | reason | severity |
|---|---|---|---|
| MB-01 | **变量来源分层**：应区分「BlendedICU 全集纳入」（demographic + time series）vs「子集选择」（17 drugs）vs「排除变量」（diagnoses）三种情况。AI-A 只覆盖了「17药选择」和「无筛选管道」，没有描述 diagnoses 被排除的理由（"not consistently available across all four databases"） | Q4 问「变量筛选与建模逻辑」，diagnoses 的排除理由也是变量逻辑的一部分；MOESM1 明确说了排除原因 | 中 |
| MB-02 | **17药选择标准的分支**：MOESM1 只说 "a selection of 17 drugs"，未说标准。AI-A 在 Uncertainty 中标记了，但决策树中缺少「17药如何从 >100 药中选出的分支」。可能的候选标准：频次阈值、临床相关性、跨库一致性——均未在论文中说明 | 这是 Q4 最核心的「入模依据」问题之一，AI-A 未在树中给出明确分支 | 高 |
| MB-03 | **药暴露变量的编码方式分支**：原文将药暴露作为时间序列变量处理，但药暴露的编码（是否按时点标记？cumulative？binary exposure？）未说明。药暴露在不同数据库的测量频率差异可能巨大，这涉及变量定义一致性 | 这与 N3（药暴露捷径）直接相关；如果药暴露编码方式本身存在跨库差异，捷径风险可能部分源于编码而非临床差异 | 中 |
| MB-04 | **「预先确定」的确认路径**：Q4 问「是否预先确定」。AI-A 通过「MOESM1 未叙述筛选管道」推断「预先确定」，但缺少直接确认路径（如原文明确说「变量集预先设定」或「在实验前固定」）。需补充「TRIPOD+AI 报告规范」的说明——TRIPOD+AI 要求在论文中报告变量选择方法，若未报告可能违反报告规范 | 这涉及方法论质量评估，对 Q4 的回答完整性有影响 | 低 |
| MB-05 | **GCS/尿量的来源确认分支**：AI-A 的 E1 提到「GCS/尿量」，但 MOESM1 未单独列举。需确认这两个变量是否确实在 BlendedICU v0.3.2 的 42 个时间序列变量中 | 防止 AI-A 自行补充变量清单之外的内容 | 低 |

---

## 6. Required Fixes

### 必须修改（高严重度）

1. **修正 N2（无传统筛选管道）的断言强度**。将「原文未做传统 UV/VIF/LASSO」改为「论文文本未报告传统筛选步骤（UV/VIF/LASSO/逐步），实际执行情况无法从论文确认」。明确 E2 支持的是「未报告」而非「未执行」。降 N2 置信度至 medium。

2. **拆分 N1 为两个子节点**，区分「全集纳入」（demographic + time series）与「选择纳入」（17 drugs）。「全集纳入」是预确定的，「选择纳入」的具体标准未说明。分别设置置信度。

3. **修正 N3 的证据性质**。将「药暴露端口捷径」标注为「作者推测（"It is plausible that..."），非实证结论」，并将 E3 升级为需要标注证据等级的条目。如需保留为 limitation 分支，需在前置说明中注明这是后验推测。

4. **增加 MB-01（变量来源分层）与 MB-02（17药选择标准）分支**。Q4 的核心关注点是「入模依据」，缺失病名排除理由和17药选择依据将导致回答不完整。

### 需要改写（中严重度）

5. **修正 N4 表述**。改为「模型为 TPC 多任务深度学习架构，demographic/vitals/labs/药暴露作为输入特征经非线性变换隐式调整，非 Cox/logistic 加性协变量模型」。补充「隐式调整」以准确反映 TPC 的变量处理方式。

6. **修正 N1「固定」的表述**。区分「变量集预先确定」与「模型参数动态更新」。原文 TPC 是 hourly 更新的动态预测模型，「固定」仅指变量集不变。

7. **在 MOESM1 与 paper 主文本的证据关联上补充交叉验证**。目前 AI-A 的 E1-E4 分别来自 MOESM1 和主文本，但未交叉验证 MOESM1 声称的变量列表与实际 Table 1 中展示的变量是否一致。

### 优化建议（低严重度）

8. **补充变量清单的版本标注**。MOESM1 明确说 "BlendedICU dataset (version v0.3.2)"，建议在树中标注版本号，便于后续 Q8 复现时核对 keep=62 清单是否对应 v0.3.2。

9. **将 N3 的关联性标注在边 EA-03 上**。明确 N3 与 Q4 核心问题（变量入模逻辑）是间接关联（训练策略的后验讨论），可保留为 limitation 上下文但不宜作为核心回答。

10. **添加「TRIPOD+AI 报告规范」的说明分支**。如果该研究遵循 TRIPOD+AI（论文明确声称），则应报告变量选择方法——未报告可能反映方法学缺口，这有助于回答「是否预先确定」时区分「规范要求」与「实际执行」。