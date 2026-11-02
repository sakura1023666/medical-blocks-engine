# 子痫前期(诊断=1)人群 · 不良妊娠结局全指标并行发病 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `27_eclampsia/incidence_38341157` 改为仅「诊断=1」（子痫前期/子痫）人群，结局仍为不良妊娠结局，跑全部可算复合指标，并行 workers。

**Architecture:** 复用现有回顾单库发病 batch（`db_mode=mimic`）。新建诊断=1 子集 dabiao + 独立 config/输出根，避免覆盖全队列旧结果；`PE_Diagnosis` 在子集内恒为 Yes，从协变量/亚组剔除。

**Tech Stack:** R Medical Blocks incidence dual-batch；`run/incidence/run_incidence_dual_batch.R`；并行 `--workers`。

**Scheduled start:** **2026-11-02 17:30（五点半）** 执行 shared-only → workers。

## Global Constraints

- 结局：`Disease_Group` = Adverse_pregnancy_outcome vs No_adverse_pregnancy_outcome（不变）
- 人群：仅 `PE_Diagnosis == "Yes"`（诊断全 1）；预期 **n=1124**（事件 778 / 非事件 346）
- 数据源：回顾 `全部数据整合`；单位换算逻辑与现 `dabiao_retro_apo` 一致
- 指标：可算全复合指标（共享层筛查后锁定名单；仍 skip HDL/LDL 自身组成暴露）
- 并行：`--workers 2`（或机器允许时 4）；`--db mimic`
- **禁止覆盖** 现有全队列 `by_index/【success】*`；新跑必须用新输出根
- 年龄亚组切点仍 **35**；MICE `m=5` + 推断 Rubin；`fit` 操作层 complete#1
- 铁律：不把结局组成分项进协变量（沿用 `.disease_exclusion_vars`）

---

## 文件与职责

| 路径 | 职责 |
|------|------|
| `.../incidence_38341157_PE_yes/`（新建） | 本轮唯一输出根：checkpoints / by_index / logs / Tables |
| `.../incidence_38341157_PE_yes/data/dabiao_pe_yes_apo.RData` | 诊断=1 子集 dabiao |
| `.../incidence_38341157_PE_yes/data/config_incidence_dual_batch.R` | 本轮 config（自现 config 复制改） |
| `.../incidence_38341157/data/*` | **只读参考**；不改动全队列已发表产物 |
| `docs/superpowers/plans/2026-11-02-eclampsia-apo-pe-yes-batch.md` | 本计划 |

---

## 预计人数与风险（写进 Methods 备忘）

- 全队列 n=3164 → PE=Yes **n=1124**（事件率约 **69.2%**，明显高于全队列 27%）
- 事件多、对照少（778 vs 346）→ 分位层内可能不稳定；闸门可能更多停在 binary
- `PE_Diagnosis` 不再可作协变量/亚组（常数）；原 Model2 含 PE 的解释不可直接对比全队列
- 连续 UHR 等量纲问题仍在 → 以分位表为主报

---

### Task 1: 建新输出根 + 诊断=1 dabiao

**Files:**
- Create: `/mnt/g/02block_result/27_eclampsia/incidence_38341157_PE_yes/data/`
- Create: `dabiao_pe_yes_apo.csv` / `.RData`
- Create: `data/_column_review_pe_yes.md`（短注：子集口径）

- [ ] **Step 1:** 建目录  
  `mkdir -p /mnt/g/02block_result/27_eclampsia/incidence_38341157_PE_yes/data`

- [ ] **Step 2:** 从现有 `dabiao_retro_apo.csv` 过滤 `PE_Diagnosis=="Yes"`，**丢掉常量列 `PE_Diagnosis`**（或保留但列入 exclude），另存 CSV + RData（`/tmp` 中转再 `cp`，避开 SMB 中文/权限坑）

- [ ] **Step 3:** 验收打印  
  `n==1124`；`Disease_Group` 计数 = 778 / 346；无 `PE_Diagnosis` 水平分裂

- [ ] **Step 4:** 写 `_column_review_pe_yes.md` 三行：子集定义、n、与全队列差异（PE 不再进模）

---

### Task 2: 复制并改 config（PE 子集专用）

**Files:**
- Create: `incidence_38341157_PE_yes/data/config_incidence_dual_batch.R`  
  （从 `incidence_38341157/data/config_incidence_dual_batch.R` 复制）

- [ ] **Step 1:** 改 `.batch_project_root` →  
  `"/mnt/g/02block_result/27_eclampsia/incidence_38341157_PE_yes"`

- [ ] **Step 2:** `rawdata_path` → `dabiao_pe_yes_apo.RData`（data / dual_db primary+secondary 三处对齐）

- [ ] **Step 3:** 项目名/协议标签加 `_PE_yes`；`feishu$enable=FALSE`

- [ ] **Step 4:** 从下列位置 **删除 `PE_Diagnosis`**：  
  `protect_vars`、`base_subgroup_vars`、`required_subgroup_vars`、  
  `univariate/multivariate required_predictors`、`subgroup_fallback` 里 PE 表达式

- [ ] **Step 5:** 亚组改为：`Age`, `Prenatal_care`, `Conception_method`（无 Gender）；`age_cutoff=35`

- [ ] **Step 6:** `index_vars`：先 `NULL` + `index_group="all"`，让 shared-only 筛可算名单；或沿用上轮 13 指标再加筛（推荐 **shared 后重锁**）

- [ ] **Step 7:** `parallel_workers = 2L`（五点半默认 2；若 CPU 空闲可改 4）

- [ ] **Step 8:** R `source(config)` 干跑无报错（可选）

---

### Task 3: 17:30 开跑（shared-only → workers）

**Commands（到点执行）：**

```bash
export MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final
CFG="/mnt/g/02block_result/27_eclampsia/incidence_38341157_PE_yes/data/config_incidence_dual_batch.R"
cd "$MEDICAL_BLOCKS_ROOT"

# 1) 共享层
Rscript run/incidence/run_incidence_dual_batch.R \
  --config "$CFG" --shared-only --db mimic \
  2>&1 | tee /tmp/eclampsia_pe_yes_shared.log

# 2) 按共享层输出把 index_vars 锁成「可算 ∩ 非 HDL/LDL」后（Agent 当场改 config），再：
nohup Rscript run/incidence/run_incidence_dual_batch.R \
  --config "$CFG" --workers 2 --db mimic \
  > /tmp/eclampsia_pe_yes_workers.log 2>&1 &
echo $! > /tmp/eclampsia_pe_yes_workers.pid
```

- [ ] **Step 1:** 17:30 跑 shared-only；确认可用指标列表（预期仍约 NLR/PLR/SII/…/UHR/BMI 一类）

- [ ] **Step 2:** 锁定 `index_vars`（排除 HDL/LDL）；启动 `--workers 2`

- [ ] **Step 3:** 巡检：`pgrep -af run_incidence_dual_batch`；`tail -f /tmp/eclampsia_pe_yes_workers.log`

- [ ] **Step 4:** 跑完核：`by_index/【success】*` 个数 = 锁定指标数；写 `Tables/Batch_summary_all_indices.csv`

---

### Task 4: 结果速览（跑完后）

- [ ] **Step 1:** 解析各指标 Table 2：最高档 Model2 OR/P、闸门分支（Q/T/B）

- [ ] **Step 2:** 与全队列结果对比一句（尤其 UHR：全队列曾最优；PE 子集可能改变效应量）

- [ ] **Step 3:** 聊天汇报：成功/失败数、推荐主指标、输出根绝对路径

---

## 明确不做（本轮）

- 不重跑前瞻队列
- 不覆盖 `incidence_38341157` 全队列 success
- 不在五点半前开 workers（除非用户改口）
- 本轮不强制 Nature QC / 中期（用户另点名再做）

---

## 回滚

- 删除或停用 `incidence_38341157_PE_yes/` 即可；全队列目录原样保留

---

## Agent 到点执行口令（复制）

> 到 **17:30** 按本计划 Task 1→2（若未预先做好）→ Task 3 开跑；跑完做 Task 4 汇报。
