# Task 9 report

## Tests run
```
Rscript tests/test_pub_figure_onplot_annotations.R  → OK
Rscript tests/test_pub_figure_export.R              → OK
Rscript tests/test_pub_figure_profile_gate.R        → OK profile gate
```

## Spec coverage
- Flowchart: existing attrition (unchanged)
- RCS/KM/Forest/ROC/maxstat: 图上标注 wired
- Cursor rule #7: done
- No mass refresh of old studies
- No fake P without panel_stats

## Status
DONE

---

## Post-review fix (Important #1 + #2) — 2026-08-26

### #1 panel_stats cutoffs = on-plot vlines only
- Shared: `R/pub_figure_export.R` `.pub_figure_rcs_vline_cutoffs(cutoffs, mode)` / `.pub_figure_rcs_panel_vline_cutoffs(..., show_vlines)`.
  - `primary`：与 `rcs_primary_cutoff` / `.rci01_add_cutoff_vlines` 相同（or1 单点 → peak[1] → or1[1] → all[1]）。
  - `all`：`sort(unique(cutoffs$all))` 有限值。
  - `show_vlines=FALSE` → 空向量。
- Incidence：`cutoff_vline_mode`（默认 primary）选 xs；Model2 仅 `show_cut_c`；Model3 仅 `show_cut_d`。`.rci01_add_cutoff_vlines` 改用同一 helper。
- Prognosis / NHANES / IPTW：画 `$all`；Model2 iff `show_cut_c`，Model3 iff `show_cut_d`（不再把 `cut_use$all` 写到无竖线的 Model2）。

### #2 harvest 不再 readRDS 全部 checkpoint
- `.pub_figure_harvest_onplot_rds`：basename 匹配 `rcs|km|subgroup`（忽略大小写），保持优先序。
- `.pub_figure_harvest_skip_rest`：本库 `seen_rcs` + forest + km_binary 已齐，且剩余无名 `km*` 时 break。
- 集成：仅 `imputation.rds` 含 panel_stats 时 harvest RCS 为空。

### Test evidence
```
Rscript tests/test_pub_figure_onplot_annotations.R  → OK
  (primary vs all；show_vlines 空；onplot rds 过滤；skip_rest；imputation 不收获)
Rscript tests/test_pub_figure_export.R              → OK
parse() of pub_figure_export.R + four RCS blocks   → OK
```
未重跑 `test_pub_figure_profile_gate.R`（本补丁未改 profile gate）。无 git commit；无 mass refresh。

### Residual
- 旧 checkpoint 仍可能含「全量 all / 错面板」cutoff，须重跑对应 RCS block 后 md 才对齐。
- Forest 若只存在于不含 `rcs|km|subgroup` 的文件名将不再被收获（dual-batch 标准名为 `subgroup_*.rds`）。
