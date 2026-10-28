# 发表收口入口（全项目复用）

本目录 + `R/pub_*.R` 是**唯一**发表收口引擎入口。课题目录不要再堆 `hotfix_*.R`。

## 自动挂点（跑完即触发结构 QC）

| 挂点 | 文件 |
|------|------|
| 单库 `run_pipeline` 收尾 | `R/pipeline_runner.R` → `pub_qc_run_after_project()` |
| dual-batch 指标 finalize | `R/incidence_dual_batch_runner.R` |
| TST summary | `Blocks/71_…/12block_tst_summary_results.R` |
| CLI | `Rscript run/pub/run_pub_qc_after_project.R --project <根>` |
| Nature 两方面机器扫描（DPI 修复 + xlsx） | `python3 python/nature_two_aspect_scan.py --project <根> --repair` |
| 函数 | `R/pub_qc_after_finalize.R` |

关闭：`config$pub$auto_qc = FALSE` 或 `MEDICAL_BLOCKS_AUTO_PUB_QC=0`。

结构报告：`reports/pub_qc_YYYY-MM-DD.md`。Agent 须继续按  
`.cursor/skills/pub-qc-after-project` + `nature-statistics` + `nature-figure` 修清 P0。

## 常用 CLI

```bash
# 结构 QC + nature stub
Rscript run/pub/run_pub_qc_after_project.R --project /mnt/g/02block_result/<课题>

# 四目录 / image_information 补刷
Rscript run/pub/refresh_image_information.R --dir ".../Figures"
Rscript run/pub/repair_zero_tiffs.R --dir ".../Figures"

# 文献 wide 表
Rscript run/pub/rebuild_lit_publication_tables.R   # 见 README_lit_tables.md

# 发病/预后收口（默认写 by_index/【success】*/summary_results/ 白名单五件套；
# SA_complete_case 显著优先晋升，否则回退其它 SA；legacy Fig1→pv2）
# 复用地图：docs/reuse/2026-10-23-incidence-index-summary-delivery-reuse-map.md
Rscript run/incidence/finalize_summary_result.R \
  --project /mnt/g/02block_result/<课题> \
  [--index INDEX] [--redraw-fig1] [--config path/to/config.R]

# ML 文献终稿收口（重编号填空号 + Methods/软件版本 + summary_result）
# build_aki_sosm_wpr_replication.R 原子替换后自动挂；也可单独重跑：
Rscript run/ml/finalize_ml_literature_publication.R \
  --pub ".../by_index/【success】INDEX/publication_literature_final"

# 交付根白名单收口（主入口；只留 Figures/Tables/方法md/软件版本txt/中期PDF）
# 复用地图：docs/reuse/2026-10-22-ml-lit-delivery-whitelist-reuse-map.md
# ML 单库指标级：docs/reuse/2026-10-23-ml-single-summary-results-delivery-reuse-map.md
Rscript run/pub/finalize_delivery_root.R --dir ".../summary_results" --study-type ml
Rscript run/pub/finalize_delivery_root.R --dir ".../summary_result" --study-type ml
# 预后 v2（如 Hip AKI）：写 Methods + 软件版本 + 四目录 + 白名单修剪
Rscript run/pub/finalize_delivery_root.R --dir ".../summary_results" \
  --study-type prognosis_v2 \
  --outcome "365-day all-cause mortality" \
  --exposure "SIRI and PIV" \
  --databases "MIMIC-IV"
# remirror_hip_aki_pub.R 收尾已自动调用上述 finalize（含 image_information 刷新）
# 数据库池化 / BlendedLoS（Methods=`R/pub_dbpool_methods.R`；薄封装见 run/dbpool/）：
Rscript run/pub/finalize_delivery_root.R --dir ".../summary_results" --study-type dbpool
Rscript run/dbpool/finalize_summary_delivery.R --dir ".../summary_results"
# 复用地图：docs/reuse/2026-10-26-dbpool-delivery-midterm-reuse-map.md
# 仅修剪 / 扫课题下全部 summary_result*：
Rscript run/pub/finalize_delivery_root.R --dir ".../summary_result" --prune-only
Rscript run/pub/finalize_delivery_root.R --project /mnt/g/02block_result/<课题> --prune-only
# （prune_delivery_root.R 仅为兼容别名，内部转调 --prune-only）
# xlsx 外科修复（勿 write.xlsx 整表覆盖）
Rscript run/pub/surgical_xlsx_repair.R --xlsx "..." --set ...
```

## 引擎能力（改这里，勿课题复制）

| 能力 | 入口 |
|------|------|
| 禁下划线展示 | `pipeline_display_label` / `pipeline_scrub_pub_df`（`R/utils.R`） |
| SCI 三线 xlsx | `sci_xlsx_single_header_booktabs` / `write_table1_xlsx_guan_style` |
| xlsx drawing 残片修复 | `R/competing_supp_xlsx.R` → `.competing_xlsx_fix_drawings`（写完自动调；勿 ElementTree 改 sheet） |
| 图四目录 + **dpi≥600** | `R/pub_figure_export.R` → `export_pub_figures` / `pub_figure_ensure_formats` / `formats_status$bad_dpi` |
| 预后纳排图版式 + 底账 | `R/attrition_log.R` → `attrition_draw_outcome_figure` / `attrition_write_outcome_ledger` |
| 多库 Cox RCS 面板 | `Blocks/15_rcs/05block_rcs_cox_models_panel.R` → `rcs_cox_models_panel_fit` / `_plot` |
| 多库相关 + Cox 中介 | `Blocks/20_mediation/13block_mediation_multi_db_cox.R` → `mediation_multi_db_cox_run` / `_write_xlsx` |
| 竞争风险事件过少脚注 | `R/pub_figure_export.R` → `pub_competing_sparse_footnote` |
| 软件版本 | `R/pub_software_versions.R` → `pub_write_software_versions` / `pub_write_methods_software_section` |
| TST Methods 防再审 gates | `R/pub_tst_methods.R` + `configs/templates/Methods_tst_reporting_gates.template.md`（Figure vs Table、外验首末数、负 NRI、Software 白名单） |
| 双库 IPW 拼图 / summary_result | `R/ipw_dual_db_pub.R` |
| 发病/预后指标级 summary_results（含 SA_complete_case） | `R/ml_index_summary_results.R`（默认开）+ `R/incidence_summary_result.R`；CLI `run/incidence/finalize_summary_result.R` |
| xlsx strip（悬空 drawing / 未声明 ns1） | `R/pub_xlsx_tools/xlsx_strip.py` ← finalize 拷表后自动调 |
| image_information 中介表号/箱线分组 | `R/pub_figure_export.R`（按 Tables 文件名解析 Table S#；CHARLS 库名） |
| ML 单库指标 summary_results（Methods+软件版本+白名单） | `R/ml_index_summary_results.R` → worker finalize 自动挂；启用时跳过课题根 `summary_result/` |
| 结构 QC | `R/pub_qc_after_finalize.R` + 本目录 `run_pub_qc_after_project.R` |
| Nature 两方面机器扫描 | `python/nature_two_aspect_scan.py`（finalize 后自动 `--repair`） |
| 交付白名单修剪 | `R/pub_delivery_prune.R` + `finalize_delivery_root.R` |
| 数据库池化 Methods + 收口 | `R/pub_dbpool_methods.R` + `run/dbpool/finalize_summary_delivery.R`（`--study-type dbpool`） |
| ML 文献终稿（重编号+Methods+summary） | `R/ml_literature_pub_finalize.R` + `run/ml/finalize_ml_literature_publication.R` |
| 规则 | `.cursor/rules/nature_pub_qc_after_project.mdc`、`pub_delivery_whitelist.mdc`、`pub_figure_three_formats.mdc`、`ipw_dual_db_pub_reuse.mdc`、`pub_no_underscore_display.mdc` |

## 课题特例

病种定稿重画（如胆结石 Chen 样式）放在 `run/<disease>_*/`，且**必须调用**上表引擎函数；一次性脚本进 `_archive_oneoff/`。
