<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-19T11:21:43 | request_id=msg_207c8d27-b268-4fab-9c91-a05115ddbd31 | usage={"input_tokens": 23544, "output_tokens": 3370, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=6839 -->
# AI-B Tree Attack

paper_id: paper_004
question_id: Q4
review_target: @rounds/A_tree_round1_paper_004_Q4.md
source_file: adversarial_lit_reading/chunks/paper_004_ewas_new.md；补充材料统计要点

## 1. Attack Summary

总体判断：**部分可信**

AI-A 的决策树核心框架正确——协变量基于 DAG 先验确定、毒物不做单因素预筛、弹性网仅用于 ERS 构建——但存在以下关键问题：

1. **方法层面的严重误读**：AI-A 声称「加权 logistic」用于 ERS–结局模型，但原文明确指出 ExWAS 报不加权结果以避免过调整。补充材料进一步说明「描述、RCS、亚组、中介用复杂抽样」，暗示 ExWAS 与 ERS 的加权策略需区分对待。
2. **共线性的处理被过度简化**：AI-A 将「无 VIF 切点」归为不确定性，但原文的 Discussion 明确指出同时纳入尼古丁代谢物与烟草暴露相关毒物可能诱发 **collider bias**，这是共线性问题的重要体现，AI-A 完全遗漏。
3. **分支不完整**：AI-A 未覆盖「ExWAS 不加权 vs ERS 加权」这一重要分歧；未覆盖二分类毒物（16个）与连续毒物（57个）的不同处理方式在模型中的影响。

---
## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A1 | N5 | 「ERS 两模型=空模与全协变量；**加权 logistic**」 | **既有错误又有遗漏**：(1) 错误：ExWAS 明确**不加权**（p3:「We reported unweighted results…to avoid potential over-adjustment bias」）；(2) 遗漏：补充材料说明「ExWAS 不加权」，暗示 ERS 的 Model 2 可能加权（因该句列举「描述、RCS、亚组、中介」用复杂抽样，ERS 不在其中）。AI-A 没有区分 ExWAS 与 ERS 的加权策略差异。 | **原文支持 ExWAS 不加权**：p3「reported unweighted results to maintain methodological consistency with prior investigations and to avoid potential over-adjustment bias」；补充材料明确描述/ERS非加权名单。 | 改为：ExWAS 与 ERS 的加权策略需分开标注——ExWAS 不加权；ERS 按正文可能加权（需复查补充材料原文），Model 1 不调整、Model 2 调整全部协变量 | **高** |
| A2 | N8 | 「共线性交给弹性网」 | 只给出「无 VIF 切点」作为不确定性，但**遗漏了关键方法学细节**：原文 Discussion 明确提示「当尼古丁代谢物与其他暴露同时进入回归，conditioning on这些变量可能诱导 collider bias」——这是对共线性问题更深层的讨论，不是「只是没报告 VIF」那么简单。 | 原文 p8-9：Discussion「may induce collider bias」「can open non-causal pathways between exposures or distort the true effect estimates」 | 改为：原有的「无 VIF 切点」限定不放这里；N8 应重写为「共线性不仅在统计上被弹性网部分处理，原文还明确警示烟相关毒物同时入模可能诱发 collider bias，且未报告具体处理方法（如剔除烟相关毒物或敏感性分析）」，severity 中 | **高** |
| A3 | N6 | 非线性只明确做在 ERS 上，RCS 3 结点 | 「明确」用词不当：原文只说 RCS 用在 ERS 上，但**未逐字承诺 ExWAS 阶段无任何非线性检查**。不过从方法描述看（ExWAS 部分未提及 RCS），此推断合理。 | p3 方法：只用「To evaluate potential nonlinearity, we employed restricted cubic splines (RCS) with 3 knots」，紧跟 ERS 段落之后 | 改为「方法仅提到 ERS 阶段用 RCS；ExWAS 阶段未明说非线性检查，但不能完全排除」 | 中 |
| A4 | N7 | 交互以分层/效应修饰呈现，不是全暴露交互矩阵 | 过于简化：原文在亚组中「no significant effect modification was detected in stratified analyses」，但 AI-A 没有指出这是**未发现效应修饰**，而非「逐毒物检验交互」的完整证据。在补充分层时，各毒物分别做年龄/性别分层（p4、Fig.3），这更接近「对每个毒物跑两次亚组模型」而非「对每个毒物做交互检验」。 | p4、Fig.3：分层报告的是一次对 73 毒物分别按年龄/性别跑 ExWAS，给出 q<0.05 的集合 | 改为：分层 = 按年龄/性别分别重跑整轮 ExWAS + ERS 亚组；未见 effect modification ＝ 用交互 p 值或可视化判断；原文未明说交互检验的具体形式 | 中 |
| A5 | N3 | ExWAS 不做 p 预筛，全部进入 ExWAS | 部分证据缺失：原文指出 73 毒物中 16 个二分类、57 个 log 转化；但未逐字写「全部毒物进 ExWAS」——需要从不描述预筛这一事实推断。AI-A 使用了「不做 p 预筛」这种否定性断言，需要标注为推断。 | p5-6：只描述预处理（二分类/log转化），未描述单因素筛选步骤 | 保留核心但当添加「原文未描述 p 预筛步骤」这一限定 | 中 |

---
## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E1 | N2 → N8 (limitation) | AI-A 把「无 VIF 切点」挂到了「协变量选自 DAG」这个分支的限 制 上，但共线性问题主要出在**毒物之间**（如烟相关毒物高度相关），不是协变量与毒物之间的 VIF。这条边定位错误。 | 将 N8 从 N2 的子节点改为 N0 或 N3 的子节点（即共线性问题直接与毒物侧数据相关），或在 N8 加注「实质问题在毒物间共线，而非协变量-毒物共线」 | 中 |
| E2 | N3 → N4 (leads_to) | 「ExWAS 不做 p 预筛 → leads_to → 弹性网」这条边给人「弹性网选择在 ExWAS 之后，是 ExWAS 的下游步骤」的感觉。实际上 ExWAS 与 ERS 是两个独立分析，前者单毒物回归、后者混合暴露建模。 | 将 `leads_to` 改为「separate_analysis」(独立分析)，或添加标注「ExWAS 与 ERS 为相互独立流程，不是串联关系」 | 中 |
| E3 | N4 → N5 (leads_to) | 弹性网（N4）与 ERS 结局建模（N5）的关系是「构建 ERS 后进入结局回归」，但 AI-A 缺失「ERS 构建完成后需先按中位数分高低组」这 一 关键步骤 → 然后才进行 N5 的两模型回归。这是流程断裂。 | 在 N4 与 N5 之间插入新节点 N4.5「method: 按 ERS 中位数分为高低组，连续与分类两种形式进结局模型」，原 N5 拆分两行 | 中 |

---
## 4. Evidence Problems

| problem_id | node/edge | evidence issue | detail | severity |
|---|---|---|---|---|
| P1 | N5 / E3 | 证据位置错误 | AI-A 声称 ERS 用「加权 logistic」并引用 `E4 | Methods 2.5`，但 Methods 2.5 只有「weighted logistic regression in 2 models」这句，且是紧跟在 ERS 构建后面的。真正说明 ExWAS 不加权的句子在同段落更早位置，被 AI-A 部分忽略。同时补充材料明确 ExWAS 不加权。 | 高 |
| P2 | N6 / E5 | 偷换概念 | E5 说「非线性只明确做在 ERS 上，RCS 3 结点」，但原文的 Fig.4E 展示的是「ERS 与 periodontitis」的 RCS，不排除作者在 ExWAS 阶段做了其他未在图 中 展示的非线性检查；「只明确做在 ERS 上」的断言超出证据范围 | 中 |
| P3 | N8 / E7 | 把「未报告」当「未存在」 | AI-A 说「正文未写 VIF 阈值或逐步回归删协变量」，然后得出「共线交给弹性网」——这是把「没报告」与「不存在/无需处理」混同。「未写」≠「未处理」，可能正文未报告但在补充材料有，也可能作者没做——两者在证据上区分开 | 中 |
| P4 | 整树 | 把「仿真/方法结果」当「方法假设」 | 弹性网选择的结果（Fig.4C 展示 17 个毒物入选）是分析**结果**不是方法**设定**；AI-A 的 N4 只描述 CV 调参，没有区分「设定 alpha/lambda 网格」与「最终选出的毒物名单是结果而非方法」。 | 低 |

---
## 5. Missing Branches

| missing_id | missing branch | evidence | suggested addition | severity |
|---|---|---|---|---|
| M1 | **ExWAS 不加权 vs ERS 加权** | p3「ExWAS…reported unweighted results」；补充材料「ExWAS 不加权…描述、RCS、亚组、中介用复杂抽样」 | 新增节点：N9「method: ExWAS 与 ERS 的抽样权重策略不同——ExWAS 不加权，ERS 按复杂抽样加权」，类型为 method，severity 高 | 高 |
| M2 | **毒物二分类 vs 连续的处理差异** | p6「16 toxicants underwent dichotomization based on detection limits, while the remaining 57 were log-transformed」 | 新增分支在 N3 或 N0 下：N10「method: 73 毒物中 16 个按检出限二分类，57 个 ln 转化」——说明进入模型的不全是连续量 | 中 |
| M3 | **collider bias 警示** | p8-9 Discussion「when nicotine metabolites and other environmental exposures are simultaneously included…may induce collider bias」 | 新增分支：N11「caveat: 烟相关毒物与其他暴露同时入模可能诱发 collider bias，这是作者明确点出的方法论局限」 | 高 |
| M4 | **吸烟敏感性分析** | p9「associations of most pollutants were substantially attenuated after additional adjustment for smoking status」；「analysis restricted to never-smokers identified lead, 2HPMA, and 2-Naphthol」 | 在共线性/敏感 性 分支下增加：N12「method: 吸烟作为特别协变量做了额外调整 + 不吸烟者亚组分析；多数烟相关毒物关联被削弱」 | 中 |
| M5 | **WQS 作为互补混合暴露分析** | p3「complementary mixture analysis, Weighted Quantile Sum (WQS) regression…q=4, 1000 bootstrap」 | 分支在 N4 旁：N13「method: 除 ERS 外，WQS 作为补充混合暴露建模；两结果互相印证」 | 低 |
| M6 | **共线性的应对方式——LOD 与缺失驱动的二分类仍可能保留部分共线** | 补充材料统计要点「>90%低于检出限或缺失>40%剔除；>30%低于检出限则二分类」 | N10 的补充说明：二分类处理在减少缺失影响同时不消除毒物间相关性，共线性仍需弹性网处理 | 低 |

---
## 6. Required Fixes

1. **重写 N5**：区分 ExWAS（不加权）与 ERS（原文称 weighted logistic，但补充材料只列「描述、RCS、亚组、中介用复杂抽样」——需要标注「ERS 加权与否需复查原文正文，勿引用补充材料作为反证」）。AI-A 现有「加权 logistic」表述**必须重写**。**Severity: 高**
2. **重写 N8**：不能只写「无 VIF 切点」——必须加入 collider bias 的鉴定结论（原文 Discussion 的明确警示），并将 N8 从 N2 子节点移到 N0 或 N3 子节点。**Severity: 高**
3. **增加 M1 分支**：ExWAS 不加权与 ERS 可能加权的差异，这对用户后续建模是关键警示。**Severity: 高**
4. **增加 M2 分支**：16 个二分类 + 57 个 ln 转化。**Severity: 中**
5. **补充 N6 的限定**：「明确」改为「仅从方法描述可推断」，去掉过度断言。**Severity: 中**
6. **修正 N7 的表述**：从「交互以分层/效应修饰呈现」改为更忠实的「原文对年龄/性别做分层 ExWAS（每毒物一层），并对 ERS 做亚组；未检测到显著效应修饰」。**Severity: 中**
7. **新增 M4 分支**：吸烟敏感性分析是共线性问题的重要处理方法，AI-A 的树完全没有覆盖。**Severity: 中**
8. 补充 M5（WQS 互补分析）与 M6（LOD 处理与共线的关系）为低严重度节点的分支条件。**Severity: 低**
9. **修正 E2 边**：ExWAS 与 ERS 不是「步骤先后」而是「独立分析」，将 `leads_to` 改为 `separate_analysis`。**Severity: 中**
10. **在 E3 边中补入按中位数分组节点（N4.5）**，使 ERS 构建→高低分组→结局回归的逻辑链完整。**Severity: 中**

---
## 7. Final Attack Verdict

**总体判定：部分可信，需要重大修改才能作为用户决策树使用。**

核心框架（DAG 协变量、无 p 预筛、弹性网仅用于 ERS）成立，但：
- **两处高危问题**（N5 加权策略误读、N8 collider bias 遗漏）直接影响用户对方法迁移的判断；
- **五处中危问题**要求修改后才能进入下一轮；
- **低危问题**可在收尾轮统一调整。

AI-A 当前版本**不可直接进入下一轮**；需要完成 Required Fixes 1-8 后方可复用。