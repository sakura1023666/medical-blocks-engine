<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-11-03T11:37:50 | request_id=msg_f592eb9d-338b-4e1f-b053-30cced110b8b | usage={"input_tokens": 20140, "output_tokens": 5824, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 768, "prompt_tokens_details": {"cached_tokens": 768}} | char_len=10944 -->
# AI-B Tree Attack

paper_id: paper_40295872
question_id: Q8
review_target: @rounds/A_tree_round1_paper_40295872_Q8.md
source_file: adversarial_lit_reading/chunks/paper_40295872_jin2025_shr_sofa_af_mortality_cardiovasc_diabetol.md

---

## 1. Attack Summary

**总体判断：需要重大修改**

AI-A 的决策树整体框架合理（三分法：复用/改编/不适用），证据定位基本准确，但在多个关键节点上存在**因果过度**、**证据偷换**和**方法迁移不精确**的问题。最核心的问题是：**N1 把「中介分析+nomogram+SHAP」作为「可直接复用」的完整模块**，但原文的 nomogram 是基于 logistic 回归的发病预测工具，与用户「survival 地基」存在设计冲突——这正是 AI-A 自己标注了 U3 但未在树中充分反映的矛盾。

另有若干节点存在**原文证据不足或过度解读**：

- N1b 声称 RCS「可直接复用」，但**未区分**原文 RCS 是「按 SOFA 分层内部比较」还是「跨层交互检验」；
- N14a 将「AF 特异病理机制段」归为「不适用」，但**遗漏了原文 Discussion 中通用代谢-器官交互机制**（如酸中毒-线粒体生物能衰竭）与脓毒症的潜在可迁移性；
- N4 的「仅 MIMIC 单库敏感性」分支**缺少证据强度标注**，也未说明 SHR 轴在脓毒症中的文献基础是否薄弱（需区分「因 eICU 缺 HbA1c 而禁用」与「因脓毒症病理不适合而禁用」两类理由）。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| N-01 | N1 | 「**可直接复用**：预后模块顺序与统计套路」——**包含**中介→nomogram→SHAP 整链 | 中介分析在原文中围绕「碳酸氢盐作为 SHR→死亡的中介物」这一 **AF 特异机制假设**展开；nomogram 用 **logistic 回归**（对应「发病概率」而非 survival 风险），与用户「survival 地基」存在地基冲突；SHAP 绑定「SHR 与 SOFA 交互」这一具体变量结构。三者均不是「中性套路」，不能整体归入「可直接复用」。 | 原文 Methods: "A nomogram was developed with multivariable logistic regression"; Fig.4 中介为「bicarbonate-mediated pathway」绑定 SHR。 | 将 N1c 拆分：中介=「需改编」（中介变量需按脓毒症重新选定）；nomogram=「需改编 + 需注意 logistic vs survival 地基差异」；SHAP=「可直接复用」但需配合替代暴露变量重新训练。 | **高** |
| N-02 | N1a | 「暴露×SOFA 交叉分层 + 多时点 Cox」为「可直接复用」 | 原文分组为 SHR tertile（三分类）× SOFA 二分 → 四组合。用户需跑「双库可算复合指标全池」——**多指标 × 多切点**时，四组合框架是否仍成立？「组合→KM→Cox」是套路可复用，但 AI-A 未提示**多指标多重比较**带来的膨胀问题（Bonferroni/FDR 调整）与**指标间相关性**（复合指标共享组分）导致的多重共线性。 | 原文只用单一 SHR，无多指标并行场景。 | N1a 增加条件：「多指标并行时需预声明多重比较调整策略与指标间相关性处理（如相关矩阵/聚类）」；或将「四组合」改为「暴露分层（按指标分位） × 器官评分二分」的更一般化框架并附此警示。 | **中** |
| N-03 | N1b | 「RCS 非线性 + 阈值探索」为「可直接复用」 | RCS 本身可复用，但 AI-A 未区分原文中两种解读：低 SOFA 组阈值效应（SHR=1.0）vs 高 SOFA 组 J 型曲线（理想 SHR=1.2）——**这一区分是对「SHR 与器官功能障碍交互」的发现，不是可直接迁移的分析模板**。用户迁移时不应预设「阈值=1.0/1.2」或「J 型」，而应重新估计。 | 原文 Results: "threshold effects at SHR=1.0 in low SOFA patients... high SOFA patients showed a J-shaped curve, with an ideal SHR of 1.2" | N1b 增加警示：「RCS 框架可复用；但阈值 1.0/1.2 与 J 型是 AF 数据下的发现，不预设为脓毒症规律；需按数据重估并报告不确定区间。」 | **中** |
| N-04 | N3 | 「SHR 等 HbA1c 轴指标主分析禁入双库」 | AI-A 将禁用理由**主要归为「eICU 无 HbA1c」**——这是数据可得性理由。但原文对 HbA1c 依赖的另一层含义是：**SHR 中 HbA1c 本身对「慢性血糖控制」的意义在脓毒症人群中高度不确定**（脓毒症急性期大量液体复苏、糖代谢急剧波动），这不同于「eICU 缺少该变量」。需至少标注此不确定性。 | 原文 Methods: SHR 需「HbA1c or fasting blood glucose within 24h of admission」；无脓毒症人群验证。 | N3 增加区分：「eICU 无 HbA1c ⇒ 数据不可达」与「脓毒症急性期 HbA1c 的稳定性/解释力存疑 ⇒ 机制不确定」两类理由，后者作为文献级风险标注（需复查脓毒症 HbA1c 文献）。 | **中** |
| N-05 | N7 | 「插补：MissForest→MICE m=5+Rubin」 | AI-A 将插补引擎差异并入「需改编」合理，但原文 MissForest 依赖 **MAR 假设**（Methods 明言 "based on the missing-at-random assumption"），而 MICE 同样依赖 MAR——**两者在假设层面无本质差异**，改动动因来自「项目铁律」，并非「原文方法缺陷」。AI-A 将其放在「需改编」分支下，未注明「此改编来自工程规范而非原文错误」。 | 原文 Methods: "Multiple imputation was performed... using Miss Forest method, based on the missing-at-random assumption." | N7 修订：「缺失处理由 MissForest→MICE m=5+Rubin 属工程规范迁移，非对原文统计方法的否定；两者同属 MAR 假设家族；若数据缺失机制偏离 MAR（如脓毒症检验缺失与疾病严重度相关），需做 MNAR 敏感性分析。」 | **低** |
| N-06 | N8 | 「验证：仅 bootstrap→加 eICU 外验口径」 | 原文 nomogram 确实仅 bootstrap 内验（limitations 也承认单中心）。但 AI-A 未指出：**原文预测模型为「nomogram+logistic」，在双库外验时需区分「模型参数固定后的外验」与「模型在外验库重训练」**——AI-A 在 U3 中提出此疑问但树中 N8 未体现。同时，原文 C-index 0.807/0.792/0.722 是内验值，**不可直接作为预期外验表现**。 | 原文 Results: "Internal validation through 1,000 bootstrap resamples" | N8 增加：「双库外验需预声明『冻结参数 vs 重新训练』规则；不得预设内验 C-index 可再现。」 | **中** |
| N-07 | N14a | 「AF 特异病理机制段 = 不适用」 | 原文 Discussion 的机制论述**混合**了「AF 特异」（心房重构、电生理）与「通用代谢-器官交互」（线粒体生物能衰竭→SOFA 衰竭→酸中毒→凝血障碍）。后者在脓毒症病理生理中同样存在（脓毒症诱导线粒体功能障碍、乳酸性酸中毒），不能整体判为「不适用」。 | 原文 Discussion: "SHR-induced metabolic stress diminishes myocardial bioenergetics... acidotic environments... platelet hyperaggregation... SLC26A4-mediated bicarbonate reabsorption" | N14a 修订：「AF 特异部分（心房电生理、基质重构）不适用；但『高血糖应激→线粒体生物能衰竭→器官衰竭加速→酸中毒』的代谢-器官交互框架**可能与脓毒症共享**，作为假设可在课题讨论中引用，但需标注其为生成性假说而非已证路径。」 | **高** |
| N-08 | N12 | 「SOFA 切点/时点/中介物：按脓毒症重定并注释」— 严重程度 medium | AI-A 将 N12 标为「可迁移性不足 (medium)」合理，但漏掉一层：**原文 SOFA cutoff=5 依据是单个引用 [18]（Kohnke 2024 脓毒症微循环）**——该依据本身就来自脓毒症人群！AI-A 在「按脓毒症重定」时未引用这层事实，导致 N12 的理由「原文切点不可默认真理」与原文实际引用的脓毒症来源形成张力的含糊地带。 | 原文引用 [18]: Kohnke J... Crit Care 2024 "A proof of concept for microcirculation monitoring using machine learning based hyperspectral imaging in critically ill patients" — 该文献基于脓毒症/危重症人群。 | N12 修订：「原文 SOFA cutoff=5 所引文献 [18] 来自危重症/脓毒症微循环研究，并非 AF 特有；但引用强度仍低（单篇、概念验证），需按脓毒症文献重新检索确认 5 分切点的稳健性。」 | **中** |
| N-09 | N4 | 「可降级：MIMIC 单库敏感性保留 SHR 轴」 | AI-A 将 SHR 轴「降级为 MIMIC 单库敏感性」在用户门控下合理，但**未说明「敏感性分析」在已跑双库主分析（剔除 HbA1c 轴）之后的补充性角色**——SHR 结果若与主池指标结论不一致，应如何报告分歧？AI-A 的树缺此「结果分歧协商」分支。 | 用户确认（E8）——非原文。 | N4 下增加：「MIMIC 单库 HbA1c 轴结果与双库主池不一致时，需在论文讨论中并列报告，不预设谁优谁劣。」 | **低** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E-01 | N1→N1c（"leads_to" 中介+nomogram+SHAP） | 边将三个异质组件并为一个「可直接复用」链。中介是**机制验证**工具（因果路径），nomogram 是**预测工具**（logistic 地基），SHAP 是**解释工具**。三者方法论角色不同、对用户 survival 地基的适配度不同，不应合并为一条「可直接复用」边。 | 拆分：N1→N1c₁「SHAP=可直接复用」；N1→N1c₂「中介=需改编（变量选择/因果框架）」；N1→N1c₃「nomogram=需改编（logistic vs survival 地基）」。 | **高** |
| E-02 | N9→N7（"if" 插补） | N7 是「由 E6 引出（原文用 MissForest）但迁移到用户双库场景」——边类型标为 "if"（条件）可能误导：这不是「用户像原文一样缺数据」的条件，而是「用户按项目铁律替换引擎」的规范动作。边属性应更明确。 | 将 N9→N7 边改为 "normative"（规范遵循）而非 "if"，或直接在 N7 节点标注「此改动源于项目规范，非原文缺陷」。 | **低** |
| E-03 | N3→N4（"if" 可降级为敏感性） | 边关系正确，但 E-04 中的「结果分歧协商」分支缺失，导致 N3→N4 的边界条件为「MIMIC 有 HbA1c」→「做敏感性」→ 然后呢？无下游。 | 在 N4 后增加「结果分歧协商」分支（见 N-09）。 | **低** |
| E-04 | N13→N1/N9/N14 三分叉 | 三分叉本身合理，但 AI-A 将每个分支下的子节点都标为同层级（transfer_to），未区分「方法组件」与「人群/数据适配」两类不同维度的迁移问题——如 N2（病种改写）与 N1a（分析模板复用）本质是不同属性层次，合并为「需改编」的平级子节点造成了逻辑扁平化。 | 将 N9 下再细分为「方法组件改编」（N7、N8、N12）与「场景适配改编」（N2、N10、N11），或加第一层维度标签。 | **中** |
| E-05 | N14→N14c（"limitation" 发病 logistic 地基） | 原文是「首次入 ICU 的 AF 患者中的死亡预测」，是**队列内生存分析 + logistic 预测工具的组合**。原文并非「发病研究」——AI-A 说「原文地基是发病 logistic」可能过度。原文明文做了 Cox（生存）但 nomogram 用 logistic（分类）——**是混合地基**，不是纯发病。 | N14c 修订：「原文为 Cox+logistic 混合地基（Cox 主推断 + logistic 预测工具）；用户纯 survival 地基与 logistic nomogram 的适配需提前『工具预测 vs 因果推断』分离声明，而非简单归为『不适用』——Cox 部分本来就是可复用的。」 | **高** |
| E-06 | N9→N11（"if" 暴露改为全池） | 边关系合理，但"N11→N3" 的 because 链将「改暴露」与「禁 HbA1c 轴」捆绑为单一因果理由。实际用户的「全池」决定与「禁 HbA1c 轴」决定来自两个独立考量（全指标池 = 课题广度；禁 HbA1c = eICU 数据可达性）。 | 将 N11→N3 与 N11→N4 分离，避免「因为要跑全池⇒所以禁 HbA1c」的耦合表述。 | **低** |

---

## 4. Evidence Problems

| problem_id | related_node | problem_type | description | severity |
|---|---|---|---|---|
| P-01 | N1 | 证据范围过度 | AI-A 将原文「全链」作为「可直接复用」的单一证据（E1/E4），但原文该链绑定「SHR 具体变量」「AF 人群」「logistic 预测」三层实体。**统计套路 ≠ 变量结构 ≠ 人群适配**三层信息在 AI-A 的 E1 中未拆分，导致「可复用」边界模糊。 | **高** |
| P-02 | N14c | 证据误读 | AI-A 称原文地基为「发病 logistic」，但原文 Methods 明确包含：Cox 回归（survival）+ logistic nomogram（预测工具）→ **是混合设计**。「发病」表述不准确，且将「nomogram 用 logistic」误升格为「地基」。 | **高** |
| P-03 | N7 | 证据解释偏差 | AI-A 将 MissForest→MICE 作为「需改编」的依据放在原文 E6 上，但原文 MissForest 本身在统计上是可接受的插补方法，**不是错误或缺陷**。改编动因来自用户项目铁律，非原文问题。证据链略显误导。 | **低** |
| P-04 | N3 | 证据未完整引用 | AI-A 引 E3（SHR 公式需要 HbA1c）作为禁主分析的理由，但原文 Limitations 还提到「单中心」「缺失 AF 表型」「无外验」——AI-A 在主分析禁用理由中**只引了数据不可达**，未合并「脓毒症人群 HbA1c 稳定性存疑」的机制不确定性假设（见 N-04）。 | **中** |
| P-05 | N8 | 证据未区分内外验 | AI-A 将「仅 bootstrap」归为 Limitations（E5），但原文 Limitations 明确承认「single center data may affect generalizability」。AI-A 引对了位置但未说明：**模型内验 C-index（0.807）在无外验条件下具有高不确定性**——这是将「验证缺口」表述为「需加外验」而非「当前证据不足推出普遍性」的细微但重要差异。 | **中** |
| P-06 | N12 | 证据引用不足 | N12 讲到 SOFA 切点「不可默认 AF 的 5 分」——但原文 [18] 引用的正是脓毒症/危重症人群的证据（见 N-08）。「默认」说法既有对的部分（单篇引用的不确定性），也有不准确的部分（并非 AF 特有）。AI-A 未展开这层。 | **中** |

---

## 5. Missing Branches

| branch_id | missing_branch | related_node | why it matters | suggested addition | severity |
|---|---|---|---|---|---|
| M-01 | **多指标多重比较与相关性处理分支** | N1a | 用户显式声明「并行跑双库可算的全部复合指标」→ 必然面临多指标间共享组分（如多个指标都含 HbA1c/血糖组分）导致的**相关性结构与多重比较膨胀**。AI-A 树中完全未提。 | 在 N1a 下增加：「指标相关矩阵 + 聚类分组；预声明 FDR/Bonferroni 控制；报告指标间 Spearman 相关表」。 | **高** |
| M-02 | **结果分歧协商分支** | N4 | MIMIC 单库 HbA1c 轴与双库主池结果不一致时如何处理？AI-A 未给决策规则。 | 在 N4 后增加：「若敏感性结果与主池不一致：并列报告 + 讨论可能解释（人群差异/变量定义差异），不预设孰优」。 | **低** |
| M-03 | **eICU 外验失败的应对分支** | N10/N8 | 用户加入 eICU 外验后，若外验 C-index 显著低于内验或校准度差——应如何决策（a. 修订模型结构 b. 放弃外验仅报告内验 c. 报告外部验证失败原因）？AI-A 只见「加外验」动作，未见「外验失败」路径。 | 在 N8 后增加「conditional」分支：「外验失败 → 诊断来源（人群异质性/变量定义差异/过拟合）→ 预声明处理规则」。 | **中** |
| M-04 | **新数据下的变量操作化分支** | N11 | 用户「双库可算复合指标全池」——**eICU 与 MIMIC 的变量定义对齐**（如血糖单位 mg/dL vs mmol/L、HbA1c 有无、ICU 评分字段版本）是一个具体操作层问题，AI-A 未在树中体现「变量映射/单位一致性检查」分支。 | 在 N11 下增加：「开发集与外验集的变量操作化一致性核对（单位/时间窗/编码版本）→ 输出 variable_alignment_table」。 | **中** |
| M-05 | **中介变量的因果合理性预检** | N1c/中介部分 | 原文中介分析是「探索性」的，但 AI-A 将中介放入「可直接复用」链——中介需要 **因果假设的预先细化**（DAG/反事实框架），不是「跑一个 bootstrap 就行」。 | 在中介节点增加：「预声明中介假设（DAG）+ 敏感性分析（如 E-value）」。 | **高** |
| M-06 | **缺失机制偏离 MAR 的处理分支** | N7 | 脓毒症场景中检验缺失可能与疾病严重度（如乳酸频繁测 vs 不测）相关——偏离 MAR 时插补可能引入偏倚。AI-A 仅写「MICE+Rubin」未给偏离路径。 | 在 N7 后增加：「若缺失与结局相关（MNAR 怀疑）：delta-adjustment / pattern-mixture 模型敏感性分析」。 | **中** |
| M-07 | **SHR 轴在脓毒症中的文献基础核查** | N3/N4 | AI-A 将 SHR 轴「降级为 MIMIC 敏感性」的决策仅来自数据可达性（eICU 无 HbA1c）。但若脓毒症文献中 SHR 预测价值同样较强，则「敏感性」地位需升级为「独立讨论主题」。 | 在 N3 增加：「文献核查分支：检索脓毒症 SHR 预测文献 → 若证据充分则提升 MIMIC 单库 SHR 分析的报告优先级」。 | **低** |

---

## 6. Required Fixes

以下按优先级列出 AI-A 决策树必须修改的条目：

### 高优先级

1. **拆分 N1c**：将「中介 + nomogram + SHAP」从单一「可直接复用」节点拆为「SHAP=可直接复用；中介=需改编；nomogram=需改编（logistic vs survival 地基冲突）」三叶。核心矛盾是：nomogram 的 logistic 地基与用户 survival 地基的张力不应被「可复用」标签掩盖——这正是 E-05 指出的「原文是 Cox+logistic 混合地基」问题。
2. **修正 N14c**：将「发病 logistic 地基」改为「Cox+logistic 混合地基」的准确表述，并在「不适用」话术中区分「logistic 预测工具」与「Cox 生存主推断」——Cox 部分是可迁移的，不能整体否定。
3. **扩充 N14a**：将「AF 特异机制不适用」细化为「AF 特异部分（心房电生理/重构）不适用；但代谢-器官交互的通用机制（酸中毒-线粒体衰竭）可能作为脓毒症可检验假说」，避免过度一刀切。
4. **增加 M-01（多指标多重比较分支）**：用户显式声明「全指标池并行」，这是决策树当前最大的逻辑空洞——没有处理多指标并行的关联与膨胀问题，N1a 的「四组合」框架在池化场景下可能失效。
5. **增加 M-05（中介因果预检）**：中介在原文中是探索性分析（原文 Limitations 承认「其他机制亦可能贡献」），AI-A 应将其标记为「探索性工具」而非「可直接复用模块」，并增加 DAG/敏感性分析预检。

### 中优先级

6. **修正 N3 理由拆分**：将「eICU 无 HbA1c（数据不可达）」与「脓毒症 HbA1c 解释力不确定（机制存疑）」分开标注，避免将数据限制误表述为机制结论。
7. **修正 N12 对 SOFA cut-off 的批评**：原文 [18] 引用的正是脓毒症/危重症证据——AI-A 的「不可默认 AF 的 5 分」说法不完全准确，需改为「引用仅来自单篇概念验证研究，稳健性不足，需重新检索确认」。
8. **修正 N8 的验证缺口表述**：从「加 eICU 外验」的单一动作扩展为「预声明冻结参数 vs 重训练规则 + 外验失败应对路径（M-03）」。
9. **修正 N1b 的 RCS 迁移边界**：明确「RCS 框架可复用、阈值不可预设」，避免 AI-A 未言明但可能被用户误读的「连阈值一起搬」风险。
10. **增加 M-06（MNAR 敏感性分析）**：脓毒症缺数据机制可能偏离 MAR，MICE 不是「一键解决」。

### 低优先级

11. **修正 N7 插补动因表述**：区分「原文方法无错（MissForest 可接受）」与「用户按项目铁律替换引擎」两层含义，避免 Evidence Table 误导。
12. **修正 N9→N7 边类型**：将 "if" 改为 "normative" 或加注释说明改编动因来自项目规范。
13. **增加 M-02/M-07 结果分歧与文献核查分支**：为 MIMIC 单库 SHR 敏感性分析增加下游结果协商规则与文献级风险提示。

---

## 7. 总结判定

AI-A 的决策树在**宏观结构**上可用（三分法合理、用户场景嵌入正确、HbA1c 门控正确），但在以下三处存在影响结论可信度的问题：

1. **「可直接复用」边界过宽**：把中介、nomogram、SHAP 三类异质工具合并为单一可复用模块，掩盖了 logistic 与 survival 的工具地基冲突；
2. **「不适用」边界过窄**：把原文 Discussion 中「代谢-器官交互」的通用机制与「AF 特异机制」混为一谈，可能错失可迁移的机制假设；
3. **多指标并行场景逻辑空洞**：树中无「指标相关/多重比较/结果分歧」处理分支，而这恰恰是用户「全池并行」研究设计最核心的方法学挑战。

建议：**高优先级 5 项全部修入 Round 2；中优先级 5 项至少修入 3 项；低优先级视篇幅取舍。** 修改后可将严重程度降为「低风险」，可进入下一轮。