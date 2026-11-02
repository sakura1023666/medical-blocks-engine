#!/usr/bin/env python3
"""Compose two single-page PDFs into one page with A/B labels.

Default: PyMuPDF show_pdf_page (Form XObject, vector).
--as-images: rasterize each panel onto white, then stack/side-embed as one image PDF.
  Use for qgraph/bootnet (and similar) sources where show_pdf_page paints a black panel.
Auto: after vector compose, if either panel is mostly near-black, redo with --as-images.
"""
from __future__ import annotations

import argparse
import io
import os
import sys


def _open_pymupdf():
    try:
        import pymupdf as fitz  # noqa: WPS433
    except ImportError:
        import fitz  # type: ignore  # noqa: WPS433
    return fitz


def _panel_is_black(page, fitz, dark_frac_cut: float = 0.35) -> bool:
    """True if a large fraction of the page luminance is near black (corrupt embed)."""
    try:
        import numpy as np
    except ImportError:
        return False
    pix = page.get_pixmap(matrix=fitz.Matrix(0.35, 0.35), alpha=False)
    arr = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width, 3)
    y = arr.mean(axis=2)
    dark = float((y < 25).mean())
    mean = float(y.mean())
    # qgraph black-panel: huge dark fraction + low mean; normal networks stay bright
    return dark >= dark_frac_cut and mean < 80.0


def _render_white(pdf_path: str, fitz, zoom: float = 2.5):
    from PIL import Image

    doc = fitz.open(pdf_path)
    try:
        page = doc[0]
        pix = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom), alpha=True)
        im = Image.frombytes("RGBA", (pix.width, pix.height), pix.samples)
        bg = Image.new("RGB", im.size, (255, 255, 255))
        bg.paste(im, mask=im.split()[3])
        return bg
    finally:
        doc.close()


def combine_as_images(
    pdf_a: str,
    pdf_b: str,
    dest: str,
    labels: tuple[str, str],
    stack: bool,
    label_band: float = 28.0,
    zoom: float = 2.5,
    dpi: float = 150.0,
) -> None:
    from PIL import Image, ImageDraw, ImageFont

    fitz = _open_pymupdf()
    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18
        )
    except Exception:
        font = ImageFont.load_default()

    band = max(18, int(round(float(label_band) or 28.0)))
    gap = 12
    ima = _render_white(pdf_a, fitz, zoom=zoom)
    imb = _render_white(pdf_b, fitz, zoom=zoom)

    def labeled(im: Image.Image, lab: str) -> Image.Image:
        top = Image.new("RGB", (im.width, band), (255, 255, 255))
        dr = ImageDraw.Draw(top)
        dr.text((10, max(2, band // 4)), lab, fill=(0, 0, 0), font=font)
        out = Image.new("RGB", (im.width, band + im.height), (255, 255, 255))
        out.paste(top, (0, 0))
        out.paste(im, (0, band))
        return out

    pa = labeled(ima, labels[0])
    pb = labeled(imb, labels[1])

    if stack:
        max_w = max(pa.width, pb.width)
        total_h = pa.height + gap + pb.height
        canvas = Image.new("RGB", (max_w, total_h), (255, 255, 255))
        canvas.paste(pa, ((max_w - pa.width) // 2, 0))
        canvas.paste(pb, ((max_w - pb.width) // 2, pa.height + gap))
    else:
        max_h = max(pa.height, pb.height)
        total_w = pa.width + gap + pb.width
        canvas = Image.new("RGB", (total_w, max_h), (255, 255, 255))
        canvas.paste(pa, (0, (max_h - pa.height) // 2))
        canvas.paste(pb, (pa.width + gap, (max_h - pb.height) // 2))

    buf = io.BytesIO()
    canvas.save(buf, format="PNG")
    png_bytes = buf.getvalue()
    w_pt = canvas.width * 72.0 / float(dpi)
    h_pt = canvas.height * 72.0 / float(dpi)
    out = fitz.open()
    page = out.new_page(width=w_pt, height=h_pt)
    page.insert_image(page.rect, stream=png_bytes)
    os.makedirs(os.path.dirname(os.path.abspath(dest)) or ".", exist_ok=True)
    out.save(dest, deflate=True, garbage=3)
    out.close()


def combine_vector(
    pdf_a: str,
    pdf_b: str,
    dest: str,
    labels: tuple[str, str],
    stack: bool,
    label_band: float = 0.0,
) -> None:
    fitz = _open_pymupdf()
    src_a = fitz.open(pdf_a)
    src_b = fitz.open(pdf_b)
    try:
        pa = src_a[0]
        pb = src_b[0]
        ra = pa.rect
        rb = pb.rect
        gap = 10.0
        band = max(0.0, float(label_band))
        label_y = max(14.0, band - 6.0) if band > 0 else 22.0
        if stack:
            width = max(ra.width, rb.width)
            scale_a = width / ra.width if ra.width > 0 else 1.0
            scale_b = width / rb.width if rb.width > 0 else 1.0
            ha = ra.height * scale_a
            hb = rb.height * scale_b
            height = ha + hb + gap + 2 * band
            out = fitz.open()
            page = out.new_page(width=width, height=height)
            page.show_pdf_page(fitz.Rect(0, band, width, band + ha), src_a, 0)
            second_top = band + ha + gap
            page.show_pdf_page(
                fitz.Rect(0, second_top + band, width, second_top + band + hb),
                src_b,
                0,
            )
            page.insert_text((14, label_y), labels[0], fontsize=16, fontname="times-bold")
            page.insert_text(
                (14, second_top + label_y),
                labels[1],
                fontsize=16,
                fontname="times-bold",
            )
        else:
            content_height = max(ra.height, rb.height)
            height = content_height + band
            scale_a = content_height / ra.height if ra.height > 0 else 1.0
            scale_b = content_height / rb.height if rb.height > 0 else 1.0
            wa = ra.width * scale_a
            wb = rb.width * scale_b
            width = wa + wb + gap
            out = fitz.open()
            page = out.new_page(width=width, height=height)
            page.show_pdf_page(fitz.Rect(0, band, wa, band + content_height), src_a, 0)
            page.show_pdf_page(
                fitz.Rect(wa + gap, band, wa + gap + wb, band + content_height),
                src_b,
                0,
            )
            page.insert_text((14, label_y), labels[0], fontsize=16, fontname="times-bold")
            page.insert_text(
                (wa + gap + 14, label_y),
                labels[1],
                fontsize=16,
                fontname="times-bold",
            )
        os.makedirs(os.path.dirname(os.path.abspath(dest)) or ".", exist_ok=True)
        out.save(dest, deflate=True, garbage=3)
        out.close()
    finally:
        src_a.close()
        src_b.close()


def _combined_has_black_panel(dest: str) -> bool:
    fitz = _open_pymupdf()
    doc = fitz.open(dest)
    try:
        page = doc[0]
        # Check top and bottom halves separately (stacked A/B)
        try:
            import numpy as np
        except ImportError:
            return _panel_is_black(page, fitz)
        pix = page.get_pixmap(matrix=fitz.Matrix(0.4, 0.4), alpha=False)
        arr = np.frombuffer(pix.samples, dtype=np.uint8).reshape(
            pix.height, pix.width, 3
        )
        mid = max(1, pix.height // 2)
        for sl in (arr[:mid], arr[mid:]):
            y = sl.mean(axis=2)
            dark = float((y < 25).mean())
            mean = float(y.mean())
            if dark >= 0.35 and mean < 80.0:
                return True
        return False
    finally:
        doc.close()


def combine(
    pdf_a: str,
    pdf_b: str,
    dest: str,
    labels: tuple[str, str],
    stack: bool,
    label_band: float = 0.0,
    as_images: bool = False,
    auto_raster_if_black: bool = True,
) -> None:
    if as_images:
        combine_as_images(
            pdf_a, pdf_b, dest, labels, stack=stack, label_band=label_band or 28.0
        )
        return

    combine_vector(pdf_a, pdf_b, dest, labels, stack=stack, label_band=label_band)
    if auto_raster_if_black and _combined_has_black_panel(dest):
        # qgraph/bootnet Form XObject often paints black; rebuild as white-backed images
        combine_as_images(
            pdf_a, pdf_b, dest, labels, stack=stack, label_band=label_band or 28.0
        )


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    ap = argparse.ArgumentParser()
    ap.add_argument("--pdf-a", required=True)
    ap.add_argument("--pdf-b", required=True)
    ap.add_argument("--dest", required=True)
    ap.add_argument("--label-a", default="A")
    ap.add_argument("--label-b", default="B")
    ap.add_argument("--stack", action="store_true", default=True)
    ap.add_argument("--side", action="store_true", help="Left-right instead of top-bottom")
    ap.add_argument(
        "--label-band",
        type=float,
        default=0.0,
        help="Reserved label band above each panel, in PDF points",
    )
    ap.add_argument(
        "--as-images",
        action="store_true",
        help="Rasterize panels onto white then embed (safe for qgraph)",
    )
    ap.add_argument(
        "--no-auto-raster",
        action="store_true",
        help="Do not auto-fallback to --as-images when vector panels look black",
    )
    args = ap.parse_args()
    stack = not bool(args.side)
    combine(
        args.pdf_a,
        args.pdf_b,
        args.dest,
        (args.label_a, args.label_b),
        stack=stack,
        label_band=args.label_band,
        as_images=bool(args.as_images),
        auto_raster_if_black=not bool(args.no_auto_raster),
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        msg = f"pub_figure_combine_ab failed: {type(exc).__name__}: {exc}"
        try:
            sys.stderr.write(msg + "\n")
        except Exception:
            sys.stderr.buffer.write((msg + "\n").encode("utf-8", errors="replace"))
        raise SystemExit(1)
