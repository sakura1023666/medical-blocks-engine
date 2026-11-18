# run/ml — 正式入口（跨课题复用）

**禁止**把 `/tmp`、结果目录 `scripts/`、`_archive_oneoff/` 里的草稿当下一课题入口。

## 批跑 / 正式流水线

| 用途 | 入口 |
|------|------|
| 双库 ML batch | `run_ml_dual_batch.R` + `run_ml_dual_batch_worker.R` |
| 文献终稿（重编号 + Methods + sync summary + prune） | `finalize_ml_literature_publication.R` |
| 指标 code 包 | `generate_single_pipeline_code_bundle.R` |
| AKI 文献双指标复刻 build | `build_aki_sosm_wpr_replication.R` / `build_ml_dual_literature_final.R` |

## 文献 Model1–3 统一（本轮沉淀）

| 用途 | 入口 |
|------|------|
| 统一 Model3（踢严重度）重算 Table2/S4/S8/S9 + Fig3/6 + Methods | `rebuild_assoc_unified_model3.R` |
| 关联图 Fig2/3/4/6 重画 + 可选 Fig8 文本层栅格化 | `redraw_assoc_figs.R` |
| config 片段（scheme=`literature_m123`） | `configs/ml_literature_aki_dev_ext_assoc_overrides.R` |
| 引擎规则 | `R/ml_assoc_covariate_rule.R` |
| 关联图绘制 | `R/ml_reference_assoc_figures.R` |
| PDF 文本层→image PDF（消 collision） | `R/pub_figure_export.R` → `pub_figure_rasterize_pdf_page` |
| 复用地图 | `docs/reuse/2026-10-26-ml-literature-m123-assoc-reuse-map.md` |

```bash
MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
  Rscript run/ml/rebuild_assoc_unified_model3.R \
  --study <study_root> --index A+B \
  --delivery <study>/by_index/【success】A+B

MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
  Rscript run/ml/redraw_assoc_figs.R \
  --study <study_root> --index A+B \
  --delivery <study>/by_index/【success】A+B
```

## 已归档（勿当正式入口）

`_archive_oneoff/sar_crcv_2026-10/run_ml_superseded/`：

- `rebuild_joint_table2_no_severity.R` → 被 `rebuild_assoc_unified_model3.R` 取代
- `redraw_sar_crcv_fig2346_collision.R` → 被 `redraw_assoc_figs.R` 取代
- `fix_fig4_fig6_fig7.R`、`redraw_fig2_km_pretty.R`、`redraw_fig8_compact.R`、`redraw_assoc_figs_mimic_only.R`
