# Osteo Yan2026 有调节中介复现 — Implementation Plan

> **For agentic workers:** 本会话按任务内联执行（用户已要求「实现计划并开工」）。步骤用 checkbox 跟踪。

**Goal:** 在 `Blocks/20_mediation/07–12` 落地 Yan2026 九步法，对 OA 数据跑 X(URX+WQS)→M(血检)→Y(Group)，含调节与有调节中介。

**Architecture:** 独立 config/run；数据 prep 注入 `ctx$data$cleaned`；中介用 `mediation::mediate`（boot + BCa）；调节/有调节中介用手写 GLM 交互 + bootstrap 条件间接效应；结果写到 `medition/yan2026_modmed_reproduce/`。

**Tech Stack:** R 4.5.1、`mediation`、`ggplot2`、`corrplot`；可选装 `openxlsx`。

## Global Constraints

- Rscript: `/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe`
- 不改既有 osteo 课题；新 block 仅加在 `Blocks/20_mediation/`
- crude、无 survey 权重；正式 sims=5000；冒烟可用环境变量/config `sims`
- 硬排除：`analysis_exclusion$disease_vars` 含 Diabetes/Group 等
- Spec: `docs/superpowers/specs/2026-08-12-osteo-yan2026-moderated-mediation-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `R/moderated_mediation_process.R` | PROCESS 式单次中介提取、调节交互检验、条件间接效应、简单斜率 |
| `Blocks/20_mediation/07block_modmed_data_prep.R` | 读 RData、合并 WQS（行序对齐）、编码 Y/Gender |
| `08block_modmed_spearman.R` | Spearman 表+热图 |
| `09block_modmed_mediation_batch.R` | 108 次中介 + 显著筛选 |
| `10block_modmed_moderation.R` | Age/BMI/Gender × 路径 a/b/c' |
| `11block_modmed_moderated_mediation.R` | 条件间接效应 |
| `12block_modmed_simple_slopes.R` | 简单斜率表 + Fig.6 类图 |
| `configs/config_osteo_yan2026_modmed.R` | 课题配置 |
| `run/environment/run_osteo_yan2026_modmed.R` | 入口 |
| `R/pipeline_runner.R` | 注册 6 个 block 路径 |

---

### Task 1: Helper + data_prep + pipeline 注册

**Files:**
- Create: `R/moderated_mediation_process.R`
- Create: `Blocks/20_mediation/07block_modmed_data_prep.R`
- Modify: `R/pipeline_runner.R`（在 `mediation_longitudinal` 附近追加 6 个 mapping；本 task 先加 prep，后续 task 补全）

- [ ] **Step 1:** 实现 `modmed_merge_wqs(merged, wqs_fit)`：断言 `wqs_fit$data` 与 merged 行序键一致后赋 `WQS`
- [ ] **Step 2:** 实现 `modmed_run_mediate(d, x, m, y, sims, seed)` → 一行 data.frame（ACME/ADE/total/prop + CI + p）
- [ ] **Step 3:** 实现 `modmed_moderation_tests` / `modmed_conditional_indirect` / `modmed_simple_slope_plot`
- [ ] **Step 4:** `modmed_data_prep` block：读 config 路径 → `ctx$data$cleaned`；写 `Gender_num`（Male=1）、`Group_bin`
- [ ] **Step 5:** 冒烟：Rscript 只跑 prep，检查 `WQS` 非 NA 数与 nrow

### Task 2: Spearman + mediation_batch

**Files:**
- Create: `08block_modmed_spearman.R`, `09block_modmed_mediation_batch.R`

- [ ] **Step 1:** Spearman：X∪M∪Y 相关矩阵；写 Tables/Figures
- [ ] **Step 2:** 双重循环 X×M；`sims` 从 config；断点 `checkpoints/med_batch_partial.rds`
- [ ] **Step 3:** 显著：ACME CI 不含 0 → `ctx$results$modmed_significant`
- [ ] **Step 4:** 冒烟 sims=20，1 个 X × 2 个 M

### Task 3: Moderation + moderated mediation + simple slopes

**Files:**
- Create: `10`–`12` blocks

- [ ] **Step 1:** 对显著对 × {Age,BMI,Gender} 测 a/b/c' 交互
- [ ] **Step 2:** 交互显著 → 条件间接效应（Mean±1SD 或 Gender 分层）
- [ ] **Step 3:** 简单斜率图 PDF

### Task 4: Config + run + full smoke + catalog

**Files:**
- Create: `configs/config_osteo_yan2026_modmed.R`, `run/environment/run_osteo_yan2026_modmed.R`
- Modify: `R/pipeline_runner.R` 全量注册
- Run: `scripts/update_blocks_catalog.py`

- [ ] **Step 1:** config 指向 medition 数据与输出；`sims` 默认 5000，可用 `MODMED_SIMS` 覆盖
- [ ] **Step 2:** run 入口 + smoke `MODMED_SIMS=50`
- [ ] **Step 3:** 更新 Blocks catalog

---

## Spec coverage

| Spec 项 | Task |
|---------|------|
| 9 步映射 | 2–3 |
| X=URX+WQS, Y=Group, M=血检 | 1–2 |
| crude / 无权重 / bootstrap | 1–2 |
| 硬排除 | 4 config |
| 不改旧项目 | 全局 |
| WQS 对齐校验 | 1 |
| catalog | 4 |
