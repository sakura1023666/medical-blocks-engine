<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-10-27T15:56:10 | request_id=msg_7ffd8b72-9603-4c4c-bf8f-a084aba1192f | usage={"input_tokens": 1013, "output_tokens": 4802, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 12288, "prompt_tokens_details": {"cached_tokens": 12288}} | char_len=9009 -->
# AI-B Tree Attack

paper_id: paper_40295871
question_id: Q8
review_target: @rounds/A_tree_round1_paper_40295871_Q8.md
source_file: @chunks/paper_40295871.md / 原始PDF

## 1. Attack Summary

总体判断：**部分可信，但需重大修改**

主要问题：
- AI-A 的总体结论方向正确（方法可迁移到MIMIC/eICU脓毒症∩AKI场景），但存在多处**方法细节误读**和**过度简化**问题
- 最大问题在于：AI-A 声称"SMOTE train"可迁移，但未指出原文SMOTE比例为1:1，而MIMIC/eICU中AKI患者死亡率通常在30-50%之间，若直接用1:1 SMOTE可能出现过度平衡导致失真
- "五步特征规则"表述过于简化，原文是：缺失>30%删除 → 布尔特征方差>90%删除 → 相关性≥0.7保留AUC大者 → 信息熵排序逐步添加 → (SMOTE处理在建模前) 这五步，但AI-A未明确说明每步的具体阈值
- AI-A对"内验定权"的描述模糊，未说明TOPSIS的具体融合公式（αi计算），MIMIC/eICU不同库特征分布差异可能影响权重适用性

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| N1 | 五步特征规则可迁移 | "五步特征规则"可迁移 | AI-A只说了"五步"，但未明确步骤内容和阈值。原文是：缺失>30%删、布尔方差>90%删、相关≥0.7保留AUC大者、信息熵逐步选到34个（entropy从高到低排序）、min-max归一化。"五步"表述过于笼统，实际是**删特征→插补→筛相关→熵排序→选数量→归一化**共6个动作。且"信息熵从高到低"实为"entropy小=信息量大"，应选entropy小的优先。AI-A的表述可能被误解为随意五步 | 原文Page2"Sequence characterization was performed...removing 23 features with a missing rate higher than 30%...variance was calculated for 23 of the Boolean features...correlation coefficients...entropy values..." | 改为"原文特征工程步骤：1)缺失率>30%删除(23特征)；2)布尔特征方差>90%删除；3)四法插补(LR-MI最优AUC=0.844)；4)Pearson相关≥0.7保留AUC大者；5)按信息熵从低到高排序，逐步加入特征至AUC最大化(34个)；6)min-max归一化"并可迁移至MIMIC/eICU相同流程 | **高** |
| N2 | "七模型+TOPSIS"可迁移 | "七模型+TOPSIS"可迁移 | AI-A表述过于简单。原文TOPSIS融合有具体细节：每个指标权重为1/6；需正向化（极大型指标转换）；需标准化；计算PIS/NIS；再计算topsisscore。还简化了：SVM和NB无特征重要性权重，TCF特征重要性仅由DT/RF/XGB/LGBM/GBDT提供。直接说"七模型+TOPSIS"不准确——TOPSIS不是简单加权平均 | 原文Page8公式8-13详细说明TOPSIS算法流程 | 补充："TOPSIS融合需7个模型的AUC、F1、ACC、PRE、SEN、SPE六指标，等权1/6，正转化后标准化，计算PIS/NIS，得各模型topsisscore作为融合权重αi（见原文公式8-13）" | **中** |
| N3 | "SMOTE train" | "SMOTE train"可迁移 | AI-A未明确原文SMOTE比例为**1:1**（原文Page8"SMOTE was applied to the training set according to the 1:1 rule"）。MIMIC+eICU中脓毒症∩AKI实际死亡率约30-40%，类别不平衡程度与原文内验集（正例20.9%）不同。直接1:1过采样可能过度平衡导致校准失效。且原文SMOTE作用在**特征处理之后、模型训练之前**，AI-A未说明此顺序 | 原文Page8"SMOTE applied to the training set according to the 1:1 rule" | 补充"原文SMOTE比例为1:1、作用在min-max归一化之后。建议迁移时先评估MIMIC/eICU实际正例比例，若远低于1:1可考虑调整过采样比例或改用SMOTE-Tomek/ADASYN" | **高** |
| N4 | "内验定权" | "内验定权" | AI-A只用四个字，未说明原文的具体分法：训练集/内验集 = 2760/691 = 80%/20%，训练集用于训练，内验集用于计算模型性能并确定TOPSIS权重。AI-A必须说明：TOPSIS权重是**在内部验证集上计算的6指标**再融合而定的 | 原文Page5"Cohort 1 split into 70% training and 30% internal validation"（注意：Page5 Fig1注释说70/30，Page8说80/20，需注意矛盾） | 需说明"原文将ICU队列(Cohort1的ICU子集)分为训练集约80%(2760)和内验集约20%(691)；七子模型在训练集训练，在内验集评估6指标后，用TOPSIS等权融合得各模型权重αi". 另需注明原文Fig.1注为70/30（n=2760/691≈80/20），存在文本与图注不一的矛盾 | **高** |
| N5 | "外验冻结" | "外验冻结"可迁移 | AI-A的概念正确（模型在开发期间不触碰外验集），但"外验冻结"不是原文的独立步骤——原文只是"不在外验上训练"，此为所有外部验证的基本假设。AI-A将"外部验证"设为独立节点可能会被理解为"模型参数固定后再跑外验"的流程节点，而原文并未如此强调 | 原文仅在Page5/Fig1描述了dataset partitioning | 改为"外部验证仅用于评估不外验训练"或直接合并到数据划分节点中 | **低** |
| N6 | "校准/DCA/SHAP" | "校准/DCA/SHAP"可迁移 | AI-A只列了三个缩写，未说明每个的具体使用方式和限制。原文"calibration curve on Supplementary Fig3, DCA on Supplementary Fig4, SHAP on GBDT only（不是TFC全模型）"。AI-A说"SHAP"不加说明可能被理解为对TCF全模型做SHAP，但原文只对GBDT做SHAP热力图（Fig4），对TCF用的是加权特征重要性（Supplementary Table9） | 原文Page4"we chose the GBDT model...visualized its feature importance by drawing a SHAP feature importance heatmap, as shown in Fig.4" | 明确说明："原文SHAP仅用于GBDT最优子模型；TCF全模型的特征重要性由可提供权重的5个子模型（DT/RF/XGB/LGBM/GBDT）特征权重之和排序得到。MIMIC/eICU场景建议同样做法：先选出内验AUC最高子模型做SHAP，再对TCF做加权特征重要性" | **高** |
| N7 | "不适用：原文院内三中心原数据与中文指标名" | | AI-A将"中文指标名"列为"不适用"是多余的——原文虽为中文临床数据，但特征名均为英文缩写（PCT/CRP等），与MIMIC/eICU的英文变量名匹配难度在于**语义同一性**而非"中文指标名"。此外"原文院内三中心原数据"迁移到MIMIC/eICU确实不适用，但还有更关键的问题AI-A没提：原文的"NLR/PLR/LMR/PAR/SI"五个计算特征是原文自己定义的，在MIMIC/eICU可计算但需检查变量是否存在 | 原文Page7公式2-6定义了NLR/PLR/LMR/PAR/SI | 改为："不适用：原文三中心原始ICU患者数据（中国医院、年龄跨度为0-73岁含儿科）不可复制；需自行在MIMIC/eICU重建纳排。NLR/PLR/LMR/PAR/SI五个计算特征在MIMIC/eICU可计算，但需确认血小板/白蛋白/乳酸等变量在ICU入院首测是否可得" | **中** |

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| E1 | N1(五步特征规则) → N2(七模型+TOPSIS) 之间的因果边 | AI-A把"特征规则→建模"当作简单顺序流程。但原文明确SMOTE位置在**特征预处理之后、模型训练之前**，且min-max归一化也是在此。如果AI-A将特征工程与建模分开两个节点，需明确SMOTE和归一化在两者中间。否则用户可能把SMOTE当作建模一部分或特征一部分，导致顺序错乱 | 补"SMOTE和min-max归一化是特征步骤的输出→模型输入的桥梁，位于两者之间而非建模内部" | **中** |
| E2 | N3(可迁移七模型+TOPSIS) → N4(内验定权) | "内验定权"与"训练集训练"的边界不清。AI-A只写了"内验定权"四个字，未说明TOPSIS的权重是在内验集上计算7个子模型的6指标后由TOPSIS算法推算的。若用户理解为"在内验集上重新训练模型定权"则完全错误 | 明确"权重不是训练出来的，是在内验集预测后由TOPSIS算法统计算出的" | **高** |
| E3 | N6(校准/DCA/SHAP) → 可迁移结论 | 原文在外部验证合并集上只报告了AUC=0.7705、DCA在阈值~0.1-0.5时净获益显著，但校准曲线图汇总在Supplementary（未附在文本）。AI-A建议全部可迁移，但未强调原文的DCA是在合并4个外部验证集（n=1421）做的，而MIMIC/eICU结构不同（ICU多且长尾），DCA的阈值范围不一定适用 | 提示"DCA阈值范围~0.1-0.5在MIMIC/eICU可能不同，需重新绘制DCA曲线评估" | **中** |
| E4 | N7(不适用) → 总体结论 | AI-A将"不适用"只限定为"原文院内三中心原数据与中文指标名"，但未提及**人群差异**：原文仅有脓毒性休克（septic shock），用户研究为脓毒症∩AKI（可能含非休克患者），两组人群基线特征和死亡率差异大（原文Training set死亡20.91%，eICU AKI死亡率通常约30-40%）。AI-A应把"核心人群差异"列为不适用/需改写 | 加"不适用于直接应用原文的septic shock定义——必须改用Sepsis-3+AKI-KDIGO定义，或在MIMIC/eICU中重新确定脓毒症与AKI的ICD代码/临床标准交集" | **高** |
| E5 | "可迁移：五步特征规则" 与 "不适用：无法复现原文中文指标" | 这两条存在矛盾：如果某些中文指标名（如hs-CRP、Fibrinogen）在MIMIC/eICU中找不到精确对应，那么五步特征规则中的"原始93指标"就不可完全复制，AI-A应区分"方法流程可迁移"与"特征集依赖医院数据" | 建议"将特征规则迁移为'同一类变量'：人口学、生命体征、实验室、治疗干预（机械通气、透析）、药物等，具体映射到MIMIC/eICU可得变量后做特征选择" | **中** |

## 4. Evidence Problems

1. **训练/内验比例矛盾未被识别**：原文正文Page5 Fig1注释为"70%训练/30%内验"，Page8 Methods为"80%（2760）/20%（691）"（实际上80%×3451=2760.8≈80%=2760，所以正文Methods是一致的；但Fig.1图注的"70%...30%"与80/20矛盾）。AI-A未指出此内部矛盾，若用户以Fig1注为准会导致数据划分差异。需在AI-A决策树中标注原文源矛盾。

2. **SHAP的适用范围**：原文Page4明确"we chose the GBDT model...visualized its feature importance by drawing a SHAP feature importance heatmap"。AI-A直接说"校准/DCA/SHAP"可迁移，未限定SHAP仅用于GBDT最优子模型。对TCF全模型原文用的是加权特征重要性（Supplementary Table 9）。这是**过度引用**——把"对其中一个子模型做SHAP"说成"对整体模型做可解释性"。

3. **业绩指标的来源混淆**：AI-A未区分原文Table 2的指标是**内部验证集**上的1000次bootstrap结果（95%CI），而外验集性能（cohort1-1 AUC0.808 / cohort1-2 AUC0.662 / cohort2 AUC0.784 / cohort3 AUC0.786）分散在Page4-5。若用户只看到AI-A的"内验定权"字样，可能误以为模型只在内验集验证过。

4. **"SMOTE train"证据**：原文对SMOTE的说明仅一句"SMOTE applied to the training set according to the 1:1 rule"（Page8）。AI-A未说明SMOTE仅用于**训练集**，不用于内验或外验。此区别很重要。

5. **TOPSIS公式细节缺失**：AI-A说"TOPSIS"，但未引用原文公式8-13，也未指出需要六个指标的正向化+标准化+等权+计算距离。直接说"TOPSIS"可能被用户简化为"加权平均"，实际TOPSIS不是简单权平均。

## 5. Missing Branches

| 缺失条件/分支 | 影响 | 严重程度 |
|---|---|---|
| **人群定义差异**：原文septic shock（Sepsis-3标准），用户为脓毒症∩AKI（可能含非休克患者）。基线死亡率不同（原文20.9-28.7%，AKI-脓毒症更高）。若直接套用原文模型架构，可能因基线风险差异导致预测概率校准偏 | 高 | 需加分支："需重新定义结局事件发生率与正例比例，并报告模型在MIMIC和eICU各自/合并后的基线AUC、校准曲线" |
| **MIMIC/eICU数据粒度差异**：原文用"ICU入院后首次测量"构建特征；MIMIC有更细的时间戳、chsartevents/labevents多时间点，eICU粒度不同。第一次测量在不同数据库中定义可能不同（如ICU admission vs 到医院时间） | 高 | "补充特征提取时间窗口：MIMIC建议用ICU admission后首个小时/首24h聚合值；eICU同理，需明确时间窗口并说明缺失值处理" |
| **结局时间定义**：原文为"ICU入院后28天全因死亡"（ICU admission为start）。用户研究结局为hosp28（可能指住院28天死亡？）需明确标准。若hosp28是在入院时间点开始计算，与原文一致；若从其他起始算则不同 | 中 | "明确定义hosp28的计数起点：ICU admission？Hospital admission？需与原文保持一致（ICU admission起计28d全因死亡）" |
| **多中心数据池与同一患者重复**：MIMIC和eICU是**不同的重症数据库**，患者不重叠，但MIMIC有多个ICU床位/多次ICU入院；eICU也有多次入院。原文单次ICU入院。若不排除重复住院可能引入信息泄漏。 | 高 | "需加分支：处理同一患者多次ICU入院（按患者ID去重或取首次入院），避免重复测量导致样本非独立" |
| **特征工程中插补方法**：原文比较4种插补（KNN-MI、LR-MI、KNN、Ridge），选LR-MI（AUC 0.844最优）。MIMIC/eICU缺失模式不同（例如MIMIC的lab值常稀疏、eICU则每4h记录生命体征），LR-MI能否迁移需验证 | 中 | "在MIMIC/eICU中需重新评估插补方法，不要默认LR-MI最优；并在开发时比较至少2-3种插补" |
| **SMOTE-after-特征选择 vs SMOTE-before-特征选择**：原文SMOTE在特征选择之后执行。但SMOTE不平衡过采样应在特征选择之前还是之后是方法学争论。AI-A未说明用户应将该顺序保持或改变 | 中 | "提示用户在MIMIC/eICU中考虑到SMOTE时机（特征选择前/后）对结果的可能影响，并报告做敏感性分析" |

## 6. Required Fixes

1. **[必须修改] 明确SMOTE比例与时机**：AI-A需标注原文SMOTE比例为**1:1**，且位于特征工程之后、模型训练之前。迁移到MIMIC/eICU时需评估族群正例比例（AKI死亡率约30-50%，原文正例仅20.9%），决定是否选用1:1或其他过采样策略，并做校准评估。

2. **[必须修改] 补充TOPSIS细节**：AI-A需说明TOPSIS不是简单加权平均，需重演原文七个模型的6指标（AUC/F1/ACC/PRE/SEN/SPE）在内验集上的计算，然后按公式8-13（正向化→标准化→等权1/6→PIS/NIS→topsisscore→αi）求融合权重。并说明SVM/NB无特征重要性、SHAP仅对GBDT子模型用。

3. **[必须修改] 修正"内验定权"表述**：AI-A需要写清楚"子模型在训练集训练（2760例）→在内验集（691例）上计算各模型6指标→用TOPSIS确定权重→应用到外验集预测"。并标注原文正文80/20与图注70/30的矛盾（见证据问题1），建议用户采用Methods中的80/20。

4. **[必须修改] 明确SHAP范围**：AI-A不能笼统说"SHAP可迁移"，应改为"SHAP仅用于最优AUC子模型（原文为GBDT）作特征重要性解释；TCF全模型用可解释子模型（不含SVM/NB）的加权特征重要性排序"。

5. **[必须修改] 增加"人群定义"分支**：用户研究（脓毒症∩AKI）不是原文的septic shock，需在决策树中加分支：MIMIC/eICU中如何定义脓毒症（Sepsis-3）∩AKI（KDIGO/ICD代码）？年龄≥18的筛选逻辑？在训练/验证时报告事件发生率与基线表（类似原文Table 1），以评估迁移适用性。

6. **[必须修改] 增加"数据粒度与去重"分支**：MIMIC/eICU多ICU入院/多次住院需去重或限定首次ICU入院；特征时间窗口需统一（ICU admission后首个测量/首小时/首24h聚合），并注明与原文"首次测量"的差异。

7. **[建议修改] 校准/DCA迁移需注明验证范围**：原文DCA是在合并4个外部验证集（n=1421）上做的，阈值~0.1-0.5净获益。MIMIC/eICU合并后样本量大得多（可能数万），阈值范围可能不同，不能照搬，需重新绘DCA并在决策阈值范围内评估净获益。

8. **[建议修改] 特征选择时不可一字不差照搬34特征**：AI-A列出34个特征名，但未说明这些特征在MIMIC/eICU中的**变量映射不可能100%匹配**（例如"Number of resuscitations (NOR)"在MIMIC中可能需通过procedure events找CPT代码；"Number of blood purifications (NOBP)"类似）。故应改为"选取原文34特征中在MIMIC/eICU可映射的变量子集，并重新运行特征选择流程（可能得到不同变量数）"。

---

## AI-B 额外提示

AI-A的总体方向是对的，但遗漏了 **N3→N4之间最关键的一步——TOPSIS权重不是随意定的，需要在每个新数据集上重新计算（因为权重依赖内验集6指标）**。迁移到MIMIC/eICU时，如果仍用原文的αi权重（0.141/0.153/0.155/0.151/0.089/0.153/0.158），会不匹配。正确做法是：在MIMIC/eICU的开发集上重训七模型，在内验集上重新计算六指标、再按TOPSIS重新定权。AI-A应将此作为"如何迁移"的显式步骤，否则用户直接拿原文权重套用会导致严重偏差点。

---

**攻击完成。以上攻击仅针对AI-A的阶段性产物，不涉及对AI-A的否定。建议AI-A按"Required Fixes"列出优先级逐条修改。**