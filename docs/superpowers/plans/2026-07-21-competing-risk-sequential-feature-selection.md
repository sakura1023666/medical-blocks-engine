# Competing Risk Sequential Feature Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace competing-risk-specific LASSO/RF blocks with the generic univariate Cox → Cox-LASSO → random-forest RFE chain, build deterministic nested Model 1–6 covariates, label every indicator directory as `【success】` or `【failed】`, then rerun all 95 MIMIC indicators with 20 workers.

**Architecture:** Derive a binary primary-event column for feature selection while retaining the original competing-event status for Fine-Gray. Add opt-in candidate routing to the generic feature-selection blocks so existing pipelines keep their current behavior. Resolve Model 2/5 and Model 3/6 from RF-ranked and univariate-ranked variables with a deterministic nesting policy.

**Tech Stack:** R, survival, glmnet, caret, randomForest, cmprsk, jsonlite, openxlsx, processx.

## Global Constraints

- MIMIC single-database batch uses all 95 `.composite_index_vars`.
- Feature selection order is strictly `univariate_prognosis → feature_selection_lasso → feature_selection_random_forest`.
- Univariate screening cutoff is `P < 0.10`.
- No significance-seeking random covariate search is allowed.
- Model 2/5 must be a proper subset of Model 3/6.
- If RF selects one variable, supplement Model 3/6 with the next eligible univariate variable.
- Fine-Gray Models 1–3 and Standard Cox Models 4–6 use the same nested covariate tiers.
- Trajectory clustering remains LMM BLUP + mclust K=2–4, minimum class proportion 5%, no tercile fallback.
- Preserve raw files under the result root `data/`; remove generated outputs/checkpoints before rerun.
- Do not create a git commit unless the user explicitly requests one.

---

### Task 1: Add primary-event feature-selection outcome

**Files:**
- Modify: `R/utils.R` in `pipeline_derive_competing_diabetes_28d()`
- Modify: `configs/templates/config_competing_risk_stroke_batch.template.R`
- Modify: `/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/config_competing_risk_stroke_batch.R`
- Create: `scripts/test_competing_sequential_feature_selection.R`

**Interfaces:**
- Produces data column: `competing_primary_event: integer`, equal to `1L` only when `competing_status_28d == primary_cause`, otherwise `0L`.
- Produces config: `survival$time_var`, `survival$event_var`, and `data$outcome_column` pointing to the feature-selection outcome.
- Preserves `competing_risk$event_type_col = "competing_status_28d"` for Fine-Gray.

- [ ] **Step 1: Write a failing derivation test**

Add synthetic assertions to `scripts/test_competing_sequential_feature_selection.R`:

```r
status <- c(0L, 1L, 2L, 3L)
primary <- 1L
got <- as.integer(status == primary)
stopifnot(identical(got, c(0L, 1L, 0L, 0L)))
```

Load the pipeline-derived test fixture and assert that `competing_primary_event` exists and is binary.

- [ ] **Step 2: Run the test and verify failure**

Run:

```bash
Rscript scripts/test_competing_sequential_feature_selection.R
```

Expected: fail because `competing_primary_event` is not yet generated/configured.

- [ ] **Step 3: Implement binary outcome derivation**

After `competing_status_28d` is assigned in `pipeline_derive_competing_diabetes_28d()`, add:

```r
primary_cause <- as.integer(cr$primary_cause %||% 1L)[1L]
data$competing_primary_event <- as.integer(
  !is.na(data$competing_status_28d) &
    as.integer(data$competing_status_28d) == primary_cause
)
```

Configure:

```r
data$outcome_column = "competing_primary_event"
survival = list(
  time_var = "competing_time_28d",
  event_var = "competing_primary_event",
  index_var = "NLR"
)
univariate_prognosis = list(
  sig_cutoff = 0.05,
  screening_cutoff = 0.10,
  pause_enable = FALSE,
  fail_on_index_ns = FALSE
)
```

- [ ] **Step 4: Run derivation tests**

Run:

```bash
Rscript scripts/test_competing_sequential_feature_selection.R
```

Expected: primary-event assertions pass.

---

### Task 2: Route generic LASSO from univariate candidates

**Files:**
- Modify: `Blocks/19_feature_selection/01block_feature_selection_lasso.R`
- Extend test: `scripts/test_competing_sequential_feature_selection.R`

**Interfaces:**
- Consumes: `config$feature_selection_lasso$candidate_source = "univariate"`.
- Consumes: `ctx$results$univar_features`.
- Produces: `ctx$results$feature_selection_by_model$lasso`.

- [ ] **Step 1: Add a failing candidate-routing test**

Create a minimal context with:

```r
ctx$results$Model2Factors <- c("WrongA", "WrongB", "WrongC")
ctx$results$univar_features <- c("Age", "BMI", "HbA1c")
ctx$config$feature_selection_lasso$candidate_source <- "univariate"
```

Assert that the resolved candidates equal `c("Age", "BMI", "HbA1c")`.

- [ ] **Step 2: Run the test and verify failure**

Run the test script. Expected: current code prefers `Model2Factors`.

- [ ] **Step 3: Add the opt-in routing helper**

In `block_feature_selection_lasso()`, resolve `cand0` as:

```r
candidate_source <- tolower(trimws(
  as.character(bl_cfg$candidate_source %||% "auto")[1L]
))
cand0 <- if (identical(candidate_source, "univariate")) {
  uv_cand
} else {
  # retain the existing auto / Model2Factors fallback logic unchanged
}
```

Keep the current default `auto` so other studies are unaffected.

- [ ] **Step 4: Verify LASSO routing**

Run the test script. Expected: exact univariate candidate set is used.

---

### Task 3: Route generic random forest from LASSO candidates

**Files:**
- Modify: `Blocks/19_feature_selection/04block_feature_selection_random_forest.R`
- Extend test: `scripts/test_competing_sequential_feature_selection.R`

**Interfaces:**
- Consumes: `config$feature_selection_random_forest$candidate_source = "lasso"`.
- Consumes: `ctx$results$feature_selection_by_model$lasso`.
- Produces: ordered `ctx$results$feature_selection_by_model$random_forest`.

- [ ] **Step 1: Add a failing RF routing test**

Set:

```r
ctx$results$univar_features <- c("Age", "BMI", "HbA1c")
ctx$results$feature_selection_by_model$lasso <- c("Age", "HbA1c")
ctx$config$feature_selection_random_forest$candidate_source <- "lasso"
```

Assert that RF sees only `c("Age", "HbA1c")`.

- [ ] **Step 2: Run the test and verify failure**

Expected: current RF block resolves candidates from Model2/univariate, not LASSO.

- [ ] **Step 3: Implement LASSO-source routing**

Add:

```r
lasso_cand <- as.character(
  ctx$results$feature_selection_by_model$lasso %||% character(0)
)
candidate_source <- tolower(trimws(
  as.character(bl_cfg$candidate_source %||% "auto")[1L]
))
cand0 <- if (identical(candidate_source, "lasso")) {
  lasso_cand
} else {
  # preserve existing auto behavior
}
```

After RFE, store a deterministic ranking using `fit_rf$variables` importance when available, followed by selected feature order.

- [ ] **Step 4: Verify RF routing and deterministic order**

Run the test script. Expected: RF candidate set exactly equals LASSO output and repeated resolution yields identical order.

---

### Task 4: Build deterministic nested Model 2/5 and Model 3/6 covariates

**Files:**
- Modify: `Blocks/55_competing_risk_full/09block_competing_models_123.R`
- Extend test: `scripts/test_competing_sequential_feature_selection.R`

**Interfaces:**
- Consumes:
  - `ctx$results$feature_selection_by_model$random_forest`
  - RF ranking
  - `ctx$results$univar_coef`
  - `competing_risk$demographic_vars`
- Produces: `ctx$results$competing_model_covs$m1/m2/m3`.

- [ ] **Step 1: Write table-driven failing tests**

Cover:

```r
# RF has proper demographic subset
RF = c("Age", "HbA1c")        # m2=Age, m3=Age+HbA1c

# RF has no demographics; univariate demographic is eligible
RF = c("HbA1c", "CHD")        # m2=Age, m3=Age+HbA1c+CHD

# no eligible demographics
RF = c("HbA1c", "CHD")        # m2=HbA1c, m3=HbA1c+CHD

# one RF variable; supplement from univariate
RF = c("HbA1c")               # m2=HbA1c, m3=HbA1c+CHD
```

Assert `length(m2) >= 1`, `m2` is a proper subset of `m3`, and no exposure variable is included.

- [ ] **Step 2: Run tests and verify current union-based resolver fails**

Expected: `.competing_resolve_model_covs()` currently reads specialized LASSO/RF union and fixed demographics.

- [ ] **Step 3: Implement nested resolver**

Replace the specialized result reads with generic RF/univariate results. Apply this order:

1. eligible RF demographics when they form a proper subset;
2. univariate demographics with `P < 0.10`;
3. top-ranked RF variable;
4. if RF has one variable, supplement with the lowest-P eligible univariate variable;
5. throw `MODEL_COVARIATE_INSUFFICIENT` if no proper nesting is possible.

Set:

```r
m1 <- character(0)
m2 <- unique(model2_vars)
m3 <- unique(c(m2, rf_vars, supplement_vars))
```

Verify `length(setdiff(m3, m2)) >= 1L` before fitting.

- [ ] **Step 4: Run nested-model tests**

Expected: all scenarios pass and footnotes list the exact covariates.

---

### Task 5: Replace pipeline blocks and delete obsolete competing blocks

**Files:**
- Modify: `R/pipeline_runner.R`
- Modify: `configs/templates/config_competing_risk_stroke_batch.template.R`
- Modify: `/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/config_competing_risk_stroke_batch.R`
- Modify: `Decisiontree/decision_tree_competing_risk_stroke_diabetes.md`
- Modify: `docs/superpowers/specs/2026-07-20-competing-risk-stroke-diabetes-design.md`
- Delete: `Blocks/55_competing_risk_full/04block_competing_lasso_screen.R`
- Delete: `Blocks/55_competing_risk_full/08block_competing_rf_screen.R`

**Interfaces:**
- Pipeline order becomes:
  `competing_baseline_trajectory → univariate_prognosis → feature_selection_lasso → feature_selection_random_forest → competing_finegray`.

- [ ] **Step 1: Add a static pipeline-order assertion**

In the test script, source the active config and assert:

```r
expected <- c(
  "univariate_prognosis",
  "feature_selection_lasso",
  "feature_selection_random_forest"
)
pos <- match(expected, pipeline_unit$blocks)
stopifnot(all(!is.na(pos)), identical(pos, sort(pos)))
stopifnot(!any(c("competing_lasso_screen", "competing_rf_screen") %in% pipeline_unit$blocks))
```

- [ ] **Step 2: Replace old block names and add feature-selection configs**

Configure:

```r
feature_selection = list(
  restrict_to_train = FALSE,
  target_n_features_min = 1L,
  target_n_features_max = 8L
)
feature_selection_lasso = list(
  candidate_source = "univariate",
  lasso_use_cox = TRUE,
  lasso_cv_times = 100L,
  target_n_features_min = 1L,
  target_n_features_max = 8L,
  pause_enable = FALSE
)
feature_selection_random_forest = list(
  candidate_source = "lasso",
  target_n_features_min = 1L,
  target_n_features_max = 8L,
  pause_enable = FALSE
)
```

Use 100 LASSO repetitions for the 95-unit batch to keep runtime bounded; retain the generic block default of 1000 for other studies.

- [ ] **Step 3: Remove obsolete sources and mappings**

Delete both specialized files and their entries in `pipeline_block_sources()`. Update all non-archive competing-risk templates/docs so no active reference remains.

- [ ] **Step 4: Run static tests**

Run:

```bash
Rscript scripts/test_competing_sequential_feature_selection.R
rg "competing_lasso_screen|competing_rf_screen" \
  R Blocks configs/templates Decisiontree docs/superpowers/specs
```

Expected: test passes; search has no active pipeline references.

---

### Task 6: Enrich status summaries and verify directory labels

**Files:**
- Modify: `run/study/run_study_batch_worker.R`
- Modify: `R/study_batch_runner.R`
- Extend test: `scripts/test_competing_sequential_feature_selection.R`

**Interfaces:**
- Worker status fields: `failed_stage`, `trajectory_k`, `final_covariates`, `model2_covariates`, `model3_covariates`.
- Directory output: `by_unit/【success】{Index}` or `by_unit/【failed】{Index}`.
- Summary output: `Tables/Indicator_availability.csv` and `.xlsx`.

- [ ] **Step 1: Add status-label tests**

Test `incidence_batch_output_dir_name("NLR", "success") == "【success】NLR"` and the failed equivalent. Test failed-stage extraction for:

```r
TRAJECTORY_CLUSTER_FAIL
BASELINE_INDEX_NS_STOP
PAUSE_FOR_USER_DECISION: feature_selection_lasso
MODEL_COVARIATE_INSUFFICIENT
```

- [ ] **Step 2: Capture final context on success**

Change the worker to:

```r
final_ctx <- run_pipeline(...)
.write_status("success", ctx = final_ctx)
```

Extend `.write_status()` to serialize trajectory K and final model covariates. On errors, infer `failed_stage` deterministically from the error prefix.

- [ ] **Step 3: Write availability summaries**

After directory renaming, create rows containing:

```r
data.frame(
  index = statuses$unit,
  status_cn = ifelse(statuses$status == "success", "可用", "失败"),
  status = statuses$status,
  failed_stage = statuses$failed_stage,
  error_message = statuses$error_message,
  trajectory_k = statuses$trajectory_k,
  final_covariates = statuses$final_covariates,
  elapsed_sec = statuses$elapsed_sec
)
```

Write CSV and XLSX under `Tables/Indicator_availability.*`.

- [ ] **Step 4: Run status tests**

Expected: label names, status fields, and summary schema pass.

---

### Task 7: Validate, clean generated outputs, and rerun

**Files:**
- Preserve: `/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/data/` raw inputs
- Delete generated result/checkpoint directories under that result root

**Interfaces:**
- Shared run produces 95 `units` and valid/empty `12_*.RData` results.
- Unit run uses 20 workers and produces one labeled directory per indicator.

- [ ] **Step 1: Run static verification**

Run:

```bash
Rscript scripts/test_competing_sequential_feature_selection.R
Rscript -e 'source("/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/config_competing_risk_stroke_batch.R"); stopifnot(length(.test_units)==95L, config$study_batch$parallel_workers==20L)'
```

Expected: exit 0.

- [ ] **Step 2: Remove only generated outputs**

Delete `by_unit`, `checkpoints`, `_shared`, `Tables`, `Figures`, `logs`, and `data/mimic/12_*.RData`. Preserve all other files in `data/`.

- [ ] **Step 3: Run shared layer**

Run:

```bash
Rscript run/competing_risk/run_competing_risk_chf_batch.R \
  --config "/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/config_competing_risk_stroke_batch.R" \
  --shared-only --no-skip
```

Expected: `Pipeline finished: competing_stroke_shared`, units count 95.

- [ ] **Step 4: Run NLR smoke test**

Run:

```bash
Rscript run/competing_risk/run_competing_risk_chf_batch.R \
  --config "/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/config_competing_risk_stroke_batch.R" \
  --only-unit NLR --workers 1 --no-skip
```

Expected: logs show strict univariate → LASSO → RF order. Either `【success】NLR` or `【failed】NLR` must exist with a specific status reason; no interface/runtime error is allowed.

- [ ] **Step 5: Remove NLR smoke output and launch all 95 units**

Run:

```bash
Rscript run/competing_risk/run_competing_risk_chf_batch.R \
  --config "/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/config_competing_risk_stroke_batch.R" \
  --workers 20 --no-skip
```

Expected: 20 workers launch and eventually all 95 units receive labeled directories.

- [ ] **Step 6: Verify final labels and summaries**

Assert:

```bash
test "$(find '/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/by_unit' -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 95
```

Confirm every basename starts with `【success】` or `【failed】`, and inspect `Tables/Indicator_availability.xlsx`.
