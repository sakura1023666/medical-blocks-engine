# Review package Task 1

## Files created
- R/pub_figure_export.R (236 lines)
- python/pub_figure_rasterize.py (53 lines)
- tests/test_pub_figure_export.R (75 lines)

## Full contents

======= BEGIN R/pub_figure_export.R =======
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
  cmd <- paste(
    "python3",
    shQuote(script),
    "--pdf", shQuote(pdf_path),
    "--png", shQuote(png_path),
    "--tiff", shQuote(tiff_path),
    "--dpi", as.character(as.integer(dpi)[1L])
  )
  err <- tempfile()
  on.exit(unlink(err), add = TRUE)
  status <- system(paste(cmd, "2>", shQuote(err)))
  if (!is.null(status) && status != 0) {
    stop(paste(readLines(err, warn = FALSE), collapse = "\n"), call. = FALSE)
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
======= END R/pub_figure_export.R =======

======= BEGIN python/pub_figure_rasterize.py =======
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
======= END python/pub_figure_rasterize.py =======

======= BEGIN tests/test_pub_figure_export.R =======
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
chk <- system(
  paste(
    "python3 -c",
    shQuote(sprintf(
      "from PIL import Image; im=Image.open(%s); print(im.info.get('compression'))",
      shQuote(tiff_path)
    ))
  ),
  intern = TRUE
)
stopifnot(any(grepl("tiff_lzw|lzw", chk, ignore.case = TRUE)))

unlink(fd, recursive = TRUE)
cat("test_pub_figure_export: OK\n")
======= END tests/test_pub_figure_export.R =======
