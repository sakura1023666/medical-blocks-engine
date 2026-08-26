# Whole-branch review package — pub figures formats

No git — package lists deliverables.


Modified (key):
- R/dual_db_combine_figures.R
- R/incidence_dual_batch_runner.R
- R/pipeline_runner.R
- Blocks/55_competing_risk_full/18block_competing_pub_export.R
- Blocks/54_cross_lagged_full/phases/collect_summary_result*.sh
- configs/templates/config_*_dual_batch.template.R
- tests/test_result_review_guards.R
- docs/Blocks_catalog.md


## New files (full)


======= BEGIN R/pub_figure_export.R (236 lines) =======

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


======= BEGIN python/pub_figure_rasterize.py (53 lines) =======

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


======= BEGIN tests/test_pub_figure_export.R (75 lines) =======

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


======= BEGIN R/dual_db_compose_n_panel.py (244 lines) =======

#!/usr/bin/env python3
"""Vector N-panel figure compose: place N PDF pages in a 1xN row or 2x2 grid (N==4).

Preserves text as editable PDF operators (no raster). Labels use Times-Roman
(standard PDF font; maps to Times New Roman appearance).
"""
from __future__ import annotations

import argparse
import sys
from io import BytesIO

from pypdf import PdfReader, PdfWriter, Transformation, PageObject


def _page_wh(page) -> tuple[float, float]:
    box = page.mediabox
    return float(box.width), float(box.height)


def _label_overlay_pdf(
    width: float,
    height: float,
    items: list[tuple[str, float, float, float]],
    font_size: float,
) -> PdfReader:
    """Build a 1-page PDF with Times-Roman text via reportlab if available, else raw content."""
    try:
        from reportlab.pdfgen import canvas
        from reportlab.pdfbase import pdfmetrics
        from reportlab.pdfbase.ttfonts import TTFont
        import os

        buf = BytesIO()
        c = canvas.Canvas(buf, pagesize=(width, height))
        font_name = "Times-Bold"
        for cand in (
            "/usr/share/fonts/truetype/msttcorefonts/Times_New_Roman_Bold.ttf",
            "/usr/share/fonts/truetype/msttcorefonts/Times_New_Roman.ttf",
            "/usr/share/fonts/truetype/msttcorefonts/timesbd.ttf",
            "/usr/share/fonts/truetype/msttcorefonts/times.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf",
            "/usr/share/fonts/opentype/liberation/LiberationSerif-Bold.ttf",
        ):
            if os.path.isfile(cand):
                try:
                    pdfmetrics.registerFont(TTFont("TNREmbed", cand))
                    font_name = "TNREmbed"
                    break
                except Exception:
                    pass
        c.setFont(font_name, font_size)
        for text, x, y, _just in items:
            c.drawString(x, y, text)
        c.save()
        buf.seek(0)
        return PdfReader(buf)
    except Exception:
        def esc(s: str) -> str:
            return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")

        streams = []
        for text, x, y, _just in items:
            streams.append(
                f"BT /F1 {font_size:.2f} Tf {x:.2f} {y:.2f} Td ({esc(text)}) Tj ET"
            )
        content = "\n".join(streams)
        from pypdf.generic import (
            DictionaryObject,
            NameObject,
            DecodedStreamObject,
        )

        writer = PdfWriter()
        page = writer.add_blank_page(width=width, height=height)
        font_dict = DictionaryObject(
            {
                NameObject("/Type"): NameObject("/Font"),
                NameObject("/Subtype"): NameObject("/Type1"),
                NameObject("/BaseFont"): NameObject("/Times-Bold"),
            }
        )
        font_ref = writer._add_object(font_dict)
        resources = DictionaryObject(
            {NameObject("/Font"): DictionaryObject({NameObject("/F1"): font_ref})}
        )
        page[NameObject("/Resources")] = resources
        stream = DecodedStreamObject()
        stream.set_data(content.encode("latin-1", errors="replace"))
        page[NameObject("/Contents")] = writer._add_object(stream)
        out = BytesIO()
        writer.write(out)
        out.seek(0)
        return PdfReader(out)


def _grid_shape(n: int) -> tuple[int, int]:
    """Return (cols, rows). N==4 -> 2x2; otherwise 1xN row."""
    if n == 4:
        return 2, 2
    return n, 1


def compose(
    paths: list[str],
    out_path: str,
    labels: list[str] | None = None,
    layout: str = "side",
    label_h_pt: float = 28.0,
    margin_pt: float = 18.0,
    gap_pt: float = 18.0,
    font_size: float = 14.0,
    center: bool = True,
) -> None:
    n = len(paths)
    if n < 2:
        raise SystemExit("need at least 2 input PDFs")
    if labels is None:
        labels = [f"{chr(65 + i)}." for i in range(n)]
    if len(labels) != n:
        raise SystemExit("labels count must match inputs")

    readers = [PdfReader(p) for p in paths]
    pages = []
    sizes = []
    for r in readers:
        if not r.pages:
            raise SystemExit("empty PDF page")
        pages.append(r.pages[0])
        sizes.append(_page_wh(pages[-1]))

    layout = (layout or "side").lower()
    cols, rows = _grid_shape(n)
    if layout == "grid":
        cols, rows = 2, 2

    # Equal-height panels within each row; rows stacked vertically.
    row_groups: list[list[int]] = []
    idx = 0
    for _r in range(rows):
        row_groups.append(list(range(idx, min(idx + cols, n))))
        idx += cols

    row_heights: list[float] = []
    row_widths: list[float] = []
    scaled: list[tuple[float, float, float, float]] = []  # w, h, sx, sy per panel

    for group in row_groups:
        panel_h = max(sizes[i][1] for i in group)
        row_w = 0.0
        for i in group:
            w, h = sizes[i]
            sx = sy = panel_h / h
            sw = w * sx
            scaled.append((sw, panel_h, sx, sy))
            row_w += sw
        row_w += gap_pt * max(0, len(group) - 1)
        row_heights.append(label_h_pt + panel_h)
        row_widths.append(row_w)

    content_w = max(row_widths)
    content_h = sum(row_heights) + gap_pt * max(0, rows - 1)
    total_w = content_w + 2 * margin_pt
    total_h = content_h + 2 * margin_pt

    max_w = 22 * 72.0
    if total_w > max_w:
        sc = max_w / total_w
        total_w = max_w
        content_w *= sc
        content_h *= sc
        gap_pt *= sc
        margin_pt *= sc
        label_h_pt *= sc
        scaled = [(w * sc, h * sc, sx * sc, sy * sc) for w, h, sx, sy in scaled]
        row_heights = [rh * sc for rh in row_heights]
        row_widths = [rw * sc for rw in row_widths]

    page = PageObject.create_blank_page(width=total_w, height=total_h)
    if center:
        x0 = (total_w - content_w) / 2.0
        y0 = (total_h - content_h) / 2.0
    else:
        x0 = margin_pt
        y0 = margin_pt

    label_items: list[tuple[str, float, float, float]] = []
    si = 0
    y_top = y0 + content_h
    for ri, group in enumerate(row_groups):
        row_h = row_heights[ri]
        row_w = row_widths[ri]
        x_row = x0 + (content_w - row_w) / 2.0
        y_row = y_top - row_h
        x_cur = x_row
        for j, pi in enumerate(group):
            sw, ph, sx, sy = scaled[si]
            si += 1
            page.merge_transformed_page(
                pages[pi], Transformation().scale(sx, sy).translate(x_cur, y_row)
            )
            lab_y = y_row + ph + (label_h_pt - font_size) * 0.55
            label_items.append((labels[pi], x_cur + sw * 0.02, lab_y, 0.0))
            x_cur += sw + gap_pt
        y_top = y_row - gap_pt

    overlay = _label_overlay_pdf(total_w, total_h, label_items, font_size)
    page.merge_page(overlay.pages[0])

    writer = PdfWriter()
    writer.add_page(page)
    with open(out_path, "wb") as f:
        writer.write(f)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    p.add_argument("--inputs", nargs="+", required=True)
    p.add_argument("--labels", nargs="*", default=[])
    p.add_argument("--layout", default="side")
    p.add_argument("--label-h-pt", type=float, default=28.0)
    p.add_argument("--margin-pt", type=float, default=18.0)
    p.add_argument("--gap-pt", type=float, default=18.0)
    p.add_argument("--font-size", type=float, default=14.0)
    p.add_argument("--center", action="store_true", default=True)
    p.add_argument("--no-center", action="store_true", default=False)
    args = p.parse_args()
    labels = args.labels if args.labels else None
    compose(
        args.inputs,
        args.out,
        labels=labels,
        layout=args.layout,
        label_h_pt=args.label_h_pt,
        margin_pt=args.margin_pt,
        gap_pt=args.gap_pt,
        font_size=args.font_size,
        center=not bool(args.no_center),
    )


if __name__ == "__main__":
    main()


======= END R/dual_db_compose_n_panel.py =======


======= BEGIN tests/test_dual_db_combine_n_panel.R (59 lines) =======

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

# figures_dir regression: cross-lagged summary_result/figure (not index_root/Figures)
ix2 <- tempfile("ix_figdir_")
fig_sr <- file.path(ix2, "summary_result", "figure")
dir.create(fig_sr, recursive = TRUE)
make_min_pdf(file.path(fig_sr, "Figure 2-eICU. RCS plot.pdf"))
make_min_pdf(file.path(fig_sr, "Figure 2-MIMIC. RCS plot.pdf"))
make_min_pdf(file.path(fig_sr, "Figure 2-HRS. RCS plot.pdf"))

cfg2 <- list(
  dual_db = list(
    combine_figures = list(enable = TRUE, remove_singles = TRUE, dpi = 72L),
    primary = list(name = "eICU"),
    secondary = list(name = "MIMIC"),
    tertiary = list(name = "HRS")
  )
)
dual_db_combine_paired_figures(ix2, cfg2, figures_dir = fig_sr)
stopifnot(file.exists(file.path(fig_sr, "Figure 2. RCS plot.pdf")))
stopifnot(!file.exists(file.path(fig_sr, "Figure 2-eICU. RCS plot.pdf")))
stopifnot(!file.exists(file.path(fig_sr, "Figure 2-MIMIC. RCS plot.pdf")))
stopifnot(!file.exists(file.path(fig_sr, "Figure 2-HRS. RCS plot.pdf")))
stopifnot(!dir.exists(file.path(ix2, "Figures")))
unlink(ix2, recursive = TRUE)

cat("test_dual_db_combine_n_panel: OK\n")


======= END tests/test_dual_db_combine_n_panel.R =======


======= BEGIN tests/test_cross_lagged_export_summary_figures.R (72 lines) =======

# tests/test_cross_lagged_export_summary_figures.R
# Regression: cross-lagged summary_result/figure mosaic + pub export phase script

root <- normalizePath(getwd())
if (!file.exists(file.path(root, "R/utils.R"))) {
  cand <- normalizePath(file.path(".."), winslash = "/")
  if (file.exists(file.path(cand, "R/utils.R"))) root <- cand
}
source(file.path(root, "R/utils.R"), local = FALSE)

make_min_pdf <- function(path) {
  grDevices::pdf(path, width = 3, height = 2, onefile = TRUE)
  plot.new()
  title(basename(path))
  grDevices::dev.off()
}

study_root <- tempfile("cl_export_test_")
fig <- file.path(study_root, "summary_result", "figure")
dir.create(fig, recursive = TRUE)

make_min_pdf(file.path(fig, "Figure 2-CHARLS. RCS plot.pdf"))
make_min_pdf(file.path(fig, "Figure 2-ELSA. RCS plot.pdf"))
make_min_pdf(file.path(fig, "Figure 2-HRS. RCS plot.pdf"))

writeLines(
  "main_grouping=quartile",
  file.path(study_root, "phase3_relock_acceptance.txt")
)

phase_script <- file.path(
  root, "Blocks/54_cross_lagged_full/phases/export_summary_figures.R"
)
stopifnot(file.exists(phase_script))

on.exit(unlink(study_root, recursive = TRUE), add = TRUE)

old_mb <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = NA_character_)
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)
on.exit({
  if (is.na(old_mb)) Sys.unsetenv("MEDICAL_BLOCKS_ROOT") else Sys.setenv(MEDICAL_BLOCKS_ROOT = old_mb)
}, add = TRUE)

run_out <- system2(
  "Rscript",
  c(phase_script, study_root),
  stdout = TRUE,
  stderr = TRUE
)
if (!is.null(attr(run_out, "status")) && attr(run_out, "status") != 0L) {
  stop(
    "export_summary_figures.R failed:\n",
    paste(run_out, collapse = "\n"),
    call. = FALSE
  )
}

combined_stem <- "Figure 2. RCS plot"
stopifnot(file.exists(file.path(fig, "pdf", paste0(combined_stem, ".pdf"))))
stopifnot(file.exists(file.path(fig, "png", paste0(combined_stem, ".png"))))
stopifnot(file.exists(file.path(fig, "tiff", paste0(combined_stem, ".tiff"))))
stopifnot(file.exists(file.path(fig, "image_information", paste0(combined_stem, ".md"))))

loose <- list.files(fig, pattern = "\\.pdf$", ignore.case = TRUE)
stopifnot(length(loose) == 0L)

stopifnot(!file.exists(file.path(fig, "Figure 2-CHARLS. RCS plot.pdf")))
stopifnot(!file.exists(file.path(fig, "pdf", "Figure 2-CHARLS. RCS plot.pdf")))
stopifnot(!file.exists(file.path(fig, "Figure 2-ELSA. RCS plot.pdf")))
stopifnot(!file.exists(file.path(fig, "Figure 2-HRS. RCS plot.pdf")))

cat("test_cross_lagged_export_summary_figures: OK\n")


======= END tests/test_cross_lagged_export_summary_figures.R =======


======= BEGIN Blocks/54_cross_lagged_full/phases/export_summary_figures.R (95 lines) =======

#!/usr/bin/env Rscript
# 交叉滞后 summary_result/figure：多库拼图 + 四目录发表导出
args <- commandArgs(trailingOnly = TRUE)
study_root <- as.character(args[[1L]] %||% "")[1L]
if (!nzchar(study_root) || !dir.exists(study_root)) {
  stop("need existing study_root as first argument", call. = FALSE)
}

eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(eng)) {
  cand <- normalizePath(file.path(study_root, "../.."), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "R/utils.R"))) {
    eng <- cand
  } else {
    eng <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  }
}

source(file.path(eng, "R/utils.R"), local = FALSE)
source(file.path(eng, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(eng, "R/pub_figure_export.R"), local = FALSE)
if (file.exists(file.path(eng, "R/cross_lagged_study_meta.R"))) {
  source(file.path(eng, "R/cross_lagged_study_meta.R"), local = FALSE)
}

fig <- file.path(study_root, "summary_result", "figure")
if (!dir.exists(fig)) {
  message("summary_result/figure 不存在，跳过 mosaic/export")
  quit(save = "no", status = 0)
}
dir.create(fig, recursive = TRUE, showWarnings = FALSE)

meta_g <- ""
if (exists("cross_lagged_study_meta", mode = "function")) {
  meta_g <- tryCatch(
    as.character(cross_lagged_study_meta(study_root)$grouping %||% "")[1L],
    error = function(e) ""
  )
}
if (!nzchar(meta_g)) {
  acc <- file.path(study_root, "phase3_relock_acceptance.txt")
  if (file.exists(acc)) {
    mg <- grep("^main_grouping=", readLines(acc, warn = FALSE), value = TRUE)
    if (length(mg)) meta_g <- sub("^main_grouping=", "", mg[1L])
  }
}

known_dbs <- c("CHARLS", "ELSA", "HRS", "NHANES", "CLHLS", "SHARE")
pdfs <- list.files(fig, pattern = "\\.pdf$", ignore.case = TRUE)
dbs <- character(0)
for (db in known_dbs) {
  if (any(grepl(paste0("-", db, "\\."), pdfs, ignore.case = TRUE))) {
    dbs <- c(dbs, db)
  }
}
if (exists("cross_lagged_study_meta", mode = "function")) {
  sm <- tryCatch(cross_lagged_study_meta(study_root), error = function(e) NULL)
  if (!is.null(sm)) {
    pref <- unique(c(sm$cohorts_xs %||% character(0), sm$cohorts_long %||% character(0)))
    pref <- pref[pref %in% dbs]
    dbs <- unique(c(pref, setdiff(dbs, pref)))
  }
}
dbs <- dbs[nzchar(dbs)]

cfg <- list(
  dual_db = list(
    combine_figures = list(enable = length(dbs) >= 2L, remove_singles = TRUE, dpi = 200L),
    databases = dbs,
    primary = list(name = if (length(dbs)) dbs[[1L]] else "primary"),
    secondary = list(name = if (length(dbs) >= 2L) dbs[[2L]] else "secondary"),
    tertiary = list(name = if (length(dbs) >= 3L) dbs[[3L]] else "")
  ),
  pub_figures = list(formats_dir = TRUE, dpi = 300L, write_image_information = TRUE)
)

tryCatch(
  dual_db_combine_paired_figures(study_root, cfg, figures_dir = fig),
  error = function(e) message("combine 跳过: ", conditionMessage(e))
)

tryCatch(
  export_pub_figures(
    fig,
    meta = list(
      databases = dbs,
      combined = length(dbs) >= 2L,
      grouping = meta_g
    ),
    config = cfg
  ),
  error = function(e) message("export 跳过: ", conditionMessage(e))
)

message("export_summary_figures: ", fig)


======= END Blocks/54_cross_lagged_full/phases/export_summary_figures.R =======


======= BEGIN docs/superpowers/specs/2026-08-20-pub-figures-formats-and-image-information-design.md (197 lines) =======

# 发表图三格式目录 + 多库拼图 + image_information

日期：2026-08-20  
状态：已批准；实现计划见 `docs/superpowers/plans/2026-08-20-pub-figures-formats-and-image-information.md`  
范围：所有会把发表图汇总到 `Figures/`（或交叉滞后 `summary_result/figure`）的套路：发病、预后、机器学习 dual-batch、交叉滞后、竞争风险、CRM/IPW/中介等。

## 1. 目标

以后跑任何现有套路：

1. **多库必须拼图**：同一图号、不同库的发表图拼成一张（无库标签文件名），再进入汇总交付。
2. **单库不拼图**：该库终稿直接进入汇总交付。
3. **无论单库/多库**，汇总图目录顶层只保留四个子目录：
   - `pdf/`
   - `png/`
   - `tiff/`
   - `image_information/`
4. 三种栅格/矢量格式**同名不同扩展名**；TIFF 使用 **LZW 压缩**。
5. 每张定稿图一份 Markdown，描述该图在讲什么，并附可拿到的 N / 结局 / 暴露。

## 2. 已确认决策

| 项 | 决定 |
|----|------|
| 四目录 | 单库、多库一律创建 |
| 多库拼图 | 强制；复用并扩展现有 `dual_db_combine_paired_figures` |
| 单库拼图 | 不拼 |
| 汇总顶层 | 只有上述四目录，不再直接放图文件 |
| 分库底稿 | 不进汇总（`remove_singles`）；可留在 `<DB>/Figures` 与 `step*/Figures` |
| TIFF | 默认 300 dpi，压缩 LZW，RGB |
| PNG | 与 TIFF 同 DPI |
| PDF | 仍为矢量主交付（拼图优先矢量路径） |
| 图信息 | 每图一份 md + 总目录 `README.md` |
| 图信息内容 | 图号/图题、这张图描述的信息、N/结局/暴露（有则写） |
| 不写入 md | 完整 HR/OR 结果表（避免与主表重复） |

## 3. 非目标

- 不改各分析 block 内部多面板（SHAP cowplot、RCS patchwork 等）；那些仍是单库底稿。
- 不把 step 级中间图强制三联导出。
- 不在缺配对时让整条流水线失败（告警；汇总仍不留带库标签单图）。
- 不把 `Figure Missing Value Overview*` 纳入拼图或四目录。
- 不二次拼已经无库标签的合成图（例如总 flowchart）。

## 4. 目录布局

### 4.1 Dual-batch（发病 / 预后 / ML）

```
<output>/by_index/【success】<ix>/
  Figures/
    pdf/
    png/
    tiff/
    image_information/
      README.md
      Figure 1. ….md
  <DB>/Figures/          ← 分库底稿（带库标签 PDF），不搬进汇总四目录
  <DB>/stepNN_*/Figures/
```

交叉滞后汇总目录名为 `summary_result/figure`（单数），规则相同：该目录顶层改为四个子目录，不再散落 PDF/PNG。

竞争风险等根 `Output/Figures/` 同样改造。

### 4.2 文件名

- 定稿 stem 与现有发表命名一致：`Figure N. <caption>` / `Figure SN. <caption>`。
- `pdf/xxx.pdf`、`png/xxx.png`、`tiff/xxx.tiff`、`image_information/xxx.md` 共用同一 `xxx`（含空格与图题，与现网 PDF 文件名去掉扩展名后一致）。
- 多库拼图文件名**不带**库标签、不带 `Combined`。

## 5. 架构

发表层统一收口（方案 A）：block 仍按现状写 PDF；在**汇总目录定稿之后**调用一次导出。

```
各库出图（PDF 底稿）
    → 镜像到汇总 Figures/（可含库标签成对文件）
    → 若库数 ≥ 2：拼图（remove_singles）
    → export_pub_figures(figures_dir, meta)
         扫描顶层定稿 PDF（无库标签）
         写入 pdf/ png/ tiff/
         写 image_information/*.md 与 README.md
         删除 Figures/ 顶层散落图文件
```

分库与 step 目录不跑 `export_pub_figures`。

## 6. 组件

### 6.1 `export_pub_figures(figures_dir, meta = list())`

新共享函数（建议放在 `R/pub_figure_export.R`，由 `utils.R` 或 finalize 源入）。

输入：已定稿的汇总图目录（此时顶层应是无库标签 PDF，或单库终稿 PDF）。

行为：

1. 确保四个子目录存在。
2. 收集顶层 `Figure*.pdf` / `Figure*.png`（忽略已在子目录内的文件；忽略 Missing Value Overview）。
3. 每个 stem：复制/规范化 PDF → `pdf/`；栅格化 → `png/` 与 `tiff/`（300 dpi；TIFF `compression = "lzw"`；优先 Python/Pillow 或 magick，与现有拼图栅格回退一致）。
4. 写 `image_information/<stem>.md`。
5. 写/覆盖 `image_information/README.md`。
6. 删除顶层散落的图文件（不删除四子目录）。

`meta` 由调用方注入：暴露名、结局、各库 N、grouping、库名单、是否拼图、布局。缺字段在 md 写「未记录」。

配置入口（可选，有默认即可跑）：

```r
config$pub_figures <- list(
  formats_dir = TRUE,          # 总开关，默认 TRUE
  dpi = 300L,
  tiff_compression = "lzw",    # 固定 LZW，不允许课题改成无压缩除非显式测试
  write_image_information = TRUE
)
```

### 6.2 多库拼图：扩展现有 `dual_db_combine_paired_figures`

- **2 库**：行为与 `docs/superpowers/specs/2026-08-12-dual-db-combine-paired-figures-design.md` 相同。
- **3 库及以上**：按 config 库顺序生成 `A. {db}`、`B. {db}`、…；默认一行 N 列，N=4 时可用 2×2。
- 库名单来源优先级：`dual_db` primary/secondary（及已有第三库字段若存在）→ 课题 meta 队列顺序（交叉滞后）→ 文件名中实际出现的库标签（稳定排序兜底）。
- 交叉滞后 `summary_result/figure`、竞争风险发表导出：在收集/编号完成之后调用同一拼图函数（目录参数泛化为「汇总 Figures 目录」+ 库名向量），再调用 `export_pub_figures`。
- Dual-batch 挂点保持：`incidence_batch_finalize_index_outputs` 中 combine 之后、`incidence_batch_curate_index_pub_outputs` 之后（或 curate 末尾）调用导出，避免 curate 再把文件挪回顶层。

若 curate 会重排/改名，**必须先 curate 再 export**。顺序定为：

1. 各库 sync / mirror  
2. combine（多库）  
3. curate / 交叉滞后 reorder 白名单  
4. `export_pub_figures`

### 6.3 图信息 Markdown

每图一份，建议结构：

```markdown
# Figure N. <caption>

## 这张图在讲什么
（2–4 句：图类型、视觉编码、比较对象、多库则说明面板 A/B/… 对应哪一库）

## 标识
- 图号 / 图题
- 文件：`../pdf/…` `../png/…` `../tiff/…`

## 分析上下文
- 暴露 / 结局 / N（多库：分库 N + 合计）
- Grouping（若适用，须与主文 logistic 闸门一致）
- 库名单、是否拼图、布局

## 技术
- 尺寸（inch）、DPI=300、TIFF=LZW、色彩=RGB
```

`这张图在讲什么` 的生成规则（可测试、禁止空话）：

- 优先：`pub_figure` 注册的 caption + 图类型 role（KM / RCS / forest / ROC / SHAP / flowchart / bar …，来自现有 `layout_by_role` 关键词或 kind）。
- 拼图：显式写「面板按库拼接」及库顺序。
- 禁止编造未提供的统计数字；N 只来自 meta/ctx。

`README.md`：表格列 = 图号、图题、是否拼图、pdf 相对路径。

## 7. 数据流与错误处理

| 情况 | 处理 |
|------|------|
| 单库 | 跳过 combine；export 四目录 |
| 多库配对完整 | 拼图 → remove_singles → export |
| 多库缺一侧 | 与现网拼图一致：cli 告警，保留可得到的一侧为**无库标签**终稿并进入 export；带库标签底稿不留在汇总顶层 |
| 栅格化失败 | PDF 仍写入 `pdf/`；png/tiff 告警；md 注明缺失格式 |
| 无任何发表图 | 仍创建四空目录 + 空 README，避免下游脚本找不到路径 |
| TIFF 设备不可用 | 失败应可见（warning + 日志），不静默改成未压缩 TIFF |

## 8. 测试

- 单库假 PDF 两张：export 后顶层无散落文件；三格式同 stem；md 含图题；README 两行。
- 双库成对 PDF：combine 后无 `-DB` 文件；四目录只有无标签拼图；md 写明 A/B 库名。
- 三库成对：一行三列或约定网格；三个面板标签。
- TIFF 文件头/ magick 信息含 LZW（或 Pillow `compression == "tiff_lzw"`）。
- 交叉滞后路径名 `figure/`（单数）同样适用。
- 回归：现有 `tests/test_result_review_guards.R` 中 dual combine 用例在 export 之后仍「汇总无分库单图」。

## 9. 实现入口（计划阶段再拆任务）

- 新：`R/pub_figure_export.R`（`export_pub_figures` + md 渲染）
- 改：`R/dual_db_combine_figures.R`（≥3 库布局）
- 改：`R/incidence_dual_batch_runner.R` finalize 顺序
- 改：交叉滞后 `collect_summary_result*.sh` 或对应 R collect：收集后 combine（若多队列）+ export
- 改：竞争风险 `18block_competing_pub_export.R`（及同类发表收口）
- 模板：`pub_figures` 默认块写入 dual / 单流水线模板
- 测试：`tests/test_pub_figure_export.R`

## 10. 与分位铁律的关系

change / 敏感性图若进入汇总四目录，md 中 Grouping 必须来自课题 `cross_lagged_study_meta()$grouping` 或调用方注入的主文闸门，禁止在导出层写死 tertile。


======= END docs/superpowers/specs/2026-08-20-pub-figures-formats-and-image-information-design.md =======


======= BEGIN docs/superpowers/plans/2026-08-20-pub-figures-formats-and-image-information.md (931 lines) =======

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
stopifnot(file.exists(file.path(fd, "image_information"
... [truncated for package size] ...


======= END docs/superpowers/plans/2026-08-20-pub-figures-formats-and-image-information.md =======


## Snippets: R/pipeline_runner.R

--- L633 ---

630:}
631:
632:#' Figures 目录是否属于 dual-batch 分库槽位（run_pipeline 收口 export 应跳过）
633:pipeline_figures_is_dual_slot <- function(figs, config) {
634:  dual <- config$dual_db %||% list()
635:  cur <- dual$current_db
636:  if (!is.null(cur) && nzchar(as.character(cur)[1L])) return(TRUE)
637:  if (!isTRUE(dual$enable)) return(FALSE)
638:
639:  figs_norm <- normalizePath(figs, winslash = "/", mustWork = FALSE)
640:  db_names <- character(0)
641:  for (key in c("primary", "secondary", "tertiary")) {
642:    nm <- (dual[[key]] %||% list())$name
643:    if (!is.null(nm) && nzchar(as.character(nm)[1L])) {
644:      db_names <- c(db_names, as.character(nm)[1L])
645:    }
646:  }
647:  dbs <- dual$databases
648:  if (!is.null(dbs) && length(dbs)) db_names <- c(db_names, as.character(dbs))
649:  if (exists("dual_db_sanitize_path_name", mode = "function")) {
650:    db_names <- unique(vapply(db_names, dual_db_sanitize_path_name, character(1L)))
651:  } else {
652:    db_names <- unique(trimws(as.character(db_names)))
653:  }
654:  db_names <- db_names[nzchar(db_names)]
655:  parent_dir <- basename(dirname(figs_norm))
656:  if (length(db_names) && parent_dir %in% db_names) return(TRUE)
657:


--- L883 ---

880:      }
881:    }
882:  }
883:  if (exists("export_pub_figures", mode = "function") ||
884:      file.exists(file.path(root, "R/pub_figure_export.R"))) {
885:    if (!exists("export_pub_figures", mode = "function")) {
886:      source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
887:    }
888:    out_root <- ctx$root_output_dir %||% config$project$output_dir
889:    figs <- file.path(out_root, "Figures")
890:    is_dual_slot <- pipeline_figures_is_dual_slot(figs, config)
891:    if (!isTRUE(is_dual_slot) && dir.exists(figs) && !dir.exists(file.path(figs, "pdf"))) {
892:      tryCatch(
893:        export_pub_figures(figs, meta = list(
894:          exposure = config$project$exposure_var %||% config$project$index_var %||% "",
895:          outcome = config$data$outcome_column %||% "",
896:          databases = config$project$database %||% character(0),
897:          combined = FALSE
898:        ), config = config),
899:        error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
900:      )
901:    }
902:  }
903:  invisible(ctx)
904:}


--- L885 ---

882:  }
883:  if (exists("export_pub_figures", mode = "function") ||
884:      file.exists(file.path(root, "R/pub_figure_export.R"))) {
885:    if (!exists("export_pub_figures", mode = "function")) {
886:      source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
887:    }
888:    out_root <- ctx$root_output_dir %||% config$project$output_dir
889:    figs <- file.path(out_root, "Figures")
890:    is_dual_slot <- pipeline_figures_is_dual_slot(figs, config)
891:    if (!isTRUE(is_dual_slot) && dir.exists(figs) && !dir.exists(file.path(figs, "pdf"))) {
892:      tryCatch(
893:        export_pub_figures(figs, meta = list(
894:          exposure = config$project$exposure_var %||% config$project$index_var %||% "",
895:          outcome = config$data$outcome_column %||% "",
896:          databases = config$project$database %||% character(0),
897:          combined = FALSE
898:        ), config = config),
899:        error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
900:      )
901:    }
902:  }
903:  invisible(ctx)
904:}


--- L890 ---

887:    }
888:    out_root <- ctx$root_output_dir %||% config$project$output_dir
889:    figs <- file.path(out_root, "Figures")
890:    is_dual_slot <- pipeline_figures_is_dual_slot(figs, config)
891:    if (!isTRUE(is_dual_slot) && dir.exists(figs) && !dir.exists(file.path(figs, "pdf"))) {
892:      tryCatch(
893:        export_pub_figures(figs, meta = list(
894:          exposure = config$project$exposure_var %||% config$project$index_var %||% "",
895:          outcome = config$data$outcome_column %||% "",
896:          databases = config$project$database %||% character(0),
897:          combined = FALSE
898:        ), config = config),
899:        error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
900:      )
901:    }
902:  }
903:  invisible(ctx)
904:}


--- L893 ---

890:    is_dual_slot <- pipeline_figures_is_dual_slot(figs, config)
891:    if (!isTRUE(is_dual_slot) && dir.exists(figs) && !dir.exists(file.path(figs, "pdf"))) {
892:      tryCatch(
893:        export_pub_figures(figs, meta = list(
894:          exposure = config$project$exposure_var %||% config$project$index_var %||% "",
895:          outcome = config$data$outcome_column %||% "",
896:          databases = config$project$database %||% character(0),
897:          combined = FALSE
898:        ), config = config),
899:        error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
900:      )
901:    }
902:  }
903:  invisible(ctx)
904:}



## Snippets: R/incidence_dual_batch_runner.R

--- L2107 ---

2104:    incidence_batch_shorten_pub_table_names(td, config)
2105:  }
2106:
2107:  # 发表图四目录导出（pdf/png/tiff + image_information）
2108:  if (!exists("export_pub_figures", mode = "function")) {
2109:    exp_src <- file.path(root, "R", "pub_figure_export.R")
2110:    if (file.exists(exp_src)) source(exp_src, local = FALSE)
2111:  }
2112:  if (exists("export_pub_figures", mode = "function")) {
2113:    figs_dir <- file.path(index_root, "Figures")
2114:    meta <- list(
2115:      exposure = as.character(config$project$exposure_var %||% config$project$index_var %||% ix)[1L],
2116:      outcome = as.character(config$data$outcome_column %||% config$project$outcome %||% "")[1L],
2117:      databases = as.character(db_seq),
2118:      combined = length(db_seq) >= 2L,
2119:      grouping = as.character(
2120:        config$logistic_gate$grouping %||%
2121:          config$project$grouping %||%
2122:          ""
2123:      )[1L]
2124:    )
2125:    tryCatch(
2126:      export_pub_figures(figs_dir, meta = meta, config = config),
2127:      error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
2128:    )
2129:  }
2130:}
2131:


--- L2108 ---

2105:  }
2106:
2107:  # 发表图四目录导出（pdf/png/tiff + image_information）
2108:  if (!exists("export_pub_figures", mode = "function")) {
2109:    exp_src <- file.path(root, "R", "pub_figure_export.R")
2110:    if (file.exists(exp_src)) source(exp_src, local = FALSE)
2111:  }
2112:  if (exists("export_pub_figures", mode = "function")) {
2113:    figs_dir <- file.path(index_root, "Figures")
2114:    meta <- list(
2115:      exposure = as.character(config$project$exposure_var %||% config$project$index_var %||% ix)[1L],
2116:      outcome = as.character(config$data$outcome_column %||% config$project$outcome %||% "")[1L],
2117:      databases = as.character(db_seq),
2118:      combined = length(db_seq) >= 2L,
2119:      grouping = as.character(
2120:        config$logistic_gate$grouping %||%
2121:          config$project$grouping %||%
2122:          ""
2123:      )[1L]
2124:    )
2125:    tryCatch(
2126:      export_pub_figures(figs_dir, meta = meta, config = config),
2127:      error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
2128:    )
2129:  }
2130:}
2131:
2132:# ── 3. 叠加单库数据路径 ────────────────────────────────────────────────────────


--- L2112 ---

2109:    exp_src <- file.path(root, "R", "pub_figure_export.R")
2110:    if (file.exists(exp_src)) source(exp_src, local = FALSE)
2111:  }
2112:  if (exists("export_pub_figures", mode = "function")) {
2113:    figs_dir <- file.path(index_root, "Figures")
2114:    meta <- list(
2115:      exposure = as.character(config$project$exposure_var %||% config$project$index_var %||% ix)[1L],
2116:      outcome = as.character(config$data$outcome_column %||% config$project$outcome %||% "")[1L],
2117:      databases = as.character(db_seq),
2118:      combined = length(db_seq) >= 2L,
2119:      grouping = as.character(
2120:        config$logistic_gate$grouping %||%
2121:          config$project$grouping %||%
2122:          ""
2123:      )[1L]
2124:    )
2125:    tryCatch(
2126:      export_pub_figures(figs_dir, meta = meta, config = config),
2127:      error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
2128:    )
2129:  }
2130:}
2131:
2132:# ── 3. 叠加单库数据路径 ────────────────────────────────────────────────────────
2133:incidence_batch_apply_db_overrides <- function(config, db, root, ix) {
2134:  # 统一槽位：eicu/nhanes/primary → primary；mimic/secondary → secondary
2135:  slot <- if (exists("dual_db_normalize_slot", mode = "function")) {
2136:    dual_db_normalize_slot(db)


--- L2126 ---

2123:      )[1L]
2124:    )
2125:    tryCatch(
2126:      export_pub_figures(figs_dir, meta = meta, config = config),
2127:      error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
2128:    )
2129:  }
2130:}
2131:
2132:# ── 3. 叠加单库数据路径 ────────────────────────────────────────────────────────
2133:incidence_batch_apply_db_overrides <- function(config, db, root, ix) {
2134:  # 统一槽位：eicu/nhanes/primary → primary；mimic/secondary → secondary
2135:  slot <- if (exists("dual_db_normalize_slot", mode = "function")) {
2136:    dual_db_normalize_slot(db)
2137:  } else {
2138:    db0 <- tolower(as.character(db)[1L])
2139:    if (db0 %in% c("nhanes", "nhance", "eicu", "e_icu", "primary")) "nhanes" else "mimic"
2140:  }
2141:  is_pri <- identical(slot, "nhanes") ||
2142:    (exists("dual_db_slot_is_primary", mode = "function") &&
2143:       isTRUE(dual_db_slot_is_primary(slot)))
2144:  db_cfg <- if (is_pri) config$dual_db$primary else config$dual_db$secondary
2145:  config$data$rawdata_path        <- db_cfg$rawdata_path
2146:  config$data$rawdata_obj         <- db_cfg$rawdata_obj
2147:  config$data$id_column           <- db_cfg$id_column
2148:  config$data$outcome_column      <- config$data$outcome_column %||% "Disease_Group"
2149:  config$column_mapping$database_type <- db_cfg$column_mapping_type
2150:  config$project$database         <- db_cfg$name


--- L2127 ---

2124:    )
2125:    tryCatch(
2126:      export_pub_figures(figs_dir, meta = meta, config = config),
2127:      error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
2128:    )
2129:  }
2130:}
2131:
2132:# ── 3. 叠加单库数据路径 ────────────────────────────────────────────────────────
2133:incidence_batch_apply_db_overrides <- function(config, db, root, ix) {
2134:  # 统一槽位：eicu/nhanes/primary → primary；mimic/secondary → secondary
2135:  slot <- if (exists("dual_db_normalize_slot", mode = "function")) {
2136:    dual_db_normalize_slot(db)
2137:  } else {
2138:    db0 <- tolower(as.character(db)[1L])
2139:    if (db0 %in% c("nhanes", "nhance", "eicu", "e_icu", "primary")) "nhanes" else "mimic"
2140:  }
2141:  is_pri <- identical(slot, "nhanes") ||
2142:    (exists("dual_db_slot_is_primary", mode = "function") &&
2143:       isTRUE(dual_db_slot_is_primary(slot)))
2144:  db_cfg <- if (is_pri) config$dual_db$primary else config$dual_db$secondary
2145:  config$data$rawdata_path        <- db_cfg$rawdata_path
2146:  config$data$rawdata_obj         <- db_cfg$rawdata_obj
2147:  config$data$id_column           <- db_cfg$id_column
2148:  config$data$outcome_column      <- config$data$outcome_column %||% "Disease_Group"
2149:  config$column_mapping$database_type <- db_cfg$column_mapping_type
2150:  config$project$database         <- db_cfg$name
2151:  config$project$database_type    <- db_cfg$db_type



## Snippets: Blocks/55_competing_risk_full/18block_competing_pub_export.R

--- L309 ---

306:  }
307:  combined_flag <- length(dbs_have) >= 2L
308:  if (combined_flag) {
309:    if (!exists("dual_db_combine_paired_figures", mode = "function")) {
310:      comb_src <- file.path(root, "R/dual_db_combine_figures.R")
311:      if (file.exists(comb_src)) source(comb_src, local = FALSE)
312:    }
313:    if (exists("dual_db_combine_paired_figures", mode = "function")) {
314:      tryCatch(
315:        dual_db_combine_paired_figures(out_root, cfg, figures_dir = fig_dir),
316:        error = function(e) cli::cli_alert_warning("竞争风险拼图跳过: {e$message}")
317:      )
318:    }
319:  }
320:
321:  if (!exists("export_pub_figures", mode = "function")) {
322:    src <- file.path(root, "R/pub_figure_export.R")
323:    if (file.exists(src)) source(src, local = FALSE)
324:  }
325:  if (exists("export_pub_figures", mode = "function")) {
326:    tryCatch(
327:      export_pub_figures(
328:        fig_dir,
329:        meta = list(
330:          exposure = cfg$project$exposure_var %||% "",
331:          outcome = cfg$data$outcome_column %||% "",
332:          databases = if (combined_flag) dbs_have else (cfg$project$database %||% character(0)),
333:          combined = combined_flag


--- L310 ---

307:  combined_flag <- length(dbs_have) >= 2L
308:  if (combined_flag) {
309:    if (!exists("dual_db_combine_paired_figures", mode = "function")) {
310:      comb_src <- file.path(root, "R/dual_db_combine_figures.R")
311:      if (file.exists(comb_src)) source(comb_src, local = FALSE)
312:    }
313:    if (exists("dual_db_combine_paired_figures", mode = "function")) {
314:      tryCatch(
315:        dual_db_combine_paired_figures(out_root, cfg, figures_dir = fig_dir),
316:        error = function(e) cli::cli_alert_warning("竞争风险拼图跳过: {e$message}")
317:      )
318:    }
319:  }
320:
321:  if (!exists("export_pub_figures", mode = "function")) {
322:    src <- file.path(root, "R/pub_figure_export.R")
323:    if (file.exists(src)) source(src, local = FALSE)
324:  }
325:  if (exists("export_pub_figures", mode = "function")) {
326:    tryCatch(
327:      export_pub_figures(
328:        fig_dir,
329:        meta = list(
330:          exposure = cfg$project$exposure_var %||% "",
331:          outcome = cfg$data$outcome_column %||% "",
332:          databases = if (combined_flag) dbs_have else (cfg$project$database %||% character(0)),
333:          combined = combined_flag
334:        ),


--- L313 ---

310:      comb_src <- file.path(root, "R/dual_db_combine_figures.R")
311:      if (file.exists(comb_src)) source(comb_src, local = FALSE)
312:    }
313:    if (exists("dual_db_combine_paired_figures", mode = "function")) {
314:      tryCatch(
315:        dual_db_combine_paired_figures(out_root, cfg, figures_dir = fig_dir),
316:        error = function(e) cli::cli_alert_warning("竞争风险拼图跳过: {e$message}")
317:      )
318:    }
319:  }
320:
321:  if (!exists("export_pub_figures", mode = "function")) {
322:    src <- file.path(root, "R/pub_figure_export.R")
323:    if (file.exists(src)) source(src, local = FALSE)
324:  }
325:  if (exists("export_pub_figures", mode = "function")) {
326:    tryCatch(
327:      export_pub_figures(
328:        fig_dir,
329:        meta = list(
330:          exposure = cfg$project$exposure_var %||% "",
331:          outcome = cfg$data$outcome_column %||% "",
332:          databases = if (combined_flag) dbs_have else (cfg$project$database %||% character(0)),
333:          combined = combined_flag
334:        ),
335:        config = cfg
336:      ),
337:      error = function(e) cli::cli_alert_warning("发表图导出跳过: {e$message}")


--- L315 ---

312:    }
313:    if (exists("dual_db_combine_paired_figures", mode = "function")) {
314:      tryCatch(
315:        dual_db_combine_paired_figures(out_root, cfg, figures_dir = fig_dir),
316:        error = function(e) cli::cli_alert_warning("竞争风险拼图跳过: {e$message}")
317:      )
318:    }
319:  }
320:
321:  if (!exists("export_pub_figures", mode = "function")) {
322:    src <- file.path(root, "R/pub_figure_export.R")
323:    if (file.exists(src)) source(src, local = FALSE)
324:  }
325:  if (exists("export_pub_figures", mode = "function")) {
326:    tryCatch(
327:      export_pub_figures(
328:        fig_dir,
329:        meta = list(
330:          exposure = cfg$project$exposure_var %||% "",
331:          outcome = cfg$data$outcome_column %||% "",
332:          databases = if (combined_flag) dbs_have else (cfg$project$database %||% character(0)),
333:          combined = combined_flag
334:        ),
335:        config = cfg
336:      ),
337:      error = function(e) cli::cli_alert_warning("发表图导出跳过: {e$message}")
338:    )
339:  }


--- L321 ---

318:    }
319:  }
320:
321:  if (!exists("export_pub_figures", mode = "function")) {
322:    src <- file.path(root, "R/pub_figure_export.R")
323:    if (file.exists(src)) source(src, local = FALSE)
324:  }
325:  if (exists("export_pub_figures", mode = "function")) {
326:    tryCatch(
327:      export_pub_figures(
328:        fig_dir,
329:        meta = list(
330:          exposure = cfg$project$exposure_var %||% "",
331:          outcome = cfg$data$outcome_column %||% "",
332:          databases = if (combined_flag) dbs_have else (cfg$project$database %||% character(0)),
333:          combined = combined_flag
334:        ),
335:        config = cfg
336:      ),
337:      error = function(e) cli::cli_alert_warning("发表图导出跳过: {e$message}")
338:    )
339:  }
340:
341:  cli::cli_alert_success("文献级导出完成: {length(figs)} figures / {length(tabs)} tables")
342:  ctx
343:}
344:
345:register_block("competing_pub_export", block_competing_pub_export, "文献级 Figure/Table 导出")


--- L325 ---

322:    src <- file.path(root, "R/pub_figure_export.R")
323:    if (file.exists(src)) source(src, local = FALSE)
324:  }
325:  if (exists("export_pub_figures", mode = "function")) {
326:    tryCatch(
327:      export_pub_figures(
328:        fig_dir,
329:        meta = list(
330:          exposure = cfg$project$exposure_var %||% "",
331:          outcome = cfg$data$outcome_column %||% "",
332:          databases = if (combined_flag) dbs_have else (cfg$project$database %||% character(0)),
333:          combined = combined_flag
334:        ),
335:        config = cfg
336:      ),
337:      error = function(e) cli::cli_alert_warning("发表图导出跳过: {e$message}")
338:    )
339:  }
340:
341:  cli::cli_alert_success("文献级导出完成: {length(figs)} figures / {length(tabs)} tables")
342:  ctx
343:}
344:
345:register_block("competing_pub_export", block_competing_pub_export, "文献级 Figure/Table 导出")


--- L327 ---

324:  }
325:  if (exists("export_pub_figures", mode = "function")) {
326:    tryCatch(
327:      export_pub_figures(
328:        fig_dir,
329:        meta = list(
330:          exposure = cfg$project$exposure_var %||% "",
331:          outcome = cfg$data$outcome_column %||% "",
332:          databases = if (combined_flag) dbs_have else (cfg$project$database %||% character(0)),
333:          combined = combined_flag
334:        ),
335:        config = cfg
336:      ),
337:      error = function(e) cli::cli_alert_warning("发表图导出跳过: {e$message}")
338:    )
339:  }
340:
341:  cli::cli_alert_success("文献级导出完成: {length(figs)} figures / {length(tabs)} tables")
342:  ctx
343:}
344:
345:register_block("competing_pub_export", block_competing_pub_export, "文献级 Figure/Table 导出")



## Snippets: R/dual_db_combine_figures.R

--- L34 ---

31:    label_cex = as.numeric(cfg$label_cex %||% 1.15)[1L],
32:    primary = as.character((dd$primary %||% list())$name %||% "primary")[1L],
33:    secondary = as.character((dd$secondary %||% list())$name %||% "secondary")[1L],
34:    tertiary = as.character((dd$tertiary %||% list())$name %||% "")[1L],
35:    databases = {
36:      d <- unique(c(
37:        as.character((dd$primary %||% list())$name %||% "")[1L],
38:        as.character((dd$secondary %||% list())$name %||% "")[1L],
39:        as.character((dd$tertiary %||% list())$name %||% "")[1L],
40:        as.character(dd$databases %||% character(0))
41:      ))
42:      d[nzchar(d)]
43:    }
44:  )
45:}
46:
47:.dual_db_panel_label <- function(letter, db, fmt = "A. {db}") {
48:  db <- as.character(db %||% "")[1L]
49:  out <- gsub("{db}", db, fmt, fixed = TRUE)
50:  # 允许配置写成 "A. {db}"；B 面板自动换字母
51:  out <- sub("^[A-Z]\\.", paste0(letter, "."), out)
52:  if (!grepl(paste0("^", letter, "\\."), out)) {
53:    out <- paste0(letter, ". ", db)
54:  }
55:  out
56:}
57:
58:.dual_db_is_missing_overview <- function(bn) {


--- L39 ---

36:      d <- unique(c(
37:        as.character((dd$primary %||% list())$name %||% "")[1L],
38:        as.character((dd$secondary %||% list())$name %||% "")[1L],
39:        as.character((dd$tertiary %||% list())$name %||% "")[1L],
40:        as.character(dd$databases %||% character(0))
41:      ))
42:      d[nzchar(d)]
43:    }
44:  )
45:}
46:
47:.dual_db_panel_label <- function(letter, db, fmt = "A. {db}") {
48:  db <- as.character(db %||% "")[1L]
49:  out <- gsub("{db}", db, fmt, fixed = TRUE)
50:  # 允许配置写成 "A. {db}"；B 面板自动换字母
51:  out <- sub("^[A-Z]\\.", paste0(letter, "."), out)
52:  if (!grepl(paste0("^", letter, "\\."), out)) {
53:    out <- paste0(letter, ". ", db)
54:  }
55:  out
56:}
57:
58:.dual_db_is_missing_overview <- function(bn) {
59:  grepl("Missing\\s*Value\\s*Overview", bn, ignore.case = TRUE)
60:}
61:
62:#' 从文件名解析库标签与配对键
63:#' @return NULL 或 list(db=, key=, layout_hint=)


--- L536 ---

533:  paste0("-(", alt, ")\\.")
534:}
535:
536:.dual_db_compose_n_pdf_vector <- function(paths, labels, out_path, layout = "side",
537:                                          label_cex = 1.15) {
538:  paths <- as.character(paths)
539:  labels <- as.character(labels)
540:  if (length(paths) < 2L) stop("n-panel 拼图至少需要 2 个 PDF", call. = FALSE)
541:  if (length(labels) != length(paths)) {
542:    stop("labels 数量须与 paths 一致", call. = FALSE)
543:  }
544:  py <- Sys.which("python3")
545:  if (!nzchar(py)) py <- Sys.which("python")
546:  if (!nzchar(py)) stop("python3 不可用，无法矢量拼图", call. = FALSE)
547:
548:  script <- .dual_db_find_compose_script("dual_db_compose_n_panel.py")
549:  if (is.null(script)) stop("找不到 dual_db_compose_n_panel.py", call. = FALSE)
550:
551:  tmp_dir <- tempfile("dual_nvec_")
552:  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
553:  on.exit(unlink(tmp_dir, recursive = TRUE, force = TRUE), add = TRUE)
554:  safe_paths <- vapply(seq_along(paths), function(i) {
555:    dst <- file.path(tmp_dir, sprintf("in_%03d.pdf", i))
556:    if (!file.copy(paths[[i]], dst, overwrite = TRUE)) {
557:      stop("无法复制源 PDF 到临时目录", call. = FALSE)
558:    }
559:    dst
560:  }, character(1))


--- L548 ---

545:  if (!nzchar(py)) py <- Sys.which("python")
546:  if (!nzchar(py)) stop("python3 不可用，无法矢量拼图", call. = FALSE)
547:
548:  script <- .dual_db_find_compose_script("dual_db_compose_n_panel.py")
549:  if (is.null(script)) stop("找不到 dual_db_compose_n_panel.py", call. = FALSE)
550:
551:  tmp_dir <- tempfile("dual_nvec_")
552:  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
553:  on.exit(unlink(tmp_dir, recursive = TRUE, force = TRUE), add = TRUE)
554:  safe_paths <- vapply(seq_along(paths), function(i) {
555:    dst <- file.path(tmp_dir, sprintf("in_%03d.pdf", i))
556:    if (!file.copy(paths[[i]], dst, overwrite = TRUE)) {
557:      stop("无法复制源 PDF 到临时目录", call. = FALSE)
558:    }
559:    dst
560:  }, character(1))
561:  out_safe <- file.path(tmp_dir, "out.pdf")
562:
563:  font_size <- max(10, round(12 * as.numeric(label_cex %||% 1.15)[1L], 1))
564:  n_layout <- if (length(paths) == 4L) "grid" else "side"
565:  args <- c(
566:    script,
567:    "--out", out_safe,
568:    "--inputs", safe_paths,
569:    "--labels", labels,
570:    "--layout", n_layout,
571:    "--font-size", as.character(font_size)
572:  )


--- L549 ---

546:  if (!nzchar(py)) stop("python3 不可用，无法矢量拼图", call. = FALSE)
547:
548:  script <- .dual_db_find_compose_script("dual_db_compose_n_panel.py")
549:  if (is.null(script)) stop("找不到 dual_db_compose_n_panel.py", call. = FALSE)
550:
551:  tmp_dir <- tempfile("dual_nvec_")
552:  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
553:  on.exit(unlink(tmp_dir, recursive = TRUE, force = TRUE), add = TRUE)
554:  safe_paths <- vapply(seq_along(paths), function(i) {
555:    dst <- file.path(tmp_dir, sprintf("in_%03d.pdf", i))
556:    if (!file.copy(paths[[i]], dst, overwrite = TRUE)) {
557:      stop("无法复制源 PDF 到临时目录", call. = FALSE)
558:    }
559:    dst
560:  }, character(1))
561:  out_safe <- file.path(tmp_dir, "out.pdf")
562:
563:  font_size <- max(10, round(12 * as.numeric(label_cex %||% 1.15)[1L], 1))
564:  n_layout <- if (length(paths) == 4L) "grid" else "side"
565:  args <- c(
566:    script,
567:    "--out", out_safe,
568:    "--inputs", safe_paths,
569:    "--labels", labels,
570:    "--layout", n_layout,
571:    "--font-size", as.character(font_size)
572:  )
573:  if (grepl("Subgroup\\s*Forest", basename(out_path), ignore.case = TRUE)) {


--- L598 ---

595:  invisible(out_path)
596:}
597:
598:.dual_db_compose_n_pdf_raster <- function(paths, labels, out_path, layout = "side",
599:                                          dpi = 200L, label_cex = 1.15) {
600:  paths <- as.character(paths)
601:  labels <- as.character(labels)
602:  n <- length(paths)
603:  if (n < 2L) stop("n-panel 栅格拼图至少需要 2 个 PDF", call. = FALSE)
604:  imgs <- lapply(paths, function(p) .dual_db_pdf_to_png(p, dpi = dpi))
605:  on.exit({
606:    for (im in imgs) unlink(im$unlink_dir, recursive = TRUE, force = TRUE)
607:  }, add = TRUE)
608:  infos <- lapply(imgs, function(im) .dual_db_png_info(im$path))
609:
610:  dpi <- max(72L, as.integer(dpi)[1L])
611:  label_h_in <- 0.45
612:  margin_in <- 0.35
613:  gap_in <- 0.25
614:
615:  cols <- if (n == 4L) 2L else n
616:  rows <- if (n == 4L) 2L else 1L
617:  grid <- vector("list", n)
618:  idx <- 1L
619:  for (r in seq_len(rows)) {
620:    row_idx <- idx:min(idx + cols - 1L, n)
621:    panel_h <- max(vapply(infos[row_idx], function(x) x$h / dpi, numeric(1)))
622:    row_w <- 0


--- L694 ---

691:  invisible(out_path)
692:}
693:
694:.dual_db_compose_n_pdf <- function(paths, labels, out_path, layout = "side",
695:                                     dpi = 200L, label_cex = 1.15) {
696:  ok_vec <- tryCatch({
697:    .dual_db_compose_n_pdf_vector(
698:      paths, labels, out_path,
699:      layout = layout, label_cex = label_cex
700:    )
701:    TRUE
702:  }, error = function(e) {
703:    cli::cli_alert_warning("n-panel 矢量拼图不可用，回退栅格: {conditionMessage(e)}")
704:    FALSE
705:  })
706:  if (isTRUE(ok_vec) && file.exists(out_path) &&
707:      isTRUE((file.info(out_path)$size %||% 0) > 500)) {
708:    return(invisible(out_path))
709:  }
710:  .dual_db_compose_n_pdf_raster(
711:    paths, labels, out_path,
712:    layout = layout, dpi = dpi, label_cex = label_cex
713:  )
714:}
715:
716:#' 汇总目录双库成对发表图拼图
717:#'
718:#' @param index_root by_index/<ix> 根目录


--- L697 ---

694:.dual_db_compose_n_pdf <- function(paths, labels, out_path, layout = "side",
695:                                     dpi = 200L, label_cex = 1.15) {
696:  ok_vec <- tryCatch({
697:    .dual_db_compose_n_pdf_vector(
698:      paths, labels, out_path,
699:      layout = layout, label_cex = label_cex
700:    )
701:    TRUE
702:  }, error = function(e) {
703:    cli::cli_alert_warning("n-panel 矢量拼图不可用，回退栅格: {conditionMessage(e)}")
704:    FALSE
705:  })
706:  if (isTRUE(ok_vec) && file.exists(out_path) &&
707:      isTRUE((file.info(out_path)$size %||% 0) > 500)) {
708:    return(invisible(out_path))
709:  }
710:  .dual_db_compose_n_pdf_raster(
711:    paths, labels, out_path,
712:    layout = layout, dpi = dpi, label_cex = label_cex
713:  )
714:}
715:
716:#' 汇总目录双库成对发表图拼图
717:#'
718:#' @param index_root by_index/<ix> 根目录
719:#' @param config 完整 config（读 dual_db$combine_figures / primary/secondary$name）
720:#' @param figures_dir 可选；默认 `file.path(index_root, "Figures")`，交叉滞后可传 `summary_result/figure`
721:#' @return invisible list(combined=, deleted=, skipped=)


--- L710 ---

707:      isTRUE((file.info(out_path)$size %||% 0) > 500)) {
708:    return(invisible(out_path))
709:  }
710:  .dual_db_compose_n_pdf_raster(
711:    paths, labels, out_path,
712:    layout = layout, dpi = dpi, label_cex = label_cex
713:  )
714:}
715:
716:#' 汇总目录双库成对发表图拼图
717:#'
718:#' @param index_root by_index/<ix> 根目录
719:#' @param config 完整 config（读 dual_db$combine_figures / primary/secondary$name）
720:#' @param figures_dir 可选；默认 `file.path(index_root, "Figures")`，交叉滞后可传 `summary_result/figure`
721:#' @return invisible list(combined=, deleted=, skipped=)
722:dual_db_combine_paired_figures <- function(index_root, config, figures_dir = NULL) {
723:  cfg <- .dual_db_combine_cfg(config)
724:  if (!isTRUE(cfg$enable)) return(invisible(list(combined = character(), deleted = character(), skipped = character())))
725:
726:  figs <- if (!is.null(figures_dir) && nzchar(as.character(figures_dir)[1L])) {
727:    as.character(figures_dir)[1L]
728:  } else {
729:    file.path(index_root, "Figures")
730:  }
731:  if (!dir.exists(figs)) {
732:    return(invisible(list(combined = character(), deleted = character(), skipped = character())))
733:  }
734:


--- L720 ---

717:#'
718:#' @param index_root by_index/<ix> 根目录
719:#' @param config 完整 config（读 dual_db$combine_figures / primary/secondary$name）
720:#' @param figures_dir 可选；默认 `file.path(index_root, "Figures")`，交叉滞后可传 `summary_result/figure`
721:#' @return invisible list(combined=, deleted=, skipped=)
722:dual_db_combine_paired_figures <- function(index_root, config, figures_dir = NULL) {
723:  cfg <- .dual_db_combine_cfg(config)
724:  if (!isTRUE(cfg$enable)) return(invisible(list(combined = character(), deleted = character(), skipped = character())))
725:
726:  figs <- if (!is.null(figures_dir) && nzchar(as.character(figures_dir)[1L])) {
727:    as.character(figures_dir)[1L]
728:  } else {
729:    file.path(index_root, "Figures")
730:  }
731:  if (!dir.exists(figs)) {
732:    return(invisible(list(combined = character(), deleted = character(), skipped = character())))
733:  }
734:
735:  pdfs <- list.files(figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
736:  deleted <- character(0)
737:  if (isTRUE(cfg$drop_missing_overview)) {
738:    miss <- pdfs[.dual_db_is_missing_overview(basename(pdfs))]
739:    if (length(miss)) {
740:      unlink(miss)
741:      deleted <- c(deleted, basename(miss))
742:      cli::cli_alert_info("已删除缺失概览图 {length(miss)} 个")
743:      pdfs <- list.files(figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
744:    }


--- L722 ---

719:#' @param config 完整 config（读 dual_db$combine_figures / primary/secondary$name）
720:#' @param figures_dir 可选；默认 `file.path(index_root, "Figures")`，交叉滞后可传 `summary_result/figure`
721:#' @return invisible list(combined=, deleted=, skipped=)
722:dual_db_combine_paired_figures <- function(index_root, config, figures_dir = NULL) {
723:  cfg <- .dual_db_combine_cfg(config)
724:  if (!isTRUE(cfg$enable)) return(invisible(list(combined = character(), deleted = character(), skipped = character())))
725:
726:  figs <- if (!is.null(figures_dir) && nzchar(as.character(figures_dir)[1L])) {
727:    as.character(figures_dir)[1L]
728:  } else {
729:    file.path(index_root, "Figures")
730:  }
731:  if (!dir.exists(figs)) {
732:    return(invisible(list(combined = character(), deleted = character(), skipped = character())))
733:  }
734:
735:  pdfs <- list.files(figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
736:  deleted <- character(0)
737:  if (isTRUE(cfg$drop_missing_overview)) {
738:    miss <- pdfs[.dual_db_is_missing_overview(basename(pdfs))]
739:    if (length(miss)) {
740:      unlink(miss)
741:      deleted <- c(deleted, basename(miss))
742:      cli::cli_alert_info("已删除缺失概览图 {length(miss)} 个")
743:      pdfs <- list.files(figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
744:    }
745:  }
746:  # 汇总目录只要 Figure 1. Flowchart.pdf；分库 Inclusion exclusion 底稿仅留在各库子目录


--- L726 ---

723:  cfg <- .dual_db_combine_cfg(config)
724:  if (!isTRUE(cfg$enable)) return(invisible(list(combined = character(), deleted = character(), skipped = character())))
725:
726:  figs <- if (!is.null(figures_dir) && nzchar(as.character(figures_dir)[1L])) {
727:    as.character(figures_dir)[1L]
728:  } else {
729:    file.path(index_root, "Figures")
730:  }
731:  if (!dir.exists(figs)) {
732:    return(invisible(list(combined = character(), deleted = character(), skipped = character())))
733:  }
734:
735:  pdfs <- list.files(figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
736:  deleted <- character(0)
737:  if (isTRUE(cfg$drop_missing_overview)) {
738:    miss <- pdfs[.dual_db_is_missing_overview(basename(pdfs))]
739:    if (length(miss)) {
740:      unlink(miss)
741:      deleted <- c(deleted, basename(miss))
742:      cli::cli_alert_info("已删除缺失概览图 {length(miss)} 个")
743:      pdfs <- list.files(figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
744:    }
745:  }
746:  # 汇总目录只要 Figure 1. Flowchart.pdf；分库 Inclusion exclusion 底稿仅留在各库子目录
747:  fig1_singles <- pdfs[.dual_db_is_per_db_fig1_flowchart(basename(pdfs))]
748:  if (length(fig1_singles)) {
749:    unlink(fig1_singles)
750:    deleted <- c(deleted, basename(fig1_singles))


--- L727 ---

724:  if (!isTRUE(cfg$enable)) return(invisible(list(combined = character(), deleted = character(), skipped = character())))
725:
726:  figs <- if (!is.null(figures_dir) && nzchar(as.character(figures_dir)[1L])) {
727:    as.character(figures_dir)[1L]
728:  } else {
729:    file.path(index_root, "Figures")
730:  }
731:  if (!dir.exists(figs)) {
732:    return(invisible(list(combined = character(), deleted = character(), skipped = character())))
733:  }
734:
735:  pdfs <- list.files(figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
736:  deleted <- character(0)
737:  if (isTRUE(cfg$drop_missing_overview)) {
738:    miss <- pdfs[.dual_db_is_missing_overview(basename(pdfs))]
739:    if (length(miss)) {
740:      unlink(miss)
741:      deleted <- c(deleted, basename(miss))
742:      cli::cli_alert_info("已删除缺失概览图 {length(miss)} 个")
743:      pdfs <- list.files(figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
744:    }
745:  }
746:  # 汇总目录只要 Figure 1. Flowchart.pdf；分库 Inclusion exclusion 底稿仅留在各库子目录
747:  fig1_singles <- pdfs[.dual_db_is_per_db_fig1_flowchart(basename(pdfs))]
748:  if (length(fig1_singles)) {
749:    unlink(fig1_singles)
750:    deleted <- c(deleted, basename(fig1_singles))
751:    cli::cli_alert_info("已删除汇总目录分库 Figure 1 纳排图 {length(fig1_singles)} 个")


--- L755 ---

752:    pdfs <- list.files(figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
753:  }
754:
755:  db_names <- if (length(cfg$databases)) cfg$databases else unique(c(cfg$primary, cfg$secondary, cfg$tertiary))
756:  db_names <- db_names[nzchar(db_names)]
757:  # 也收集文件名中出现的库标签（防配置名与文件不完全一致）
758:  per_db_pat <- .dual_db_per_db_tag_pattern(db_names)
759:  for (bn in basename(pdfs)) {
760:    m <- regmatches(bn, regexpr(per_db_pat, bn, ignore.case = TRUE, perl = TRUE))
761:    if (length(m) && nzchar(m)) {
762:      db_names <- unique(c(db_names, sub("^-", "", sub("\\.$", "", m))))
763:    }
764:  }
765:
766:  buckets <- list()
767:  for (fp in pdfs) {
768:    parsed <- .dual_db_parse_paired_figure_bn(basename(fp), db_names)
769:    if (is.null(parsed)) next
770:    key <- parsed$key
771:    if (is.null(buckets[[key]])) buckets[[key]] <- list()
772:    buckets[[key]][[parsed$db]] <- fp
773:  }
774:
775:  order_dbs <- cfg$databases
776:  if (!length(order_dbs)) order_dbs <- unique(c(cfg$primary, cfg$secondary, cfg$tertiary))
777:  order_dbs <- order_dbs[nzchar(order_dbs)]
778:  if (identical(cfg$panel_order, "secondary_first") && length(order_dbs) >= 2L) {
779:    order_dbs <- c(order_dbs[2L], order_dbs[1L], order_dbs[-c(1L, 2L)])


--- L776 ---

773:  }
774:
775:  order_dbs <- cfg$databases
776:  if (!length(order_dbs)) order_dbs <- unique(c(cfg$primary, cfg$secondary, cfg$tertiary))
777:  order_dbs <- order_dbs[nzchar(order_dbs)]
778:  if (identical(cfg$panel_order, "secondary_first") && length(order_dbs) >= 2L) {
779:    order_dbs <- c(order_dbs[2L], order_dbs[1L], order_dbs[-c(1L, 2L)])
780:  }
781:
782:  combined <- character(0)
783:  skipped <- character(0)
784:
785:  for (key in names(buckets)) {
786:    pair <- buckets[[key]]
787:    dbs_have <- names(pair)
788:    if (length(dbs_have) < 2L) {
789:      skipped <- c(skipped, key)
790:      cli::cli_alert_warning("多库拼图缺配对，保留单图: {key}（仅有 {paste(dbs_have, collapse = ', ')}）")
791:      next
792:    }
793:    # 若汇总目录已有同角色无库标签拼图，跳过（按角色而非图号，避免 KM 占住 Fig2 后 RCS 被跳过）
794:    role_fn <- if (exists("incidence_batch_prognosis_figure_role", mode = "function")) {
795:      incidence_batch_prognosis_figure_role
796:    } else {
797:      NULL
798:    }
799:    role <- if (is.function(role_fn)) role_fn(key) else NA_character_
800:    if (!is.na(role) && nzchar(role) && !role %in% c("other", "drop")) {


--- L850 ---

847:          dpi = cfg$dpi, label_cex = cfg$label_cex
848:        )
849:      } else {
850:        .dual_db_compose_n_pdf(
851:          pdf_paths, labels, out_path,
852:          layout = layout, dpi = cfg$dpi, label_cex = cfg$label_cex
853:        )
854:      }
855:      TRUE
856:    }, error = function(e) {
857:      cli::cli_alert_warning("拼图失败 [{key}]: {e$message}")
858:      FALSE
859:    })
860:    if (!isTRUE(ok) || !file.exists(out_path)) {
861:      skipped <- c(skipped, key)
862:      next
863:    }
864:    combined <- c(combined, key)
865:    if (isTRUE(cfg$remove_singles)) {
866:      victims <- unique(pdf_paths)
867:      victims <- victims[normalizePath(victims, winslash = "/", mustWork = FALSE) !=
868:        normalizePath(out_path, winslash = "/", mustWork = FALSE)]
869:      if (length(victims)) {
870:        unlink(victims)
871:        deleted <- c(deleted, basename(victims))
872:      }
873:    }
874:  }

