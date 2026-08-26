# Disease and Index-Component Hard Exclusion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure disease-related variables, the current composite index's transitive raw components, and all other composite indices never enter analysis/publication tables or covariate selection, while excluding disease-derived indices from the batch.

**Architecture:** Add reusable formula-introspection helpers around `.idx_definitions()`, then resolve one exclusion manifest per active index. Keep required source variables only until the exposure is materialized; exclude them from the earliest Table S1 and hard-delete them from unit analysis copies immediately after `competing_index_exposure`.

**Tech Stack:** R, base expression parsing (`parse`, `all.vars`), existing block registry, existing script-based tests.

## Global Constraints

- Disease variables are configured per study; reusable code must not hard-code diabetes.
- Current-index component scope is `current_transitive`.
- Disease matching is case/separator normalized, not fuzzy substring matching.
- Current index and its quartile/trajectory columns remain available as exposures.
- Other composite indices, disease variables, and current-index components must not appear in any analysis/publication table or model candidate set.
- Formula resolution failure must stop with `EXCLUSION_COMPONENT_RESOLVE_FAIL`.
- No git commit because this workspace is not a Git repository and the user did not request one.

---

### Task 1: Formula dependency resolver

**Files:**
- Modify: `Blocks/00_index/01block_index.R`
- Test: `scripts/test_competing_sequential_feature_selection.R`

**Interfaces:**
- Produces: `pipeline_index_definition_map(): named character`
- Produces: `pipeline_index_raw_components(index_var, definitions = pipeline_index_definition_map()): character`
- Produces: `pipeline_indices_using_vars(vars, indices, definitions): character`

- [ ] **Step 1: Add failing resolver tests**

Assert:

```r
stopifnot(setequal(
  pipeline_index_raw_components("NLR"),
  c("Neutrophil_Count", "Lymphocytes")
))
stopifnot(setequal(
  pipeline_index_raw_components("ALI"),
  c("Weight", "Height", "Albumin", "Neutrophil_Count", "Lymphocytes")
))
excluded_units <- pipeline_indices_using_vars(
  c("T1DM", "T2DM", "Diabetes", "HbA1c"),
  .composite_index_vars
)
stopifnot(all(c("SHR", "HGI", "HbA1c_HDL_C", "eGDR", "HSI", "NFS", "FSI") %in% excluded_units))
```

- [ ] **Step 2: Run RED test**

Run:

```bash
Rscript scripts/test_competing_sequential_feature_selection.R
```

Expected: fail because resolver functions do not exist.

- [ ] **Step 3: Implement expression parsing and recursion**

Build the map from each `.idx_definitions()` entry's `name` and `expr`. Resolve `all.vars(parse(text = expr))`; recursively expand names that are also indices. Detect cycles and missing definitions. Preserve deterministic first-seen order.

- [ ] **Step 4: Run GREEN test**

Run the same test and expect all resolver assertions to pass.

---

### Task 2: Reusable exclusion manifest and unit-data block

**Files:**
- Create: `Blocks/03_imputation/03block_analysis_exclusion.R`
- Modify: `R/pipeline_runner.R`
- Modify: `R/study_batch_runner.R`
- Test: `scripts/test_competing_sequential_feature_selection.R`

**Interfaces:**
- Consumes: `config$analysis_exclusion`
- Produces: `pipeline_analysis_exclusion_manifest(config, data_names = character()): list`
- Registers: `analysis_exclusion`
- Produces: `ctx$results$analysis_exclusion_manifest`

- [ ] **Step 1: Add failing manifest and hard-delete tests**

For active unit `NLR`, assert the manifest contains `T1DM`, `T2DM`, `HbA1c`,
`Neutrophil_Count`, `Lymphocytes`, and all other available composite indices,
but excludes `NLR`, `NLR_quartile`, `NLR_trajectory`, time/event and ID columns
from the drop list. Apply the block to synthetic `raw/cleaned/imputed` data and
assert all drop-list columns are absent.

- [ ] **Step 2: Run RED test**

Expected: fail because the manifest/block does not exist.

- [ ] **Step 3: Implement manifest resolution**

Normalize names by lower-casing and removing `_`, `-`, spaces and punctuation.
Resolve disease-variable aliases against actual columns, recursively resolve the
active index components, and add other composite indices. Throw:

```r
stop(
  "EXCLUSION_COMPONENT_RESOLVE_FAIL: 无法解析指标 ", index_var,
  call. = FALSE
)
```

when the active index has no resolvable definition.

- [ ] **Step 4: Implement and register hard-delete block**

Delete manifest `drop_vars` from each non-null `ctx$data$raw`,
`ctx$data$cleaned`, and `ctx$data$imputed`. Write a CSV audit manifest under
the unit Tables directory, but do not place excluded values in it.

- [ ] **Step 5: Wire per-unit configuration**

In `study_batch_patch_config_for_unit()`, resolve the same manifest and append
its table exclusions to:

```r
cfg$imputation$table_s1_exclude_vars
cfg$univariate_prognosis$excluded_predictors
```

Register the new block source in `pipeline_block_sources()`.

- [ ] **Step 6: Run GREEN test**

Expected: manifest and deletion tests pass.

---

### Task 3: Filter disease-derived exposure units

**Files:**
- Modify: `configs/templates/config_competing_risk_stroke_batch.template.R`
- Modify: `/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/config_competing_risk_stroke_batch.R`
- Test: `scripts/test_competing_sequential_feature_selection.R`

**Interfaces:**
- Produces: `.disease_related_index_units`
- Produces: `.test_units = setdiff(.composite_index_vars, .disease_related_index_units)`

- [ ] **Step 1: Add failing live-config test**

Assert that `.test_units` excludes every result from
`pipeline_indices_using_vars(config$analysis_exclusion$disease_vars, .composite_index_vars)`
and that `trajectory_calc_28d_index$index_vars` and `study_batch$units` are
identical to `.test_units`.

- [ ] **Step 2: Run RED test**

Expected: existing config still contains disease-derived indices.

- [ ] **Step 3: Add configuration and filtered unit list**

Configure:

```r
analysis_exclusion = list(
  disease_vars = c("T1DM", "T2DM", "Diabetes", "HbA1c"),
  component_scope = "current_transitive",
  exclude_other_composite_indices = TRUE,
  exclude_exposure_if_uses_disease_var = TRUE
)
```

Source the index definition helpers before resolving `.test_units`.

- [ ] **Step 4: Run GREEN test**

Expected: filtered units and shared/worker lists are exactly identical.

---

### Task 4: Guarantee exclusion from every analysis table

**Files:**
- Modify: `Blocks/55_competing_risk_full/14block_competing_baseline_quartile.R`
- Modify: `Blocks/55_competing_risk_full/15block_competing_baseline_trajectory.R`
- Modify: `Blocks/03_imputation/01block_imputation.R` only if configuration propagation is insufficient
- Modify: `Decisiontree/decision_tree_competing_risk_stroke_diabetes.md`
- Test: `scripts/test_competing_sequential_feature_selection.R`

**Interfaces:**
- Baseline exclusion consumes `ctx$results$analysis_exclusion_manifest$drop_vars`
  or recomputes the same manifest from config.

- [ ] **Step 1: Add failing table-variable tests**

Build synthetic NLR data and assert `.competing_baseline_all_vars()` omits
disease variables, NLR raw components, and other composite indices while
retaining NLR.

- [ ] **Step 2: Run RED test**

Expected: current baseline helper admits excluded variables.

- [ ] **Step 3: Apply defense-in-depth table exclusions**

Merge manifest exclusions into `.competing_baseline_exclude_vars()`. Keep the
hard-delete block as the primary boundary and table-level exclusion as defense
in depth.

- [ ] **Step 4: Update pipeline order and decision tree**

The active sequence must include:

```r
"competing_index_exposure",
"analysis_exclusion",
"trim_index_extreme"
```

Document the disease-derived unit filter and two-stage exclusion.

- [ ] **Step 5: Run GREEN test**

Expected: all table-variable assertions pass and pipeline order is exact.

---

### Task 5: Verify, clean, and rerun

**Files:**
- Preserve raw files under result-root `data/`
- Remove generated unit/shared outputs before rerun

**Interfaces:**
- Smoke result must show excluded variables absent from Table S1, Table 1/3,
  `univar_features`, LASSO, RF, and Model 2/3.

- [ ] **Step 1: Run static suite**

```bash
Rscript scripts/test_competing_sequential_feature_selection.R
```

Expected: `ALL PASS`.

- [ ] **Step 2: Clean invalid generated outputs**

Delete `by_unit`, `checkpoints`, `_shared`, `Tables`, `Figures`, `logs`, and
`data/mimic/12_*.RData`; preserve all other raw files under `data/`.

- [ ] **Step 3: Run shared layer**

```bash
Rscript run/competing_risk/run_competing_risk_chf_batch.R \
  --config "/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/config_competing_risk_stroke_batch.R" \
  --shared-only --no-skip
```

Expected: unit count equals the filtered `.test_units`.

- [ ] **Step 4: Run NLR smoke**

Run one NLR worker. Inspect generated CSV/XLSX variable names and checkpoint
candidate sets. Expected: no disease variable, NLR component, or other
composite-index leakage. `BASELINE_INDEX_NS_STOP` remains an acceptable
scientific early stop after table exclusion is verified.

- [ ] **Step 5: Launch filtered full batch**

```bash
Rscript run/competing_risk/run_competing_risk_chf_batch.R \
  --config "/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/config_competing_risk_stroke_batch.R" \
  --workers 20 --no-skip
```

Expected: only filtered units launch and all completed unit directories receive
`【success】` or `【failed】` prefixes.
