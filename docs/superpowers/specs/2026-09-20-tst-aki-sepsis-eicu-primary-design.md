# TST sepsis-AKI：eICU 主库 + MIMIC 外验

**日期**：2026-09-20  
**产出根**：`G:/02block_result/42_AKI_spesis/two_stage_transformer_40041421`  
**用户确认**：按人数 — eICU 主（≈63146）+ MIMIC 外验（≈21470）

## 口径

| 项 | 值 |
|----|-----|
| 病种 | sepsis-associated AKI，院内死亡 |
| 主库 | eICU；`patientunitstayid`；结局由 `hospdischargestatus` 派生 |
| 外验 | MIMIC；主库权重不重训；`min_age=18` 同步 |
| 对照分 | APSIII（两端 baseline 均有） |
| 插补 | `tst_split` → `imputation`；`fit_on=train` |
| 时序 | 真小时 `expand_hours=FALSE`；白名单 + day1>30% 砍列 |
| 白名单 | `configs/tst_feature_priority/aki_sepsis_eicu.R`（禁挂 aki_mimic） |

## 不做什么

不改 33_AKI / 卒中已发表结果；不把评分/诊断泄漏进动态特征池。
