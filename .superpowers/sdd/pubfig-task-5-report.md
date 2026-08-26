# Task 5 Report: 竞争风险 + 通用单流水线 export 收口

**Date:** 2026-08-20  
**Status:** ✅ Complete  
**Git commit:** Skipped (workspace has no `.git`, per global constraints)

---

## Summary

Hooked `export_pub_figures()` at the end of `competing_pub_export` (with optional multi-db combine) and at `run_pipeline` shutdown for non-dual-slot aggregate `Figures/` directories. Extended regression guards.

---

## Changes

### 1. `Blocks/55_competing_risk_full/18block_competing_pub_export.R`

**Location:** Before `cli_alert_success` (after manifest / covariate writes)

**Behavior:**

1. Detect ≥2 distinct `-DB.` tags among top-level PDFs in `fig_dir`
2. If multi-db: lazy-source `R/dual_db_combine_figures.R`, call `dual_db_combine_paired_figures(out_root, cfg, figures_dir = fig_dir)` (non-fatal `tryCatch`)
3. Lazy-source `R/pub_figure_export.R`, call `export_pub_figures(fig_dir, meta, config)` with `combined = TRUE` when combine ran, else single-db meta
4. Errors → `cli_alert_warning("发表图导出跳过: …")`

### 2. `R/pipeline_runner.R`

**Location:** After `pub_renumber_pub_dir` loop (outside `sync_all_block_pub_outputs_to_root` block)

**Dual-slot guard:**

```r
is_dual_slot <- !is.null(config$dual_db$current_db) &&
  nzchar(as.character(config$dual_db$current_db)[1L])
```

Export runs only when:

- `!isTRUE(is_dual_slot)` — skip dual-batch per-DB worker runs
- `dir.exists(figs)` — aggregate `Figures/` present
- `!dir.exists(file.path(figs, "pdf"))` — skip if Task 2 finalize already exported

Targets `ctx$root_output_dir %||% config$project$output_dir`.

### 3. `tests/test_result_review_guards.R`

Added source-scan guards:

- `pipeline_runner.R`: `export_pub_figures(figs` after `pub_renumber_pub_dir`; `is_dual_slot` present
- `18block_competing_pub_export.R`: `export_pub_figures` before `cli_alert_success`; `dual_db_combine_paired_figures` present

---

## Verification

| Test | Result |
|------|--------|
| `Rscript tests/test_pub_figure_export.R` | ✅ OK |
| `Rscript tests/test_result_review_guards.R` | ✅ OK |

---

## Pre-existing vs new

| Item | Pre-existing | This task |
|------|--------------|-----------|
| `export_pub_figures` core (Task 1) | ✅ | consumed |
| Dual-batch finalize export (Task 2) | ✅ | unchanged |
| Cross-lagged summary export (Task 4) | ✅ | unchanged |
| `competing_pub_export` export hook | ❌ | **added** |
| `run_pipeline` end export hook | ❌ | **added** |
| Dual-slot guard in `run_pipeline` | ❌ | **added** |

---

## Concerns / notes

1. **Non-fatal errors:** Both hooks use `tryCatch` + warning only (parity with Tasks 2/4); pipeline exit code stays 0 on export failure — watch logs.
2. **Dual-batch workers:** Per-DB slot runs skip `run_pipeline` export via `is_dual_slot`; aggregate export remains Task 2 finalize responsibility.
3. **Single-db competing risk:** Figures retain `-DB` filename tags; export moves them into four subdirs without combine (expected).
4. **No end-to-end competing batch smoke:** Guards are source-order + existing export smoke; full competing batch not run in CI here.

---

## Files touched

- `Blocks/55_competing_risk_full/18block_competing_pub_export.R`
- `R/pipeline_runner.R`
- `tests/test_result_review_guards.R`
- `.superpowers/sdd/pubfig-task-5-report.md` (this file)

---

## Fix pass (2026-08-20)

**Status:** ✅ Complete

### Findings addressed

1. **`R/pipeline_runner.R` — stronger dual-slot export guard**
   - Extracted `pipeline_figures_is_dual_slot(figs, config)` helper.
   - Keeps existing `current_db` check and `pdf/` skip.
   - When `dual_db$enable` is TRUE, also skips if:
     - `basename(dirname(Figures))` matches a known db display name from `primary` / `secondary` / `tertiary` / `databases` (sanitized via `dual_db_sanitize_path_name` when available).
     - Path matches `by_index/<ix>/<slot>/Figures` (per-DB slot under index root, not aggregate `by_index/<ix>/Figures`).

2. **`tests/test_result_review_guards.R`**
   - Source guards require `pipeline_figures_is_dual_slot`, `current_db`, `dual$enable`, and `by_index/.../Figures` regex.
   - Unit checks: per-DB path → TRUE; aggregate index Figures → FALSE; `current_db` set → TRUE.
   - Competing guard strengthened: `dual_db_combine_paired_figures` must appear **before** `export_pub_figures`, which must appear before `cli_alert_success`.

### Verification (Fix pass)

| Test | Result |
|------|--------|
| `Rscript tests/test_pub_figure_export.R` | ✅ OK |
| `Rscript tests/test_result_review_guards.R` | ✅ OK |

### Files changed (Fix pass)

- `R/pipeline_runner.R`
- `tests/test_result_review_guards.R`
- `.superpowers/sdd/pubfig-task-5-report.md` (this section)
