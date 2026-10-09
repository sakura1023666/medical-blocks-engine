# SA-AKI：MIMIC 主库 + eICU 外验（趋势对齐 TBI，数据仅本项目）

**日期**：2026-09-22  
**参考项目（仅趋势/配方，禁止迁移学习）**：`37_TBI/two_stage_transformer_40041421`  
**本项目数据根**：`42_AKI_spesis/two_stage_transformer_40041421_mimic_main`

## 硬约束

1. **禁止**加载 TBI / 他病权重、禁止 fine-tune / transfer；TF 从零训在本项目 MIMIC 小时表 + dabiao。
2. **主库 = MIMIC**；**外验 = eICU**（主库验收通过后再做；权重不重训；`min_age=18` 同步）。
3. 验收（L120，LOS≥5，Day1–5 同 n）：
   - **Day5 TF test AUC 为最高日**（趋势同 TBI Table2：Day1→Day5 升）
   - **Day5 TF > APSIII / Logistic / XGB**（本课题硬门槛；不接受 XGB 更高）
   - 目标 Day5 TF **≥0.80**（与先前闸门一致）

## 队列

- 纳排名单：`data/mimic/MIMIC-脓毒症 AKI(1).csv`（stay_id，n=16687）
- dabiao：名单 ∩ 原 dabiao → **n=16686**（缺 1；审计见 `_dabiao_idfilter_audit_*.txt`）
- 小时表：本项目 `378_mimic_sepsisAKI_hourly_full_5d.csv`（非 TBI 表）

## 配方（抄 TBI 成功旋钮，特征/数据仍为本病）

| 项 | 设定 |
|----|------|
| 白名单 | `aki_sepsis_mimic.R` ∩ day1 缺失≤30%；补 RDW/RBC/RASS/TCO2（仍砍 >30%） |
| force_keep | 仅 `lactate` + `norepinephrine`（去掉 ABP 55% 灌 0） |
| 患者缺失 | 0.50（同 TBI）；**不**放宽特征 day1 阈值 |
| 静态融合 | +BMI/CHARLSON/Heart_Failure/Malignant_Tumor/Liver_cirrhosis；**APSIII 仅对照** |
| 架构 | 128×2、Focal、day5_w=5、dropout=0.2、无 input_noise、patience=20 |
| A2 | split → MI(`fit_on=train`) |
| 单位 | L120_B + logistic + xgb |

## 明确不做

- 迁 TBI checkpoint / 小时表 / dabiao  
- 放宽 day1 特征缺失凑维  
- XGB≥TF 仍交 TF 主结果  

## 执行顺序

1. 重建 dabiao（已按名单过滤）→ 清 MIMIC shared/checkpoints/未完成 by_unit  
2. MIMIC shared → L120 TF+对照  
3. 验收 Day5 趋势与 TF 最高  
4. 通过后再挂 eICU 外验  
