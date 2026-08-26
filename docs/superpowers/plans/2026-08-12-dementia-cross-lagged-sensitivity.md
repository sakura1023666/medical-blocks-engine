# Dementia Cross-Lagged Sensitivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Dementia cross-lagged sensitivity (Table1 + logistic tertile + Change, S9–S17.1) on CLHLS/SHARE/HRS/ELSA using the same AfterMI, outcome, tertile method, Model1/2, and Step05 years/wide as the prior main analysis — only the three sample filters change.

**Architecture:** Extend `R/cross_lagged_sensitivity.R` loaders/table names and `phases/phase_sensitivity.R` cohorts/config for Dementia study layout; keep statistical defaults locked to 姜小胖 main analysis. medical-blocks only orchestrates and emits hip-isomorphic table shells.

**Tech Stack:** R, cli, survival/glm (via existing logistic blocks), openxlsx/readxl, existing `baseline_binary` / `logistic_tertile_glm` / `cross_lagged_change_logistic`.

**Spec:** `docs/superpowers/specs/2026-08-12-dementia-cross-lagged-sensitivity-design.md`

## Global Constraints

- Continuity: same AfterMI / Disease / tertile algorithm / Model1·2 / Step05 years & wide; only three scenario filters.
- Cohorts: `CLHLS`, `SHARE`, `HRS`, `ELSA` (no CHARLS).
- Model1 = `Age + Education + Alcohol_drinking`.
- Model2 = `Age + Education + Alcohol_drinking + Hypertension + Total_Cholesterol + HDL`.
- Tertile: `quantile(probs=c(1/3,2/3))` + `cut(..., right=FALSE, labels=T1/T2/T3)` (match `C01_LogisticCode_new_3.R`); **not** blocks default `Q1–Q3` + `right=TRUE` unless overridden.
- Study root: `/mnt/g/02block_result/20_Dementia/cross-laged_40595747`.
- Anchor (read-only): `/mnt/g/ftp/交付项目备份/临床交付项目及代码/141 痴呆 交叉滞后 姜小胖/姜小胖_痴呆20260203 - 副本`.
- Do not re-impute, rewrite Step09 delivery code, or run CLPN/competing_risk.
- Do not create a git commit unless the user explicitly requests one.
- If medical-blocks default conflicts with main analysis, change the default path for Dementia to match main analysis.

## File map

| File | Responsibility |
|------|----------------|
| `R/cross_lagged_sensitivity.R` | Dementia loaders (AfterMI/dabiao/long/wide), outcome normalize, parameterized table basenames, lock helpers |
| `Blocks/54_cross_lagged_full/phases/phase_sensitivity.R` | Dementia cohorts, disease/index config, Change outcome level, README |
| `Blocks/11_logistic/05block_logistic_tertile_glm.R` | Opt-in `right=FALSE` + `T1/T2/T3` labels via `bl_cfg` (hip default unchanged) |
| `tests/test_dementia_cross_lagged_sensitivity.R` | Unit tests for loaders, basename, outcome, tertile cut alignment |
| study_root `phase3_relock_acceptance.txt` | Lock Model1/Model2 for Dementia |

---

### Task 1: Lock file + table basename + outcome normalizer

**Files:**
- Modify: `R/cross_lagged_sensitivity.R` (`cross_lagged_sens_table_basename`, add helpers)
- Create: `/mnt/g/02block_result/20_Dementia/cross-laged_40595747/phase3_relock_acceptance.txt`
- Create: `tests/test_dementia_cross_lagged_sensitivity.R`

**Interfaces:**
- Produces: `cross_lagged_sens_table_basename(scenario, kind, db=NULL, index_display="FI", disease_display="Hip fracture")` → character path basename
- Produces: `cross_lagged_sens_normalize_disease_group(df, case_label="Dementia", control_label="Normal")` → data.frame with `Disease_Group`
- Produces lock file lines: `Model1=...`, `Model2_single=...`

- [ ] **Step 1: Write failing tests for basename + outcome**

```r
# tests/test_dementia_cross_lagged_sensitivity.R
source("R/utils.R", local = FALSE)
source("R/cross_lagged_sensitivity.R", local = FALSE)

bn <- cross_lagged_sens_table_basename(
  "exclude_chronic_ge2", "logistic", "ELSA",
  index_display = "Leisure_activities", disease_display = "Dementia"
)
stopifnot(grepl("Leisure_activities and Dementia", bn, fixed = TRUE))
stopifnot(grepl("Table S10-ELSA", bn, fixed = TRUE))
stopifnot(!grepl("FI and Hip", bn, fixed = TRUE))

df <- data.frame(Disease = c("Dementia", "Normal", "Dementia"), stringsAsFactors = FALSE)
out <- cross_lagged_sens_normalize_disease_group(df)
stopifnot(identical(as.character(out$Disease_Group), c("Dementia", "Normal", "Dementia")))
cat("Task1 tests OK (will fail until implemented)\n")
```

- [ ] **Step 2: Run tests — expect FAIL (function args / missing helper)**

```bash
cd /mnt/e/01block/01Block-new-Final && Rscript tests/test_dementia_cross_lagged_sensitivity.R
```

Expected: error about unused args or missing `cross_lagged_sens_normalize_disease_group`.

- [ ] **Step 3: Implement basename params + normalizer + lock file**

In `cross_lagged_sens_table_basename`, add `index_display` / `disease_display` with hip defaults; substitute into logistic/baseline/change titles.

Add:

```r
cross_lagged_sens_normalize_disease_group <- function(df, case_label = "Dementia",
                                                     control_label = "Normal") {
  d <- as.data.frame(df)
  if ("Disease_Group" %in% names(d) && any(d$Disease_Group %in% c(case_label, control_label), na.rm = TRUE))
    return(d)
  if (!"Disease" %in% names(d)) return(d)
  x <- d$Disease
  if (is.factor(x)) x <- as.character(x)
  if (is.numeric(x) || is.logical(x)) {
    d$Disease_Group <- ifelse(as.integer(x) == 1L, case_label, control_label)
  } else {
    xl <- as.character(x)
    d$Disease_Group <- ifelse(tolower(xl) %in% c("dementia", "1", "yes"), case_label, control_label)
  }
  d
}
```

Write study lock file:

```
Model1=Age+Education+Alcohol_drinking
Model2_single=Age+Education+Alcohol_drinking+Hypertension+Total_Cholesterol+HDL
```

- [ ] **Step 4: Re-run tests — expect PASS**

```bash
Rscript tests/test_dementia_cross_lagged_sensitivity.R
```

---

### Task 2: Dementia data loaders (AfterMI / dabiao / long / wide)

**Files:**
- Modify: `R/cross_lagged_sensitivity.R` (`cross_lagged_sens_load_imputed`, `cross_lagged_sens_load_dabiao`, `cross_lagged_sens_load_long`; add wide helper)
- Modify: `tests/test_dementia_cross_lagged_sensitivity.R`

**Interfaces:**
- Consumes study_root + db token (`ELSA`/`HRS`/`SHARE`/`CLHLS`)
- Produces data.frame from AfterMI `data_imp`; dabiao also object `data_imp` in Dementia files
- Produces long list: `list(long_all=, wide=)` resolving `D05_long_*` object names `ELSA_long` / `HRS_long` / `SHARE_long` / `clhls_long`, and Step05 `code/Step05_Change/{ELSA,HRS,SHARE,clhls}_wide1.RData` (object inside as loaded)

**Known paths:**

```
{study_root}/data/Step01_RawData/D01_AfterMI_Data_{ELSA|HRS|share|clhls}.RData  # data_imp
{study_root}/data/Step01_RawData/D01_dabiao_{ELSA|HRS|share|clhls}.RData       # data_imp
{study_root}/data/Step01_RawData/D05_long_{ELSA|HRS|SHARE|clhls}.RData
{study_root}/code/Step05_Change/{ELSA,HRS,SHARE,clhls}_wide1.RData
```

- [ ] **Step 1: Extend test — load ELSA AfterMI nrow == 5049**

```r
study <- "/mnt/g/02block_result/20_Dementia/cross-laged_40595747"
imp <- cross_lagged_sens_load_imputed(study, "ELSA")
stopifnot(nrow(imp) == 5049L)
stopifnot("Leisure_activities" %in% names(imp))
dab <- cross_lagged_sens_load_dabiao(study, "ELSA")
stopifnot(nrow(dab) == nrow(imp) || nrow(dab) > 0L)
pack <- cross_lagged_sens_load_long(study, "ELSA")
stopifnot(!is.null(pack$wide) || !is.null(pack$long_all))
```

- [ ] **Step 2: Run — expect FAIL on missing fallback paths**

- [ ] **Step 3: Implement fallbacks**

Pattern for each loader:

1. Try existing hip paths (unchanged).
2. Else resolve Dementia file with case aliases (`SHARE`↔`share`, `CLHLS`↔`clhls`).
3. Load env; prefer `data_imp`, then `dabiao`, then first object.
4. Call `cross_lagged_sens_normalize_disease_group` on AfterMI/dabiao results.
5. For long: if `D05_long_*` has only `*_long`, set `long_all` to that; load `code/Step05_Change/{db}_wide1.RData` into `wide` (first data.frame in env or known name). Never invent alternate wave maps when wide exists.

Add helper:

```r
cross_lagged_sens_db_aliases <- function(db) {
  db <- as.character(db)
  unique(c(db, toupper(db), tolower(db),
           if (toupper(db) == "SHARE") c("share", "SHARE"),
           if (toupper(db) == "CLHLS") c("clhls", "CLHLS", "Clhls")))
}
```

- [ ] **Step 4: Re-run tests — PASS; print n for all four DBs**

```r
for (db in c("CLHLS","SHARE","HRS","ELSA")) {
  d <- cross_lagged_sens_load_imputed(study, db)
  cat(db, nrow(d), "\n")
}
# expect 1032, 14682, 5361, 5049
```

---

### Task 3: Align logistic tertile cut with main analysis (T1–T3, right=FALSE)

**Files:**
- Modify: `Blocks/11_logistic/05block_logistic_tertile_glm.R` (~lines 144–152)
- Modify: `tests/test_dementia_cross_lagged_sensitivity.R`

**Interfaces:**
- Consumes `bl_cfg$tertile_right` (default `TRUE` = current hip behavior)
- Consumes `bl_cfg$tertile_labels` (default `c("Q1","Q2","Q3")`)
- Dementia phase sets `tertile_right=FALSE`, `tertile_labels=c("T1","T2","T3")`

- [ ] **Step 1: Failing unit check of cut semantics**

```r
x <- c(1, 2, 3, 4, 5, 6, 7, 8, 9)
qs <- as.numeric(quantile(x, probs = c(1/3, 2/3)))
# main-analysis style
g_main <- cut(x, breaks = c(-Inf, qs[1], qs[2], Inf), labels = c("T1","T2","T3"),
              right = FALSE, include.lowest = TRUE)
# document current block default
g_block <- cut(x, breaks = c(-Inf, qs, Inf), labels = c("Q1","Q2","Q3"), right = TRUE)
stopifnot(is.factor(g_main))
# After Task3, a small helper or inline bl_cfg path must reproduce g_main
```

- [ ] **Step 2: Implement opt-in in `05block_logistic_tertile_glm.R`**

```r
t_right <- isTRUE(bl_cfg$tertile_right %||% TRUE)
t_labs <- bl_cfg$tertile_labels %||% c("Q1", "Q2", "Q3")
if (length(t_labs) != 3L) t_labs <- c("Q1", "Q2", "Q3")
qs <- as.numeric(quantile(data2[[index_var]], probs = c(1/3, 2/3), na.rm = TRUE))
data2$Group <- cut(
  data2[[index_var]],
  breaks = c(-Inf, qs[1], qs[2], Inf),
  labels = t_labs,
  right = t_right,
  include.lowest = TRUE
)
data2$Group <- factor(data2$Group, levels = t_labs)
# cutoffs display: if !t_right use "< / -< / ≥" style like delivery tables
```

Keep default when `bl_cfg` omits keys so hip runs unchanged.

- [ ] **Step 3: Smoke that defaults still produce Q1–Q3 when unset**

```r
# optional: source block with minimal ctx on toy data without tertile_right → levels Q1 Q2 Q3
```

---

### Task 4: Wire `phase_sensitivity.R` for Dementia

**Files:**
- Modify: `Blocks/54_cross_lagged_full/phases/phase_sensitivity.R`

**Interfaces:**
- Detect Dementia study if `basename(dirname(study_root))` contains `Dementia` or `file.exists(file.path(study_root,"data/Step01_RawData/D01_AfterMI_Data_ELSA.RData"))`
- Sets `.cohorts`, disease/index displays, `logistic_tertile_glm` tertile flags, Change `outcome_event_level="Dementia"`

- [ ] **Step 1: Add study profile at top after `study_root` normalize**

```r
.is_dementia <- {
  grepl("Dementia", study_root, ignore.case = TRUE) ||
    file.exists(file.path(study_root, "data/Step01_RawData/D01_AfterMI_Data_ELSA.RData"))
}
.meta <- if (.is_dementia) {
  list(
    cohorts = c("CLHLS", "SHARE", "HRS", "ELSA"),
    disease = "Dementia", disease_code = "20",
    analysis_group = "Dementia", reference_group = "Normal",
    index_var = "Leisure_activities",
    index_display = "Leisure_activities",
    disease_display = "Dementia",
    project_prefix = "Dementia_Leisure_sens_"
  )
} else {
  list(
    cohorts = c("CHARLS", "ELSA", "HRS"),
    disease = "Hip_fracture", disease_code = "16",
    analysis_group = "Hip_Fracture", reference_group = "No_Fracture",
    index_var = "FI",
    index_display = "FI",
    disease_display = "Hip fracture",
    project_prefix = "Hip_Frailty_sens_"
  )
}
.cohorts <- .meta$cohorts
```

- [ ] **Step 2: Update `.make_base_config` to use `.meta`**; set

```r
logistic_tertile_glm = list(
  ...,
  index_var = .meta$index_var,
  tertile_right = if (.is_dementia) FALSE else TRUE,
  tertile_labels = if (.is_dementia) c("T1", "T2", "T3") else c("Q1", "Q2", "Q3"),
  model1_factors = .M1,
  model2_factors = .M2
)
```

And project/outcome fields from `.meta`.

- [ ] **Step 3: Pass `index_display`/`disease_display` into every `cross_lagged_sens_table_basename(...)` call**

- [ ] **Step 4: Change block**

```r
cfg$cross_lagged_change_logistic <- list(
  outcome_event_level = .meta$analysis_group,
  covariates = .M2,
  scheme = "tertile",
  index_stem = if (.is_dementia) "Leisure_activities" else "FI",
  output_suffix = ""
)
```

If change block hardcodes FI column names, add Dementia mapping only as required by existing `20block_cross_lagged_change_logistic.R` config keys (read that file and set the real keys — do not invent FI columns for Dementia).

- [ ] **Step 5: Dry-run parse**

```bash
Rscript -e 'parse("Blocks/54_cross_lagged_full/phases/phase_sensitivity.R")'
```

Expected: expression parse OK.

---

### Task 5: Early-event years map + FILTER_NOTE n_before check

**Files:**
- Modify: `R/cross_lagged_sensitivity.R` (add year map helper used by phase)
- Modify: `phases/phase_sensitivity.R` (`exclude_event_le_2y` branch)

**Interfaces:**
- Produces: `cross_lagged_sens_dementia_wave_years(db)` → `list(baseline=, fu=)`

```r
cross_lagged_sens_dementia_wave_years <- function(db) {
  switch(toupper(db),
    HRS   = list(baseline = 2010L, fu = c(2012L, 2014L, 2016L)),
    SHARE = list(baseline = 2015L, fu = c(2017L, 2019L, 2021L)),
    CLHLS = list(baseline = 2008L, fu = c(2012L, 2014L)),
    ELSA  = list(baseline = 2008L, fu = 2014L),
    stop("unknown db")
  )
}
```

- [ ] **Step 1: Test year map**

```r
stopifnot(cross_lagged_sens_dementia_wave_years("HRS")$baseline == 2010L)
stopifnot(identical(cross_lagged_sens_dementia_wave_years("ELSA")$fu, 2014L))
```

- [ ] **Step 2: Ensure `exclude_event_le_2y` uses long_all with year/Disease; if long lacks year, build minimal long ONLY from same CSV rules as C00 (document in FILTER_NOTE). Prefer existing `D05_long_*`.**

- [ ] **Step 3: In FILTER_NOTE always write `n_before=` equal to AfterMI nrow for that db (for complete_case, n_before = dabiao nrow before complete.cases).**

---

### Task 6: Anchor concordance smoke (unfiltered ELSA)

**Files:**
- Create: `scripts/smoke_dementia_sens_anchor_elsa.R`

**Purpose:** Before full sensitivity, prove continuity on ELSA AfterMI without scenario filter.

- [ ] **Step 1: Script loads AfterMI ELSA, applies Model2, computes tertile cuts with right=FALSE, prints cuts + n**

```r
study <- "/mnt/g/02block_result/20_Dementia/cross-laged_40595747"
source("R/cross_lagged_sensitivity.R")
d <- cross_lagged_sens_load_imputed(study, "ELSA")
d <- cross_lagged_sens_normalize_disease_group(d)
qs <- as.numeric(quantile(d$Leisure_activities, probs = c(1/3, 2/3), na.rm = TRUE))
cat("n=", nrow(d), " cuts=", paste(qs, collapse=","), "\n")
# Compare method to delivery Table 2-ELSA (labels T1/T2/T3). Note: delivery table cut display may be rounded; method must be 1/3,2/3.
```

- [ ] **Step 2: Run**

```bash
cd /mnt/e/01block/01Block-new-Final && Rscript scripts/smoke_dementia_sens_anchor_elsa.R
```

Expected: `n=5049`; cuts finite; no error.

- [ ] **Step 3: Optionally call `block_logistic_tertile_glm` once with dementia bl_cfg and confirm table footnote lists Model1/Model2 from lock**

---

### Task 7: Full sensitivity run + README

**Files:**
- Run against study_root (outputs under `sensitivity/`, `summary_result/table/`)
- Write: `{study_root}/sensitivity/README_sensitivity.txt`

- [ ] **Step 1: Smoke one cell**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript Blocks/54_cross_lagged_full/phases/phase_sensitivity.R \
  --study-root /mnt/g/02block_result/20_Dementia/cross-laged_40595747 \
  --only ELSA --scenario exclude_chronic_ge2 --no-sync
```

Expected: `sensitivity/exclude_chronic_ge2/ELSA/Tables/` contains S9 + S10 style xlsx; FILTER_NOTE has n_before=5049.

- [ ] **Step 2: Full four cohorts × three scenarios**

```bash
Rscript Blocks/54_cross_lagged_full/phases/phase_sensitivity.R \
  --study-root /mnt/g/02block_result/20_Dementia/cross-laged_40595747
```

Expected: S9–S17.1 present (Change may skip a db only if wide missing — must not happen for four DBs that already have `*_wide1.RData`).

- [ ] **Step 3: README contents**

```
time=...
study=Dementia Leisure_activities sensitivity
anchor=姜小胖_痴呆20260203 main analysis
data=data/Step01_RawData D01_AfterMI (n ELSA=5049 HRS=5361 SHARE=14682 CLHLS=1032)
Model1=Age+Education+Alcohol_drinking
Model2=Age+Education+Alcohol_drinking+Hypertension+Total_Cholesterol+HDL
tertile=per-cohort 1/3,2/3 right=FALSE labels=T1-T3
scenarios=exclude_chronic_ge2 | complete_case | exclude_event_le_2y
tables=S9-S17.1 isomorphic to hip shells
```

- [ ] **Step 4: Checklist against spec §9**

- [ ] AfterMI n match delivery  
- [ ] FILTER_NOTE n_before = main n  
- [ ] Logistic uses Leisure_activities + Dementia + T1–T3  
- [ ] Change uses Step05 wide ∩ filtered IDs  
- [ ] summary_result/table has copies  

---

## Spec coverage self-check

| Spec item | Task |
|-----------|------|
| Continuity hard constraint | Global + Task 6–7 |
| Three scenarios | Task 4, 7 |
| Four cohorts | Task 4 |
| Model1/2 lock | Task 1 |
| Tertile = main analysis | Task 3 |
| Table names Dementia/Leisure | Task 1, 4 |
| Loaders AfterMI/dabiao/long/wide | Task 2 |
| Wave years C00 | Task 5 |
| Change ∩ filtered IDs | Task 4, 7 |
| No second imputation / methods | Global Constraints |
| Hip table shell S9–S17.1 | Task 1, 4, 7 |

## Placeholder scan

None intentional. Change-block config key names must be verified against `20block_cross_lagged_change_logistic.R` in Task 4 Step 4 (read file, set real keys).
