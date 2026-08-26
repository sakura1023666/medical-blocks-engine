# Task 4 report: cross-lagged summary_result/figure mosaic + export

## Status

**Done.** Created `Blocks/54_cross_lagged_full/phases/export_summary_figures.R` and hooked it at the end of all `collect_summary_result*.sh` scripts.

## Changes

| File | Action |
|------|--------|
| `Blocks/54_cross_lagged_full/phases/export_summary_figures.R` | **Created** — detect cohorts from `-DB.` PDF tags; resolve `grouping` via `cross_lagged_study_meta()` → `phase3_relock_acceptance.txt`; call `dual_db_combine_paired_figures(study_root, cfg, figures_dir=fig)` then `export_pub_figures()`. |
| `collect_summary_result_generic.sh` | **Modified** — Rscript export after collect/manifest. |
| `collect_summary_result_hip.sh` | **Modified** — same hook. |
| `collect_summary_result.sh` | **Modified** — `exec` → `bash` so child scripts run export; local override also triggers export. |
| `collect_summary_result_circadian.sh` | **Modified** — `exec` → `bash` (export via generic). |

## Interface usage

- `dual_db_combine_paired_figures(index_root, config, figures_dir = fig)` — uses Task 3 `figures_dir` parameter; **no** `dirname(fig)` workaround.
- `export_pub_figures(fig, meta = list(databases, combined, grouping), config)` — writes `pdf/`, `png/`, `tiff/`, `image_information/` under `summary_result/figure/`.
- Grouping never hardcoded; sourced from study meta or relock acceptance file.

## Smoke test

Temp study `.tmp/cl_export_smoke_hfg1` with three per-cohort RCS PDFs (`-CHARLS/-ELSA/-HRS`) + one single-panel S5:

```
Rscript Blocks/54_cross_lagged_full/phases/export_summary_figures.R .tmp/cl_export_smoke_hfg1
```

Results:

- Combined `Figure 2. RCS plot between FI and Hip Fracture.pdf`; per-DB singles removed.
- Four format subdirs populated; figure root has **no** loose PDF/PNG.
- Raster exports (png/tiff) succeeded at 300 DPI.

## Commits

None (per global constraints — workspace has no `.git`).

## Concerns

1. **Local collect override** (`collect_summary_result.local.sh`): export runs from dispatcher only; local scripts must copy figures into `summary_result/figure/` first or call export themselves.
2. **Raster deps**: smoke passed here; hosts without ImageMagick/Ghostscript may skip tiff/png (export logs warning, keeps pdf/).
3. **Pooled figures** (`Figure 2-Pooled`, etc.) are intentionally excluded from `databases` vector — they remain single-panel exports, not mosaic inputs.

---

## Fix pass (2026-08-20)

**Status:** Done — committed regression test added (not git-committed per constraints).

**Test:** `tests/test_cross_lagged_export_summary_figures.R`

**What it does:**
1. Builds temp `study_root` with `summary_result/figure/` and three minimal per-cohort RCS PDFs (`Figure 2-CHARLS/ELSA/HRS. RCS plot.pdf`).
2. Writes `phase3_relock_acceptance.txt` with `main_grouping=quartile` (acceptance is optional fallback; unknown study roots resolve grouping via `cross_lagged_study_meta()` default).
3. Invokes `Rscript Blocks/54_cross_lagged_full/phases/export_summary_figures.R <study_root>` with `MEDICAL_BLOCKS_ROOT` set to repo root (`Sys.setenv`, not inline `env=` — avoids shell parse errors on complex Cursor env).
4. Asserts:
   - Combined `Figure 2. RCS plot.pdf` in `pdf/`; matching `png` + `tiff`.
   - `image_information/Figure 2. RCS plot.md` exists.
   - No loose PDF at `summary_result/figure/` root.
   - Per-cohort singles (`-CHARLS/-ELSA/-HRS`) removed from root and `pdf/`.

**Test result:**
```
Rscript tests/test_cross_lagged_export_summary_figures.R
→ test_cross_lagged_export_summary_figures: OK
```

**Files changed:**

| File | Action |
|------|--------|
| `tests/test_cross_lagged_export_summary_figures.R` | **Created** — end-to-end regression for export phase script. |
| `.superpowers/sdd/pubfig-task-4-report.md` | **Updated** — this fix pass section. |

**Notes:** `export_summary_figures.R` `tryCatch` exit behavior unchanged (matches dual-batch finalize + plan). No git commit.
