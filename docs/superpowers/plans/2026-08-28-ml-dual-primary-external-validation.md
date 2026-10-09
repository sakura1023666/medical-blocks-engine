# ML Dual Primary External Validation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Secondary ML DB skips UV/VIF/FS and inherits primary features; primary = larger N; re-run sdLDL_C.

**Architecture:** Change `ml_dual_secondary_ml_symmetric_blocks` + pipeline render lists + worker messaging; assert N; swap study `.study` roles; delete index outputs/ck and re-run worker.

**Tech Stack:** R medical-blocks engine, study config on DockerHome.

## Task 1: Engine secondary blocks

- Modify `configs/ml_dual_shared_overrides.R` — drop UV/VIF from secondary
- Modify `configs/study_interface/ml_dual_batch_pipelines.R` — render_tables_after
- Modify `run/ml/run_ml_dual_batch_worker.R` — comments + assert call
- Add `ml_dual_assert_primary_larger_n` in `R/ml_dual_pipeline_helpers.R`

## Task 2: Study config + rule

- Swap CHARLS/NHANES in study `config.R`; `apply_nhanes_upstream=FALSE`
- Add `.cursor/rules/ml_dual_primary_external_validation.mdc`

## Task 3: Clean + re-run

- Delete `by_index/*sdLDL_C*` and `checkpoints/by_index/sdLDL_C`
- `Rscript run/ml/run_ml_dual_batch_worker.R --config <study>/config.R --index sdLDL_C`
- Verify features match, no weight cols, dual figures present
