#!/usr/bin/env python3
"""Rasterize publication PDF to PNG and/or TIFF (LZW).

Rules (2026-11, EMs Shiny / RCS lessons):
- Multi-page PDFs: stack ALL pages vertically into one raster (not page-1 only).
- Oversized media boxes (screenshot/Shiny): clamp long edge so 600 dpi PNG
  stays viewable; DPI metadata still written as >=600.

Legacy one-page behaviour is preserved when the PDF has a single normal-sized page.
"""
from __future__ import annotations

import argparse
import os
import sys


# Long-edge clamp in inches before 600 dpi raster (≈11*600 = 6600 px).
DEFAULT_MAX_EDGE_IN = 11.0
# Absolute pixel cap on the long side (safety for stacked RCS).
DEFAULT_MAX_EDGE_PX = 12000


def png_save_dpi(dpi: int) -> tuple[float, float]:
    """DPI tuple whose PNG pHYs reads back as at least ``dpi``."""
    ppm = int(int(dpi) / 0.0254) + 1
    d = ppm * 0.0254
    return (d, d)


def save_tiff_dpi(im, path: str, dpi: int) -> None:
    """Write LZW TIFF with an inch resolution tag."""
    import PIL.TiffImagePlugin as tiff_plugin

    previous = getattr(tiff_plugin, "WRITE_LIBTIFF", False)
    tiff_plugin.WRITE_LIBTIFF = False
    try:
        im.save(
            path,
            format="TIFF",
            compression="tiff_lzw",
            dpi=(int(dpi), int(dpi)),
            resolution_unit=2,
        )
    finally:
        tiff_plugin.WRITE_LIBTIFF = previous


def _effective_zoom(page_rect, dpi: int, max_edge_in: float, max_edge_px: int) -> float:
    """Zoom factor for pymupdf Matrix: clamp huge pages before raster."""
    w_in = float(page_rect.width) / 72.0
    h_in = float(page_rect.height) / 72.0
    long_in = max(w_in, h_in)
    zoom = float(dpi) / 72.0
    if long_in > float(max_edge_in) and long_in > 0:
        # Render as if page were max_edge_in on the long side at target dpi.
        zoom = (float(max_edge_in) * float(dpi)) / (long_in * 72.0)
    # Pixel safety
    long_px = long_in * 72.0 * zoom
    if long_px > float(max_edge_px) and long_px > 0:
        zoom *= float(max_edge_px) / long_px
    return zoom


def _render_pymupdf_all(
    pdf_path: str,
    dpi: int,
    *,
    max_edge_in: float = DEFAULT_MAX_EDGE_IN,
    max_edge_px: int = DEFAULT_MAX_EDGE_PX,
    gap_px: int = 24,
):
    import io

    import pymupdf  # noqa: WPS433
    from PIL import Image

    doc = pymupdf.open(pdf_path)
    try:
        images = []
        for i in range(doc.page_count):
            page = doc[i]
            zoom = _effective_zoom(page.rect, dpi, max_edge_in, max_edge_px)
            mat = pymupdf.Matrix(zoom, zoom)
            pix = page.get_pixmap(matrix=mat, alpha=False)
            im = Image.open(io.BytesIO(pix.tobytes("png"))).convert("RGB")
            images.append(im)
        if not images:
            raise RuntimeError("PDF has zero pages")
        if len(images) == 1:
            return images[0]
        max_w = max(im.width for im in images)
        total_h = sum(im.height for im in images) + gap_px * (len(images) - 1)
        # Cap stacked height
        if total_h > max_edge_px:
            scale = float(max_edge_px) / float(total_h)
            images = [
                im.resize(
                    (max(1, int(im.width * scale)), max(1, int(im.height * scale))),
                    Image.Resampling.LANCZOS,
                )
                for im in images
            ]
            max_w = max(im.width for im in images)
            total_h = sum(im.height for im in images) + max(
                1, int(gap_px * scale)
            ) * (len(images) - 1)
            gap_use = max(1, int(gap_px * scale))
        else:
            gap_use = gap_px
        canvas = Image.new("RGB", (max_w, total_h), (255, 255, 255))
        y = 0
        for im in images:
            x = (max_w - im.width) // 2
            canvas.paste(im, (x, y))
            y += im.height + gap_use
        return canvas
    finally:
        doc.close()


def _render_pypdfium2(pdf_path: str, dpi: int):
    """Fallback: page 0 only (legacy); prefer pymupdf path for multi-page."""
    import pypdfium2 as pdfium  # noqa: WPS433

    doc = pdfium.PdfDocument(pdf_path)
    page = doc[0]
    # Clamp scale for huge pages
    w_pt, h_pt = page.get_size()
    long_in = max(w_pt, h_pt) / 72.0
    scale = dpi / 72.0
    if long_in > DEFAULT_MAX_EDGE_IN:
        scale = (DEFAULT_MAX_EDGE_IN * dpi) / (long_in * 72.0)
    bitmap = page.render(scale=scale)
    return bitmap.to_pil()


def _render_pdftoppm(pdf_path: str, dpi: int):
    """Fallback: page 0 only."""
    import subprocess
    import tempfile

    from PIL import Image

    with tempfile.TemporaryDirectory() as td:
        prefix = os.path.join(td, "page")
        # Soft DPI if page is huge — pdftoppm can't easily know; use dpi as-is
        subprocess.check_call(
            ["pdftoppm", "-png", "-r", str(dpi), "-f", "1", "-l", "1", pdf_path, prefix]
        )
        cand = prefix + "-1.png"
        if not os.path.isfile(cand):
            cand = prefix + ".png"
        return Image.open(cand).convert("RGB")


def render_page(
    pdf_path: str,
    dpi: int,
    *,
    max_edge_in: float = DEFAULT_MAX_EDGE_IN,
    max_edge_px: int = DEFAULT_MAX_EDGE_PX,
):
    errors = []
    try:
        return _render_pymupdf_all(
            pdf_path, dpi, max_edge_in=max_edge_in, max_edge_px=max_edge_px
        )
    except Exception as exc:  # noqa: BLE001
        errors.append(f"pymupdf: {type(exc).__name__}: {exc}")
    for name, fn in (
        ("pypdfium2", _render_pypdfium2),
        ("pdftoppm", _render_pdftoppm),
    ):
        try:
            return fn(pdf_path, dpi)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{name}: {type(exc).__name__}: {exc}")
    raise RuntimeError("All PDF raster backends failed: " + " | ".join(errors))


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    try:
        from PIL import Image as _PIL_Image

        _PIL_Image.MAX_IMAGE_PIXELS = None
    except Exception:
        pass

    ap = argparse.ArgumentParser()
    ap.add_argument("--pdf", required=True)
    ap.add_argument("--png")
    ap.add_argument("--tiff")
    ap.add_argument("--dpi", type=int, default=600)
    ap.add_argument("--max-edge-in", type=float, default=DEFAULT_MAX_EDGE_IN)
    ap.add_argument("--max-edge-px", type=int, default=DEFAULT_MAX_EDGE_PX)
    args = ap.parse_args()
    dpi = int(args.dpi) if int(args.dpi) > 0 else 600
    im = render_page(
        args.pdf,
        dpi,
        max_edge_in=float(args.max_edge_in),
        max_edge_px=int(args.max_edge_px),
    )
    if args.png:
        os.makedirs(os.path.dirname(os.path.abspath(args.png)) or ".", exist_ok=True)
        im.save(args.png, format="PNG", dpi=png_save_dpi(dpi))
    if args.tiff:
        os.makedirs(os.path.dirname(os.path.abspath(args.tiff)) or ".", exist_ok=True)
        save_tiff_dpi(im, args.tiff, dpi)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        msg = f"pub_figure_rasterize failed: {type(exc).__name__}: {exc}"
        try:
            sys.stderr.write(msg + "\n")
        except Exception:
            sys.stderr.buffer.write((msg + "\n").encode("utf-8", errors="replace"))
        raise SystemExit(1)
