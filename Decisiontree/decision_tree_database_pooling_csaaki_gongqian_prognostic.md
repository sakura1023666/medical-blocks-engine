# 分析决策树 — CSA-AKI 预后特征臂（对照 Allyn 池）

> 用户 2026-11-04：Allyn 池跑完后，另开「给 CSA-AKI 做最好的预后模型」主线对照。  
> 不覆盖 `Output_database_pooling/`（Allyn 池结果）。

## 与 Allyn 臂的异同

| 项 | Allyn 池臂 | 本臂（预后海选） |
|---|---|---|
| 人群 / 划分 / 结局 | 同 | 同 |
| 架构 | TPC（+ benchmark LSTM/TF） | 同 |
| 特征 | BlendedLoS keep=1 − Cr/尿 | **文献白名单 KEEP** − Cr/尿 |
| 输出 | `Output_database_pooling/` | `Output_database_pooling_prognostic/` |

## 特征

见 `reports/tst_feature_lit_csaaki_prognostic_2026-11-04.md`  
运行：`DBPOOL_KEEP_TS` + `DBPOOL_DROP_TS=urine_output,creatinine`

## 主比较

`csa_expD_pooled_mimic_sicdb` 外验 eICU/INSPIRE：死亡 AUROC、RLoS MAPE（两臂同口径）。
