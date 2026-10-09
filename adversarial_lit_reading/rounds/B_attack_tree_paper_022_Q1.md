<!-- glm_call provenance: model=deepseek-v4-flash-0731 | ts=2026-09-30T11:17:51 | request_id=msg_f7ea7180-16d5-4309-bd23-1e1b4c4605a9 | usage={"input_tokens": 9380, "output_tokens": 16384, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 1024, "prompt_tokens_details": {"cached_tokens": 1024}} | char_len=3061 -->
# AI-B Tree Attack

paper_id: paper_022  
question_id: Q1  
review_target: @rounds/A_tree_round1_paper_022_Q1.md  
source_file: adversarial_lit_reading/chunks/paper_022_2026_wang_ckm_cum_egdr_stroke.md  

---

## 1. Attack Summary

总体判断：**需要重大修改**

主要问题：

- 核心骨架基本可信：4 个 eGDR 变化模式来自 k-means，K=4 由 elbow 法选定；CKM 0–4 是先验分期；RCS 支持负向线性关联，报道 P for nonlinearity = 0.259。
- 但 AI-A 在若干关键措辞上存在过度推断：
  1. “elbow 数据驱动”把目视拐点判断包装成客观自动化选择；
  2. “预设/检验方向”混淆了“作者事先假设”与“事后分析结果”；
  3. 使用“→ / 保护方向”等因果化语言，与观察性研究不符；
  4. N5 与 N12 对 tertiles 的定位互相矛盾；
  5. N7 的亚组列表与原文 Methods 不符，加入 BMI30、遗漏教育和高血压；
  6. E4/E6/E7/E11 等证据位置超出提供的 chunk，部分细节需复查全文。

---

## 2. Node-level Attacks

| attack_id | target_node | AI-A original claim | critique | original evidence check | suggested revision | severity |
|---|---|---|---|---|---|---|
| ATK-N1 | N2 | 簇数 K=4 由 elbow 数据驱动选定 | elbow 法本质依赖研究者目视“拐点”，不是严格统计准则；原文没有报告各 k 的 WCSS 数值，也没有 Silhouette/Gap/BIC 等交叉验证。AI-A 的“数据驱动”表述过于绝对。 | 原文 Methods 说 “optimal number ... determined using the elbow method”，并称 “clear inflection point at K=4”，但没有定量判定标准。 | 改为：“K=4 由 elbow 法（WCSS 拐点，包含研究者判断）选定；未报告其他聚类有效性指标。” | 中 |
| ATK-N2 | N3 | 输入特征=两时点 eGDR（2012 与 2015），非单次基线 | 只有两个时点，k-means 实际是在二维平面上聚类；这不等同于多时点轨迹模型（如 LCGA / 潜类别增长模型）。“捕捉时间演变”是原文的表述，但 AI-A 继承后容易误导读者。 | 原文 Methods 明确 “bivariate approach”，输入是 2012 和 2015 两个 eGDR 值。 | 改为：“二维 k-means：2012 与 2015 两个 eGDR 特征；实际刻画基线水平与两时点变化，不是多时点轨迹建模。” | 中 |
| ATK-N3 | N4 | 四类标签为结果解释性命名（非先验临床试验臂） | “非先验临床试验臂”是一个空对比，因为本研究本来就不是临床试验；且 AI-A 未指出类名语义冲突：Class 2 在 Methods 中叫 persistent low，在 Table 1 描述中又叫 persistent high-risk group。若不澄清，读者可能把 “persistent low” 误读为低风险。 | 原文 Methods 定义 Class 2 为 persistent low；Table 1 文本称 Class 2 “corresponding to a persistent high-risk group”。 | 删除“非先验临床试验臂”这类空对比；补充：“Class 2 的 persistent low 指低 eGDR 轨迹，即高胰岛素抵抗/高风险；原文自身存在低风险误读风险。” | 中 |
| ATK-N4 | N5 | 累积 eGDR 另作连续暴露 + 三分位（T1–T3）先验分位 | “先验分位”不准确：三分位的组数 3 是先验指定，但切点由样本分位数决定，属数据依赖；同时原文又把它列为敏感性分析，AI-A 与 N12 的“三分位趋势属敏感性”冲突。 | 原文 Methods 先写 “analysed as both a continuous measure and in tertiles”，后又在 sensitivity 中写 “reclassifying cumulative eGDR into tertiles”。 | 改为：“组数 3 为研究者指定，tertile 切点由样本分布确定；tertiles 同时用于剂量-反应展示和敏感性/线性趋势检验。” | 中 |
| ATK-N5 | N7 | 亚组切点多为先验（年龄60、BMI30、CKM 0–2/3–4 等） | 原文 Methods 的亚组列表是：年龄、性别、教育、吸烟/饮酒、CKM 分期、糖尿病、高血压、血脂异常；没有 BMI 亚组。AI-A 加入 BMI30，又遗漏教育与高血压。若 BMI 仅在 Table 3 出现，应标明并核实，不能直接归为原文预设亚组。 | Methods “stratified analyses across these subgroups: age..., sex, educational attainment..., behavioural factors..., CKM stage..., diabetes, hypertension, or dyslipidaemia” 不含 BMI。 | 按原文 Methods 列出亚组；若 BMI 来自 Table 3，标注“Table 3 待核对”，否则删除 BMI。 | 高 |
| ATK-N6 | N10 | 暴露↑与卒中风险↓（负向关联）为预设/检验方向 | 原文并未声明事前假设“eGDR 升高会降低卒中风险”，OR 0.95 与 RCS 是分析结果。AI-A 把“预设”和“检验”并列，并用 ↔/→ 方向箭头，容易把观察性关联读成因果或事前假设。 | Abstract 报告 OR 0.95 和 RCS 线性负相关，但没有 “we hypothesized” 之类表述。 | 改为：“结果方向为负向关联；原文未明确预设线性、单调或 U 型方向。箭头应改为‘与较低卒中 odds 相关’。” | 高 |
| ATK-N7 | N11 | Table 2 趋势 + Fig. 3 RCS 线性逆关联 | 提供的 chunk 中没有 Table 2 和 Fig. 3 的完整内容；E6 中的三分位 OR、P for trend 无法从 chunk 核实。Abstract 只能支持 OR 0.95 与 RCS P for nonlinearity = 0.259。且“P for nonlinear 支持线性叙述”应弱化为