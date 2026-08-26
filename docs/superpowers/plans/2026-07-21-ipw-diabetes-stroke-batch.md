# IPW Diabetes Stroke Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a MIMIC ischemic-stroke IPW batch pipeline (Jin 2026 method mapped to diabetes via HbA1c≥6.5 → 28-day all-cause death), with composite-index parallel workers, full Fig1–5 / Table1 / sensitivity / supp outputs, Feishu sync, without modifying existing `55`/`58` projects.

**Architecture:** Shared layer (`data_clean → column_mapping → index`) computes composite indices and drops disease-formula units; each worker runs diabetes IPW + covariate chain with the current index in adjustment. New blocks live only under `Blocks/69_ipw_diabetes_stroke_full/`; existing IPTW/KM/Cox/subgroup/STEPP blocks are reused after registering missing names in `pipeline_runner.R`.

**Tech Stack:** R 4.5.1 (`Rscript.exe`), survival, WeightIt/ipw (as used by `34_IPTW`), mice, glmnet, caret, randomForest, jsonlite, processx, Feishu bitable API.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-21-ipw-diabetes-stroke-batch-design.md`
- R binary: `"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"` (Windows paths for data: `G:/02block_result/...`)
- Result root: `G:/02block_result/11_ischemic stroke/Medication_regimen_model_42118193/`
- Exposure: `Diabetes_HbA1c = 1{HbA1c >= 6.5}` after imputation; raw `HbA1c` excluded from PS/covariates
- Outcome: 28-day all-cause hospital death from merged prognosis (`death_within_hosp_28days`, time = `pmin(hosp_survival_day, 28)`)
- Pipeline order: `ipw_diabetes_exposure` **before** `analysis_exclusion`
- Do not edit `Blocks/55_*`, `Blocks/58_*`, or other finished project outputs
- New module prefix: `69_ipw_diabetes_stroke_full`
- Feishu app_token: `RBjfb2iwmamW14s4WhKcS7kwnie` (project config override; do not rewrite global `.env.feishu` unless asked)
- `mirror_pub_outputs_to_root = TRUE`
- Do not create a git commit unless the user explicitly requests one

## File map

| Path | Role |
|------|------|
| `Decisiontree/decision_tree_ipw_diabetes_stroke.md` | Human decision tree |
| `Blocks/69_ipw_diabetes_stroke_full/01–07block_*.R` | New literature-depth blocks |
| `R/pipeline_runner.R` | Append register paths only |
| `configs/templates/config_ipw_diabetes_stroke_batch.template.R` | Batch template |
| `G:/.../Medication_regimen_model_42118193/config_ipw_diabetes_stroke_batch.R` | Live project config |
| `run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R` | Batch entry |
| `run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch_worker.R` | Worker entry |
| `scripts/test_ipw_diabetes_exposure.R` | Unit smoke for exposure/outcome |
| `run/feishu/run_feishu_setup_*` or project sync via existing helpers | Feishu tables |

---

### Task 1: Decision tree + register missing IPTW/subgroup blocks

**Files:**
- Create: `Decisiontree/decision_tree_ipw_diabetes_stroke.md`
- Modify: `R/pipeline_runner.R` (append mappings only)

**Interfaces:**
- Produces runner keys: `iptw_balance`, `iptw_association`, `subgroup_iptw_weighted`, `subgroup_treatment_forest` pointing at existing `34_*` / `18_*` files.

- [ ] **Step 1: Write decision tree**

Create `Decisiontree/decision_tree_ipw_diabetes_stroke.md` with:

```markdown
# 分析决策树 — IPW 糖尿病 × 重症缺血性卒中（28天）

> Config：`…/Medication_regimen_model_42118193/config_ipw_diabetes_stroke_batch.R`
> Run：`run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R --config <路径>`
> 方法学：Jin 2026 IPW 映射；暴露 HbA1c≥6.5；结局 28 天全因死亡

## 共享层
`data_clean → column_mapping → index`（剔除含 HbA1c/Diabetes 公式的指标）

## 指标层主链
`imputation → ipw_diabetes_exposure → analysis_exclusion → trim → univariate → lasso → RF → iptw_balance → iptw_association → flowchart → KM pub → subgroup → STEPP → Cox sens → overlap → literature_targets → pub_export`

## 关键产出
Fig1–5 / Table1 / Sens(Cox+重叠权重) / S1–S2 / Table S1 / Indicator_availability
```

- [ ] **Step 2: Register missing blocks in pipeline_runner**

In `pipeline_block_sources()`, after existing `km_*` / `subgroup_*` entries, append (do not reorder unrelated keys):

```r
    iptw_balance                  = b("34_IPTW/01block_iptw_balance.R"),
    iptw_association              = b("34_IPTW/02block_iptw_association.R"),
    subgroup_iptw_weighted        = b("18_subgroup/08block_subgroup_iptw_weighted.R"),
    subgroup_treatment_forest     = b("18_subgroup/07block_subgroup_treatment_forest.R"),
```

- [ ] **Step 3: Verify keys resolve**

Run:

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" -e '
root <- "E:/01block/01Block-new-Final"
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
m <- pipeline_block_sources(root)
need <- c("iptw_balance","iptw_association","subgroup_iptw_weighted","subgroup_treatment_forest")
stopifnot(all(need %in% names(m)))
stopifnot(all(file.exists(unlist(m[need]))))
cat("OK\n")
'
```

Expected: `OK`

---

### Task 2: `ipw_diabetes_exposure` block + unit test

**Files:**
- Create: `Blocks/69_ipw_diabetes_stroke_full/01block_ipw_diabetes_exposure.R`
- Create: `scripts/test_ipw_diabetes_exposure.R`
- Modify: `R/pipeline_runner.R` (append `ipw_diabetes_exposure`)

**Interfaces:**
- Consumes: `ctx$data$imputed %||% ctx$data$cleaned` with `HbA1c`, and after merge `hosp_survival_day`, `death_within_hosp_28days`
- Produces columns: `Diabetes_HbA1c` (0/1), `surv_time_28d`, `surv_event_28d`
- Config key: `config$ipw_diabetes`

- [ ] **Step 1: Write failing test**

```r
# scripts/test_ipw_diabetes_exposure.R
root <- "E:/01block/01Block-new-Final"
setwd(root)
source("R/utils.R")
source("R/pipeline_runner.R")
hba1c <- c(5.5, 6.5, 7.0, NA)
thr <- 6.5
stopifnot(identical(
  as.integer(!is.na(hba1c) & hba1c >= thr),
  c(0L, 1L, 1L, NA_integer_)
))
src <- "Blocks/69_ipw_diabetes_stroke_full/01block_ipw_diabetes_exposure.R"
if (!file.exists(src)) stop("MISSING_BLOCK")
source(src)
cat("source_ok\n")
```

- [ ] **Step 2: Run test — expect MISSING_BLOCK**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" scripts/test_ipw_diabetes_exposure.R
```

- [ ] **Step 3: Implement block**

Create `Blocks/69_ipw_diabetes_stroke_full/01block_ipw_diabetes_exposure.R`:

```r
###############################################################################
#  ipw_diabetes_exposure — HbA1c≥threshold → Diabetes_HbA1c；派生 28 天生存结局
#
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  ipw_diabetes = list(
#    hba1c_var = "HbA1c",
#    hba1c_threshold = 6.5,
#    exposure_var = "Diabetes_HbA1c",
#    followup_days = 28L,
#    time_source = "hosp_survival_day",
#    event_source = "death_within_hosp_28days",
#    time_var = "surv_time_28d",
#    event_var = "surv_event_28d",
#    pause_enable = TRUE,
#    pause_on_missing_hba1c = TRUE
#  )
###############################################################################

block_ipw_diabetes_exposure <- function(ctx, ...) {
  cfg <- ctx$config
  bl <- cfg$ipw_diabetes %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("PAUSE_FOR_USER_DECISION: ipw_diabetes_exposure needs imputed/cleaned data", call. = FALSE)
  }
  hvar <- as.character(bl$hba1c_var %||% "HbA1c")[1L]
  thr  <- as.numeric(bl$hba1c_threshold %||% 6.5)[1L]
  evar <- as.character(bl$exposure_var %||% "Diabetes_HbA1c")[1L]
  if (!hvar %in% names(data)) {
    stop("PAUSE_FOR_USER_DECISION: missing HbA1c column: ", hvar, call. = FALSE)
  }
  x <- suppressWarnings(as.numeric(data[[hvar]]))
  data[[evar]] <- as.integer(!is.na(x) & x >= thr)

  tsrc <- as.character(bl$time_source %||% "hosp_survival_day")[1L]
  esrc <- as.character(bl$event_source %||% "death_within_hosp_28days")[1L]
  tvar <- as.character(bl$time_var %||% "surv_time_28d")[1L]
  yvar <- as.character(bl$event_var %||% "surv_event_28d")[1L]
  days <- as.integer(bl$followup_days %||% 28L)[1L]
  if (!tsrc %in% names(data) || !esrc %in% names(data)) {
    stop("PAUSE_FOR_USER_DECISION: missing survival source columns ", tsrc, "/", esrc, call. = FALSE)
  }
  tt <- suppressWarnings(as.numeric(data[[tsrc]]))
  data[[tvar]] <- pmin(tt, days, na.rm = FALSE)
  data[[tvar]][is.na(tt)] <- NA_real_
  data[[yvar]] <- as.integer(suppressWarnings(as.numeric(data[[esrc]])) == 1)

  if (!is.null(ctx$data$imputed)) ctx$data$imputed <- data else ctx$data$cleaned <- data
  ctx$config$survival$time_var  <- tvar
  ctx$config$survival$event_var <- yvar
  ctx$config$survival$index_var <- evar
  ctx$config$data$outcome_column <- yvar
  ctx$config$iptw_balance$exposure_var <- evar
  ctx$config$iptw_balance$index_var <- evar
  ctx$results$ipw_diabetes_exposure <- list(
    n = nrow(data),
    n_diabetes = sum(data[[evar]] == 1L, na.rm = TRUE),
    n_event = sum(data[[yvar]] == 1L, na.rm = TRUE)
  )
  ctx
}

register_block("ipw_diabetes_exposure", block_ipw_diabetes_exposure,
               "Derive Diabetes_HbA1c and 28d survival outcome")
```

Append runner map:

```r
    ipw_diabetes_exposure = b("69_ipw_diabetes_stroke_full/01block_ipw_diabetes_exposure.R"),
```

- [ ] **Step 4: Re-run test — expect `source_ok`**

---

### Task 3: Remaining `69_*` analysis/export blocks

**Files:**
- Create: `02block_ipw_flowchart.R` → `ipw_diabetes_flowchart`
- Create: `03block_ipw_weighted_km_pub.R` → `ipw_weighted_km_pub`
- Create: `04block_ipw_overlap_weights.R` → `ipw_overlap_weights`
- Create: `05block_ipw_subgroup_km_pub.R` → `ipw_subgroup_km_pub`
- Create: `06block_ipw_literature_targets.R` → `ipw_literature_targets`
- Create: `07block_ipw_pub_export.R` → `ipw_pub_export`
- Modify: `R/pipeline_runner.R` (append all six)

**Interfaces:**
- Consumes: `ctx$data$iptw_weighted` / `ctx$results$iptw_design` from `iptw_balance`; survival cols from Task 2
- Produces published files under unit `Tables/` / `Figures/` with keys in spec §2
- Pattern: copy structure from `55_competing_risk_full/17block_competing_flowchart.R` and `58_medication_regimen_full/07block_medication_literature_targets.R` (read then adapt; do not edit those files)

- [ ] **Step 1: Implement flowchart**

`ipw_diabetes_flowchart`: count rows at cohort / HbA1c non-missing / outcome non-missing / analysis set; split by `Diabetes_HbA1c`; export `Figure_1_Flowchart` via `pub_paths` + ggplot or diagram export used elsewhere in repo.

- [ ] **Step 2: Implement weighted KM pub**

`ipw_weighted_km_pub`:
- Read weighted design from `ctx$data$iptw_weighted` or weights column from `iptw_balance`
- Fit weighted KM + IPW Cox HR; write `Figure_2_IPW_KM`
- Unweighted KM → `Figure_S2_Unweighted_KM`
- Use `pub_format_p` for footnotes

- [ ] **Step 3: Implement overlap weights**

`ipw_overlap_weights`:
- Reuse PS from `ctx$results$iptw_design` if present; else refit logistic PS on same covariates
- Overlap weight `e(x)*(1-e(x))` (or WeightIt `"overlap"` if package available)
- IPW-style Cox HR table → `Table_Sens_Overlap_Weights`

- [ ] **Step 4: Implement subgroup KM pub**

`ipw_subgroup_km_pub`:
- Config `ipw_diabetes$severity_var` (default try `SOFA` or `GCS` median split — **must** resolve from config after data probe, not hard-coded clinical rule in block beyond median)
- Two-panel KM → `Figure_4_Subgroup_KM`

- [ ] **Step 5: Literature targets + pub export**

`ipw_literature_targets`: checklist of required filenames; write `Tables/Literature_targets_audit.csv`; if any required missing and `pause_on_missing_targets=TRUE`, stop with pause_point (batch default FALSE → warning + failed flag in results).

`ipw_pub_export`: call `mirror_pub_output_to_root` when `config$project$mirror_pub_outputs_to_root` is TRUE; ensure unit root `Tables/`/`Figures/` populated.

- [ ] **Step 6: Register all six in `pipeline_runner.R` and parse-check**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" -e '
files <- list.files("E:/01block/01Block-new-Final/Blocks/69_ipw_diabetes_stroke_full", full.names=TRUE, pattern="\\\\.R$")
for (f in files) parse(f)
cat("parse_ok", length(files), "\n")
'
```

Expected: `parse_ok 7`

---

### Task 4: Batch config template + live project config

**Files:**
- Create: `configs/templates/config_ipw_diabetes_stroke_batch.template.R`
- Create: `G:/02block_result/11_ischemic stroke/Medication_regimen_model_42118193/config_ipw_diabetes_stroke_batch.R` (copy from template with absolute data paths)

**Interfaces:**
- Produces global `config`, `pipeline_shared`, `pipeline_unit`
- `study_batch$units` resolved from filtered `.composite_index_vars`
- `analysis_exclusion$disease_vars = c("T1DM","T2DM","Diabetes","HbA1c")` but **must not drop** `Diabetes_HbA1c`

- [ ] **Step 1: Probe columns once (document in config comments)**

Confirmed baseline object `baseline` (65366×104) has `HbA1c`,`Age`,`Gender`,`SOFA`,`GCS`.  
Prognosis CSV has `death_within_hosp_28days`,`hosp_survival_day`.  
Cohort filter: `dabiao.csv` `subject_id`.

- [ ] **Step 2: Write template**

Skeleton (fill paths like competing-risk stroke template):

```r
.block_repo_root <- {
  env <- Sys.getenv("BLOCK_REPO_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env else "E:/01block/01Block-new-Final"
}
source(file.path(.block_repo_root, "configs/indices/composite_index_vars.R"))
source(file.path(.block_repo_root, "Blocks/00_index/01block_index.R"))

.block_result_root <- {
  env <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env
  else if (dir.exists("G:/02block_result")) "G:/02block_result"
  else "/mnt/g/02block_result"
}
.batch_project_root <- file.path(.block_result_root, "11_ischemic stroke/Medication_regimen_model_42118193")
.batch_data_root <- file.path(.batch_project_root, "data")

.disease_exclusion_vars <- c("T1DM", "T2DM", "Diabetes", "HbA1c")
.disease_related_index_units <- pipeline_indices_using_vars(.disease_exclusion_vars, .composite_index_vars)
.test_units <- setdiff(.composite_index_vars, .disease_related_index_units)

config <- list(
  project = list(
    name = "IPW_Diabetes_Stroke_MIMIC",
    disease_code = "11",
    study_type = "prognosis",
    database = "MIMIC",
    root = .block_repo_root,
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),
  data = list(
    rawdata_path = file.path(.batch_data_root, "D01_baseline_MIMIC_ICU_frist_0626 (1).RData"),
    rawdata_obj = "baseline",
    id_column = "ID",
    outcome_column = "surv_event_28d"
  ),
  data_clean = list(
    missing_threshold = 1.0,
    cohort_id_path = file.path(.batch_data_root, "dabiao.csv"),
    cohort_id_column = "subject_id",
    supplement_merge_path = file.path(.batch_data_root, "mimic\u9884\u540e\u6570\u636e-all.csv"),
    supplement_merge_id_column = "subject_id",
    supplement_merge_columns = c("hosp_day", "is_hosp_dead", "hosp_survival_day", "death_within_hosp_28days"),
    min_n_after_cohort = 200L
  ),
  column_mapping = list(enable = TRUE, database_type = "MIMIC"),
  index = list(enable = TRUE, only = .test_units),
  imputation = list(
    missing_col_threshold = 0.5, method = "cart", m = 5L, max_iter = 5L, seed = 1234L,
    force_keep_columns = c(.test_units, "HbA1c"),
    pause_enable = FALSE
  ),
  ipw_diabetes = list(
    hba1c_var = "HbA1c", hba1c_threshold = 6.5, exposure_var = "Diabetes_HbA1c",
    followup_days = 28L,
    time_source = "hosp_survival_day", event_source = "death_within_hosp_28days",
    time_var = "surv_time_28d", event_var = "surv_event_28d",
    severity_var = "SOFA", pause_enable = FALSE
  ),
  analysis_exclusion = list(
    disease_vars = .disease_exclusion_vars,
    component_scope = "current_transitive",
    exclude_other_composite_indices = TRUE,
    exclude_exposure_if_uses_disease_var = TRUE,
    protect_vars = c("Diabetes_HbA1c", "surv_time_28d", "surv_event_28d")
  ),
  survival = list(time_var = "surv_time_28d", event_var = "surv_event_28d", index_var = "Diabetes_HbA1c"),
  univariate_prognosis = list(sig_cutoff = 0.10, pause_enable = FALSE),
  feature_selection_lasso = list(candidate_source = "univariate", pause_enable = FALSE),
  feature_selection_random_forest = list(candidate_source = "lasso", pause_enable = FALSE),
  iptw_balance = list(
    enable = TRUE, exposure_var = "Diabetes_HbA1c", index_var = "Diabetes_HbA1c",
    smd_threshold = 0.1, pause_enable = FALSE
  ),
  iptw_association = list(enable = TRUE, pause_enable = FALSE),
  subgroup_iptw_weighted = list(enable = TRUE, pause_enable = FALSE),
  subgroup_treatment_forest = list(enable = TRUE, pause_enable = FALSE),
  stepp_prognosis = list(
    enable = TRUE,
    # horizon in days for 28d survival STEPP — set keys to match 32_stepp config schema after reading block header
    pause_enable = FALSE
  ),
  cox_binary = list(pause_enable = FALSE),
  study_batch = list(
    output_base = .batch_project_root,
    units = .test_units,
    unit_mode = "index",
    parallel_workers = "auto",
    skip_existing = TRUE,
    worker_script = "run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch_worker.R",
    shared_ck_alias = "index"
  ),
  feishu = list(
    enable = TRUE,
    app_token = "RBjfb2iwmamW14s4WhKcS7kwnie"
  )
)

pipeline_shared <- list(
  name = "ipw_diabetes_shared",
  blocks = c("data_clean", "column_mapping", "index"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_project_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "ipw_diabetes_unit",
  blocks = c(
    "imputation",
    "ipw_diabetes_exposure",
    "analysis_exclusion",
    "trim_index_extreme",
    "univariate_prognosis",
    "feature_selection_lasso",
    "feature_selection_random_forest",
    "iptw_balance",
    "iptw_association",
    "ipw_diabetes_flowchart",
    "ipw_weighted_km_pub",
    "subgroup_iptw_weighted",
    "subgroup_treatment_forest",
    "ipw_subgroup_km_pub",
    "stepp_prognosis",
    "cox_binary",
    "ipw_overlap_weights",
    "ipw_literature_targets",
    "ipw_pub_export"
  ),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
```

If `analysis_exclusion` does not yet honor `protect_vars`, extend that block **minimally** to skip deleting protected names (prefer config-driven protect list over hard-coding `Diabetes_HbA1c` inside the exclusion block).

- [ ] **Step 3: Copy live config to result root and `parse()` both files**

---

### Task 5: Run entrypoints (batch + worker)

**Files:**
- Create: `run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R`
- Create: `run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch_worker.R`

**Interfaces:**
- Same CLI as competing risk: `--config`, `--workers`, `--shared-only`, `--only-unit`, `--no-skip`
- Calls `run_study_batch(...)` from `R/study_batch_runner.R`

- [ ] **Step 1: Copy pattern from `run/competing_risk/run_competing_risk_chf_batch.R`**

Change only:
- directory detection `ipw_diabetes_stroke`
- default config path to template
- keep `source(R/study_batch_runner.R)` + `run_study_batch(...)`

- [ ] **Step 2: Worker script**

Mirror `run/study/run_study_batch_worker.R` or competing-risk worker: accept `--config --unit`, load shared ck, patch `index_var` to current unit for any block that reads current composite index as covariate, run `pipeline_unit$blocks`.

Worker must:
1. Copy shared checkpoint
2. Drop other index columns; keep current unit column
3. Filter NA on current index
4. Set `config$incidence$index_var` / any covariate force-include for current index if needed
5. Run unit pipeline
6. Write `_batch_status.json` and rename to `【success】` / `【failed】`

- [ ] **Step 3: Dry-parse entrypoints**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" -e 'parse("E:/01block/01Block-new-Final/run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R"); parse("E:/01block/01Block-new-Final/run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch_worker.R"); cat("ok\n")'
```

---

### Task 6: Feishu wiring

**Files:**
- Possibly: `run/feishu/run_feishu_mark_*` style one-shot OR config-only sync via existing `feishu_*` helpers
- Modify: live project `config$feishu` with `table_id` once created

- [ ] **Step 1: List tools under `run/feishu/` and `R/feishu_*.R`; create routine/result tables on app_token `RBjfb2iwmamW14s4WhKcS7kwnie` using the same field schema as existing routine table**

- [ ] **Step 2: Write table_ids into project config `feishu$table_id` / success/failure ids**

- [ ] **Step 3: Smoke with `SMOKE_NO_FEISHU=1` first; then one successful unit push**

---

### Task 7: Shared-only + NLR smoke

**Files:** none new (execution)

- [ ] **Step 1: Shared layer**

```bash
R="/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
CFG="G:/02block_result/11_ischemic stroke/Medication_regimen_model_42118193/config_ipw_diabetes_stroke_batch.R"
cd /mnt/e/01block/01Block-new-Final
"$R" run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R --config "$CFG" --shared-only --no-skip
```

Expected: `_shared/main/index.rds` exists; disease-formula units absent from unit list.

- [ ] **Step 2: Single worker NLR**

```bash
SMOKE_NO_FEISHU=1 "$R" run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R \
  --config "$CFG" --only-unit NLR --workers 1 --no-skip
```

Expected: `by_unit/【success】NLR` (or failed with actionable `_batch_status.json`).

- [ ] **Step 3: Audit literature files under NLR unit**

Required basenames must exist for Fig1–5, Table1, Sens×2, S1, S2, Table S1 (allow pub_paths numeric prefixes).

- [ ] **Step 4: Hard-exclusion audit**

Confirm analysis tables / PS covariate lists contain neither `HbA1c` nor diagnosis diabetes columns; `Diabetes_HbA1c` present as exposure only.

---

### Task 8: Full batch launch readiness

- [ ] **Step 1: Fix any NLR failures from Task 7**

- [ ] **Step 2: Launch**

```bash
"$R" run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R --config "$CFG" --workers 20 --no-skip
```

- [ ] **Step 3: Write root `Tables/Indicator_availability.csv` + `Batch_summary_all_units.csv`**

- [ ] **Step 4: Sync Feishu; update decision tree with final run commands**

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Fig1–5 / Table1 / Sens / Supp | 3, 7 |
| HbA1c≥6.5 exposure | 2 |
| 28d death outcome | 2, 4 |
| Hard exclusion + protect exposure | 4 |
| Composite-index batch parallel | 4, 5, 8 |
| Blocks/69 only new code | 2, 3 |
| Reuse 34/27/10/18/32/19 | 1, 4 |
| Register IPTW missing from runner | 1 |
| Feishu new base | 6 |
| mirror_pub | 3, 4 |
| Do not touch 55/58 | Global |
| Decision tree / config / run | 1, 4, 5 |

## Self-review notes

- Fixed exposure-before-exclusion order in Task 4 pipeline_unit.
- `protect_vars` added so exclusion cannot delete `Diabetes_HbA1c`.
- Confirmed `iptw_*` / `subgroup_iptw_*` were missing from runner — Task 1 registers them.
- Outcome columns confirmed in prognosis CSV; severity default `SOFA` (present in baseline).
- Commit steps omitted unless user asks (Global Constraints).
