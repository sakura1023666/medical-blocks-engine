# 复用地图：TCF 发表重建 + PDF-only 交付（2026-11-02）

沉淀自 Wang 2025 SA-AKI TCF（PMID 40295871，MIMIC+eICU）对话。
**新 TCF / 多算法融合课题直接走引擎，勿在 `02block_result/.../scripts/` 堆完整重建逻辑。**

## 本轮上收了什么

| 能力 | 引擎位置 | 说明 |
|------|----------|------|
| Fig1–6 + S1–S7 重建 | `python/ml_tcf/pub/rebuild_wang2025_figures.py` | bootstrap CI / 图例种子与表同源；Fig6 **不含** Training 表观 AUC |
| S1–S13 + Table1/2 计算 | `python/ml_tcf/pub/rebuild_wang2025_tables_compute.py` | 写 `_tables_rebuild_workspace/wang_payloads/` |
| 分层 bootstrap 种子 | `python/ml_tcf/pub/bootstrap.py` | Internal=0, C1=2, C2=3, eICU=4；`n_boot=400, seed=42` |
| 表 xlsx 组装 | `run/ml_tcf_sepsis_aki/rebuild_wang2025_tables_core.R` | `export_sci_table` 三线表 |
| 薄入口 | `run/ml_tcf_sepsis_aki/rebuild_wang2025_{figures,tables}.R` | 课题 scripts 只 redirect |
| Methods（TCF） | `R/ml_index_summary_results.R` → `ml_index_methods_statistical_lines_tcf` | `config$methods$kind = "tcf"` |
| 默认 PDF-only | `R/pub_figure_export.R` | `export_png/export_tiff` 默认 `FALSE` |
| 交付白名单 | `R/pub_delivery_prune.R` | Figures/Tables/Methods md/软件 txt/中期（+Shiny 若有） |
| 规则 | `pub_figure_three_formats.mdc` / `pub_delivery_whitelist.mdc` | 全项目 |

## 课题侧只留什么

结果目录 `scripts/`：

- `rebuild_wang2025_tcf_figures.py` → redirect 引擎
- `rebuild_wang2025_tcf_tables_compute.py` → redirect 引擎
- `rebuild_wang2025_tcf_tables.R` → redirect 引擎
- 旧 `.bak_*` → `scripts/_archive_oneoff_YYYY-MM-DD/`（禁止当真相源）

config：

```r
methods = list(kind = "tcf"),
pub_figures = list(
  formats_dir = TRUE,
  dpi = 600L,
  write_image_information = TRUE,
  export_png = FALSE,
  export_tiff = FALSE
)
```

模板：`configs/templates/config_ml_tcf_sepsis_aki_batch.template.R`。

## 常用命令

```bash
export MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final
SUCCESS="…/by_index/【success】ALLVARS"

# 图（PDF + image_information）
Rscript "$MEDICAL_BLOCKS_ROOT/run/ml_tcf_sepsis_aki/rebuild_wang2025_figures.R" \
  --success-root "$SUCCESS"

# 表（SCI xlsx；内部调 engine tables_compute）
Rscript "$MEDICAL_BLOCKS_ROOT/run/ml_tcf_sepsis_aki/rebuild_wang2025_tables.R" \
  --success-root "$SUCCESS"

# 交付收口
Rscript "$MEDICAL_BLOCKS_ROOT/run/pub/finalize_delivery_root.R" \
  --dir "$SUCCESS/summary_results" --study-type ml
```

## Bootstrap 锁（勿再分叉）

- Table 2 TCF / Table S10 Internal / Fig5 图例 / Fig6 Internal：**同一** Internal AUC CI 字符串
- 种子偏移：`SEED_OFF_INTERNAL=0`, `C1=2`, `C2=3`（**禁止**再用 0/1/2 与 S10 错位）
- Fig6：**不要**画 Training 表观 AUC（≈1）；S10 可留 apparent 行 + Methods Limitations

## 新课题检查清单

- [ ] 未复制整份 `rebuild_wang2025_*` 进下一课题 scripts
- [ ] `methods$kind = "tcf"`（Methods 不是 Cox 模板）
- [ ] `export_png/tiff = FALSE`（除非期刊点名）
- [ ] 改种子只改 `python/ml_tcf/pub/bootstrap.py`
- [ ] 交付根无 `reports/` / `content.json` / 旧 png·tiff 残留（默认模式会 drop raster dirs）

## 反例（禁止）

- 在 G: `scripts/` 继续改业务逻辑，引擎副本落后
- Table2 与 Fig5 各用一套 `seed+day` / 不同 stratum offset
- Fig6 把 Training AUC=0.999 当外推表现
- Methods 仍是「Cox / landmark」却跑的是 TCF+TOPSIS
