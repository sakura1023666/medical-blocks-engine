# Review package Task 3

======= BEGIN tests/test_dual_db_combine_n_panel.R =======
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
======= END tests/test_dual_db_combine_n_panel.R =======
======= BEGIN R/dual_db_compose_n_panel.py =======
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
======= BEGIN dual_db_combine_figures.R (key hunks) =======
34:    tertiary = as.character((dd$tertiary %||% list())$name %||% "")[1L],
35:    databases = {
39:        as.character((dd$tertiary %||% list())$name %||% "")[1L],
40:        as.character(dd$databases %||% character(0))
536:.dual_db_compose_n_pdf_vector <- function(paths, labels, out_path, layout = "side",
548:  script <- .dual_db_find_compose_script("dual_db_compose_n_panel.py")
549:  if (is.null(script)) stop("找不到 dual_db_compose_n_panel.py", call. = FALSE)
598:.dual_db_compose_n_pdf_raster <- function(paths, labels, out_path, layout = "side",
694:.dual_db_compose_n_pdf <- function(paths, labels, out_path, layout = "side",
697:    .dual_db_compose_n_pdf_vector(
710:  .dual_db_compose_n_pdf_raster(
720:#' @param figures_dir 可选；默认 `file.path(index_root, "Figures")`，交叉滞后可传 `summary_result/figure`
722:dual_db_combine_paired_figures <- function(index_root, config, figures_dir = NULL) {
726:  figs <- if (!is.null(figures_dir) && nzchar(as.character(figures_dir)[1L])) {
727:    as.character(figures_dir)[1L]
755:  db_names <- if (length(cfg$databases)) cfg$databases else unique(c(cfg$primary, cfg$secondary, cfg$tertiary))
775:  order_dbs <- cfg$databases
776:  if (!length(order_dbs)) order_dbs <- unique(c(cfg$primary, cfg$secondary, cfg$tertiary))
777:  order_dbs <- order_dbs[nzchar(order_dbs)]
778:  if (identical(cfg$panel_order, "secondary_first") && length(order_dbs) >= 2L) {
779:    order_dbs <- c(order_dbs[2L], order_dbs[1L], order_dbs[-c(1L, 2L)])
825:    paths <- lapply(order_dbs, resolve)
850:        .dual_db_compose_n_pdf(
877:    db_msg <- paste(order_dbs, collapse = ", ")
--- full file line count ---
910 R/dual_db_combine_figures.R
--- around L34 ---
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

--- around L39 ---
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

--- around L536 ---
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

--- around L548 ---
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

--- around L549 ---
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

--- around L598 ---
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

--- around L694 ---
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

--- around L697 ---
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

--- around L710 ---
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

--- around L720 ---
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

--- around L722 ---
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

--- around L726 ---
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

--- around L727 ---
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

--- around L755 ---
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

--- around L776 ---
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

--- around L850 ---
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

