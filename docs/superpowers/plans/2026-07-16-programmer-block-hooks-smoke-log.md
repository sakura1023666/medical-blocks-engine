# Programmer Block Hooks — E2E Smoke Log

**Date:** 2026-07-16  
**Path used:** lightweight (`add_block` + `pipeline_extension_guard_check` via Rscript). Full `./run_study.sh … --shared-only` **not** run (heavy).  
**Commits:** none (constraint).

## Matrix

| Port | Study | Slot / block | add_block | tree_v001 | baseline md5 = mother | Guard legal | Illegal mid-chain → 非法 |
|------|-------|--------------|-----------|-----------|----------------------|-------------|--------------------------|
| 5006 env | `_hooks_smoke_env` (copy `_template`) | `environment.tail_end` / `plot_histogram` | PASS | PASS | `40c74447432f653a890843c7dda74170` | PASS | PASS (`plot_forest` 不在 extensions.json) |
| 5001 incidence | `_hooks_smoke_inc` (minimal fixture) | `incidence.regular_end` / `plot_histogram` | PASS | PASS | `d9bfb393ba5b5804d9b71efcfdada8d7` | PASS | PASS |
| 5003 ml | `_hooks_smoke_ml` (minimal fixture) | `ml.primary_end` / `plot_histogram` | PASS | PASS | `619ff6266df6d9570ec9c53ceaaa428d` | PASS | PASS |

## Notes

- **5006:** Real template config with `pipeline_tail`. After legal attach, config ends with `…, 'plot_histogram'`. Hand-insert of `plot_forest` mid-chain (no `extensions.json` update) → `stop("非法 pipeline 扩展: …")`.
- **5001 / 5003:** Programmer `_template` only has `.study` + `source(*_build.R)` (no literal `pipeline_* <- list` for CLI rewrite). Smoke used **minimal fixtures** whose `blocks` match `baseline_pipelines.json`.
- Study dirs are small (≤28K); no full pipeline outputs left.
- Mother `Decisiontree/*.md` and `Blocks/` not mutated.

## Guard command pattern

```r
source("<ENGINE>/R/pipeline_extension_guard.R")
source("<study>/config.R", local = env)
pipeline_extension_guard_check("<routine>", list(...pipelines...), "<study>", "<ENGINE>")
```
