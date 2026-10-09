# eICU 真小时长表接入 TST Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按原文 Methods 把 eICU 小时长表接入两阶段 Transformer，真 `H=24` 槽 + `expand_hours=FALSE`，并跑通 `33_AKI` shared-only。

**Architecture:** `tst_timeseries` 增加 `lab_format=eicu_hourly_long` 分支；`prepare.py` 在 `expand_hours=False` 时按日内小时填槽；`tst_cohort` 兼容 `patientunitstayid` / `hospdischargestatus`；AKI 课题 config + dabiao。

**Tech Stack:** R Blocks (`71_*`)、Python `python/two_stage_transformer/prepare.py`、data.table/pandas、现有 task-parallel runner。

**Spec:** `docs/superpowers/specs/2026-08-28-tst-eicu-hourly-long-design.md`

## Global Constraints

- 默认 `lab_format=mimic_day_wide` 行为不变（卒中回归）。
- 小时值列默认 `mean`；脚注标明非 offset-nearest。
- 不提交 git（除非用户明确要求）。
- 产出只写 `G:/02block_result/33_AKI/two_stage_transformer_40041421/`。

## File map

| 文件 | 职责 |
|------|------|
| `python/two_stage_transformer/prepare.py` | 真小时张量 |
| `tests/test_tst_prepare_hourly.py` | prepare 单测 |
| `Blocks/71_two_stage_transformer_stroke/02block_tst_timeseries.R` | eicu 长表分支 |
| `Blocks/71_two_stage_transformer_stroke/01block_tst_cohort.R` | eICU 键/结局/LOS |
| `.../33_AKI/.../data/eicu/dabiao.csv` | 入选名单 |
| `.../33_AKI/.../config_two_stage_transformer_stroke_task_parallel.R` | 课题 config |

---

### Task 1: prepare.py 真小时

**Files:**
- Modify: `python/two_stage_transformer/prepare.py`
- Create: `tests/test_tst_prepare_hourly.py`

**Interfaces:**
- Consumes: `_tst_hourly_long.csv` with `patient,day,hour(0-23),feats...,label,los_days`
- Produces: `X(n,D,H,F)` with true per-hour values when `expand_hours=False`

- [ ] **Step 1:** 写失败单测：2 患者 × 2 天 × 不同小时值 → `expand_hours=False` 时 `X[0,0,0,0] != X[0,0,1,0]`
- [ ] **Step 2:** 实现 `_patient_day_hour_table` + 改 `_expand_windows`；兼容旧 `hour=day*24` 单行
- [ ] **Step 3:** 跑通单测；另测 `expand_hours=True` 广播仍成立

---

### Task 2: tst_timeseries eicu_hourly_long

**Files:**
- Modify: `Blocks/71_two_stage_transformer_stroke/02block_tst_timeseries.R`

**Interfaces:**
- Consumes: `config$tst_timeseries$lab_format`, `value_col`, `lab_long_path`
- Produces: `_tst_hourly_long.csv`（真小时行）+ coverage audit

- [ ] **Step 1:** 分支读取；pivot；day/hour_in_day；覆盖率；按小时 ffill；导出
- [ ] **Step 2:** 默认 `mimic_day_wide` 代码路径保持原样

---

### Task 3: tst_cohort eICU

**Files:**
- Modify: `Blocks/71_two_stage_transformer_stroke/01block_tst_cohort.R`

- [ ] **Step 1:** dabiao/prognosis 候选加 `patientunitstayid`
- [ ] **Step 2:** 派生 `is_hosp_dead`；LOS 用 `unitlosday`；排除 `<1` 天；空 disposition 剔除

---

### Task 4: AKI 课题落地

**Files:**
- Create: `.../data/eicu/dabiao.csv`
- Create: `.../config_two_stage_transformer_stroke_task_parallel.R`（从卒中 task_parallel 改路径/开关）

- [ ] **Step 1:** 从小时表写 dabiao
- [ ] **Step 2:** config：`lab_format`、`expand_hours=FALSE`、EICU 路径、disease_code=33

---

### Task 5: shared-only 冒烟

- [ ] **Step 1:** `Rscript ...task_parallel.R --config <AKI config> --shared-only`
- [ ] **Step 2:** 检查导出长表同日多 hour；日志含 `eicu_hourly_long`

---
