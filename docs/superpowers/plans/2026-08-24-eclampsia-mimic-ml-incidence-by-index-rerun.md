# 子痫 by_index 发病 ML 重跑 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重建 `27_eclampsia/small sample prediction_39780007/config.R`，用 `D04_dabiao`（n=4756）以 10 worker 重跑 by_index 发病六模型批处理。

**Architecture:** 从 SDD Task 3 全文恢复 `config.R`（`ml_dual_batch_build` + incidence 覆盖）→ 自检 → Windows bat 启动 `run_ml_dual_batch.R --workers 10 --db nhanes`。不改主仓引擎；不做 all_vars / Table 4/5。

**Tech Stack:** R 4.5.1（Windows `Rscript.exe`）、`run/ml/run_ml_dual_batch.R`、TabPFN（`C:/ProgramData/anaconda3/python.exe`）、MIMIC 单库。

## Global Constraints

- 课题根：`/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/`
- 主仓：`/mnt/e/01block/01Block-new-Final`（`MEDICAL_BLOCKS_ROOT`）
- 仅六模型：`adaboost`, `tabpfnv2`, `catboost`, `xgboost`, `lightgbm`, `rf`
- `index_group=all`，`index_vars=NULL`，10 workers，`fail_policy=continue`
- 发病 logistic（禁止 `assoc_model="cox"`）
- `age_cutoff=35`；`Age_Group` 仅 `"< 35"` / `"≥ 35"`
- 分析表仅 `D04_dabiao`（不用 `dabiao_clean`）
- 无 git：跳过所有 commit 步骤
- Spec：`docs/superpowers/specs/2026-08-24-eclampsia-mimic-ml-incidence-by-index-rerun-design.md`

---

## File map

| 路径 | 职责 |
|------|------|
| `…/config.R` | 程序员 config（重建，对齐 Task 3） |
| `…/Data/mimic/D04_dabiao.RData` | 已有分析表（只读） |
| `.superpowers/sdd/eclampsia-launch-ml-batch.bat` | Windows 启动器（可更新） |
| `run/ml/run_ml_dual_batch.R` | 只调用，不改 |

---

### Task 1: 重建 config.R

**Files:**
- Create: `/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/config.R`
- Source text: `.superpowers/sdd/eclampsia-task-3-review-pkg.md` Full config.R 块（L31–261）

- [x] **Step 1:** 将 Task 3 全文 config 写入课题根 `config.R`（不含 markdown 围栏）。
- [x] **Step 2:** 确认 `primary_rdata_file = "D04_dabiao.RData"`、`outcome_column = "DN"`、六模型名单与 disease_vars 13 项。

**Verify:**
```bash
test -f "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/config.R"
grep -E 'tabpfnv2|age_cutoff|D04_dabiao|assoc_model' ".../config.R" | head
```
Expected: 文件存在；含 `tabpfnv2`、`age_cutoff = 35L`、`D04_dabiao`、`logistic`。

---

### Task 2: 自检 config + 数据

**Files:**
- Test via Rscript against study config

- [x] **Step 1:** 设置 `MEDICAL_BLOCKS_ROOT`，source config，跑 stopifnot：
  - `length(config$ml_models$methods)==6L`
  - `identical(as.integer(config$subgroup$age_cutoff), 35L)`
  - `identical(config$ml_batch$assoc_model, "logistic")`
  - `identical(config$ml_batch$index_group, "all")`
  - `file.exists(config$data$rawdata_path)` 且 load 后 `nrow(dabiao)==4756`
  - `length(config$analysis_exclusion$disease_vars)==13L`
- [x] **Step 2:** 若失败，修 config 后重跑自检。

---

### Task 3: 启动 10-worker 批跑

**Files:**
- Update/use: `.superpowers/sdd/eclampsia-launch-ml-batch.bat`
- Target config: `G:/02block_result/27_eclampsia/small sample prediction_39780007/config.R`

- [x] **Step 1:** 确认 bat 指向 `config.R`，含 `MEDICAL_BLOCKS_ROOT` 与 `MEDICAL_BLOCKS_SKIP_WIN_R=1`，`--workers 10 --db nhanes`。
- [x] **Step 2:** 经 Windows 启动（ProcessStartInfo 对 config 路径加引号），避免路径空格拆参。
- [x] **Step 3:** 确认 `logs/` 出现、master 存活、`by_index/` 开始出现目录。

**Success:** `db_mode=nhanes, workers=10` 调度可见；至少若干指标目录写入。

---

## Spec coverage

| Spec 要求 | Task |
|-----------|------|
| 重建 config + 六模型/35/disease_vars | 1–2 |
| D04 only，不用 dabiao_clean / all_vars | 1–2 |
| 10 worker Windows 启动 | 3 |
| 不做 Table 4/5 | （无 task，故意省略） |
