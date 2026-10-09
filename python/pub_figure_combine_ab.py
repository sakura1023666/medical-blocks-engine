#!/usr/bin/env python3
"""Compose two single-page PDFs into one vector page with A/B labels.

Uses PyMuPDF show_pdf_page (Form XObject) so paths/text stay vector.
Default layout is stacked (A above B). Pass --side for left|right.
"""
from __future__ import annotations

import argparse
import os
import sys


def _open_pymupdf():
    try:
        import pymupdf as fitz  # noqa: WPS433
    except ImportError:
        import fitz  # type: ignore  # noqa: WPS433
    return fitz


def combine(
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
    args = ap.parse_args()
    stack = not bool(args.side)
    combine(
        args.pdf_a,
        args.pdf_b,
        args.dest,
        (args.label_a, args.label_b),
        stack=stack,
        label_band=args.label_band,
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
