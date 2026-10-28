# 复用地图：发病/预后指标级 summary_results 交付（2026-10-23）

沉淀自 cute_ran（抑郁 HHR，NHANES+CHARLS）对话。**新课题直接走引擎，勿再抄 `/tmp` 或课题根双份 summary。**

## 客户交付面（唯一）

路径：`by_index/【success】<INDEX>/summary_results/`

| 保留 | 说明 |
|------|------|
| `Figures/` | pdf/png/tiff/image_information |
| `Tables/` | 仅发表 `.xlsx`（finalize 后自动 strip） |
| `Methods_statistical_analysis.md` | 方法（含 Software） |
| `Methods_software_versions.txt` | 软件版本 |
| `*中期*.pdf` | 中期 PDF（Phase 7 后再 prune） |

课题根 **不再** 放第二份 `summary_result` / `summary_results`（`config$pub$summary_result = FALSE` + `write_index_summary_results = TRUE`）。

## 本对话已进引擎（改这里，勿课题复制）

| 能力 | 文件 |
|------|------|
| 发病/预后默认写指标级 summary_results | `R/ml_index_summary_results.R` → `ml_index_summary_results_enabled`（incidence/survival_batch 默认 TRUE） |
| 指标级 sync + Methods + prune | `ml_finalize_index_summary_results` |
| CLI：敏感性晋升 + 指标级收口 | `run/incidence/finalize_summary_result.R` |
| SA：完整病例显著优先，否则回退其它 SA_* | `R/incidence_summary_result.R` → `incidence_promote_sensitivity_for_summary` |
| 拷表后 xlsx strip（drawing / ns1） | `R/pub_xlsx_tools/xlsx_strip.py` + `incidence_finalize_summary_result` 循环 strip |
| 中介图注跟真实 Table S#；箱线按结局分组；CHARLS 库名 | `R/pub_figure_export.R` |
| 勿因目录名 `summary_results` 自动只留图+表 | `run/incidence/finalize_summary_result.R`（仅显式 `tables_figures_only=TRUE`） |
| 模板默认 pub 块 | `configs/templates/config_incidence_dual_batch.template.R`、`config_survival_dual_batch.template.R` |
| Worker finalize 挂点 | `R/incidence_dual_batch_runner.R`（先指标级则跳过课题根） |
| 白名单 prune | `R/pub_delivery_prune.R` + `run/pub/finalize_delivery_root.R` |
| 总入口说明 | `run/pub/README.md` |

## 本对话「结果 / tmp」≠ 引擎（勿复用）

| 路径 | 处理 |
|------|------|
| `/tmp/finalize_hhr_summary_results.R` | 一次性 → 课题 `_archive_oneoff/`（已归档） |
| `/tmp/cute_ran_midterm_*`、`/tmp/finalize_cute_ran.log` | 日志/暂存，可删 |
| 课题根 `summary_results` / `summary_result`（旧双份） | 已迁到 `by_index/【success】HHR/summary_results/`；根目录归档名带 `MOVED`/`ARCHIVED` |
| `summary_results_delivery_workspace/` | 中期 content.json / dump 工作区，**不进客户交付** |
| 课题 `reports/nature_*` / `pub_qc_*` | 质控产物，留 reports，不进 summary_results |

## 新课题检查

- [ ] 用最新模板（含 `pub$write_index_summary_results = TRUE`）或接受引擎默认
- [ ] finalize 后交付只在 `by_index/【success】*/summary_results/`，五类白名单齐全
- [ ] 未从 `/tmp/finalize_hhr_*.R` 抄收口逻辑
- [ ] 中期出完后对 summary_results 再 `--prune-only`
- [ ] 未在课题 `scripts/` 堆 remirror/hotfix 当长期方案

## 正式入口（下一课题只跑这些）

```bash
# worker / batch 收尾会自动挂指标级 summary_results
# 手工补收口：
Rscript run/incidence/finalize_summary_result.R \
  --project /mnt/g/02block_result/<课题> \
  --index <INDEX> \
  --config /mnt/g/02block_result/<课题>/config_incidence_dual_batch.R

Rscript run/pub/run_pub_qc_after_project.R --project /mnt/g/02block_result/<课题>
# Agent：nature-statistics + nature-figure 修 P0 → 中期 → prune
Rscript run/pub/finalize_delivery_root.R \
  --dir ".../by_index/【success】INDEX/summary_results" --prune-only
```

## 反例

- 客户打开课题根 `summary_results/`（旧双份）当交付
- `tables_figures_only=TRUE` 长期开着导致无 Methods/软件版本/中期
- 把 `/tmp/finalize_hhr_summary_results.R` 当下一指标入口
