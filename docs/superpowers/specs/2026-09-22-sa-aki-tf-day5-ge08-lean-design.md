# SA-AKI L120：TF Day5≥0.80 且必须最高（瘦特征 + 瘦架构）

**日期**：2026-09-22  
**约束（用户硬闸）**：

1. **Two-stage Transformer（arch B）Day5 test AUC ≥ 0.80**
2. **同一 LOS≥5 张量上，TF Day5 必须严格高于 APSIII / Logistic / XGB**（趋势同 TBI；不接受「XGB 更高但 TF 不够」）
3. **eICU、MIMIC 双库都试**；谁同时满足 1+2 谁可做主库（两边都满足取 TF 更高者）

## 分母

- L120：`LOS≥5` only；Day1–5 同分母（`day_mask_all_comers=FALSE`）
- 禁止为凑维放宽 day1 缺失阈值

## 特征

| 库 | 策略 |
|----|------|
| eICU | `feature_select_mode=whitelist` + `aki_sepsis_eicu.R` ∩ day1≤30%；**禁止 density pad** |
| MIMIC | 维持白名单 ∩ coverage（~67 维）；不再 pad |

静态融合保留 APSIII（对照列，不进动态池）。

## 架构 / 损失（抄 TBI 成功配置为底）

- `d_model=128`, `n_layers=2`, `heads=4`, `dropout=0.3`, `tab_dim=128`
- Focal + `day5_loss_weight=3`（先对齐 TBI；若不达标再试 5）
- 早停：`val_auc` @ Day5

## 对照（同张量）

- APSIII、Logistic、XGB：仅用于验收「TF 最高」与诊断天花板  
- **不得**在 TF 未反超时把 XGB 当主结果交稿

## 验收表

| 库 | TF Day5 | TF > 全部对照 | 结论 |
|----|---------|---------------|------|
| eICU | ≥0.80 | 是 | 候选主库 |
| MIMIC | ≥0.80 | 是 | 候选主库 |
| 仅一边 | — | — | 该边主、另一边外验或不报 |
| 都否 | — | — | **停**，改配方，不硬交 |

## 明确不做

- 放宽缺失阈值凑 100–200 维  
- 192×3 大模型硬磨  
- XGB≥0.80 但 TF 更低仍交稿  

## 执行顺序

1. 停/归档当前 192×3 对照跑  
2. eICU shared 白名单瘦特征重跑 → L120 prepare（LOS≥5）  
3. 双库瘦 TF 训练 + 同张量三对照  
4. 出表选主库  
