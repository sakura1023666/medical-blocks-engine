<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-10T15:43:19 | request_id=msg_07667c7d-d7c8-46a1-ad83-774a77d6590e | usage={"input_tokens": 12342, "output_tokens": 3706, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=7477 -->
# AI-B Tree Attack

paper_id: paper_025
question_id: Q2
review_target: @rounds/A_tree_round1_paper_025_Q2.md
source_file: chunks/paper_025_allyn_2026_blended_los_pooling.md + MOESM1/2

## 1. Attack Summary

总体判断：**部分可信 / 需要重大修改**

主要问题：

1. **N1 存在概念模糊**：AI-A 将「加权联合损失」等同于「不是复合终点聚合」，但原文 MOESM1 明确指出 RLoS 预测是**条件于存活的独立第二步**，损失函数也是**条件性加权**（只在存活时计入 RLoS 项）。这不是简单的「联合多任务」，而是**两阶段级联设计**，与 N2 的表述有细微但重要的差别。
2. **N2 的损失函数表述不精确**：AI-A 写 `L=BCE+α·MAPE`，但原文是 `L=BCE+α·MSLE`（Mean Squared Logarithmic Error），不是 MAPE。**MAPE 是评估指标，不是损失函数**。这是关键的方法混淆——AI-A 把评估指标当成了训练损失。
3. **N4 的自洽性问题**：AI-A 引用 `E3`（原文说 AUROC/MAPE 是主指标），但 Mcomposite 的归一化基线和置信区间计算方式在原文表 3 有明确说明（bootstrap 1000 次），AI-A 未将其与不确定性列表关联。
4. **N5 的表述过于绝对**：原文确实未报告 Bonferroni/FDR，但 AI-A 说「**原文未做多重比较校正**」是事实陈述还是评价？如果是评价，原文可能采用了整体性策略（比较 CI 重叠），这不算「未校正」而是「用 CI 替代假设检验」——需要更谨慎的措辞。

**严重程度**：N2 需要紧急修正（高），N1 需要精度补充（中），N4/N5 需要限定条件（中）。

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A1 | N1 | 双终点联合训练，不是把终点合成单一临床复合终点 | 部分正确但表述模糊。「联合训练」不等于「两阶段级联」——原文是**条件性两阶段**：先预测死亡，再在存活条件下预测 RLoS。AI-A 的「联合训练」表述未区分「多任务并行」与「条件级联」，可能误导读者以为两个任务是并列的 | 原文 MOESM1：「RLoS prediction assumed that the patient was discharged alive. Accordingly, a two-step process was chosen. First, the model predicts the probability of patient mortality... and then the model predicts time-to-discharge assuming survival」 | 改为：「双终点采用**条件级联**设计：死亡预测与 RLoS 预测不在同一层面并行，RLoS 条件于存活」 | **高** |
| A2 | N2 | L=BCE+α·MAPE，α=20 | **方法和表述双重错误**：① 原文损失是 `BCE + α·MSLE`（Mean Squared Logarithmic Error），不是 MAPE；② α=20 的权重是用于 MSLE 而非 MAPE；③ 更重要的是，**损失是条件性的**——只有存活患者的 RLoS 项才计入损失（通过 indicator 掩码） | 原文 MOESM1：「The loss function (L) is therefore a weighted sum of the binary cross-entropy of mortality prediction and the mean squared logarithmic error of the RLoS prediction, applied conditionally」；公式与 α=20 同在原文 | 改为：「L = BCE + α·MSLE，α=20，且**条件性计算**（仅在存活患者上计入 RLoS 损失项）」 | **高** |
| A3 | N3 | 死亡者 RLoS 评估排除 | 基本正确，但表述省略了「训练时包含」这一重要补充。原文明确说「模型在**全队列**上训练（包括有已知死亡结局的患者）」，只是**评估时**排除。AI-A 只说了评估侧 | 原文 MOESM1：「The model is trained on the entire patient cohort, including those with a known fatal outcome. However, when evaluating performance, length-of-stay predictions are not included for patients who have died」 | 补充：「训练在全队列（含死亡者）上进行，评估时排除死亡者的 RLoS 项」 | **中** |
| A4 | N4 | Mcomposite 用于跨配置排序，主指标仍是 AUROC/MAPE | 基本正确，但需补充 Mcomposite 的计算细节——归一化到**内部验证基线**（非外部），且置信区间用 bootstrap (1000 次) 估计。考虑与 N6 共享这一信息 | 原文表 3 注：「95% CI computed by bootstrap resampling (1,000 iterations). The composite metric is used for cross-configuration ranking only」 | 补充 Mcomposite 基线/CI 说明；将与 N6 关联 | 中 |
| A5 | N5 | 原文未明确多重比较校正 | 表述过于绝对，措辞需加限定。更精确的表述是「原文**未报告**多重比较校正方法，而是通过**CI 重叠判断**配置间差异显著性」——这是「用 CI 替代假设检验」策略，不等于「未做处理」 | E4 引用合理，但 MOESM1 或许有更多信息——AI-A 未引用 MOESM1 的统计方法部分 | 改为：「原文**未报告** Bonferroni/FDR 等传统多重比较校正，而是采用 **CI 重叠 + 点估计并列表形式**进行跨配置比较」 | 中 |
| A6 | N6 | Table3 并列表+CI | 正确但缺少「CI 由 DeLong (AUROC) / bootstrap (MAPE) 估计」的方法学细节——这是判断 CI 可比较性的关键 | 原文表 2/3 注「95% CI for AUROC were computed using the DeLong method; 95% CIs for MAPE were estimated by bootstrap resampling (10,000 iterations, percentile method)」 | 添加 CI 估计方法 | 低 |
| A7 | — | — | AI-A **未覆盖「多亚型/多终点」中的「多亚型」部分**。Q2 问的是「多亚型/多终点/多层暴露」三件事，AI-A 只回答了「多终点」，对「多亚型」（如 ICU 亚型/unit type）和「多层暴露」（如药物暴露的层级处理）完全未涉及 | 原文 Table 1 有 unit type 分层；药物暴露是「是否暴露」二值而非多层暴露；患者层面无亚型分组 | 需要补充说明：「原文无临床亚型分组（subgroup）分析」「药物暴露为二值变量（有/无），无多层暴露设计」 | **高** |

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E1 | N0→N1 | N0 是「Q2 多终点如何处理」的**问题节点**，N1 是对此问题的 claim。但 AI-A 通过「不是复合终点」来回答问题，只做了**否定性回答**，没有给出**正面描述**（两阶段级联、条件训练等）。建议改为「正面描述+否定排除」的双重结构 | 让 N1 同时给出正面（条件级联设计）和否定（非单一复合临床终点）两个面向 | 中 |
| E2 | N1→N2 (supported_by E1) | N1 若改为「条件级联」，N2 的损失函数描述必须相应修正为「条件性加权损失」——否则自相矛盾：既说级联又说联合损失。AI-A 原文 N1→N2 是「方法」关系，但未反映**条件性** | 将 N2 改为「条件性加权损失 L=BCE+α·MSLE，仅存活者计入 RLoS 项」 | **高** |
| E3 | N1→N3 | 关系为「同向细化」，但 N3 是「评估排除」，N1 是「训练任务结构」——这两个是不同的层面（训练 vs 评估），AI-A 将它们连接为「方法」关系但未说明这是「训练-评估不对称」设计 | 补充「训练-评估不对称」说明：训练时 RLoS 损失条件于存活，评估时排除死亡者 | 中 |
| E4 | N0→N4 | AI-A 认为「主指标 vs 复合指标」是对 Q2 的回答，但 Q2 问的是「是否多重比较」「是否复合终点聚合」——N4 回答了复合终点问题，未完全回答多重比较问题。N5 才回答了多重比较，但 N0→N5 的边缺少问题分支 | 将 N0 分支分解为「终点关系」「评估指标」「多重比较」三个子问题 | 中 |
| E5 | N4→N5 | AI-A 未画出 N4→N5 的边，但它们在逻辑上是关联的：「主指标是 AUROC/MAPE」→ Mcomposite 仅排序 → 多重比较的必要性降低。AI-A 的树没有体现这一推理链 | 添加 N4→N5 边，标注「因此」关系 | 低 |

## 4. Evidence Problems

| attack_id | 问题描述 | 原文位置 | 证据类型 | 严重程度 |
|---|---|---|---|---|
| EP1 | **关键方法混淆：损失函数 vs 评估指标**。AI-A 写 `L=BCE+α·MAPE`，但原文是 `L=BCE+α·MSLE`（Mean Squared Logarithmic Error）。MAPE 是评估指标（Table 3 中报告），MSLE 才是训练损失。AI-A 将二者混为一谈 | MOESM1（原 supp）：「the mean squared logarithmic error of the RLoS prediction」 vs 正文 Table 3：MAPE 用于报告 | 方法误解 | **高** |
| EP2 | **证据引用不足**：AI-A 引用 MOESM1/2，但未将 MOESM1 中的关键方法学信息（损失函数细节、条件性设计、两阶段流程）充分纳入树中。N1-N3 的证据支持不充分 | MOESM1「Prediction of the ICU remaining length of stay through a two-stage process」部分 | 证据覆盖不足 | 中 |
| EP3 | **未覆盖「多亚型」**：Q2 明问「多亚型」，AI-A 的树和答案完全未提及。原文虽然没有正式亚型分析，但 Table 1 包含了 unit type 分类（Cardiac、Medical、Surgical 等），且 HiRID 无 unit type 信息——这是「亚型信息缺失」的重要背景 | Table 1 Unit Type 行：HiRID 显示「-」19,573 (100%) | 遗漏分支 | **高** |
| EP4 | **未覆盖「多层暴露」**：原文药物暴露是二值（有/无）记录（Table 1 注 3「Number of ICU stays where a drug was administered at least once」），不是多层暴露。AI-A 未回答 Q2 的这一子问题 | Table 1 图例注 3 | 遗漏回答 | 中 |

## 5. Missing Branches

| attack_id | 缺失分支 | 重要性 | 建议补充 |
|---|---|---|---|
| MB1 | **「训练-评估不对称」分支**：训练时 RLoS 损失被计入（条件于存活）+ 评估时 RLoS 排除死亡者。AI-A 的树只覆盖了「评估排除」部分 | 关键 | 增加「训练阶段条件性加权损失」分支，并标注与评估侧的差异 |
| MB2 | **多亚型（subgroup）分支**：Q2 明问「多亚型」，AI-A 未覆盖。需要说明「本文**无**预先定义的临床亚型分组分析」「unit type 存在跨库差异（HiRID 无此信息）」 | 重要 | 新增一个节点：「原文未进行亚型分层分析；Table 1 报告了 unit type 分布但未作为亚型进行模型测试」 |
| MB3 | **多层暴露分支**：Q2 问「多层暴露」，AI-A 未覆盖药物暴露的层级问题。需说明「药物暴露为二值（是否暴露），不是剂量/时效等多层暴露」 | 重要 | 补充：「药物暴露是二值变量，未进行剂量/时长等分层处理」 |
| MB4 | **RLoS 上限截断（10天）分支**：原文 MOESM1 明确「RLoS was capped to 10 days；prediction of 10 was equivalent to 'RLoS is more than 10 days'」。这影响 RLoS 回归的性质，AI-A 未提到 | 中高 | 补充：「RLoS 预测有上限截断（10天），超过者统一记为 10 天」 |
| MB5 | **多配置并行的多重比较分支**：AI-A 提到多训练配置（Table 3），但未分析这些配置间的多重比较问题——4 种训练策略 × 2 个终点 × 2 种评估集（specialization/generalization），这本身就是多重比较场景 | 重要 | 补充「多重比较的潜在风险点在配置×指标组合层面」 |
| MB6 | **CI 与假设检验的替代关系分支**：N5 说「未做多重比较校正」，但原文用 CI 重叠判断显著性——这在统计上等效于 Wald 检验的近似。建议说明「CI 重叠是**描述性**显着性判断，不等于正式的假设检验」 | 中 | 在 N5 补充「原文以 CI 重叠作为描述性判断，未报告 p 值」 |

## 6. Required Fixes

### 高严重程度（必须修复）

1. **【方法错误】N2 的损失函数修正**：将 `L=BCE+α·MAPE` 改为 `L=BCE+α·MSLE`（Mean Squared Logarithmic Error）。MAPE 是评估指标，MSLE 是训练损失——AI-A 把评估指标误当成了损失函数。这是最严重的方法学错误。

2. **【概念模糊】N1 的表述修正**：将「双终点联合训练」改为「双终点**条件级联**：先预测死亡概率，再在存活假设下预测 RLoS」。原文的设计是「两阶段」而非简单的「联合多任务并行」。请同时在 N2 上反映这一点——损失的条件性结构（指示死亡时不计入 RLoS 项）。

3. **【遗漏】添加「多亚型」分支（MB2）**：Q2 的第一子问题是「多亚型」，AI-A 完全未回答。至少需要添加一个节点说明：(a) 原文没有进行患者亚型分层分析；(b) Table 1 报告了 unit type 分布但 HiRID 无此信息；(c) 亚型差异可能影响模型迁移（如 AmsterdamUMC 的高 unit type 特异性）。

4. **【遗漏】添加「多层暴露」分支（MB3）**：说明原文药物暴露是二值（有/无）记录，未进行剂量/时长等多层处理。

### 中严重程度（需要修改）

5. **【证据补充】N3 补充训练侧信息**：在 N3 中补充「训练时在全队列（含死亡者）上进行；评估时排除死亡者的 RLoS 项」——这是「训练-评估不对称」设计。

6. **【精度修正】N5 的措辞**：将「原文未做多重比较校正」改为「原文**未报告** Bonferroni/FDR 等多重比较校正方法；采用 CI 重叠进行描述性判断」。避免将「未报告」升级为「未做」——后者是更强的判断。

7. **【补充】N4 添加 Mcomposite 细节**：说明 Mcomposite 归一化到**内部验证基线**，值 <1 表示优于基线，>1 表示劣于基线，CI 用 bootstrap (1000 次) 估计。

### 低严重程度（建议优化）

8. **【次要】N6 补充 CI 估计方法**：AUROC 用 DeLong，MAPE 用 bootstrap (10,000次, 百分位法)。

9. **【次要】MB4 补充 RLoS 上限截断**：RLoS 被截断在 10 天，>10 天的预测记为 10。这影响 MAPE 的解释。