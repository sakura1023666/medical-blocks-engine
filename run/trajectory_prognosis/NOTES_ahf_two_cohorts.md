# AHF Sodium/eGFR：两套队列

## A. 主分析（各自排除）— 当前

- 路径：`67_AHF/Prognosis_Trajectory_v2_42558177`
- Sodium：`obs_days_na >= 3`
- eGFR：`obs_days_egfr >= 3`
- 两指标 N 可不同

## B. 第二套（交集 ≥3）— 主分析跑完后

- 用户确认：两边都 ≥3 天
- 路径：`67_AHF/Prognosis_Trajectory_v2_42558177_intersect_ge3`（新建，不覆盖 A）
- 入组：`obs_days_na >= 3 & obs_days_egfr >= 3`
- 再跑 Sodium + eGFR
