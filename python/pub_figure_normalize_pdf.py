#!/usr/bin/env python3
"""Normalize publication PDFs before 600 dpi raster export.

Fixes two recurring delivery bugs:
1. Screenshot / Shiny PDFs with enormous media boxes (20+ inches) → PNG
   explodes at 600 dpi and looks unlike the PDF viewer fit-to-window.
2. Optional: stack multi-page PDFs into one tall page so PDF and PNG match.

Usage:
  python3 python/pub_figure_normalize_pdf.py --pdf in.pdf --out out.pdf
  python3 python/pub_figure_normalize_pdf.py --pdf in.pdf --out out.pdf --stack-pages
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile


def _open_fitz(path: str):
    import pymupdf  # noqa: WPS433

    return pymupdf.open(path)


def page_inches(page) -> tuple[float, float]:
    r = page.rect
    return (float(r.width) / 72.0, float(r.height) / 72.0)


def needs_size_clamp(doc, max_edge_in: float) -> bool:
    for page in doc:
        w, h = page_inches(page)
        if max(w, h) > float(max_edge_in) + 1e-6:
            return True
    return False


def normalize_doc(
    pdf_path: str,
    out_path: str,
    *,
    max_edge_in: float = 11.0,
    stack_pages: bool = False,
    gap_pt: float = 12.0,
) -> dict:
    """Rewrite PDF: clamp page edge inches; optionally stack pages vertically."""
    import pymupdf  # noqa: WPS433

    src = _open_fitz(pdf_path)
    try:
        n = int(src.page_count)
        clamped = needs_size_clamp(src, max_edge_in)
        do_stack = bool(stack_pages) and n > 1
        if not clamped and not do_stack:
            if os.path.abspath(pdf_path) != os.path.abspath(out_path):
                shutil.copy2(pdf_path, out_path)
            return {
                "changed": False,
                "pages_in": n,
                "pages_out": n,
                "clamped": False,
                "stacked": False,
            }

        out = pymupdf.open()
        try:
            if do_stack:
                # Build one tall page: scale each source page so its long edge
                # ≤ max_edge_in, then stack.
                rendered_rects = []
                scales = []
                for i in range(n):
                    page = src[i]
                    w_in, h_in = page_inches(page)
                    scale = 1.0
                    m = max(w_in, h_in)
                    if m > max_edge_in:
                        scale = max_edge_in / m
                    scales.append(scale)
                    rendered_rects.append(
                        (
                            page.rect.width * scale,
                            page.rect.height * scale,
                        )
                    )
                max_w = max(r[0] for r in rendered_rects)
                total_h = sum(r[1] for r in rendered_rects) + gap_pt * (n - 1)
                # Final stacked page long edge must also ≤ max_edge_in so
                # formats_status / 600 dpi PNG stay consistent (no 15in tall RCS).
                stack_scale = 1.0
                long_pt = max(max_w, total_h)
                max_pt = float(max_edge_in) * 72.0
                if long_pt > max_pt and long_pt > 0:
                    stack_scale = max_pt / long_pt
                    max_w *= stack_scale
                    scales = [s * stack_scale for s in scales]
                    rendered_rects = [
                        (w * stack_scale, h * stack_scale) for w, h in rendered_rects
                    ]
                    total_h = sum(r[1] for r in rendered_rects) + gap_pt * stack_scale * (
                        n - 1
                    )

                new_page = out.new_page(width=max_w, height=total_h)
                y = 0.0
                for i in range(n):
                    pw, ph = rendered_rects[i]
                    x = (max_w - pw) / 2.0
                    dest = pymupdf.Rect(x, y, x + pw, y + ph)
                    new_page.show_pdf_page(dest, src, i)
                    y += ph + gap_pt * stack_scale
                pages_out = 1
            else:
                for i in range(n):
                    page = src[i]
                    w_in, h_in = page_inches(page)
                    scale = 1.0
                    m = max(w_in, h_in)
                    if m > max_edge_in:
                        scale = max_edge_in / m
                    nw = page.rect.width * scale
                    nh = page.rect.height * scale
                    new_page = out.new_page(width=nw, height=nh)
                    new_page.show_pdf_page(new_page.rect, src, i)
                pages_out = n

            # Write via temp then replace (SMB-safe)
            td = tempfile.mkdtemp(prefix="pub_norm_")
            try:
                tmp = os.path.join(td, "out.pdf")
                out.save(tmp, garbage=4, deflate=True)
                os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)
                if os.path.exists(out_path):
                    try:
                        os.chmod(out_path, 0o666)
                    except Exception:
                        pass
                    try:
                        os.remove(out_path)
                    except Exception:
                        pass
                shutil.copy2(tmp, out_path)
            finally:
                shutil.rmtree(td, ignore_errors=True)
        finally:
            out.close()

        return {
            "changed": True,
            "pages_in": n,
            "pages_out": pages_out,
            "clamped": clamped,
            "stacked": do_stack,
        }
    finally:
        src.close()


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    ap = argparse.ArgumentParser()
    ap.add_argument("--pdf", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-edge-in", type=float, default=11.0)
    ap.add_argument(
        "--stack-pages",
        action="store_true",
        help="Stack multi-page PDF into one tall page (RCS etc.)",
    )
    ap.add_argument("--gap-pt", type=float, default=12.0)
    args = ap.parse_args()
    if not os.path.isfile(args.pdf):
        raise FileNotFoundError(args.pdf)
    info = normalize_doc(
        args.pdf,
        args.out,
        max_edge_in=float(args.max_edge_in),
        stack_pages=bool(args.stack_pages),
        gap_pt=float(args.gap_pt),
    )
    print(
        "NORMALIZE",
        f"changed={info['changed']}",
        f"pages_in={info['pages_in']}",
        f"pages_out={info['pages_out']}",
        f"clamped={info['clamped']}",
        f"stacked={info['stacked']}",
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"pub_figure_normalize_pdf failed: {type(exc).__name__}: {exc}\n")
        raise SystemExit(1)
