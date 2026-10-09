# NHANES 纳排图调查权重完整记账 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让后续 NHANES 纳排图自动记录调查权重筛选，并确保最终分叉人数与加权 Table 1 分析集一致。

**Architecture:** 在 `obj` block 成功构建基础调查设计后写入一条标准纳排日志；在纳排分叉解析器中优先使用调查设计的变量数据。保持 `ctx$data$imputed` 不变，因此不会改变任何下游模型的数据对象语义。

**Tech Stack:** R、survey、现有 attrition log 与基础 R 回归测试。

## Global Constraints

- 不重跑、不修改当前 AIP_WHtR 结果。
- 仅在有效调查权重确实减少人数时增加纳排步骤。
- 无 `nhanes_design` 的普通项目行为保持不变。
- 所有生产代码修改必须先由失败测试复现。

---

### Task 1: 调查权重分析集纳排日志

**Files:**
- Modify: `tests/test_attrition_log.R`
- Modify: `Blocks/12_obj/01block_obj.R:276-281`

**Interfaces:**
- Consumes: `attrition_record(ctx, step_id, label, n, kind, meta)`
- Produces: `ctx$results$attrition$log` 中的 `after_survey_weight` 条目

- [ ] **Step 1: 写失败测试**

在 `tests/test_attrition_log.R` 构造 `imputed` 10 人、有效设计 6 人的上下文，并断言调用新的辅助函数后：

```r
ctx_w <- attrition_record_survey_weight_step(ctx_w, design_n = 6L)
entry <- ctx_w$results$attrition$log[[
  which(vapply(ctx_w$results$attrition$log,
               function(x) identical(x$step_id, "after_survey_weight"),
               logical(1)))[1L]
]]
stopifnot(identical(entry$n, 6L))
stopifnot(identical(entry$meta$exclude_label,
                    "Missing or non-positive survey weights"))
```

- [ ] **Step 2: 运行测试确认失败**

Run: `Rscript tests/test_attrition_log.R`

Expected: FAIL，提示 `attrition_record_survey_weight_step` 不存在。

- [ ] **Step 3: 最小实现**

在 `R/attrition_log.R` 增加：

```r
attrition_record_survey_weight_step <- function(ctx, design_n) {
  n_before <- attrition_n_current(ctx)
  design_n <- as.integer(design_n)[1L]
  if (!is.finite(n_before) || !is.finite(design_n) || design_n >= n_before) {
    return(ctx)
  }
  attrition_record(
    ctx, "after_survey_weight", "Eligible survey-weighted cohort",
    design_n,
    meta = list(
      block = "obj",
      source = "survey_design",
      exclude_label = "Missing or non-positive survey weights"
    )
  )
}
```

在 `Blocks/12_obj/01block_obj.R` 的 `design_base` 成功分支调用：

```r
if (exists("attrition_record_survey_weight_step", mode = "function")) {
  ctx <- attrition_record_survey_weight_step(
    ctx, nrow(design_base$variables)
  )
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `Rscript tests/test_attrition_log.R`

Expected: PASS，末行输出 `OK attrition_log`。

### Task 2: 病例/对照分叉与调查设计同源

**Files:**
- Modify: `tests/test_attrition_log.R`
- Modify: `R/attrition_log.R:285-291`

**Interfaces:**
- Consumes: `ctx$results$nhanes_design$variables`
- Produces: `attrition_resolve_outcome_fork(ctx, config)` 返回同一调查设计分析集的病例/对照人数

- [ ] **Step 1: 写失败测试**

构造全数据 10 人（病例 4、对照 6）和调查设计变量 6 人（病例 2、对照 4），断言：

```r
fork_w <- attrition_resolve_outcome_fork(ctx_w, ctx_w$config)
stopifnot(identical(fork_w$left_n, 2L))
stopifnot(identical(fork_w$right_n, 4L))
stopifnot(fork_w$left_n + fork_w$right_n == 6L)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `Rscript tests/test_attrition_log.R`

Expected: FAIL，当前实现返回全数据的 4/6。

- [ ] **Step 3: 最小实现**

将 `attrition_resolve_outcome_fork()` 的数据源改为：

```r
design_vars <- tryCatch(
  (ctx$results$nhanes_design %||% list())$variables,
  error = function(e) NULL
)
d <- if (is.data.frame(design_vars) && nrow(design_vars)) {
  design_vars
} else {
  ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
}
```

- [ ] **Step 4: 运行回归测试**

Run:

```bash
Rscript tests/test_attrition_log.R
Rscript tests/test_incidence_dual_figure1_from_attrition.R
```

Expected: 两个测试均以 `OK` 结束。

### Task 3: 静态与语法验证

**Files:**
- Verify: `R/attrition_log.R`
- Verify: `Blocks/12_obj/01block_obj.R`
- Verify: `tests/test_attrition_log.R`

**Interfaces:**
- Consumes: Task 1–2 修改
- Produces: 可供后续所有 NHANES 项目使用的公共行为

- [ ] **Step 1: 解析修改文件**

Run:

```bash
Rscript -e 'parse("R/attrition_log.R"); parse("Blocks/12_obj/01block_obj.R"); parse("tests/test_attrition_log.R")'
```

Expected: exit code 0。

- [ ] **Step 2: 检查 IDE 诊断**

对三个修改文件运行 linter，Expected: 无新增错误。

- [ ] **Step 3: 确认当前结果未改变**

Run:

```bash
stat "/mnt/g/02block_result/07_Diabetic retinopathy/incidence_38341157/by_index(all)/【success】AIP_WHtR/Figures/pdf/Figure 1. Flowchart.pdf"
```

Expected: 文件修改时间未因本次公共引擎修复发生变化。
