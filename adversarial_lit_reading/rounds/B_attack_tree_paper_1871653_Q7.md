<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-11-18T14:47:17 | request_id=msg_fecf8da2-dd58-4fd8-98ef-12071ce43ba7 | usage={"input_tokens": 13475, "output_tokens": 4164, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 768, "prompt_tokens_details": {"cached_tokens": 768}} | char_len=8916 -->
# AI-B Tree Attack

paper_id: paper_1871653
question_id: Q7
review_target: @rounds/A_tree_round1_paper_1871653_Q7.md
source_file: adversarial_lit_reading/chunks/paper_1871653_fcimb_temperature_jlcm.md

## 1. Attack Summary

总体判断：**部分可信，需重大修改**

主要问题：
1. **N2 节点严重失真**：AI-A 声称“院内终点外推全因死亡受限”，但原文的是“post-discharge mortality **information is not reliably available** in the eICU-CRD”——即该选择是为了**保证队列间测量一致性**，而非 ICL 主观描述。更关键的是 **Fine-Gray 竞争风险模型的正确实现需要“出院后死亡”数据**，而原文明确承认其不可得 → 文中所述 Fine-Gray 分析的实际实施方式需要澄清，且这可能比 AI-A 所述更严重。此外，N2 说“失访控制代价”也欠准确，患者若“discharged alive before day 28”即进入竞争风险，并非失访。
2. **原文对部分局限有明确承认，但 AI-A 遗漏了“排除患者可能引入默认偏倚”中“哪些具体结论被影响”的表述区分**，且把 Discussion 中“selection is inherent to trajectory-based analyses”这一为其方法学辩护的论述，直接降格为“可能高估可分层性”的一刀切叙事，见 N3。
3. **N6**（方向性结论较稳）的置信度应为 **low** 而非 medium，因为：(i) 排除了早期死亡患者；(ii) eICU、Drum Tower、MIMIC 三类队列定义不一致；(iii) 外验仅同模型重估，不能视作独立方法学复制；且原文对 Fine-Gray 与 cause-specific 之间估计结果的差异表述需仔细审查——只有 Classes 2/3 稳健，Classes 4/5 在竞争风险模型下估计有差异。
4. **E4 证据映射失误**：把“MAP 硬分类”写进 N4 中心（亚型=统计学表型），但原文中 MAP 硬分类出现在 Methods（Baseline covariates 描述），与“潜类别解释非机制证明”是两个不同的点，不应合并到一个 node 同一个 evidence_id 下。
5. **缺失分支**：未提及变量异质性问题，如 MIMIC 使用 ICD 编码定义脓毒症、而南京 Drum Tower 用 Sepsis-3 标准，这种**定义差异**直接影响 NH 的普适性与类可复制性，AI-A 未写入。


## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| NA-01 | N2 | “院内终点 → 外推全因死亡受限” | 原文并非“限制外推全因死亡”，而是“post-discharge mortality information is not reliably available in eICU” → 这是**测量可行性**问题，不是外推方向问题。且 Fine-Gray 竞争风险模型的常规实现需要出院后死亡/全因死亡数据；原文仅用“cause-specific + discharge alive as censoring”作为主分析，Fine-Gray 作为 sensitivity 但可能仅依赖院内状态 → 现有描述需澄清 Fine-Gray 的原始实现方式。 | Methods 2.4 原文“确保跨队列一致性与最小化错分”；“post-discharge mortality not reliably available in the eICU” 被 AI-A 曲解为“外推受限”。 | 修改为：“院内终点是测量可行性决定（eICU 无出院后数据），且可能影响对全因死亡的结论强度；Fine-Gray 作为 sensitivity 的实施细节（是否使用出院后全因死亡）在原文未完全报告，需读者自行核实；因果估计的绝对效应外推受限。” | **高** |
| NA-02 | N1 | “测量异质 → 效应量可偏” | 遗漏了“measurement sites/devices/frequency across databases”具体是哪些（腋温、耳温、膀胱、直肠），且原文还提到“假性低体温/高体温可能由记录频次不同导致” → 原文对**测量异质**的表述从 Discussion 看主要是“obscure transient extremes or misclassify short-term abnormalities”，但这不等于直接推定“效应量偏倚”，应区分随机错分与信息偏倚方向。 | Discussion 段落中“heterogeneity in measurement sites, devices, and recording frequency”与“time-window aggregation may obscure transient extremes”原文有。但“效应量可偏”是 AI-A 添加的推断。 | 改为“测量异质（部位/设备/频率）可能导致**非差异性或差异性错分**，时间窗口聚合可能掩盖瞬时极值；对效应量影响方向需依赖错分类型，原文未给出方向性判断。” | **中** |
| NA-03 | N3 | “排除者死亡更高 → 可能高估可分层性” | 原文明确说“excluded patients had higher mortality and shorter ICU LOS”，且“survivorship bias + underrepresents early critical illness trajectories”——但“高估可分层性”是 AI-A 的过度解读；排除早期死亡者后对**轨迹类**的影响取决于排除者在各类的分布，可能**低估**早期高风险类（如低体温→早死人群）的效应，也可能**高估**稳定正常体温类的相对低危。不能简单的说“高估”或“低估”。另原文还说“inherent to trajectory-based analyses”，即作者认为该选择难以避免，AI-A 未体现这一“可辩护性”。 | Supplementary Table 1/2 支持排除者特征；原文明确“inherent to trajectory-based analyses”。AI-A 的推演（可分层性）无原文明示对应关系。 | 改写为“排除早期死亡/短 LOS 者 → 早期高风险轨迹可能被低估（而非高估），总体可分层性方向不确定；且这种排除对轨迹类分析是内在的，作者认为是不可避免的。” | **高** |
| NA-04 | N4 | “亚型=统计学表型非机制” | 引用 E4“MAP 硬分类”不当。MAP 硬分类属于 Baseline covariates 的操作化，不是 N4 的解释边界证据；N4 真正的原文依据在 Discussion：“suggested that normothermia may represent different underlying states, including treated fever, impaired febrile response” 与“nonlinear temperature-mortality relationship may arise from the balance between immune insufficiency…”，这才是潜类别非机制性的证据。E4 应拆分为两条独立证据（MAP 作为变量 vs. 亚型解释边界）。 | E4 中 “MAP 硬分类；潜类别解释非机制证明” 是两件事，合并为一条 evidence 是偷换概念。 | E4 拆为两条：(i) MAP 硬分类 → 用于 N1/N2 调整变量（不影响 N4）；(ii) Discussion 的 underiable states 讨论 → 用于 N4。N4 的 claim 本身正确，但证据链要梳理。 | **高** |
| NA-05 | N5 | “外验异质” | AI-A 说“单中心占比小（688/13717≈5%）” — 原文只是说 validation 合并（eICU 13029 + 南京 688），单中心小占比是 AI-A 推断，语义上多余但可保留；但要注意：**外验做法**是“用 MIMIC 模型参数对验证集做 posterior class-membership probability”，然后比较轨迹分布与风险——这不等于“重新拟合模型”，所以“外验”其实只是“模型迁移”层级的外部一致性检验，跟“独立复制发现”不同。AI-A 未对此方法学局限给出说明。 | 原文 2.5.4“Posterior class-membership probabilities were estimated using model parameters derived from the MIMIC-IV cohort” → 证实外验本质为迁移检验。 | 修改为“外验采用 MIMIC 模型参数 + 单中心小队列合并 → 对轨迹类‘存在性’外推有限，重估仅限同框架再评估；单中心占比小，南京数据对整体外验贡献有限。” | **中** |
| NA-06 | N6 | “方向性结论较稳，精确HR外推谨慎” | “较稳”缺乏限定：类 3 在两种模型（cause-specific vs Fine-Gray）下表现不一致（原文：Classes 4 and 5 estimates differed between cause-specific and Fine-Gray），所以**方向性结论只在 Classes 2/3 稳健**；PAMM 外验“Similar temporal patterns”但没有给出显著性检验；entropy 在 five-class 是下降的 → 分类质量未完全最优。因此 N6 应降低置信度。 | Results 3.5 ：“For Classes 4 and 5, the estimates differed from those of the cause-specific Cox models” 支持修改。 | N6 置信度降为 low，claim 改为“Classes 2/3 的方向性结论相对稳健；Classes 4/5 受竞争风险模型影响较大；PAMM 外验同向但无正式检验；整体方向性结论需限定在 3 类周转轨迹。” | **高** |


## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| EA-01 | N1→N2 | 把“残余混杂”与“院内终点”两个独立局限连接为主链。原文两者在 Discussion 中独立给出，无相互推导关系；N1 的混杂影响所有 HR，N2 是数据可得性限制，两节点之间不应为因果连接，应为并列关系。 | 改为 并列分支（不是 chain）。N1 与 N2 都是 L1/L2 层，不构成 N1→N2 的推导。 | **中** |
| EA-02 | N2→N3 | “院内终点”与“轨迹样本选择”无逻辑推导关系。即使是全因死亡终点，若数据库无出院后随访，N3 的选择偏倚仍然存在。两个局限是叠加的，不能视为推导关系。 | 改为“N2 与 N3 为相互作用/叠加”，若需链式写作，应标注“共同影响外推性”而不仅是单一方向。 | **中** |
| EA-03 | N3→N4 | “样本选择”到“亚型非机制”是**范畴跳跃**：前者是队列入选问题，后者是模型解释边界（统计学表型 vs. 生物机制）。二者都是局限，但无“由于入选偏倚，因此亚型非机制”的推理。 | 删除该推理边，改为并列关系，或注明“N3 与 N4 分别从人群代表性与解释层级限制结论”。 | **高** |
| EA-04 | N4→N5 | “亚型非机制”到“外验异质”也无必然推理链。亚型非机制是任何潜类别模型的固有属性，与外验队列异质是独立问题。 | 删除该边，全部改为 parallel structure。 | **高** |
| EA-05 | N5→N6 | 即使外验异质，N6 的“方向性结论较稳”并不是由“外验异质”推导出来的，而是由“多证据方向大体一致”得出的。也就是 N5→N6 是把一个缺陷直接连接到“结论稳健”的判断，逻辑上不成立（因为 N5 的存在反而削弱 N6）。 | 改为双路径：N1合N2+N3+N4→N6（均削弱），N5→N6（外验可部分正面支持）+ 补充 N5 的局限性讨论。否则当前边关系是矛盾。 | **高** |


## 4. Evidence Problems

1. **E1 把“观察性残余混杂”与“测量异质”合并为一个证据**。实际上 Discussion 中二者是分开列出的独立局限（“residual confounding and reverse causation” vs. “heterogeneity in measurement sites, devices, and recording frequency”），且对应不同的处理策略。合并会模糊“哪条证据影响哪个节点”。
2. **E2 的“失访控制代价”表述有误**。原文说“discharged alive before day 28 = competing event; post-discharge mortality not reliably available in eICU”，不是“失访”，而是“信息不可得”。用词不准确导致 N2 被误读。
3. **E4 把“MAP 硬分类”与“潜类别解释非机制”放在同一条证据**。二者无关联：MAP 硬分类是基线变量操作化，与潜类别解释边界无关。应拆分。
4. **E5 引用位置不明**：“Methods”太宽泛，应精确到 2.5.4 External validation。且“合并异质来源”的描述不完整——实际上是“heterogeneous definitions of sepsis across cohorts”，这不仅是异质性，更是定义不一致问题，直接影响轨迹的“同质性”前提。
5. **缺证据**：N4 真正需要的是 Discussion 中“normothermia may represent different underlying states, including treated fever, impaired febrile response, or recovery”这一段——AI-A 未引用；N6 需要 Results 3.5 中“Classes 4 and 5 estimates differed”才能说“方向性结论稳健”，AI-A 未引用。


## 5. Missing Branches

| attack_id | missing branch | why needed | suggested addition | severity |
|---|---|---|---|---|
| MB-01 | **Sepsis 定义异质性** | MIMIC/eICU 用 ICD-9/10 编码定义脓毒症，而 Drum Tower 用 Sepsis-3 + SOFA≥2；不同判定标准直接影响轨迹可复制性与跨队列异质性。 | 增加节点 “跨队列脓毒症定义不一致（ICD vs Sepsis-3） → 疾病表型异质性可能影响轨迹的跨队列一致性”，severity 中。 | **高** |
| MB-02 | **竞争风险模型下类 4/5 估计不稳定** | 原文明确说 Classes 4、5 在 Fine-Gray 下估计结果与 cause-specific Cox 有差异；这意味着“方向性结论”在 2/5 的类上是不稳的。AI-A 的 N6 没有体现这一点。 | 在 N6 中增加限定或加一个分支 “Fine-Gray 竞争风险模型敏感性结果对 Classes 4/5 不稳定 → 甲类结论稳健性依赖模型选择”。 | **高** |
| MB-03 | **latent class 模型熵在 5 类时下降** | 原文 “entropy peaked in the 4-class model and declined slightly in the 5-class model” → 5 类选择并非纯由分类质量驱动，而是结合了临床解释性。AI-A 未提，但这是模型不确定性的来源。 | 可加为“类数选择含主观解释成分（5 类虽 BIC 最低、但熵低于 4 类方案）”，在 N4 中补充。 | **中** |
| MB-04 | **反因果、时间锚定与 ICU 入点问题** | 原文提到“exact onset time of sepsis could not be reliably determined”，以 ICU 入院为锚点。若脓毒症发病到入 ICU 的时间变异大，则体温轨迹的“第 0 天”在生理意义上并不同质。这是时间锚定的一个重大方法学局限，AI-A 尚未列出。 | 增加节点 “ICU 入院作为共同锚点的可变性（脓毒症发病到入 ICU 的间隔不一致） → 体温轨迹的第 0 天跨患者不等价”。 | **高** |
| MB-05 | **类 5 不是最低风险组** | 原文“stable normothermia was not consistently associated with the lowest risk”，AI-A 的解读没提这一点。这是一个“意料之外的阴性发现”，也可能影响对“正常体温 = 低风险”的过度简化理解。 | 在 N6 或 N4 中提一句：“稳定正常体温类并非始终最低风险，需注意对‘正常体温保护作用’的误读”。 | **中** |
| MB-06 | **阈值分析与累积暴露** | 原文说阈值/累积暴露分析“enhance clinical interpretability rather than identify optimal cutoffs”——是支持性证据而非独立主要发现，AI-A 未在 N4 中说明。 | 在 N4 中加“阈值/累积分析仅具解释性，不用于寻找最优切点”。 | **低** |


## 6. Required Fixes

1. **拆分证据与节点之间的逻辑关系**：N1–N5 之间的推理边全部改为并列结构，删除 N1→N2→N3→N4→N5 的链式因果；在 E1-E5 中拆分 E4、修正 E1/E2 的表述精确性，不要混淆“测量实用性”、“随机错分”与“效应量方向”等属性。
2. **N2 全面改写**：以“post-discharge mortality 在 eICU 不可得”为出发点，写明“院内终点是数据可用性驱动的选择”，并添加说明：Fine-Gray 竞争风险模型（作为 sensitivity）的真实实施细节原文未完全披露，可能依赖院内状态构建事件/竞争事件。
3. **修正 N3 的方向性判断**：改为“排除早期死亡/短 LOS 者可能**低估**早期高风险轨迹（而非高估），需考虑排除对各类分布的影响方向不确定；作者认为这是轨迹分析的固有选择”。
4. **修正 N6 的表述与置信度**：区分大类（Class 2/3）与小类（4/5），说明 Fine-Gray 敏感性对 4/5 不稳定；对 PAMM 外验不提供显著性检验 → 结论方向“较稳”仅适用于 2/3 类，且应标明置信度 low；将“精确 HR 外推谨慎”改为“外验证力不足以支持精确效应量或临床决策阈值的跨队列迁移”。
5. **补充缺失分支**：增加 Sepsis 定义异质性（ICD vs Sepsis-3）、时间锚定可变性、熵下降与类数选择主观性、Class 5 非最低风险、阈值分析的“解释性非最优切点”五条分支。
6. **在 N4 中补充分类熵下降**：说明 five-class 的熵比 four-class 略低，因此类数选择不仅基于模型拟合，还包括临床解释性判断。
7. **证据表（E 表）修正**：E4 拆分；E5 精确引用位置（2.5.4）；新增对 3.5 竞争风险结果与 4.6 Discussion 中“under-representation survivorship bias”的引用；所有 evidence_id 建议重新编号，以“同一局限一个证据”为原则。