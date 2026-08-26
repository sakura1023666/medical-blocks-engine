# Cutoff Boundary Equals-High Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Unify exposure/index cutoff dichotomization to `x < cut` → low, `x >= cut` → high.

**Architecture:** Change RCS `cut(right=FALSE)` + labels; change explicit `<=` / `>` binary assignments and default labels to `<` / `>=`. Leave already-correct prognosis binary/segmented Cox alone.

**Tech Stack:** R Blocks pipeline

### Task 1: RCS helpers

- Modify `R/utils.R` `rcs_cutoff_factor`
- Modify `Blocks/15_rcs/02block_rcs_incidence.R` `.rci01_cutoff_factor`

### Task 2: Binary exposure grouping sites

- `Blocks/14_cutoff/01block_cutoff.R`
- `Blocks/34_IPTW/01block_iptw_balance.R`
- `Blocks/11_logistic/00logistic_iptw_weighted_common.R`
- `Blocks/18_subgroup/03block_subgroup_nhanes_weighted.R`

### Task 3: Grep verify

Confirm no remaining in-scope `<= cut` exposure dichotomies for Index_Group / RCS groups.
