# 美化提示词：文献 → 对抗阅读 → 地基套路（可复制）

> **旧版提示词不够。** 若只有「决策树 + config + run」、没有「PDF 切块 + 对抗阅读 Q1–Q8 + GLM 真实攻击」，就**对不上**汇报稿标准路径。  
> 用下面这一版；Agent 须同时加载 `pipeline-foundation` + `adversarial-lit-reading`。

---

## 通用模板（完整标准路径）

```text
【角色】
你是 Medical Blocks 流水线工程师。必须按「文献进系统标准路径」执行，
不可跳过对抗阅读直接写 config。

【必读 Skill】
1. `.cursor/skills/pipeline-foundation/SKILL.md`
2. `.cursor/skills/adversarial-lit-reading/SKILL.md`
3. `.cursor/skills/pub-qc-after-project/SKILL.md`
4. `docs/汇报_流水线地基与轨迹案例.md`（标准路径 mermaid）

【标准路径（按序，不可跳）】
A. PDF 入库切块（papers/ → pdf_to_chunks.py → chunks/）
B. 对抗阅读 Q1–Q8（默认至少 Q4+Q5+Q8；我说「完整」则全跑）
   每问：AI-A 建树 → GLM 5.1 真实攻击（glm_call.py）→ AI-A 修正 → Judge JSONL → validate
   禁止伪造 B_*.md；glm_call 非零即停整条链
C. 地基判定：发病 or 预后？
   - 能落地基 → 3A 复制地基模板实例化
   - 地基有、后缀无 → 3B 只加方法层 Block（序号接着最大号）
   - 对不上 → 先和我改问题，禁止硬开第三块地基
D. 写 config 前门控：列审阅 / 分层数值 /（双复合）查新
E. 输出《分析套路决策树》→ 等我确认（与对抗树分开：对抗树在 rounds/labels，套路树在 Decisiontree/）
F. 写 config / run / Blocks / 飞书（只写代码，不自动试跑）
G. 等我确认试跑 → --shared-only → workers → 发表收口
H. 发表质控（强制）：按 `.cursor/skills/pub-qc-after-project/SKILL.md`
   + 规则 `nature_pub_qc_after_project`（`nature-statistics` + `nature-figure`）
   只审 【success】 指标；跳过 【failed】 / 裸名目录
   结构 + 交叉数字 + 逻辑审阅 + Nature Layer D → `reports/pub_qc_*.md` 与 `reports/nature_*_qc_*.md`
   **P0 必须修改并复检清零**；口头给出 PASS/WARN/FAIL；未出报告或 P0 未清不得宣称完成
   （我只举例路径或说「不要审」时禁止打开该目录审阅）

【输入】
- 文献：@adversarial_lit_reading/papers/<论文>.pdf
- 数据：\\192.168.68.133\02block_result\<病种>\data
- 研究问题：（暴露、结局、队列、方法，一句话）
- 方法学映射：（若 A 文方法做 B 病，写清暴露/结局如何替换）
- 对抗范围：完整 Q1–Q8  /  仅 Q4+Q5+Q8（二选一，默认完整）

【硬性交付】
《对抗阅读》
- rounds/A_tree_round1_*.md、B_attack_tree_*.md、A_tree_round2_revised_*.md
- labels/<paper>_<Q>_training.jsonl（validate PASS；B 文件须有 glm provenance）
- （可选）rounds/block_gap_*.md

《套路工程》
1. Decisiontree/decision_tree_<routine>.md（须引用对抗 chosen 结论）
2. configs/templates/config_<routine>_batch.template.R
3. 项目 config_*.R（新目录；勿覆盖已 【success】 旧课题）
4. run/<routine>/run_*_batch.R + worker
5. Blocks：有则复用，无则新建；禁止改旧 block 行为
6. 飞书：run/feishu/ + 三表同步（我给出 base 链接则用我的）
7. 发表清单：原文每个 Figure/Table/Supp → 产出键，一个都不能少
8. 质控：reports/pub_qc_YYYY-MM-DD.md + nature_statistics/figure_qc（PASS/WARN/FAIL；P0 已清）

【工程约束】
- Rscript 与包路径按我约定；R 不能实现再接 Python（参考 ML python 路径）
- 必须可并行 batch；先 --shared-only，再 --workers
- 双确认门：确认分析决策树才写代码；确认试跑才 Rscript

【完成标准】
对抗阅读产物齐全且未伪造 GLM；地基判定正确；套路交付件齐全；
图/表键对齐文献；发表质控 + Nature P0 已清且结论已告知；不改动历史成功项目。
```

---

## 填好的示例：糖尿病 × 卒中 IPW（用药模型三分）

```text
【角色】Medical Blocks 流水线工程师；标准路径不可跳对抗阅读。

【必读】
`.cursor/skills/pipeline-foundation/SKILL.md`
`.cursor/skills/adversarial-lit-reading/SKILL.md`
`.cursor/skills/pub-qc-after-project/SKILL.md`
`docs/汇报_流水线地基与轨迹案例.md`

【标准路径】
PDF 切块 → 对抗阅读（本题：完整 Q1–Q8）→ 地基判定 → 门控 → 分析决策树确认
→ config/run/Blocks/飞书 → 我确认试跑 → --shared-only → workers → 发表收口
→ 发表质控（reports/pub_qc_*.md；PASS/WARN/FAIL）

【输入】
- 文献：@adversarial_lit_reading/papers/用药模型三分.pdf
- 数据：\\192.168.68.133\02block_result\11_ischemic stroke\Medication_regimen_model_42118193\data
- 研究问题：糖尿病与重症缺血性脑卒中患者 28 天全因死亡（MIMIC，IPW；HbA1c≥6.5% 定义糖尿病）
- 映射：原文放疗 → Diabetes_HbA1c；原文 OS → 28 天全因死亡
- 地基预期：预后 + IPW 后缀；优先复用 Blocks/69_ipw_diabetes_stroke_full/（缺图缺表再补，不改旧成功目录行为）
- 飞书：https://lcn1in9jd6ie.feishu.cn/base/RBjfb2iwmamW14s4WhKcS7kwnie

【对抗阅读】
- 先确认/生成 chunks；Q1–Q8 逐问跑完（AI-A / 真实 GLM / 修正 / Judge / validate）
- 重点问：Q4 变量与 PS 逻辑、Q5 加权与缺失、Q8 迁到卒中+HbA1c 的边界
- 禁止伪造 B_*.md

【硬性交付】
对抗 rounds+labels + Decisiontree + template/项目 config + run batch+worker
+ Blocks（复用 69 优先）+ 飞书 + Fig1–5 / Supp 全键对照清单
+ 跑完后的 pub_qc 报告

【工程】
Rscript："/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
新课题可用新产出目录；勿覆盖 Medication_regimen_model_42118193 里已 【success】 的产物除非我明确说验收补洞。
写代码前先交：对抗摘要 + 地基判定 + 分析决策树 + 图/表对照表，等我确认。
```

---

## 自检：这版提示词能不能出汇报稿那张图？

| 节点 | 旧提示词 | 本版 |
|------|----------|------|
| PDF 入库切块 | ❌ 未写 | ✅ |
| 对抗阅读 Q1–Q8 | ❌ 未写 | ✅ 强制 + GLM |
| 地基判定 3A/3B/停 | △ 只提地基 | ✅ |
| 写 config 前门控 | ✅ | ✅ |
| 用户确认决策树 | ✅（仅套路树） | ✅ 对抗树 + 套路树分开 |
| shared-only → workers | ✅ | ✅ |
| 发表收口 | ✅ | ✅ |
| 发表质控 PASS/WARN/FAIL | ❌ 旧版无 | ✅ Phase 6 |

---

## 使用注意

1. 说「完整」→ Agent 应跑满 Q1–Q8；赶时间可改「仅 Q4+Q5+Q8」，但须在提示词写明。  
2. 对抗树（rounds/labels）≠ 套路树（Decisiontree/）；两套都要。  
3. `@pipeline-foundation` + `@adversarial-lit-reading` + `@pub-qc-after-project` 可同时 @。  
4. 质控只对「刚跑完 / 我点名要审」的项目根执行，且**只审 【success】**；举例路径或说「不要审」则跳过打开目录。
