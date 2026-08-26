# Task 2 Review: Dual-batch finalize hook for `export_pub_figures`

**Reviewer:** code-review subagent  
**Date:** 2026-08-20  
**Scope:** Verify pre-existing workspace changes against brief + global constraints (read-only; no test re-run).

---

## Verdict

| Dimension | Result |
|-----------|--------|
| **Spec** | **PASS** |
| **Quality** | **Approved** |

---

## Spec checklist (brief)

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Hook at end of `incidence_batch_finalize_index_outputs`, after all curate | ✅ | `R/incidence_dual_batch_runner.R` L1922–1944, after combine (L1836–1842), `incidence_batch_curate_index_pub_outputs` (L1877), ML/S-table realign (L1899–1920) |
| Lazy-source `R/pub_figure_export.R`; call `export_pub_figures(figs_dir, meta, config)` | ✅ | Matches brief snippet verbatim |
| `figs_dir = file.path(index_root, "Figures")` | ✅ | L1928 |
| `meta` from config (`exposure`, `outcome`, `databases`, `combined`, `grouping`); no hard-coded tertile | ✅ | L1929–1938 |
| Non-fatal `tryCatch` + `cli_alert_warning` | ✅ | L1940–1943 |
| Finalize order: **combine → curate → export** | ✅ | combine L1836–1842; curate L1877+; export L1922+ |
| `pub_figures` defaults in three dual templates | ✅ | `config_incidence_dual_batch`, `config_survival_dual_batch`, `config_ml_dual_batch` — all `formats_dir=TRUE`, `dpi=300L`, `tiff_compression="lzw"`, `write_image_information=TRUE` |
| Regression guards extended | ✅ | `tests/test_result_review_guards.R` L466–504 |
| Tests claimed OK | ✅ (not re-run) | Implementer report; guards + `test_pub_figure_export.R` present and coherent |
| Git commit | N/A | Skipped per global constraints (no `.git`) |

---

## Global constraints

| Constraint | Status |
|------------|--------|
| Aggregate Figures top level: four subdirs only after export | ✅ Hook runs last; guard asserts zero top-level `.pdf/.png/.tiff` |
| TIFF LZW, 300 DPI, RGB | ✅ Template defaults; Task 1 `.pub_figure_cfg` uses dpi + hard-coded LZW |
| Multi-db: combine before export; per-db drafts not in aggregate four dirs | ✅ Export after `dual_db_combine_paired_figures` |
| Single-db: finals to four dirs | ✅ Same hook; `combined = length(db_seq) >= 2L` |
| Grouping from caller config | ✅ `logistic_gate` → `project$grouping` |
| No step-level intermediate mutation | ✅ Only `index_root/Figures` |
| Missing pair: warn, keep single-sided, still export | ✅ Unchanged combine behavior; export processes remaining PDFs |

---

## Shared finalize path (incidence / survival / ML)

All three workers call `incidence_batch_finalize_index_outputs`:

- `run/incidence/run_incidence_dual_batch_worker.R`
- `run/survival/run_survival_dual_batch_worker.R`
- `run/ml/run_ml_dual_batch_worker.R`

No separate survival/ML hook required.

---

## Findings (non-blocking)

1. **Ordering guard is partial.** Test checks `incidence_batch_curate_index_pub_outputs` before `export_pub_figures(figs_dir` via source scan (L499–504); it does **not** assert `dual_db_combine_paired_figures` precedes export. Runtime order is correct; optional hardening only.

2. **Early return unchanged.** `mirror_aggregate = FALSE` returns at L1799–1800 before combine/curate/export — pre-existing; export only runs for mirrored aggregate workflows. Documented in implementer report.

3. **Template `tiff_compression` unused by Task 1.** `.pub_figure_cfg()` hard-codes `"lzw"` (L20 `pub_figure_export.R`); global constraint still satisfied. Template field is forward-compatible, not a Task 2 defect.

4. **Commit deferred.** User must commit manually when git repo is restored.

---

## Quality assessment

Implementation is minimal, matches brief snippet, respects finalize ordering, and extends guards appropriately. No business-logic or semantic changes required.

**Approved** for merge/integration with Task 1.
