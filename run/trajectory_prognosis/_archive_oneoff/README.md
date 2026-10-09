# 归档：轨迹课题一过性 repair / fix 脚本

本目录脚本是对话中为 **GPR**、**AP WPR dual** 等课题临时写的 hotfix，**能力已回写引擎**，新课题勿再调用。

## 已融入引擎

| 旧脚本 | 已融入 |
|--------|--------|
| `repair_gpr_pub_style_fix.R` | `R/trajectory_pub_finalize.R`（CONSORT Fig1、竖拼）+ `R/pub_figure_export.R` |
| `repair_gpr_restore_13figs.R` | `trajectory_paper_figure_stems` / `trajectory_enforce_paper_figures` |
| `repair_gpr_s3_shared_cut.R` | `trajectory_resolve_shared_piecewise_cut` / `trajectory_apply_shared_piecewise_cut` |
| `align_ap_wpr_dual_pub_to_reference.R` | finalize + `dual_db_combine_paired_figures` |
| `fix_ap_wpr_dual_drop_s1_align_tables.R` | `R/trajectory_dual_pub_harmonize.R` → `align_dual_tables` + `drop_missing_overview` |
| `fix_ap_wpr_dual_pub_consistency.R` | finalize：`root_keep_db`、亚组锁名单走 config、Fig1 attrition |
| `fix_ap_wpr_dual_table_s9.R` | `trajectory_parse_uv_hr_cell()`（优先 `p=` 单元格） |
| `fix_ap_wpr_dual_fig2_class_labels.R` | `config$trajectory$skip_class_swap=TRUE`（已有） |
| `rebuild_ap_wpr_table_s5_like_table1.R` | 对齐走 `align_dual_tables`；按类基线重导仍用 block `trajectory_baseline_by_class` |
| `repair_gpr_*class*.R` / fig* | 课题重跑；正式入口仍是 batch worker + finalize |

## 新课题请用

```bash
Rscript run/trajectory_prognosis/finalize_trajectory_pub.R \
  --index-root <by_index/【success】INDEX> \
  --config <study/config.R>
```

或在 `config$trajectory_pub` 开启后让 worker 成功尾自动 finalize。

规则：`.cursor/rules/trajectory_pub_reuse.mdc`  
设计：`docs/superpowers/specs/2026-09-28-trajectory-dual-pub-harmonize-design.md`
