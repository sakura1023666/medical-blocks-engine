# 胆结石碎石成功列线图（课题入口）

> 引擎复用能力见 `run/pub/README.md` 与 `R/utils.R`（禁下划线 / SCI xlsx / pub-qc）。  
> 本目录只保留**本病**批跑与 Chen 文献对齐重画。

## 现行入口（请只认这些）

| 脚本 | 用途 |
|------|------|
| `run_gallstone_nomogram_batch.R` | 批跑 / shared+workers |
| `rebuild_all_pub_figures_lit.R` | Fig2–9 + S1/S2 Chen 样式重画（调用引擎四目录 + pub-qc） |
| `export_tables_sci_xlsx.R` | Table1–2 / S1–S4 → SCI xlsx（`pipeline_scrub_pub_df`） |
| `refresh_image_information_lit.R` | 本病图注（暴露/N）；通用补刷请用 `run/pub/refresh_image_information.R` |

展示名字典：`R/literature_gallstone_nomogram.R` → `gallstone_nomogram_display_labels()`。

## 已归档（勿再当主入口）

`_archive_oneoff/`：

- `relock_figures_lit_numbering.R`
- `reorganize_publication_layout.R`
- `reorganize_tables_chen_order.R`
- `rebuild_summary_lit_aligned.R`

历史一次性整理脚本；逻辑已并入上面现行入口或引擎。

## 产出根

默认：`/mnt/g/02block_result/45_Gallstone/Nomogram_41815074/summary_results/`
