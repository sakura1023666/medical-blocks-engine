# Attrition Flowchart Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增通用 `attrition_flowchart` block，使全部 baseline 套路在流水线末尾默认产出纳排 CSV + Figure 1 PDF（config 队列步骤 + 显式记账 + runner nrow 兜底）。

**Architecture:** `R/attrition_log.R` 提供记账/合并/绘图；`Blocks/00_attrition/01block_attrition_flowchart.R` 在末尾定稿；`run_pipeline` 自动追加 nrow 变化；`baseline_pipelines.json` 各 routine 主 pipeline 末尾挂块；专用 flowchart 遇通用 Figure 1 已存在则跳过。

**Tech Stack:** R ≥ 4.3, `cli`, `jsonlite`, 现有 `pipeline_runner.R` / `register_block` / `init_ctx` / `save_result` 约定。

**Spec:** `docs/superpowers/specs/2026-08-12-attrition-flowchart-block-design.md`

## Global Constraints

- 禁止无证据编造人数；算不出 N → warning 并跳过该步，不 `stop` 整条流水线。
- `attrition_flowchart` 写入 `baseline_pipelines.json` 后属合法基线块，无需 `extensions.json`。
- 通用块占用 Figure 1 标准文件名；专用 flowchart 默认 `skip_if_generic`。
- Git：默认**不** `git commit`，除非用户明确要求；计划中的 Commit 步骤可跳过。
- 完成后运行 `python3 scripts/update_blocks_catalog.py` 同步 `docs/Blocks_catalog.md`。

---

## File map

| 路径 | 职责 |
|------|------|
| Create: `R/attrition_log.R` | record / finalize / draw / resolve steps |
| Create: `Blocks/00_attrition/01block_attrition_flowchart.R` | 末尾出表出图 block |
| Create: `tests/test_attrition_log.R` | 合并优先级、去重、空 steps、无证据跳过 |
| Modify: `R/pipeline_runner.R` | 注册映射；source attrition_log；nrow 自动记账 |
| Modify: `configs/study_interface/baseline_pipelines.json` | 各 pipeline 末尾加 `attrition_flowchart` |
| Modify: `Blocks/02_data_clean/01block_data_clean.R` | 结束时 `attrition_record` |
| Modify: `Blocks/03_imputation/01block_imputation.R` | 结束时 `attrition_record` |
| Modify: `Blocks/03_imputation/02block_trim_index_extreme.R` | 修剪后 `attrition_record` |
| Modify: `R/incidence_dual_batch_runner.R` | 指标 NA/极端值过滤后记账 |
| Modify: `Blocks/55_.../17block_competing_flowchart.R` 等 | skip_if_generic |
| Modify: 主要 `configs/templates/config_*_batch.template.R` | 默认 `config$attrition` |
| Modify: RA 研究 config（验证） | 填 `steps`，去掉对手写 flowchart 脚本的依赖 |

---

### Task 1: `attrition_log.R` 核心 API（TDD）

**Files:**
- Create: `tests/test_attrition_log.R`
- Create: `R/attrition_log.R`

**Interfaces:**
- Produces:
  - `attrition_record(ctx, step_id, label, n, kind = "include", meta = list())` → ctx
  - `attrition_n_current(ctx)` → integer or NA
  - `attrition_resolve_config_steps(ctx, steps)` → list of rows with `step_id`,`label`,`n`,`source`
  - `attrition_finalize_rows(ctx, config)` → data.frame(`step`,`n`,`source`,`kind`)
  - `attrition_draw_pdf(rows, title, pdf_path, font_family = "Times New Roman")` → logical
  - `attrition_auto_append_nrow(ctx, block_id, n_before, n_after)` → ctx（仅当 n 变化且无同 block 显式记录）

- [ ] **Step 1: 写失败测试**

```r
# tests/test_attrition_log.R
root <- normalizePath(".")
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/attrition_log.R"))

ctx <- list(
  config = list(
    data = list(outcome_column = "Disease_Group", id_column = "ID"),
    project = list(database = "MIMIC", analysis_group = "ASCVD", reference_group = "Non_ASCVD"),
    attrition = list(enable = TRUE, auto_append = TRUE, outcome_breakdown = TRUE, steps = list())
  ),
  data = list(
    imputed = data.frame(
      ID = 1:10,
      Disease_Group = factor(c(rep("ASCVD", 3), rep("Non_ASCVD", 7)),
                             levels = c("Non_ASCVD", "ASCVD"))
    )
  ),
  results = list()
)

# record + dedupe by step_id
ctx <- attrition_record(ctx, "after_clean", "After data_clean", 12L)
ctx <- attrition_record(ctx, "after_clean", "After data_clean", 10L) # update
stopifnot(length(ctx$results$attrition$log) == 1L)
stopifnot(identical(as.integer(ctx$results$attrition$log[[1]]$n), 10L))

# empty steps → at least current N
rows <- attrition_finalize_rows(ctx, ctx$config)
stopifnot(nrow(rows) >= 1L)
stopifnot(any(rows$n == 10L))

# auto append only when nrow changes
ctx2 <- ctx
ctx2 <- attrition_auto_append_nrow(ctx2, "boxplot", 10L, 10L)
stopifnot(length(ctx2$results$attrition$log) == 1L)
ctx2 <- attrition_auto_append_nrow(ctx2, "boxplot", 10L, 8L)
stopifnot(any(vapply(ctx2$results$attrition$log, function(x) identical(x$step_id, "auto_boxplot"), logical(1))))

# missing evidence step skipped (source=id_file bad path)
ctx$config$attrition$steps <- list(
  list(id = "bad", label = "Missing file", source = "id_file",
       path = "/no/such/file.csv", id_col = "subject_id", join_on = "ID")
)
rows2 <- attrition_finalize_rows(ctx, ctx$config)
stopifnot(!any(rows2$step == "Missing file"))

# draw pdf smoke
td <- tempfile("attr_")
dir.create(td)
pdf_path <- file.path(td, "Figure 1. Inclusion exclusion flowchart.pdf")
ok <- attrition_draw_pdf(
  data.frame(step = c("Baseline", "Analytic"), n = c(100L, 80L), stringsAsFactors = FALSE),
  title = "Figure 1. test",
  pdf_path = pdf_path
)
stopifnot(isTRUE(ok), file.exists(pdf_path), file.info(pdf_path)$size > 0)

cat("OK attrition_log\n")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `Rscript --vanilla tests/test_attrition_log.R`  
Expected: FAIL（找不到 `R/attrition_log.R` 或函数未定义）

- [ ] **Step 3: 实现 `R/attrition_log.R`**

实现要点（完整写入该文件）：

```r
# R/attrition_log.R — 通用纳排记账 / 合并 / 绘图
`%||%` <- function(a, b) if (!is.null(a)) a else b

attrition_n_current <- function(ctx) {
  d <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.data.frame(d)) as.integer(nrow(d)) else NA_integer_
}

attrition_record <- function(ctx, step_id, label, n, kind = "include", meta = list()) {
  # ... ensure ctx$results$attrition$log named/unnamed list; upsert by step_id
  ctx
}

attrition_auto_append_nrow <- function(ctx, block_id, n_before, n_after) {
  # if auto_append FALSE or n_before==n_after or NA → return ctx
  # step_id = paste0("auto_", block_id); skip if explicit record already covers this block via meta$block
  # label = paste("After", block_id)
  ctx
}

attrition_resolve_config_steps <- function(ctx, steps) {
  # switch(source): rawdata | id_file | current | fixed
  # id_file: read.csv, optional filter via with(df, eval(parse(text=filter))),
  #   intersect IDs with baseline join_on and optional prior step ID set stored in env
  # on failure: cli::cli_alert_warning + skip
}

attrition_finalize_rows <- function(ctx, config) {
  # merge: config steps → explicit log → (autos already in log)
  # if empty: single row Analytic cohort from attrition_n_current
  # outcome_breakdown: annotate last label with case/control counts
  # return data.frame(step, n, source, kind)
}

attrition_draw_pdf <- function(rows, title, pdf_path, font_family = "Times New Roman") {
  # reuse style of survival_batch_draw_flowchart_pdf (vertical boxes + drop counts)
  # font fallback if family missing
}
```

- [ ] **Step 4: 再跑测试**

Run: `Rscript --vanilla tests/test_attrition_log.R`  
Expected: 打印 `OK attrition_log`

- [ ] **Step 5: Commit（仅当用户要求）**

```bash
git add R/attrition_log.R tests/test_attrition_log.R
# git commit only if user asked
```

---

### Task 2: Block `attrition_flowchart`

**Files:**
- Create: `Blocks/00_attrition/01block_attrition_flowchart.R`
- Modify: `R/pipeline_runner.R`（仅增加 `pipeline_block_sources` 映射一行；nrow 逻辑放 Task 3）

**Interfaces:**
- Consumes: Task 1 全部函数；`ctx$config$attrition`；`ctx$root_output_dir` / `config$project$output_dir`
- Produces: CSV + PDF；`ctx$results$attrition_flowchart`

- [ ] **Step 1: 写 block 文件头 + `block_attrition_flowchart`**

```r
###############################################################################
#  attrition_flowchart — 通用纳排表 + Figure 1 PDF（全套路默认末尾）
#
#  register_block: "attrition_flowchart"
#  典型位置: 任意 pipeline 最后一个 block
#
#  config$attrition = list(
#    enable = TRUE,
#    steps = list(),                 # 可选队列步骤
#    auto_append = TRUE,
#    outcome_breakdown = TRUE,
#    draw_pdf = TRUE,
#    csv_name = "Flowchart_attrition.csv",
#    figure_name = "Figure 1. Inclusion exclusion flowchart.pdf"
#  )
#
#  读: ctx$data$* , ctx$results$attrition$log , config$attrition
#  写: Tables/*.csv , Figures/Figure 1*.pdf , ctx$results$attrition_flowchart
###############################################################################

block_attrition_flowchart <- function(ctx, ...) {
  cfg <- ctx$config$attrition %||% list()
  if (!is.null(cfg$enable) && !isTRUE(cfg$enable)) return(ctx)
  if (!exists("attrition_finalize_rows", mode = "function")) {
    root <- ctx$project_root %||% getwd()
    al <- file.path(root, "R/attrition_log.R")
    if (file.exists(al)) source(al, local = FALSE)
  }
  rows <- attrition_finalize_rows(ctx, ctx$config)
  # resolve out dirs (prefer ctx$root_output_dir)
  # write csv; if draw_pdf draw; mirror if project$mirror_pub_outputs_to_root
  # db suffix: dual_db$current_db or project$database
  ctx$results$attrition_flowchart <- list(rows = rows, csv = csv_path, pdf = pdf_path)
  ctx
}

register_block("attrition_flowchart", block_attrition_flowchart,
               "Write inclusion/exclusion attrition table and Figure 1 PDF")
```

- [ ] **Step 2: 在 `pipeline_block_sources` 靠近 `data_clean` 处注册**

```r
attrition_flowchart = b("00_attrition/01block_attrition_flowchart.R"),
```

- [ ] **Step 3: 最小烟测**

```bash
Rscript --vanilla -e '
root<-"."; source("R/utils.R"); source("R/attrition_log.R"); source("R/pipeline_runner.R")
stopifnot("attrition_flowchart" %in% names(pipeline_block_sources(normalizePath(root))))
'
```

Expected: 无错误退出

---

### Task 3: `run_pipeline` source + nrow 自动兜底

**Files:**
- Modify: `R/pipeline_runner.R`（`run_pipeline` 开头 source；主循环 block 前后 nrow）

**Interfaces:**
- Consumes: `attrition_n_current`, `attrition_auto_append_nrow`
- Produces: 运行中填充 `ctx$results$attrition$log` 的 `auto_*` 行

- [ ] **Step 1: 在 `run_pipeline` 加载 gate 文件之后 source attrition_log**

```r
attr_log <- file.path(root, "R", "attrition_log.R")
if (file.exists(attr_log)) source(attr_log, local = FALSE)
```

- [ ] **Step 2: 在 `run_block` 调用前后插入 nrow 记账**

在现有 `ctx <- tryCatch(run_block(...))` 之前：

```r
n_before <- if (exists("attrition_n_current", mode = "function")) attrition_n_current(ctx) else NA_integer_
```

在成功返回后、checkpoint 保存前：

```r
if (exists("attrition_auto_append_nrow", mode = "function") &&
    !identical(block_name, "attrition_flowchart")) {
  n_after <- attrition_n_current(ctx)
  ctx <- attrition_auto_append_nrow(ctx, block_name, n_before, n_after)
}
```

- [ ] **Step 3: 用现有最小 pipeline 冒烟（可构造假 pipeline）**

```r
# 临时：仅 data_clean 不可行则用 mock ctx + 两个假 block 不强制；
# 至少确认 source 不报错：
Rscript --vanilla -e 'source("R/pipeline_runner.R"); cat("ok\n")'
```

---

### Task 4: 更新 `baseline_pipelines.json`

**Files:**
- Modify: `configs/study_interface/baseline_pipelines.json`
- Modify: `tests/test_pipeline_extension_guard.R`（可选追加：incidence regular 含 attrition_flowchart 且 guard OK）

- [ ] **Step 1: 对下列每个 pipeline 数组，若末尾尚无 `attrition_flowchart` 则 append**

覆盖 keys（以文件实际为准）：

- `incidence.pipeline_nhanes_batch`, `incidence.pipeline_regular_batch`
- `survival.pipeline_regular_batch`
- `competing.pipeline_unit`（shared 可选不加；unit 必加）
- `environment.pipeline_tail`（以及若存在完整主链则加）
- `trajectory.pipeline_unit_suffix`
- `ipw.pipeline_unit`
- `tst.pipeline_unit`
- `ml.pipeline_nhanes_batch`, `ml.pipeline_regular_primary_ml_batch`, `ml.pipeline_mimic_ml_batch`

脚本示例：

```python
# run once while implementing
import json
from pathlib import Path
p = Path("configs/study_interface/baseline_pipelines.json")
d = json.loads(p.read_text())
TARGET = {
  "incidence": ["pipeline_nhanes_batch", "pipeline_regular_batch"],
  "survival": ["pipeline_regular_batch"],
  "competing": ["pipeline_unit"],
  "environment": ["pipeline_tail"],
  "trajectory": ["pipeline_unit_suffix"],
  "ipw": ["pipeline_unit"],
  "tst": ["pipeline_unit"],
  "ml": ["pipeline_nhanes_batch", "pipeline_regular_primary_ml_batch", "pipeline_mimic_ml_batch"],
}
for routine, keys in TARGET.items():
  for k in keys:
    blocks = d[routine][k]
    if isinstance(blocks, dict):
      blocks = blocks["blocks"]
      holder = d[routine][k]
      if blocks[-1] != "attrition_flowchart":
        blocks.append("attrition_flowchart")
        holder["blocks"] = blocks
    else:
      if blocks[-1] != "attrition_flowchart":
        blocks.append("attrition_flowchart")
        d[routine][k] = blocks
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
```

- [ ] **Step 2: 验证 guard 对 incidence 仍 OK**

```bash
Rscript --vanilla -e '
root<-normalizePath(".")
source("R/utils.R"); source("R/pipeline_runner.R"); source("R/pipeline_extension_guard.R")
base<-jsonlite::fromJSON(file.path(root,"configs/study_interface/baseline_pipelines.json"), simplifyVector=FALSE)
pipes<-list(
  pipeline_regular_batch=list(blocks=unlist(base$incidence$pipeline_regular_batch)),
  pipeline_nhanes_batch=list(blocks=unlist(base$incidence$pipeline_nhanes_batch))
)
# baseline load returns bare arrays — guard as_chr handles both
pipeline_extension_guard_check("incidence", list(
  pipeline_regular_batch = unlist(base$incidence$pipeline_regular_batch),
  pipeline_nhanes_batch = unlist(base$incidence$pipeline_nhanes_batch)
), tempfile("st_"), root)
cat("OK baseline+attrition guard\n")
'
```

Expected: `OK baseline+attrition guard`

---

### Task 5: 上游显式记账（data_clean / imputation / trim）

**Files:**
- Modify: `Blocks/02_data_clean/01block_data_clean.R`（在 `ctx$data$cleaned <- data` 之后、`return` 前）
- Modify: `Blocks/03_imputation/01block_imputation.R`（写完 imputed 后、register 前的成功路径末尾）
- Modify: `Blocks/03_imputation/02block_trim_index_extreme.R`（删行后）

- [ ] **Step 1: data_clean**

```r
if (exists("attrition_record", mode = "function")) {
  ctx <- attrition_record(
    ctx, "after_data_clean", "After data cleaning",
    as.integer(nrow(data)), meta = list(block = "data_clean")
  )
}
```

- [ ] **Step 2: imputation**（在 `ctx$data$imputed` 赋值完成后）

```r
if (exists("attrition_record", mode = "function")) {
  n_imp <- attrition_n_current(ctx)
  ctx <- attrition_record(
    ctx, "after_imputation", "After imputation",
    n_imp, meta = list(block = "imputation")
  )
}
```

- [ ] **Step 3: trim_index_extreme**（实际删行后）

```r
if (exists("attrition_record", mode = "function")) {
  ctx <- attrition_record(
    ctx, "after_trim_index", "After trimming index extremes",
    as.integer(nrow(data)), meta = list(block = "trim_index_extreme")
  )
}
```

- [ ] **Step 4: 语法检查**

```bash
Rscript -e 'parse("Blocks/02_data_clean/01block_data_clean.R"); parse("Blocks/03_imputation/01block_imputation.R"); parse("Blocks/03_imputation/02block_trim_index_extreme.R"); cat("OK parse\n")'
```

---

### Task 6: Dual-batch 指标 NA/极端值记账

**Files:**
- Modify: `R/incidence_dual_batch_runner.R`（过滤 NA/trim 后约打印 `删 NA` 的位置）

- [ ] **Step 1: 在 per-index 过滤完成后调用**

定位已有日志：`删 NA {n_na} 行, 删极端值 {n_trim} 行 → 剩余 {n_after}`。在其后：

```r
if (exists("attrition_record", mode = "function") && exists("ctx", inherits = FALSE)) {
  ctx <- attrition_record(
    ctx,
    step_id = paste0("after_index_filter_", ix),
    label = sprintf("After excluding missing/extreme %s", ix),
    n = as.integer(n_after),
    meta = list(block = "index_filter", index = ix, n_na = n_na, n_trim = n_trim)
  )
}
```

若该处尚无 `ctx` 对象名，使用实际局部变量名（实现时以该函数签名为准，保持把更新后的 ctx 传回后续 pipeline）。

- [ ] **Step 2: survival dual batch 若有同类过滤，同样挂一点（搜索 `删 NA`）**；无则跳过并在 PR 说明。

---

### Task 7: 专用 flowchart `skip_if_generic`

**Files:**
- Modify: `Blocks/55_competing_risk_full/17block_competing_flowchart.R`
- Modify: `Blocks/69_ipw_diabetes_stroke_full/02block_ipw_flowchart.R`
- Modify: `Blocks/70_crm_nhanes_pub/02block_crm_nhanes_flowchart.R`

- [ ] **Step 1: 每个专用 block 开头加入**

```r
mode <- (ctx$config$attrition %||% list())$specialty_figure_mode %||% "skip_if_generic"
fig1_candidates <- c(
  file.path(ctx$root_output_dir %||% ".", "Figures",
            "Figure 1. Inclusion exclusion flowchart.pdf"),
  file.path(ctx$root_output_dir %||% ".", "Figures", "Figure 1. Flowchart.pdf")
)
if (identical(mode, "skip_if_generic") && any(file.exists(fig1_candidates))) {
  cli::cli_alert_info("通用 Figure 1 已存在，跳过专用 flowchart")
  return(ctx)
}
```

注意：若专用块**排在** `attrition_flowchart` **之前**，则通用图尚不存在，专用块仍会出图；baseline 更新后通用块在末尾，专用块在前 → 专用仍会画。为满足「通用占用 Figure 1」，实现二选一（本任务采用 B）：

- **B（推荐，写进代码）**：专用块若检测到将写的目标路径为 Figure 1，则改写为 `Figure 1b. <specialty> flowchart.pdf`；若 `skip_if_generic` 且 pipeline 含 `attrition_flowchart`，则直接 skip 专用出图（仍可写 counts CSV 到非 Figure1 名）。

```r
pipe_blocks <- ctx$pipeline$blocks %||% character(0)
if (identical(mode, "skip_if_generic") && "attrition_flowchart" %in% pipe_blocks) {
  cli::cli_alert_info("pipeline 含 attrition_flowchart，跳过专用 Figure 1")
  return(ctx)
}
```

若 `ctx$pipeline` 不存在，从 `ctx$config` / 调用方注入；必要时在 `run_block` 里设置 `ctx$current_pipeline_blocks <- blocks_full`（Task 3 一并加上）。

- [ ] **Step 2: Task 3 补充** `ctx$pipeline_blocks <- blocks_full` 在循环前赋值一次。

---

### Task 8: 模板默认 `config$attrition`

**Files:**
- Modify（至少）:
  - `configs/templates/config_incidence_single.template.R`
  - `configs/templates/config_incidence_dual_batch.template.R`
  - `configs/templates/config_incidence_nhanes_batch.template.R`
  - `configs/templates/config_survival_dual_batch.template.R`（若存在）
  - 其他常用 batch 模板：在 `config <- list(` 内增加一节即可

- [ ] **Step 1: 插入默认节**

```r
  attrition = list(
    enable = TRUE,
    title = NULL,
    db_label = NULL,
    steps = list(),
    outcome_breakdown = TRUE,
    auto_append = TRUE,
    draw_pdf = TRUE,
    csv_name = "Flowchart_attrition.csv",
    figure_name = "Figure 1. Inclusion exclusion flowchart.pdf",
    specialty_figure_mode = "skip_if_generic"
  ),
```

- [ ] **Step 2: build 脚本若生成 config，同步默认键**（如 `configs/study_interface/incidence_dual_batch_build.R`）

---

### Task 9: 目录同步 + RA 研究迁移验证

**Files:**
- Modify: `docs/Blocks_catalog.md` via script
- Modify: `/mnt/g/02block_result/19_Rheumatoid Arthritis/incidence_38341157/Data/config_incidence_mimic_batch.R`
- Optional keep: `run/rheumatoid_ascvd/draw_flowchart_ra_ascvd.R` 标记 deprecated

- [ ] **Step 1: 更新 catalog**

```bash
python3 scripts/update_blocks_catalog.py
python3 scripts/update_blocks_catalog.py --check
```

Expected: exit 0；文档出现 `attrition_flowchart`

- [ ] **Step 2: RA config 增加 steps**

```r
  attrition = list(
    enable = TRUE,
    db_label = "MIMIC",
    steps = list(
      list(id = "baseline", label = "MIMIC-IV ICU first-stay baseline", source = "rawdata"),
      # 注意：dabiao 已是 RA∩GC 队列时，rawdata nrow=399；
      # 若要用原始 65366 基线，另设 raw_baseline_path 或 fixed n + 原始 RData 路径键
      list(id = "analytic", label = "Analytic cohort with ASCVD outcome labeled",
           source = "current")
    ),
    outcome_breakdown = TRUE,
    auto_append = TRUE,
    draw_pdf = TRUE,
    specialty_figure_mode = "skip_if_generic"
  ),
```

**重要：** 当前 RA dabiao 已是筛选后 399 人。若要复现 65366→898→399 全链，steps 应指向**原始** baseline RData + 两个 CSV（`id_file`），而 `rawdata` 指向分析 dabiao 仅作 `current`。实现时在 RA config 使用：

```r
steps = list(
  list(id = "baseline", label = "MIMIC-IV ICU first-stay baseline",
       source = "fixed", n = 65366L, meta_note = "from D01_baseline_MIMIC_ICU_frist_0626"),
  list(id = "ra", label = "Rheumatoid arthritis (RA)",
       source = "id_file",
       path = file.path(.batch_data_root, "mimic/类风湿性关节炎.csv"),
       id_col = "subject_id", join_on = "ID",
       join_universe_path = file.path(.batch_data_root, "mimic/D01_baseline_MIMIC_ICU_frist_0626 (1).RData"),
       join_universe_obj = "baseline"),
  list(id = "ra_gc", label = "RA + glucocorticoid use (rxglucocorticoids=1)",
       source = "id_file",
       path = file.path(.batch_data_root, "mimic/糖皮质激素.csv"),
       id_col = "subject_id", filter = "!is.na(rxglucocorticoids) & as.integer(rxglucocorticoids)==1",
       intersect_with = "ra",
       join_universe_path = file.path(.batch_data_root, "mimic/D01_baseline_MIMIC_ICU_frist_0626 (1).RData"),
       join_universe_obj = "baseline"),
  list(id = "analytic", label = "Analytic cohort with ASCVD outcome labeled",
       source = "current")
)
```

Task 1 的 `id_file` 解析需支持可选 `join_universe_path` / `join_universe_obj`（与分析 `rawdata` 解耦）。若 Task 1 未做，本步补进 `attrition_resolve_config_steps`。

- [ ] **Step 3: 对单个指标冒烟（共享层已存在时可 --only-index NLR --from attrition 不可用则全跑 to 末尾）**

更稳妥：

```bash
export MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final
# 确保 pipeline_regular_batch 末尾含 attrition_flowchart 后：
Rscript run/incidence/run_incidence_dual_batch.R \
  --config "/mnt/g/02block_result/19_Rheumatoid Arthritis/incidence_38341157/Data/config_incidence_mimic_batch.R" \
  --db mimic --only-index NLR --no-skip
```

Expected:  
`by_index/【success】NLR/.../Figures/Figure 1. Inclusion exclusion flowchart.pdf` 存在且非占位；  
项目 `Tables/Flowchart_attrition*.csv` 含队列步骤。

- [ ] **Step 4: 验收清单对照 spec §9 逐条勾选**

---

## Spec coverage self-check

| Spec 要求 | Task |
|-----------|------|
| `R/attrition_log.R` API | Task 1 |
| Block + 注册 | Task 2 |
| runner nrow 兜底 | Task 3 |
| baseline 全套路末尾挂接 | Task 4 |
| data_clean/imputation/trim 记账 | Task 5 |
| 指标缺失剔除记账 | Task 6 |
| 专用 flowchart 并存/skip | Task 7 |
| 模板默认 config | Task 8 |
| catalog + RA 验证 | Task 9 |
| 无证据不编造 / enable=FALSE / 空 steps | Task 1 + Task 2 |
| Figure 1 文件名 | Task 2 |

## Placeholder scan

无 TBD；`join_universe_path` 已在 Task 9 明确为 Task 1 解析扩展。

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-12-attrition-flowchart-block.md`.

**两种执行方式：**

1. **Subagent-Driven（推荐）** — 每任务新开子 agent，任务间复习，迭代快  
2. **Inline Execution** — 本会话按 `executing-plans` 连续执行并设检查点  

选哪种？
