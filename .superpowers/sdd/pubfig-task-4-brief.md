# Task brief

### Task 4: 交叉滞后 summary_result/figure

**Files:**
- Create: `Blocks/54_cross_lagged_full/phases/export_summary_figures.R`
- Modify: `Blocks/54_cross_lagged_full/phases/collect_summary_result_generic.sh`
- Modify: `Blocks/54_cross_lagged_full/phases/collect_summary_result_hip.sh`（若仍被调用）
- Modify: `Blocks/54_cross_lagged_full/phases/collect_summary_result_circadian.sh`
- Modify: `Blocks/54_cross_lagged_full/phases/collect_summary_result.sh`

**Interfaces:**
- Consumes: `dual_db_combine_paired_figures`, `export_pub_figures`, `cross_lagged_study_meta(study_root)$grouping`
- Produces: `summary_result/figure/{pdf,png,tiff,image_information}/`

- [ ] **Step 1: 写 `export_summary_figures.R`**

```r
#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
study_root <- args[[1L]]
stopifnot(dir.exists(study_root))

# 定位引擎根：study 的上级链或 MEDICAL_BLOCKS_ROOT
eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(eng)) {
  # 常见：.../01Block-new-Final/studies/<name>
  cand <- normalizePath(file.path(study_root, "../.."), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "R/utils.R"))) eng <- cand
  else eng <- normalizePath(getwd())
}
source(file.path(eng, "R/utils.R"), local = FALSE)
source(file.path(eng, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(eng, "R/pub_figure_export.R"), local = FALSE)
if (file.exists(file.path(eng, "R/cross_lagged_study_meta.R"))) {
  source(file.path(eng, "R/cross_lagged_study_meta.R"), local = FALSE)
}

fig <- file.path(study_root, "summary_result", "figure")
dir.create(fig, recursive = TRUE, showWarnings = FALSE)

meta_g <- tryCatch(cross_lagged_study_meta(study_root)$grouping, error = function(e) "")
dbs <- character(0)
# 从文件名推断 + 已知队列
for (bn in list.files(fig, pattern = "\\.pdf$", ignore.case = TRUE)) {
  # Figure N-DB. ... 已由 combine 解析
}
# 课题常见三库
for (db in c("CHARLS", "ELSA", "HRS", "NHANES")) {
  if (any(grepl(paste0("-", db, "\\."), list.files(fig), ignore.case = TRUE))) {
    dbs <- c(dbs, db)
  }
}
dbs <- unique(dbs)

cfg <- list(
  dual_db = list(
    combine_figures = list(enable = length(dbs) >= 2L, remove_singles = TRUE, dpi = 200L),
    databases = dbs,
    primary = list(name = if (length(dbs)) dbs[[1]] else "primary"),
    secondary = list(name = if (length(dbs) >= 2) dbs[[2]] else "secondary"),
    tertiary = list(name = if (length(dbs) >= 3) dbs[[3]] else "")
  ),
  pub_figures = list(formats_dir = TRUE, dpi = 300L, write_image_information = TRUE)
)

# combine 期望 index_root（其下有 Figures/）。交叉滞后目录名是 figure/
# 适配：临时把 figure 当作 Figures，或给 combine 增加 figures_subdir 参数。
# 【实现时二选一，优先改 combine 支持 figures_dir 直接传入】
if (exists("dual_db_combine_paired_figures_dir", mode = "function")) {
  dual_db_combine_paired_figures_dir(fig, cfg)
} else {
  # 薄包装：创建临时 index_root/Figures 符号或复制——禁止。应在 Task 3 增加：
  # dual_db_combine_paired_figures <- function(index_root, config, figures_dir = NULL)
  # figures_dir 默认 file.path(index_root, "Figures")
  dual_db_combine_paired_figures(dirname(fig), cfg) # 仅当 fig 名为 Figures 时正确
}

# 正确做法（实现者必须在 Task 3 完成）：
# dual_db_combine_paired_figures(index_root = study_root, config = cfg,
#   figures_dir = fig)

export_pub_figures(
  fig,
  meta = list(
    databases = dbs,
    combined = length(dbs) >= 2L,
    grouping = meta_g
  ),
  config = cfg
)
```

**实现约束（写入 Task 3 补丁）：** 给 `dual_db_combine_paired_figures` 增加可选参数 `figures_dir = NULL`；为 `NULL` 时用 `file.path(index_root, "Figures")`，否则直接用传入目录。交叉滞后只传 `figures_dir = summary_result/figure`。

- [ ] **Step 2: 各 collect_*.sh 末尾**

在脚本成功收齐图之后：

```bash
ENG_ROOT="${MEDICAL_BLOCKS_ROOT:-}"
if [[ -z "$ENG_ROOT" ]]; then
  ENG_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fi
Rscript "$ENG_ROOT/Blocks/54_cross_lagged_full/phases/export_summary_figures.R" "$STUDY"
```

- [ ] **Step 3: 手工烟雾**（若无完整 study，用临时目录模拟三份 `-CHARLS/-ELSA/-HRS` PDF 再跑 Rscript）

- [ ] **Step 4: Commit**

```bash
git add Blocks/54_cross_lagged_full/phases/export_summary_figures.R \
  Blocks/54_cross_lagged_full/phases/collect_summary_result*.sh \
  R/dual_db_combine_figures.R
git commit -m "$(cat <<'EOF'
feat: mosaic and export cross-lagged summary figures

After collect, combine multi-cohort panels and write pdf/png/tiff
plus image_information under summary_result/figure.
EOF
)"
```

---

