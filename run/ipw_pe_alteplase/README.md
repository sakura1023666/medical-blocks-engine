# PE × alteplase IPW（双库）— 正式入口

可复用逻辑已进引擎；本目录只保留**本课题入口**。新 IPW 双库课题请读  
`docs/reuse/2026-10-10-ipw-dual-db-600dpi-reuse-map.md` 与  
`.cursor/rules/ipw_dual_db_pub_reuse.mdc`。

## 保留（用这些）

| 文件 | 作用 |
|------|------|
| `run_ipw_pe_alteplase_batch.R` | 批跑入口 |
| `run_ipw_pe_alteplase_batch_worker.R` | 单库 worker |
| `remirror_dual_panel_figures.R` | 薄封装 → `R/ipw_dual_db_pub.R::ipw_dual_panel_remirror` |
| `finalize_summary_result.R` | 薄封装 → `ipw_finalize_summary_result` + 本课题 Methods 文案 |
| `curate_pub_tables.R` / `curate_supp_tables_jin4.R` | Jin 表序整理（课题可选） |

## 已归档（勿当长期方案）

`_archive_oneoff/`：`repair_*` / `rerun_*` / `restore_*` — 本轮修表键/单步重跑痕迹，新课题禁止复制。

## 引擎（之后所有项目）

| 能力 | 入口 |
|------|------|
| IPW KM log-rank p（svylogrank 取 p 非 Chisq） | `Blocks/69_…/03block_ipw_weighted_km_pub.R` |
| Flowchart 暴露自适应标签 | `Blocks/69_…/02block_ipw_flowchart.R` |
| 阿替普酶暴露块 | `Blocks/69_…/10block_ipw_alteplase_exposure.R` |
| 预后亚组 IPTW → HR；退化 NE | `Blocks/18_subgroup/08block_subgroup_iptw_weighted.R` |
| 双库拼图 + summary_result | `R/ipw_dual_db_pub.R` |
| png/tiff ≥600 dpi | `R/pub_figure_export.R` + `python/pub_figure_rasterize.py` |
| 结构 QC CLI | `run/pub/run_pub_qc_after_project.R` |
| 模板 | `configs/templates/config_ipw_pe_alteplase_dual_batch.template.R` |

## 推荐顺序

```bash
# 1) workers（shared-only → full）
Rscript run/ipw_pe_alteplase/run_ipw_pe_alteplase_batch.R --config …

# 2) 拼图
Rscript run/ipw_pe_alteplase/remirror_dual_panel_figures.R --project <课题根>

# 3) summary_result
Rscript run/ipw_pe_alteplase/finalize_summary_result.R --project <课题根>

# 4) 结构 QC（DPI≥600）
Rscript run/pub/run_pub_qc_after_project.R --project <课题根>
# Agent Layer D：nature-statistics + nature-figure
```
