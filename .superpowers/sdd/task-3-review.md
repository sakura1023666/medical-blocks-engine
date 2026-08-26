# Task 3 Review — `ip_cohort_sle_aki` 胶水块 + 注册

**Reviewer**: subagent (read-only)  
**Date**: 2026-08-26  
**Scope**: brief `task-3-brief.md` + constraints `sle-aki-global-constraints.md`（尤其「禁止改旧课题行为」）

## Verdict

| Gate | Result |
|------|--------|
| **Spec** | ✅ |
| **Quality** | **Approved** |

## Verification

| Check | Result | Evidence |
|-------|--------|----------|
| 新 block + `register_block` | ✅ | `Blocks/72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R` |
| `pipeline_block_sources` 一行 | ✅ | `R/pipeline_runner.R:416` 仅追加；未改既有键 |
| 假数据 10∩5→5 + 纳排列 | ✅ | `tests/test_ip_cohort_sle_aki.R`；产出 `ip_attrition_steps` 含 `step/n_in/n_out/n_excluded/reason` |
| 结局列 | ✅ | `Acute_Renal_Failure`（已有则保留）+ `Disease` 0/1 |
| `aki_window_note` | ✅ | 写入 `ctx$results$ip_aki_window_note`；空则回填 `config$ip_two_stage$aki_window_note` |
| TDD / 真数据冒烟 | ✅（依报告） | RED 函数未定义 → GREEN 271→270、AKI=110 |
| **data_clean 默认路径未改** | ✅ | 见下节；**不**标 Important |
| 未改旧课题 config | ✅ | `configs/` 无 `ip_two_stage` / `ip_cohort_prepared` |
| 无 git commit | ✅ | 符合 global constraints |
| Catalog AUTO | ✅ | `ip_cohort_sle_aki` 卡片 + id_list；MANUAL 未改 |

## data_clean 闸门（重点）

`Blocks/02_data_clean/01block_data_clean.R:46-50` 在既有 `environment_dkd_prepared` 之后插入：

```r
} else if (isTRUE(ctx$results$ip_cohort_prepared %||% FALSE) && !is.null(ctx$data$raw)) {
  data <- ctx$data$raw
```

- 旗标默认 `FALSE`；仅本块 `ctx$results$ip_cohort_prepared <- TRUE` 时进入。
- 旧课题不跑 `ip_cohort_sle_aki` → 仍走 `mapped` / `rawdata_path` 加载，**默认路径未变**。
- 模式与 `environment_dkd_prepared` 相同；brief 未列此文件，但对 spec Stage0（本块在 `data_clean` 之前）是必要 opt-in，否则会 reload 全库 65366。

**不构成 Important（默认路径未改）。**

## Critical

无。

## Important

无（阻塞项无；默认路径未改故不升 Important）。

非阻塞备注（勿挡 Task 4）：

1. **测试未覆盖 data_clean 闸门** — `tests/test_ip_cohort_sle_aki.R` 未断言 flag-off 仍 load 文件、flag-on 吃 `ctx$data$raw`。建议 Task 7 前补一条回归。
2. **`ip_attrition_steps` 尚未接入 `attrition_finalize_rows`** — Figure 1 仍读 `config$attrition$steps`；接线属 Task 7。
3. **Age=NA 剔除 1 人（271→270）** — 与 brief 伪代码一致；dabiao=271 时交叉核对会差 1（report 已记）。

## Strengths

- ID 统一转字符再交集，覆盖 numeric/character 漏并。
- 已有 `Acute_Renal_Failure` 不覆盖；ARF.csv 仅缺列时派生。
- 假数据覆盖年龄、既有 ARF 列、ID 类型；真数据人数与 Task 1 对齐。
- 共享引擎改动仅 opt-in 一枝，旧课题 config 未动。
