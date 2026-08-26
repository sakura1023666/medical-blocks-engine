# IPW no-index + Jin composite_risk STEPP — Implementation Plan

> **For agentic workers:** Execute task-by-task. Spec: `docs/superpowers/specs/2026-07-23-ipw-jin-composite-risk-no-index-design.md`

**Goal:** Remove composite-index batch (NLR); build Jin-style `composite_risk` from Model2Factors for STEPP; wipe old outputs; re-run once as unit `main`.

**Architecture:** Shared = `data_clean → column_mapping` only. Unit `main` runs IPW chain with new `ipw_jin_composite_risk` after VIF; STEPP `index_var=composite_risk`. `analysis_exclusion$allow_no_index=TRUE` drops all composites without a current index.

**Tech Stack:** R pipeline blocks, study_batch runner, existing `stepp_prognosis` jin_treatment.

## Tasks

- [ ] Task 1: `analysis_exclusion` allow_no_index + `iptw_balance` only ∪ index if column exists
- [ ] Task 2: New `09block_ipw_jin_composite_risk.R` + register in `pipeline_runner.R`
- [ ] Task 3: Config template + project config (`units=main`, no index, STEPP composite_risk)
- [ ] Task 4: Worker branch for `main` / `unit_mode=fixed` (no narrow, no stepp overwrite)
- [ ] Task 5: Delete old results (keep data/) and run shared + `--only-unit main --no-skip`
