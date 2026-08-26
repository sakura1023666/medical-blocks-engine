# AI-B Tree Attack

paper_id: paper_004
question_id: Q1
review_target: @rounds/A_tree_round1_paper_004_Q1.md
source_file: adversarial_lit_reading/chunks/paper_004_mmc7.md

## 1. Attack Summary

总体判断：**需要重大修改**

AI-A 对 Q1 的**核心论点是可信且证据扎实的**——"本研究未使用聚类/LCA/轮廓系数定 K；核心分组均为先验/外部标准指定；先验假设保护性（HR<1）方向"——这一结论经逐条比对原文（METHOD DETAILS Page 17–19、Quantification Page 19）确认成立：原文确实只用先验切分（baseline Yes/No、五档自评二分、World Bank 分类、DSM-IV 算法），全文无 K-means/LCA/silhouette/BIC/RCS/spline。

但决策树存在 **1 项高严重度的结果失实** 与 **多项中/低严重度的方法与证据缺口**，必须修改后才能作为对原文的忠实表征：

- **高**：N10/N12 将"无效使用组 = null（无保护）"表述为普适结论，但原文 Figure 4 明确显示**中收入国的无效组 HR=0.70（0.55–0.90）显著保护**，与"null"直接矛盾。AI-A 自己在 U4 已承认此点，却未在节点正文与 Provisional Answer 反映，造成树内自相矛盾。
- **中**：N7 统计模型节点遗漏 **shared frailty（队列随机效应）**，而这是多队列 pooled Cox 的核心机制。
- **中**：全树反复贴"因果过度"标签，却**从未出现 E-value** 这一作者用于抵御未测量混杂的核心敏感性分析，使因果批判失衡。
- **中**：N8/N10 未标注 **selection-into-effectiveness 混杂**（健康状况更好/听力更轻者更易自评"有效"），而原文 Discussion 大篇幅讨论该选择偏倚——这直接动摇"有效性→方向"的推断链。
- **中**：N14 把反向因果当作未处理的局限，但原文已做 SA1（排除前 3 年事件）且结论稳健，属**低估作者的缓解措施**。

核心 Q1 答案方向正确，但若不修正上述结果失实与方法/证据缺口，该树不能作为对原文结果层的可信表征。

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A1 | N12 | "主要结果一致指向 HR<1（保护方向），无效使用组为 null 关联" | "一致"与"无效组 null"均为失实：原文按收入分层后，**中收入国无效组同样显著保护**，并非 null。"无效组 null"只在 pooled 与高收入国成立。该节点把分层的异质性结果压平成单一结论。 | Page 7（行735-736）："middle-income countries exhibited protective associations for both good (HR 0.70, 0.56–0.88) **and** poor effectiveness users (HR 0.70, 0.55–0.90)"；高收入国仅 good 组显著（行733-734）。 | 改为："主要结果多指向 HR<1；**无效组在 pooled/高收入国为 null，但在中收入国亦显著保护（HR=0.70）**，故'有效性决定保护方向'的结论存在国别异质性，非全局成立。" | 高 |
| A2 | N10 | "有效性三分结果：有效组 HR=0.86（风险降低）；无效组 HR=0.98（与参照无显著差异）" | 同 A1：仅引用 pooled 的 0.98，掩盖了中收入国无效组的保护性关联。结果节点应呈现分层数字而非只给 pooled。 | 行724-729（pooled good 0.86 / poor 0.98）；行735-736（MIC good 0.70 / poor 0.70）。 | N10 应补充分层："pooled good 0.86、poor 0.98；高收入 good 0.87、poor null；**中收入 good 0.70、poor 0.70（均显著）**。" | 中 |
| A3 | N7 | "统计模型：IPTW 加权 Cox PH；暴露为分类变量；检验 PH 假设；未使用 RCS/样条" | 漏掉**shared frailty（队列共享脆弱项）**。原文为"7 队列 pooled"，必须用 frailty 项吸收队列级异质性，这是模型骨架，非可省略细节。未提 frailty 会让人误以为是单层 Cox。 | Page 19（行3061-3063）："we fitted Cox proportional hazards models ... To address between-cohort heterogeneity, we included cohort as a **shared frailty** in the model"；行2414 同。 | N7 改为："IPTW 加权 Cox PH + **cohort shared frailty**；暴露为分类变量；PH 仅图形检验（log-cumulative hazard）；无 RCS/spline。" | 中 |
| A4 | N3 | "有效性暴露预设 3 类：无助听器（参照）、有效、无效" | "3 类"是把参照组（非使用者）也算进有效性类别，存在概念混淆。原文有效性变量**本质是使用者内 2 类（good vs poor）**，非使用者是参照/比较组而非"第 3 种有效性"。称"三分暴露"会误导迁移者。 | Page 17（行2950-2954）："We categorized hearing aid **users** into two effectiveness groups ... good effectiveness ... poor effectiveness. Participants who did not use hearing aids ... constituted the **reference** group." | N3 改为："有效性暴露：使用者内 2 类（good=excellent/very good/good；poor=fair/poor），**非使用者为参照组**；分析层面共 3 个比较组。" | 低-中 |
| A5 | N8 / N10 | N8"先验方向：有效使用→更低风险"；N10 把有效性 HR 直接当作方向证据 | 未标注 **selection-into-effectiveness 混杂**：自评"有效"者更可能是健康状况更好、听力损害更轻、期望管理更佳的人群（健康素养/社会经济选择）。原文 Discussion 专门讨论此点，使"有效组风险低"**无法直接归因于有效性本身**，从而削弱"方向"推断。这与 Q1 第 3 问（是否假设方向）的严谨性直接相关。 | Page 9–10（行2190-2258）选择效应讨论；行2347-2355："individuals with milder impairment may be more likely to report a positive outcome ... 'poor effectiveness' may have had adequate correction but higher expectations." | 在 N8/N10 增加 risk_tag："有效性分组受健康选择/严重度混杂，'有效→低风险'不能仅归因于干预本身。" | 中-高 |
| A6 | N15 | "可借鉴：二元暴露→有效性三分（自评切点）+ 收入分层 + IPTW 三组 multinomial + Cox 亚组/交互，适用于多队列 harmonized 生存分析" | 迁移建议过度乐观：(1) 暴露为**单时点 baseline 自评**，非时变/客观；(2) 中收入国存在强**选择偏倚**（经济能力/健康素养过滤），其 HR 不能直接外推；(3) "有效性三分"措辞不准（见 A4）；(4) 未提示地理代表性缺口。confidence 标 medium 但风险描述偏弱。 | 行2944（baseline 单时点）；行2190-2258（MIC 选择效应）；行2384-2391（无低收入国/非洲/南美/大洋洲）。 | N15 改为："方法套路可借鉴，但需限定：(a) 暴露为单时点自评、含测量与分类误差；(b) 收入分层结果受**强选择偏倚**，MIC 估计不可直接外推；(c) 原样本**无低收入国**，迁移到低资源场景需重新验证；(d) '有效性'为使用者内 2 类 + 参照组。" | 中 |
| A7 | N14 | "观察性 pooled IPTW，无法确立因果方向"（risk_tag 因果过度） | 方向性结论是对的，但**低估作者的缓解措施**：原文已用 SA1（排除前 3 年新发病例）专门处理反向因果，且结论稳健；并计算 E-value 量化未测量混杂。节点把"无法确立因果"写成几乎未处理的局限。 | Page 19（行3081-3082）SA1；Page 4（行416-419）SA1 结论稳健；Page 19（行3101-3103）E-value。 | N14 改为："观察性设计无法确立因果；作者已用 **SA1（排除前 3 年）缓解反向因果**且结论稳健、并计算 **E-value**（pooled 1.34、MIC 1.73；good-effectiveness 1.45/1.89）量化未测量混杂——仍不能完全排除残余混杂。" | 中 |
| A8 | N1 | "本文未使用无监督聚类/LCA/K-means 等数据驱动定 K；所有核心分组均为先验/外部标准" | 结论正确，**不构成攻击**。仅提示：Q1 问"数据驱动 vs 主观指定"对一篇观察性流行病学研究略不寻常（更适合 ML/聚类论文）；N1 诚实承认"无数据驱动亚型"是恰当的，无需修改，作为保留确认。 | 全文 + Page 17–19 无聚类/LCA/silhouette/BIC 定 K。 | 无需修改（确认成立）。 | — |

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E1 | N12 →\|contradicted_by\|→ N14 | 把"观察性局限"标为结果的"contradicted_by（被反驳）"在逻辑上过强：观察性设计是**对因果解释的限制**，并不"反驳"关联结果本身存在。边的语义会让人误读为"结果被推翻"。 | 改为 N12 →\|limited_in_causal_interpretation_by\|→ N14（或 qualified_by），保留关联、仅限定因果解读。 | 低 |
| E2 | N8 →\|leads_to\|→ N7（先验方向→分类 Cox） | "假设方向 → 用分类 Cox 检验"形成轻微循环：分类 Cox 本身不"检验方向假设"，只是估计 HR；把 N8 方向假设与 N7 模型用 leads_to 直接相连，会暗示模型验证了假设，而实际上方向来自先验+结果一致性。 | 改为 N8 →\|tested_by\|→ N9/N10（结果证据），并标注"分类 Cox 仅估计 HR，方向结论由先验+结果一致性支撑，非模型直接验证"。 | 低-中 |
| E3 | N1 →\|because\|→ N2/N3/N4/N5 | "because"边暗示"因为没做聚类，所以用先验分组"——但"未做聚类"与"采用先验切分"是**两个并列观察**，并非因果关系。研究者是先决定用先验切分，故而没做聚类，方向与 N1→N2 的"because"相反。 | 把 because 改为 co-observed_with / instantiated_as，避免把"未聚类"说成"先验分组"的原因。 | 低 |
| E4 | N10 →\|supported_by\|→ N12 | N10（有效性结果）支撑 N12（"无效组 null"）——但 N10 的 pooled 数据并不能支撑 N12 的普适性结论（见 A1/A2）。这条 supported_by 边把不充分证据连成了强主张。 | 在修正 N10/N12 后保留该边，但 N12 必须改为带分层限定，否则 supported_by 关系不成立。 | 中 |

## 4. Evidence Problems

1. **E-value 完全缺位（最重要的证据缺口）**：原文对未测量混杂的核心防御是 E-value（pooled 1.34、HIC 1.31、MIC 1.73；good-effectiveness 1.45/1.42/1.89；Page 4 行399-402、Page 7 行737-740、Page 19 行3101-3103）。Evidence Map（E1–E15）与所有节点均无 E-value，而 N9/N12/N14 反复贴"因果过度"标签——使 AI-B/AI-A 的因果批判看起来像作者未做防御，**属过度引用式的片面化**。应新增一个 evidence 节点（如 E16 E-value）并把"因果过度"标签改为"作者已用 E-value + 关联性措辞防御，残余混杂仍存"。

2. **N10/N12 的证据只取 pooled、丢弃分层**：原文 Figure 4 同时给 pooled / HIC / MIC 三套 HR，AI-A 结果节点只引用 pooled 的 0.86/0.98，导致"无效组 null"被当成全局结论（见 A1/A2）。这是**证据选择性引用**，而非证据位置错误。

3. **N6 协变量罗列近似正确但口径混杂**：教育在 Table 1 为 3 档、亚组为 2 档（行3019 vs 行3075），AI-A 用"教育 3（Table 1）/亚组 2"标注，方向正确；但 SDI 在亚组为 low/middle/high 三分位（行3076），界值未在正文披露，AI-A U2 已合理标注为"需查 S4"，保留即可——此处确认非错误。

4. **PH 假设证据（E15）准确但可强化**：E15 称"log-cumulative hazard 图近似平行、无 formal test 统计量"——与 Page 19（行3063-3066）一致，AI-A 的 U5 标注合理，**不属错误**，仅建议在 N7 同步注明"仅图形检验、无 Schoenfeld 统计量"。

## 5. Missing Branches

1. **selection-into-effectiveness 混杂分支（最关键缺失）**：原文 Discussion（行2190-2258）与 Limitation 2（行2347-2355）大篇幅指出——自评"有效"者更可能是健康素养高、听力更轻、社会经济资源更好的**正向选择人群**，且严重度与期望会混杂有效性自评。该混杂直接威胁"有效组→低风险"的解读，却未在 N8/N10 出现任何分支。**应新增 N-selection 节点并连到 N8、N10、N12**，限定方向推断。

2. **低收入国/地理代表性缺口分支**：原文 Limitation 4（行2384-2391）明确"无任何低收入国，缺非洲/南美/大洋洲"。N15 迁移节点只谈"多队列 harmonized"优点，未提示该缺口，迁移到低资源场景缺乏依据。**应新增 generalizability-limitation 分支连到 N15**。

3. **反向因果的 SA1 稳健性分支**：原文 SA1（排除前 3 年，行3081-3082；结果稳健 行416-419）专门处理反向因果，但树中没有对应分支，使 N14 看起来像未处理（见 A7）。**应在 N14 下增加 SA1 缓解子分支**。

4. **队列异质性 / harmonization 措辞差异分支**：原文 Limitation 5（行2401-2418）指出各队列对"使用/有效性"的问法不同（"ever wear" vs "normal use"），可能把"试过但非常用者"误分入 poor 组，偏向 null。这影响 N3 的"有效性"定义可比性，AI-A U3 仅侧面提及，**应提升为正式 limitation 分支连到 N3**。

5. **区间删失分支**：原文 Limitation 6（行2419-2426）指出 2–3 年波次造成 interval censoring（发病时间点不准）。与 N7 时标（time since baseline）相关，树中未体现。**低优先级，建议作为 N7 子分支**。

6. **单时点 baseline 暴露分支**：暴露在 baseline 单时点测定（行2944），非时变；6.5 年随访下，单时点二元暴露对"方向/剂量"的支撑有限。**应作为 N2/N3 的 limitation 子分支**，强化"未探索剂量反应"（N11）的连带论证。

## 6. Required Fixes

1. **【高·必修】修正 N10、N12 与 Provisional Answer**：删除"无效组一致为 null"的普适表述；改为分层——"pooled/高收入国无效组 null，**中收入国无效组 HR=0.70（0.55–0.90）亦显著保护**"。同步消除 U4 与节点正文的自相矛盾（把 U4 的内容上移进节点）。
2. **【中·必修】N7 补 shared frailty**：统计模型节点加入"cohort shared frailty"，以正确表征多队列 pooled Cox。
3. **【中·必修】新增 E-value 证据节点**：补 E16（E-value：pooled 1.34 / HIC 1.31 / MIC 1.73；good-effectiveness 1.45/1.42/1.89），并把 N9/N12/N14 的"因果过度"标签改写为"作者已用 E-value + 关联性措辞防御，残余混杂仍存"。
4. **【中·必修】新增 selection-into-effectiveness 混杂分支**：连接 N8/N10/N12，明确"有效组低风险受健康/严重度/社会经济选择混杂，不能直接归因有效性"，以严谨化 Q1 第 3 问的方向推断。
5. **【中·建议】修订 N14**：把反向因果标为"已用 SA1（排除前 3 年）缓解且结论稳健 + E-value 量化"，而非未处理。
6. **【低-中·建议】修正 N3 措辞**："有效性暴露"改为"使用者内 2 类（good/poor）+ 非使用者参照组"，避免"3 类有效性"概念混淆；同步修正 N15 迁移表述。
7. **【低-中·建议】补缺失分支**：低收入国/地理代表性缺口、队列 harmonization 问法差异（连 N3）、单时点 baseline 暴露（连 N2/N3），分别作为 limitation 子节点。
8. **【低·建议】修正边语义**：N12→N14 由 contradicted_by 改为 limited_in_causal_interpretation_by；N1→N2/3/4/5 由 because 改为 instantiated_as（见 E1/E3）。

> 说明：AI-A 对 Q1 的**主结论（无数据驱动定 K、全为先验/外部标准、先验假设保护性方向）经比对原文成立**，本攻击不针对该核心论点；所列高/中严重度问题集中于**结果层的分层失实、方法节点完整性（frailty/E-value）与混杂分支缺失**，修正后该树可作为对原文的忠实表征。
