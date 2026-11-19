<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-11-19T15:15:33 | request_id=msg_88c4a68e-2871-4999-983b-6fd8214c1a77 | usage={"input_tokens": 12898, "output_tokens": 3617, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 768, "prompt_tokens_details": {"cached_tokens": 768}} | char_len=6946 -->
# AI-B Tree Attack

paper_id: paper_060
question_id: Q3
review_target: @rounds/A_tree_round1_paper_060_Q3.md
source_file: @chunks/papers/paper_060.md (Acta Psychologica 267 (2026) 107149)

---

## 1. Attack Summary

**总体判断：需要重大修改（部分可信）**

**主要问题：**
AI-A 决策树的结构大致合理，但在**证据引用精度**、**方法误读**、**分支遗漏**和**因果过度解读**四个维度存在严重问题。具体包括：(1) N2 节点关于"网络 vs 仅相关"的对比在原文中缺乏直接对应证据（原文未将网络分析作为"更好替代"来论证，而是作为补充视角）；(2) N3 节点关于方法优势的因果推论（"优于"）缺乏原文因果证据支撑，属于因果过度；(3) N5/U1 关于"未做方法替换敏感性"的判断方向正确，但遗漏了原文已存在的**内部稳健性检验**（如 LPA 的 1-5 类比较、BLRT/LMR 检验、网络 CS 系数 bootstrap），这些不能算"完全未做"稳健性验证；(4) 缺失关键分支如"横断面设计限制"、"数据共享前置研究"、"跨群体可比性（已有文献的三类/四类解）"。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A-N1 | N1 | "LPA 捕捉条目模式异质性，优于单一总分切点" | "优于"是价值判断，原文仅说明传统回归的局限及需要识别潜在亚组（Page 2, Introduction），但未做**实证**对比证明 LPA 优于总分切点。该判断部分是方法论共识，但作为"本文的论证"缺乏原文直接证据。 | 原文 P2: "existing studies... largely conceptualized SOC as a homogeneous, continuous variable, overlooking potential latent subgroups" — 这支持"需用LPA"，但不支持"LPA优于总分切点"作为**实证结论**。 | 将"优于"改为"被采用以捕捉条目模式异质性，原文指出既有研究忽略潜在亚组"；将"优于"限定为"理论上更适配研究问题"而非"经验上更优"。 | 中 |
| A-N2 | N2 | "网络识别中心/桥节点，优于只报相关" | AI-A 声称网络"优于"只报相关，但原文仅将网络分析定位为"提供细致视角"（Page 2: "network analysis offers a nuanced view of the links"），且相关系数表（Table 5）**同时被报告**。原文没有声称网络取代了相关，而是**补充**。 | 原文 P2: "While traditional regression is limited, network analysis offers a nuanced view..." — 注意此处对比的是回归，不是相关；且原文 Table 5 仍报告相关。 | 修正为"网络分析作为补充视角，识别中心/桥节点；与相关分析并列报告而非替代"。 | **高** |
| A-N3 | N3 | "中介量化间接路径" | "量化间接路径"表述本身准确，但 AI-A 标注的置信度为 high 且未标注横断面因果风险。原文承认横断面设计（P8 limitations 部分被截断但标题可见），且中介模型中的因果方向是理论假设而非实证验证。AI-A 虽在 risk 列标注"横断面因果"，但 claim 部分未限定为"假设检验"。 | 原文 Methods/Measures 均注明 cross-sectional；Table 6 报告的是路径系数和置信区间，不能证明因果方向。 | 修正为"中介模型检验理论假设的间接路径（横断面设计下为统计关联而非因果证明）"。 | 中 |
| A-N4 | N4 | "三件套回答「谁异质+结构+机制」" | 框架合理，但"回答"一词暗示这些分析完全成功闭环。实际原文自身在 Discussion 中承认"本研究首次整合三方法"（P5），但对"机制"的结论是部分的（中介在 C3 不显著）。AI-A 的置信度高且未标注此限定。 | 原文 P5: "This study is the first to integrate LPA, network analysis, and mediation analysis to reveal the heterogeneous structure..." — 原文自己用"to reveal"而非"revealed fully"。 | 修正为"三件套旨在回答「谁异质+结构+机制」，但机制部分的结论是部分成立的（C3 中介不显著）"。 | 中 |
| A-N5 | N5 | "未见用 LCA/K-means/传统逐步回归/SEM 全模型作为敏感性替换" | 描述基本准确，但"未见"需要区分"未报告"和"未做"。AI-A 使用的证据 E5（Methods/Results）来源是**全文查阅所得**，但 AI-A 无法 100% 确证作者"未做"（可能是做了未报告）。应修正为"原文未报告"。 | 全文 Methods 2.3(1)-(4) 描述了四类分析，未提及 LCA/K-means/SEM 作为敏感性；但不排除补充材料或审稿回复中存在。 | 将"未见用"改为"原文未报告使用"；并区分"未报告"与"未执行"。 | 中 |
| A-N6 | N6 | "SPSS/Mplus/PROCESS/JASP；网络在 R" | 对原文 Methods 2.3 描述基本准确。但 AI-A 未标注 JASP 在原文中的**具体用途**未说明（原文在 2.3 开头列出软件，但未逐一对应分析方法）。 | 原文 P3, 2.3: "SPSS 24.0, Mplus 8.3, PROCESS Macro 4.2 and JASP 0.18.2 were used for data analysis." — 确列出，但后文具体章节只提到 R 用于网络，Mplus 用于 LPA，PROCESS 用于中介，JASP 用途不明。 | 建议补充"JASP 具体用于何种分析在原文中未明确说明"。 | 低 |
| A-U1 | U1 | "换方法结论是否不变：原文未证明" | 判断方向正确，但 AI-A 遗漏了原文**有限的内部稳健性检验**：LPA 做了 1-5 类模型的系统比较（Table 2），网络做了 CS 系数 bootstrap（CS = 0.362–0.751，P5 原文明确报告），中介做了 5000 次 bootstrap。这些虽非"方法替换"，但属于结果稳健性验证。AI-A 的"未证明"过于绝对。 | 原文 Table 2 报告了 1-5 类 LPA 的拟合指标；P5 报告网络 CS 系数；Methods 2.3(4) 报告 bootstrap 5000 次。 | 修正为"原文未做方法替换敏感性（如 LCA 取代 LPA），但包含有限的内部稳健性检验（LPA 类数比较、网络 bootstrap、中介 bootstrap）"；增加 U3 节点区分内部稳健性与方法替换敏感性。 | **高** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| A-E1 | N1 → N4, N2 → N4, N3 → N4 | AI-A 画出三条方法节点直接汇入 N4（三件套），隐含这三者同等地为 N4 提供支撑。但原文中三个方法的成熟度和作用不同：LPA 用于识别亚组（充分验证），网络分析是描述性探索（CS 系数勉强达标），中介是验证性假设检验（部分不显著）。三者对 N4 的支持强度不均。 | 建议为每个节点→N4 的边标注`support_strength`（如 LPA→N4 强，网络→N4 中，中介→N4 中偏弱），或拆分 N4 为"亚组识别成功+结构描述部分成功+机制部分成立"。 | 中 |
| A-E2 | N4 → N5 | N4 是三件套的组合策略声明，N5 是"未做方法替换"的局限。这条边暗示"组合策略→未做替换"。逻辑上，组合策略本身并不推导出"未做替换"——这是两个独立事实。原文可能做了有限的内部稳健性但未做方法替换。AI-A 的边未说明为何 N4 需要推出 N5。 | 将边逻辑改为"组合策略的充分性→需验证方法替换稳健性→原文未报告→证据不足"。缺少"需验证"中间节点。 | 中 |
| A-E3 | Q3 → N6 | Q3 问题包含"为何选此法"和"换方法结论会变吗"两个维度。N6（软件栈）与这两个维度都无直接逻辑关联。软件选择是实施细节（tool），不是方法选择理由（method rationale），也不是方法替代敏感性（method robustness）。 | 建议删除 N6 或重定位为补充信息/次要节点，标注`not_directly_relevant_to_Q3`。 | 中 |
| A-E4 | N5 → U1 | 这条边本身合理（N5 支持 U1），但 AI-A 证据链方向不完全准确：N5 是"未报告方法替换"，U1 是"换方法结论是否不变——证据不足"。中间应有"未报告方法替换→无法评估结论稳健性→证据不足"的推理链。当前边反馈到 U1 缺少"为何未报告方法替换导致证据不足"的解释节点。 | 增加中间节点的推理链或将 N5 的 role 从 claim 改为 evidence_of_gap。 | 低 |

---

## 4. Evidence Problems

**P1. 证据位置不精确（E1–E6）** —— AI-A 的 evidence map 使用"Methods 2.3(2)"、"Discussion"等方式，但未精确到页码/段落，且多处证据来自摘要而非正文。审稿时无法快速核对。建议引用形式改为（Page X, Section 2.3）或引用原文 Table/Figure 编号。

**P2. E5 证据方向混淆** —— AI-A 用"Methods/Results"作为证据声称"未见用 LCA/K-means/SEM"是基于**全文阅读的推断**，不是原文明确的"我们未使用 X 方法"的声明。这属于**默证推断**（argument from silence），需注明"默证推断"属性。

**P3. 过度引用 vs 未引用** —— E2 声称"非仅相关矩阵叙述"，但原文 Table 5 **确实报告了相关矩阵**，同时补充了网络分析。AI-A 将"互补"扭曲为"替代"，属于偷换概念。

**P4. 机制证据过度解读** —— N3 声称中介"量化间接路径"，原文确实做了，但 C2（Profile 2）的中介效应在 Table 6 中置信区间为 **-0.062 到 0.030（包含 0）**，且 C3 也不显著[]。AI-A 未报告这些部分不显著的细节，构成选择偏差。

---

## 5. Missing Branches

| missing_id | missing branch | why it matters | suggested revision |
|---|---|---|---|
| M1 | **横断面设计的因果局限** | Q3 的"换方法结论会变吗"部分隐含"因果关系是否稳健"。原文明确是横断面研究（Methods 2.1），横断面下 LPA+中介的因果解释天然受限。AI-A 决策树未纳入"横断面设计→因果解释受限→换方法可能改变结论"分支。 | 增加节点 N7: "横断面设计" → "因果关系强度受限" → 连接至 U1。 |
| M2 | **数据共享前置研究的重叠风险** | 原文在 P3, 2.5 明确说明"data were derived from the same dataset as a previously published study (Ma et al., 2025)"。这产生两个问题：(1) 方法选择的独立性可能受限（同一团队复用分析框架）；(2) "换方法"中枢组可能已在先前发表中被分析过。 | 增加分支: "同数据复用 → 方法选择可能受先前研究影响 → 换方法结论稳健性需更谨慎评估"。 |
| M3 | **跨群体可比性（文献中已有 LCA/K-means 先例）** | 原文 Discussion 明确提到 Liu et al. 2024（三类解）、Wang et al. 2024（三类解）、Liu et al. 2025（四类解）在不同人群中做过类似分类。AI-A 将 "首次整合"（原文原文强调）与 "方法首创"混淆——原文承认 LPA 在 SOC 分类中已有先例，仅"整合三方法"是首次。 | 增加分支/注释: "方法选择并非独创，但三法整合是首次 → 换方法后的结论差异可能主要来自人群差异而非方法差异"。 |
| M4 | **LPA 类数选择的内部比较（1–5类）** | AI-A 说"未见方法替换敏感性"，但原文 Table 2 系统比较了 1-5 类模型的拟合指标（AIC/BIC/aBIC/entropy/LMR/BLRT），且明确说明 5 类因小类群体比例过低被拒绝。这本身是一种**类数敏感性分析**。 | 将 U1 的表述修正为"原文做了 LPA 类数敏感性（1–5 类），但未做 LCA/K-means 等方法替换敏感性"。 |
| M5 | **网络 CS 系数的边界问题** | 原文报告 Profile 1 的 CS 系数为 0.362，低于通常 0.5 的推荐阈值。这意味着网络分析在 C1 中的稳定性边际不足。AI-A 未在决策树中反映该发现对"网络分析稳健性"的削弱。 | 增加节点: "C1 网络 CS=0.362/<0.5 → 网络中心性结论在低 SOC 组中稳健性有限"。 |

---

## 6. Required Fixes

1. **【必改】【高】修正 N2 和 E2** —— 将"网络分析vs仅相关"的表述改为"网络分析作为补充视角，与相关分析并列报告"。原文 Table 5 确实报告了相关矩阵，不能声称网络"替代"了相关。

2. **【必改】【高】修正 U1** —— 在原"未做方法替换敏感性"基础上补充"原文包含有限的内部稳健性检验（LPA 1–5 类比较、网络 bootstrap CS 系数、中介 bootstrap 5000 次）"，并区分"内部稳健性"与"方法替换敏感性"。

3. **【必改】【中】修正 N3 表达** —— 将"中介量化间接路径"改为"中介模型检验理论假设的间接路径（横断面下为统计关联而非因果验证）"。删除过度自信的表述，并在结果精度上补充"C2 组中介效应在 95% 置信区间内含 0（-0.062 to 0.030）的不显著发现"[]。

4. **【必改】【中】删除或重定位 N6** —— 软件栈与 Q3 无关。若保留，需标注为"实施细节、非方法选择理由"。

5. **【必改】【中】增加缺失分支** —— 补充 M1（横断面因果局限）和 M2（数据复用）分支，连接至结论的置信度评估。

6. **【建议】【中】证据引用格式** —— 将 E1–E6 的引用从"Methods 2.3(2)"格式改为精确的（Page X, Section 2.Y）或原文 Table/Figure 编号。

7. **【建议】【低】N4 拆分** —— 将"三件套回答…"拆分为"亚组异质性成功识别 + 网络结构部分稳健 + 中介机制部分成立（C3 不显著）"。

8. **【建议】【低】边标注支持强度** —— 为 N1→N4、N2→N4、N3→N4 三条边标注 support_strength 差异，避免误导读者认为三者对结论的支撑力度相同。