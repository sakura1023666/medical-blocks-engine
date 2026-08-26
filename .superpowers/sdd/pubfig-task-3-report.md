# Task 3 Report: ≥3 database panel combine + figures_dir

## Status

**COMPLETE** — no git commit (per global constraints: workspace has no `.git`).

## TDD evidence

### RED (pre-implementation)

```bash
$ Rscript tests/test_dual_db_combine_n_panel.R
✔ 双库拼图完成: 1 张（layout=auto; A=CHARLS, B=ELSA）
Error: !file.exists(file.path(figs, "Figure 2-HRS. RCS plot.pdf")) is not TRUE
```

Only CHARLS+ELSA were combined; HRS single remained → expected failure.

### GREEN (post-implementation)

```bash
$ Rscript tests/test_dual_db_combine_n_panel.R
✔ 多库拼图完成: 1 张（layout=auto; order=CHARLS, ELSA, HRS）
test_dual_db_combine_n_panel: OK
```

Additional smoke (same session):

| Test | Result |
|------|--------|
| 2-DB eICU/MIMIC pair compose | OK — `Figure 2. RCS plot.pdf` produced, singles removed |
| `figures_dir=summary_result/figure` | OK — combine works outside default `Figures/` |

## Changes

| File | Action |
|------|--------|
| `tests/test_dual_db_combine_n_panel.R` | Created (brief Step 1) |
| `R/dual_db_compose_n_panel.py` | Created — 1×N row; N==4 → 2×2 grid; vector labels |
| `R/dual_db_combine_figures.R` | Modified |

### `R/dual_db_combine_figures.R` highlights

- `.dual_db_combine_cfg`: `tertiary`, `databases` vector from primary/secondary/tertiary/`databases`
- `dual_db_combine_paired_figures(index_root, config, figures_dir = NULL)` — optional figures dir for Task 4
- N>2 → `.dual_db_compose_n_pdf` (vector via Python, raster fallback)
- N==2 → existing `.dual_db_compose_pair_pdf` unchanged
- `.dual_db_per_db_tag_pattern()` replaces hardcoded `(eICU|MIMIC|NHANES)` in detection, same-role skip, purge tags
- `.dual_db_panel_label` accepts C/D/E… letters

## Concerns / follow-ups

1. **N==4 layout**: auto 2×2 in Python; RCS `stack` layout for 2-panel only — 3+ always row/grid (per brief).
2. **Vector compose deps**: requires `python3` + `pypdf` (+ optional `reportlab`); falls back to raster if missing.
3. **Task 4**: `figures_dir` ready; caller should pass `summary_result/figure` directly.
4. **Existing guard test** `tests/test_result_review_guards.R` dual_db sections not re-run in full this session; 2-DB smoke passed inline.

## Commits

None (explicitly skipped).

## Fix pass

**Status:** Important review finding addressed — `figures_dir` now has committed regression coverage.

### Change

- `tests/test_dual_db_combine_n_panel.R`: second block uses `summary_result/figure` with 3× `-DB` PDFs (eICU/MIMIC/HRS), calls `dual_db_combine_paired_figures(ix2, cfg2, figures_dir = fig_sr)`, asserts `Figure 2. RCS plot.pdf` exists, per-DB singles removed, and default `Figures/` unused.

### Tests (2026-08-20)

| Test | Result |
|------|--------|
| `Rscript tests/test_dual_db_combine_n_panel.R` | OK — default `Figures/` 3-panel + `figures_dir` 3-panel |
| `Rscript tests/test_result_review_guards.R` | OK — dual_db guard sections pass |

No git commit (per instructions).
