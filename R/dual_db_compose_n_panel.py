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
