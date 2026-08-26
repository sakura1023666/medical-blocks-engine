# Task 2 Report: Dual-batch finalize hook for export_pub_figures

**Date:** 2026-08-20  
**Status:** ✅ Complete  
**Git commit:** Skipped (workspace has no `.git`, per global constraints)

---

## Summary

Wired `export_pub_figures()` at the end of `incidence_batch_finalize_index_outputs()` so dual-batch incidence/survival/ML pipelines emit pdf/png/tiff + image_information under aggregate `Figures/` after combine and curate. Added `pub_figures` defaults to three dual-batch templates and extended regression guards.

---

## Changes

### 1. `R/incidence_dual_batch_runner.R`

**Function:** `incidence_batch_finalize_index_outputs(root, config, ix, db_seq)`  
**Location:** Lines 1922–1944 (after all table curate/realign/compact/shorten work)

**Finalize order (unchanged except new final step):**

1. Sync per-db pub outputs  
2. Mirror aggregate (`mirror_dual_db_aggregate`)  
3. Clean stale `.svg`  
4. Dedupe prognosis figures (if applicable)  
5. **Combine** paired figures (`dual_db_combine_paired_figures`)  
6. Purge aggregate `.tex` / scratch csv  
7. **Curate** (`incidence_batch_curate_index_pub_outputs` + ML/S-table realign)  
8. **Export** (`export_pub_figures`) ← **new**

**Hook behavior:**

- Lazy-sources `R/pub_figure_export.R` if `export_pub_figures` not loaded
- Targets `file.path(index_root, "Figures")` (aggregate index root, not per-db slot)
- Builds `meta` from config: exposure, outcome, databases, combined flag, grouping (from `logistic_gate` / `project`, never hard-coded tertile)
- Wraps call in `tryCatch` with `cli_alert_warning` on failure (non-fatal skip)

### 2. Dual-batch templates — `pub_figures` defaults

Added to all three templates:

```r
pub_figures = list(
  formats_dir = TRUE,
  dpi = 300L,
  tiff_compression = "lzw",
  write_image_information = TRUE
),
```

| File | Insertion point |
|------|-----------------|
| `configs/templates/config_incidence_dual_batch.template.R` | After `imputation`, before `dual_db` |
| `configs/templates/config_survival_dual_batch.template.R` | After `covariate_policy`, before `dual_db` |
| `configs/templates/config_ml_dual_batch.template.R` | After `index`, before `dual_db` |

### 3. `tests/test_result_review_guards.R`

Added two guard blocks:

1. **Export smoke:** temp `Figures/` with two PDFs → `export_pub_figures()` → assert top level has zero `.pdf/.png/.tiff` files; four subdirs exist (`pdf`, `png`, `tiff`, `image_information`).
2. **Finalize ordering:** source scan of `incidence_dual_batch_runner.R` — `export_pub_figures(figs_dir` appears after `incidence_batch_curate_index_pub_outputs`.

---

## Test Results

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript tests/test_result_review_guards.R   # OK
Rscript tests/test_pub_figure_export.R      # OK
```

Both exit 0. No assertion or business-logic changes required.

---

## Interface Contract

**Consumed:** `export_pub_figures(figures_dir, meta, config)` from `R/pub_figure_export.R` (Task 1)

**Returns:** invisible `list(exported=, missing_raster=, md=)` — caller ignores return value; errors logged as warnings.

**Meta fields injected at finalize:**

| Field | Source |
|-------|--------|
| `exposure` | `config$project$exposure_var` → `index_var` → `ix` |
| `outcome` | `config$data$outcome_column` → `config$project$outcome` |
| `databases` | `db_seq` |
| `combined` | `length(db_seq) >= 2L` |
| `grouping` | `config$logistic_gate$grouping` → `config$project$grouping` |

---

## Global Constraints Compliance

| Constraint | Status |
|------------|--------|
| Aggregate top level only four subdirs after export | ✅ `export_pub_figures` moves PDFs into subdirs and deletes top-level files |
| TIFF LZW, 300 DPI, RGB | ✅ Template defaults + Task 1 rasterizer |
| Multi-db: combine then remove_singles; per-db drafts not in aggregate four dirs | ✅ Export runs after combine/curate |
| Single-db: no combine; finals go to four dirs | ✅ Same hook; `combined = FALSE` in meta |
| Grouping not hard-coded tertile | ✅ From config injection |
| No change to step-level intermediate figures | ✅ Only touches aggregate `index_root/Figures` |
| Missing Value Overview excluded | ✅ Handled in Task 1 export logic |
| Missing pair: warn, keep single-sided, still export | ✅ Unchanged combine behavior; export processes remaining top-level PDFs |

---

## Concerns / Follow-ups

1. **Survival/ML runners:** Both call `incidence_batch_finalize_index_outputs` (shared finalize path) — no separate survival/ML hook needed; verified by shared function name in runner.
2. **Rasterizer dependency:** Export requires `python3` + `PIL` for png/tiff; failures are warned per-figure (`missing_raster`) and do not abort finalize.
3. **Early return:** If `mirror_aggregate = FALSE`, finalize returns before combine/curate/export — intentional existing behavior; pub export only runs for mirrored aggregate workflows.
4. **No git commit:** Per workspace constraint; user must commit manually if repo is restored.

---

## Files Touched

- `R/incidence_dual_batch_runner.R` (modified)
- `configs/templates/config_incidence_dual_batch.template.R` (modified)
- `configs/templates/config_survival_dual_batch.template.R` (modified)
- `configs/templates/config_ml_dual_batch.template.R` (modified)
- `tests/test_result_review_guards.R` (modified)

**Not modified (Task 1 artifacts, consumed as-is):**

- `R/pub_figure_export.R`
- `python/pub_figure_rasterize.py`
- `tests/test_pub_figure_export.R`
