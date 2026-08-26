# Task 1 Report: Merge D04_dabiao + Smoke Check

**Status:** DONE_WITH_CONCERNS  
**Date:** 2026-08-21  
**Study root:** `/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/`  
**Commits:** none (no git in workspace)

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Merge script | `build_merged_data.R` | Created |
| Merged dabiao | `Data/mimic/D04_dabiao.RData` | Created |

## Implementation

- Loads `data/D01_baseline_MIMIC_GW_0804.RData` (`baseline`) and `data/D03_result_子痫_MIMIC(1).RData` (`result`).
- Merges `result` × `baseline` on `subject_id` / `ID` (`all.x = TRUE`), renames key to `ID`.
- Validates `nrow == 4756`, `sum(DN == 1) == 482`, no duplicate `ID`.
- Saves `dabiao` to `Data/mimic/D04_dabiao.RData`.

### Script deviation (concern)

Brief verbatim block 1 used `sys.frame(1)$ofile` before the `commandArgs` resolver; under `Rscript` this errors (`not that many frames on the stack`) when `ECLAMPSIA_STUDY_ROOT` is unset. **Fix:** moved `commandArgs` root resolution first, then optional `ECLAMPSIA_STUDY_ROOT` override. Merge logic and `stopifnot` checks unchanged.

## Verification

### Step 2 — run merge

```bash
cd "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007"
Rscript build_merged_data.R
```

**Output:** `OK dabiao n=4756 events=482`

### Step 3 — load check

```bash
Rscript -e 'load(".../Data/mimic/D04_dabiao.RData"); stopifnot(nrow(dabiao)==4756, sum(dabiao$DN==1)==482); cat("PASS\n")'
```

**Output:** `PASS`

### Self-review

| Check | Result |
|-------|--------|
| `nrow(dabiao)` | 4756 |
| `sum(DN == 1)` | 482 |
| `anyDuplicated(ID)` | 0 |
| Columns | 76 (`ID`, `DN` present) |
| Output file size | ~125 KB |

## Out of scope (not done)

- `config.R`, column review, batch launch — per task brief.

## Concerns

1. Root-resolution reorder vs brief verbatim (see above); functionally equivalent for this study layout.
2. No further issues; counts match spec.
