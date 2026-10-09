# 发表数字口径 est=2 / cutoff=3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将引擎发表数字默认改为 `est=2`、`cutoff=3`（P=3、desc=2、千分位开不变），使发病/预后/ML 等新跑表统一。

**Architecture:** 单一事实来源仍是 `R/utils.R` 的 `.pipeline_pub_digits()` + `pipeline_apply_pub_digits()`；改 options 默认与模板，并把中介路径图写死的 `d_est=3L` 改为读全局 `est`。已写死 `config$pub_digits$est=3` 的课题 config **不改**（尊重覆盖）。

**Tech Stack:** R、现有 `tests/*.R` stopifnot、cursor rule、config templates。

## Global Constraints

- Spec：`docs/superpowers/specs/2026-09-22-pub-digits-est2-cutoff3-design.md`
- 新默认：`est=2`、`p=3`、`desc=2`、`cutoff=3`、`int_big_mark=TRUE`
- 不回刷已落盘 SCI 表；不全仓清剿 `sprintf("%.3f")`
- 不修改已显式写 `pub_digits$est=3` 的课题 config（如 `configs/config_pa_mobility_cognitive.R`、`run/ml/build_aki_sosm_wpr_replication.R`）
- **禁止 git commit，除非用户明确要求提交**

## File map

| File | Role |
|------|------|
| `tests/test_pub_digits_defaults.R` | 新建：断言无 config 时默认 est/cutoff |
| `R/utils.R` | 改 `.pipeline_pub_digits` 默认与注释/兜底 |
| `.cursor/rules/pub_digits_consistency.mdc` | 铁律文案对齐 |
| `configs/templates/config_incidence_dual_batch.template.R` | 模板默认 |
| `configs/templates/config_survival_dual_batch.template.R` | 模板默认 |
| `configs/templates/config_pa_mobility_cognitive.template.R` | 模板默认 |
| `Blocks/20_mediation/00mediation_common.R` | `d_est` 默认读全局 est |
| `Blocks/20_mediation/01block_mediation_prognosis.R` | 同上 |

---

### Task 1: 默认位数失败测试

**Files:**
- Create: `tests/test_pub_digits_defaults.R`
- Modify: `R/utils.R`（Task 2）

**Interfaces:**
- Consumes: `.pipeline_pub_digits()`, `pub_format_est()`, `pipeline_apply_pub_digits()`
- Produces: 可执行断言：无覆盖时 `est==2`、`cutoff==3`；显式覆盖后仍可恢复为 3

- [ ] **Step 1: 写失败测试**

创建 `tests/test_pub_digits_defaults.R`：

```r
#!/usr/bin/env Rscript
# 发表数字默认：est=2 / p=3 / desc=2 / cutoff=3 / int_big_mark=TRUE
root <- normalizePath(file.path(getwd()), winslash = "/", mustWork = TRUE)
if (!file.exists(file.path(root, "R", "utils.R"))) {
  # 允许从 repo 根或 tests/ 启动
  cand <- normalizePath(file.path(dirname(root), ".."), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(getwd(), "..", "R", "utils.R"))) {
    root <- normalizePath(file.path(getwd(), ".."), winslash = "/", mustWork = TRUE)
  }
}
source(file.path(root, "R", "utils.R"), local = FALSE)

# 清掉可能被其它测试污染的 options
options(
  medical_blocks.pub_digits.est = NULL,
  medical_blocks.pub_digits.p = NULL,
  medical_blocks.pub_digits.desc = NULL,
  medical_blocks.pub_digits.cutoff = NULL,
  medical_blocks.pub_digits.int_big_mark = NULL
)

d <- .pipeline_pub_digits()
stopifnot(identical(as.integer(d$est), 2L))
stopifnot(identical(as.integer(d$p), 3L))
stopifnot(identical(as.integer(d$desc), 2L))
stopifnot(identical(as.integer(d$cutoff), 3L))
stopifnot(isTRUE(d$int_big_mark))

stopifnot(identical(pub_format_est(1.2345), "1.23"))
stopifnot(identical(pub_format_p(0.01234), "0.012"))
stopifnot(identical(pub_format_int(4399L), "4,399"))

# 课题覆盖仍生效
pipeline_apply_pub_digits(list(pub_digits = list(est = 3L, cutoff = 4L)))
d2 <- .pipeline_pub_digits()
stopifnot(identical(as.integer(d2$est), 3L))
stopifnot(identical(as.integer(d2$cutoff), 4L))
stopifnot(identical(pub_format_est(1.2345), "1.235"))

# 恢复默认，避免污染后续进程（同会话）
options(
  medical_blocks.pub_digits.est = NULL,
  medical_blocks.pub_digits.p = NULL,
  medical_blocks.pub_digits.desc = NULL,
  medical_blocks.pub_digits.cutoff = NULL,
  medical_blocks.pub_digits.int_big_mark = NULL
)

message("OK: test_pub_digits_defaults")
```

若仓库测试惯例用 `source("R/bootstrap.R")` 或固定 `PROJECT_ROOT`，按同目录其它 `tests/test_*.R` 头部改写 root 解析，但断言内容不变。

- [ ] **Step 2: 运行确认失败**

Run（在 repo 根）:

```bash
Rscript tests/test_pub_digits_defaults.R
```

Expected: FAIL — `stopifnot(identical(as.integer(d$est), 2L))` 失败（当前默认仍为 3），或 `pub_format_est` 得到 `"1.235"` 而非 `"1.23"`。

---

### Task 2: 改引擎默认与注释

**Files:**
- Modify: `R/utils.R`（约 L99–110、`pub_format_est` 兜底、约 L7066 注释）

**Interfaces:**
- Consumes: `getOption("medical_blocks.pub_digits.*")`
- Produces: 无覆盖时 `.pipeline_pub_digits()` 返回 `est=2L, cutoff=3L`

- [ ] **Step 1: 改 `.pipeline_pub_digits` 默认**

将：

```r
# 默认：效应量(OR/HR) 3 位；P 3 位（<0.001）；描述统计 2 位；切点 4 位
.pipeline_pub_digits <- function() {
  list(
    est = as.integer(getOption("medical_blocks.pub_digits.est", 3L))[1L],
    p = as.integer(getOption("medical_blocks.pub_digits.p", 3L))[1L],
    desc = as.integer(getOption("medical_blocks.pub_digits.desc", 2L))[1L],
    cutoff = as.integer(getOption("medical_blocks.pub_digits.cutoff", 4L))[1L],
```

改为：

```r
# 默认：效应量(OR/HR/RR+CI) 2 位；P 3 位（<0.001）；描述统计 2 位；切点 3 位
.pipeline_pub_digits <- function() {
  list(
    est = as.integer(getOption("medical_blocks.pub_digits.est", 2L))[1L],
    p = as.integer(getOption("medical_blocks.pub_digits.p", 3L))[1L],
    desc = as.integer(getOption("medical_blocks.pub_digits.desc", 2L))[1L],
    cutoff = as.integer(getOption("medical_blocks.pub_digits.cutoff", 3L))[1L],
```

- [ ] **Step 2: 对齐 `pub_format_est` 兜底**

在 `pub_format_est` 内将无效 dig 时的兜底：

```r
if (!is.finite(dig) || dig < 0L) dig <- 3L
```

改为：

```r
if (!is.finite(dig) || dig < 0L) dig <- 2L
```

（`pub_format_p` / `pub_format_p_cell` 兜底仍为 `3L`，勿改。）

- [ ] **Step 3: 更新文件内注释**

将约 L7066–7067：

```r
#   描述统计: 默认 2 位；效应量(OR/HR): 默认 3 位（用 pub_format_est）；P: 默认 3 位
```

改为：

```r
#   描述统计: 默认 2 位；效应量(OR/HR/RR+CI): 默认 2 位（用 pub_format_est）；P: 默认 3 位；切点: 默认 3 位
```

- [ ] **Step 4: 跑测试确认通过**

```bash
Rscript tests/test_pub_digits_defaults.R
```

Expected: 打印 `OK: test_pub_digits_defaults`，exit 0。

另跑（回归，勿改其显式 digits=3 断言）：

```bash
Rscript tests/test_result_review_guards.R
```

Expected: 仍 PASS（该文件用 `pub_format_est(1.51, 3L)` 显式三位）。

---

### Task 3: 铁律与模板默认

**Files:**
- Modify: `.cursor/rules/pub_digits_consistency.mdc`
- Modify: `configs/templates/config_incidence_dual_batch.template.R:65`
- Modify: `configs/templates/config_survival_dual_batch.template.R:42`
- Modify: `configs/templates/config_pa_mobility_cognitive.template.R:29`

**Interfaces:**
- Consumes: 无
- Produces: 新课题从模板拷贝时得到 `est=2, cutoff=3`

- [ ] **Step 1: 更新 cursor rule**

在 `.cursor/rules/pub_digits_consistency.mdc`：

1. 标题/正文凡「OR/HR/CI：`est = 3`」改为「`est = 2`」；「切点：`cutoff = 4`」改为「`cutoff = 3`」。
2. 示例改为：

```r
config$pub_digits <- list(est = 2L, p = 3L, desc = 2L, cutoff = 3L, int_big_mark = TRUE)
```

3. 检查清单：「Table 2 / 中介 / 单因素 OR(CI) 均为 3 位」→「均为 **2** 位」；「切点标签可用 4 位」→「切点默认 **3** 位」。
4. 反例：「单因素列 `fmt_num(OR)` 只留两位，主文 Table 2 却是三位」改为：「同一课题 OR 有的 2 位、有的 3 位（未统一走 `pub_format_est`）」。
5. frontmatter `description` 若仍写「OR/HR/P 默认 3 位」改为「OR/HR/CI 默认 2 位；P 默认 3 位」。

- [ ] **Step 2: 更新三份模板**

三处均改为：

```r
pub_digits = list(est = 2L, p = 3L, desc = 2L, cutoff = 3L, int_big_mark = TRUE),
```

（若原模板无 `int_big_mark`，一并补上，与铁律一致。）

- [ ] **Step 3: 确认不改课题覆盖 config**

不要修改：

- `configs/config_pa_mobility_cognitive.R`（仍 `est=3`）
- `run/ml/build_aki_sosm_wpr_replication.R`
- `tests/test_ml_reference_assoc_figures.R` 内显式 `pub_digits`（文献复刻夹具）

用 grep 确认模板已新、课题覆盖仍旧：

```bash
rg -n "pub_digits = list\(est" configs/templates configs/config_pa_mobility_cognitive.R
```

Expected: templates 为 `est = 2L`；`config_pa_mobility_cognitive.R` 仍为 `est = 3L`。

---

### Task 4: 中介路径图读全局 est

**Files:**
- Modify: `Blocks/20_mediation/00mediation_common.R`（约 L79–91）
- Modify: `Blocks/20_mediation/01block_mediation_prognosis.R`（约 L97 及调用处）

**Interfaces:**
- Consumes: `.pipeline_pub_digits()$est`
- Produces: 路径标签默认位数 = 当前全局 `est`（无覆盖时为 2）

- [ ] **Step 1: 改 common**

将：

```r
.path_lbl_p_below_ci <- function(est, p, lo, hi, d_est = 3L) {
```

改为：

```r
.path_lbl_p_below_ci <- function(est, p, lo, hi,
                                 d_est = as.integer(.pipeline_pub_digits()$est)[1L]) {
```

将调用：

```r
lbl_a <- .path_lbl_p_below_ci(coef_a, p_a, ci_a_lo, ci_a_hi, 3L)
lbl_b <- .path_lbl_p_below_ci(coef_b, p_b, ci_b_lo, ci_b_hi, 3L)
lbl_d <- .path_lbl_p_below_ci(effect_total, p_total, ci_tot_lo, ci_tot_hi, 3L)
```

改为省略末参或显式传 `d_est` 变量：

```r
.d_est <- as.integer(.pipeline_pub_digits()$est)[1L]
lbl_a <- .path_lbl_p_below_ci(coef_a, p_a, ci_a_lo, ci_a_hi, .d_est)
lbl_b <- .path_lbl_p_below_ci(coef_b, p_b, ci_b_lo, ci_b_hi, .d_est)
lbl_d <- .path_lbl_p_below_ci(effect_total, p_total, ci_tot_lo, ci_tot_hi, .d_est)
```

- [ ] **Step 2: 同样改 prognosis block**

在 `01block_mediation_prognosis.R` 对同名 `.path_lbl_p_below_ci` 与 `3L` 调用做相同替换。

- [ ] **Step 3: grep 残留**

```bash
rg -n "d_est\s*=\s*3L|\.path_lbl_p_below_ci\([^)]+3L\)" Blocks/20_mediation
```

Expected: 无生产代码仍写死 `3L` 作为路径效应量默认（注释除外）。

- [ ] **Step 4: 再跑 Task 1 测试**

```bash
Rscript tests/test_pub_digits_defaults.R
```

Expected: PASS。

（中介 block 无单独轻量单测时，不强制整链重跑；改动仅为默认参数来源。）

---

### Task 5: Spec 覆盖自检

**Files:** 无代码；核对清单

- [ ] **Step 1: 对照 spec 逐条打勾**

| Spec 要求 | Task |
|-----------|------|
| `.pipeline_pub_digits` est=2 / cutoff=3 | Task 2 |
| 铁律 mdc | Task 3 |
| 三模板 | Task 3 |
| 中介 d_est 读全局 | Task 4 |
| 不回刷旧表 / 不清剿 sprintf | 全期遵守 |
| 课题 est=3 覆盖保留 | Task 3 Step 3 |
| 验收测试 | Task 1–2 |

- [ ] **Step 2: 最终 grep**

```bash
rg -n "getOption\(\"medical_blocks.pub_digits.est\", 3L\)|getOption\(\"medical_blocks.pub_digits.cutoff\", 4L\)" R/utils.R
rg -n "est = 3L, p = 3L, desc = 2L, cutoff = 4L" configs/templates .cursor/rules/pub_digits_consistency.mdc
```

Expected: 两处均无匹配（引擎与模板/铁律已是新默认）。

---

## Spec coverage (plan self-review)

- est=2 / cutoff=3 / 千分位维持 → Task 1–2  
- 铁律 + 模板 → Task 3  
- 中介写死 d_est → Task 4  
- 不回刷、不清剿、尊重课题覆盖 → Global Constraints + Task 3 Step 3  
- 无 TBD / 无「类似 Task N」占位  

## Out of scope（勿做）

- 修改 `configs/config_pa_mobility_cognitive.R` 等已写死三位的课题  
- 外科修复子宫肌瘤 HHR 等已导出表  
- 全仓替换 `round(..., 3)` / `%.3f`  
- git commit（除非用户另行要求）
