# SAR+CrCV 一次性脚本（已归档，勿当正式入口）

本目录为 2026-10 AKI SAR+CrCV 对话中的 `/tmp`、结果目录草稿、以及被正式入口取代的 `run/ml` 旧脚本。

## 可复用能力（请走这里）

| 能力 | 入口 |
|------|------|
| literature_m123 + Model3 踢严重度 | `R/ml_assoc_covariate_rule.R` + `configs/ml_literature_aki_dev_ext_assoc_overrides.R` |
| 统一重算表+Fig3/6 | `run/ml/rebuild_assoc_unified_model3.R` |
| 关联图重画+Fig8 栅格 | `run/ml/redraw_assoc_figs.R` |
| PDF 文本层栅格 | `R/pub_figure_export.R` → `pub_figure_rasterize_pdf_page` |
| 交付白名单 | `docs/reuse/2026-10-22-ml-lit-delivery-whitelist-reuse-map.md` |
| **本轮复用地图** | `docs/reuse/2026-10-26-ml-literature-m123-assoc-reuse-map.md` |
| `run/ml` 目录说明 | `run/ml/README.md` |

## 子目录

| 目录 | 内容 |
|------|------|
| `run_ml_superseded/` | 旧 `rebuild_joint_*`、`redraw_sar_crcv_*`、`fix_fig4_*`、`redraw_fig2/8_*` 等 |
| `tmp_oneoff/` | 从 `/tmp` 拷贝的草稿 |
| `lit_pub_SAR_CrCV/` | 课题中间表样例 |

禁止把本目录脚本复制到下一课题 `scripts/` 当长期方案。
