# 分析决策树：AHF × Sodium/eGFR 轨迹预后（Prognosis_Trajectory_v2_42558177）

## 地基判定

- **地基**：预后 `survival`（指标轨迹分型 → 30 天院内死亡）
- **方法后缀**：JLCM 潜类别 + eICU `predictClass` 外验 + PAMM（与 COPD `55_COPD/Prognosis_Trajectory_v2_42558177` 同套路）
- **参考文献套路**：fcimb-16-1871653 / COPD WPR success 交付面

## 暴露

| 指标 | 口径 |
|------|------|
| Sodium | 住院日级血钠中位数（入 ICU 起 30 天窗） |
| eGFR | CKD-EPI 2021 无种族式，日级（取数端已算） |

两指标**独立**建模（本批不跑交叉组合）。

## 人群 / 库

- 发现：MIMIC-IV AHF ICU stay
- 外验：eICU AHF unit-stay
- 纳排：≥18 岁、ICU LOS≥1 天；诊断码见 `data/_source_docs`

## 结局

- `died_30d_hosp` → `survival_30d` / `survival_time_30d`（30 天）

## 轨迹建模门槛

- 日序列：1–30
- `min_non_na_days = 3`（与取数说明一致）

## 两套分析口径（用户 2026-11-27 确认）

1. **主分析（当前在跑）**：按指标各自排除（Sodium≥3 / eGFR≥3 分别建模，N 可略不同）
2. **第二套（主分析跑完后再跑）**：两边都 ≥3 天的**交集队列**上再跑 Sodium + eGFR（同一 N）
   - 产出根另开，避免覆盖主分析：`67_AHF/Prognosis_Trajectory_v2_42558177_intersect_ge3/`
   - 宽表实测：MIMIC both≥3≈8421（单指标各 8424）；eICU both≥3≈2262

## 协变量

- 发现集 UV → VIF → 锁定后套外验（`covariate_vars_from_vif=TRUE`）

## 配置 / 入口

- Config：`configs/config_trajectory_prognosis_ahf_jlcm_batch.R`
- Prepare：`run/trajectory_prognosis/prepare_ahf_trajectory_data.R`
- Batch：`run/trajectory_prognosis/run_trajectory_prognosis_ahf_jlcm_batch.R`
