# Task 4 Report: `rcs_prognosis_panel_stats`

## Status
**Done** — extractor + block write + tests pass.

## Changes

| File | Change |
|------|--------|
| `R/pub_figure_export.R` | Added `.pub_figure_extract_cox_rcs_p(p)` (`logtest[3]`, `coefficients[2,5]`) |
| `Blocks/15_rcs/01block_rcs_prognosis.R` | After fits / `cut_use`, writes `ctx$results$rcs_prognosis_panel_stats` (Crude/Model1/Model2[/Model3]) |
| `tests/test_pub_figure_onplot_annotations.R` | TDD extractor test with `fake_p` fixture |

## Panel stats schema

```r
list(
  Crude  = list(p_overall, p_nonlinear, cutoffs = numeric(0)),
  Model1 = list(p_overall, p_nonlinear, cutoffs = numeric(0)),
  Model2 = list(p_overall, p_nonlinear, cutoffs = cut_use$all),
  Model3 = ...  # optional, cutoffs empty
)
```

Block lazy-sources `R/pub_figure_export.R` if `.pub_figure_extract_cox_rcs_p` is not yet loaded.

## Tests

```bash
Rscript tests/test_pub_figure_onplot_annotations.R
# test_pub_figure_onplot_annotations: OK
```

## Commits
None (per task constraint).

## Concerns
- Block unit test not added (no lightweight Cox/smoothHR fixture); harvest path covered by existing Task 3 fixture.
- When Model3 is shown with `m3_sig`, figure vlines may appear on Model 3 panel but `Model2` entry still carries `cut_use$all` per spec.
