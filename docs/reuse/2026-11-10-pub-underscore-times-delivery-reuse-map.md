# 发表展示禁下划线 · Times New Roman · 交付白名单（2026-11-10）

沉淀自脓毒症 Jin / WPR 双库交付收口。**新课题直接走引擎**，勿再堆 `/tmp/wpr_*` 或课题 `scripts/` hotfix。

## 已进引擎（勿课题私改绕过）

| 能力 | 入口 |
|------|------|
| 导表禁 `_` | `pipeline_display_label` / `pipeline_scrub_pub_df`（`R/utils.R`）；`sci_xlsx_*` |
| 已落盘 xlsx 外科 scrub | `R/pub_xlsx_surgical.R` → `pub_xlsx_scrub_underscores(_dir)` |
| 收口统一 scrub | `R/pub_delivery_prune.R` → `pub_delivery_scrub_tables_underscores` |
| 挂点 | `ml_finalize_index_summary_results`；`run/pub/finalize_delivery_root.R`（含 `--prune-only`） |
| Layer A3 质控 | `R/pub_qc_underscore.R` → `pub_qc_run_after_project` |
| Times New Roman | `sci_xlsx_*` / `resolve_plot_font_family` / `pipeline_pdf_device`；规则 `pub_times_new_roman.mdc` |
| 交付白名单五件套 | `pub_prune_delivery_root`；规则 `pub_delivery_whitelist.mdc` |
| QC 读 `max_edge_in` | `run/pub/run_pub_qc_after_project.R`（缺省 16） |
| Nature + 中期 | `nature_pub_qc_after_project.mdc` → `midterm_after_pub_qc.mdc` |

## 正式入口（每课题跑完）

```bash
# 指标 finalize 已自动：scrub + Methods/软件版本 + prune
# 补收口 / 只修剪：
Rscript run/pub/finalize_delivery_root.R --dir ".../summary_results" --prune-only

# 结构 QC（含禁下划线）：
Rscript run/pub/run_pub_qc_after_project.R --project ".../课题根"
```

## 铁律

1. **禁止**在 `/tmp` 或课题目录长期留 `wpr_fix_*.R` / `compose_*.py` 当正式入口。
2. **禁止** `write.xlsx` 整表覆盖已发表 SCI 三线表；返工用 `pub_xlsx_*`。
3. **`summary_results` 根**只留：Figures / Tables / Methods md / 软件版本 txt / 中期 PDF（ML 有网页时另可 Shiny）。
4. 图字体走 `resolve_plot_font_family`；表样式 `fontName = "Times New Roman"`。

## 本轮一次性脚本去向

| 原位置 | 处理 |
|--------|------|
| `/tmp/wpr_*`（compose/finalize/fix_p0 等） | 归档 `run/sepsis_jin_prognosis/_archive_oneoff/2026-11-10_wpr_session/`；**勿当入口** |
| `run/sepsis_jin_prognosis/repair_wpr_content_gaps.R` | 移入同目录 `_archive_oneoff/`（WPR 内容补洞一次性） |

## 检查清单

- [ ] 新跑指标 `summary_results` 经 finalize 后无编程 `_`（或 QC A3 PASS）
- [ ] 表 xlsx / 图 PDF 为 Times 系
- [ ] 交付根无 `content.json` / `_report_dump` / `reports/`
- [ ] 未复活 `/tmp/wpr_*` 当正式流水线
