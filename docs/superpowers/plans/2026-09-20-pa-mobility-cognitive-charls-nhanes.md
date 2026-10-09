# PA–Mobility Cognitive (CHARLS + NHANES) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a complete Medical-Blocks study for PA–mobility four phenotypes → CHARLS LMM cognitive trajectories + NHANES survey-weighted DSST/NfL, without modifying existing projects.

**Architecture:** New `Blocks/74_pa_mobility_cognitive_full/` registered in `R/pipeline_runner.R`; dual-unit `study_batch` (CHARLS / NHANES); reuse prepared D01–D05 under `/mnt/g/02block_result/02_Cognitive_impairment/trajectory_Personalized_yuhan/data` (UNC `\\192.168.68.133\02block_result\...`).

**Tech Stack:** R 4.5.1 (`Rscript.exe` path below), `lme4`, `survey`, `ggplot2`; engine `run_pipeline` / `run_study_batch`; `export_pub_figures`.

## Global Constraints

- R: `"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"`
- Install missing packages into that R library only
- Do not modify other studies under `02block_result` or existing configs/results
- Main model = LMM phenotype×time (not LCMM); NHANES NfL weight = `WTSSNH2Y`
- Phenotype ref = Active_preserved (code 1); thresholds locked (≥600 MET; any mobility difficulty)
- Data root default: `/mnt/g/02block_result/02_Cognitive_impairment/trajectory_Personalized_yuhan/data`
- Output root: `/mnt/g/02block_result/02_Cognitive_impairment/pa_mobility_cognitive_charls_nhanes`
- Pub figures: `pdf/png/tiff/image_information` via `export_pub_figures`
- No git commit unless user asks

---

## File map

| Path | Role |
|------|------|
| `Decisiontree/decision_tree_pa_mobility_cognitive.md` | Decision tree |
| `configs/config_pa_mobility_cognitive.R` | Single-pipeline config |
| `configs/config_pa_mobility_cognitive_batch.R` | Batch CHARLS/NHANES |
| `configs/templates/config_pa_mobility_cognitive*.template.R` | Templates |
| `run/pa_mobility_cognitive/run_*.R` | Entrypoints |
| `Blocks/74_pa_mobility_cognitive_full/*.R` | New blocks |
| `R/pipeline_runner.R` | Register `pamob_*` block paths |
| `R/pamob_utils.R` | Shared helpers (MET labels, phenotype key, LMM table fmt) |
| `Data/smoke/D01_pamob_charls.RData` / `D01_pamob_nhanes.RData` | Smoke subsets |
| `scripts/create_smoke_pamob_data.R` | Build smoke from real D0x |

---

### Task 1: Decision tree + utils + pipeline registration

**Files:**
- Create: `Decisiontree/decision_tree_pa_mobility_cognitive.md`
- Create: `R/pamob_utils.R`
- Modify: `R/pipeline_runner.R` (add `pamob_*` entries after `ip_stage2` / before `render_tables`)

**Interfaces:**
- Produces: `pamob_phenotype_key(pa_sufficient, mobility_limited)`, `pamob_out_dirs(ctx)`, `pamob_write_csv(df, path)`

- [ ] **Step 1:** Write decision tree mirroring approved spec §5–7
- [ ] **Step 2:** Implement `R/pamob_utils.R` with phenotype key 1–4 and output path helpers
- [ ] **Step 3:** Register all `pamob_*` block file paths in `pipeline_block_files()`

---

### Task 2: CHARLS assemble + feasibility + cognition long

**Files:**
- Create: `Blocks/74_pa_mobility_cognitive_full/00pamob_common.R`
- Create: `01block_pamob_feasibility.R`
- Create: `02block_pamob_assemble_charls.R` (load D05 + D01 + D02; baseline wave phenotype; merge cognition long)
- Create: `03block_pamob_cognition_long.R` (global = em+mi; Time_years)

**Interfaces:**
- Consumes: `config$pamob$data_root`, `baseline_wave` (default 2011), paths to D01/D02/D05
- Produces: `ctx$data$pamob_charls_wide`, `ctx$data$pamob_charls_long`, feasibility CSV under `Tables/Feasibility/`

- [ ] **Step 1:** Assemble from prepared RData/CSV (prefer `*-ok` / D05 object `phenotype`)
- [ ] **Step 2:** Feasibility matrix: n by wave × phenotype; attrition steps for baseline PA∩mobility∩≥1 follow-up cognition
- [ ] **Step 3:** Long table columns: `ID_h`, `Time_years`, `Global_cognition`, `Episodic_memory`, `phenotype` (baseline), covariates if present

---

### Task 3: CHARLS baseline Table1 + LMM + contrasts + Fig3

**Files:**
- Create: `04block_pamob_baseline_charls.R`
- Create: `05block_pamob_lmm_global.R`
- Create: `06block_pamob_lmm_episodic.R`
- Create: `07block_pamob_contrast_preset.R`
- Create: `08block_pamob_traj_plot.R`
- Create: `09block_pamob_sensitivity_charls.R`
- Create: `10block_pamob_flowchart.R`
- Create: `11block_pamob_concept_fig1.R`

**Interfaces:**
- LMM formula: `Global_cognition ~ Time_years * phenotype + Age + Sex + (1|ID_h)` (Model1); Model2/3 add covars from `config$pamob$covariates_*`
- Contrast: Inactive_preserved−Active_preserved and Active_limited−Inactive_limited on `Time_years:phenotype` slopes via `emmeans` or manual contrast on fixed effects
- Produces: `Tables/Table1_CHARLS_Baseline.csv`, `Table2_CHARLS_LMM_Global.csv`, `Figures/Figure 3. CHARLS cognitive trajectories.pdf`

- [ ] **Step 1:** Fit `lme4::lmer`; if missing package install via that Rscript
- [ ] **Step 2:** Export Table2 with phenotype×time terms + two preset contrasts
- [ ] **Step 3:** Plot predicted trajectories (ref + 3 levels) for Figure 3
- [ ] **Step 4:** Sensitivity: `phenotype_2`, exclude stroke if column exists, mobility_limited_2 already in D05

---

### Task 4: NHANES assemble + survey DSST/NfL + Fig4

**Files:**
- Create: `12block_pamob_assemble_nhanes.R`
- Create: `13block_pamob_baseline_nhanes.R`
- Create: `14block_pamob_svy_dsst.R`
- Create: `15block_pamob_svy_nfl.R`
- Create: `16block_pamob_panel_fig4.R`
- Create: `17block_pamob_sensitivity_nhanes.R`

**Interfaces:**
- Merge D03 PA + D04 mobility → phenotype4; join D02 DSST + D05 NfL on SEQN
- Survey design: `survey::svydesign(ids=~SDMVPSU, strata=~SDMVSTRA, weights=~WTSSNH2Y, nest=TRUE)` for NfL models; DSST-only may use MEC weight if configured
- Produces: `Table3_NHANES_Baseline.csv`, `Table4_NHANES_DSST_NfL.csv`, `Figure 4. NHANES DSST and NfL panel.pdf`

- [ ] **Step 1:** Build phenotype using same 1–4 key
- [ ] **Step 2:** `svyglm` continuous outcomes; log(SSSNFL)
- [ ] **Step 3:** Dual-panel predicted means / geometric means

---

### Task 5: Pub export + configs + runs + smoke

**Files:**
- Create: `18block_pamob_pub_export.R`
- Create: `configs/config_pa_mobility_cognitive.R`
- Create: `configs/config_pa_mobility_cognitive_batch.R`
- Create: `configs/templates/config_pa_mobility_cognitive.template.R`
- Create: `configs/templates/config_pa_mobility_cognitive_batch.template.R`
- Create: `run/pa_mobility_cognitive/run_pa_mobility_cognitive.R`
- Create: `run/pa_mobility_cognitive/run_pa_mobility_cognitive_batch.R`
- Create: `scripts/create_smoke_pamob_data.R`
- Create: `Data/smoke/D01_pamob_charls.RData`, `D01_pamob_nhanes.RData`
- Run: `python3 scripts/update_blocks_catalog.py`

**Interfaces:**
- `pipeline_shared`: `pamob_feasibility` (optional light clean)
- `pipeline_unit` CHARLS / NHANES branch blocks
- `finalize_blocks`: `pamob_pub_export`

- [ ] **Step 1:** Wire configs to real data paths + smoke paths
- [ ] **Step 2:** Dry-run batch `--shared-only` then unit CHARLS smoke
- [ ] **Step 3:** Update Blocks catalog

---

## Spec coverage checklist

| Spec item | Task |
|-----------|------|
| Decision tree / config / run / Blocks/74 | 1, 5 |
| Feasibility gate | 2 |
| Four phenotype + LMM + contrasts | 2–3 |
| Figures 1–4, Tables 1–4 | 3–5 |
| NHANES WTSSNH2Y | 4 |
| Pub four directories | 5 |
| No LCMM / no touch old projects | Global |

## Self-review

- No TBD placeholders in task file paths
- Phenotype key consistent code 1–4 / Active_preserved ref
- Block names in registration match config `pipeline$blocks`
