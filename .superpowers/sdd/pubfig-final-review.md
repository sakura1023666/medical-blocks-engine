# Final Whole-Branch Review — Pub Figures Formats (Tasks 1–6)

**Reviewer:** Senior Code Reviewer (final)  
**Date:** 2026-08-20  
**Scope:** Spec + plan + global constraints + progress ledger + minor rollup  
**Package:** `.superpowers/sdd/pubfig-final-review-pkg.md`  
**Verification run (targeted):** `test_pub_figure_export.R`, `test_dual_db_combine_n_panel.R`, `test_cross_lagged_export_summary_figures.R`, `test_result_review_guards.R` — all **OK**

---

## Executive Summary

The branch delivers the approved **方案 A** architecture: blocks still emit PDF; aggregate directories (`Figures/` or `summary_result/figure`) run **combine → curate → `export_pub_figures`** to produce `pdf/` `png/` `tiff/` `image_information/`, with TIFF LZW rasterization and per-figure Markdown. All six plan tasks are implemented; hook points match the file map; targeted tests pass on this workspace.

**Verdict: Ready for merge / production use on standard configs** (`mirror_aggregate=TRUE`, Python3 + Pillow or poppler, dual/multi cohort with complete pairing). Residual gaps are edge-case spec softness and metadata richness—not happy-path blockers.

| Severity | Count |
|----------|------:|
| Critical | 0 |
| Important | 6 |
| Minor | 9 |

---

## Plan Alignment (Tasks 1–6)

| Task | Plan deliverable | Status | Notes |
|------|------------------|--------|-------|
| 1 | `R/pub_figure_export.R`, `python/pub_figure_rasterize.py`, unit test | ✅ | Four dirs, LZW TIFF, md + README, top-level cleanup for processed stems |
| 2 | Dual-batch finalize export + templates + guards | ✅ | Export after `incidence_batch_curate_index_pub_outputs`; templates include `pub_figures` |
| 3 | ≥3 DB mosaic + `figures_dir=` | ✅ | `dual_db_compose_n_panel.py`, vector-first with raster fallback; 3-DB test passes |
| 4 | Cross-lagged `export_summary_figures.R` + collect hooks | ✅ | All four `collect_summary_result*.sh` call Rscript; e2e test passes |
| 5 | Competing + single `run_pipeline` hooks | ✅ | Combine-before-export in competing; `pipeline_figures_is_dual_slot` guards dual workers |
| 6 | `docs/Blocks_catalog.md` MANUAL note | ✅ | Line 80 documents four-directory convention |

**Spec coverage checklist:** All rows in plan §Spec coverage checklist are satisfied on the primary path. Deviations are listed under Important/Minor below.

---

## Architecture

**Strengths**

- Single export function (`export_pub_figures`) reused across incidence/survival/ML finalize, cross-lagged collect, competing pub export, and non-dual `run_pipeline` — good DRY and consistent delivery shape.
- Order discipline enforced: finalize places export **after** curate (guards assert `export_pos > curate_pos`); competing asserts combine `<` export `<` success; pipeline asserts export after `pub_renumber_pub_dir`.
- `figures_dir` parameter cleanly supports cross-lagged `summary_result/figure` without `Figures/` rename hacks.
- Idempotency: `run_pipeline` skips when `Figures/pdf/` already exists — avoids double export from dual-batch workers.
- Grouping not hard-coded in export layer; cross-lagged resolves via `cross_lagged_study_meta()` → `phase3_relock_acceptance.txt` (分位铁律 compliant).

**Weaknesses**

- Export is **not** sourced from `R/utils.R`; each hook lazy-sources `pub_figure_export.R`. Acceptable but easy to miss in new pipelines.
- `%||%` redefined at top of `pub_figure_export.R` (duplicate of `utils.R`); harmless when sourced after utils, noisy when sourced alone.
- Cross-lagged / finalize / competing wrap combine+export in `tryCatch(..., message/warning only)` — failures do not fail collect/finalize (plan-aligned, ops must read logs).

---

## Testing

| Test | Covers | Result |
|------|--------|--------|
| `tests/test_pub_figure_export.R` | Two PDFs, Missing Overview excluded, four dirs, LZW, md fields, top clean | ✅ |
| `tests/test_dual_db_combine_n_panel.R` | 3-DB mosaic + `figures_dir=` regression | ✅ |
| `tests/test_cross_lagged_export_summary_figures.R` | Full `export_summary_figures.R` phase | ✅ |
| `tests/test_result_review_guards.R` | Export top clean, hook order, dual-slot guard, competing order | ✅ |

**Gaps (tests not present or thin)**

- No unit test for **N=4 → 2×2 grid** layout (`dual_db_compose_n_panel.py` `_grid_shape`).
- No test for **raster failure** → PDF-only delivery + md annotation.
- No competing-risk end-to-end smoke through `18block_competing_pub_export.R`.
- No test for **`mirror_aggregate=FALSE`** finalize path (export skipped entirely).
- Dual-batch meta **`n_by_db` / `n_total`** never asserted in integration tests.

**Recommended verification before first real study rerun**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript tests/test_pub_figure_export.R
Rscript tests/test_dual_db_combine_n_panel.R
Rscript tests/test_cross_lagged_export_summary_figures.R
Rscript tests/test_result_review_guards.R
# Optional: one real by_index finalize or collect_summary_result on a study with ≥2 cohorts
```

**Runtime deps:** `python3`, `PIL` (or `pypdfium2`), and/or `pdftoppm` (poppler); `pypdf` + optional `reportlab` for vector n-panel compose.

---

## Production Readiness

**Ready when**

- Dual templates use `mirror_aggregate=TRUE` (default).
- Host has Python raster stack (verified by unit tests).
- Operators expect **warning-only** on mosaic/export failure (cross-lagged collect exits 0).

**Not ready without awareness when**

- `dual_db$mirror_aggregate=FALSE` — finalize returns **before** combine **and** export (see Important #1).
- Incomplete multi-cohort pairing — tagged `-DB` stems may land in `pdf/` (see Important #5).
- Sample sizes in md will read **未记录** until call sites pass `n_by_db` (see Important #2).

---

## Findings

### Critical (0)

None on the standard dual/multi-cohort path with complete figure pairing and default templates.

---

### Important (6)

#### I1. `mirror_aggregate=FALSE` skips entire finalize tail including export

**Where:** `R/incidence_dual_batch_runner.R` L1968–1970 — early `return` before combine, curate, and `export_pub_figures`.

**Impact:** Any config disabling aggregate mirror never receives four-directory delivery despite `pub_figures` in template.

**Recommendation:** Move export (or a slim export-only block) outside the `mirror_aggregate` gate, or document as unsupported and assert in config guard.

**Merge:** Can defer if all production configs keep `mirror_aggregate=TRUE` (templates do).

---

#### I2. `n_by_db` / `n_total` not injected at any hook

**Where:** `incidence_batch_finalize_index_outputs`, `export_summary_figures.R`, `18block_competing_pub_export.R`, `run_pipeline` — meta lists omit sample counts.

**Impact:** All production `image_information/*.md` show `样本量: 未记录` despite spec §6.3 expecting per-DB N when available.

**Recommendation:** Plumb attrition / Table1 N from ctx or batch runner into `meta$n_by_db` / `meta$n_total` in finalize (Task 2 follow-up).

**Merge:** Defer — functional delivery works; metadata incomplete.

---

#### I3. Raster failure does not annotate Markdown

**Where:** `export_pub_figures` tracks `missing_raster` but `pub_figure_write_image_md` always lists full pdf/png/tiff paths; spec §7 requires md to note missing formats.

**Recommendation:** Pass per-stem raster status into md writer (e.g. strikethrough or “缺失: png/tiff”).

**Merge:** Defer — PDF still delivered; warning logged via cli.

---

#### I4. README index missing 图题 column

**Where:** `export_pub_figures` README table: `Figure | Combined | PDF` only.

**Spec:** §6.3 — columns should include 图题.

**Recommendation:** Add caption column derived from stem (same regex as md).

**Merge:** Defer — index still usable.

---

#### I5. Incomplete multi-cohort pairing may export tagged stems

**Where:** Combine skips keys with `<2` DBs but leaves `Figure N-DB. …pdf` at top; `export_pub_figures` accepts any `^Figure` and preserves tag in `pdf/` stem.

**Spec tension:** §7 says unlabeled final should enter export; guards test expects tagged singles to remain when only one DB configured.

**Impact:** Edge case only; happy path (complete pairing) produces clean stems.

**Recommendation:** Either rename lone side to unlabeled key before export, or exclude tagged stems from export until paired.

**Merge:** Defer — pre-existing combine semantics; document for operators.

---

#### I6. Silent failure in cross-lagged collect path

**Where:** `export_summary_figures.R` L77–93 — `tryCatch` logs message, exit 0.

**Impact:** Collect scripts succeed while mosaic/export failed; downstream may assume four dirs populated.

**Recommendation:** Optional strict mode env var, or non-zero exit when `exported` empty but tagged PDFs remain.

**Merge:** Defer — matches dual-batch finalize parity (Task 4 review accepted this).

---

### Minor (9) — rollup triage

| ID | Source | Issue | Must fix before merge? | Notes |
|----|--------|-------|------------------------|-------|
| M1 | Task 1 | `system()+shQuote` vs plan's `system2` | **No** | Works on WSL; tests pass |
| M2 | Task 1 | poppler/pypdfium2 fallback undocumented in catalog | **No** | Ops doc only |
| M3 | Task 2 | `tiff_compression` in template unused (hardcoded LZW) | **No** | Matches constraint “TIFF LZW fixed” |
| M4 | Task 3 | roxygen for `figures_dir` incomplete on `dual_db_combine_paired_figures` | **No** | |
| M5 | Task 3 | N==4 2×2 grid untested | **No** | Add test when 4-cohort study ships |
| M6 | Task 4 | `known_dbs` hardcoded list may miss new cohort tags | **No** | Filename fallback + study_meta ordering helps |
| M7 | Task 5 | No competing e2e smoke | **No** | Static guards cover hook order |
| M8 | Task 5 | Export outside `sync_all_block` registration | **No** | By design (post-pipeline hook) |
| M9 | Task 6 | Catalog omits default DPI=300 | **No** | Optional one-line MANUAL tweak |

**Must fix before merge (from minor rollup):** **None.** All rollup items are deferrable follow-ups.

**Must fix before first production use (recommended, not merge blockers):**

1. **I1** if any study sets `mirror_aggregate=FALSE`.
2. **I2** if reviewers expect N in figure md (likely yes for publication package).
3. Confirm Python raster deps on deployment host (run Task 1 test once on target).

---

## Minor Rollup Triage Summary

| Rollup item | Verdict |
|-------------|---------|
| WSL `system()+shQuote` | ✅ Accept — verified |
| poppler fallback | ✅ Accept — document in deploy skill |
| `mirror_aggregate` skip export | ⚠️ Elevated to **I1** |
| `tiff_compression` unused | ✅ Defer (intentional hardcode) |
| roxygen / N4 untest | ✅ Defer |
| tryCatch swallow | ⚠️ Elevated to **I6** — defer merge |
| catalog DPI | ✅ Defer (M9) |
| competing e2e | ✅ Defer (M7) |
| export hook placement | ✅ Accept by design |

---

## Constraint Compliance

| Global constraint | Compliance |
|-------------------|------------|
| Top-level only four subdirs (processed figures) | ✅ On happy path; tagged/unpaired edge may leave non-`Figure*` or tagged stems — see I5 |
| TIFF LZW, 300 dpi default, RGB | ✅ Tested via Pillow `tiff_lzw` |
| Multi-DB mosaic + remove_singles | ✅ 2- and 3-DB tests |
| Single-DB no mosaic | ✅ combine disabled when `<2` DBs |
| Grouping not hard-coded tertile | ✅ Injected from config / study_meta / acceptance file |
| Missing Value Overview excluded | ✅ Deleted at combine + export |
| Step-level figures untouched | ✅ Export only on aggregate dirs |

---

## Files Touched (review package)

**New:** `R/pub_figure_export.R`, `python/pub_figure_rasterize.py`, `R/dual_db_compose_n_panel.py`, `Blocks/54_cross_lagged_full/phases/export_summary_figures.R`, `tests/test_pub_figure_export.R`, `tests/test_dual_db_combine_n_panel.R`, `tests/test_cross_lagged_export_summary_figures.R`

**Modified:** `R/dual_db_combine_figures.R`, `R/incidence_dual_batch_runner.R`, `R/pipeline_runner.R`, `Blocks/55_competing_risk_full/18block_competing_pub_export.R`, `Blocks/54_cross_lagged_full/phases/collect_summary_result*.sh`, `configs/templates/config_*_dual_batch.template.R`, `tests/test_result_review_guards.R`, `docs/Blocks_catalog.md`

---

## Conclusion

Tasks 1–6 are **complete and coherent**. Architecture matches spec; tests cover core behaviors and regression guards. No Critical defects block merge. Address **I2 (sample N in md)** before treating `image_information` as publication-ready metadata; watch **I1** on non-default configs.

**Overall verdict: Ready** (merge and standard-pipeline use), with Important follow-ups tracked above.
