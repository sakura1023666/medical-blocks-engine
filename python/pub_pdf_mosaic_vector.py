#!/usr/bin/env python3
"""Compose panel PDFs into one vector page (2xN grid). No rasterization.

Usage:
  python3 python/pub_pdf_mosaic_vector.py --out out.pdf --cols 2 panel_a.pdf panel_b.pdf ...
"""
from __future__ import annotations

import argparse
import sys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--cols", type=int, default=2)
    ap.add_argument("panels", nargs="+")
    args = ap.parse_args()
    try:
        import fitz  # PyMuPDF
    except ImportError:
        print("PyMuPDF (fitz) required", file=sys.stderr)
        return 2

    docs = []
    rects = []
    for p in args.panels:
        d = fitz.open(p)
        if d.page_count < 1:
            d.close()
            continue
        pg = d[0]
        r = pg.rect
        docs.append(d)
        rects.append((r.width, r.height))
    if not docs:
        print("no panels", file=sys.stderr)
        return 1

    cols = max(1, int(args.cols))
    n = len(docs)
    rows = (n + cols - 1) // cols
    cell_w = max(w for w, _h in rects)
    cell_h = max(h for _w, h in rects)
    out_w = cell_w * cols
    out_h = cell_h * rows
    out = fitz.open()
    page = out.new_page(width=out_w, height=out_h)
    for i, d in enumerate(docs):
        r = i // cols
        c = i % cols
        x0 = c * cell_w
        y0 = r * cell_h
        target = fitz.Rect(x0, y0, x0 + cell_w, y0 + cell_h)
        page.show_pdf_page(target, d, 0)
    out.save(args.out)
    out.close()
    for d in docs:
        d.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
