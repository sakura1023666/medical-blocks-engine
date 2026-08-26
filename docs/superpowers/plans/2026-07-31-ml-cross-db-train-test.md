# ML Cross-DB Train/Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ML dual-batch produce one cross-DB train/test result set (larger DB = train, smaller = test), add shared-layer index screening OR/HR table, fix duplicate figure DB prefixes; then wipe and re-run RAR only.

**Architecture:** Add `config$ml_batch$split_mode = "cross_db"` (default for new studies via build). In that mode the per-index worker loads both DBs once, assigns roles by `n`, fits imputation on train only, sets `ctx$data$train` / `ctx$data$test` (existing ML slot names; alias `imputed` for single-DB association blocks), skips secondary’s separate internal 70/30 pipeline, and writes one `by_index/<ix>/` tree. Keep `split_mode = "per_db_internal"` for old behavior.

**Tech Stack:** R 4.5 / medical-blocks pipeline, mice, existing Blocks 00–23, processx workers.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-31-ml-cross-db-train-test-design.md`
- Prefer existing ctx slots: `ctx$data$train`, `ctx$data$test`, `ctx$data$imputed` (do **not** rename all ML blocks to `data_train`)
- Test-set rows must not fit imputation / LASSO / ML tuning
- No time var → skip Cox, KM, subgroup HR
- Index screening table does **not** auto-filter `index_vars`
- Do **not** git commit unless user asks
- Verify only with `--only-index RAR` after wipe

## File map

| File | Responsibility |
|------|----------------|
| `R/ml_cross_db_split.R` (create) | Role assignment by n; build combined train/test frames |
| `Blocks/03_imputation/01block_imputation.R` | Optional train-fit / test-transform when `imputation$fit_on = "train"` |
| `Blocks/21_train_validation/01block_train_validation.R` | `mode = "passthrough"` when train/test already set |
| `configs/study_interface/ml_dual_batch_pipelines.R` | Cross-db pipeline list |
| `run/ml/run_ml_dual_batch_worker.R` | Cross-db single-run path |
| `R/ml_dual_batch_runner.R` / incidence helpers | Output dir without per-DB full dual loop when cross_db |
| `Blocks/.../index_screening_or_hr` (create) | Shared-layer screening table |
| `R/utils.R` `.inject_db_into_pub_label` + mirror/curate | Stop double DB prefix in cross_db |
| `configs/study_interface/ml_dual_batch_build.R` | Default `split_mode`, wire screening |
| Study `config.R` | `split_mode = "cross_db"` |

---

### Task 1: Role assignment helper

**Files:**
- Create: `R/ml_cross_db_split.R`
- Test: manual Rscript smoke in step 4

**Interfaces:**
- Produces: `ml_cross_db_assign_roles(db_frames, primary_name)` → `list(assignment = data.frame(role, db_name, n, n_event), train_db, test_dbs)`
- Produces: `ml_cross_db_bind_role(frames, assignment)` → named list of raw frames by role before imputation

- [ ] **Step 1: Implement assign_roles**

```r
# R/ml_cross_db_split.R
ml_cross_db_assign_roles <- function(db_n, primary_name = NULL, event_counts = NULL) {
  # db_n: named integer vector of analysis n per db
  stopifnot(length(db_n) >= 1L, !is.null(names(db_n)))
  ord <- order(-as.integer(db_n), !(names(db_n) %in% primary_name), names(db_n))
  nm <- names(db_n)[ord]
  roles <- if (length(nm) == 1L) {
    c(train = nm[[1L]])
  } else {
    c(train = nm[[1L]], setNames(nm[-1L], c("test", if (length(nm) > 2L) paste0("test", seq_len(length(nm) - 2L) + 1L) else character())))
  }
  # return data.frame role, db_name, n, n_event
}
```

- [ ] **Step 2: Source from pipeline bootstrap** (ensure `R/ml_cross_db_split.R` is sourced in `run/ml/run_ml_dual_batch.R` / worker alongside other `R/*.R` helpers — mirror how `ml_dual_pipeline_helpers.R` is loaded).

- [ ] **Step 3: Smoke**

```bash
Rscript -e 'source("R/ml_cross_db_split.R"); print(ml_cross_db_assign_roles(c(MIMIC_IV=200L,eICU=100L), "MIMIC_IV"))'
```

Expected: train=MIMIC_IV, test=eICU.

---

### Task 2: Imputation fit-on-train

**Files:**
- Modify: `Blocks/03_imputation/01block_imputation.R`
- Config key: `config$imputation$fit_on` ∈ `c("all","train")` default `"all"`

**Interfaces:**
- Consumes: `ctx$data$train` / `ctx$data$test` already populated with pre-imputation rows when `fit_on="train"`
- Produces: imputed `ctx$data$train`, `ctx$data$test`, and `ctx$data$imputed = rbind(train,test)` for association blocks that want pooled

- [ ] **Step 1:** At start of `block_imputation`, if `identical(cfg$fit_on, "train")`:
  - Require `ctx$data$train`
  - Run `mice` on train only; `mice::mice` + complete
  - For test: use `mice::mice` with method that applies train imputations — prefer `mice::complete` on a model built with `ignore` or manual median/mode from train for numeric/factor (document chosen method in block header). Minimal correct approach for this codebase: fit mice on train; for test columns, impute each NA with train-column median (numeric) or mode (factor) from completed train (fast, no leakage). Store note in `Tables/Imputation_fit_on_train.txt`.
  - Set `ctx$data$imputed <- rbind(train_imp, test_imp)`.

- [ ] **Step 2:** Leave `fit_on="all"` path unchanged.

---

### Task 3: train_validation passthrough

**Files:**
- Modify: `Blocks/21_train_validation/01block_train_validation.R` around `block_train_validation` (~348+)

- [ ] **Step 1:** If `isTRUE(cfg$passthrough) || identical(cfg$mode, "passthrough")`:
  - Require non-null `ctx$data$train` and `ctx$data$test`
  - Optionally export baseline Table 1 train vs test
  - `return(ctx)` without `rsample` split

- [ ] **Step 2:** In `ml_dual_batch_build.R` / overrides, when `split_mode=="cross_db"`: set `config$train_validation$passthrough <- TRUE` and `config$imputation$fit_on <- "train"`.

---

### Task 4: Cross-db worker path (one pipeline per index)

**Files:**
- Modify: `run/ml/run_ml_dual_batch_worker.R`
- Modify: `R/incidence_dual_batch_runner.R` (`incidence_batch_apply_db_overrides` usage)
- Modify: `configs/study_interface/ml_dual_batch_pipelines.R`

**Interfaces:**
- When `config$ml_batch$split_mode == "cross_db"` (or `config$incidence_batch$split_mode`):
  - Do **not** loop `for (db in c("nhanes","mimic"))` full pipelines
  - Load shared checkpoints for both DBs for this index
  - Assign roles via Task 1
  - Build `ctx` with `output_dir = by_index/<ix>/` (flat, no `<DB>/` child pipeline root)
  - Set pre-imputation `ctx$data$train` / `test` from role DBs (after column harmonize + index already in shared ck)
  - Run single pipeline: imputation → trim → train_validation(passthrough) → baseline/univariate/VIF/LASSO/ML/SHAP/subgroup
  - Skip `pipeline_mimic_ml_batch`

- [ ] **Step 1:** Add helper `ml_batch_run_cross_db_index(config, root, ix)` in `R/ml_dual_batch_runner.R` or worker file that performs the above.

- [ ] **Step 2:** Branch at top of worker after resolving `ix`:

```r
if (identical(config$ml_batch$split_mode %||% "per_db_internal", "cross_db")) {
  ml_batch_run_cross_db_index(config, root, ix)
  quit(save = "no", status = 0L)
}
```

- [ ] **Step 3:** Ensure finalize/mirror does not expect two DB subfolders; write status json success once.

- [ ] **Step 4:** Association blocks (logistic/RCS/Cox/KM): for cross_db use train+test via existing dual patterns where possible; single-db still uses `imputed`. Wire `config$association$data_source` if needed: `"imputed"` vs `"train_test"`.

---

### Task 5: Index screening OR/HR table

**Files:**
- Create: `Blocks/00_index/02block_index_screening_or_hr.R` (or `Blocks/29_...`)
- Register in `R/pipeline_runner.R` block map
- Hook after shared-layer index in `run_ml_dual_batch` (once, train-candidate DB = max n)

**Output columns:** 复合指标名, 变量名, 计算公式, 总样本量, DN=1的人数, OR, P_OR, HR, P_HR

- [ ] **Step 1:** For each name in `.composite_index_vars_dual_safe` (or `index_group` candidate list), if components present and `n_valid >= 50`, fit univariate logistic of outcome ~ index; if `time_var` present fit coxph; else HR/P = NA.

- [ ] **Step 2:** Write `file.path(root, "Tables", "Index_screening_OR_HR.csv")` (create Tables under study root).

- [ ] **Step 3:** Call from `run_ml_dual_batch` after shared ck complete; do not change `index_vars`.

---

### Task 6: Fix duplicate figure DB prefixes

**Files:**
- Modify: `R/utils.R` `.inject_db_into_pub_label` and/or call sites
- Modify: `R/dual_db_harmonize.R` mirror `prefix_db` behavior when `split_mode=="cross_db"`
- Modify: `R/incidence_dual_batch_runner.R` `incidence_batch_ml_pub_figure_target_bn`
- Study config: `mirror_aggregate_prefix_db = FALSE` under cross_db **or** engine forces false when cross_db

- [ ] **Step 1:** When cross_db, set `config$dual_db$mirror_aggregate_prefix_db <- FALSE` and `pipeline$database_name <- "Train-Test"` (or `sprintf("Train(%s)-Test(%s)", train_db, test_db)` once).

- [ ] **Step 2:** In `.inject_db_into_pub_label`, if label already contains the db token, return unchanged.

- [ ] **Step 3:** Smoke: fake basename `Figure 3-MIMIC_IV. ML performance` + inject MIMIC_IV → unchanged.

---

### Task 7: Study config + wipe + re-run RAR

**Files:**
- Modify: `/mnt/g/02block_result/17_pancreatic carcinoma/ml_40395549/config.R`

- [ ] **Step 1:** Add:

```r
config$ml_batch$split_mode <- "cross_db"
config$incidence_batch$split_mode <- "cross_db"
config$dual_db$mirror_aggregate_prefix_db <- FALSE
```

- [ ] **Step 2:** Kill any running pancreatic ML batch; delete RAR outputs:

```bash
# kill via C:/Users/Public/kill_pc_ml.ps1
BASE="/mnt/g/02block_result/17_pancreatic carcinoma/ml_40395549"
rm -rf "$BASE/by_index/"*RAR* "$BASE/checkpoints/by_index/"*RAR* "$BASE/logs/RAR.log"
```

- [ ] **Step 3:** Re-run:

```bash
cd /mnt/g/DockerHome/5003/medical-blocks-studies
export MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final
./run_study.sh "17_pancreatic carcinoma" --workers 1 --no-skip --only-index RAR
```

- [ ] **Step 4: Verify**
  - `by_index/【success】RAR/` (or `RAR/`) has **one** ML Figure 3, not per-DB duplicates with double names
  - `Tables/Train_test_assignment.csv` roles match n
  - `Tables/Index_screening_OR_HR.csv` exists at study root
  - TabPFN evalresult present; no `'/c' not found` / HF download
  - No time-skip regressions (futime present → Cox/KM/HR allowed)

---

## Spec coverage check

| Spec section | Task |
|--------------|------|
| §3 role rules | Task 1 |
| §4 imputation train-fit | Task 2 |
| §4 passthrough / slots | Task 3 |
| §2/§5 single pipeline output | Task 4 |
| §6 screening table | Task 5 |
| §7 figure dedupe | Task 6 |
| §9 RAR verify | Task 7 |
| `per_db_internal` compat | Task 4 branch keeps old path |

## Placeholder scan

None intentional; imputation test-transform uses explicit median/mode from train (documented in Task 2).
