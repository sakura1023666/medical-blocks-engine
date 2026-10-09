# TST sepsis-AKI eICU-primary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 在 `42_AKI_spesis` 跑通两阶段 Transformer：eICU 训练、MIMIC 外验。  
**Architecture:** 复用 71 块共享层 + task_parallel；外验脚本镜像为 MIMIC 组装。  
**Tech Stack:** R pipeline、Python `two_stage_transformer`、`prepare_*_external_and_eval.py`

---

### Task 1: dabiao + 白名单 + config

- [ ] 从小时表生成 `data/eicu/dabiao.csv`、`data/mimic/dabiao.csv`
- [ ] 新建 `configs/tst_feature_priority/aki_sepsis_eicu.R`
- [ ] 写项目根 `config_two_stage_transformer_stroke_task_parallel.R`（本病路径，A2 顺序）

### Task 2: MIMIC 外验

- [ ] 新增/泛化外验脚本：eICU 权重 + MIMIC 小时表 → `mimic_external`
- [ ] Fig S7 / summary 挂点可读 MIMIC 外验

### Task 3: 开跑

- [ ] `--shared-only`（`--config` 指向本项目）
- [ ] shared 通过后全矩阵 workers
