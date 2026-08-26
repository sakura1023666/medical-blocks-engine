# Eclampsia Task 2 Report

**Status:** DONE  
**Commits:** none  
**Date:** 2026-08-21  
**Study root:** `/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/`

## Deliverables

| Artifact | Path |
|---|---|
| Raw column dump | `Data/_column_review_raw.txt` (76 lines) |
| Column review | `Data/_column_review.md` |
| This report | `.superpowers/sdd/eclampsia-task-2-report.md` (repo) |

## One-line test summary

76/76 columns reviewed in `_column_review.md`; `disease_vars` length = **13** (≥8).

## disease_vars（Task 3 粘贴）

```r
.disease_exclusion_vars <- c(
  # 妊娠高血压谱系 / 诊断泄漏
  "Hypertension",
  # 血糖轴
  "T1DM", "T2DM", "Diabetes", "Glucose", "HbA1c",
  # 尿蛋白 / 尿白蛋白轴
  "UrineProtein", "UrineGlucose", "AlbuminUrine", "AlbuminCreatinine",
  # 【边界·已排除】子痫前期肾功能/病理相关
  "UricAcid", "CKD", "Acute_Renal_Failure"
)
```

## Exclusion rationale (summary)

| Group | Vars | Why |
|---|---|---|
| HTN spectrum | `Hypertension` | Overlaps eclampsia/preeclampsia definition |
| Glucose axis | `T1DM`, `T2DM`, `Diabetes`, `Glucose`, `HbA1c` | Metabolic/GDM leakage per brief |
| Urine protein axis | `UrineProtein`, `UrineGlucose`, `AlbuminUrine`, `AlbuminCreatinine` | Core PE diagnostic markers |
| Boundary | `UricAcid`, `CKD`, `Acute_Renal_Failure` | PE severity / renal end-organ overlap; uncertain → exclude |

## Explicitly NOT in disease_vars

- `ID`, `DN` — ID / outcome
- `Gender` — design drop (all-female); Task 3 → `base_exclude_vars`
- `ALBI` — composite index; component exclusion handles
- General labs kept: platelets, AST/ALT, creatinine, BUN, lipids, etc. (per brief「通用实验室」)
- Other comorbidities kept: `COPD`, `Heart_Failure`, `Stroke`, etc.

## Data notes

- dabiao n=4756, DN events=482 (Task 1; not re-merged)
- `Hypertension` Yes≈5 (sparse); still excluded for definition leakage
- `UrineProtein` / urine albumin mostly missing; still hard-excluded
- `Gender` 100% Female

## Concerns

- Boundary trio (`UricAcid`/`CKD`/`Acute_Renal_Failure`) is conservative; Task 3 may revisit if too many indices are skipped via `exclude_exposure_if_uses_disease_var` (UricAcid alone could skip uric-acid–based composites if any).
- HELLP-adjacent labs (Platelet/AST/ALT/LD) kept as general labs per brief; if reviewers want stricter PE-spectrum exclusion, expand disease_vars later and re-run.

## Out of scope (as instructed)

- No `config.R` write
- No batch start
- No git commits
