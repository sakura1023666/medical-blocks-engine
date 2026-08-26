# Task brief

### Task 3: ≥3 库拼图

**Files:**
- Create: `tests/test_dual_db_combine_n_panel.R`
- Create: `R/dual_db_compose_n_panel.py`（或扩展现有 pair 脚本接受 N 个 PDF）
- Modify: `R/dual_db_combine_figures.R`
  - `.dual_db_combine_cfg`：收集 `tertiary` / `databases` 向量
  - `dual_db_combine_paired_figures`：`length(dbs_have) >= 2` 时按 `order_dbs` 全量拼；N>2 走 n-panel
  - 新增 `.dual_db_compose_n_pdf(paths, labels, out_path, layout, dpi, label_cex)`

**Interfaces:**
- Consumes: 现有 `.dual_db_parse_paired_figure_bn`、`.dual_db_panel_label`
- Produces: 同一 `dual_db_combine_paired_figures(index_root, config)` 支持 3+ 库；输出仍为无库标签 `key`

- [ ] **Step 1: Failing test**

```r
# tests/test_dual_db_combine_n_panel.R
root <- normalizePath(getwd())
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/dual_db_combine_figures.R"), local = FALSE)

make_min_pdf <- function(path) {
  grDevices::pdf(path, width = 3, height = 2); plot.new(); title(basename(path)); grDevices::dev.off()
}

ix <- tempfile("ix3_")
figs <- file.path(ix, "Figures")
dir.create(figs, recursive = TRUE)
make_min_pdf(file.path(figs, "Figure 2-CHARLS. RCS plot.pdf"))
make_min_pdf(file.path(figs, "Figure 2-ELSA. RCS plot.pdf"))
make_min_pdf(file.path(figs, "Figure 2-HRS. RCS plot.pdf"))

cfg <- list(
  dual_db = list(
    combine_figures = list(enable = TRUE, remove_singles = TRUE, dpi = 72L),
    primary = list(name = "CHARLS"),
    secondary = list(name = "ELSA"),
    tertiary = list(name = "HRS")
  )
)
# 实现后应识别 tertiary；若暂用 databases 向量亦可：
# cfg$dual_db$databases <- c("CHARLS","ELSA","HRS")

dual_db_combine_paired_figures(ix, cfg)
stopifnot(file.exists(file.path(figs, "Figure 2. RCS plot.pdf")))
stopifnot(!file.exists(file.path(figs, "Figure 2-CHARLS. RCS plot.pdf")))
stopifnot(!file.exists(file.path(figs, "Figure 2-ELSA. RCS plot.pdf")))
stopifnot(!file.exists(file.path(figs, "Figure 2-HRS. RCS plot.pdf")))
unlink(ix, recursive = TRUE)
cat("test_dual_db_combine_n_panel: OK\n")
```

- [ ] **Step 2: Run — expect FAIL**（仍只拼 primary/secondary 或跳过）

- [ ] **Step 3: 实现 n-panel**

在 `.dual_db_combine_cfg` 增加：

```r
tertiary = as.character((dd$tertiary %||% list())$name %||% "")[1L],
databases = {
  d <- unique(c(
    as.character((dd$primary %||% list())$name %||% "")[1L],
    as.character((dd$secondary %||% list())$name %||% "")[1L],
    as.character((dd$tertiary %||% list())$name %||% "")[1L],
    as.character(dd$databases %||% character(0))
  ))
  d[nzchar(d)]
}
```

拼图循环改为：

```r
order_dbs <- cfg$databases
if (!length(order_dbs)) order_dbs <- unique(c(cfg$primary, cfg$secondary, cfg$tertiary))
order_dbs <- order_dbs[nzchar(order_dbs)]
# ...
paths <- lapply(order_dbs, function(db) resolve(db))
paths <- Filter(Negate(is.null), paths)
if (length(paths) < 2L) { ... skip ... }
labels <- vapply(seq_along(paths), function(i) {
  .dual_db_panel_label(LETTERS[[i]], paths[[i]]$db, cfg$label_format)
}, character(1))
pdf_paths <- vapply(paths, function(x) x$path, character(1))
if (length(pdf_paths) == 2L) {
  .dual_db_compose_pair_pdf(...)
} else {
  .dual_db_compose_n_pdf(pdf_paths, labels, out_path, layout = layout, dpi = cfg$dpi, label_cex = cfg$label_cex)
}
```

`.dual_db_compose_n_pdf`：调用 `R/dual_db_compose_n_panel.py`（基于现有 pair 脚本扩展：一行 N 列；N==4 时 2×2）。栅格回退可复用现有 `.dual_db_compose_pair_pdf_raster` 的思路扩展为 N 图。

库名解析正则：把硬编码 `(eICU|MIMIC|NHANES)` 扩为「config 中全部 db_names + 文件名已解析标签」，避免 CHARLS/ELSA/HRS 漏检。

- [ ] **Step 4: Run test — expect OK**

- [ ] **Step 5: Commit**

```bash
git add R/dual_db_combine_figures.R R/dual_db_compose_n_panel.py tests/test_dual_db_combine_n_panel.R
git commit -m "$(cat <<'EOF'
feat: combine three-plus database publication figure panels

Extend dual_db_combine_paired_figures beyond A/B so cross-cohort
studies can mosaic CHARLS/ELSA/HRS-style panels in one pass.
EOF
)"
```

---

