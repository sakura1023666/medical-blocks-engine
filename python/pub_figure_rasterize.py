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
