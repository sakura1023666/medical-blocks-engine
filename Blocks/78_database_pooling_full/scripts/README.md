# scripts — 78 数据库池化适配与实验封装

**本目录是正式源码位置。** `/tmp` 里的同名 `.py` 多为过期副本，下一课题禁止当入口。

| 文件 | 作用 |
|---|---|
| `adapt_realextraction_to_blendedlos.py` | RealExtraction → BlendedLoS 数据布局 |
| `run_dbpool_experiment.py` | 按实验单元调用 `../upstream/BlendedLoS` |
| `build_blendedlos_hourly.py` | 协调长表 → 每人小时宽表 |
| `freeze_liver_acg.py` / `prepare_liver_acg_blendedlos.py` | ACG 酶≥2×ULN 队列冻结与划分 |
| `finalize_easl_paper_pub.py` | 定稿 Table/Fig；末尾 `_finalize_delivery_root`（Methods+白名单） |
| `rebuild_table_s1_allyn.py` / `rebuild_table_s2_moesm2.py` | Table S1 / S2 重建 |
| `rebuild_table2_only.py` / `rebuild_table3_only.py` | Table 2 / 3 重建 |
| `eval_liver_paper_ci.py` | DeLong AUROC / bootstrap MAPE CI |

上游公开代码在 `../upstream/BlendedLoS/`。

发表收口：`run/dbpool/finalize_summary_delivery.R`（见 `docs/reuse/2026-10-26-dbpool-delivery-midterm-reuse-map.md`）。
