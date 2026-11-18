# 归档：Hip AKI 一轮发表返工的一次性脚本（2026-10-23）

这些文件**不要**再当正式入口。可复用逻辑已进引擎：

| 归档文件 | 引擎落点 |
|----------|----------|
| `_apply_quantile_cascade_hip_aki.R` | `R/quantile_scheme_cascade.R` |
| `_unify_covariates_hip_aki.R` | remirror / Table3 Model1–3 脚注 |
| `_fix_fig1_table4_hip_aki.R` / `_fix_figs_*` | remirror + `R/pub_figure_export.R` |
| `_rebuild_table4_hip_aki.R` | 主文无 Table4；敏感性走 S5 |
| `_screen_sa_hip_aki.R` | 一次性显著性扫描，不进发表 |

仍活跃的课题薄封装（调用引擎）：

- `_rebuild_tables5_hip_aki.R` → `R/pv2_literature_pub_tables.R`
- `_rebuild_s6_s7_s8_hip_aki.R` → 同上
- `_rebuild_tables3_hip_aki.R` → Model4 课题表 + 引擎格式化助手
- `_refresh_image_info_hip_aki.R` → 本题图注文案（数字来自产物）
- `remirror_hip_aki_pub.R` → 本题总装 + `finalize_delivery_root.R`
