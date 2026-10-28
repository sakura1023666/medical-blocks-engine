<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-19T11:22:24 | request_id=msg_d25eb22d-0873-468a-bf50-5e2cf93e0307 | usage={"input_tokens": 23637, "output_tokens": 3108, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=6376 -->
# AI-B Tree Attack

paper_id: paper_004
question_id: Q5
review_target: @rounds/A_tree_round1_paper_004_Q5.md
source_file: adversarial_lit_reading/chunks/paper_004_ewas_new.md；补充统计要点（docx 抽取）

---

## 1. Attack Summary

**总体判断：部分可信，需要重大修改**

**主要问题：**

1. **N3 节点将「不加权」推广到全部 ExWAS**，但原文明确 `all associations were assessed` 且只有最后一段说明 ExWAS 不加权——**节点定位模糊，缺少 ExWAS 与 WQS/ERS 之间的边界说明**。
2. **N9 节点称「logit 线性未逐暴露检验」**，这一判断属于 AI-A 自己的推断——原文没有明确说「未检验」，只能说是「未报告」；**建议降级为 uncertainty**，而非结论。
3. **N7 节点将 WQS 归入「加权框架」**，但原文只说 ExWAS 不加权，未明确 WQS 是否加权；需要区分「加权 logistic」和「WQS 是否加权」两个子问题。
4. **E6 将 ERS 关联说成「加权 logistic」，但未区分 Model 1（未调整）和 Model 2（调整后）是否为同一种加权方式**——Model 1 未调整是否仍用权重？原文未说明。
5. **E8 对「本文不是生存模型」的说明属于方法定位，不是证据**——应将其放入 `uncertainty` 或改为对假设适用范围的说明，而非 node claim。

**证据引用主要问题：**
- E4/E5 引用 `Supp Missing` 但标记 `exact location` 不明确——「补充材料」多大段落？需要 page/table 级别定位。
- E2 把「为避免过调整」说成「与过调整有关」，但原文理由是 `maintain methodological consistency` + `avoid potential over-adjustment`——**两个理由并存，不能只取其一**。
- E6 的 `WQS q=4 B=1000` 与原文一致，但 `B=1000` 是 WQS 内部 bootstrap，不是插补种子；E5/E6 混用「bootstrap」概念需区分。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A-N1 | N1 | 「哪些步骤用抽样设计？」 | 问题节点过于宽泛；需明确 ExWAS 与描述/回归/中介之间的边界。 | 原文 Methods 2.5 首句「All analyses accounted for... unless otherwise specified」 + 末段 ExWAS 不加权。 | 拆分为：「描述/回归/中介是否加权？」「ExWAS 与 WQS 是否加权？」 | 中 |
| A-N2 | N2 | 「描述/RCS/亚组/中介用 wtsa2yr+strata+PSU」 | 原文对这四个分析是否**全部**加权未逐一确认；只说了「unless otherwise specified」，未点名 RCS/亚组。 | 原文「This applied to descriptive statistics, RCS, subgroup analyses, and mediation」——但「applied」不一定等于「全部加权」，可能是「若加权则用这些变量」。 | 改为「原文声明复杂抽样设计适用于描述、RCS、亚组、中介；但未逐一说明每个函数是否使用 `svyglm`」 | 中 |
| A-N3 | N3 | 「ExWAS 明确不加权」 | 原文说不加权**是为了**「maintain consistency + avoid over-adjustment」——AI-A 只提了后者；且「不加权」只针对 ExWAS 的独立回归，不适用于 WQS/ERS 的 logistic。 | 原文「Within the ExWAS framework... we reported unweighted results... to maintain methodological consistency... and to avoid potential over-adjustment bias」 | 修正为「ExWAS 独立回归不加权，理由包含一致性和避免过调整；WQS/ERS 的 logistic 是否加权需另查」 | **高** |
| A-N4 | N4 | 「LOD 与缺失率规则先于变换」 | 原文顺序是「LOD 处理 → 二分/对数变换 → 进入回归」，与 AI-A 一致；但 N4 只写「规则」，未确认是否在 ExWAS 还是所有暴露层面。 | 原文 Methods 2.3 + 补充：73 个毒物，16 二分、57 对数；ExWAS 与 ERS 输入应为同一预处理后的暴露。 | 无修改必要，但需在后续 follow-up 说明该规则是全部分析的前提。 | 低 |
| A-N5 | N5 | 「mice m=5, iter=5, PMM/logreg」 | 与补充一致。但「PMM 连续、logreg 二分类」是 AI-A 对 mice 默认的建议，原文可能只写了方法名——需区分。 | 补充材料「mice: m=5，迭代5，PMM/logreg」——AI-B 未见到明确的「连续变量用 PMM」字句。 | 改为「原文说明用 mice，m=5、迭代5、PMM/logreg；变量类型对应的具体方法未逐一说明」 | 中 |
| A-N6 | N6 | 「随机种子 123456 与 2024」 | 与补充一致。但 AI-A 不用讨论种子的「意义」，只需确认可复现性。 | 补充：「插补 set.seed(123456)；bootstrap set.seed(2024)」。 | 保持。 | 低 |
| A-N7 | N7 | 「ERS 关联与混合物步骤在加权或 WQS 框架」 | **问题**：原文只说 ERS–结局用加权 logistic，WQS 是补充分析，未明确 WQS 是否加权。 | 原文「The association between ERS and periodontitis was evaluated using weighted logistic regression」 + 「WQS ... setting quantiles=4, B=1000」。 | 拆分为：「ERS–结局：加权 logistic」；「WQS：是否加权未明确说明，需复查补充材料」 | **高** |
| A-N8 | N8 | 「中介依赖顺序可忽略（sequential ignorability）」 | 与补充一致。但顺序可忽略在横断面设计中**不可能成立**——AI-A 只说是「limitation」，未明确这是**不可检验的假设**。 | 补充：mediation 包默认假设 sequential ignorability；原文承认探索性。 | 升级为「不可检验的假设」；在 Provisional Answer 中说明不满足时的解释力度。 | 中 |
| A-N9 | N9 | 「logit 线性除 ERS 的 RCS 外未逐暴露检验」 | **问题**：原文没有「未检验」的说法，只说 ExWAS 用 logistic；AI-A 的「未逐毒物检验」属于**自行推断**。 | 原文 3.5 只对 ERS 做了 RCS；未提到对其他暴露做线性检验。 | 将 N9 移入 `uncertainty`：「未报告对每个毒物的 logit 线性检验」 | **高** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| A-E1 | N1 → N2：「if 非 ExWAS：加权」 | N1 的问题「哪些步骤用抽样」按「是否 ExWAS」分叉，但原文只有一个「unless otherwise specified」例外；ExWAS 之外是否全部加权，原文未逐一步确认（如 RCS 是否用 svy 版本）。 | 将分裂改为：「所有分析默认加权，除非另有说明；ExWAS 是不加权的例外；WQS 是否加权需复查」 | **高** |
| A-E2 | N1 → N3：「if ExWAS：不加权」 | 边来自 N1 的判断「是否 ExWAS」→ 合理，但 N1 的问题定义不够精确，需确认「ExWAS」指独立回归模型，而非包含 ExWAS 的整个工作流。 | 将边标签改为「if ExWAS 独立回归：不加权」 | 中 |
| A-E3 | N2 → N7：加权 logistic + WQS | 这条边把 N2（描述/RCS/亚组/中介加权）与 N7（ERS/WQS）连接**没有明确证据**——原文未说明 ERS 的 logistic 是否沿用描述性统计的权重；WQS 的权重使用也不明确。 | 拆分：N2 → 「ERS 关联」（加权 logistic）→ WQS（权重未明确）；加注「需复查补充材料」。 | **高** |
| A-E4 | N5 → N6：supported_by 种子 | 种子只能证明「可复现性」，不能「支持」插补方法本身；边类型应为「evidence_for_reproducibility」。 | 改为「N5 → N6：evidence_for_reproducibility」 | 低 |
| A-E5 | N7 → N9：limitation 关系 | N9 属于「未报告」，不是 N7（加权/混合物）直接导致的 limitation——逻辑上是从 N7 的分析类型推断出的假设盲区，不应作为 arrow。 | 将 N9 改为独立 uncertainty 节点，不从此边连接。 | 中 |

---

## 4. Evidence Problems

| problem_id | evidence_id | problem | suggested fix |
|---|---|---|---|
| P-EP1 | E1 | 「描述统计加权」与 Table 1 的 P 值来源**不能等同**——Table 1 使用 survey 设计检验还是未加权卡方？原文没写。 | 加注「Table 1 的 P 值是否基于权重检验未明确」；放入 uncertainty。 |
| P-EP2 | E2 | 「ExWAS 不加权」引用的理由是「避免过调整」，但原文有两个理由：一致性 + 过调整。 | 改为「两个理由并存，不能只取其一」。 |
| P-EP3 | E4 | 「PMM/logreg」是方法名，但 AI-A 将其推广为「连续 PMM、二分类 logreg」——原文可能只列了这两种方法名，未绑定变量类型。 | 改为「原文列方法为 PMM/logreg；未说明变量与方法的对应」。 |
| P-EP4 | E6 | 「ERS 关联加权」但 Model 1（未调整）和 Model 2（调整）是否用同一权重？原文 Model 1 未写加权。 | 成为 follow-up：Model 1 的未调整是否仍加权重？ |
| P-EP5 | E8 | 「本文非 Cox，故无 PH 假设」属于**方法对比**，不是论文证据；且原文也未做 Box-Tidwell 等其他线性检验说明。 | 从 evidence map 中删除或降级为「说明性注释」。 |

---

## 5. Missing Branches

| branch_id | missing_branch | why it matters | suggested new node |
|---|---|---|---|
| M-1 | **WQS 的权重使用不明** | ExWAS 不加权，但 WQS 是否加权未说明；WQS 作为混合暴露验证，权重影响结果代表性。 | N10：「WQS 是否使用权重未在正文说明，需复查补充材料」 |
| M-2 | **ERS 构建时的权重处理** | 弹性网（`gcdnet`）是否在加权框架下运行？原文只说了 ERS–结局加权，未说 ERS 构建时是否用权重。 | N11：「弹性网变量选择是否加权未报告」 |
| M-3 | **多套插补的合并规则（Rubin vs 单套）** | 5 套插补如何合并系数？原文未写 `pool` 规则。 | N12：「插补结果的合并方式未说明」 |
| M-4 | **LOD 二分类后缺失是否仍参与插补** | 二分变量（未检出=0）是否被视为「缺失」并插补？还是视为真实 0？ | N13：「LOD 二分后是否仍视为缺失，原文未明确」 |
| M-5 | **未纳入插补模型的辅助变量** | mice 插补是否只用暴露变量，还是包含结局与协变量？这在 ERS 与 ExWAS 间可影响偏倚。 | N14：「插补模型包含哪些变量未报告」 |
| M-6 | **灵敏度分析限制** | 3.7 的「unimputed sensitivity」是「同一套模型不含插补数据」还是「只用完整数据」？AI-A 未提及。 | N15：「unimputed sensitivity 定义需确认」 |

---

## 6. Required Fixes

1. **修正 N3**：ExWAS 不加权 → 补充原文两个理由（一致性 + 避免过调整），并明确「不加权」仅针对 ExWAS 独立回归。
2. **拆开 N7**：加权 logistic（ERS–结局）与 WQS（权重不明）分开；补充分析 WQS 是否加权。
3. **N9 降级为 uncertainty**：原文未报告逐暴露线性检验 →「未报告」而非「未检验」。
4. **E1 加注**：Table 1 的 P 值检验方式未明确；描述统计加权 ≠ Table 1 P 值加权检验。
5. **E4 避免「PMM/logreg」过度推广**：精确到原文字句。
6. **E5 将种子边改为 reproducibility 类型**；N9 改为独立 uncertainty 节点。
7. **增加 follow-up branch M1–M6 为 B 级分支**：WQS 权重、ERS 构建是否加权、插补合并规则、LOD 二分后缺失定义、插补模型变量、unimputed sensitivity 定义。

---

**AI-B signed.**