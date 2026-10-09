# AKI SOSM+WPR 原文全图表双库适配复刻设计

## 状态

本设计取代 `2026-09-17-sosm-wpr-publication-final-design.md`。旧 `publication_final` 仅为既有产物重排，不符合原文面板结构，不再作为目标终稿。

## 研究映射

- 原文疾病/暴露：ASCVD，SHR+GV。
- 本课题疾病/暴露：AKI，SOSM+WPR。
- 结局：仅 28 天全因死亡；现有数据不支持 90 天结局。
- 主库：MIMIC-IV；开发集/内验集沿用既有拆分。
- 外验库：eICU；冻结 MIMIC-IV 特征和模型，不重做 Boruta、不重训。
- 疾病分层：**SOFA 三层 `0–4` / `5–10` / `≥11`**（对应原文 NGR/Pre-DM/DM 三层糖代谢结构，使每张分层图的"×3"面板数与原文一致）。依据：SOFA≥11 为 AKI ICU 预后文献验证的高风险阈值（PMC4184902），≤10 段在 4 处再切一刀得低/中两层；两库同公式、同切点。实测每层 n/事件充足：MIMIC 8129/8048/2217（事件 568/1586/1190）、eICU 3669/5668/1221（事件 283/1174/639）。
- 分层键（资产目录/manifest）：`sofa_0_4` / `sofa_5_10` / `sofa_11plus`；显示标签 `SOFA 0–4` / `SOFA 5–10` / `SOFA ≥11`。
- D02 两库均视为用户确认的上游 AKI 预筛队列；`Acute_Renal_Failure` 不作为二次纳入筛选。

## 不可伪造内容

1. eICU 无 HbA1c，禁止生成 NGR/Pre-DM/DM。
2. 两库最长随访均为 28 天，禁止生成 90 天结果。
3. 两库无 ICU 全程低血糖发作变量；S9 改为“排除基线 Glucose <70 mg/dL”，题名和脚注必须明确。
4. 当前数据无基线+动态肌酐或标准尿量窗，禁止把单次肌酐写成 KDIGO stage。
5. Table S1 若无上游 ICD/KDIGO 提取证据，只能报告已证实的队列/变量定义并标记“上游代码未提供”，不得编造 ICD。

## 原文主表

### Table 1

28 天生存/死亡基线。单一工作簿：

- Panel A：MIMIC-IV。
- Panel B：eICU。
- 结局列固定显示 `Survivor` / `Non-survivor`，禁止显示 `AKI` / `No AKI`。

### Table 2

SOSM+WPR 联合四组与 28 天死亡的 Cox 关联：

- Overall、SOFA ≤10、SOFA ≥11。
- 联合组按原文逻辑：各指标最高三分位为 high、下两三分位为 low。
- Group 1 low/low 为参照。
- 模型列：Unadjusted；Model 1=Age+Gender；Model 2 按项目 ML 关联协变量铁律解析。
- Panel A=MIMIC-IV，Panel B=eICU。

## 原文主图

> 原文每张分层图按 3 层（NGR/Pre-DM/DM）展开；本课题为双库（MIMIC-IV 开发/内验 + eICU 外验），故每张分层图 = 原文面板数 × 2 库。所有图题/轴/框内文字用**英文**（用户确认，图1亦英文）。

1. **Figure 1**：双库纳排流程图（英文）。Panel A=MIMIC-IV，Panel B=eICU；逐步人数来自真实 attrition/checkpoint。
2. **Figure 2**：KM 共 **18 面板**（原文 9×2 库）。每库 3×3：行=SOFA 0–4 / 5–10 / ≥11，列=SOSM tertile、WPR tertile、SOSM+WPR 联合四组；每面板 Log-rank P。
3. **Figure 3**：RCS 共 **4 面板**（2×2）。每库 SOSM/WPR 各一图，图内叠加 3 条 SOFA 层调整后 HR 曲线、95%CI、P-overall、P-nonlinear。
4. **Figure 4**：ROC 共 **6 面板**（原文 28 天 3 层×2 库；90 天数据不可算，不生成）。每面板比较 SOSM、WPR、联合、APSIII、OASIS、GCS，报 AUC 及 95%CI/DeLong。
5. **Figure 5**：Landmark。先在 MIMIC-IV 的 Overall + 3 个 SOFA 层做 PH 检验，自动选违反最明显的层与转折时间；锁定后 eICU 验证。每库显示该层 landmark 前/后 KM（Group1–4），共 2 面板。
6. **Figure 6**：亚组森林图，**4 面板**（2 库×2 指标）；每面板含 Overall + 双库共有临床亚组（Age/Gender/Race/Hypertension/Diabetes/CKD/Ventilation）效应量与 P-interaction。
7. **Figure 7**：分层 Boruta，**6 面板**（2 库×3 SOFA 层）；Z-score boxplot，Confirmed/Rejected/Shadow 三色。外验库禁止重做特征选择——故 Figure 7 仅 MIMIC-IV 3 层；若需 eICU 侧仅呈现继承审计（不放 Boruta）。**最终定为 MIMIC-IV 3 面板**（原文 Fig7 就是单库 3 面板），eICU 无 Boruta。
8. **Figure 8**：分层五模型 ROC+SHAP，**18 面板**（原文 9×2 库）。每库 3 层×3 子图：每层一张五模型 ROC + 最优模型 beeswarm + importance bar（严格原文 A–I 结构）。

## 原文补充表

1. S1：AKI 队列和变量定义/代码证据。
2. S2：双库单因素 Cox。
3. S3：MIMIC-IV train/internal VIF 与 eICU 继承特征审计。
4. S4：SOSM、WPR 连续和三分位 Cox；Overall + SOFA 三层；28 天。
5. S5：Figure 4 判别力数值和 DeLong 比较。
6. S6：SOFA 0–4 层 PH 检验（对应原文 S6=NGR）。
7. S7：SOFA 5–10 层 PH 检验（对应原文 S8=Pre-DM）。
8. S8：SOFA ≥11 层 PH 检验（对应原文 S7=DM）。
9. S9：排除基线 Glucose <70 mg/dL 的联合 Cox 敏感性。
10. S10：完整病例联合 Cox 敏感性。
11. S11：SOFA 分层五模型性能；Overall+三层，MIMIC train/internal + eICU external。

## 原文补充图

1. S1：Overall + SOFA 三层的 PH β(t) 趋势，两库拼图。
2. S2：MIMIC-IV overall Boruta。
3. S3：overall 五模型 ROC，MIMIC internal + eICU external。
4. S4：overall 最优冻结模型 SHAP，MIMIC-IV/eICU。
5. S5：代表性 survivor/non-survivor 的个体 SHAP；SOFA 三层，MIMIC-IV/eICU。

## 本课题额外补充产物

- Figure S6：overall 三集校准。
- Figure S7：overall 三集性能指标。
- Figure S8：overall 三集 DCA。
- Table S12：overall train/internal/external ML 性能。
- Table S13：模型超参数。
- Table S14：Log-Loss。
- Table S15：DeLong。
- Table S16：NRI/IDI。

## 实现边界

- 新增公共、可复用的“reference-paper profile”模块，不在结果目录写一次性 hotfix。
- 新输出先写 `publication_literature_final.__staging__`；验收后生成 `publication_literature_final/`。
- 旧 `publication_final/` 保留并写 `OBSOLETE.md`，不覆盖审计底稿。
- 所有 xlsx 使用公共 SCI 三线表写出或外科式编辑；不得整表覆盖既有发表表。
- 所有图输出 `pdf/png/tiff/image_information` 四目录。
- 数字位遵循 3/3/2/4 公共口径。

## 验收

- 主图 Figure 1–8 齐全且面板数符合本设计。
- 原文补充图 S1–S5 齐全；额外图从 S6 开始。
- 主表 Table 1–2、原文补充表 S1–S11、额外表 S12–S16 连续且无重号。
- eICU 模型均来自冻结的 MIMIC-IV 对应模型。
- 所有图四格式数量一致，根目录无平铺 PDF。
- 所有 xlsx `readable=TRUE`、`corrupt_cells=0`、`styles>0`。
- MANIFEST 逐项记录原文角色、适配差异、数据库、来源 checkpoint 和验证状态。

