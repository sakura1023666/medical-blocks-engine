# Pub Figures Formats + Image Information Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 所有套路的汇总图目录顶层只留 `pdf/` `png/` `tiff/` `image_information/`；多库强制拼图后导出三格式（TIFF=LZW）并为每张图写 md。

**Architecture:** Block 仍写 PDF；在汇总定稿（拼图 + curate）之后调用 `export_pub_figures()`。拼图扩展现有 `dual_db_combine_paired_figures` 支持 ≥3 库；交叉滞后 / 竞争风险 / 单流水线在各自收口挂同一导出函数。

**Tech Stack:** R, Python3 (pypdf/Pillow 或 magick), `pdftoppm`, 现有 `R/dual_db_combine_figures.R`

**Spec:** `docs/superpowers/specs/2026-08-20-pub-figures-formats-and-image-information-design.md`

## Global Constraints

- 汇总顶层**只有**四个子目录，不得残留散落图文件
- TIFF：**LZW**，默认 DPI **300**，RGB
- 多库：拼图后 `remove_singles`；分库底稿不进汇总四目录
- 单库：不拼图，终稿进四目录
- md Grouping 禁止写死 tertile；有则用调用方注入的主文闸门
- 不改 step 级中间图；Missing Value Overview 不进四目录
- 缺配对：告警，保留无库标签单侧并 export（与现网一致）

---

## File map

| 文件 | 职责 |
|------|------|
| `R/pub_figure_export.R` | `export_pub_figures`、md 渲染、四目录落盘 |
| `python/pub_figure_rasterize.py` | PDF → PNG/TIFF（LZW） |
| `R/dual_db_combine_figures.R` | ≥3 库拼图 + 泛化库名单 |
| `R/dual_db_compose_n_panel.py` | N 面板矢量/栅格拼图（新建；2 面板可仍走现有 pair 脚本） |
| `R/incidence_dual_batch_runner.R` | finalize 末尾调用 export |
| `R/pipeline_runner.R` | 单流水线结束时对根 `Figures/` export |
| `Blocks/55_competing_risk_full/18block_competing_pub_export.R` | 发表导出末尾 export |
| `Blocks/54_cross_lagged_full/phases/export_summary_figures.R` | collect 后：多库拼图 + export |
| `Blocks/54_cross_lagged_full/phases/collect_summary_result_generic.sh` 等 | 末尾调用上述 R |
| `configs/templates/*.template.R` | `pub_figures` 默认块 |
| `tests/test_pub_figure_export.R` | 导出 + LZW + 顶层清空 |
| `tests/test_dual_db_combine_n_panel.R` | ≥3 库拼图 |

---

### Task 1: `export_pub_figures` 核心（TDD）

**Files:**
- Create: `tests/test_pub_figure_export.R`
- Create: `python/pub_figure_rasterize.py`
- Create: `R/pub_figure_export.R`

**Interfaces:**
- Produces:
  - `export_pub_figures(figures_dir, meta = list(), config = list())` → invisible `list(exported=, missing_raster=, md=)`
  - `pub_figure_write_image_md(path, stem, meta, tech)` → writes one md
  - `pub_figure_ensure_format_dirs(figures_dir)` → character vector of four paths

- [ ] **Step 1: Write the failing test**

```r
# tests/test_pub_figure_export.R
root <- normalizePath(getwd())
if (!file.exists(file.path(root, "R/utils.R"))) {
  # allow running from tests/
  cand <- normalizePath(file.path(".."), winslash = "/")
  if (file.exists(file.path(cand, "R/utils.R"))) root <- cand
}
source(file.path(root, "R/utils.R"), local = FALSE)
stopifnot(file.exists(file.path(root, "R/pub_figure_export.R")))
source(file.path(root, "R/pub_figure_export.R"), local = FALSE)

# 最小可栅格 PDF（1 页空白）
make_min_pdf <- function(path) {
  grDevices::pdf(path, width = 4, height = 3, onefile = TRUE)
  plot.new()
  title("test fig")
  grDevices::dev.off()
}

fd <- tempfile("pub_figs_")
dir.create(fd)
f1 <- file.path(fd, "Figure 1. Flowchart.pdf")
f2 <- file.path(fd, "Figure 2. RCS plot.pdf")
make_min_pdf(f1)
make_min_pdf(f2)
# 不应进入交付
file.create(file.path(fd, "Figure Missing Value Overview.pdf"))

meta <- list(
  exposure = "BAR",
  outcome = "Death",
  n_total = 1000L,
  n_by_db = c(eICU = 600L, MIMIC = 400L),
  databases = c("eICU", "MIMIC"),
  combined = TRUE,
  layout = "side",
  grouping = "quartile"
)

res <- export_pub_figures(fd, meta = meta, config = list(pub_figures = list(dpi = 72L)))
stopifnot(dir.exists(file.path(fd, "pdf")))
stopifnot(dir.exists(file.path(fd, "png")))
stopifnot(dir.exists(file.path(fd, "tiff")))
stopifnot(dir.exists(file.path(fd, "image_information")))
stopifnot(file.exists(file.path(fd, "pdf", "Figure 1. Flowchart.pdf")))
stopifnot(file.exists(file.path(fd, "png", "Figure 1. Flowchart.png")))
stopifnot(file.exists(file.path(fd, "tiff", "Figure 1. Flowchart.tiff")))
stopifnot(file.exists(file.path(fd, "image_information", "Figure 1. Flowchart.md")))
stopifnot(file.exists(file.path(fd, "image_information", "README.md")))
# 顶层无散落图
top <- list.files(fd, pattern = "\\.(pdf|png|tiff|tif)$", ignore.case = TRUE)
stopifnot(length(top) == 0L)
# Missing overview 不得进 pdf/
stopifnot(!file.exists(file.path(fd, "pdf", "Figure Missing Value Overview.pdf")))
md <- paste(readLines(file.path(fd, "image_information", "Figure 2. RCS plot.md"), warn = FALSE), collapse = "\n")
stopifnot(grepl("BAR", md), grepl("Death", md), grepl("quartile", md), grepl("LZW", md, ignore.case = TRUE))

# TIFF LZW：用 Python 读 compression
py <- file.path(root, "python", "pub_figure_rasterize.py")
stopifnot(file.exists(py))
tiff_path <- file.path(fd, "tiff", "Figure 1. Flowchart.tiff")
chk <- system2(
  "python3",
  c("-c", sprintf(
    "from PIL import Image; im=Image.open(%s); print(im.info.get('compression'))",
    shQuote(tiff_path)
  )),
  stdout = TRUE, stderr = TRUE
)
stopifnot(any(grepl("tiff_lzw|lzw", chk, ignore.case = TRUE)))

unlink(fd, recursive = TRUE)
cat("test_pub_figure_export: OK\n")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /mnt/e/01block/01Block-new-Final && Rscript tests/test_pub_figure_export.R`

Expected: FAIL — `R/pub_figure_export.R` 不存在或 `export_pub_figures` 未定义

- [ ] **Step 3: Implement Python rasterizer**

Create `python/pub_figure_rasterize.py`:

```python
#!/usr/bin/env python3
"""Rasterize first page of a PDF to PNG and/or TIFF (LZW)."""
from __future__ import annotations

import argparse
import sys


def render_page(pdf_path: str, dpi: int):
    # Prefer pypdfium2 / pdf2image / pdftoppm via subprocess
    try:
        import pypdfium2 as pdfium
        doc = pdfium.PdfDocument(pdf_path)
        page = doc[0]
        bitmap = page.render(scale=dpi / 72.0)
        return bitmap.to_pil()
    except Exception:
        pass
    import os
    import subprocess
    import tempfile
    from PIL import Image

    with tempfile.TemporaryDirectory() as td:
        prefix = os.path.join(td, "page")
        subprocess.check_call(
            ["pdftoppm", "-png", "-r", str(dpi), "-f", "1", "-l", "1", pdf_path, prefix]
        )
        # pdftoppm writes prefix-1.png
        cand = prefix + "-1.png"
        if not os.path.isfile(cand):
            # some builds use prefix.png
            cand = prefix + ".png"
        return Image.open(cand).convert("RGB")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pdf", required=True)
    ap.add_argument("--png")
    ap.add_argument("--tiff")
    ap.add_argument("--dpi", type=int, default=300)
    args = ap.parse_args()
    im = render_page(args.pdf, args.dpi)
    if args.png:
        im.save(args.png, format="PNG")
    if args.tiff:
        im.save(args.tiff, format="TIFF", compression="tiff_lzw")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Implement `R/pub_figure_export.R`**

实现要点（完整写入文件）：

```r
###############################################################################
# pub_figure_export.R — 汇总 Figures → pdf/png/tiff + image_information
# Spec: docs/superpowers/specs/2026-08-20-pub-figures-formats-and-image-information-design.md
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

.PUB_FIGURE_EXPORT_DIR <- tryCatch({
  of <- sys.frame(1)$ofile
  if (!is.null(of) && nzchar(as.character(of)[1L])) {
    dirname(normalizePath(of, winslash = "/", mustWork = FALSE))
  } else NA_character_
}, error = function(e) NA_character_)

.pub_figure_cfg <- function(config = list()) {
  cfg <- (config$pub_figures %||% list())
  list(
    enable = isTRUE(cfg$formats_dir %||% TRUE),
    dpi = as.integer(cfg$dpi %||% 300L)[1L],
    tiff_compression = "lzw",
    write_image_information = isTRUE(cfg$write_image_information %||% TRUE)
  )
}

pub_figure_ensure_format_dirs <- function(figures_dir) {
  figures_dir <- as.character(figures_dir %||% "")[1L]
  stopifnot(nzchar(figures_dir))
  dirs <- c(
    pdf = file.path(figures_dir, "pdf"),
    png = file.path(figures_dir, "png"),
    tiff = file.path(figures_dir, "tiff"),
    image_information = file.path(figures_dir, "image_information")
  )
  for (d in dirs) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  dirs
}

.pub_figure_is_missing_overview <- function(bn) {
  grepl("Missing\\s*Value\\s*Overview", bn, ignore.case = TRUE)
}

.pub_figure_role_blurb <- function(stem) {
  s <- as.character(stem %||% "")[1L]
  if (grepl("Flowchart|Inclusion|Exclusion|Attrition", s, ignore.case = TRUE))
    return("纳排/流程图：展示分析队列从原始样本到最终纳入的逐步筛选。")
  if (grepl("\\bRCS\\b|Restricted\\s*Cubic", s, ignore.case = TRUE))
    return("限制性立方样条（RCS）图：展示暴露与结局关联的剂量–反应形状及置信带。")
  if (grepl("Forest|Subgroup", s, ignore.case = TRUE))
    return("亚组森林图：按预设分层比较暴露与结局的关联效应及交互。")
  if (grepl("\\bKM\\b|Kaplan", s, ignore.case = TRUE))
    return("Kaplan–Meier 生存曲线：比较分组间累积生存/事件概率随时间的变化。")
  if (grepl("\\bROC\\b", s, ignore.case = TRUE))
    return("ROC 曲线：展示预测/判别性能（灵敏度–1-特异度）。")
  if (grepl("SHAP|Feature\\s*Importance", s, ignore.case = TRUE))
    return("模型解释图：展示特征对预测的贡献或重要性。")
  if (grepl("CLPN|network", s, ignore.case = TRUE))
    return("网络/CLPN 图：展示指标条目或条件之间的关联结构。")
  "发表图：详见文件名中的图题；具体统计量见对应主表/附录表。"
}

pub_figure_write_image_md <- function(md_path, stem, meta = list(), tech = list()) {
  stem <- as.character(stem %||% "")[1L]
  caption <- sub("^Figure\\s+[0-9S]+\\.\\s*", "", stem, ignore.case = TRUE)
  fig_no <- sub("^((Figure\\s+[0-9S]+)\\.).*$", "\\2", stem, ignore.case = TRUE)
  n_line <- if (!is.null(meta$n_by_db) && length(meta$n_by_db)) {
    paste0(
      paste(sprintf("%s=%s", names(meta$n_by_db), meta$n_by_db), collapse = "; "),
      if (!is.null(meta$n_total)) sprintf("；合计 N=%s", meta$n_total) else ""
    )
  } else if (!is.null(meta$n_total)) {
    sprintf("N=%s", meta$n_total)
  } else "未记录"

  blurb <- .pub_figure_role_blurb(stem)
  if (isTRUE(meta$combined) && length(meta$databases)) {
    blurb <- paste0(
      blurb, " 多库拼图面板顺序：",
      paste(sprintf("%s=%s", LETTERS[seq_along(meta$databases)], meta$databases), collapse = ", "),
      if (nzchar(meta$layout %||% "")) sprintf("（布局=%s）", meta$layout) else "", "。"
    )
  }

  lines <- c(
    paste0("# ", stem),
    "",
    "## 这张图在讲什么",
    blurb,
    "",
    "## 标识",
    paste0("- 图号: ", fig_no),
    paste0("- 图题: ", caption),
    paste0("- 文件: `../pdf/", stem, ".pdf` `../png/", stem, ".png` `../tiff/", stem, ".tiff`"),
    "",
    "## 分析上下文",
    paste0("- 暴露: ", meta$exposure %||% "未记录"),
    paste0("- 结局: ", meta$outcome %||% "未记录"),
    paste0("- 样本量: ", n_line),
    paste0("- Grouping: ", meta$grouping %||% "未记录"),
    paste0("- 数据库: ", paste(meta$databases %||% "未记录", collapse = ", ")),
    paste0("- 是否拼图: ", if (isTRUE(meta$combined)) "是" else "否"),
    "",
    "## 技术",
    paste0("- 尺寸(inch): ", tech$width %||% "未记录", " x ", tech$height %||% "未记录"),
    paste0("- DPI: ", tech$dpi %||% 300L),
    "- TIFF 压缩: LZW",
    "- 色彩: RGB",
    ""
  )
  writeLines(lines, md_path, useBytes = TRUE)
  invisible(md_path)
}

.pub_figure_rasterize_one <- function(pdf_path, png_path, tiff_path, dpi, root_hint = NULL) {
  script <- NULL
  cands <- c(
    if (!is.null(root_hint)) file.path(root_hint, "python", "pub_figure_rasterize.py"),
    if (!is.na(.PUB_FIGURE_EXPORT_DIR)) file.path(dirname(.PUB_FIGURE_EXPORT_DIR), "python", "pub_figure_rasterize.py"),
    file.path(getwd(), "python", "pub_figure_rasterize.py")
  )
  for (c in cands) if (!is.null(c) && file.exists(c)) { script <- c; break }
  if (is.null(script)) stop("找不到 python/pub_figure_rasterize.py", call. = FALSE)
  args <- c(
    script,
    "--pdf", pdf_path,
    "--png", png_path,
    "--tiff", tiff_path,
    "--dpi", as.character(as.integer(dpi)[1L])
  )
  st <- system2("python3", args, stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(st, "status")) && attr(st, "status") != 0) {
    stop(paste(st, collapse = "\n"), call. = FALSE)
  }
  invisible(TRUE)
}

#' 汇总 Figures 定稿导出
#' @param figures_dir 汇总图目录（顶层此时应为无库标签 PDF）
#' @param meta list: exposure, outcome, n_total, n_by_db, databases, combined, layout, grouping
#' @param config 完整或含 pub_figures 的 list
export_pub_figures <- function(figures_dir, meta = list(), config = list()) {
  cfg <- .pub_figure_cfg(config)
  figures_dir <- as.character(figures_dir %||% "")[1L]
  if (!nzchar(figures_dir) || !dir.exists(figures_dir)) {
    return(invisible(list(exported = character(), missing_raster = character(), md = character())))
  }
  dirs <- pub_figure_ensure_format_dirs(figures_dir)
  if (!isTRUE(cfg$enable)) {
    return(invisible(list(exported = character(), missing_raster = character(), md = character())))
  }

  root_hint <- tryCatch(normalizePath(file.path(figures_dir, "../.."), winslash = "/", mustWork = FALSE), error = function(e) getwd())
  # 若能定位仓库根更好：从本文件推导
  if (!is.na(.PUB_FIGURE_EXPORT_DIR)) {
    root_hint <- dirname(.PUB_FIGURE_EXPORT_DIR)
  }

  tops <- list.files(figures_dir, pattern = "\\.(pdf|png)$", full.names = TRUE, ignore.case = TRUE)
  tops <- tops[file.info(tops)$isdir %in% FALSE]
  exported <- character(0)
  missing_raster <- character(0)
  md_files <- character(0)
  readme_rows <- list()

  for (fp in tops) {
    bn <- basename(fp)
    if (.pub_figure_is_missing_overview(bn)) {
      unlink(fp)
      next
    }
    if (!grepl("^Figure", bn, ignore.case = TRUE)) next
    stem <- sub("\\.(pdf|png)$", "", bn, ignore.case = TRUE)
    pdf_src <- fp
    if (grepl("\\.png$", bn, ignore.case = TRUE)) {
      # 仅有 png：仍复制到 png/，pdf/tiff 尽量跳过并记 missing
      file.copy(fp, file.path(dirs[["png"]], paste0(stem, ".png")), overwrite = TRUE)
      exported <- c(exported, stem)
      unlink(fp)
      next
    }
    dest_pdf <- file.path(dirs[["pdf"]], paste0(stem, ".pdf"))
    file.copy(pdf_src, dest_pdf, overwrite = TRUE)
    dest_png <- file.path(dirs[["png"]], paste0(stem, ".png"))
    dest_tiff <- file.path(dirs[["tiff"]], paste0(stem, ".tiff"))
    ok_r <- tryCatch({
      .pub_figure_rasterize_one(dest_pdf, dest_png, dest_tiff, cfg$dpi, root_hint = root_hint)
      TRUE
    }, error = function(e) {
      if (exists("cli_alert_warning", mode = "function") || requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning("栅格化失败 [{stem}]: {e$message}")
      }
      FALSE
    })
    if (!isTRUE(ok_r)) missing_raster <- c(missing_raster, stem)

    if (isTRUE(cfg$write_image_information)) {
      md_path <- file.path(dirs[["image_information"]], paste0(stem, ".md"))
      pub_figure_write_image_md(
        md_path, stem, meta = meta,
        tech = list(dpi = cfg$dpi, width = "未记录", height = "未记录")
      )
      md_files <- c(md_files, md_path)
    }
    readme_rows[[length(readme_rows) + 1L]] <- data.frame(
      figure = stem,
      combined = isTRUE(meta$combined),
      pdf = file.path("pdf", paste0(stem, ".pdf")),
      stringsAsFactors = FALSE
    )
    exported <- c(exported, stem)
    unlink(fp)
  }

  # 空目录也写 README
  if (isTRUE(cfg$write_image_information)) {
    readme <- file.path(dirs[["image_information"]], "README.md")
    if (length(readme_rows)) {
      tab <- do.call(rbind, readme_rows)
      lines <- c(
        "# Image information index",
        "",
        "| Figure | Combined | PDF |",
        "|---|---|---|",
        sprintf("| %s | %s | `%s` |", tab$figure, ifelse(tab$combined, "yes", "no"), tab$pdf),
        ""
      )
    } else {
      lines <- c("# Image information index", "", "_No publication figures._", "")
    }
    writeLines(lines, readme, useBytes = TRUE)
  }

  invisible(list(exported = unique(exported), missing_raster = unique(missing_raster), md = md_files))
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /mnt/e/01block/01Block-new-Final && Rscript tests/test_pub_figure_export.R`

Expected: `test_pub_figure_export: OK`

若 Pillow/pdftoppm 缺失：安装 `python3-pil` / `poppler-utils`，或在测试机用 `pip install pypdfium2 pillow`。

- [ ] **Step 6: Commit**

```bash
git add R/pub_figure_export.R python/pub_figure_rasterize.py tests/test_pub_figure_export.R \
  docs/superpowers/specs/2026-08-20-pub-figures-formats-and-image-information-design.md
git commit -m "$(cat <<'EOF'
feat: export pub Figures into pdf/png/tiff plus image_information

Add shared export_pub_figures so aggregate figure dirs deliver three
formats (TIFF LZW) and per-figure markdown descriptions.
EOF
)"
```

---

### Task 2: Dual-batch finalize 挂载 export

**Files:**
- Modify: `R/incidence_dual_batch_runner.R`（`incidence_batch_finalize_index_outputs` 末尾，约 1920 行后、函数结束前）
- Modify: `tests/test_result_review_guards.R`（拼图清扫后增加「export 后顶层无散落」断言，或新建轻量用例）
- Modify: `configs/templates/config_incidence_dual_batch.template.R`
- Modify: `configs/templates/config_survival_dual_batch.template.R`
- Modify: `configs/templates/config_ml_dual_batch.template.R`

**Interfaces:**
- Consumes: `export_pub_figures(figures_dir, meta, config)` from Task 1
- Produces: finalize 顺序固定为 combine → curate → **export**

- [ ] **Step 1: 在 finalize 末尾 source + 调用**

在 `incidence_batch_finalize_index_outputs` 函数体**最后**（所有 table curate 之后）加入：

```r
  # 发表图四目录导出（pdf/png/tiff + image_information）
  if (!exists("export_pub_figures", mode = "function")) {
    exp_src <- file.path(root, "R", "pub_figure_export.R")
    if (file.exists(exp_src)) source(exp_src, local = FALSE)
  }
  if (exists("export_pub_figures", mode = "function")) {
    figs_dir <- file.path(index_root, "Figures")
    meta <- list(
      exposure = as.character(config$project$exposure_var %||% config$project$index_var %||% ix)[1L],
      outcome = as.character(config$data$outcome_column %||% config$project$outcome %||% "")[1L],
      databases = as.character(db_seq),
      combined = length(db_seq) >= 2L,
      grouping = as.character(
        config$logistic_gate$grouping %||%
          config$project$grouping %||%
          ""
      )[1L]
    )
    tryCatch(
      export_pub_figures(figs_dir, meta = meta, config = config),
      error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
    )
  }
```

注意：若 `index_root` 变量名在该函数内已是成功目录路径，直接用；不要在 combine 之前调用。

- [ ] **Step 2: 模板加默认配置**

每个 dual template 增加：

```r
  pub_figures = list(
    formats_dir = TRUE,
    dpi = 300L,
    tiff_compression = "lzw",
    write_image_information = TRUE
  ),
```

- [ ] **Step 3: 回归测试**

Run:

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript tests/test_result_review_guards.R
Rscript tests/test_pub_figure_export.R
```

Expected: 两者均 OK。若 guards 因路径假设失败，只修断言不改业务语义。

- [ ] **Step 4: Commit**

```bash
git add R/incidence_dual_batch_runner.R configs/templates/config_*_dual_batch.template.R
git commit -m "$(cat <<'EOF'
feat: run pub figure format export at dual-batch finalize

After combine and curate, write pdf/png/tiff and image_information
under aggregate Figures for incidence/survival/ML dual pipelines.
EOF
)"
```

---

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

### Task 5: 竞争风险 + 通用单流水线收口

**Files:**
- Modify: `Blocks/55_competing_risk_full/18block_competing_pub_export.R`（在 `cli_alert_success` 之前）
- Modify: `R/pipeline_runner.R`（`run_pipeline` 在 `pub_renumber_pub_dir` **之后**对根 `Figures/` 调用 export）

**Interfaces:**
- Consumes: `export_pub_figures`
- 多库竞争风险：若根 `Figures/` 仍有 `-DB` 成对文件，先 `dual_db_combine_paired_figures(..., figures_dir=...)` 再 export

- [ ] **Step 1: competing_pub_export 末尾**

```r
  if (!exists("export_pub_figures", mode = "function")) {
    src <- file.path(ctx$config$project$root %||% getwd(), "R/pub_figure_export.R")
    if (file.exists(src)) source(src, local = FALSE)
  }
  if (exists("export_pub_figures", mode = "function")) {
    tryCatch(
      export_pub_figures(
        fig_dir,
        meta = list(
          exposure = ctx$config$project$exposure_var %||% "",
          outcome = ctx$config$data$outcome_column %||% "",
          databases = ctx$config$project$database %||% character(0),
          combined = FALSE
        ),
        config = ctx$config
      ),
      error = function(e) cli::cli_alert_warning("发表图导出跳过: {e$message}")
    )
  }
```

- [ ] **Step 2: `run_pipeline` 收尾**

在 `pub_renumber_pub_dir` 循环之后：

```r
  if (exists("export_pub_figures", mode = "function") ||
      file.exists(file.path(root, "R/pub_figure_export.R"))) {
    if (!exists("export_pub_figures", mode = "function")) {
      source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
    }
    out_root <- ctx$root_output_dir %||% config$project$output_dir
    figs <- file.path(out_root, "Figures")
    if (dir.exists(figs)) {
      # 若顶层已有 pdf/ 子目录则跳过，避免 dual-batch 子进程误二次处理
      if (!dir.exists(file.path(figs, "pdf"))) {
        tryCatch(
          export_pub_figures(figs, meta = list(
            exposure = config$project$exposure_var %||% config$project$index_var %||% "",
            outcome = config$data$outcome_column %||% "",
            databases = config$project$database %||% character(0),
            combined = FALSE
          ), config = config),
          error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
        )
      }
    }
  }
```

说明：dual-batch 指标目录由 Task 2 finalize 导出；worker 内 `run_pipeline` 若指向分库 `Figures/`，`pdf/` 尚不存在会导出分库底稿——**不可取**。改为：

```r
# 仅当非 dual 分库输出时导出：config$dual_db$current_db 为空/NULL，且路径不是 */<DB>/Figures
is_dual_slot <- !is.null(config$dual_db$current_db) && nzchar(as.character(config$dual_db$current_db)[1L])
if (!isTRUE(is_dual_slot) && dir.exists(figs) && !dir.exists(file.path(figs, "pdf"))) {
  export_pub_figures(...)
}
```

- [ ] **Step 3: 跑 `Rscript tests/test_pub_figure_export.R` + 相关 guards**

- [ ] **Step 4: Commit**

```bash
git add Blocks/55_competing_risk_full/18block_competing_pub_export.R R/pipeline_runner.R
git commit -m "$(cat <<'EOF'
feat: export publication figure formats from competing and single pipelines

Hook export_pub_figures after competing pub export and at run_pipeline
end for non-dual aggregate Figures directories.
EOF
)"
```

---

### Task 6: 文档与 Blocks 目录（若改了 register_block）

**Files:**
- Modify: `docs/Blocks_catalog.md` MANUAL 段（仅当新增全局约定时）— 用 `python3 scripts/update_blocks_catalog.py` 若 block 头有变
- 可选：在 `docs/Blocks_catalog.md` 手写「发表图四目录」坑位一句（MANUAL 坑点区）

- [ ] **Step 1:** 在 catalog MANUAL「发表图」相关处加一条：

> 汇总 `Figures/`（及交叉滞后 `summary_result/figure`）顶层只保留 `pdf/` `png/` `tiff/` `image_information/`；多库先拼图再导出；TIFF=LZW。

- [ ] **Step 2:** Commit docs

```bash
git add docs/Blocks_catalog.md
git commit -m "$(cat <<'EOF'
docs: note pub Figures four-directory delivery convention
EOF
)"
```

---

## Spec coverage checklist（写完自审）

| Spec 要求 | Task |
|-----------|------|
| 四目录单/多库一律 | 1, 2, 4, 5 |
| 多库拼图 + remove_singles | 2, 3, 4 |
| TIFF LZW 300dpi | 1 |
| image_information md + README | 1 |
| 顶层无散落文件 | 1 |
| ≥3 库 | 3 |
| 交叉滞后 figure/ | 3（figures_dir 参数）+ 4 |
| 竞争风险 / 单流水线 | 5 |
| Grouping 不写死 | 1 md + 4 meta 注入 |
| Missing overview 排除 | 1 |
| dual finalize 顺序 curate→export | 2 |

## Placeholder scan

无 TBD；Task 4 依赖 Task 3 的 `figures_dir=` 参数——已在 Task 3/4 双向写明，实现时先完成 Task 3 再写 Task 4。

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-20-pub-figures-formats-and-image-information.md`.

**两种执行方式：**

1. **Subagent-Driven（推荐）** — 每任务派一个新子代理，任务间审查  
2. **Inline Execution** — 本会话按 executing-plans 批量做，设检查点  

要哪一种？
