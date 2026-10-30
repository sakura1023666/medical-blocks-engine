<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-30T15:39:32 | request_id=msg_fb182118-297a-462b-bdec-17309630f27e | usage={"input_tokens": 24862, "output_tokens": 3590, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=7755 -->
# AI-B Tree Attack

paper_id: paper_013
question_id: Q6
review_target: @rounds/A_tree_round1_paper_013_Q6.md
source_file: adversarial_lit_reading/chunks/paper_013_joint_traj_tyg_cvd_elsa.md

## 1. Attack Summary

总体判断：**需要重大修改**

主要问题：

1. **关键事实错误**：AI-A 的 N2 声称「9 项敏感性分析全部支持主结论」，但文中明确说明第 9 项敏感性（cross-classified median-split）结果 HR 仅 3.48/3.62，且该分析本质上回答的是「基线分类是否与轨迹分类一致」，并非「方向与量级一致」的敏感性检验——与其余 8 项敏感性分析性质不同，但 AI-A 将其混入「全部方向与量级一致（HR 4.62–5.52）」的论断。
2. **证据遗漏**：AI-A 完全遗漏了文中明确讨论的一个与用户研究直接相关的点——作者在 Discussion 中承认「轨迹可能主要反映不同的基线风险层，而非有意义的纵向演变」（Page 16 L757–767）。这一条对「追踪轨迹方法是否比基线单测更好」至关重要，却未出现在决策树任何节点中。
3. **逻辑跳跃**：E5/E6 的 C-index 比较属于「两法头对头比较」，却被 AI-A 放在「内部验证/判别力」节点——而这两者意义不同（头对头等价性 ≠ 判别力有效性）。
4. **严重程度最高的 N5 表述**：「无 bootstrap/CV 内部验证」是对的，但将其与「无外部验证队列」并列处理时过于简略——作者明确说需「develop and external validation of prospective prediction algorithms」（L730–733），这一自我限定意见未被映射到决策树。

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A1 | N2 | 「9 项敏感性全部支持主结论：…最高组 HR 4.62–5.52」 | 第 9 项敏感性（median-split cross-classified）是**完全不同的分析类型**（验证分类学一致性），其 HR 为 3.48/3.62，并未落在 4.62–5.52 范围。且交叉分类比较的是「基线中位分组」与「轨迹分组」的一致性，并非检验主分析结论对假设变化的稳健性。将两者混为一谈夸大了敏感性检验的覆盖范围。 | 原文 L570–581：「cross-classified analyses based on median-split BMI×TyG and WHtR×TyG categories…supporting the concordance between the trajectory-based and categorical approaches」——确实为「一致性检验」而非「敏感性检验」 | 将第 9 项敏感性从「敏感性分析」改为「分类学替代一致性分析」，并单独评估其意义 | **高** |
| A2 | N3 | 「区分度仅 C-index(0.66)=判别中等」 | AI-A 将 C-index 的比较（ΔC=0.003）置于「判别力有效性」语境下，但该比较是**两法头对头等价性检验**（研究目的 3），并非「判别力充分性」检验。此外，文中 C-index 0.663 是针对「模型区分度」报告，但**未报告基准模型（如仅年龄/性别模型）的 C-index**——缺少「增量判别力」证据。AI-A 未指出这一关键缺口。 | 原文 L713–719：C-statistics「0.663 vs 0.660, P=0.723」用于比较两法；全文无基准模型 C-index | 将「头对头比较」与「判别力评估」分成两个独立节点，并补充「无基准模型对比」作为缺失证据 | **高** |
| A3 | N6 | 「log-rank+BH-FDR 内部一致」 | N6 的证据强度被高估。log-rank 检验只是「组间差异显著性」检验——组间有差异≠关联方向正确≠轨迹分组有效。BH-FDR 只是多重比较校正，不增加「有效性」证据。AI-A 将这两者列为「内部一致性证据」过强。 | 原文 L628–630：log-rank P<0.001 仅说明组间累计发生率差异有统计学意义；L648–649：BH-FDR 用于多重比较校正 | 降级为「组间差异初步证据」，不作为验证有效性的核心论据；与 C-index 等区分度指标分开评估 | **中** |
| A4 | N4 | 「post-hoc power（卒中 65.2%/81.3%）量化次终点阴性」 | 文中明确说卒中「only the highest-risk groups reached statistical significance」（L649–650），中间组 HR 1.81/2.06 非显著。post-hoc power 引用的 65.2%/81.3% 恰好对应这两个非显著组。但 N4 未指出「power <80% 意味着该检验不足以排除有意义的效应」——AI-A 只做了「事实陈述」，未做「推论」。 | 原文 L649–653：stroke「consistent with limited statistical power for this endpoint (65.2% and 81.3%, respectively)」 | 补充「80% 以下 power 不足以宣称阴性结论」的限定语；并删除「量化」一词（power 用观察效应量反算，本身有循环论证嫌疑） | **中** |
| A5 | E5 | 「无 bootstrap/CV 内部验证」 | AI-A 表述准确，但遗漏了 C-index 95%CI 的来源标注问题（AI-A 自己在 U1 中提到，但没有在节点表中反映）。更重要的是——**作者明确声明「trajectory membership can only be determined retrospectively after repeated measurements over several years」**（L730–731），即预测算法尚未开发，这是「有效性」问题的一部分，不应仅归入「迁移性」。 | 原文 L730–733：轨迹归属需多次测量后回顾确定 → 临床前瞻应用不可用 | 在 N5 中补充「轨迹归属只能事后确定 → 前瞻预测算法未建立」作为第二项关键缺口 | **高** |
| A6 | N1 | 「纳入 vs 排除全基线对比+结局率对比」 | AI-A 将此作为「L1 证据金字塔顶层」是**权重大小判断问题**。纳入 vs 排除对比只是**描述性证据（D 级）**，不是设计层面的排除偏倚控制（如使用逆概率加权）。将描述性对比置于 9 敏感性、判别力等分析性证据之上，层级安排有误。 | 原文 L617–621：SMD 对比仅是「suggesting that missingness was not substantially associated with the primary outcome」——结论本身即限定词较多 | 将 N1 的「L1 证据金字塔」降级为「基线诊断性证据」，不置于证据层级顶部；顶部应放置判别力+敏感性 | **中** |

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| A7 | N1 → N2 | N1（选择偏倚对比）→ N2（9 敏感性）之间无推断关系——选择偏倚问题与敏感性分析是两个独立防御线，不能因为「选择偏倚证据强」就推断「敏感性分析应该被信任」。需在边标注 `parallel` 而非 `support`。 | 明确标注 N1 与 N2 为并行支路而非序贯推导 | **低** |
| A8 | N2 → N3 | AI-A 将 N2（敏感性支持）作为 N3（判别力）的前提条件，但敏感性分析与判别力验证是不同维度的有效性证据（前者检验关联稳健性，后者检验预测效用）。当前边结构造成「敏感性分析全过→判别力合理」的错误暗示。 | 将 N2 与 N3 改为并列关系（共同指向 N4 的综合评估），而非序贯链条 | **中** |
| A9 | N3 → N5 | N3（判别力缺陷）→ N5（验证缺口）的推理：从「C-index 不高且无校准」推导出「需要外部验证」可行，但遗漏了作者自己提出的时间属性问题——轨迹归属需事后确定，使得每一步「验证」对临床前瞻应用都无效。此漏洞使 N5 不完整。 | 在 N5 中补充「轨迹归属事后性」作为验证的前提障碍 | **高** |
| A10 | N5 → N6 | N5（缺口）→ N6（post-hoc power）的边方向：应将 N6 作为 N5 缺口的一个具体例子，而非独立后续节点。当前结构中两者因果链关系松散，且 N6 本身是「伪证据」，不太应作为树的输出节点。 | 将 N6 合并入 N5 作为「不可作为验证的证据」子项；或单独作为「伪验证」警示节点 | **中** |

## 4. Evidence Problems

1. **E1 的「选择偏倚方向性证据」标签**：Supp Table 1 中包括 vs 排除率的多次比较存在多个 SMD >0.1 的变量（饮酒 94.6% vs 91.9%、高血压 29.0% vs 34.4%、关节炎 29.8% vs 33.3%），AI-A 的 evidence_summary 仅聚焦「结局率几乎全等」这一条。这不算错误，但将「结局相关性」（CVD 发生率相同）等同于「选择机制近 MCAR」是过度简化——SMD 在**非结局**变量上的组间差异仍然存在，选择偏倚方向性更准确地说是「与结局无关但与其他因素相关」。

2. **「最高组 HR 4.62–5.52」的混淆**：文中实际报告的是「highest-risk group retaining HRs ranging from 4.62 to 5.52 for composite CVD across both approaches」（L683–685），但这是**敏感性分析中最高组的 HR 范围**，不是 9 项敏感性各自的独立结果范围。AI-A 在 Node Table 中写成「9 敏感性全支持、方向量级不变 → 最高组 HR 4.62–5.52」，有将「综合范围」误读为「各项结果」的风险。

3. **NRI/IDI 无效应表达不完整**：文中明确「NRI and IDI comparisons also yielded no statistically significant differences between the two approaches for any endpoint (all P>0.8)」（L722–724）——**P>0.8 表示差异极不显著**，这是「两法等价」的证据，但也可能反映检验功效不足。AI-A 未对此作出双面解读。

4. **缺失：轨迹稳定性对有效性的影响**：作者自己承认「the identified trajectories remained relatively stable across waves, suggesting that the groups may primarily reflect different baseline risk strata rather than meaningful longitudinal evolution」（L755–758）。AI-A 未在决策树任何节点或 Uncertainty 中反映这一关键坦诚声明——这直接关系 Q6 的「分析有效性」评判。如果轨迹只是「基线风险的再包装」，那么「纵向轨迹方法优于基线单测」的结论就被削弱了。

## 5. Missing Branches

| missing_branch_id | missing branch claim | why it matters | source evidence | suggested addition |
|---|---|---|---|---|
| M1 | 轨迹稳定性 → 「轨迹≈基线分层」风险 | 若轨迹组反映的是基线差异化而非动态演变，则 Q6 的「纵向方法优于单测」结论被根本性削弱 | L755–758「trajectories remained relatively stable…groups may primarily reflect different baseline risk strata rather than meaningful longitudinal evolution」 | 新增节点：N4b「轨迹稳定性 → 有效性存疑」，并在 Provisional Answer 中补充「轨迹可能仅反映基线分层」的让步 |
| M2 | 外部验证的可行性障碍（轨迹归属事后性） | 作者说「trajectory membership can only be determined retrospectively after repeated measurements over several years」——这不仅是「没有外部验证」的限制，而且是「即使做了外部验证，对前瞻应用也无意义」的结构性障碍 | L730–733 | 在 N5 中新增子节点：外部验证缺失不仅是「还没做」，而是「作者自己承认前瞻预测算法未建立」 |
| M3 | 卒中分析事件数过少 → 多数亚组不可估 | 文中 L662「Stroke-specific subgroup analyses were limited by small event numbers in several strata, with many estimates non-estimable」——这是「分析有效性」的关键限制，AI-A 仅以「post-hoc power」一带而过 | L662–663 | 新增「卒中亚组分析不可估」条目到 Missing Branches 或 Node N4 |
| M4 | 结局自我报告 → 结局误分类风险 | 文中 L743「CVD outcomes were ascertained through self-reported physician diagnoses rather than adjudicated medical records or registry linkage, which may lead to outcome misclassification」——未见 AI-A 决策树提及 | L743–745 | 在 N5「验证缺口」中新增结局确定方式限制条目 |
| M5 | 非因果性声明 | 作者在 Limitations 明确「associations reported should be interpreted as predictive rather than causal」（L767–768），AI-A 的 N5 未涵盖「因果性限制」，只覆盖「方法验证缺口」 | L767–768 | 在 N5 或新节点声明「关联非因果」 |
| M6 | 年龄相关肌少症偏倚 | 作者专门讨论 BMI 在 >65 岁人群的肌少症混入问题（L570–573 附近），此事影响 BMI+TyG 轨迹的**有效性解读**。缺失此分支使 BMI 轨迹组的结果可能被误读。 | L567–574 | 新增分支：BMI+TyG 轨迹组的肌少症偏倚风险 |

## 6. Required Fixes

### 高优先级

1. **[N2/高]** 修正「9 项敏感性」表述——第 9 项（median-split cross-classified）不是敏感性分析，是与主分析「分类学一致性」检验，其 HR 为 3.48/3.62（不在 4.62–5.52 范围）。将 E2 拆分为「8 项敏感性」+「1 项分类学一致性验证」。

2. **[N3/高]** 区分「C-index 头对头比较」（E3）与「判别力充分性评估」——前者比较两法差异，后者需与基准模型比较。AI-A 将两者混淆为同一概念，且未报告「无基准模型对比」这一关键缺口。

3. **[N5/高]** 补充「轨迹归属只能事后确定 → 前瞻预测算法未建立」（L730–733）——这是外部验证无法兑现的**结构性障碍**，应作为 N5 的核心内容而非仅为「可迁移性不足」。同时补充「结局为自我报告 → 误分类风险」和「观察性研究 → 效应为预测性非因果性」两条限制。

4. **[新增 M1/高]** 新增「轨迹稳定性 → 可能仅反映基线分层」节点（L755–758）。这是作者对自身方法学局限的明确承认，且直接关系到「纵向轨迹是否优于基线单测」的 Q6 核心判断。

### 中优先级

5. **[A4/中]** N4 限定「post-hoc power 用观察效应量反算」的循环论证缺陷，并说明 power <80% 不能排除有意义的效应存在。

6. **[A2/中]** 将 N6 从「内部一致性证据」降级为「组间差异初步证据」，删除「内部验证」含义，避免与真正的内部验证（bootstrap/CV）混淆。

7. **[结构性修改/中]** 调整决策树拓扑：N1（选择偏倚）与 N2（敏感性）应为并行支路；N4（post-hoc power）应从树主体拆出，改为「伪验证」警示节点。

### 低优先级

8. **[低]** N2 → N3 边标注为不重要/删除，明确二者为并列证据维度。

9. **[低]** E1 的 evidence_summary 补充非结局变量的 SMD 差异，不要只引用结局率。