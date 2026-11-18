# 复用地图：ML 单库 summary_results 交付白名单（2026-10-23）

沉淀自听力损失 TyG_WHtR / HHR NHANES 单库 ML 对话。**新课题直接走引擎，勿再抄结果目录或 `/tmp` 脚本。**

## 客户交付面（唯一）

路径：`by_index/【success】<INDEX>/summary_results/`

| 保留 | 说明 |
|------|------|
| `Figures/` | pdf/png/tiff/image_information |
| `Tables/` | 仅发表 `.xlsx` |
| `Methods_statistical_analysis.md` | 方法（含 `## Software`） |
| `Methods_software_versions.txt` | 软件版本 |
| `*中期*.pdf` | 中期 PDF（Phase 7 Agent 出完后再 prune） |

**禁止**再把课题根 `summary_result/` 当客户交付（ML 单库已跳过该路径）。

## 引擎入口（改这里，勿课题复制）

| 能力 | 文件 |
|------|------|
| 指标级 sync 表图 + 写 Methods + 软件版本 + 白名单 prune | `R/ml_index_summary_results.R` → `ml_finalize_index_summary_results` / `ml_index_methods_statistical_lines` |
| Worker finalize 自动挂点 | `R/incidence_dual_batch_runner.R`（`mirror_aggregate=FALSE` 与双库收尾两处） |
| ML 启用时跳过课题根 `summary_result/` | 同上 → `incidence_batch_finalize_summary_result` 开头门控 |
| 交付 CLI（补写/修剪） | `run/pub/finalize_delivery_root.R --dir …/summary_results --study-type ml` |
| 白名单实现 | `R/pub_delivery_prune.R` |
| 单库模板开关 | `configs/templates/config_ml_single_batch.template.R` → `write_index_summary_results = TRUE` |
| Cursor 规则 | `.cursor/rules/pub_delivery_whitelist.mdc` |
| 与文献终稿白名单总表 | `docs/reuse/2026-10-22-ml-lit-delivery-whitelist-reuse-map.md` |

## 本对话「结果 / tmp」≠ 引擎

下列**不要**复用到下一课题：

| 路径 | 处理 |
|------|------|
| 课题 `…/ml_tyg_whtr_nhanes_single/summary_result/`（根级双份） | 归档到课题 `_archive_oneoff/`，交付只用指标级 `summary_results` |
| 课题 `reports/nature_*` / `pub_qc_*` / 中期 `content.json` | 课题产物；QC 留 reports，中期工作区进 `summary_results_delivery_workspace/` |
| `01Block-new-Final/tmp/curate_hhr_*.R`、`tmp/ml_hhr_tabpfn_*.log`、`tmp/restore_charls_*.R` | 一次性 → `_archive_oneoff/ml_hhr_tyg_2026-10/` |
| `/tmp/midterm_tyg_build.log` 等 | 日志，可删 |

## 新课题检查

- [ ] config：`write_index_summary_results = TRUE`（单库模板默认）
- [ ] finalize 后只有 `by_index/【success】*/summary_results/` 五类白名单，**无**课题根第二份 `summary_result/`
- [ ] 未从 `tmp/` 或课题 `scripts/` 抄 prune/Methods hotfix
- [ ] 中期 PDF 写进 `summary_results` 后再 `finalize_delivery_root.R --prune-only`

## 反例

- 客户打开课题根 `summary_result/`（表号重复、缺中期）却当交付
- finalize 后又在结果目录手写 `Methods_*.md` 绕过 `ml_index_methods_statistical_lines`
- 把 `tmp/curate_hhr_*.R` 当下一指标长期方案
