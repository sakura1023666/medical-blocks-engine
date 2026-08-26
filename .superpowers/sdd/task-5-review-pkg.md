# Task 5 Review Package
# Task 5 Report: `threshold_logistic` 块

**Status**: DONE  
**Date**: 2026-08-26  
**Worker**: Task 5 subagent  
**Commits**: none（global constraints / 用户明确禁止）

---

## 1. 执行摘要

已按 TDD 实现发病侧 `threshold_logistic`：连续 index 分位数网格两段 logistic，`segmented` 精修 psi；导出阈值、阈值下/上每单位 OR 与 P、LRT；CSV 表 + PDF（平滑相对 OR 曲线 + 竖线）。`pub_figure$profile == "mimic_inc_prog_sle_aki"` 走文献版 theme（Task 6 getter 尚未存在时块内回退）。`pipeline_block_sources` 已注册；catalog AUTO 已同步。未 git commit。

TDD：先写 `tests/test_threshold_logistic.R`，Windows Rscript 首次失败为 `exists("block_threshold_logistic", mode = "function") is not TRUE`；实现 block + 注册后 PASS。

---

## 2. 交付物

| 项 | 路径 | 说明 |
|----|------|------|
| Block | `Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R` | 新建；`register_block("threshold_logistic", …)` |
| 注册 | `R/pipeline_runner.R` → `pipeline_block_sources` | `threshold_logistic = b("72_.../03block_threshold_logistic.R")`（仅追加一行，未改旧映射） |
| 测试 | `tests/test_threshold_logistic.R` | 假数据阈值/OR/CSV/PDF；非 incidence 跳过；lit profile；注册；真数据 Age 冒烟 |
| Catalog | `docs/Blocks_catalog.md` | `python3 scripts/update_blocks_catalog.py` exit 0；416 blocks；MANUAL §1–§3 未改 |

---

## 3. Block 行为

消费：`ctx$data$imputed`（空则 cleaned/raw）；`incidence$index_var` / `outcome_var`；协变量 `threshold_logistic$covariates` → Model2 → Model1。`study_type` 非 incidence 则跳过。

产出：

- 网格（默认 Q10–Q90，81 点；每段 `min_segment_n=20`）拟合 `y ~ pmin(x,τ) + pmax(x-τ,0) + covs`
- 若已装 `segmented`：以网格 τ（或 RCS `cutoff_value`）为初值精修
- `ctx$results$threshold_logistic`：threshold / or_below / or_above / p_below / p_above / p_lrt / method
- `Tables/Table_Threshold_logistic_<Index>.csv`（立即落盘）+ `export_sci_table` 入队
- `Figures/Figure_Threshold_<Index>.pdf`（经 `.pub_figure_filename` 后空格化，与引擎发表图命名一致）
- lit profile：`theme_classic` + Times + 阈值标注；否则 `theme_bw`

ggplot2 / segmented 已在 R-4.5.1 library，未新装包。

---

## 4. 测试摘要

命令：

```bash
cd /mnt/e/01block/01Block-new-Final
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" tests/test_threshold_logistic.R
```

| 阶段 | 结果 |
|------|------|
| RED | `Error: exists("block_threshold_logistic", mode = "function") is not TRUE` |
| GREEN | `OK test_threshold_logistic`；假数据 method=segmented threshold≈8.79；real-data smoke n=270 events=110 threshold=63（Age 作连续暴露） |

非 incidence 跳过无 CSV；`mimic_inc_prog_sle_aki` 同样落 PDF。

---

## 5. Catalog

- 脚本 exit OK；新 `register_block` id：`threshold_logistic`（416 blocks）
- AUTO 卡片用途行：`threshold_logistic — 发病侧连续 index 的 threshold / piecewise logistic 表+图`
- MANUAL §1/§2/§3 未改（套路 template 属 Task 7）

---

## 6. Concerns / 待后续确认

1. **假数据阈值未钉在 DGP hinge=5**：n=360 噪声下 segmented 落到 ~8.8；测试只要求有限阈值与两侧 OR>0。
2. **真数据冒烟用 Age 当暴露**：指标库尚未进流水线；Task 8 通跑才验收真实 index。
3. **PDF 文件名**：`.pub_figure_filename` 把 `Figure_Threshold_NLR.pdf` 变成 `Figure Threshold NLR.pdf`（去下划线），与 RCS 等发表图一致。
4. **Task 6 `is_pub_profile` 尚无**：块内字符串回退；Task 6 落地后自动走公共 getter。
5. **文献 Figure 3 版式**：当前为相对 OR 曲线 + 竖线 + 标注；更深面板留给 Task 6。
6. **export_sci_table 仅入队**：单测直接调 block 不 flush，xlsx 不一定落盘；CSV 已立即写出。
7. **未改旧课题 config**；未 git commit。

---

## 7. 自检清单

- [x] 失败测试先跑（`block_threshold_logistic` 未定义）
- [x] `register_block("threshold_logistic", …)` + `pipeline_block_sources` 一行
- [x] CSV + PDF；profile 分支不改默认 theme_bw
- [x] 测试 PASS（假数据 + 真数据冒烟）
- [x] catalog 脚本 OK；用途行非分隔线
- [x] 无 git commit
- [x] 本 report 已写入 `.superpowers/sdd/task-5-report.md`

00ip_common.R
01block_ip_cohort_sle_aki.R
02block_ip_stage2_cohort_28d.R
03block_threshold_logistic.R
418:    threshold_logistic            = b("72_incidence_prognosis_two_stage/03block_threshold_logistic.R"),
465 /mnt/e/01block/01Block-new-Final/Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R
# threshold_logistic — 发病侧连续 index 的 threshold / piecewise logistic 表+图
###############################################################################
#
#  register_block: "threshold_logistic"
#  典型流水线: … → rcs_incidence → threshold_logistic → subgroup_incidence
#
#  对连续暴露在分位数网格上拟合两段 logistic（优先 segmented 精修 psi），
#  输出阈值点、阈值下/上每单位 OR 与 P、LRT；图为平滑曲线 + 竖线阈值。
#  pub_figure$profile == "mimic_inc_prog_sle_aki" 时走文献版主题（Task 6 可再加深）。
#
#  require_data  = ctx$data$imputed %||% ctx$data$cleaned
#  require_study = project$study_type == "incidence"（非 incidence 则跳过）
#  协变量       = config$threshold_logistic$covariates → Model2Factors → Model1Factors
#
#  # ── 配置 config$threshold_logistic ────────────────────────────────────────
#  threshold_logistic = list(
#    index_var        = NULL,    # NULL → incidence$index_var / logistic$index_var
#    outcome_var      = NULL,    # NULL → incidence$outcome_var / data$outcome_column
#    covariates       = NULL,    # NULL → Model2Factors（空则 Model1）
#    q_lo             = 0.10,    # 网格下分位
#    q_hi             = 0.90,
#    n_grid           = 81L,
#    min_segment_n    = 20L,     # 每段最少人数
#    start_from_rcs   = TRUE,    # 若有 ctx$results$cutoff_value 则作为 segmented 初值
#    table_filename   = NULL,    # NULL → Table_Threshold_logistic_<Index>.csv
#    figure_filename  = NULL     # NULL → Figure_Threshold_<Index>.pdf
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  读: 连续 index、二元结局、锁定协变量
#  写: ctx$results$threshold_logistic（threshold / or_below / or_above / p_* / method）
#      Tables/Table_Threshold_logistic_*.csv（及 export_sci_table 入队）
#      Figures/Figure_Threshold_*.pdf
###############################################################################

.thl03_need_pkg <- function(pkg) {
  if (requireNamespace(pkg, quietly = TRUE)) return(TRUE)
  repos <- getOption("repos")
  if (is.null(repos) || identical(unname(repos), "@CRAN@") ||
      identical(repos, c(CRAN = "@CRAN@"))) {
    repos <- c(CRAN = "https://cloud.r-project.org")
  }
  tryCatch({
    utils::install.packages(pkg, repos = repos, quiet = TRUE)
    requireNamespace(pkg, quietly = TRUE)
  }, error = function(e) FALSE)
}

.thl03_parse_factors <- function(x) {
  if (is.null(x) || !length(x)) return(character(0))
  if (length(x) == 1L && is.character(x) && grepl("+", x, fixed = TRUE)) {
    return(trimws(unlist(strsplit(x, "\\s*\\+\\s*"))))
  }
  out <- trimws(as.character(x))
  out[nzchar(out)]
}

.thl03_is_lit_profile <- function(config) {
  if (exists("is_pub_profile", mode = "function")) {
    return(isTRUE(is_pub_profile(config, "mimic_inc_prog_sle_aki")))
  }
  p <- tryCatch(config$pub_figure$profile, error = function(e) NULL)
  identical(as.character(p %||% "")[1L], "mimic_inc_prog_sle_aki")
}

.thl03_wald_or <- function(fit, term) {
  sm <- tryCatch(summary(fit)$coefficients, error = function(e) NULL)
  empty <- list(or = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_, p = NA_real_)
  if (is.null(sm) || !nrow(sm)) return(empty)
  rn <- rownames(sm)
  hit <- which(rn == term | rn == paste0("`", term, "`"))[1L]
  if (!length(hit) || is.na(hit)) {
    hit <- grep(paste0("^", gsub("\\.", "\\\\.", term)), rn)[1L]
  }
  if (!length(hit) || is.na(hit)) return(empty)
  est <- as.numeric(sm[hit, "Estimate"])
  se <- as.numeric(sm[hit, "Std. Error"])
  pr_col <- grep("^Pr\\(", colnames(sm))[1L]
  pv <- if (length(pr_col) && !is.na(pr_col)) as.numeric(sm[hit, pr_col]) else NA_real_
  if (!is.finite(est) || !is.finite(se) || se < 0) return(empty)

---

# Task 5 Review — `threshold_logistic`

**Reviewer**: subagent (read-only)  
**Date**: 2026-08-26  
**Scope**: brief `task-5-brief.md` + constraints（旧课题不动 / block 注册）

## Verdict

| Gate | Result |
|------|--------|
| **Spec** | ✅ |
| **Quality** | **Approved** |

## Verification

| Check | Result | Evidence |
|-------|--------|----------|
| Block 新建 | ✅ | `Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R` |
| `register_block` | ✅ | L464–465；catalog AUTO 卡片 |
| `pipeline_block_sources` | ✅ | `R/pipeline_runner.R:418` 仅追加一行 |
| 消费 / 产出 | ✅ | 连续暴露 + Model2/1 协变量；CSV + PDF |
| 阈值搜索 | ✅ | 分位网格 + `segmented`；RCS `cutoff_value` 初值 |
| TDD / 测试 | ✅ | 复核 Rscript PASS（τ≈8.79 / 真数据 τ=63） |
| 旧课题未改 | ✅ | `configs/` 无引用；无 pipeline 挂载 |

## Critical

无。

## Important

1. Brief Step 2 流水线单指标冒烟 — Task 8 通跑验收；当前 Age 代理暴露。
2. 假数据阈值未锚定 DGP hinge=5 — 测试只检有限 τ 与 OR>0。
3. 文献 Figure 3 版式 — lit profile 基础版；Task 6 加深。
4. `export_sci_table` 单测不 flush — xlsx 仅入队。

## Reviewer test log (2026-08-26)

```
OK test_threshold_logistic
real-data smoke: n=270 events=110 threshold=63
method=segmented (fake data threshold≈8.793)
```
