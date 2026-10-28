#!/usr/bin/env python3
"""Rasterize first page of a PDF to PNG and/or TIFF (LZW)."""
from __future__ import annotations

import argparse
import os
import sys


def _render_pymupdf(pdf_path: str, dpi: int):
    import pymupdf  # noqa: WPS433

    doc = pymupdf.open(pdf_path)
    try:
        page = doc[0]
        zoom = float(dpi) / 72.0
        mat = pymupdf.Matrix(zoom, zoom)
        pix = page.get_pixmap(matrix=mat, alpha=False)
        from PIL import Image
        import io

        return Image.open(io.BytesIO(pix.tobytes("png"))).convert("RGB")
    finally:
        doc.close()


def _render_pypdfium2(pdf_path: str, dpi: int):
    import pypdfium2 as pdfium  # noqa: WPS433

    doc = pdfium.PdfDocument(pdf_path)
    page = doc[0]
    bitmap = page.render(scale=dpi / 72.0)
    return bitmap.to_pil()


def _render_pdftoppm(pdf_path: str, dpi: int):
    import subprocess
    import tempfile
    from PIL import Image

    with tempfile.TemporaryDirectory() as td:
        prefix = os.path.join(td, "page")
        subprocess.check_call(
            ["pdftoppm", "-png", "-r", str(dpi), "-f", "1", "-l", "1", pdf_path, prefix]
        )
        cand = prefix + "-1.png"
        if not os.path.isfile(cand):
            cand = prefix + ".png"
        return Image.open(cand).convert("RGB")


def save_tiff_dpi(im, path: str, dpi: int) -> None:
    """Write LZW TIFF with an inch resolution tag.

    Anaconda Pillow routes TIFF through libtiff, which drops the dpi= argument
    and leaves XResolution empty (readers then report 1 dpi). The pure-Python
    encoder keeps the tag.
    """
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


def png_save_dpi(dpi: int) -> tuple[float, float]:
    """DPI tuple whose PNG pHYs reads back as at least ``dpi``.

    pHYs stores integer pixels per metre. ``round(600/0.0254)`` is 23622,
    which reads as 599.9988 and file properties often show 599 while TIFF
    shows 600. Use the next pixel-per-metre so the tag is 600.0242.
    """
    ppm = int(int(dpi) / 0.0254) + 1
    d = ppm * 0.0254
    return (d, d)


def render_page(pdf_path: str, dpi: int):
    errors = []
    for name, fn in (
        ("pymupdf", _render_pymupdf),
        ("pypdfium2", _render_pypdfium2),
        ("pdftoppm", _render_pdftoppm),
    ):
        try:
            return fn(pdf_path, dpi)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{name}: {type(exc).__name__}: {exc}")
    raise RuntimeError("All PDF raster backends failed: " + " | ".join(errors))


def main() -> int:
    # Force UTF-8 stderr/stdout so R on Windows does not choke on localized OS errors
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    # 上下拼大图（如双库 CLPN）600 dpi 像素数可超 Pillow 默认炸弹阈值
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
    args = ap.parse_args()
    dpi = int(args.dpi) if int(args.dpi) > 0 else 600
    im = render_page(args.pdf, dpi)
    dpi_tuple = (dpi, dpi)
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
