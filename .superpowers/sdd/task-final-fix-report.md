# Final whole-branch review fixes (2026-08-18)

## Status: DONE

No git commit (per instructions).

## What changed

1. **complete_case default FALSE** — spec is Yes/No + age on imputed cohort. `sensitivity_suite$complete_case %||% FALSE` in `incidence_sensitivity_scenarios_for_index`; templates/build set `complete_case = FALSE`. Complete-case path remains opt-in only.
2. **Light workers skip shared index availability** — when `.sensitivity_light` is TRUE, incidence/survival workers set `avail[[db]] <- TRUE` and do not call `incidence_batch_index_available`. Per-index `index.rds` is still required later.
3. **Sensitivity_summary.csv n is post-filter** — `incidence_sensitivity_summary_n()` uses `n_nhanes_after` / `n_mimic_after` from `run_one`, not pre-filter `sg$ns`.
4. **Skip Figure 1 on light** — survival worker does not call `survival_batch_write_index_flowcharts` when light. Incidence finalize/`incidence_batch_curate_index_pub_outputs` skips `incidence_batch_ensure_figure1_placeholder` when `.sensitivity_light`.
5. **`incidence_sensitivity_pass` output_base** — `modifyList(incidence_batch, survival_batch)` like `for_index`, so prognosis-only studies write summary next to their output.
6. **Rename strips existing `Sensitivity analysis[:\-.]` prefixes** via `incidence_sensitivity_strip_existing_sa_caption` before adding `Sensitivity analysis-{zh}.`
7. **Prognosis light Table 2 dual-db align** — after both DBs finish the light Cox block, call `dual_db_harmonize_unified_cox_branch` + `survival_batch_realign_cox_to_unified`. Full Cox gate cascade stays off.
8. **copy_imputed_ck leftover** — dest no longer keeps unfiltered `imputation.rds` (not copied / unlinked). After subgroup filter, any leftover `imputation.rds` is overwritten with filtered `index.rds`.

## Tests

| Command | Result |
|---------|--------|
| `Rscript tests/test_incidence_sensitivity_light.R` | Task1–7 + TaskCC OK; exit 0 |
| `Rscript tests/test_result_review_guards.R` | `test_result_review_guards: OK`; exit 0 |

Added/adjusted in `tests/test_incidence_sensitivity_light.R`:
- template/build `complete_case` is not TRUE; key-absent suite does not generate `SA_complete_case`
- `incidence_sensitivity_summary_n` uses after-filter n
- Cox file `Sensitivity analysis: Multivariable Cox` → single `S13 Sensitivity analysis-{zh}` name
- `copy_imputed_ck` dest has no leftover unfiltered `imputation.rds`
