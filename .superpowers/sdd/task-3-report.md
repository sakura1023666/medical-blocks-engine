# Task 3 Report — `00osteo_dxa_qct_common.R`

**Date:** 2026-09-22  
**Engine root:** `/mnt/e/01block/01Block-new-Final`

## Deliverables

| Item | Path |
|------|------|
| Common helpers | `Blocks/75_osteo_dxa_qct/00osteo_dxa_qct_common.R` |
| Tests | `tests/test_osteo_dxa_qct_blocks.R` |

## TDD

### RED (Step 1 — test before implementation)

Command:

```bash
cd /mnt/e/01block/01Block-new-Final && Rscript tests/test_osteo_dxa_qct_blocks.R
```

Output:

```
Error: file.exists(common_path) is not TRUE
Execution halted
EXIT:1
```

Cause: `Blocks/75_osteo_dxa_qct/00osteo_dxa_qct_common.R` did not exist yet; test intentionally `stopifnot(file.exists(common_path))` before `source`.

### GREEN (Step 2–3 — implement helpers, re-run)

Command:

```bash
cd /mnt/e/01block/01Block-new-Final && Rscript tests/test_osteo_dxa_qct_blocks.R
```

Output:

```
helper OK
EXIT:0
```

## Functions implemented

| Function | Role |
|----------|------|
| `.osteo75_pick_col` | First matching column name from `candidates` in `data`; stops if none |
| `.osteo75_cohen_kappa` | Binary κ via observed/expected agreement (`list(kappa=, n=)`); no `irr` dependency |
| `.osteo75_make_strata` | Named list `Nathan`, `AAC`, `BMI`, `Age` from `_bin` columns or raw `Nathan`/`BMI`/`Age`/`AAC` |
| `.osteo75_diag_metrics` | Single-row `data.frame`: sens, spec, ppv, npv, n, n_pos |
| `.osteo75_auc_continuous` | `pROC::roc` + `ci.auc`; default `direction="<"`; returns `list(auc=, ci_lo=, ci_hi=)` |

## Test assertions (beyond brief minimum)

- κ on 6×6 known table: `n == 6`, finite κ (reference κ ≈ 0.333 for brief vectors).
- `diag_metrics`: sens = 2/3, spec = 1.
- `pick_col`: resolves `QCT_vBMD` when listed second among candidates.
- `make_strata`: four named strata, length 4 on mini frame.
- AUC: exercised when `requireNamespace("pROC")` is TRUE (environment has pROC; no skip note).

## Git

No commit (per task instruction).

## Next

Task 4: `01block_dxa_qct_agreement.R` consuming these helpers.
