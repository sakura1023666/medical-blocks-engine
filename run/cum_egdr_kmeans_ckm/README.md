# run/cum_egdr_kmeans_ckm

累积暴露 × k-means（CKM/卒中或 ELSA/骨质疏松）发表流水线入口。  
**可复用逻辑在引擎 `R/` + `Blocks/76/`**；本目录只留批跑与发表重导入口。

## 正式入口（只用这些）

| 脚本 | 用途 |
|------|------|
| `run_cum_egdr_kmeans_ckm_batch.R` | Shared + workers 批跑 `Blocks/76` |
| `rebuild_publication.R` | CHARLS/CKM eGDR 发表重导 |
| `rebuild_publication_elsa_osteoporosis.R` | ELSA 骨质疏松多指标发表重导（扫全部 `【success】`） |
| `redraw_elsa_fig3_s123_all_success.R` | 只重画 Fig3/S1–S3（RCS 3 knots；Overall\|BMI&lt;30\|Age≥60；S1 访视月 futime） |

```bash
# 批跑
Rscript run/cum_egdr_kmeans_ckm/run_cum_egdr_kmeans_ckm_batch.R \
  --config "<project>/configs/config_*.R" --workers auto

# 批跑后必做发表定稿（CHARLS）
Rscript run/cum_egdr_kmeans_ckm/rebuild_publication.R

# ELSA 骨质疏松多指标
Rscript run/cum_egdr_kmeans_ckm/rebuild_publication_elsa_osteoporosis.R
# 或只画 Fig3/S1–S3
Rscript run/cum_egdr_kmeans_ckm/redraw_elsa_fig3_s123_all_success.R
Rscript run/cum_egdr_kmeans_ckm/redraw_elsa_fig3_s123_all_success.R --index WWI,AIP
```

## 引擎复用点（新课题直接用，勿再写 tmp hotfix）

| 能力 | 入口 |
|------|------|
| `age_filter`（如 `Age >= 50`）在 ingest 落实 | `Blocks/76/.../01block_ckm_stroke_data_ingest.R` + config `data_clean$age_filter` |
| Hypertension_w4 → Hypertension | `R/literature_ckm_cum_egdr.R` → `ckm_stroke_harmonize_columns` |
| uv_vif 前列对齐 | `Blocks/76/.../05block_logistic_cum_index_bundle.R` |
| Table2/S1 指标名（非写死 eGDR） | `R/cum_egdr_kmeans_pub.R` → `ckm_stroke_build_table2_assoc(..., index_lab=)` |
| Methods 软件版本 | `ckm_stroke_write_software_versions` / `ckm_stroke_software_footnote` |
| Table1 章节加粗 | `ckm_stroke_style_table1_xlsx` |
| RCS P/Ref 区外标注（防 collision） | `ckm_stroke_rcs_one_panel`（subtitle + caption） |
| 森林 Never/Ever、en-dash | `ckm_stroke_forest_free_stats` |
| 中间 CSV 进 `_internal` / 归档 | rebuild 脚本 + `ckm_stroke_clean_summary_junk` |
| Age≥50 日志标签 | `Blocks/02_data_clean/01block_data_clean.R` |

模板：`configs/templates/config_cum_egdr_kmeans_ckm_batch.template.R`  
铁律摘要：`.cursor/rules/cum_egdr_kmeans_pub_reuse.mdc`

## Helpers

- `R/literature_ckm_cum_egdr.R` — 宽表/对齐/kmeans/OR-HR/uv_vif
- `R/cum_egdr_kmeans_pub.R` — 发表表图（rebuild 与 Blocks 共用）

## `_archive/`（勿复活）

逻辑已沉入 helpers / 正式入口，仅考古：

- `rebuild_pub_tables_fig2.R` / `rebuild_figures_match_paper.R` / `rebuild_summary_publication.R`
- `redraw_wwi_figures.R`（已被 `redraw_elsa_fig3_s123_all_success.R` 替代）

**禁止**再在 `tmp/` 或课题 `scripts/` 堆一次性 hotfix；可复用改动必须回写上表入口。
