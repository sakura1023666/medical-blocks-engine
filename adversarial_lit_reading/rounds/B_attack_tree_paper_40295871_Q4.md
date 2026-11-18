<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-27T15:40:27 | request_id=msg_20e165da-ab3c-4bc2-8955-7b6350da14a0 | usage={"input_tokens": 24084, "output_tokens": 3795, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "prompt_tokens_details": {"cached_tokens": 0}} | char_len=7072 -->
# AI-B Tree Attack

paper_id: paper_40295871
question_id: Q4
review_target: @rounds/A_tree_round1_paper_40295871_Q4.md
source_file: adversarial_lit_reading/chunks/paper_40295871_tcf_septic_shock.md (+ supp chunk)

## 1. Attack Summary

总体判断：**部分可信，但需重大修改**——决策树主脉络（预测导向的筛选流水线）符合原文，但在"预先确定性"判定、筛选流水线细节（插补择优与相关成对的AUC具体指涉）、以及"方法预先确定 vs 子集数据驱动"的表述上存在证据强度不足与概念区分不当问题，迁移到用户研究时必须有强限定。

主要问题：
1. **N7 的含混性**：将"Methods 中写规则"直接等同于"预先确定"，但原文明写"no research protocol was prepared, and the study was not registered"，且第5步"逐步加特征至 AUC 最大"在研究报告层面即已决定，实际问题在于**预先决定的是筛选机制而非最终特征集**。AI-A 混滑了"规则预先确定"与"特征集预先确定"两个层面。
2. **E3/E1 中"34 为止"被 N2/N3 当作"最优"**——原文与 Supp T5 显示 AUC 曲线在 32→34 上升后在 36 骤降，curve 不平滑，"34 最优"应标注为"在该熵排序路径上的局部最优"。
3. **相关成对筛选（第4步）的 AUC 在其他步骤前计算，但未明说在哪份数据上**——AI-A 的 U2 已意识到但证据层未展开（高严重度）。
4. **N8 的表述有过度绝对化**：原文确实没用 UV/VIF/DAG 叙事，但补采信息显示 `Supp Table 1` 里做了大量假设检验（t 检验/卡方），这虽然是基线比较而非协变量筛选，但 AI-A 全文未提及这一点，在反AI-B审查视角下属"选择性证据"。

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A-B-N1-01 | N1 | "预测特征工程五步流水线而非临床DAG/UV→VIF" | 后半句"而非……"是否准确？原文确实无 DAG 与 VIF，但 Supp Table 1 有大量统计检验（t检验/卡方），AI-A 完全未提，导致读者以为原文没有做任何传统统计筛选。 | 无 DAG 与 VIF 叙述正确；但 Supp T1 有假设检验（基线比较），N1 需补充"baseline comparison statistics exist but are not used for predictor selection" | "特征筛选=五步流水线；基线比较中包含假设检验但未用作筛选" | **高** |
| A-B-N2-01 | N2 | "插补择优/相关成对留 AUC 更大/熵排序逐步加至 AUC 最优→34" | "熵排序逐步加至 AUC 最优→34"——Supp T5 显示 36 时 AUC 0.8310 < 34 的 0.8410，但当 38→44 时 AUC 回升，46 后回升至 0.8270，50 时 0.8254。仅称"34 为最优"掩盖了曲线非单调、38-44 段回升的现象；更准确必须说"在熵排序路径上 34 为最大（后续再波动）"。 | Supp T5 明确显示曲线非单峰 | "熵排序逐步加至 AUC 在34处最高，但36后有波动/回升——严格说为路径上局部最优而非全局单调收敛" | **中** |
| A-B-N2-02 | N2 | "插补择优"表述 | 原文第(3)步仅说"四种插补方法比较后选最优"，但未明说比较时用的是**同一分类模型**（用了什么模型？）。AI-A 也未说明。若该模型与后续七模型不一致，插补方法的"最优"是在代理任务上成立的。 | 原文 ("build the same classification model separately") 有"same classif. model"，AI-A 未引用 | 保留，但需注明"该比较所用基模型未明说，需复查原文补充材料" | **低** |
| A-B-N3-01 | N3 | "34 特征列表" | 34 个特征在正文 Results 列出，AI-A 未在节点表中展开；无问题。 | 与原文一致 | 无需修改 | 低 |
| A-B-N4-01 | N4 | "七分类器 + TOPSIS 融合" | 与原文一致，但 N4 中的"最终预测器"概念与"七子模型"的关系未明确——TOPSIS 融合**不是在训练集上训练一个融合器**，而是在内验集上算权重。AI-A 的 N5 已部分处理但未强调"融合权重是内验集上确定的"。 | 原文 "model fusion and weight assignment were conducted based on the internal validation set" | 需在 N4/N5 间增设"融合权重=内验集上计算"的边 | **中** |
| A-B-N5-01 | N5 | "内验六指标等权TOPSIS→αi; 阈值0.5; SMOTE" | "内验六指标等权TOPSIS→αi"正确。但 AI-A 未提到 αi 有极小值（SVM 0.089）——若迁移用户想复现，权重是否敏感？原文未做权重敏感性。AI-A 的 N5 可加"未做权重敏感性分析"。 | 原文结论区未报告权重敏感性 | "内验六指标等权TOPSIS→αi；SVM 权重仅0.089，原文未做权重敏感性分析" | 低 |
| A-B-N6-01 | N6 | "超参:随机/网格搜索" | 原文说 "random search"，Supp T6 标题写"All model parameters were obtained through random search"——AI-A 说"随机/网格"不准确，"网格"不在正文出现。但 Supp T6 表格本身列了"Range"与"Optimum"看起来像 grid。建议改为"随机搜索（参数网格见Supp T6）"。 | 正文仅说随机搜索；Supp T6 的标题与内容一致为随机 | 改为"随机搜索（网格定义见Supp T6）" | **低** |
| A-B-N7-01 | N7 | "Methods写了规则; 最终特征集数据驱动; 未见预注册" | "规则预写但子集数据驱动"的表述不精确——问题在于：第(5)步"熵排序逐步加至AUC最大"本身就是筛选机制，它在 Methods 中预先声明，所以**「筛选机制」预先确定、而「最终特征集」不是**。AI-A 的 N7 混淆了机制与结果，且"未见预注册"的检索不代表原文未遵守——原文在 Methods 里直接说了 "no research protocol was prepared, and the study was not registered"，这说明**不仅没有预注册，而且主动声明了**。AI-A 的证据 map 里 E5 也应更新。 | 原文 Methods 末尾明写"no research protocol was prepared, and the study was not registered" | N7 改为"筛选机制（五步流程与熵排序）在 Methods 预先声明；最终34特征集由数据驱动；原文主动声明未准备研究方案、未注册" | **高** |
| A-B-N8-01 | N8 | "未走经典协变量 p/VIF/逐步回归叙事" | 原文确实未用传统单因素p→多因素模型，但需注意 Supp T1 中做了大量基线组间检验（Levene/t/卡方）。AI-A 声明"原文未说明 UV/VIF"是事实，但没提 Supp T1 的存在，易让人误以为原文完全无统计检验。 | Supp T1 有假设检验 | "原文未用UV/VIF/DAG做筛选，但Supp T1含基线比较假设检验（t/卡方），须与筛选区分" | **中** |

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| A-B-E-01 | N1→N2 | 边成立：N1 主张后被 N2 的证据细则支持。但 N2 的"相关成对留 AUC更大"与 "熵排序+AUC 最优" 的 AUC 是有标度差异的——相关成对是在筛选过程中的AUC（未说明在何数据集），熵排序 AVC 在 32/34 段持续上升；AI-A 未提示这两个 AUC 不是同一评估下的比较。 | 在 N2 加注"两处AUC的评估集与评估时点未见原文细说——需复查代码" | **中** |
| A-B-E-02 | N5→N6 | 边成立：N6 超参搜索实际发生在七子模型训练前，但 N5 是融合逻辑。AI-A 的图中 N5→N6 是从融合→超参，时序上反了。超参搜索发生在子模型训练前（N5 的 TOPSIS 融合是子模型都训练完才做的）。 | 修正箭头方向为 N6→N5，或增加标注"N6 发生在 N5 之前" | **中** |
| A-B-E-03 | N1→N8 | 边成立但不完全：N1 主张"非临床DAG/UV→VIF"与 N8 "未用"是同一件事的重述，图结构中 N1→N8 有冗余嫌疑，且易造成"N8 是被 N1 推出的结论"而非"独立文献发现"。 | N8 不能单独成claim节点，建议改为"N1 的下位注释" | **低** |
| A-B-E-04 | N0→N7 | 边成立但 N7 的置信度评分自相矛盾：N7 标了 medium confidence + risk_tag "证据不足"，但节点表里同时给了 medium——"未见预注册"的主语是"AI-A 未检索到"，但原文确实写了"未注册"，所以证据是强证据（原文明说）。AI-A 的 risk 标注应改为"已证实"而非"证据不足"；"预先确定"问题的复杂点在于**机制确定 vs 结果数据驱动**，不是证据不足。 | 把 risk_tag 改为"概念区分需精化"，并把 confidence 上调至 high（原文声明未注册） | **高** |

## 4. Evidence Problems

| 问题 | 具体证据 | 建议 | severity |
|---|---|---|---|
| 选择性证据：隐藏 Supp T1 | AI-A 宣称全文未见 UV→VIF，但没有提 Supp T1 存在假设检验。若迁移用户以为该文"完全无统计检验"，会低估该文的统计工作。 | N8 与 Provisional Answer 中注明"基线比较含假设检验(Supp T1)，但未用于筛变量" | 中 |
| Fig.2 与 Supp T5 的"最优"表述过度 | AI-A 的 N3 说"34=最优"，但 Supp T5 显示 AUC 曲线非单调（38-44 段上行）。若读者只看 N3 会以为熵排序单调收敛。 | 在 N3 注明"Supp T5 曲线于36后波动，34为所选点；可视为局部最优而非单调收敛" | 中 |
| E4 / N6 过度简化 | Supp T6 只列随机搜索，网格/随机均出现在 AI-A 的 N6 但所附证据 E4 未有网格字样。 | N6 改为"随机搜索（参数网格见Supp T6）"，去掉"网格"或标注为读者推断。 | 低 |
| N7 "未见预注册" 证据来源不清晰 | AI-A 的 E5 说"未见预注册分析计划"，但原文 Methods 明说"no research protocol was prepared, and the study was not registered"——这不是"未见"，而是"原文声明"。 | 更改为"原文主动声明未准备方案/未注册" | 高 |

## 5. Missing Branches

| 分支 | 内容 | 影响 | 建议新增节点/边 |
|---|---|---|---|
| 插补是否 train-only？ | 原文明说 "interpolate the missing values" 在训练集上做插补比较，但外部验证集/测试集的插补是否用训练集拟合的插补器？AI-A 的 U1 已提出，但树中无节点。 | 影响复现与数据泄漏风险 | 新增节点 N9: "泄漏风险——插补器/归一化/筛选是否只用训练集拟合"，连接至 N2 |
| 数据划分不一致（70/30 vs 80/20） | 正文 Fig.1 写 70/30，但 Methods 写 80/20；AI-A 的 U3 已提，但决策树没有分支。 | 影响"内验上算TOPSIS"的可复现性 | 在 N4 旁加注"原文划分比例在 Fig.1 (70/30) 与 Methods (80/20) 不一致——需复查" |
| 外部验证集是否做了同样的特征处理？ | 原文对 cohort 2/3 是否也运行五步流程并选 34 特征？Cohort 2/3 的外部验证特征是否一致？原文未明说。AI-A 未提及。 | 若外部集也重新筛特征，则跨中心可比性存疑 | 新增节点 N10："外部验证集是否复用MIMIC的34特征？未明说" |
| SMOTE 只用了训练集？ | 原文说 "SMOTE was applied to the training set"，但最小队列（cohort 3 n=261）可能未经 SMOTE 预防——AI-A N5 已提，但"训练集 SMOTE 1:1"与"验证集是否过采样"的关系需区分。Supp T12 显示验证集有重采样。 | 迁移时若用户处理困难队列，需要明确"SMOTE是否只在训练集上做" | 在 N5 上加注"验证集过采样只用于 supp 分析（Supp T12），未改变主结果" |
| 特征重要性聚合的局限 | AI-A 未提 SVM/NB 无特征权重、树模型权重求和的不等价性（不同模型的权重尺度不可直接相加）。 | 影响对"TCF特征重要性"的理解 | 新增节点 N11："特征重要性=树模型内置权重求和；SVM/NB不参与——跨模型权重尺度不可直接相加" |

## 6. Required Fixes

1. 【高】修正 N7（和 E5）：原文主动声明未注册未准备方案，因此"未见预注册"的表述应改为"原文主动声明未预注册"。同时将 N7 的节点表 confidence 调为 high、risk_tag 从"证据不足"改为"概念区分需精化——筛选机制预先确定 vs 特征集数据驱动"。

2. 【高】在 N2 与 N3 中分别注明两处 AUC 的评估集与"最优"的语境：Supp T5 曲线非单调，34 为熵排序路径上的局部最优；"34个特征"是第(5)步在该路径上的输出，不是全局最优。

3. 【高】在 N8 与 Provisional Answer 中加入 Supp T1 的存在，以免给人的印象是该文完全无统计检验；并添加"基线比较假设检验 ≠ 协变量筛选"的辨析。

4. 【中】修正 N5→N6 的时序方向（N6 超参搜索在子模型训练前，N5 的 TOPSIS 融合在子模型训练后），或更改图中箭头方向为 N6→N5。

5. 【中】新增节点 N9（泄漏风险：插补/归一化/筛选是否 train-only）、N10（外部验证集是否复用同一34特征）、N11（特征重要性聚合局限——SVM/NB不参与，树模型权重不可直接求和）。

6. 【中】在 E1/E2 中明确标注 Supp T2/T3 的相关成对筛选的 AUC 在何数据集上计算未明说，需复查代码/补充材料。

7. 【低】N6 的"随机/网格"改为"随机搜索（Supp T6 列出参数网格）"。

8. 【低】N1→N8 的边改为注释，避免 N8 看起来是独立结论。

---

> **AI-B 备注**：本攻击仅针对 AI-A 决策树的结构与证据可信度；不改变 AI-A 文件、不写 labels。所有攻击均提供 target/critique/revision/severity。迁移使用时请务必先落实 Fix 1、2、5 带来的修订，否则用户复现时可能误以为最终特征集为全局最优，并忽略泄漏风险。