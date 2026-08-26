# Task 6 Report: NHANES / IPTW RCS panel_stats 对齐

**Date:** 2026-08-26  
**Status:** DONE

## Summary

在 `03block_rcs_nhanes.R` 与 `04block_rcs_iptw_weighted.R` 写 results 处，从已有 svyglm `p_overall` / `p_nonlin` 与 `cut_use$all` 构造 `rcs_*_panel_stats`（Crude/Model1/Model2，可选 Model3），不重算模型。Harvest 键 `rcs_nhanes_panel_stats` / `rcs_iptw_panel_stats` 已在 `R/pub_figure_export.R` `.PUB_FIGURE_RCS_PANEL_STATS_KEYS` 中，无需改动。

## Files Changed

| File | Change |
|------|--------|
| `Blocks/15_rcs/03block_rcs_nhanes.R` | 写入 `ctx$results$rcs_nhanes_panel_stats` |
| `Blocks/15_rcs/04block_rcs_iptw_weighted.R` | 写入 `ctx$results$rcs_iptw_panel_stats` |
| `tests/test_pub_figure_onplot_annotations.R` | checkpoints/nhanes fixture + harvest 断言 |

## Tests

```bash
Rscript tests/test_pub_figure_onplot_annotations.R
# test_pub_figure_onplot_annotations: OK
```

## Concerns

1. **`db_lab` 映射：** harvest 仍将 `checkpoints/.../nhanes` 的 basename 规范为 `eICU`（Task 3 遗留）；fixture 独立运行可验键，生产 md 库标签可能不准。
2. **`db_dirs` 未含 `index_root/NHANES`：** 仅扫 checkpoints/nhanes；by_index 直挂 NHANES 目录仍不可 harvest。
3. **Model2 cutoffs 用 `cut_use$all`：** 与 prognosis 一致；若 Model3 显著且切点来自 Model3，Model2 panel 的 cutoffs 与图 C 竖线可能不一致（incidence 用 resC 专属 cutoffs）。

## Commits

None (per constraint).
