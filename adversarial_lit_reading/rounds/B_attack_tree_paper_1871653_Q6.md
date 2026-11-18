<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-11-18T14:46:37 | request_id=msg_970ab6f6-ebc6-4189-8bce-9e20d623d2ab | usage={"input_tokens": 13510, "output_tokens": 2618, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 768, "prompt_tokens_details": {"cached_tokens": 768}} | char_len=5382 -->
# AI-B Tree Attack

paper_id: paper_1871653
question_id: Q6
review_target: @rounds/A_tree_round1_paper_1871653_Q6.md
source_file: adversarial_lit_reading/chunks/paper_1871653_fcimb_temperature_jlcm.md

## 1. Attack Summary

**总体判断：需要重大修改**

AI-A 决策树对「外验+敏感性」的证据地图总体方向正确，但存在四个关键问题：(1) **E4 证据偷换概念**——原文外验轨迹图是「模型参数从 MIMIC 固定后分配外库」还是「外库单独估计轨迹后再比较」？需严格区分；(2) **N4 过度标注 limitation**——原文用 Fine-Gray 处理竞争风险，但 AI-A 说「E-value 未报」为「原文不足」，这在医学文献中是常态而非缺陷，不能作为 L4 层「不足」直接剪枝；(3) **关键分支缺失**——原文明确限定了「排除 ICU 停留 < 5 次温度测量」，这直接限制了外验在早期死亡患者上的转移性；(4) **忽略了原文最大的方法学弱点**——体温在 ICU 期间受退热药/温度管理干预，原文自认「indication bias」未解决，这是比「校准曲线缺失」更重要的因果威胁，决策树必须显式标注。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| A1 | N1 | 外验套参：固定 MIMIC 参数 → 外库分配 | ✅ 位置准确 (Methods 2.5.4) — 原文明确说 `Posterior class-membership probabilities were estimated using model parameters derived from the MIMIC-IV cohort` | ✅ 原文支持 | ✔ 保留，但需标注「先验从 MIMIC 固定后赋值外库」 | 低 |
| A2 | N1 | 多中心 (eICU + 南京鼓楼合并) | ⚠️ 严重问题：**南京鼓楼仅 688 人** (3.3%)，而 eICU 13029 人 (96.7%) — AI-A 声称「多中心」但实际是被 eICU 主导的验证集 | ⚠️ 需复查：合并验证集的比例分布未在树中交代 | 必须标注验证集构成比例，防止 N5 迁移时按「三中心」表述 | **高** |
| A3 | N2 | 时依 AUC：动态 > 静态 | ✅ 位置准确 (Results 3.3, Supplementary Figure 2) | ✅ 原文支持 — 但注意**原文说「statistical significance was not observed at every landmark」** | ✔ 保留，但应在节点中注明「并非所有 landmark 都显著」 | 中 |
| A4 | N2 | bootstrap 2000 + permutation 2000 | ✅ 位置准确 (Methods 2.5.2) | ✅ 原文支持 | ✔ 无问题 | 低 |
| A5 | N3 | FG + 结局敏感性重跑 PAMM/JLCMM | ✅ 位置准确 (Methods 2.5.5 / Results 3.5) | ✅ 原文支持 | ✔ 无问题 | 低 |
| A6 | N4 | 「校准/E-value 原文不足」 | ⚠️ **过度批判**：该文是观察性队列研究，非预测模型开发论文。校准曲线/Hosmer 不是该类研究的必需指标。AI-A 将「未报」等同于「不足」是过度标注 limitation。E-value 是因果推断增强报告工具，该文并未宣称因果识别，不应以此作为「证据不足」依据 | ⚠️ 需复查原文全文 (补充材料未提供校准) | 改写为「未做校准/E-value，但鉴于研究类型非预测模型开发，此不构成显著局限」 | **中** |
| A7 | N5 | 迁移：MIMIC→eICU外验；「无南京单中心则降级说明」 | ⚠️ **南京鼓楼不是「可有可无」**：南京队列使用了 Sepsis-3 诊断标准和人工复核，而 MIMIC/eICU 用 ICD 编码 — 前者质量更高且代表了独立的数据采集方式和诊断标准 | ⚠️ 需区分：南京队列的独立性（诊断标准不同）与规模（仅 688 人） | 迁移建议不应把南京队列当成「可选」— 如果用户有南京队列，应在描述中说明其「独立诊断标准」的价值 | **高** |

---

## 3. Edge-level Attacks

| attack_id | target_edge | critique | suggested revision | severity |
|---|---|---|---|---|
| A8 | N1 → N2 | 边标注 `L1 → L2` 隐含「外验先于内部评估」，但原文 2.5.2 (内部) 在 2.5.4 (外部) 之前；且 AI-A 树中 N1→N2 的箭头方向暗示「外验支撑内部」 — 逻辑顺序颠倒 | 交换 N1/N2 顺序，或改为无向/双向关系，表明「外验+内部辨识」并行支撑迁移结论 | **高** |
| A9 | N2 → N3 | AI-A 将「内部时依 AUC + 敏感性」串联，暗示敏感性分析依赖 AUC 结果 — 但 Fine-Gray 与结局敏感性是独立于判别性能的稳健性检验，不是同一链条的后续步骤 | 将 N2、N3 改为并行分支而非串联：内部判别 (N2) 与稳健性 (N3) 分别支撑 L1 证据层级，不构成因果链 | 中 |
| A10 | N3 → N4 | 「敏感性结论 → 校准/E-value不足」的过渡不自然 — 敏感性分析做得充分与校准缺失之间无逻辑递增关系，N4 应该作为独立节点而非 N3 的后续 | 将 N4 移到树末作为「general limitation」节点，不与 N3 串联 | 低 |

---

## 4. Evidence Problems

### 4.1 **MIMIC 参数→外库分配的细节未交代** (证据粒度问题)

AI-A 声称 `E1 = "固定MIMIC参数→外库分配"`，但原文 (2.5.4) 之前还有 2.5.1 的**类数选择是在 MIMIC 中独立完成的**。外验时要问：**外库是否也重新选择类数？** 原文写 `Supplementary Tables 5 and 6` 报告了验证队列的模型 fit 指标和 posterior probabilities —— 这意味着外库的类结构也是重新评估过的，不是简单地套用 MIMIC 的 5 类。AI-A 的 E1 将此简化为一步「固定参数」，**过度简化**。

### 4.2 **外部验证的 KA 生存分离 ≠ 效度证明**

AI-A 的 N1 说外验轨迹形态「大体可复现」，并由此支撑迁移 → 但原文 Figure 2b 的验证队列只是在**描述层面**显示「相似分离」，未报告验证队列中类与死亡之间关联的**效果大小或置信区间**（如 HR 差异检验），只报告了 Supplementary Table 8（未见正文）。这使得 N1 的证据强度被高估。AI-A 应标注「外验仅报告描述性比较，无统计检验」。

### 4.3 **温度测量效度问题完全缺失**

原文 2.2 节:体温最大值的含义 + 测量部位/设备差异 + **退热药物使用未捕捉** (Discussion limitation)。这些是体温作为 biomarker 效度证据的核心限制，AI-A 完全未纳入。

---

## 5. Missing Branches

| missing_branch_id | description | why critical | suggested action |
|---|---|---|---|
| M1 | **排除 <5 次温度测量的患者** — 原文明确说明排除标准导致排除了 ICU 早期死亡患者 (4.5 Discussion: "excluded patients exhibited higher mortality and shorter lengths of stay") | 直接影响外验的适用人群：**不能迁移到 ICU 入院即高风险的早期死亡患者** | 在 N5 (transfer) 前增加分支：「目标人群必须满足 ≥5 次测温」 |
| M2 | **退热药/温度管理干预作为 unmeasured confounder** — 原文 Discussion 明确说 "important time-varying interventions such as antipyretic use, temperature management, and sedation were not fully captured, potentially introducing indication bias" | 这是「温度→死亡」因果推断的最强威胁，比 E-value 缺失更重要 | 必须在 limitation 节点作为 L2 dominant 风险标注，不能只提「校准缺失」 |
| M3 | **无负对照 (negative control) / 安慰剂检验** — 原文未做任何阴性对照分析来支持「温度特定效应」 | 观察性研究中，任何暴露变量与结局的关联都可能受共同混杂驱动 | AI-B 不能确定原文是否有（全文未见），但决策树应显式询问用户是否执行负对照 |
| M4 | **外部验证队列的交叉验证/校准评估缺失** — 外验只做了：轨迹分布比较 + 时变关联复测，但未做预测校准曲线（calibration plot） | 轨迹分类的**临床预测值**未经独立判别校准 | 应在树中显式标注「外验无校准评估」作为 limitation |
| M5 | **bootstrap 与 permutation 的显著性阈值未定义** — 原文没有报告 AUC 差异的置信区间或 p 值，只说「not significant at every landmark」 | 如果用户想在自身数据上复现，需要明确 benchmark | 在方法迁移节点加参数：列出 AUC 差异的 95%CI + 显著性标准 |

---

## 6. Required Fixes

1. **修正 E1 证据描述** — 明确说明外验不仅「固定 MIMIC 参数赋值」，原文还包括外库类数重新评估 (Supplementary Tables 5-6)，不能把多步过程压缩为「套参」。

2. **标注验证集构成不平衡** — N1 节点必须注明 eICU (13029) vs 南京鼓楼 (688) 比例，防止 N5 按「三中心独立验证」误导迁移。

3. **修正 N1→N2 边的方向** — 内部分辨 (N2) 先于外部验证 (N1)，且二者为**并行证据源**而非因果链。

4. **增加未测量混杂分支** — 在 N3 (敏感性) 之后加入「unmeasured confounding (退热药/温度管理/sedation)」作为 limitation 分支 (severity 高)。

5. **改写 N4** — 从「校准/E-value 不足」改为「未做负对照/校准评估，且原文未报告外验效果量检验」——聚焦原文**确实缺乏**的东西，而非要求该研究类型不需要的 E-value。

6. **增加 M1 (≥5次测温) 迁移约束** — 在 N5 transfer 前增加适用人群条件，防止用户在早期死亡占比较高的人群上错配模型。

7. **将南京队列从「可选」改为「独立诊断标准验证」** — 南京鼓楼使用 Sepsis-3 + 人工复核，其诊断方式与 MIMIC/eICU (ICD 编码) 根本不同。这一支线应独立标注为「诊断异质性验证」，而非仅作为「多中心之一」。

---

## 攻击结论

AI-A 决策树的基础证据位置大体正确，但三层问题需要修正：(1) **逻辑链方向错误**（N1→N2 顺序颠倒）；(2) **关键限制分支缺失**（测温次数门槛、退热药未捕获、无负对照）；(3) **N4 过度批判**。修正后可行，当前版本不可直接采信。