#!/usr/bin/env python3
"""Vector dual-DB figure compose: place two PDF pages side-by-side or stacked.

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
        # Prefer real Times New Roman if present on system
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
            # reportlab y is from bottom; items already bottom-based
            c.drawString(x, y, text)
        c.save()
        buf.seek(0)
        return PdfReader(buf)
    except Exception:
        # Minimal PDF with Times-Bold (standard 14)
        # Escape PDF string
        def esc(s: str) -> str:
            return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")

        streams = []
        for text, x, y, _just in items:
            streams.append(
                f"BT /F1 {font_size:.2f} Tf {x:.2f} {y:.2f} Td ({esc(text)}) Tj ET"
            )
        content = "\n".join(streams)
        pdf = (
            "%PDF-1.4\n"
            "1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n"
            "2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n"
            f"3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width:.2f} {height:.2f}] "
            f"/Contents 4 0 R /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 "
            f"/BaseFont /Times-Bold >> >> >> >>endobj\n"
            f"4 0 obj<< /Length {len(content)} >>stream\n{content}\nendstream\nendobj\n"
            "xref\n0 5\n0000000000 65535 f \n"
            "trailer<< /Size 5 /Root 1 0 R >>\nstartxref\n0\n%%EOF\n"
        )
        # Rebuild with correct offsets via pypdf blank + merge is hard; use reportlab-less
        # Write via PdfWriter blank and add text annotation as fallback: labels still visible.
        from pypdf.generic import (
            DictionaryObject,
            NameObject,
            NumberObject,
            ArrayObject,
            DecodedStreamObject,
            IndirectObject,
        )

        writer = PdfWriter()
        page = writer.add_blank_page(width=width, height=height)
        # Attach content stream manually
        stream = DecodedStreamObject()
        # Need font resource Times-Bold
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
        stream.set_data(content.encode("latin-1", errors="replace"))
        page[NameObject("/Contents")] = writer._add_object(stream)
        out = BytesIO()
        writer.write(out)
        out.seek(0)
        return PdfReader(out)


def compose(
    path_a: str,
    path_b: str,
    out_path: str,
    layout: str = "side",
    label_a: str = "A.",
    label_b: str = "B.",
    label_h_pt: float = 28.0,
    margin_pt: float = 18.0,
    gap_pt: float = 18.0,
    font_size: float = 14.0,
    center: bool = True,
) -> None:
    ra, rb = PdfReader(path_a), PdfReader(path_b)
    if not ra.pages or not rb.pages:
        raise SystemExit("empty PDF page")
    pa, pb = ra.pages[0], rb.pages[0]
    wa, ha = _page_wh(pa)
    wb, hb = _page_wh(pb)
    layout = (layout or "side").lower()

    if layout == "stack":
        panel_w = max(wa, wb)
        sa = panel_w / wa
        sb = panel_w / wb
        a_h = ha * sa
        b_h = hb * sb
        content_w = panel_w
        content_h = label_h_pt + a_h + margin_pt + label_h_pt + b_h
        total_w = content_w + 2 * margin_pt
        total_h = content_h + 2 * margin_pt
        page = PageObject.create_blank_page(width=total_w, height=total_h)
        x = margin_pt
        y_a = total_h - margin_pt - label_h_pt - a_h
        y_b = margin_pt
        page.merge_transformed_page(
            pa, Transformation().scale(sa).translate(x, y_a)
        )
        page.merge_transformed_page(
            pb, Transformation().scale(sb).translate(x, y_b)
        )
        lab_a_y = total_h - margin_pt - font_size * 0.85
        lab_b_y = y_b + b_h + label_h_pt * 0.55
        items = [
            (label_a, margin_pt, lab_a_y, 0.0),
            (label_b, margin_pt, lab_b_y, 0.0),
        ]
    else:
        # 等高并排；内容块在画布上四周等边距居中
        panel_h = max(ha, hb)
        sa = panel_h / ha
        sb = panel_h / hb
        a_w = wa * sa
        b_w = wb * sb
        content_w = a_w + b_w + gap_pt
        content_h = label_h_pt + panel_h
        total_w = content_w + 2 * margin_pt
        total_h = content_h + 2 * margin_pt
        # Cap extreme width (~22 in)
        max_w = 22 * 72.0
        if total_w > max_w:
            sc = max_w / total_w
            sa *= sc
            sb *= sc
            a_w *= sc
            b_w *= sc
            gap_pt *= sc
            panel_h *= sc
            content_w = a_w + b_w + gap_pt
            content_h = label_h_pt + panel_h
            total_w = max_w
            total_h = content_h + 2 * margin_pt
        page = PageObject.create_blank_page(width=total_w, height=total_h)
        # 水平/垂直居中内容块
        if center:
            x0 = (total_w - content_w) / 2.0
            y0 = (total_h - content_h) / 2.0
        else:
            x0 = margin_pt
            y0 = margin_pt
        y_img = y0
        x_a = x0
        x_b = x0 + a_w + gap_pt
        page.merge_transformed_page(
            pa, Transformation().scale(sa).translate(x_a, y_img)
        )
        page.merge_transformed_page(
            pb, Transformation().scale(sb).translate(x_b, y_img)
        )
        # 标签在图上方独立带内，避免压到表头
        lab_y = y_img + panel_h + (label_h_pt - font_size) * 0.55
        items = [
            (label_a, x_a + a_w * 0.02, lab_y, 0.0),
            (label_b, x_b + b_w * 0.02, lab_y, 0.0),
        ]

    overlay = _label_overlay_pdf(total_w, total_h, items, font_size)
    page.merge_page(overlay.pages[0])

    writer = PdfWriter()
    writer.add_page(page)
    with open(out_path, "wb") as f:
        writer.write(f)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--a", required=True)
    p.add_argument("--b", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--layout", default="side")
    p.add_argument("--label-a", default="A.")
    p.add_argument("--label-b", default="B.")
    p.add_argument("--label-h-pt", type=float, default=28.0)
    p.add_argument("--margin-pt", type=float, default=18.0)
    p.add_argument("--gap-pt", type=float, default=18.0)
    p.add_argument("--font-size", type=float, default=14.0)
    p.add_argument("--center", action="store_true", default=True)
    p.add_argument("--no-center", action="store_true", default=False)
    args = p.parse_args()
    compose(
        args.a,
        args.b,
        args.out,
        layout=args.layout,
        label_a=args.label_a,
        label_b=args.label_b,
        label_h_pt=args.label_h_pt,
        margin_pt=args.margin_pt,
        gap_pt=args.gap_pt,
        font_size=args.font_size,
        center=not bool(args.no_center),
    )


if __name__ == "__main__":
    main()
