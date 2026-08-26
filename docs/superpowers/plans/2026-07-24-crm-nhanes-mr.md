# CRM NHANES + Mendelian Randomization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an NHANES-only CRM × two-sample MR literature-depth pipeline (Han 2025 JAHA), with task-parallel batch, Feishu sync on base `RBjfb...`, reusing `Blocks/57_*` read-only and adding `Blocks/70_crm_nhanes_pub` for publication-quality gaps.

**Architecture:** Shared layer merges NHANES + mortality and derives CRM/exposure/weights; workers run via `study_batch` `unit_mode="branch"` (`obs_main`, `obs_strata`, `mr_cvd`, `mr_ckd`, `mr_diabetes`). Thin 57 blocks stay untouched; 70 wrappers/pub blocks produce Table2/4/S4, Fig1/3/S2 and deepen MR figures using `E:/孟德尔`.

**Tech Stack:** R 4.5.1 Windows `Rscript.exe`, `survey`, `survival`, `rms`/`ggplot2`, TwoSampleMR / custom IVW, Python for MR-PRESSO when needed, `processx`, Feishu bitable API, `study_batch_runner.R`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-24-crm-nhanes-mr-design.md`
- R binary: `"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"`
- Data (Windows paths in R):  
  `G:/02block_result/14_CRM/comorbid_Mendelia_randomization_40145269/data/nhanes/NHANES_文献_0722.RData` (obj `df`)  
  `G:/02block_result/14_CRM/comorbid_Mendelia_randomization_40145269/data/nhanes/nhanes-死亡.Rdata` (obj `combined_data`)
- Output root: `G:/02block_result/14_CRM/comorbid_Mendelia_randomization_40145269/` (or `Output/CRM_NHANES_MR` under project if live config prefers; template must set one absolute root)
- Do **not** modify `Blocks/01–69` (including `57_dual_incidence_mr_full`), existing `run/dual_incidence_mr/*`, or other finished projects
- New module: `Blocks/70_crm_nhanes_pub/` only (open `71+` only if a gap is proven)
- Feishu: app_token `RBjfb2iwmamW14s4WhKcS7kwnie` via process-local `Sys.setenv`; never rewrite `.env.feishu` BITABLE token
- `mirror_pub_outputs_to_root = TRUE`
- CHARLS tables/figures: skip and document; never fake with NHANES
- Do not create a git commit unless the user explicitly requests one
- Mendelian code/data: prefer `E:/孟德尔` + existing `Data/smoke/GWAS_*.csv`

## File map

| Path | Role |
|------|------|
| `Decisiontree/decision_tree_crm_nhanes_mr.md` | Decision tree + CHARLS skip list |
| `Blocks/70_crm_nhanes_pub/01block_crm_nhanes_derive.R` | Merge death + derive CRM/SUA/weights/follow-up |
| `Blocks/70_crm_nhanes_pub/02block_crm_nhanes_flowchart.R` | Figure S2 |
| `Blocks/70_crm_nhanes_pub/03block_crm_nhanes_baseline_weighted.R` | Table S4 |
| `Blocks/70_crm_nhanes_pub/04block_crm_nhanes_km_pub.R` | Figure 1 NHANES KM |
| `Blocks/70_crm_nhanes_pub/05block_crm_nhanes_ordinal_pub.R` | Table 2 pub (wrap/replace thin 57 weighted) |
| `Blocks/70_crm_nhanes_pub/06block_crm_nhanes_cox_pub.R` | Table 4 pub |
| `Blocks/70_crm_nhanes_pub/07block_crm_nhanes_rcs_pub.R` | Figure 3 pub |
| `Blocks/70_crm_nhanes_pub/08block_crm_nhanes_pub_align.R` | Mirror/check required outputs |
| `Blocks/70_crm_nhanes_pub/09block_crm_mr_figures.R` | MR Figs S3–S15 panels from IV results |
| `R/pipeline_runner.R` | Append 70 register paths only |
| `configs/templates/config_crm_nhanes_mr.template.R` | Single-run template |
| `configs/templates/config_crm_nhanes_mr_batch.template.R` | Batch template (`study_batch` + `branch_map`) |
| `run/crm_nhanes_mr/run_crm_nhanes_mr.R` | Single entry |
| `run/crm_nhanes_mr/run_crm_nhanes_mr_batch.R` | Batch entry |
| `run/crm_nhanes_mr/run_crm_nhanes_mr_batch_worker.R` | Worker entry |
| `run/feishu/run_feishu_setup_crm_nhanes_mr_tables.R` | Idempotent Feishu tables on `RBjfb...` |
| `scripts/smoke_crm_nhanes_derive.R` | Derive/merge smoke |

**Reuse (source only):** all `Blocks/57_dual_incidence_mr_full/*.R` already registered in `pipeline_runner.R` (`crm_*`, `mr_*`).

---

### Task 1: Decision tree + column audit smoke

**Files:**
- Create: `Decisiontree/decision_tree_crm_nhanes_mr.md`
- Create: `scripts/smoke_crm_nhanes_derive.R`

**Interfaces:**
- Produces audit CSV columns list used by Task 2 config keys: `SEQN`, `UricAcid`→`SUA`, `T2DM`, `Hypertension`, `MCQ160B/C/E/F`, `WTMEC2YR`/`SDMVSTRA`/`SDMVPSU`, death `seqn`/`mortstat`/`permth_int`.

- [ ] **Step 1: Write decision tree**

Create `Decisiontree/decision_tree_crm_nhanes_mr.md`:

```markdown
# 分析决策树 — NHANES CRM × 孟德尔（Han 2025 JAHA）

> Config：`configs/templates/config_crm_nhanes_mr_batch.template.R`  
> Run：`run/crm_nhanes_mr/run_crm_nhanes_mr_batch.R`  
> 规格：`docs/superpowers/specs/2026-07-24-crm-nhanes-mr-design.md`

## 共享层
`data_clean → crm_nhanes_derive`

## Worker
- `obs_main`: flowchart → baseline_weighted → ordinal_pub → cox_pub → rcs_pub → km_pub → pub_align
- `obs_strata`: crm_gout_strata（57）+ 亚组补充表
- `mr_cvd` / `mr_ckd` / `mr_diabetes`: mr_snp_screen → mr_twosample → mr_egger_presso → mr_pleiotropy → mr_sensitivity → crm_mr_figures

## CHARLS 跳过
Table1/3, Figure2, Table S3/S5/S7/S8/S10（单库）
```

- [ ] **Step 2: Write column audit smoke script**

Create `scripts/smoke_crm_nhanes_derive.R`:

```r
root <- normalizePath(getwd(), winslash = "/")
R <- list()
e <- new.env(); load("G:/02block_result/14_CRM/comorbid_Mendelia_randomization_40145269/data/nhanes/NHANES_文献_0722.RData", envir = e)
d <- e$df
e2 <- new.env(); load("G:/02block_result/14_CRM/comorbid_Mendelia_randomization_40145269/data/nhanes/nhanes-死亡.Rdata", envir = e2)
m <- e2$combined_data
stopifnot(is.data.frame(d), "SEQN" %in% names(d), "UricAcid" %in% names(d))
stopifnot(is.data.frame(m), all(c("seqn", "mortstat", "permth_int") %in% names(m)))
overlap <- sum(d$SEQN %in% m$seqn)
cat("n_df=", nrow(d), " n_mort=", nrow(m), " overlap=", overlap, "\n")
need <- c("UricAcid","T2DM","Hypertension","MCQ160B","MCQ160C","MCQ160E","MCQ160F",
          "WTMEC2YR","SDMVSTRA","SDMVPSU","Age","Gender","BMI")
miss <- need[!need %in% names(d)]
if (length(miss)) cat("MISSING_CORE:", paste(miss, collapse=", "), "\n") else cat("CORE_OK\n")
gout_cols <- grep("gout|Gout|MCQ2", names(d), value = TRUE, ignore.case = TRUE)
cat("gout_candidates:", paste(gout_cols, collapse = ", "), "\n")
```

- [ ] **Step 3: Run smoke**

Run:

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" scripts/smoke_crm_nhanes_derive.R
```

Expected: `CORE_OK` or explicit `MISSING_CORE` list; `overlap` > 0. If gout columns empty, Task 2 must set `gout_source = "optional_pause"` and `obs_strata` documents 【证据不足】/pause rather than inventing gout.

- [ ] **Step 4: Stop if overlap == 0**

If overlap is 0, fix SEQN/seqn type coercion in notes for Task 2 (`as.numeric`) before continuing; do not invent IDs.

---

### Task 2: `crm_nhanes_derive` block

**Files:**
- Create: `Blocks/70_crm_nhanes_pub/01block_crm_nhanes_derive.R`

**Interfaces:**
- Consumes: `ctx$data$cleaned %||% ctx$data$raw` after `data_clean`; config `$crm_nhanes_pub` + `$nhanes` + `$dual_incidence_mr`
- Produces: writes `ctx$data$cleaned` with columns `SUA`, `hyperuricemia`, `CVD`, `CKD`, `Diabetes`, `CRM_count`, `new_Weight`, `futime`, `fustatus`, optional `gout`; `ctx$results$crm_nhanes_derive`

- [ ] **Step 1: Implement derive block**

Create `Blocks/70_crm_nhanes_pub/01block_crm_nhanes_derive.R` with file-header contract and:

```r
block_crm_nhanes_derive <- function(ctx, ...) {
  bl <- ctx$config$crm_nhanes_pub %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data) || !is.data.frame(data))
    stop("PAUSE_FOR_USER_DECISION: crm_nhanes_derive 无数据", call. = FALSE)

  mort_path <- bl$mortality_path %||% ""
  if (!nzchar(mort_path) || !file.exists(mort_path))
    stop("crm_nhanes_derive: mortality_path 无效: ", mort_path, call. = FALSE)
  me <- new.env(); load(mort_path, envir = me)
  mort <- me[[bl$mortality_obj %||% "combined_data"]]
  mort$seqn <- as.numeric(mort$seqn)
  data$SEQN <- as.numeric(data$SEQN)
  data <- merge(data, mort[, c("seqn", "eligstat", "mortstat", "permth_int")],
                by.x = "SEQN", by.y = "seqn", all.x = TRUE)

  # SUA mg/dL
  sua_col <- bl$sua_col %||% "UricAcid"
  data$SUA <- as.numeric(data[[sua_col]])
  data$hyperuricemia <- as.integer(data$SUA >= (bl$hyperuricemia_cut_mgdl %||% 7))

  # CRM components (paper-aligned mapping; adjust via config if needed)
  data$Diabetes <- as.integer(data[[bl$diabetes_col %||% "T2DM"]] %in% c(1, "1", TRUE, "Yes"))
  # CKD: creatinine-based eGFR if available; else pause or config flag
  # CVD: any of MCQ160B/C/E/F == 1
  cvd_cols <- bl$cvd_cols %||% c("MCQ160B", "MCQ160C", "MCQ160E", "MCQ160F")
  cvd_cols <- cvd_cols[cvd_cols %in% names(data)]
  data$CVD <- if (length(cvd_cols)) {
    as.integer(rowSums(sapply(cvd_cols, function(c) data[[c]] %in% c(1, "1")), na.rm = TRUE) > 0)
  } else NA_integer_

  # CKD placeholder: use config$crm_nhanes_pub$ckd_rule
  # implement eGFR from Creatinine+Age+Gender (CKD-EPI) when bl$ckd_rule == "ckd_epi"
  data$CKD <- NA_integer_
  if (identical(bl$ckd_rule %||% "ckd_epi", "ckd_epi") && all(c("Creatinine","Age","Gender") %in% names(data))) {
    # inline CKD-EPI 2009 simplified; female/male, race if available
    scr <- as.numeric(data$Creatinine)
    age <- as.numeric(data$Age)
    female <- tolower(as.character(data$Gender)) %in% c("f", "female", "2", "女")
    # kappa/alpha
    kap <- ifelse(female, 0.7, 0.9); alp <- ifelse(female, -0.329, -0.411)
    egfr <- 141 * (pmin(scr/kap, 1)^alp) * (pmax(scr/kap, 1)^(-1.209)) * (0.993^age) * ifelse(female, 1.018, 1)
    data$eGFR <- egfr
    data$CKD <- as.integer(egfr < 60)
  }

  data$CRM_count <- as.integer(data$CVD) + as.integer(data$CKD) + as.integer(data$Diabetes)
  data$CRM_count <- pmin(data$CRM_count, 3L)

  wt <- bl$weight_col %||% "WTMEC2YR"
  data$new_Weight <- as.numeric(data[[wt]])
  data$futime <- as.numeric(data$permth_int)
  data$fustatus <- as.integer(data$mortstat == 1)

  # Age filter (paper: middle-aged and older; default >=45)
  min_age <- bl$min_age %||% 45
  data <- data[!is.na(data$Age) & data$Age >= min_age, , drop = FALSE]

  gout_col <- bl$gout_col
  if (!is.null(gout_col) && gout_col %in% names(data)) {
    data$gout <- as.integer(data[[gout_col]] %in% c(1, "1", TRUE, "Yes"))
  } else if (isTRUE(bl$pause_on_missing_gout %||% FALSE)) {
    stop("PAUSE_FOR_USER_DECISION: 无痛风列，见 crm_nhanes_pub$gout_col", call. = FALSE)
  }

  ctx$data$cleaned <- data
  ctx$data$raw <- data
  ctx$results$crm_nhanes_derive <- list(n = nrow(data), n_death = sum(data$fustatus == 1, na.rm = TRUE))
  cli::cli_alert_success("crm_nhanes_derive n={nrow(data)}")
  ctx
}
register_block("crm_nhanes_derive", block_crm_nhanes_derive, "NHANES CRM 派生")
```

Fill CKD-EPI fully in the file (no “simplified later”). Keep helper prefix `.crm70d_`.

- [ ] **Step 2: Parse-check**

Run:

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" -e "parse('Blocks/70_crm_nhanes_pub/01block_crm_nhanes_derive.R')"
```

Expected: no error.

---

### Task 3: Flowchart + baseline + KM pub blocks

**Files:**
- Create: `Blocks/70_crm_nhanes_pub/02block_crm_nhanes_flowchart.R`
- Create: `Blocks/70_crm_nhanes_pub/03block_crm_nhanes_baseline_weighted.R`
- Create: `Blocks/70_crm_nhanes_pub/04block_crm_nhanes_km_pub.R`

**Interfaces:**
- Consumes: `ctx$data$cleaned` with derive columns
- Produces files under `output_dir/Figures` / `Tables`: `Figure_S2_Flowchart.*`, `Table_S4_Baseline_NHANES.csv`, `Figure_1_KM_NHANES.*`

- [ ] **Step 1: Flowchart block**

Mirror structure of `Blocks/69_ipw_diabetes_stroke_full/02block_ipw_flowchart.R` but counts for NHANES: raw n → age filter → SUA non-missing → mortality eligible → analytic n. Export PNG/PDF + counts CSV. `register_block("crm_nhanes_flowchart", ...)`.

- [ ] **Step 2: Weighted baseline Table S4**

Use `survey::svydesign` + `svymean`/`svytable` stratified by `CRM_count` or exposure as in paper Table S4. Prefer `export_sci_table` if available. `register_block("crm_nhanes_baseline_weighted", ...)`.

- [ ] **Step 3: KM Figure 1 NHANES**

`survfit(Surv(futime, fustatus) ~ CRM_count)` (and/or gout strata if present). Save publication PNG. Pattern reference: `69_ipw_diabetes_stroke_full/03block_ipw_weighted_km_pub.R` (unweighted OK for KM display if paper shows unweighted KM; if paper KM is unweighted, do not force survey KM). `register_block("crm_nhanes_km_pub", ...)`.

- [ ] **Step 4: Parse all three**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" -e "for (f in dir('Blocks/70_crm_nhanes_pub', full.names=TRUE)) parse(f)"
```

Expected: silent success.

---

### Task 4: Ordinal / Cox / RCS publication wrappers (70)

**Files:**
- Create: `Blocks/70_crm_nhanes_pub/05block_crm_nhanes_ordinal_pub.R`
- Create: `Blocks/70_crm_nhanes_pub/06block_crm_nhanes_cox_pub.R`
- Create: `Blocks/70_crm_nhanes_pub/07block_crm_nhanes_rcs_pub.R`
- Create: `Blocks/70_crm_nhanes_pub/08block_crm_nhanes_pub_align.R`

**Interfaces:**
- Do **not** edit 57 files. These blocks implement literature-depth Table 2 / Table 4 / Figure 3.
- Optionally call thin 57 blocks only for smoke comparison via config `crm_nhanes_pub$also_run_thin57 = FALSE` (default FALSE).

- [ ] **Step 1: Ordinal pub (Table 2)**

`svyolr` / cumulative logit for exposures: continuous `SUA`, `hyperuricemia`, `gout` (if present). Models: crude + Model2 (age, sex, BMI, … from `bl$adjust_vars`). Export OR (95% CI) CSV named `Table_2_Ordinal_NHANES.csv`.

- [ ] **Step 2: Cox pub (Table 4)**

Weighted Cox (`survey::svycoxph`) for all-cause mortality by CRM strata (0 / 1 / ≥1 / 2 / 3 as paper). Export `Table_4_Cox_NHANES.csv`.

- [ ] **Step 3: RCS pub (Figure 3)**

RCS of SUA vs mortality within CRM groups; `P for nonlinearity`. Save `Figure_3_RCS_NHANES.pdf/png` + numeric table.

- [ ] **Step 4: pub_align**

Check required filenames exist; call `mirror_pub_output_to_root` if exposed; write `Pub_align_checklist.csv` with pass/fail per artifact.

- [ ] **Step 5: Parse-check Task 4 files**

Same parse loop as Task 3.

---

### Task 5: MR figures block + Mendelian path wiring

**Files:**
- Create: `Blocks/70_crm_nhanes_pub/09block_crm_mr_figures.R`

**Interfaces:**
- Consumes: `ctx$results$mr_twosample` / MR CSV under `Tables/MR/` from 57 chain; GWAS paths from `config$dual_incidence_mr`
- Produces: scatter / forest / leave-one-out / funnel under `Figures/MR/` mapped to paper S4–S15 naming
- Calls helpers under `E:/孟德尔/0代码` when present (source specific `.R` files by config list); else ggplot fallbacks

- [ ] **Step 1: Inventory Mendelian scripts**

```bash
ls "/mnt/e/孟德尔/0代码" | head -40
ls "/mnt/e/01block/01Block-new-Final/Data/smoke"/GWAS_*.csv
```

Record which script draws scatter/forest; put paths in config `dual_incidence_mr$mendelian_lib_root = "E:/孟德尔"`.

- [ ] **Step 2: Implement `crm_mr_figures`**

Read IVW table; for active outcome(s) write at least: scatter, forest, funnel, leave-one-out. File names:

```text
Figure_S4_MR_scatter_CVD.png
Figure_S5_MR_scatter_CKD.png
...
Table_5_MR_Estimates.csv  # copy/enrich from IVW+Egger+PRESSO
```

- [ ] **Step 3: Parse-check**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" -e "parse('Blocks/70_crm_nhanes_pub/09block_crm_mr_figures.R')"
```

---

### Task 6: Register blocks + configs + run scripts

**Files:**
- Modify: `R/pipeline_runner.R` (append only after `crm_gout_strata` / near 57 block entries)
- Create: `configs/templates/config_crm_nhanes_mr.template.R`
- Create: `configs/templates/config_crm_nhanes_mr_batch.template.R`
- Create: `run/crm_nhanes_mr/run_crm_nhanes_mr.R`
- Create: `run/crm_nhanes_mr/run_crm_nhanes_mr_batch.R`
- Create: `run/crm_nhanes_mr/run_crm_nhanes_mr_batch_worker.R`

**Interfaces:**
- Batch uses existing `run_study_batch` + `unit_mode = "branch"`
- Worker patches `mr_outcomes` when unit is `mr_*`

- [ ] **Step 1: Append runner mappings**

In `pipeline_block_sources()`, append:

```r
    crm_nhanes_derive             = b("70_crm_nhanes_pub/01block_crm_nhanes_derive.R"),
    crm_nhanes_flowchart          = b("70_crm_nhanes_pub/02block_crm_nhanes_flowchart.R"),
    crm_nhanes_baseline_weighted  = b("70_crm_nhanes_pub/03block_crm_nhanes_baseline_weighted.R"),
    crm_nhanes_km_pub             = b("70_crm_nhanes_pub/04block_crm_nhanes_km_pub.R"),
    crm_nhanes_ordinal_pub        = b("70_crm_nhanes_pub/05block_crm_nhanes_ordinal_pub.R"),
    crm_nhanes_cox_pub            = b("70_crm_nhanes_pub/06block_crm_nhanes_cox_pub.R"),
    crm_nhanes_rcs_pub            = b("70_crm_nhanes_pub/07block_crm_nhanes_rcs_pub.R"),
    crm_nhanes_pub_align          = b("70_crm_nhanes_pub/08block_crm_nhanes_pub_align.R"),
    crm_mr_figures                = b("70_crm_nhanes_pub/09block_crm_mr_figures.R"),
```

- [ ] **Step 2: Write batch template skeleton**

`configs/templates/config_crm_nhanes_mr_batch.template.R` must define `config`, `pipeline_shared`, `pipeline_unit`, with:

```r
study_batch = list(
  output_base = .batch_project_root,
  project_root = .block_repo_root,
  units = c("obs_main", "obs_strata", "mr_cvd", "mr_ckd", "mr_diabetes"),
  unit_mode = "branch",
  parallel_workers = "auto",
  worker_script = "run/crm_nhanes_mr/run_crm_nhanes_mr_batch_worker.R",
  shared_ck_alias = "crm_nhanes_derive",
  branch_map = list(
    obs_main = list(blocks = c(
      "crm_nhanes_flowchart", "crm_nhanes_baseline_weighted",
      "crm_nhanes_ordinal_pub", "crm_nhanes_cox_pub", "crm_nhanes_rcs_pub",
      "crm_nhanes_km_pub", "crm_nhanes_pub_align"
    )),
    obs_strata = list(blocks = c("crm_gout_strata")),
    mr_cvd = list(blocks = c(
      "mr_snp_screen", "mr_twosample", "mr_egger_presso",
      "mr_pleiotropy", "mr_sensitivity", "crm_mr_figures"
    )),
    mr_ckd = list(blocks = c(
      "mr_snp_screen", "mr_twosample", "mr_egger_presso",
      "mr_pleiotropy", "mr_sensitivity", "crm_mr_figures"
    )),
    mr_diabetes = list(blocks = c(
      "mr_snp_screen", "mr_twosample", "mr_egger_presso",
      "mr_pleiotropy", "mr_sensitivity", "crm_mr_figures"
    ))
  )
)

pipeline_shared <- list(
  name = "crm_nhanes_mr_shared",
  blocks = c("data_clean", "crm_nhanes_derive"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "_shared", "main"))
)

pipeline_unit <- list(
  name = "crm_nhanes_mr_unit",
  blocks = character(0)  # filled per branch_map in patch
)

feishu = list(
  enable = TRUE,
  app_token = "RBjfb2iwmamW14s4WhKcS7kwnie",
  disease_label = "14_CRM_NHANES_MR",
  protocol_label = "crm_nhanes_mr",
  project_id = "14_crm_nhanes_mr_038723",
  workplan_code = "B30",
  push_on_worker_finish = TRUE,
  push_on_batch_summary = TRUE
)
```

Also set `data$rawdata_path`, `rawdata_obj="df"`, `crm_nhanes_pub$mortality_path`, `mirror_pub_outputs_to_root=TRUE`, NHANES weight/strata/cluster columns.

- [ ] **Step 3: Write single + batch + worker runners**

Copy pattern from `run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R` and worker. In worker, after loading config and before `run_pipeline`:

```r
unit <- trimws(Sys.getenv("STUDY_BATCH_UNIT", ""))
if (identical(unit, "mr_cvd")) config$dual_incidence_mr$mr_outcomes <- "CVD"
if (identical(unit, "mr_ckd")) config$dual_incidence_mr$mr_outcomes <- "CKD"
if (identical(unit, "mr_diabetes")) config$dual_incidence_mr$mr_outcomes <- "Diabetes"
# Feishu process-local token
if (nzchar(config$feishu$app_token %||% ""))
  Sys.setenv(FEISHU_BITABLE_APP_TOKEN = config$feishu$app_token)
```

Use `study_batch_patch_config_for_unit`, copy shared ck, run `worker_blocks`, write status, push Feishu.

- [ ] **Step 4: Shared-only smoke**

```bash
cd /mnt/e/01block/01Block-new-Final
SMOKE_NO_FEISHU=1 "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/crm_nhanes_mr/run_crm_nhanes_mr_batch.R --shared-only --no-skip
```

Expected: shared checkpoint `crm_nhanes_derive.rds` (or `index.rds`) exists under project checkpoints.

---

### Task 7: Feishu setup script

**Files:**
- Create: `run/feishu/run_feishu_setup_crm_nhanes_mr_tables.R`

**Interfaces:**
- Clone structure from `run/feishu/run_feishu_setup_ipw_diabetes_tables.R`
- Hard-default app_token `RBjfb2iwmamW14s4WhKcS7kwnie`
- Process-local `Sys.setenv` only

- [ ] **Step 1: Copy/adapt IPW setup script**

Rename labels to CRM NHANES MR; create 项目汇总 / 成功指标 / 失败指标 (and optional 套路已做). Print table IDs for manual paste into live config `feishu$table_*` fields.

- [ ] **Step 2: Run setup (needs network + user app auth)**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run/feishu/run_feishu_setup_crm_nhanes_mr_tables.R
```

Expected: prints three `tbl...` IDs. Paste into batch template `feishu` section (not into `.env.feishu` default BITABLE token).

---

### Task 8: End-to-end smoke by unit

**Files:**
- Test only (no new code unless bugs found in 70/run)

- [ ] **Step 1: obs_main**

```bash
SMOKE_NO_FEISHU=1 "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/crm_nhanes_mr/run_crm_nhanes_mr_batch.R --only-unit obs_main --workers 1 --no-skip
```

Expected artifacts: Table_2, Table_4, Table_S4, Figure_S2, Figure_1, Figure_3, Pub_align_checklist pass for NHANES set.

- [ ] **Step 2: one MR unit**

```bash
SMOKE_NO_FEISHU=1 "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/crm_nhanes_mr/run_crm_nhanes_mr_batch.R --only-unit mr_cvd --workers 1 --no-skip
```

Expected: `Table_MR_IVW_Results.csv` or `Table_5_MR_Estimates.csv` + at least one MR figure.

- [ ] **Step 3: Full batch parallel**

```bash
SMOKE_NO_FEISHU=1 "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/crm_nhanes_mr/run_crm_nhanes_mr_batch.R --workers auto --no-skip
```

Expected: `Batch_summary_all_units.csv` with 5 units; folders `【success】*` or documented failures.

- [ ] **Step 4: Feishu push (optional if credentials ready)**

Re-run without `SMOKE_NO_FEISHU` for one unit; expect Sheet2 upsert log line.

- [ ] **Step 5: Regression check**

```bash
git status --short Blocks/57_dual_incidence_mr_full run/dual_incidence_mr
```

Expected: clean (no modifications to those paths).

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| NHANES data + death merge | 1–2 |
| Derive CRM/SUA/weights/follow-up | 2 |
| Figure S2 / Table S4 / Fig1 | 3 |
| Table 2 / Table 4 / Fig3 | 4 |
| CHARLS skip documented | 1 |
| Reuse 57 read-only | 6 (MR + gout_strata) |
| MR Table5 + S figures | 5–6, 8 |
| Batch task parallel | 6, 8 |
| Feishu RBjfb | 7–8 |
| mirror_pub TRUE | 4, 6 |
| R 4.5.1 Windows | all run steps |
| E:/孟德尔 | 5 |
| Do not edit 01–69 | Global + Task 8 step 5 |

## Self-review notes

- Placeholder scan: gout handled via audit + optional pause (no invented values).
- `study_batch` `branch` mode supplies per-unit blocks; worker sets `mr_outcomes`.
- Thin 57 observational blocks are **not** used for pub tables; 70 pub blocks supersede them to meet literature depth without editing 57.
