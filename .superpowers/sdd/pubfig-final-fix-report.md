# Pub Figures Final Fix Pass — I2–I4

**Date:** 2026-08-20  
**Scope:** Important items I2, I3, I4 from `pubfig-final-review.md`  
**Deferred (unchanged):** I1 (`mirror_aggregate=FALSE` early return), I5 (incomplete pairing tagged stems), I6 (cross-lagged tryCatch silent exit)

---

## Status

**Complete** — I2 (best effort), I3, I4 implemented; all targeted tests pass.

---

## Fixed

### I4 — README 图题 column

**File:** `R/pub_figure_export.R`

- Added `.pub_figure_caption_from_stem()` helper (same regex as per-figure md).
- README table columns: `Figure | 图题 | Combined | PDF`.
- Caption derived from stem when building `readme_rows`.

### I3 — Raster failure annotated in Markdown

**File:** `R/pub_figure_export.R`

- `pub_figure_write_image_md(..., raster_ok = TRUE)` new parameter.
- When `raster_ok = FALSE`:
  - 标识 section notes `（缺失: png, tiff — 栅格化失败）` instead of listing png/tiff paths.
  - Adds `## 格式交付` section: PDF 已生成; PNG/TIFF 未生成.
- `export_pub_figures` passes `raster_ok = isTRUE(ok_r)` per stem after rasterize attempt.

### I2 — Sample N in finalize meta (best effort)

**Files:** `R/incidence_dual_batch_runner.R`, `Blocks/54_cross_lagged_full/phases/export_summary_figures.R`

- New `incidence_batch_pub_figure_meta_n(index_root, config, db_seq)`:
  - Reads `_batch_status.json` (`n_nhanes_after`, `n_mimic_after`).
  - Maps slots via `dual_db_normalize_slot`; labels via `dual_db_slot_path_name`.
  - Returns `list(n_by_db = ..., n_total = ...)` or empty list if unavailable.
- `incidence_batch_finalize_index_outputs` merges `meta_n` into export meta when present.
- Comment in finalize and `export_summary_figures.R`: N is optional; cross-lagged path still often 未记录 (no attrition hook yet).
- **No fake N** — only real values from batch status artifact.

---

## Deferred (documented, no code change)

| ID | Item | Reason |
|----|------|--------|
| I1 | `mirror_aggregate=FALSE` skips export | Explicit deferral per task |
| I5 | Incomplete pairing may export tagged stems | Pre-existing combine semantics |
| I6 | Cross-lagged collect tryCatch exit 0 | Parity with finalize; no strict mode added |

---

## Tests

```bash
Rscript tests/test_pub_figure_export.R          # OK
Rscript tests/test_result_review_guards.R       # OK
Rscript tests/test_cross_lagged_export_summary_figures.R  # OK
```

**Test updates (`tests/test_pub_figure_export.R`):**

- Assert README contains `图题` and caption text.
- Direct call to `pub_figure_write_image_md(..., raster_ok = FALSE)` asserts missing-format annotation.

---

## Files touched

- `R/pub_figure_export.R`
- `R/incidence_dual_batch_runner.R`
- `Blocks/54_cross_lagged_full/phases/export_summary_figures.R`
- `tests/test_pub_figure_export.R`
- `.superpowers/sdd/pubfig-final-fix-report.md` (this file)
