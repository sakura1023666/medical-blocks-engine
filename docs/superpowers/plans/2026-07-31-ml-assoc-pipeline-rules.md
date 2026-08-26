# ML Assoc Pipeline Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make dual-ML pipelines emit full association outputs (univariate-on-train, VIF train+test, logistic/RCS/Cox/KM with correct data slots), conditional AdaBoost (`n_train < 350`), OR+HR subgroups when time exists, strip DB-name prefixes, and fix single-PDF duplicate pages.

**Architecture:** Expand `ml_dual_primary_ml_stat_upstream_blocks` / tail to a full assoc chain controlled by `ml_batch$assoc_blocks` (`full` default, `ml_thin` escape hatch). Add a small data-slot helper that temporarily points association blocks at `imputed` / `train` / `test`, and a thin `ml_assoc_bundle` that loops slots without rewriting every logistic/cox file. Fix `save_figure` callers that `print()` inside `plot_fn`. Wire AdaBoost into default methods with `max_train_n=349`.

**Tech Stack:** R 4.5 medical-blocks, existing Blocks 06–18 / 22–24, processx ML dual batch.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-31-ml-assoc-pipeline-rules-design.md`
- Keep ctx slots: `ctx$data$train`, `ctx$data$test`, `ctx$data$imputed` (do not rename ecosystem to `data_train`)
- Dual/cross_db association: run on **train and test separately**; single-DB association: **imputed**
- Univariate: **train only**; logistic for both incidence and prognosis on dual-ML path
- VIF: **train and test** (if test missing → imputed once)
- No `survival$time_var` → skip Cox, KM, subgroup HR
- AdaBoost only if `n_train < 350` (`max_train_n = 349`); skip must not fail the index
- Pub filenames: Train/Validation or no prefix — **never** MIMIC/eICU injection
- PDF: `plot_fn` must **return** grob/ggplot, never `print()` inside (renderer prints once)
- Do **not** git commit unless user asks
- Verify with RAR wipe + `--only-index RAR --no-skip` after implementation

## File map

| File | Responsibility |
|------|----------------|
| `R/ml_assoc_data_slots.R` (create) | Resolve slots; run a block fn with swapped `imputed` + label suffix |
| `Blocks/24_ml_dual/05block_ml_assoc_bundle.R` (create) | Loop logistic/RCS/(cox/km) over resolved slots |
| `configs/ml_dual_shared_overrides.R` | Full upstream blocks, AdaBoost defaults, assoc_blocks |
| `configs/study_interface/ml_dual_batch_pipelines.R` | Tail: subgroup OR + optional HR |
| `R/pipeline_runner.R` | Register `ml_assoc_bundle` |
| `Blocks/06_univariate/*` or dual override | Force train-only + logistic on dual-ML |
| `Blocks/08_vif/01block_multicollinearity.R` | Optional multi-slot VIF **or** call via helper twice from bundle |
| `Blocks/22_ml_models/11block_ml_adaboost.R` | Ensure skip path soft; harden hang |
| `Blocks/23_ml_performance/01block_performance_ml.R` | Remove inner `print()` in `save_figure` |
| `R/utils.R` / worker label | Cross-db `database_name` without DB names |
| Study `config.R` | methods + adaboost + assoc_blocks=full |

---

### Task 1: Fix PDF double-page (`print` inside `save_figure`)

**Files:**
- Modify: `Blocks/23_ml_performance/01block_performance_ml.R` (all `function() print(...)` → `function() ...`)
- Optional scan: other Blocks under `22_ml_models` / `17_shap` for same antipattern

**Interfaces:**
- Consumes: `save_figure(ctx, filename, plot_fn, ...)` where `render_queued_figures` auto-prints return value
- Produces: PDF with `Pages: 1` for combined 2x4 and ROC/DCA/calibration/parallel supplements

- [ ] **Step 1: Replace every inner print in performance_ml**

Change patterns like:

```r
ctx <- save_figure(ctx, "Figure S. ML performance ROC train.pdf", function() print(p_roc_tr), width = 6, height = 6)
```

to:

```r
ctx <- save_figure(ctx, "Figure S. ML performance ROC train.pdf", function() p_roc_tr, width = 6, height = 6)
```

Including `function() print(comb)` → `function() comb`.

- [ ] **Step 2: Grep guard**

```bash
rg -n 'save_figure\([^)]*function\(\)\s*print\(' Blocks/23_ml_performance/01block_performance_ml.R
```

Expected: no matches.

- [ ] **Step 3: Smoke after next RAR run (or minimal re-render if available)** — acceptance in Task 8: `pdfinfo` on combined 2x4 shows `Pages: 1`.

---

### Task 2: Assoc data-slot helper

**Files:**
- Create: `R/ml_assoc_data_slots.R`
- Source from: same bootstrap as `R/ml_cross_db_split.R` (batch runner + worker)

**Interfaces:**
- Produces: `ml_assoc_is_dual(ctx)` → logical (`cross_db` or dual_db secondary present with both train/test)
- Produces: `ml_assoc_resolve_slots(ctx)` → `data.frame(slot, label)`  
  - dual: `train`/`Train`, `test`/`Validation`  
  - single: `imputed`/`""` (empty label)
- Produces: `ml_assoc_run_on_slot(ctx, slot, label, block_name)` → runs registered block with `ctx$data$imputed` temporarily set to `ctx$data[[slot]]` (for `imputed` slot use existing); sets `ctx$config$pub$filename_suffix` or `pipeline$figure_suffix` to `label` if helpers exist; restores previous imputed after run
- Produces: `ml_assoc_has_time(ctx)` → `nzchar(config$survival$time_var)`

- [ ] **Step 1: Implement helper**

```r
# R/ml_assoc_data_slots.R
ml_assoc_has_time <- function(ctx) {
  tv <- ctx$config$survival$time_var %||% ""
  nzchar(as.character(tv)[1L])
}

ml_assoc_resolve_slots <- function(ctx) {
  split_mode <- ctx$config$ml_batch$split_mode %||%
    ctx$config$incidence_batch$split_mode %||% "per_db_internal"
  has_tt <- is.data.frame(ctx$data$train) && is.data.frame(ctx$data$test) &&
    nrow(ctx$data$train) > 0L && nrow(ctx$data$test) > 0L
  dual <- identical(split_mode, "cross_db") || isTRUE(has_tt)
  if (dual && has_tt) {
    data.frame(slot = c("train", "test"), label = c("Train", "Validation"),
               stringsAsFactors = FALSE)
  } else {
    data.frame(slot = "imputed", label = "", stringsAsFactors = FALSE)
  }
}

ml_assoc_frame_for_slot <- function(ctx, slot) {
  if (identical(slot, "imputed")) return(ctx$data$imputed %||% ctx$data$cleaned)
  ctx$data[[slot]]
}

ml_assoc_run_on_slot <- function(ctx, slot, label, block_name) {
  old_imp <- ctx$data$imputed
  on.exit({ ctx$data$imputed <<- old_imp }, add = TRUE)
  fr <- ml_assoc_frame_for_slot(ctx, slot)
  if (is.null(fr)) {
    cli::cli_alert_warning("ml_assoc: slot {slot} empty, skip {block_name}")
    return(ctx)
  }
  ctx$data$imputed <- fr
  # Prefer existing pub suffix hooks if present; else stash for blocks that read it
  ctx$config$pub <- ctx$config$pub %||% list()
  ctx$config$pub$slot_label <- label
  if (exists("run_block", mode = "function")) {
    ctx <- run_block(ctx, block_name)
  }
  ctx
}
```

Note: `on.exit` with `<<-` on list elements is fragile in R — implement by returning updated ctx and **explicitly restoring** `imputed` after each `run_block` in the caller (preferred):

```r
ml_assoc_run_on_slot <- function(ctx, slot, label, block_name) {
  old_imp <- ctx$data$imputed
  fr <- ml_assoc_frame_for_slot(ctx, slot)
  if (is.null(fr)) return(ctx)
  ctx$data$imputed <- fr
  ctx$config$pub <- modifyList(ctx$config$pub %||% list(), list(slot_label = label))
  ctx <- tryCatch(run_block(ctx, block_name), error = function(e) {
    cli::cli_alert_warning("{block_name}@{slot}: {conditionMessage(e)}"); ctx
  })
  ctx$data$imputed <- old_imp
  ctx
}
```

- [ ] **Step 2: Source in worker/batch** next to `ml_cross_db_split.R`.

- [ ] **Step 3: Smoke**

```bash
Rscript -e 'source("R/ml_assoc_data_slots.R"); print(ml_assoc_resolve_slots(list(config=list(ml_batch=list(split_mode="cross_db")), data=list(train=data.frame(a=1), test=data.frame(a=1)))))'
```

Expected: two rows Train/Validation.

---

### Task 3: `ml_assoc_bundle` + pipeline registration

**Files:**
- Create: `Blocks/24_ml_dual/05block_ml_assoc_bundle.R`
- Modify: `R/pipeline_runner.R` — add `ml_assoc_bundle = b("24_ml_dual/05block_ml_assoc_bundle.R")`
- Modify: `configs/ml_dual_shared_overrides.R` — `ml_dual_primary_ml_stat_upstream_blocks` / new `ml_dual_primary_ml_assoc_blocks`

**Interfaces:**
- Consumes: `ml_assoc_resolve_slots`, `ml_assoc_run_on_slot`, `ml_assoc_has_time`
- Produces: registered block `ml_assoc_bundle` that runs, per slot:
  - `logistic_quartile_glm`, `logistic_tertile_glm`, `logistic_binary_glm`
  - `rcs_incidence` (or prognosis RCS if study_type prognosis — use incidence RCS for dual-ML incidence studies)
  - `logistic_*_glm_rcs` trio
  - if time: `cox_binary`, `km_binary`
- Config: `ml_batch$assoc_blocks` ∈ `c("full","ml_thin")`; default `"full"`

- [ ] **Step 1: Rewrite upstream block list**

```r
ml_dual_primary_ml_stat_upstream_blocks <- function(config) {
  mode <- config$ml_batch$assoc_blocks %||% "full"
  st <- tolower(trimws(config$project$study_type %||% "incidence"))
  uni <- if (identical(st, "prognosis")) {
    # dual-ML rule: univariate still logistic → use incidence binary univariate block
    "univariate_incidence_binary"
  } else {
    "univariate_incidence_binary"
  }
  thin <- c(uni, "multicollinearity_screen")
  if (identical(mode, "ml_thin")) return(thin)
  c(thin, "ml_assoc_bundle")
}
```

- [ ] **Step 2: Implement bundle**

```r
block_ml_assoc_bundle <- function(ctx, ...) {
  mode <- ctx$config$ml_batch$assoc_blocks %||% "full"
  if (!identical(mode, "full")) return(ctx)
  slots <- ml_assoc_resolve_slots(ctx)
  base_blocks <- c(
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs"
  )
  if (ml_assoc_has_time(ctx)) {
    base_blocks <- c(base_blocks, "cox_binary", "km_binary")
  }
  root <- ctx$config$project$root %||% getwd()
  for (i in seq_len(nrow(slots))) {
    for (bn in base_blocks) {
      if (exists("pipeline_source_block", mode = "function")) {
        try(pipeline_source_block(root, bn), silent = TRUE)
      }
      ctx <- ml_assoc_run_on_slot(ctx, slots$slot[[i]], slots$label[[i]], bn)
    }
  }
  ctx
}
register_block("ml_assoc_bundle", block_ml_assoc_bundle, "关联分析：logistic/RCS/(Cox/KM) 按数据槽循环")
```

- [ ] **Step 3: Ensure gate configs stay non-pausing** — already in `ml_dual_apply_regular_upstream_overrides`; call it from build if not already.

- [ ] **Step 4: Filename collision across slots** — if blocks always write the same basename, second slot overwrites first. **Required:** before each slot run, set a suffix the pub helpers honor, **or** after each block copy/rename outputs under `Figures/` / `Tables/` to append ` (Train)` / ` (Validation)`.

Minimal reliable approach in bundle after each `ml_assoc_run_on_slot`:

```r
ml_assoc_suffix_recent_outputs <- function(ctx, label) {
  if (!nzchar(label)) return(invisible())
  for (dir_key in c("output_dir_figures", "output_dir_tables")) {
    d <- ctx[[dir_key]] %||% NULL
    if (is.null(d) || !dir.exists(d)) next
    # rename files modified in last ~2 minutes lacking " (Train)" / " (Validation)"
    # append paste0(" (", label, ")") before extension
  }
}
```

Implement carefully: only suffix files that do not already contain `(Train)`/`(Validation)`.

---

### Task 4: Univariate train-only + VIF train+test

**Files:**
- Modify: univariate incidence block to honor `config$univariate_incidence_binary$data_slot` (default `"train"` under dual-ML overrides)
- Modify: multicollinearity screen to honor `config$multicollinearity$data_slots` = `c("train","test")` **or** wrap screen in a tiny loop inside a new `ml_vif_bundle` called instead of single `multicollinearity_screen`

**Interfaces:**
- Override in `ml_dual_apply_regular_upstream_overrides` / cross_db overrides:

```r
config$univariate_incidence_binary$data_slot <- "train"
config$multicollinearity$data_slots <- c("train", "test")
```

- [ ] **Step 1: Univariate** — at data load, prefer:

```r
slot <- bl_cfg$data_slot %||% "imputed"
data <- if (identical(slot, "train") && is.data.frame(ctx$data$train)) {
  ctx$data$train
} else {
  ctx$data$imputed %||% ctx$data$cleaned
}
```

If `data_slot="train"` but train missing → fall back to imputed + cli warning.

- [ ] **Step 2: VIF** — either loop inside `block_multicollinearity` when `data_slots` length > 1 (write `Table S. VIF (Train).xlsx` etc.), or replace pipeline entry `multicollinearity_screen` with a 10-line wrapper block that calls `ml_assoc_run_on_slot` twice for `multicollinearity_screen` / `multicollinearity` registered name.

Prefer wrapper in same file as assoc helper to avoid large VIF rewrite:

```r
# in ml_assoc_bundle file or separate ml_vif_dual_block
# pipeline uses "ml_vif_train_test" instead of multicollinearity_screen when assoc full
```

Update `ml_dual_primary_ml_stat_upstream_blocks` thin segment to:

```r
c(uni, "ml_vif_train_test")
```

where `ml_vif_train_test` loops slots and runs existing multicollinearity block.

- [ ] **Step 3: Smoke** — unit-level: with fake ctx, resolve slots; no full pipeline required yet.

---

### Task 5: AdaBoost default + `n_train < 350` + soft hang

**Files:**
- Modify: `configs/ml_dual_shared_overrides.R` — `ml_dual_default_ml_methods` include `"adaboost"`; `ml_dual_apply_ml_models_overrides` set:

```r
config$ml_adaboost <- modifyList(config$ml_adaboost %||% list(), list(
  enable = TRUE,
  pause_enable = FALSE,
  limits = list(max_train_n = 349L)
))
```

- Modify: study `.../ml_40395549/config.R` — append `"adaboost"` to methods; remove “剔除 adaboost” comment; set same limits
- Modify: `Blocks/22_ml_models/11block_ml_adaboost.R` — ensure limit skip returns ctx without stop; if historically hangs, cap `mfinal` / CV folds / add `tryCatch` soft skip

**Interfaces:**
- Consumes: existing `.mlada11_check_limits`
- Produces: `evalresult_adaboost.RData` when `n_train <= 349`; clean skip log when larger

- [ ] **Step 1: Default methods + limits in shared overrides**

- [ ] **Step 2: Soft-skip path** — when limits fail, block must `return(ctx)` not `stop()`. Confirm current code path after `.mlada11_check_limits` returns FALSE.

- [ ] **Step 3: Hang mitigation** — read train path; if `adabag::boosting` / tidymodels tune has no timeout, set lower `mfinal` default (e.g. 50) and `cv_folds` ≤ 3 when `n_train < 350`. Document in block header.

- [ ] **Step 4: Confirm `ml_models_bundle` already maps `adaboost` → `ml_adaboost` (it does).

---

### Task 6: Subgroup OR + HR; strip DB prefixes

**Files:**
- Modify: `ml_dual_primary_ml_tail_blocks` in `configs/ml_dual_shared_overrides.R`

```r
ml_dual_primary_ml_tail_blocks <- function(config) {
  st <- tolower(trimws(config$project$study_type %||% "incidence"))
  has_time <- nzchar(as.character(config$survival$time_var %||% "")[1L])
  tail <- c(
    "ml_feature_selection_bundle",
    "ml_models_bundle", "performance_ml",
    "supplementary_ml", "shap", "shiny_ml_app"
  )
  if (identical(st, "incidence")) {
    tail <- c(tail, "subgroup_incidence")
    if (has_time) tail <- c(tail, "subgroup_prognosis")  # HR forest
  } else if (identical(st, "prognosis")) {
    tail <- c(tail, "subgroup_prognosis")
  }
  tail
}
```

- Modify: cross_db worker / runner where `pipeline$database_name` or figure prefix is set — use `""` or `"Train-Test"` **without** DB names when `mirror_aggregate_prefix_db=FALSE`
- Grep for figure stems containing `Train MIMIC` and stop injecting db pretty names into feature-selection titles

- [ ] **Step 1: Tail blocks as above**

- [ ] **Step 2: Label** — in worker cross_db path set:

```r
pipeline$database_name <- ""
# or config$project$database_name <- ""
```

Ensure feature selection filenames become `Figure S2A. LassoGenes.pdf` (or keep method letter only), not `Train MIMIC IV -Test eICU`.

- [ ] **Step 3: Subgroup prognosis** — set `pause_enable=FALSE`; use train (or imputed) per block defaults; minimum: one HR forest/table appears under RAR Figures/Tables.

---

### Task 7: Study config + overrides wire-up

**Files:**
- Modify: `/mnt/g/02block_result/17_pancreatic carcinoma/ml_40395549/config.R`
- Modify: `configs/study_interface/ml_dual_batch_build.R` if needed to call new overrides

- [ ] **Step 1: Study config**

```r
config$ml_batch$assoc_blocks <- "full"
config$ml_models$methods <- c(
  "xgboost", "lightgbm", "catboost", "rf", "rsvm", "mlp", "realmlp",
  "logistic", "knn", "adaboost",
  "tabpfn", "tabpfnv2", "realtabpfn_2_5", "tablcl_v2",
  "dt", "enet"
)
config$ml_adaboost <- modifyList(config$ml_adaboost %||% list(), list(
  pause_enable = FALSE,
  limits = list(max_train_n = 349L)
))
```

- [ ] **Step 2: Confirm survival time_var remains `futime`**

- [ ] **Step 3: Update spec status line already approved; update `.superpowers/sdd/progress.md` for this plan when executing**

---

### Task 8: Wipe RAR + verify acceptance

**Files:** none (ops)

- [ ] **Step 1: Wipe RAR results + checkpoints only** (reuse prior kill/wipe scripts for this study)

- [ ] **Step 2: Run**

```bash
# via study runner (Windows Rscript worker), only RAR
./run_study.sh "17_pancreatic carcinoma" --only-index RAR --no-skip --workers 1
```

- [ ] **Step 3: Acceptance checklist**

| Check | Expect |
|-------|--------|
| `【success】RAR` | status=success |
| AdaBoost | `evalresult_adaboost.RData` present (`n_train≈308`) |
| RCS | at least Train + Validation (or labeled) RCS figures |
| Logistic tables | present under Tables |
| Cox + KM | present (`futime` set) |
| Subgroup | OR figure + HR figure/table |
| Combined 2x4 PDF | `pdfinfo` → `Pages: 1` |
| Filenames | no `MIMIC`/`eICU` in new figure basenames (Train/Validation OK) |
| Assignment | train MIMIC_IV / test eICU unchanged |

- [ ] **Step 4: If AdaBoost still fails** — capture error from `logs/RAR.log`, soft-skip only after documenting root cause; do not leave silent removal from methods.

---

## Spec coverage self-check

| Spec § | Task |
|--------|------|
| §3 main chain / §3.1 | Task 3–4, 6 |
| §4 data slots | Task 2–3 |
| §5 AdaBoost | Task 5, 7–8 |
| §6 PDF double page | Task 1, 8 |
| §7 no DB prefix | Task 6–8 |
| §8 subgroup OR+HR | Task 6, 8 |
| §9 acceptance map | Task 8 |

## Placeholder scan

No TBD/TODO left in steps; commit steps omitted per global constraint (user must ask).
