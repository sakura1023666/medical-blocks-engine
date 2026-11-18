# TST Methods — Reporting gates（防再审，全项目模板）

> 引擎写入入口：`R/pub_tst_methods.R` → `finalize_delivery_root.R --study-type tst` / `tst_summary_results`。  
> 课题可覆盖数字，但下列 **7 条口径不得删**。

## 1. Figure vs table authority
- 主表 Table 2/3（及同源柱图）= bootstrap 权威（全 landmark 测试集）。
- 主文 ROC/混淆/对比面板（常 Figure 2）若画在严重度评分可得子集上 = **单次 run 快照**。
- Results：**以表为准**；图注写清 snapshot n 与表 bootstrap n 的分工。

## 2. External attrition
- 只写账本支持的首末：年龄门控后组装 n → Day-5 可评 n（≥5 evaluable days / day-mask）。
- **禁止编造**中间步（含患者级缺失>50%）人数，除非作者确认清单回填。

## 3. External comparator
- 外验可只报冻结 Transformer 的衰减与校准。
- 无表内外部严重度 AUC 时，**不写**「优于 APSIII/SOFA」，也**不写**「未做对照」自我指控。
- 补算列入《待作者补分析》。

## 4. NRI / DCA vs strong baseline
- 相对严重度分：正 NRI/IDI 可写增益。
- 相对 XGBoost 等：负 NRI/IDI = 无净增益，**禁止**写成临床增量。
- DCA 中段若 XGB 更高，正文如实写。

## 5. Same landmark cohort
- Day1–5 同一 landmark 测试队列；Limitations：不外推短住院者。

## 6. Software
- R 版本以作者实录 / `Methods_software_versions.txt` 为准。
- Software 句只列**本交付用到的包**；不列未使用的 survival 等。
- 表中未出现的基线模型（如 LightGBM）正文不提。

## 7. External tone
- 写 domain shift / 失校准；不写「外验成功」或未再校准即可部署。

## 建议 Results 句（英文，可改数字）

```text
Table 2 reports bootstrap means (SD) on the full L120 test set (n=…).
Figure 2 panels show representative single-run estimates on the score-available
subset (n=…) and are not substituted for Table 2.
External validation used an assembled adult cohort of …, of whom … had ≥5
evaluable ICU days by Day 5; we report attenuation and calibration of the
frozen Transformer without claiming superiority over severity scores on the
external cohort unless those metrics are tabulated.
```
