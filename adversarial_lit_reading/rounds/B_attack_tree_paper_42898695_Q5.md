<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-11-12T14:51:04 | request_id=msg_281b47eb-a0c3-4f66-ad37-3c013c529de5 | usage={"input_tokens": 19698, "output_tokens": 4296, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 768, "prompt_tokens_details": {"cached_tokens": 768}} | char_len=8210 -->
# AI-B Tree Attack

paper_id: paper_42898695
question_id: Q5
review_target: @rounds/A_tree_round1_paper_42898695_Q5.md
source_file: adversarial_lit_reading/chunks/paper_42898695_t2dm_mimic_eicu.md

## 1. Attack Summary

**总体判断：部分可信（需要重大修改）**

**主要问题：**

1. **N4 节点证据错误**：AI-A 声称「次要终点在部分敏感性下失去显著性」指的是 ALP，但 E4 证据标为 `Results 3.2`，实际 ALP 信号在 Results 3.2 与 Discussion 中均有详细描述。更严重的是，N4 将「ALP 对备选规格不稳健」等同于「备选失败」，但原文的 IPOW 敏感性下 ALP 点估计更大（+0.035），只是置信区间更宽——这可能是精度损失而非效应消失，AI-A 未区分这两种情况。

2. **N15 / N16 证据链断裂**：AI-A 将「日分母骤降」作为 N15（基线 MI 未明确）的 `supported_by` 证据，但日分母骤降是关于**轨迹观测缺失**的证据，而 N15 讨论的是**基线协变量缺失**——两者是不同的缺失机制，不应互相支持。这是边攻击中的典型「证据错位」。

3. **N1 缺少关键限定**：AI-A 称「轨迹推断依赖 LMM 与条件 MAR」，但原文明确指出 LMM 是主模型，且作者同时给出了 IPOW、≥3次测量、存活出院、截断至 day4 等**四类**非 MAR 备选。AI-A 的 N1 没有提及「主分析」的限定词，也没有说明 MAR 假设是**条件于模型协变量与患者既往观测**的——这正是 MAR 与 MNAR 较量的关键细节，缺少会导致读者误判原文的假设强度。

4. **N9 因果攻击不完整**：AI-A 将 eGFR/SOFA 标记为「可能介导/对撞」且 `risk_tag = 因果过度`，但原文对此的讨论分两层：(a) 可能是 post-baseline covariate 导致 overadjustment；(b) 可能是 collider。AI-A 只提到「对撞」，未提及「过调整」这一同样重要的机制，且没有说明原文**承认**这一张力并给出敏感性分析——AI-A 的措辞让读者以为这是 AI-A 的批判而非作者的自我披露。

5. **N11/N12 缺少 Cox 比例风险假设的定位**：AI-A 在 N11-N12 中讨论了条件 logistic/GEE，但没有明确回答 Q5 中的「Cox PH」假设部分。原文确实提到了 Cox 分析（90天生存，仅 MIMIC-IV），但 AI-A 没有把「Cox 仅单库」与 PH 假设检验缺失联系起来。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A1 | N1 | 「轨迹推断依赖 LMM 与条件 MAR」 | 缺少「主分析」限定词；缺少「条件于模型协变量与患者既往观测」的关键细节；MAR 不可检验的性质应在此节点即说明 | Section 2.5: "Mixed-effects models use all available observations and give valid inference under a missing-at-random assumption conditional on the modelled covariates and each patient's observed prior measurements" | 改为：「主分析依赖随机截距 LMM，其有效推断需条件 MAR（条件于模型协变量与既往观测）；作者明确此假设不可检验且不大可能精确成立」 | 中 |
| A2 | N4 | 「次要终点在部分敏感性下失去显著性」 | 将 ALP 在 IPOW 下的表现简单化为「失去显著性」，但原文 IPOW 下点估计为 +0.035（比主分析更大），仅因精度降低导致 CI 跨越 0。这与「无效应」截然不同 | Section 3.2: "Under inverse-probability-of-observation weighting the ALP point estimate was larger (+0.035) but less precise (95% CI −0.015 to +0.085; p = 0.166)" | 改为：「ALP 信号在 IPOW 下点估计更大但精度下降而失去显著性；在存活出院、截断 day4、随机斜率、非参数 day 项下消失；在≥3 测量、log 变换、DR 调整下保留」 | 高 |
| A3 | N7 | 「PS 匹配隐含治疗可换性与卡钳可比」 | 缺少「库内匹配」的限定——原文明确「Matching was within source because severity scoring is not comparable across datasets」，这是 PS 可换性假设的关键前提，AI-A 未提及 | Section 2.4: "Matching was within source because severity scoring is not comparable across datasets" | 改为：「PS 匹配隐含**库内**治疗可换性与卡钳内可比；匹配在源库内进行，因严重度评分跨库不可比」 | 中 |
| A4 | N14 | 「原文未使用调查加权复杂抽样；本问 NHANES 专项不适用」 | AI-A 将「原文未使用」直接等价于「不适用」。但 Q5 问的是「该分析依赖哪些假设」，应该回答「原文是 convenience sample 的 pooled dataset，无复杂抽样设计，因此**不需要**也**未进行**加权；但 pooling 隐含了跨库可合并性」——N14 的结论方向正确，但论证缺少「pooling 隐含的可合并性假设」这一前提 | 无直接原文证据；A14 基于全文 Methods 的方法学合理性推断 | 改为：「原文为三库方便样本池化，无调查权重/PSU/分层设计，NHANES 式加权不适用；但 pooling 隐含跨库可合并性（用随机效应+leave-one-out 检验）」 | 低 |
| A5 | N15 | 「未见基线协变量多重插补步骤；轨迹靠 LMM+MAR」 | ① N15 表述为「轨迹靠 LMM+MAR」，但 N1 已说此，重复；② 缺少对「原文报告的缺失比例」的量化——日分母从 day1 的 ~57% 骤降至 day7 的 ~10%，这种缺失严重度应量化呈现而非笼统说「大幅下降」；③ 没有区分基线协变量缺失与轨迹观测缺失 | Section 2.5 + Results 3.2: "the number of patients contributing an ALP measurement fell from 60 (57.1%) on day 1 to 11 (10.5%) on day 7" | 改为：「未见基线协变量 MI；轨迹层缺失严重（day7 仅 10.5% 贡献 ALP），主模型依赖条件 MAR；作者给出四类备选并报告 IPOW/幸存者/截断分析结果」 | 中 |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| B1 | N3 → N4 `supported_by` | N4 用「次要终点不稳健」来「支持」N3 的备选方案。但 N3 列举的是原文**预先设定的备选策略**，而 N4 描述的是这些备选在 ALP 上的表现——这不是「支持」关系，而是「检验结果」。严格地说，N4 是「备选方案的结果评估」，当结果不理想时应该表达为「N3 提出的备选未能挽救 ALP 信号」，而非「支持 N3」。 | 将边改为 `leads_to` 或 `evaluates`；N4 改写为「备选敏感性下 ALP 不稳定，点估计变大但精度降」 | 高 |
| B2 | N15 → N16 `supported_by` | N16 的「日分母骤降」是**轨迹观测**缺失证据，N15 讨论的是**基线协变量** MI——两者缺失机制不同，N16 不能「支持」N15。N16 应该支持 N1 的 MAR 假设风险，或作为独立证据节点连接 N3。 | 将 N16 改连至 N3（支撑缺失敏感性分析的必要性），或直接标记 N16 为 N1 的补充证据；N15 缺乏直接原文证据，应标注「需复查原文」 | 中 |
| B3 | N0 → N13 `leads_to` | N0 到 N13 的边没有说明 N13 回答的是「跨库可合并性」假设，而非「参数假设」。Q5 包括「复杂抽样加权」，N13 对异质性的检验应明确回答「pooling 是否站得住」以及「在什么条件下不成立」。 | 在 N13 前增加一个说明节点：「跨库可合并性：原文以随机效应+I²+leave-one-out 检验，但库数仅 3，I²/Q 解释力有限」 | 低 |
| B4 | N0 → N7 `leads_to` | N7 的 PS 匹配假设与 N9（eGFR/SOFA 测量时点问题）之间存在明显的逻辑依赖，但 AI-A 将 N9 作为 N7 的 `limitation`，遗漏了「测量时点问题是 PS 模型**变量选择**的假设」这一层——N9 不是 N7 的附带限制，而是直接威胁 N7 的「可换性」前提。 | 将 N9 从 `limitation` 提升为 N7 的 `threatens` 边，或单独分支出 N9 的因果链 | 中 |

---

## 4. Evidence Problems

| evidence_id | problem_type | description | suggested_fix |
|---|---|---|---|
| E4 | 证据位置不精确 | E4 标为 Section 2.4 + 4.1，但 SMD 平衡结果的量化数据（SMD 阈值与失衡协变量列表）在 Results 3.1 与 Table 1；Discussion 4.1 是又一次讨论。三处证据各自独立，不应合为一条 | 拆为 E4a（Methods 匹配设计）、E4b（Results 平衡数据）、E4c（Discussion 局限） |
| E6 | 证据位置完全错误 | E6 标为 Section 2.5 + 3.3，但「全调整 20 协变量完全分离」在 Results 3.3；「探索性」结论在 Discussion 4.1 与 Conclusion。若 AI-A 的 `supported_by` 指向 E6 以支撑 N12，应分离「设计」（2.5）与「结果」（3.3）两类证据 | 将 E6 拆分为设计证据（匹配集条件 logistic/GEE）与结果证据（完全分离/单库 Cox） |
| E7 | 过度引用 | E7 标为 Section 2.5 + 3.2，但 DerSimonian–Laird、I²、Q 的**方法描述**在 2.5，「leave-one-out 依赖 MIMIC-IV」的具体结果在 3.2。AI-A 将方法与结果合并引用可能造成「方法存在即结果有效」的错觉 | 拆分为方法（2.5）与结果（3.2：leave-one-out 显示依赖 MIMIC-IV；I² 很小但库数有限） |
| E10 | 表述不精确 | E10 称「双侧 p/q<0.05」，原文明确「Two-sided p < 0.05, or q < 0.05, was considered significant」；但 BH 家族仅限两分析物（总胆红素+ALP），其他轨迹与死亡为探索性。AI-A 的「BH 限两分析物族」已正确，但未说明**这一选择本身是作者预先制定而非从数据推断**——若用户课题需要复现，这一区分很关键 | 在 N17 补注：「BH 家族限两分析物（胆红素+ALP），全轨迹 BH 敏感性在补充材料」 |
| E11 | 位置含糊 | E11 标为 Results 3.2–3.3 / Fig.2–3，但「胆红素交互多规格稳健接近无效」仅在 3.2，「ALP 脆弱」同样仅在 3.2；Fig.2 是轨迹图、Fig.3 是 KM 图，不能作为这两条叙述的完整证据。若 `used_by_node` 指向 N4 与 N12，应精确标注小节而非泛泛标页码 | 拆分为 E11a（3.2 主结局鲁棒性）与 E11b（3.2–3.3 ALP 与死亡） |

---

## 5. Missing Branches

| branch_id | missing_branch | description | why_important | suggested_fix |
|---|---|---|---|---|
| M1 | **Cox PH 假设检验缺失** | Q5 明确问「Cox PH」，但 AI-A 的树没有专门节点讨论 Cox 模型中 PH 假设是否检验。原文只报告了 MIMIC-IV 单库 90 天 Cox HR 1.36（p=0.394，Section 3.3），未提及 Schoenfeld 残差检验 | Q5 直接问及此项，且 AI-A 在 Provisional Answer 第4条一笔带过「Cox 非主分析」但没有给出「PH 假设未检验」的结论 | 新增节点 N18：「Cox 模型用于 90 天生存（MIMIC-IV 单库），原文未报告 PH 假设检验；该分析为探索性且样本小（n=140, 事件数低）」 |
| M2 | **簇内相关/分层聚类假设** | AI-A 在 N13 讨论跨库异质性，但未提及**同一医院内不同患者可能相关的聚类结构**（如 MIMIC-IV 包含多年多科室；eICU 跨越 200+ 医院，但作者未使用医院固定/随机效应）。原文用 source database 作为协变量，但未对医院层聚类做任何调整 | 若用户课题为多中心 EHR 研究，医院层聚类是必须考虑的方差校正问题 | 在 N13 的修订中补注：「原文仅以 source database 为协变量，未对医院层聚类做校正；三库的医院层结构差异巨大（eICU 200+ 医院 vs MIMIC 单院区），是否需 GEE/混合模型处理医院聚类未讨论」 |
| M3 | **倾向模型的过拟合/稀疏性** | Q5 是「参数假设」，PS 模型的**参数假设**包括 logit 线性、无交互、无高阶项。AI-A 只在 N7 提到「5 个协变量、可换性」，未提及 PS 模型的线性假设和 5 变量限制（受 116 暴露患者限制）的后果 | PS 模型的 logit 线性假设是 Q5 同类问题，且 5 个变量的限制直接影响可换性假设的实现 | 在 N7 修订中补注：「PS 模型仅含 5 变量（受暴露样本量 116 限制），隐含 logit 线性与无交互假设；未被匹配的潜在混杂（磺脲类、白蛋白等）进入 DR 调整，但 PS 模型本身的设定限制未被检验」 |
| M4 | **小样本/事件数对渐近假设的威胁** | AI-A 的 U1 在不确定性列表中已提及，但未在树中作为节点呈现。作者自己也承认完全分离（62 事件 vs 20 协变量），说明渐近假设明显不成立 | 这是 Q5 要直接回答的「参数假设是否满足」的核心内容 | 将 U1 提升为正式节点 N19：「小样本渐近：62 死亡事件 vs 20 协变量已致完全分离；条件 logistic/GEE 的小样本性质未讨论」 |
| M5 | **多重插补与 FCS/联合模型的缺失** | AI-A 在 N15 提到「未见基线 MI」，但没有指出原文对基线协变量缺失的处理方式到底是什么——是完整案例分析、可用案例分析、还是未报告？（原文未明确说明，需复查原文。）同时，`day-1 值`作为协变量在 outcome model 中出现，天然带有缺失，作者如何处理未说明 | 用户课题若涉及纵向 EHR 数据，缺失处理是方法复现的关键 | 在 N15 修订中明确：「原文未报告基线协变量缺失数量或处理方式（可用案例分析？完整案例分析？），需复查原始数据/代码；`day-1 值`协变量缺失的处理方式未说明」 |

---

## 6. Required Fixes

**高优先级（必须修改）：**

1. **修正 N4 的表述**：将「次要终点在部分敏感性下失去显著性」改为「ALP 在 IPOW 下点估计更大但精度下降；在存活出院、截断 day4、随机斜率、非参数 day 项下消失；在 ≥3 测量、log 变换、DR 调整下保留」。N4 不能作为 N3 的 `supported_by`，应为 `evaluates`。否则读者会误以为作者的四类备选方法「失败」，而实际 IPOW 下效应仍在（仅精度降）。

2. **修正 N15/N16 的边连接**：N16（日分母骤降）不能 `supported_by` N15（基线 MI），两者缺失机制不同。N16 应连接 N1（支撑 MAR 假设风险）或 N3（支撑敏感性分析必要性）。

3. **新增 N18（Cox PH 假设）**：Q5 明确问及 Cox PH，AI-A 的树无此节点，属于明显遗漏。需补：「Cox 仅 MIMIC-IV 单库（n=140），原文未报告 PH 假设检验，为探索性分析」。

4. **限定 N1 的表述**：N1 必须改为「主分析依赖随机截距 LMM，其推断有效性需条件 MAR（条件于模型协变量与既往观测）」，并同时说明「作者已声明此假设不可检验且不大可能精确成立」。

**中优先级（应该修改）：**

5. **N7 补充「库内匹配」限定**：PS 可换性是**库内**假设（因跨库评分不可比），AI-A 缺失此细节是实质性改动。

6. **N9 补充「过调整」机制**：原文讨论 eGFR/SOFA 有 both overadjustment and collider 两层；AI-A 只提「对撞」是漏了一半。应改为「双重威胁：过调整（post-baseline 测量）与对撞（条件于中间变量）」。

7. **拆分 E4/E6/E7/E11 证据**：每条证据目前位置含糊或以偏概全，需精确到小节或拆分为方法/结果两条独立证据。

**低优先级（可以修改）：**

8. **N14 论证补齐**：明确「pooling 隐含可合并性假设，用随机效应+leave-one-out 检验」的推理链。

9. **新增 M2（医院聚类）提示**：原文未处理医院层聚类，多中心复现时应注意。

10. **N17 补注**：BH 家族为作者**预先选定**（胆红素+ALP）而非数据驱动，全轨迹 BH 仅为补充材料的敏感性。