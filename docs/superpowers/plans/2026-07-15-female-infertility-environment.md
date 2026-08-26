# Female Infertility Environment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and run the NHANES environment VOC pipeline for female infertility with deletion mode enabled.

**Architecture:** Keep all study-specific artifacts under `G:/02block_result/12_Female infertility/environment_37419158`. Generate a study-specific baseline RData from the shared NHANES baseline plus `不孕症disease_data.csv`, then point a local config at that derived baseline and the uploaded environment SAV, weight, code, and urinary creatinine files.

**Tech Stack:** R 4.5.1, NHANES environment pipeline, `run/environment/run_environment_osteo_fuben_orchestrated.R`, `R/prepare_environment_dkd_data.R`.

## Global Constraints

- Do not modify shared pipeline blocks for this study.
- Keep the config inside the current study folder.
- Disease code is `12`.
- Outcome is female infertility, using `不孕症disease_data.csv` column `DN` as authoritative.
- Deletion mode uses `environment_lod$sample_column_filter_enable = TRUE`, missing thresholds 0.8 to 0.5 by 0.05, column cutoff 0.40, and at least 10 retained VOCs.
- Do not commit changes unless the user explicitly asks.

---

### Task 1: Study Baseline

**Files:**
- Create: `G:/02block_result/12_Female infertility/environment_37419158/data/nhanes/D01_baseline_NHANES_infertility_DN.RData`
- Read: `E:/01block/01Block-new-Final/Data/nhanes/D01_baseline_NHANES_0610(2).RData`
- Read: `G:/02block_result/12_Female infertility/environment_37419158/data/nhanes/不孕症disease_data.csv`

**Interfaces:**
- Produces: R object `baseline`, a data frame with `SEQN`, clinical covariates, `DN`, and `Source_File`.

- [x] Copy the shared baseline into the study data folder.
- [x] Merge by `SEQN`, keeping only rows present in `不孕症disease_data.csv`.
- [x] Save the merged object as `baseline`.
- [x] Verify final DN counts and overlap with environment weight/SAV.

### Task 2: Study Config

**Files:**
- Create: `G:/02block_result/12_Female infertility/environment_37419158/data/config_environment_infertility_batch.R`
- Read: `G:/02block_result/10_osteoporosis - 副本/environment_37419158/config_environment_osteo_fuben_batch.R`

**Interfaces:**
- Produces: a sourceable config exporting `config`, `pipeline_shared`, `pipeline_voc_batch`, `pipeline_tail`, and `pipeline`.

- [x] Adapt project paths and labels to female infertility.
- [x] Use `environment_prepare$mode = "baseline_sav"`.
- [x] Point `baseline_file` to `D01_baseline_NHANES_infertility_DN.RData`.
- [x] Enable sample-column deletion mode.
- [x] Keep two-stage orchestration with BKMR 100 screen and 1000 final.

### Task 3: Verification And Run

**Files:**
- Read: `G:/02block_result/12_Female infertility/environment_37419158/data/config_environment_infertility_batch.R`

**Interfaces:**
- Consumes: sourceable config from Task 2.
- Produces: full pipeline outputs under `G:/02block_result/12_Female infertility/environment_37419158`.

- [x] Source the config and print the critical path/label settings.
- [x] Run the prepare/shared smoke check if feasible.
- [x] Start the orchestrated full run with `--phase auto --workers auto`.
- [x] Monitor early output for missing file or merge errors.
