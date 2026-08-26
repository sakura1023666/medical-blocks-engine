# IBD 双库轨迹预后 Implementation Plan

> **For agentic workers:** Execute task-by-task. Spec: `docs/superpowers/specs/2026-08-25-ibd-trajectory-prognosis-design.md`

**Goal:** 在 IBD 人群上跑 eICU+MIMIC 轨迹预后 JLCM，`dual_safe` 全量 by_index 并行；本课题关 Gate A，`disease_vars` 仅 `IBD_subtype`。

**Architecture:** 预处理写出 `D04_rt_IBD_surv28.RData` → IBD 专用 batch config（无 Gate A）→ 复用 `run_trajectory_prognosis_apri_batch.R`。

**Tech Stack:** R, Medical Blocks trajectory batch runner, JLCM

## Global Constraints

- 关 Gate A（不挂 `dual_db_column_harmonize`）
- `disease_vars = IBD_subtype` only（本课题）
- `index_group = dual_safe`
- 结局：28d 院内死亡
- 不改其他课题模板默认

---

## Task 1: 数据准备脚本

- Create: `run/trajectory_prognosis/prepare_ibd_surv28_data.R`
- 筛 IBD、合并 28d 院内死亡、写出两库 `rt`、`_column_review.md`、纳排摘要
- Run script and verify n≈211/196

## Task 2: baseline 挂 analysis_exclusion + IBD config

- Update: `configs/study_interface/baseline_pipelines.json` trajectory shared: `index` → `analysis_exclusion` → `trajectory_calc_28d_index`
- Create: `configs/config_trajectory_prognosis_ibd_batch.R`（自轨迹模板）

## Task 3: 冒烟 + 全量并行

- Smoke: `--only-index NLR --workers 1`
- Full: `dual_safe` 并行
