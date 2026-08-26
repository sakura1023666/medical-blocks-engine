# Task 3 Report: Write config.R (incidence + 6 models + age 35 + 10 workers)

## Status

**COMPLETE** — `config.R` written and dry-load **CONFIG PASS**. No git commit (per global constraints). Batch run not started (Task 4).

## Deliverable

| Item | Path |
|------|------|
| Config | `/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/config.R` |
| Report | `/mnt/e/01block/01Block-new-Final/.superpowers/sdd/eclampsia-task-3-report.md` |

## CONFIG PASS (brief Step 2)

```bash
export MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final
Rscript -e '
Sys.setenv(MEDICAL_BLOCKS_ROOT="/mnt/e/01block/01Block-new-Final")
source(".../config.R")
stopifnot(identical(config$project$study_type, "incidence"))
stopifnot(identical(config$ml_batch$assoc_model, "logistic"))
stopifnot(length(config$ml_models$methods)==6L)
stopifnot(identical(as.integer(config$subgroup$age_cutoff), 35L))
stopifnot(is.null(config$subgroup$age_group_cutoffs))
cat("CONFIG PASS\n")
'
```

**Result:** `CONFIG PASS`

Extended self-checks (same session): six methods exact match; `index_group=all` / `index_vars=NULL`; workers=10; `db_mode=nhanes`; `fail_policy=continue`; `assoc_covariate` enable + `force_model1=Age`; Task 2 `disease_vars` identical (13); Gender in drop/exclude; `rawdata_path` → study `Data/mimic/D04_dabiao.RData` exists; nhanes multi-cutoff cleared; `Age_Group` = `< 35` / `≥ 35`.

## Config highlights

- **Study type:** incidence (build default); `assoc_model = "logistic"` — no cox/KM gate blocks
- **Methods:** `adaboost`, `tabpfnv2`, `catboost`, `xgboost`, `lightgbm`, `rf`
- **Age:** `age_cutoff = 35L` on subgroup / subgroup_incidence / nhanes / sensitivity_suite / subgroup_fallback; psoriasis preset `nhanes$age_group_cutoffs` nulled
- **Exclusion:** Task 2 disease_vars pasted exactly; Gender dropped (all-female)
- **Batch:** `index_group=all`, `workers=10`, `db_mode=nhanes`, `fail_policy=continue`
- **Path fix:** when `source(config.R)` without `--config`, resolve study root via `sys.frame()$ofile` (avoids cwd = MEDICAL_BLOCKS_ROOT pointing at wrong Data/)

## Concerns / follow-ups

1. **TabPFN Python path** is Windows (`C:/ProgramData/anaconda3/python.exe`) — same as ovarian cancer; WSL-only runs will need a local python override for tabpfnv2.
2. **Task 4** must launch with `--config <study>/config.R --workers 10 --db nhanes`; do not start from this task.
3. Preset psoriasis still carries unused survival/cox defaults in the base list; they are inert for incidence ML batch (not overridden to cox).

## Commits

None (explicitly skipped).
