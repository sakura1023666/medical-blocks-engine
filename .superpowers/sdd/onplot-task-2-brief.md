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

