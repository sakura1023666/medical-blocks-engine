# Task 5 Report: `rcs_incidence_panel_stats`

## Status
**Done** — LRM anova extractor + block write + tests pass.

## Changes

| File | Change |
|------|--------|
| `R/pub_figure_export.R` | Added `.pub_figure_extract_lrm_anova_p(an)` (`an[nrow(an),3]`, `an[2,3]`) |
| `Blocks/15_rcs/02block_rcs_incidence.R` | After fits, writes `ctx$results$rcs_incidence_panel_stats` (Crude/Model1/Model2) |
| `tests/test_pub_figure_onplot_annotations.R` | TDD: `fake_an` extractor + eICU `rcs_incidence.rds` harvest fixture |

## Panel stats schema

```r
list(
  Crude  = list(p_overall, p_nonlinear, cutoffs = numeric(0)),
  Model1 = list(p_overall, p_nonlinear, cutoffs = numeric(0)),
  Model2 = list(p_overall, p_nonlinear, cutoffs = resC$cutoffs$all)
)
```

P 值与图注同源（`an[nrow(an),3]` / `an[2,3]`），标签仍为 `P-overall` / `P-non-linear`。

## Tests

```bash
Rscript tests/test_pub_figure_onplot_annotations.R
# test_pub_figure_onplot_annotations: OK
```

## Commits
None (per task constraint).

## Concerns
- 无 Model3 条目（brief 未要求；prognosis 有可选 Model3）。
- Block 级单元测试未加（无轻量 lrm fixture）；harvest 路径已由 eICU fixture 覆盖。
- Harvest 每库只保留首个含 `rcs_*_panel_stats` 的 rds（prognosis / incidence 不可同库并存于 harvest 输出）。
