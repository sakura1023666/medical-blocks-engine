# Pub Figure On-Plot Annotations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让所有经 `export_pub_figures` 写出的 `image_information/*.md` 自动包含图上可见关键标注（RCS 的 P-overall / P-non-linear / cutoff、KM Log-rank P、Forest 亚组效应与交互 P 等），并升级全局 Cursor 规则。

**Architecture:** 各图 block 出图时把图上数字写入 `ctx$results` → `pub_figure_harvest_findings` 从 checkpoint/CSV 收取 → `.pub_figure_detailed_body` 在「图面说明」输出固定段「图上标注」；缺证据写「未收获」，禁止编造。

**Tech Stack:** R（现有 `R/pub_figure_export.R`、Blocks RCS/KM）、`tests/test_pub_figure_export.R`（stopifnot 风格）、Cursor rule `.mdc`

**Spec:** `docs/superpowers/specs/2026-08-26-pub-figure-onplot-annotations-design.md`

## Global Constraints

- 数字只来自可收获产物；禁止 OCR、禁止编造
- md 结构仅 `# Figure …` + `## 图面说明` + `## 分析上下文`；禁止 `## 标识` / `## 技术`
- 「图上标注」格式尽量与图面一致（`P-overall = 0.001` / `< 0.001`）
- 本轮只做 Flowchart / RCS / KM / Forest / ROC / maxstat；不批量补刷旧课题
- 不改四目录布局与拼图逻辑
- 提交仅在用户明确要求时执行（计划中的 Commit 步骤默认跳过，除非用户说 commit）

---

## File map

| 文件 | 职责 |
|------|------|
| `R/pub_figure_export.R` | P 值格式化 helper；harvest 增 `rcs`/`km`/`forest`；detailed_body 写「图上标注」 |
| `Blocks/15_rcs/01block_rcs_prognosis.R` | 写 `rcs_prognosis_panel_stats` |
| `Blocks/15_rcs/02block_rcs_incidence.R` | 写 `rcs_incidence_panel_stats` |
| `Blocks/15_rcs/03block_rcs_nhanes.R` | 对齐 panel_stats（或等价键供 harvest） |
| `Blocks/15_rcs/04block_rcs_iptw_weighted.R` | 同上 |
| `Blocks/27_KM/01block_km_binary.R` | `km_binary` 增 `logrank_p` |
| `Blocks/27_KM/02block_km_strata.R` | `km_strata` 增每图 / 汇总 `logrank_p` |
| `.cursor/rules/pub_figure_image_information.mdc` | 图面标注必录铁律 |
| `tests/test_pub_figure_export.R` | 扩展：图上标注段、未收获、RCS/KM/Forest fixture |
| `tests/test_pub_figure_onplot_annotations.R` | 新建：panel_stats 抽取与 annotation 行格式（纯函数级） |

---

### Task 1: P 值格式化 + RCS/KM annotation 行 helper（TDD）

**Files:**
- Create: `tests/test_pub_figure_onplot_annotations.R`
- Modify: `R/pub_figure_export.R`（在 `pub_figure_harvest_findings` 之前新增 internal helpers）

**Interfaces:**
- Produces:
  - `.pub_figure_fmt_p_label(label, pv)` → character，如 `"P-overall = 0.001"` / `"P-overall < 0.001"` / `"P-overall = NA"`
  - `.pub_figure_rcs_annotation_lines(rcs_findings)` → character vector of markdown bullet lines
  - `.pub_figure_km_annotation_lines(km_findings)` → character vector
  - `.pub_figure_forest_annotation_lines(forest_findings)` → character vector

- [ ] **Step 1: Write the failing test**

```r
# tests/test_pub_figure_onplot_annotations.R
root <- normalizePath(getwd())
if (!file.exists(file.path(root, "R/utils.R"))) {
  cand <- normalizePath(file.path(".."), winslash = "/")
  if (file.exists(file.path(cand, "R/utils.R"))) root <- cand
}
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/pub_figure_export.R"), local = FALSE)

stopifnot(exists(".pub_figure_fmt_p_label", mode = "function"))
stopifnot(identical(.pub_figure_fmt_p_label("P-overall", 0.001), "P-overall = 0.001"))
stopifnot(identical(.pub_figure_fmt_p_label("P-overall", 0.0004), "P-overall < 0.001"))
stopifnot(identical(.pub_figure_fmt_p_label("P-non-linear", NA_real_), "P-non-linear = NA"))

rcs_f <- list(list(
  db = "MIMIC",
  panels = list(
    list(name = "Model2", p_overall = 0.001, p_nonlinear = 0.116, cutoffs = c(0.52))
  )
))
lines <- .pub_figure_rcs_annotation_lines(rcs_f)
stopifnot(any(grepl("P-overall = 0.001", lines)))
stopifnot(any(grepl("P-non-linear = 0.116", lines)))
stopifnot(any(grepl("0\\.52|cutoff", lines, ignore.case = TRUE)))

km_f <- list(list(db = "eICU", logrank_p = 0.023, cutoff = 1.25))
km_lines <- .pub_figure_km_annotation_lines(km_f)
stopifnot(any(grepl("Log-rank", km_lines)), any(grepl("0\\.023", km_lines)))
stopifnot(any(grepl("1\\.25|cutoff", km_lines, ignore.case = TRUE)))

forest_f <- list(list(
  db = "eICU",
  rows = data.frame(
    Variable = c("Overall", "Age < 65", "Age ≥ 65"),
    `Point Estimate` = c(1.20, 1.10, 1.35),
    Lower = c(1.01, 0.90, 1.05),
    Upper = c(1.42, 1.35, 1.74),
    `P for interaction` = c(NA, 0.04, NA),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
))
fo_lines <- .pub_figure_forest_annotation_lines(forest_f)
stopifnot(any(grepl("Overall", fo_lines)), any(grepl("1\\.20", fo_lines)))
stopifnot(any(grepl("interaction|交互", fo_lines, ignore.case = TRUE)))

cat("test_pub_figure_onplot_annotations: OK\n")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript tests/test_pub_figure_onplot_annotations.R`  
Expected: FAIL（函数不存在）

- [ ] **Step 3: Implement helpers in `R/pub_figure_export.R`**

在文件靠前（`pub_figure_harvest_findings` 之前）加入：

```r
.pub_figure_fmt_p_label <- function(label, pv) {
  label <- as.character(label %||% "P")[1L]
  pv <- suppressWarnings(as.numeric(pv)[1L])
  if (!is.finite(pv)) return(paste0(label, " = NA"))
  if (pv < 0.001) return(paste0(label, " < 0.001"))
  paste0(label, " = ", formatC(pv, digits = 3, format = "f"))
}

.pub_figure_rcs_annotation_lines <- function(rcs_findings) {
  if (!length(rcs_findings)) return(character(0))
  out <- character(0)
  for (item in rcs_findings) {
    db <- as.character(item$db %||% "")[1L]
    for (pan in item$panels %||% list()) {
      nm <- as.character(pan$name %||% "Model2")[1L]
      bits <- c(
        .pub_figure_fmt_p_label("P-overall", pan$p_overall),
        .pub_figure_fmt_p_label("P-non-linear", pan$p_nonlinear)
      )
      cuts <- suppressWarnings(as.numeric(pan$cutoffs %||% numeric(0)))
      cuts <- cuts[is.finite(cuts)]
      if (length(cuts)) {
        bits <- c(bits, paste0("cutoff = ", paste(signif(cuts, 4), collapse = "、")))
      }
      who <- if (nzchar(db)) paste0(db, " ", nm) else nm
      out <- c(out, sprintf("- %s：%s", who, paste(bits, collapse = "；")))
    }
  }
  out
}

.pub_figure_km_annotation_lines <- function(km_findings) {
  if (!length(km_findings)) return(character(0))
  out <- character(0)
  for (item in km_findings) {
    db <- as.character(item$db %||% "库")[1L]
    strata <- as.character(item$strata %||% "")[1L]
    who <- if (nzchar(strata)) paste0(db, " ", strata) else db
    bits <- character(0)
    if (!is.null(item$logrank_p)) {
      bits <- c(bits, .pub_figure_fmt_p_label("Log-rank P", item$logrank_p))
    }
    cv <- suppressWarnings(as.numeric(item$cutoff %||% NA_real_)[1L])
    if (is.finite(cv)) bits <- c(bits, sprintf("cutoff = %s", signif(cv, 4)))
    if (length(bits)) out <- c(out, sprintf("- %s：%s", who, paste(bits, collapse = "；")))
  }
  out
}

.pub_figure_forest_annotation_lines <- function(forest_findings) {
  if (!length(forest_findings)) return(character(0))
  out <- character(0)
  for (item in forest_findings) {
    db <- as.character(item$db %||% "")[1L]
    if (nzchar(db)) out <- c(out, paste0("#### ", db), "")
    df <- item$rows
    if (!is.data.frame(df) || !nrow(df)) {
      out <- c(out, "- 未收获：subgroup 表为空", "")
      next
    }
    var_col <- intersect(c("Variable", "Subgroup", "variable"), names(df))[1L]
    est_col <- intersect(c("Point Estimate", "HR", "OR"), names(df))[1L]
    lo_col <- intersect(c("Lower", "lower", "CI_low"), names(df))[1L]
    hi_col <- intersect(c("Upper", "upper", "CI_high"), names(df))[1L]
    pint_col <- grep("interaction", names(df), ignore.case = TRUE)[1L]
    if (!length(var_col) || is.na(var_col) || !nzchar(var_col)) {
      out <- c(out, "- 未收获：subgroup 缺 Variable 列", "")
      next
    }
    for (i in seq_len(nrow(df))) {
      v <- as.character(df[[var_col]][i])
      if (!nzchar(v) || grepl("^-+$", v)) next
      est <- if (!is.na(est_col)) suppressWarnings(as.numeric(df[[est_col]][i])) else NA_real_
      lo <- if (!is.na(lo_col)) suppressWarnings(as.numeric(df[[lo_col]][i])) else NA_real_
      hi <- if (!is.na(hi_col)) suppressWarnings(as.numeric(df[[hi_col]][i])) else NA_real_
      bits <- character(0)
      if (is.finite(est)) {
        if (is.finite(lo) && is.finite(hi)) {
          bits <- c(bits, sprintf("%s (95%%CI %s–%s)", signif(est, 4), signif(lo, 4), signif(hi, 4)))
        } else {
          bits <- c(bits, as.character(signif(est, 4)))
        }
      }
      if (length(pint_col) && is.finite(pint_col)) {
        pv <- suppressWarnings(as.numeric(df[[pint_col]][i]))
        if (is.finite(pv)) bits <- c(bits, .pub_figure_fmt_p_label("P for interaction", pv))
      }
      if (length(bits)) out <- c(out, sprintf("- %s：%s", v, paste(bits, collapse = "；")))
    }
    out <- c(out, "")
  }
  out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript tests/test_pub_figure_onplot_annotations.R`  
Expected: `test_pub_figure_onplot_annotations: OK`

- [ ] **Step 5: Commit（仅当用户要求）**

```bash
git add R/pub_figure_export.R tests/test_pub_figure_onplot_annotations.R
git commit -m "$(cat <<'EOF'
feat(pub-figure): add on-plot annotation format helpers

EOF
)"
```

---

### Task 2: detailed_body 强制输出「图上标注」段（TDD）

**Files:**
- Modify: `R/pub_figure_export.R` → `.pub_figure_detailed_body`
- Modify: `tests/test_pub_figure_export.R`

**Interfaces:**
- Consumes: `.pub_figure_rcs_annotation_lines` / `_km_` / `_forest_`；`meta$findings$rcs|km|forest`
- Produces: md 正文含字面量 `图上标注`

- [ ] **Step 1: Extend failing assertions in `tests/test_pub_figure_export.R`**

在现有 Flowchart 测试后追加：

```r
# RCS：注入 findings$rcs 后必须出现「图上标注」与 P-overall
meta_rcs <- meta
meta_rcs$findings <- list(
  rcs = list(list(
    db = "MIMIC",
    panels = list(list(
      name = "Model2", p_overall = 0.001, p_nonlinear = 0.116, cutoffs = 0.52
    ))
  ))
)
rcs_md <- tempfile("rcs_md_")
pub_figure_write_image_md(rcs_md, "Figure 2. RCS plot", meta = meta_rcs, raster_ok = TRUE)
rcs_txt <- paste(readLines(rcs_md, warn = FALSE), collapse = "\n")
stopifnot(grepl("图上标注", rcs_txt))
stopifnot(grepl("P-overall = 0.001", rcs_txt))
stopifnot(grepl("P-non-linear = 0.116", rcs_txt))
stopifnot(grepl("0\\.52", rcs_txt))
unlink(rcs_md)

# RCS：无 findings$rcs → 明示未收获
meta_rcs_empty <- meta
meta_rcs_empty$findings <- list()
rcs_md2 <- tempfile("rcs_md2_")
pub_figure_write_image_md(rcs_md2, "Figure 2. RCS plot", meta = meta_rcs_empty, raster_ok = TRUE)
rcs_txt2 <- paste(readLines(rcs_md2, warn = FALSE), collapse = "\n")
stopifnot(grepl("图上标注", rcs_txt2))
stopifnot(grepl("未收获", rcs_txt2))
unlink(rcs_md2)

# KM
meta_km <- meta
meta_km$findings <- list(km = list(list(db = "eICU", logrank_p = 0.023, cutoff = 1.25)))
km_md <- tempfile("km_md_")
pub_figure_write_image_md(km_md, "Figure 3. KM curve", meta = meta_km, raster_ok = TRUE)
km_txt <- paste(readLines(km_md, warn = FALSE), collapse = "\n")
stopifnot(grepl("图上标注", km_txt), grepl("Log-rank", km_txt), grepl("0\\.023", km_txt))
unlink(km_md)

# Forest
meta_fo <- meta
meta_fo$findings <- list(forest = list(list(
  db = "eICU",
  rows = data.frame(
    Variable = c("Overall", "Sex: Male"),
    `Point Estimate` = c(1.2, 1.3),
    Lower = c(1.0, 0.9), Upper = c(1.4, 1.8),
    `P for interaction` = c(NA, 0.12),
    check.names = FALSE, stringsAsFactors = FALSE
  )
)))
fo_md <- tempfile("fo_md_")
pub_figure_write_image_md(fo_md, "Figure 4. Subgroup forest plot", meta = meta_fo, raster_ok = TRUE)
fo_txt <- paste(readLines(fo_md, warn = FALSE), collapse = "\n")
stopifnot(grepl("图上标注", fo_txt), grepl("Overall", fo_txt), grepl("1\\.2", fo_txt))
unlink(fo_md)
```

- [ ] **Step 2: Run test — expect FAIL on missing「图上标注」**

Run: `Rscript tests/test_pub_figure_export.R`

- [ ] **Step 3: Update `.pub_figure_detailed_body` branches**

RCS 分支在现有描述后追加：

```r
lines <- c(lines, "图上标注（与面板一致）：", "")
rcs_ann <- .pub_figure_rcs_annotation_lines(find$rcs %||% list())
if (length(rcs_ann)) {
  lines <- c(lines, rcs_ann, "")
} else {
  lines <- c(lines, "- 未收获：各库 RCS panel_stats / P-overall / P-non-linear / cutoff", "")
}
```

KM 分支：

```r
lines <- c(lines, "图上标注：", "")
km_ann <- .pub_figure_km_annotation_lines(find$km %||% list())
if (length(km_ann)) {
  lines <- c(lines, km_ann, "")
} else {
  lines <- c(lines, "- 未收获：Log-rank P（及 binary cutoff）", "")
}
```

Forest 分支：

```r
lines <- c(lines, "图上标注（按图面行摘录）：", "")
fo_ann <- .pub_figure_forest_annotation_lines(find$forest %||% list())
if (length(fo_ann)) {
  lines <- c(lines, fo_ann, "")
} else {
  lines <- c(lines, "- 未收获：subgroup 结果表", "")
}
```

ROC / maxstat：若已有分条数字，段首加 `图上标注：`。Flowchart 保持现有逐步人数段（不必强制「图上标注」四字）。

- [ ] **Step 4: Run tests**

```bash
Rscript tests/test_pub_figure_onplot_annotations.R
Rscript tests/test_pub_figure_export.R
```

Expected: 两者 OK

- [ ] **Step 5: Commit（仅当用户要求）**

---

### Task 3: Harvest 从 checkpoint 收取 rcs / km / forest

**Files:**
- Modify: `R/pub_figure_export.R` → `pub_figure_harvest_findings`
- Modify: `tests/test_pub_figure_onplot_annotations.R`（增加临时目录 fixture）

**Interfaces:**
- Consumes: index_root 下 `<DB>/` 内 `*.rds`（`obj$ctx$results` 或 `obj$results`）
- Produces: `out$rcs`、`out$km`、`out$forest`，结构与 Task 1 helpers 一致

- [ ] **Step 1: Write harvest fixture test**

```r
# 追加到 tests/test_pub_figure_onplot_annotations.R
ix_root <- tempfile("ix_")
dir.create(file.path(ix_root, "Figures"), recursive = TRUE)
dir.create(file.path(ix_root, "MIMIC"), recursive = TRUE)
saveRDS(
  list(results = list(
    rcs_prognosis_panel_stats = list(
      Model2 = list(p_overall = 0.001, p_nonlinear = 0.116, cutoffs = 0.52)
    )
  )),
  file.path(ix_root, "MIMIC", "rcs_prognosis.rds")
)
saveRDS(
  list(results = list(
    km_binary = list(logrank_p = 0.023, cutoff = 1.25),
    subgroup = data.frame(
      Variable = c("Overall", "Age"), `Point Estimate` = c(1.2, 1.1),
      Lower = c(1.0, 0.8), Upper = c(1.4, 1.5),
      `P for interaction` = c(NA, 0.04), check.names = FALSE
    )
  )),
  file.path(ix_root, "MIMIC", "km_binary.rds")
)

hf <- pub_figure_harvest_findings(file.path(ix_root, "Figures"), meta = list(databases = "MIMIC"))
stopifnot(length(hf$rcs) >= 1L)
stopifnot(any(vapply(hf$rcs[[1]]$panels, function(p) {
  isTRUE(abs((p$p_overall %||% NA_real_) - 0.001) < 1e-9)
}, logical(1))))
stopifnot(length(hf$km) >= 1L)
stopifnot(length(hf$forest) >= 1L)
unlink(ix_root, recursive = TRUE)
```

- [ ] **Step 2: Run — expect FAIL until harvest extended**

- [ ] **Step 3: Implement harvest extensions**

`out` 初始化增加 `rcs`、`km`、`forest`。

在已有 `db_dirs` 循环中，对每个 `dd`：

1. `list.files(dd, pattern = "\\.rds$", full.names = TRUE)`（优先名含 `rcs`/`km`/`subgroup`）。
2. `readRDS` → `res <- obj$ctx$results %||% obj$results %||% list()`。
3. **RCS：** 读 `rcs_prognosis_panel_stats` / `rcs_incidence_panel_stats` / `rcs_nhanes_panel_stats` / `rcs_iptw_panel_stats`，规范为  
   `list(db=db_lab, panels=list(list(name=..., p_overall=..., p_nonlinear=..., cutoffs=...)))`。  
   **锁定：** 无 panel_stats 时不合成假 P；P 未收获由 detailed_body 明示。
4. **KM：** `res$km_binary` → `logrank_p`/`cutoff`；`res$km_strata$logrank_by_strata` → 多条（带 `strata`）。
5. **Forest：** `is.data.frame(res$subgroup)` → `list(db=db_lab, rows=res$subgroup)`。

同库每种槽去重（保留首次完整命中）。

- [ ] **Step 4: Run both test files — PASS**

- [ ] **Step 5: Commit（仅当用户要求）**

---

### Task 4: `rcs_prognosis` 写 `rcs_prognosis_panel_stats`

**Files:**
- Modify: `Blocks/15_rcs/01block_rcs_prognosis.R`
- Modify: `R/pub_figure_export.R`（`.pub_figure_extract_cox_rcs_p`）
- Modify: `tests/test_pub_figure_onplot_annotations.R`

**Interfaces:**
- Produces: `ctx$results$rcs_prognosis_panel_stats` =  
  `list(Crude=..., Model1=..., Model2=..., Model3?=...)`  
  每项 `list(p_overall, p_nonlinear, cutoffs)`  
- Extractor 与图例同一索引：`logtest[3]`、`coefficients[2,5]`

- [ ] **Step 1: Add shared extractor in `R/pub_figure_export.R`**

```r
.pub_figure_extract_cox_rcs_p <- function(p) {
  list(
    p_overall = tryCatch(suppressWarnings(as.numeric(p$logtest[3L]))[1L], error = function(e) NA_real_),
    p_nonlinear = tryCatch(suppressWarnings(as.numeric(p$coefficients[2L, 5L]))[1L], error = function(e) NA_real_)
  )
}
```

- [ ] **Step 2: Test extractor**

```r
fake_p <- list(
  logtest = c(NA, NA, 0.001),
  coefficients = matrix(c(rep(NA, 5), c(NA, NA, NA, NA, 0.116)), nrow = 2, byrow = TRUE)
)
pe <- .pub_figure_extract_cox_rcs_p(fake_p)
stopifnot(isTRUE(abs(pe$p_overall - 0.001) < 1e-9))
stopifnot(isTRUE(abs(pe$p_nonlinear - 0.116) < 1e-9))
```

- [ ] **Step 3: In prognosis block after fits，写 panel_stats**

```r
.ps <- function(res, cuts = numeric(0)) {
  pe <- .pub_figure_extract_cox_rcs_p(res$p)
  cuts <- as.numeric(cuts)
  list(
    p_overall = pe$p_overall,
    p_nonlinear = pe$p_nonlinear,
    cutoffs = cuts[is.finite(cuts)]
  )
}
# Model2 用图上竖线 cutoffs（cut_use$all）；Crude/M1 通常无竖线 → cutoffs 空
ctx$results$rcs_prognosis_panel_stats <- list(
  Crude  = .ps(resA, numeric(0)),
  Model1 = .ps(resB, numeric(0)),
  Model2 = .ps(resC, cut_use$all %||% numeric(0))
)
if (exists("resD") && !is.null(resD) && n_panel >= 4L) {
  ctx$results$rcs_prognosis_panel_stats$Model3 <- .ps(resD, numeric(0))
}
```

（变量名以文件内实际为准。）

- [ ] **Step 4: Run tests PASS**

- [ ] **Step 5: Commit（仅当用户要求）**

---

### Task 5: `rcs_incidence` 写 `rcs_incidence_panel_stats`

**Files:**
- Modify: `Blocks/15_rcs/02block_rcs_incidence.R`
- Modify: `R/pub_figure_export.R`（`.pub_figure_extract_lrm_anova_p`）
- Modify: `tests/test_pub_figure_onplot_annotations.R`

**Interfaces:**
- Produces: `ctx$results$rcs_incidence_panel_stats`  
- P 与图注同源：`p_overall = an[nrow(an), 3]`，`p_nonlinear = an[2, 3]`

- [ ] **Step 1: Add extractor**

```r
.pub_figure_extract_lrm_anova_p <- function(an) {
  an <- tryCatch(as.matrix(an), error = function(e) NULL)
  if (is.null(an) || !nrow(an) || ncol(an) < 3L) {
    return(list(p_overall = NA_real_, p_nonlinear = NA_real_))
  }
  list(
    p_overall = suppressWarnings(as.numeric(an[nrow(an), 3L]))[1L],
    p_nonlinear = suppressWarnings(as.numeric(an[min(2L, nrow(an)), 3L]))[1L]
  )
}
```

- [ ] **Step 2: After fits in `block_rcs_incidence`**

```r
.panel_from_res <- function(res, show_cuts = FALSE) {
  pe <- .pub_figure_extract_lrm_anova_p(res$an)
  cuts <- if (isTRUE(show_cuts)) {
    as.numeric(res$cutoffs$all %||% res$cutoffs$or1 %||% numeric(0))
  } else numeric(0)
  list(
    p_overall = pe$p_overall,
    p_nonlinear = pe$p_nonlinear,
    cutoffs = cuts[is.finite(cuts)]
  )
}
ctx$results$rcs_incidence_panel_stats <- list(
  Crude  = .panel_from_res(resA, FALSE),
  Model1 = .panel_from_res(resB, FALSE),
  Model2 = .panel_from_res(resC, TRUE)
)
```

- [ ] **Step 3: Fixture test for anova extractor + incidence panel_stats harvest key**

- [ ] **Step 4: Run tests PASS**

- [ ] **Step 5: Commit（仅当用户要求）**

---

### Task 6: NHANES / IPTW RCS 对齐（轻量）

**Files:**
- Modify: `Blocks/15_rcs/03block_rcs_nhanes.R`
- Modify: `Blocks/15_rcs/04block_rcs_iptw_weighted.R`
- Modify: harvest 识别 `rcs_nhanes_panel_stats` / `rcs_iptw_panel_stats`

- [ ] **Step 1: 在各自写 results 处增加 panel_stats（Model2 优先）**

从已有 `p_overall` / `p_nonlin` 与 `*_cutoffs_all` 构造，不重算。

- [ ] **Step 2: Harvest 映射进 `out$rcs`**

- [ ] **Step 3: harvest fixture 加一条 nhanes 键**

- [ ] **Step 4: Commit（仅当用户要求）**

---

### Task 7: KM 落盘 `logrank_p`

**Files:**
- Modify: `Blocks/27_KM/01block_km_binary.R`
- Modify: `Blocks/27_KM/02block_km_strata.R`
- Modify: `.pub_figure_km_annotation_lines`（已支持 `strata`，Task 1）

**Interfaces:**
- `km_binary` 增 `logrank_p`
- `km_strata` 增 `logrank_by_strata`（named numeric）

- [ ] **Step 1: `km_binary` 在出图前计算数值 log-rank，写入 results**

```r
.logrank_p <- tryCatch({
  sd <- survival::survdiff(fit_formula, data = data_categorized)
  stats::pchisq(sd$chisq, length(sd$n) - 1L, lower.tail = FALSE)
}, error = function(e) NA_real_)

ctx$results$km_binary <- list(
  index_var = index_var, cutoff = cutoff,
  n = nrow(data_categorized),
  level_low = lvl_lo, level_high = lvl_hi,
  logrank_p = .logrank_p
)
```

公式须与绘图分组列一致。

- [ ] **Step 2: `km_strata` 每张成功图记录数值 P 到 `logrank_by_strata[[strata_col]]`**

Harvest：为每个 strata 推一条 `out$km`（含 `strata`）。

- [ ] **Step 3: 扩展测试一条带 `strata` 的 km finding**

- [ ] **Step 4: Run tests PASS**

- [ ] **Step 5: Commit（仅当用户要求）**

---

### Task 8: 升级 Cursor 规则

**Files:**
- Modify: `.cursor/rules/pub_figure_image_information.mdc`

- [ ] **Step 1: 在「铁律」中新增第 7 条**

```markdown
7. **图面标注必录**：图上可见的关键数字/标注必须写入 `## 图面说明`（建议小标题「图上标注」），包括但不限于：
   - RCS：`P-overall` / `P for overall`、`P-non-linear` / `P for nonlinear`、竖线 cutoff
   - KM：Log-rank P、二分 cutoff
   - Forest：Overall 与各亚组效应量(95%CI)、P for interaction
   - ROC：AUC、CI、Youden、灵敏度/特异度（图上有则写）
   - maxstat：图上切点
   - Flowchart：逐步 n 与排除人数
   数字只来自可收获产物；缺则写「未收获」；**禁止编造**。其它图种若图上有数字，同理。
```

- [ ] **Step 2: 检查清单增加 RCS/KM/Forest 标注项**

- [ ] **Step 3: 反例增加「RCS 图上有 P/cutoff，md 只有空话」**

- [ ] **Step 4: 确认 `alwaysApply: true`**

- [ ] **Step 5: Commit（仅当用户要求）**

---

### Task 9: 回归与收尾

- [ ] **Step 1: Run**

```bash
Rscript tests/test_pub_figure_onplot_annotations.R
Rscript tests/test_pub_figure_export.R
Rscript tests/test_pub_figure_profile_gate.R
```

Expected: 全部 OK

- [ ] **Step 2: Spec coverage 自检**（§5–§8 逐项）

- [ ] **Step 3: 用户要求时统一 commit**（见下方命令）

```bash
git add \
  R/pub_figure_export.R \
  Blocks/15_rcs/01block_rcs_prognosis.R \
  Blocks/15_rcs/02block_rcs_incidence.R \
  Blocks/15_rcs/03block_rcs_nhanes.R \
  Blocks/15_rcs/04block_rcs_iptw_weighted.R \
  Blocks/27_KM/01block_km_binary.R \
  Blocks/27_KM/02block_km_strata.R \
  .cursor/rules/pub_figure_image_information.mdc \
  tests/test_pub_figure_export.R \
  tests/test_pub_figure_onplot_annotations.R \
  docs/superpowers/specs/2026-08-26-pub-figure-onplot-annotations-design.md \
  docs/superpowers/plans/2026-08-26-pub-figure-onplot-annotations.md
git commit -m "$(cat <<'EOF'
feat(pub-figure): require on-plot annotations in image_information

Persist RCS/KM panel stats, harvest into figure md, and document the global rule.
EOF
)"
```

---

## Spec coverage checklist（计划自检）

| Spec 要求 | Task |
|-----------|------|
| 方案 1 落盘→harvest→md | 3–7 + 2 |
| RCS P-overall / P-non-linear / cutoff | 1,2,4,5,6 |
| KM Log-rank / cutoff | 1,2,7 |
| Forest Overall + 亚组 + 交互 P | 1,2,3 |
| ROC / maxstat / Flowchart 保持 | 2 + 既有 harvest |
| 未收获不编造 | 2 |
| Cursor 规则 | 8 |
| 不批量补刷旧课题 | Global Constraints |
| 单一写出入口 | 仅改 `pub_figure_export.R` 写出路径 |

## 锁定口径

- 标注标签统一输出 `P-overall` / `P-non-linear`（与用户举例及预后图例一致）；发病块数值与 `anova` 图注同源即可
- 无 panel_stats 时不合成假 P
- Commit 默认跳过，除非用户明确要求
