# 发表收口入口（全项目复用）

本目录 + `R/pub_*.R` 是**唯一**发表收口引擎入口。课题目录不要再堆 `hotfix_*.R`。

## 自动挂点（跑完即触发结构 QC）

| 挂点 | 文件 |
|------|------|
| 单库 `run_pipeline` 收尾 | `R/pipeline_runner.R` → `pub_qc_run_after_project()` |
| dual-batch 指标 finalize | `R/incidence_dual_batch_runner.R` |
| TST summary | `Blocks/71_…/12block_tst_summary_results.R` |
| CLI | `Rscript run/pub/run_pub_qc_after_project.R --project <根>` |
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

# xlsx 外科修复（勿 write.xlsx 整表覆盖）
Rscript run/pub/surgical_xlsx_repair.R --xlsx "..." --set ...
```

## 引擎能力（改这里，勿课题复制）

| 能力 | 入口 |
|------|------|
| 禁下划线展示 | `pipeline_display_label` / `pipeline_scrub_pub_df`（`R/utils.R`） |
| SCI 三线 xlsx | `sci_xlsx_single_header_booktabs` / `write_table1_xlsx_guan_style` |
| 图四目录 | `R/pub_figure_export.R` → `export_pub_figures` / `pub_figure_ensure_formats` |
| 软件版本 | `R/pub_software_versions.R` → `pub_write_software_versions` / `pub_write_methods_software_section` |
| 规则 | `.cursor/rules/nature_pub_qc_after_project.mdc`、`pub_no_underscore_display.mdc`、`pub_figure_*` |

## 课题特例

病种定稿重画（如胆结石 Chen 样式）放在 `run/<disease>_*/`，且**必须调用**上表引擎函数；一次性脚本进 `_archive_oneoff/`。
