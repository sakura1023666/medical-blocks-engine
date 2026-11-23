# scripts — 78 数据库池化（正式源码位置）

**本目录是正式源码。** `/tmp`、结果盘 `scripts/`、对话临时稿 **禁止当下一课题入口**。

发表收口（全项目）：`Rscript run/dbpool/finalize_summary_delivery.R --dir …/summary_results`  
规则：`.cursor/rules/dbpool_pub_reuse.mdc`  
复用地图：`docs/reuse/2026-10-26-dbpool-delivery-midterm-reuse-map.md`

---

## A. 引擎级 / 下课题直接复用（改这里）

| 文件 | 作用 |
|---|---|
| `finalize_easl_paper_pub.py` | 定稿 Table/Fig；末尾调 `run/dbpool/finalize_summary_delivery.R` |
| `eval_liver_paper_ci.py` | DeLong AUROC / bootstrap MAPE CI |
| `rebuild_table2_only.py` / `rebuild_table3_only.py` | Table 2 / 3 重建 |
| `rebuild_table_s1_allyn.py` / `rebuild_table_s2_moesm2.py` | Table S1 / S2 重建（版式模板；勿把 Allyn/MOESM 字样写进客户 Methods） |
| `adapt_realextraction_to_blendedlos.py` | RealExtraction → BlendedLoS 布局 |
| `run_dbpool_experiment.py` | 按实验单元调 `../upstream/BlendedLoS` |
| `build_blendedlos_hourly.py` | 长表 → 小时宽表 |
| `cross_eval_ams_mimic.py` | Amsterdam↔MIMIC 交叉 specialization |
| `pack_uln_triple_summary.py` | ULN-all3 主包 + bili/ALT/AST 敏感性 S 表图 + 引擎收口 |
| `dbpool_feature_inventory.py` | **Table S9** 特征清单 + Fig2/S*↔四策略表 Gen 数字链锁定（全 dbpool 复用） |
| `refresh_uln_table3_after_cross.py` | 交叉评估后回填 Table 3 / S4/S6/S8 |
| `redraw_uln_triple_figures.py` | ULN 三联 Figure 重画 |
| `run_uln_cross_eval_four.sh` | 四队列交叉评估编排 |
| `harmonize_blendedlos_units.py` | **引擎级** 四库单位调和+门控（血糖→mmol/L、血红蛋白→g/dL）；prepare/train 必挂 |
| `fix_mimic_blood_glucose_mmol.py` | 薄包装 → `harmonize_blendedlos_units`（旧 ULN shell 兼容） |
| `schedule_uln_glu_retrain_34.sh` | 单位修正后四队列重训 → `summary(new)`（不覆写旧 Output_physclip） |
| `run_icuaaki_units_retrain_29.sh` | ICUAKI 单位修正后在 29 重训（新 Output_*_units，旧结果保留） |
| `prepare_full_icu_blendedlos.py` / `prepare_*_blendedlos.py` | 各病种 BlendedLoS 准备（换病复制改参） |
| `freeze_liver_*.py` / `prepare_liver_*.py` | 肝相关队列冻结与划分 |

上游公开代码：`../upstream/BlendedLoS/`。

---

## B. 课题一次性 / 训练运维（勿当发表入口）

训练 watch、GPU keeper、resume 某次 bench、screen 草稿等：用完归档到本目录 `_archive_oneoff/`，或留在本目录但 **不要** 从下一课题复制当 finalize。

示例（运维，非发表）：`weekend_gpu_keeper.sh`、`run_easl_paper_finalize_watch.sh`、`resume_easl_*.sh`、`schedule_uln_four_on_34.sh`、各类 `run_*_train*.sh`。

---

## C. 已并入引擎、勿在本目录再复制

| 能力 | 引擎位置 |
|---|---|
| Methods + 软件版本 + 白名单 | `R/pub_dbpool_methods.R` + `run/dbpool/finalize_summary_delivery.R` |
| 软件踢 mice/jstable（dbpool） | `run/pub/finalize_delivery_root.R` + `R/pub_software_versions.R` |
| 禁下划线 + Times xlsx | `python/pub_xlsx_scrub_display.py` |
| 字体 QC | `R/pub_qc_fonts.R` |
| 通用 finalize / QC | `run/pub/finalize_delivery_root.R`、`run/pub/run_pub_qc_after_project.R` |

---

## 标准收口顺序（每个 dbpool 课题）

1. 训练 / pack 出 Tables+Figures  
2. `Rscript run/dbpool/finalize_summary_delivery.R --dir <summary_results>`  
3. Agent：Nature Layer D → 修 P0 → 中期 PDF → prune（交付仅五件套）
