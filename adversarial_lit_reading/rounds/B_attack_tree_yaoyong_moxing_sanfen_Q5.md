<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-09T16:39:26 | request_id=msg_b2e31bbd-8a14-40e3-9a66-44e0f8ff29f5 | usage={"input_tokens": 12279, "output_tokens": 2848, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=5559 -->
# AI-B Tree Attack

paper_id: yaoyong_moxing_sanfen
question_id: Q5
review_target: @rounds/A_tree_round1_yaoyong_moxing_sanfen_Q5.md
source_file: adversarial_lit_reading/chunks/yaoyong_moxing_sanfen.md

## 1. Attack Summary

总体判断：**部分可信，需重大修改**

主要问题：
1. **节点N8（插补vs排除矛盾）属于对原文Fig.3 caption的过度解读**——原文说的是"针对亚组内加权后平衡未达标的子集改用多重插补Cox回归"，这是**亚组层面的方法切换**，并非与主队列排除缺失"矛盾"。AI-A将其升格为"方法误读/矛盾"，混淆了主分析（IPW完整病例）与亚组敏感性分析（多重插补Cox）的逻辑层次。

2. **节点N3（IPW调整Cox隐含PH假设）证据定位不完整**——原文Table 1和图3均同时报告了加权模型结果，但AI-A只引用了E2（Results部分），遗漏了图3 caption中明确说明的"未达标子集改用仅含协变量调整的Cox回归"这一信息，导致对"哪种模型真正隐含PH"的表述不准确。

3. **节点N7（未报告PH检验等）label为limitation但风险标注为"证据不足"自相矛盾**——如果原文确实未报告诊断检验，这应该是有据可依的"遗漏"而非"证据不足"；同时，AI-A未区分"PH检验在IPW-Cox中是否仍需常规报告"这一方法学争议。

4. **因果过度辩护**——节点N1将"IPW因果调整依赖可忽略性"的因果假设框架强加于原文，但原文Methods只是说"To control for confounding"，并未明确宣称"因果推断"或"可忽略性假设"。AI-A的解读超越了原文声称。

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| N1-A | N1 | "核心因果识别依赖强可忽略性+PS正确指定+IPW有效" | 原文只说"To control for confounding"（Page 3 Statistical analysis），未使用"因果识别""可忽略性"等语言。AI-A将效仿框架强加于原文可能过度。但作为"评估研究者隐含假设"的审阅点有其价值。 | 部分支持（原文未明说） | 改为"IPW调整隐含'控制已测混杂变量后治疗分配近似随机'的假设（即条件可交换性），但原文未明确陈述该假设" | 中 |
| N3-A | N3 | "加权KM/log-rank与加权Cox；隐含PH" | 原文明说"IPW-adjusted Cox proportional hazards models"（Page 3），PH假设确实是Cox模型本身的数学假设，但AI-A未引用图3 caption中"未达标子集改用不含IPW权重的multivariable Cox"这一信息。 | 部分支持（PH是Cox的数学性质，但原文未报告PH检验） | 调整为"主分析使用IPW调整Cox（隐含PH），部分未平衡亚组改用不含权重的多变量Cox"；并区分"假设使然"与"假设被检验" | 中 |
| N4-A | N4 | "主路径排除缺失基线=完整病例" | 原文明确说"patients who had missing values on baseline characteristics"被排除（Page 2 Methods Study cohort）。但N4同时被用于推导N8（插补矛盾），这属于跨层链错误的起点。 | 支持（原文明确排除缺失） | 保留N4为"主分析完整病例"，但删除其与N8的"矛盾"关联（改为"亚组敏感性分析的方法切换"） | 低（N4本身），高（作为N8的上游节点） |
| N7-A | N7 | "未报告PH/重叠/极端权重/logit线性检验" | 原文确实未报告这些诊断，但需注意：(1) 无佐证检验在IPW-Cox中也实属常见；(2) 报告空白≠假设无效，只能说不确定；(3) AI-A将其与E7绑定——E7是"全文Methods未描述"的检索结论，"全文未描述"是合理的，但"证据不足"的风险标签混淆了"原文未报告"与"我的推论无证据"。 | 支持（原文确实未报告） | 修改risk_tag为"可确认的遗漏"；将limitation表述改为"原文未报告PH检验与权重诊断，读者无法确认这些前提是否成立" | 低 |
| N8-A | N8 | "uncertainty: imputed datasets与完整病例排除矛盾" | 这是对Fig.3 caption的误读。原文说"Post-weighting balance was not achieved in [某些亚组]...therefore, multivariable Cox regression based on imputed datasets was instead applied"（Page 6 Fig.3 caption）。意思是**在特定亚组内先检查IPW平衡；平衡未达标再改用多重插补Cox**——这是分析策略的明确递进，不是"矛盾"。 | 部分支持（原文确实提到imputed datasets），但解读错误（不构成矛盾） | 改为"N8（保留）：Fig.3 caption表明部分亚组因IPW平衡未达标而改用多重插补Cox——但未说明插补模型的细节（MAR假设、迭代次数、变量集）。属方法细节缺失，非矛盾。" | 高 |
| N9-A | N9 | "非survey加权设计；IPW为处理权重非抽样权重" | 原文Study cohort称"NCDB is a hospital-based cancer registry"（Page 2），非基于抽样的调查设计。IPW用于控制confounding（Page 3）。AI-A的区分正确，但需注意：NCDB有自身的数据提交结构（非概率抽样），IPW不能校正NCDB医院选择偏差——原文limitation部分也承认。 | 支持 | 补充："NCDB自愿提交结构引入选择偏差，IPW无法校正（原文limitations已承认）" | 低 |

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E-A1 | N4 → N8（"if"） | 链路错误。N8被标注为"if"分支，暗示"当存在插补时→矛盾"。但原文描述的是亚组内方法的后备策略（fallback），是**方法切换**而非**方法冲突**。此边将方法正确性议题错误建模为逻辑矛盾。 | 删除"if"边，将N8重新定位为"N4的亚组分叉"（child of N4），并修正节点属性为"method detail missing" | 高 |
| E-A2 | N0 → N4（"leads_to"） | 根节点Q5直接连向N4（缺失处理）没有歧义，但因N4→N8链路误建，导致该边也被污染——N4被错误地当成"N8矛盾"的一端。 | 保留N0→N4，但明确N4范围为主分析（IPW路径），N8为亚组例外。在最终答案中分开表述"主分析缺失策略"与"亚组敏感性分析缺失策略" | 中 |
| E-A3 | N1 → N7（"limitation"） | N7是"未报告检验"遗漏，是全文层面的限制，不是N1这个"因果假设"节点的限制。因果假设（N1）本身不是"假设"陈述，而是"假设结构"；真正相关的是"原文未检验的假设"（PH、重叠等）。关系链N1→N7把两类不同性质的问题（"需要检验未检验"vs"因果模型成立与否"）混在一起。 | 改为N0 → N7（全文层面），或与N3关联（Cox模型的PH假设），去掉N1→N7 | 中 |

## 4. Evidence Problems

1. **E4（Fig.3 caption）的证据使用错误**：AI-A引用图3 caption的文字作为"N8矛盾"的证据（E4），但该caption描述的是"亚组内IPW平衡失败→改用Cox回归"的流程，非"主分析与亚组矛盾"。证据与推论不匹配。

2. **E7的定位模糊**：E7被用于支持N7（"未报告PH/重叠/极端权重"），但E7的原文依据是"全文Methods未描述"。空文本证据本质上是一种负向证据——需要更严谨的表述（"经全文检索未发现……"），而不是把它当作普通证据条目引用。

3. **Table 1的"Weighted2"列**：AI-A未利用Table 1中加权后SMD<0.1的**实证**平衡验证信息，这对"假设是否满足"的问题非常关键。加权后SMD的实证结果比"原文未报告检验"更具解答力。AI-A的Evidence Map中缺少对Table 1和Figure S1的引用。

4. **IPW权重的具体计算方法未交代**：原文说"IPW using estimated PS"（Page 3），但AI-A未指出原文没有说明**权重是否截尾/稳定化**——这是IPW实际应用中的关键参数细节。

## 5. Missing Branches

1. **IPW权重稳定性/截尾问题**：原文未说明权重是否截尾、是否使用稳定化权重、极端权重分布如何。AI-A在U3提到了"极端IPW权重是否截尾"，但未将其纳入树节点——应作为方法节点或限制节点加进去。

2. **删失类型与独立删失假设**：OS分析依赖"删失与事件独立"的假设（非信息删失），AI-A未提及。随访中位60.8个月（IQR 44.3-81.2）暗示一定比例的删失，但树未覆盖。

3. **NCDB选择偏差——IPW的局限**：N9说"IPW为处理权重非抽样权重"正确，但AI-A未进一步指出**NCDB医院自愿提交结构引入的选择偏差不能用IPW校正**——原文limitations也承认了这一点。应在N9节点补充该推论。

4. **亚组再平衡的具体条件**：原文说"to ensure all the relevant baseline characteristics were rebalanced within each subgroup"（Page 3），但未说明亚组内SMD的再检验标准和是否重新估计PS。AI-A的N5未细分这些细节。

5. **Sensitivity analysis用的是"nine selected risk factors"**——但主分析用了11个混杂因子（Table 1），敏感性分析只用了9个（Page 5），AI-A未注意到这个差异。用9因子Cox做敏感性分析，与主分析11因子的IPW不完全对应——需要解释差异。

6. **STEPP分析的复合风险模型**：原文明确了STEPP复合风险由6个参数构造（Page 3），但未提供具体模型系数（Supplementary Table S1）。AI-A提到了STEPP（N5），但未讨论复合风险模型本身的假设（Cox模型用于定义风险分数）。

## 6. Required Fixes

1. **（高）重写N8节点**：从"uncertainty/矛盾"改为"method detail missing"，聚焦于"Fig.3 caption提及的多重插补方法细节未展开（插补模型、次数、MAR假设）"，取消与N4的"矛盾"关系标记。

2. **（高）修正N4→N8的边**：将"if"边改为普通分支，说明是"亚组内部的敏感性分析方法切换"（fallback strategy），而非主分析冲突。

3. **（中）重写N3节点属性**：区分"主分析使用IPW调整Cox PH"与"图3中未平衡亚组改用不含IPW权重的multivariable Cox（基于插补数据）"——两种模型的PH假设内涵相同，但**加权处理不同**，CIE-A将其混合表述导致不精确。

4. **（中）重构N1节点语言**：从"核心因果识别依赖强可忽略性"改为"IPW方法隐含'在控制已测混杂后治疗分配近似随机'的假设"，后者更贴近原文的实际表述。

5. **（中）新增节点（N10）**：Sensitivity analysis使用了**9个**而非**11个**协变量调整因子——需说明与主分析11因子IPW的差异，并在假设评估中讨论。

6. **（低）新增节点（N11）**：NCDB数据来源为医院自愿提交注册——IPW只能平衡已测基线特征，无法校正NCDB入组选择偏差（原文limitations已承认）。

7. **（中）重映射E4**：将E4从"N8矛盾"证据改为"N8（亚组方法切换）"证据，避免因果推断链误导。