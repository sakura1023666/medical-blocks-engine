# prognosis_v2 课题脚本（薄封装）

**当前活跃项目**：`G:/02block_result/49_Dyslipidemia/prognosis_v2_mainval_41904528`  
（主库 NHANES+SHHS，验证 CHARLS；路径见 `pv2_paths.R`）

旧三库平权结果已归档：`prognosis_v2_41904528_ARCHIVE_equal3cohort_20261019`。

本目录只放**本题专用**的路径、协变量清单和出表文件名。可复用逻辑进引擎，不要在这里继续堆算法。

## 引擎落点（下次项目直接用）

| 能力 | 引擎位置 | 课题如何调用 |
|------|----------|--------------|
| 分位级联 quartile→tertile→binary | `R/quantile_scheme_cascade.R` | config 开 `quantile_scheme_cascade`；Table2/Cox/KM/亚组共用 |
| 文献宽表 Cox M1–M3 + 改终点敏感性 | `R/pv2_literature_pub_tables.R` | `pv2_cox_wide_m123_body` / `pv2_censor_at_days` / `pv2_write_cox_wide_xlsx` |
| S6 插补前后 / S7 关联 / S8 中介（与 Table3 同协变量） | `R/pv2_literature_pub_tables.R` | `pv2_s6_*` / `pv2_s7_*` / `pv2_s8_*` |
| 预后方法学 md + 软件版本 + 交付白名单 | `R/pub_prognosis_v2_methods.R` + `run/pub/finalize_delivery_root.R --study-type prognosis_v2` | remirror 收尾调用；中期后再 `--prune-only` |
| 睡眠×血脂异常 mainval 全收口 | `run/prognosis_v2/finalize_sleep_mainval_delivery.R` | Fig4 P-linear、S15 PH、Methods、QC、中期、prune；`PV2_PROFILE=sleep_dyslipidemia`；**每次本课题定稿必跑** |
| Rubin Cox（m=5） | `run/prognosis_v2/pv2_mi_cox.R` + `R/mi_rubin_pool.R` | 推断表必须 Rubin；图可用 complete#1 |
| 预后纳排图版式 + 底账 CSV | `R/attrition_log.R` | `attrition_draw_outcome_*` |
| 多库相关 + 未加权 Cox 中介 | `Blocks/20_mediation/13block_mediation_multi_db_cox.R` | 多库课题用；单库可走 `pv2_s7/s8_*` |
| 图四目录 / DPI≥600 | `R/pub_figure_export.R` | `pub_figure_ensure_formats` |
| Nature 结构 QC | `run/pub/run_pub_qc_after_project.R` | Agent 再填 nature-statistics / nature-figure |
| 预后 P0 机器门控（Hip 教训） | `R/pv2_pub_p0_gate.R` | remirror 收尾 `pv2_pub_p0_gate()`；规则 `prognosis_v2_pub_p0_gate.mdc` |

说明见 `run/pub/README.md`、`docs/reuse/2026-10-23-prognosis-v2-hip-aki-pub-reuse-map.md`。

## 本目录还保留什么

| 文件 | 角色 |
|------|------|
| `remirror_hip_aki_pub.R` | **Hip AKI 本题总装**（表图 + 挂 S3/S5/S6–S8 薄封装 + finalize） |
| `run_prognosis_v2_hip_aki.R` | Hip AKI 分析 runner |
| `_rebuild_tables5_hip_aki.R` | 薄：90 天 S5 宽表 |
| `_rebuild_s6_s7_s8_hip_aki.R` | 薄：S6/S7/S8 |
| `_rebuild_tables3_hip_aki.R` | 薄：S3 Model4 |
| `_refresh_image_info_hip_aki.R` | 本题图注文案（数字来自产物） |
| `pv2_mi_cox.R` / `pv2_s6_s7_s8.R` 等 | 血脂等多库课题既有入口 |
| `_archive_oneoff_20261023/` | 已废一次性脚本，勿再跑 |

## 规则（避免再乱）

1. 新算法进 `Blocks/` 或 `R/`，课题只传暴露、中介、协变量、路径。
2. **禁止**再在 `run/prognosis_v2/` 堆 `_hotfix_*` / `_fix_*` / `_screen_*`；用完进 `_archive_oneoff_*/`。
3. 不要把可复用脚本丢到 `G:/02block_result/...`；结果目录只留 Figures/Tables/Methods/软件版本/中期 PDF。
4. Windows `Rscript.exe` 读不到 WSL 环境变量；开关用 `Sys.setenv` 写在 R 里。
5. **单库**：表/图文件名不加数据库前缀（`R/pv2_pub_names.R`）；多库才 `Table 1-NHANES.…`。
6. **插补**：默认 `m=5`。Cox 必须 Rubin 合并；Boruta/图可用 complete#1。
7. **S7/S8 协变量必须与脚注一致**：默认同 Table 3 Model 3；若因概念重叠（如 CHARLSON vs OASIS）改用 Model 2，脚注写明 Model 2 + 理由，**禁止**假称 Model 3 /「与 Table 2 一致」，也禁止把概念重叠写成假 VIF 共线。
8. **收尾必跑** `pv2_pub_p0_gate()`（KM=锁定 scheme、Fig6=S8 Direct、Fig7 对比+P-int、RCS P-linear、禁下划线、PH/Methods）。
