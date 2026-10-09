# 轨迹双库发表对齐能力回写引擎（AP WPR dual 对话沉淀）

## 背景

2026-09-28 AP WPR MIMIC+eICU 轨迹对话产生一批课题私有脚本
（`align_ap_wpr_*` / `fix_ap_wpr_*` / `rebuild_ap_wpr_*`）。
能力应进 `R/trajectory_pub_finalize.R` 与助手模块，脚本归档。

## 可复用能力（进引擎）

| 能力 | config 开关 | 入口 |
|---|---|---|
| 去掉 Missing overview 并顺延图号 | `trajectory_pub$drop_missing_overview` + `figure_stems` | finalize |
| 根目录 Table3 / 分段 Cox 图只留指定库 | `shared_piecewise_cut$root_keep_db` | finalize |
| 双库 Table1/S1/S2/S3/S5 行按交集或 keep 名单外科对齐 | `align_dual_tables` | `R/trajectory_dual_pub_harmonize.R` |
| 单因素表解析 HR 优先含 `p=` 单元格 | `parse_uv_hr_prefer_p` | 同上 |
| 禁止 majority-swap | `trajectory$skip_class_swap`（已有） | survival_utils |

## 课题侧保留

- `configs/config_trajectory_prognosis_ap_wpr_dual.R`
- `run/trajectory_prognosis/prepare_ap_eicu_wpr_dual_data.R`
- `reports/disease_stratification_basis_ap_wpr_dual.md`

## 禁止

- 在 `run/trajectory_prognosis/` 根目录再堆 `fix_*课题*` hotfix
- 用 `write.xlsx` 整表覆盖已发表 SCI 三线表

## 验收

- 新课题只改 config + 调 `finalize_trajectory_pub.R`
- AP 一次性脚本在 `_archive_oneoff/`，README 指向引擎入口
