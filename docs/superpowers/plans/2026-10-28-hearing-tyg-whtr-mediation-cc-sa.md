# Hearing TyG_WHtR 中介·完整病例·表图整理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or implement task-by-task. Spec: `docs/superpowers/specs/2026-10-28-hearing-tyg-whtr-mediation-cc-sa-design.md`.

**Goal:** 在 MI 主文不变下，为听力 TyG_WHtR NHANES ML 课题补中介、完整病例对照表、亚组 P 文档与交付整理。

**Architecture:** 课题 `config.R` 挂 `mediation_nhanes_weighted` 并插入 `pipeline_nhanes_batch`；`code/run.R --blocks` 从 checkpoint 定向重跑；完整病例用引擎敏感性/对照导出补表；finalize + prune + 中期。

**Tech Stack:** R Medical Blocks, survey/svyglm, mediation_nhanes_weighted, pub_figure_export, midterm NB004.

## Global Constraints

- 主文 MI m=5 + Rubin；完整病例仅对照/敏感性
- 中介默认实验室池 + skip_export_if_ns
- 无高频结局；不做全库 ML 重训
- 交付白名单五项

---

### Task 1: config + pipeline 插入中介

- [ ] `config.R`：`mediation_nhanes_weighted` enable；exposure=TyG_WHtR；mediators=NULL（自动筛）
- [ ] `pipeline_nhanes_batch$blocks` 在 `subgroup_incidence` 后插入 `mediation_nhanes_weighted`
- [ ] `incidence_batch$sensitivity_suite`：enable + complete_case=TRUE
- [ ] Methods outcome_definition 保留 PTA

### Task 2: 定向重跑中介

- [ ] `Rscript code/run.R --blocks mediation_nhanes_weighted --db nhanes`
- [ ] 检查门控日志；有则表+路径图进 index / summary_results

### Task 3: 完整病例对照表

- [ ] 从未插补 cleaned + 锁定 Model1/2 出加权 logistic 对照表（S 号顺延）
- [ ] Methods 分写主分析 MI vs 完整病例对照

### Task 4: 亚组 / NRI 文档整理

- [ ] 导出或同步亚组表；刷新 Fig5 image_information 全 P
- [ ] Methods 点名 NRI/IDI S12–S13

### Task 5: 收口

- [ ] finalize / 四目录 / prune / 中期 / pub QC
