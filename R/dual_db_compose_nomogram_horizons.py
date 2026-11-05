#!/usr/bin/env python3
"""Compose Jin dual-DB nomogram Figure 2.

Default layout (matches literature ABC + dual DB):
  one page, 2×3 grid — MIMIC on top (A|B|C), eICU below (A|B|C).

Legacy interleaved 6-page mode: --layout pages

Usage:
  python dual_db_compose_nomogram_horizons.py \\
    --primary-a A.pdf --primary-b B.pdf --primary-c C.pdf \\
    --secondary-a A.pdf --secondary-b B.pdf --secondary-c C.pdf \\
    --primary-label MIMIC --secondary-label eICU \\
    --out Figure2.pdf

  # or from two 3-page stacked PDFs:
  python … --primary mimic3.pdf --secondary eicu3.pdf --out Figure2.pdf
"""
from __future__ import annotations

import argparse
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

import fitz

HORIZON_LABELS = [
    "A. In-hospital mortality",
    "B. 30-day mortality",
    "C. 365-day mortality",
]


def _pages_from_pdf(path: Path) -> Tuple[fitz.Document, List[fitz.Page]]:
    doc = fitz.open(path)
    return doc, [doc[i] for i in range(doc.page_count)]


def _pages_from_list(paths: Sequence[Path]) -> Tuple[List[fitz.Document], List[fitz.Page]]:
    docs, pages = [], []
    for p in paths:
        d = fitz.open(p)
        docs.append(d)
        pages.append(d[0])
    return docs, pages


def compose_grid_one_page(
    primary_pages: Sequence[fitz.Page],
    secondary_pages: Sequence[fitz.Page],
    primary_docs: Sequence[fitz.Document],
    secondary_docs: Sequence[fitz.Document],
    out: Path,
    primary_label: str = "MIMIC",
    secondary_label: str = "eICU",
    max_edge_in: float = 16.0,
    title: str = "Figure 2. Nomogram for in-hospital, 30-day and 365-day mortality",
) -> None:
    """MIMIC top ABC | eICU bottom ABC, single page."""
    n = min(3, len(primary_pages), len(secondary_pages))
    if n < 1:
        raise SystemExit("need at least one panel per database")

    margin = 16.0
    gap_x = 10.0
    gap_y = 18.0
    title_h = 22.0
    row_label_h = 18.0
    col_label_h = 16.0

    def row_metrics(pages: Sequence[fitz.Page]):
        th = max(p.rect.height for p in pages[:n])
        widths = [p.rect.width * (th / p.rect.height) for p in pages[:n]]
        return th, widths

    th_p, wp = row_metrics(primary_pages)
    th_s, ws = row_metrics(secondary_pages)
    row_w = max(sum(wp) + gap_x * (n - 1), sum(ws) + gap_x * (n - 1))
    content_h = (
        row_label_h
        + col_label_h
        + th_p
        + gap_y
        + row_label_h
        + col_label_h
        + th_s
    )
    page_w0 = row_w + 2 * margin
    page_h0 = title_h + content_h + 2 * margin
    max_edge = max_edge_in * 72.0
    sc = min(1.0, max_edge / page_w0, max_edge / page_h0)

    out_doc = fitz.open()
    page = out_doc.new_page(width=page_w0 * sc, height=page_h0 * sc)
    page.insert_text(
        (margin * sc, margin * sc + 14 * sc),
        title,
        fontsize=max(9, 12 * sc),
        fontname="times-bold",
    )

    def place_row(
        y0: float,
        db_lab: str,
        pages: Sequence[fitz.Page],
        widths: Sequence[float],
        th: float,
        docs: Sequence[fitz.Document],
    ) -> float:
        page.insert_text(
            (margin * sc, y0 + 12 * sc),
            db_lab,
            fontsize=max(9, 11 * sc),
            fontname="times-bold",
        )
        y_cols = y0 + row_label_h * sc
        total = (sum(widths[:n]) + gap_x * (n - 1)) * sc
        x = margin * sc + max(0.0, (row_w * sc - total) / 2.0)
        for i in range(n):
            lab = HORIZON_LABELS[i] if i < len(HORIZON_LABELS) else f"Panel {i+1}"
            page.insert_text(
                (x, y_cols + 11 * sc),
                lab,
                fontsize=max(7, 9 * sc),
                fontname="times-bold",
            )
            y_panel = y_cols + col_label_h * sc
            w_s, h_s = widths[i] * sc, th * sc
            # which doc index for this page
            doc_i = docs[i] if i < len(docs) else docs[0]
            page_i = 0
            # if docs are multi-page single docs, pages come from same doc
            if len(docs) == 1:
                doc_i = docs[0]
                page_i = i
            page.show_pdf_page(
                fitz.Rect(x, y_panel, x + w_s, y_panel + h_s),
                doc_i,
                page_i if len(docs) == 1 else 0,
            )
            x += w_s + gap_x * sc
        return y0 + (row_label_h + col_label_h + th) * sc

    y = margin * sc + title_h * sc
    y = place_row(y, primary_label, primary_pages, wp, th_p, primary_docs)
    y = y + gap_y * sc
    place_row(y, secondary_label, secondary_pages, ws, th_s, secondary_docs)

    out.parent.mkdir(parents=True, exist_ok=True)
    out_doc.save(out)
    out_doc.close()


def compose_pages_interleaved(
    primary: Path,
    secondary: Path,
    out: Path,
    primary_label: str,
    secondary_label: str,
) -> None:
    """Legacy: 6 full-width pages A-prim, A-sec, …"""
    dp = fitz.open(primary)
    ds = fitz.open(secondary)
    n = max(dp.page_count, ds.page_count)
    margin, title_h = 18.0, 22.0
    out_doc = fitz.open()
    for i in range(n):
        hz = HORIZON_LABELS[i] if i < len(HORIZON_LABELS) else f"Horizon {i+1}"
        for src, lab in ((dp, primary_label), (ds, secondary_label)):
            if i >= src.page_count:
                continue
            pg = src[i]
            w = pg.rect.width + 2 * margin
            h = pg.rect.height + title_h + 2 * margin
            page = out_doc.new_page(width=w, height=h)
            page.insert_text(
                (margin, margin + 14),
                f"{hz} — {lab}",
                fontsize=12,
                fontname="times-bold",
            )
            page.show_pdf_page(
                fitz.Rect(
                    margin,
                    margin + title_h,
                    margin + pg.rect.width,
                    margin + title_h + pg.rect.height,
                ),
                src,
                i,
            )
    out.parent.mkdir(parents=True, exist_ok=True)
    out_doc.save(out)
    out_doc.close()
    dp.close()
    ds.close()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--primary", default=None, help="3-page primary PDF")
    ap.add_argument("--secondary", default=None, help="3-page secondary PDF")
    ap.add_argument("--primary-a", default=None)
    ap.add_argument("--primary-b", default=None)
    ap.add_argument("--primary-c", default=None)
    ap.add_argument("--secondary-a", default=None)
    ap.add_argument("--secondary-b", default=None)
    ap.add_argument("--secondary-c", default=None)
    ap.add_argument("--out", required=True)
    ap.add_argument("--primary-label", default="MIMIC")
    ap.add_argument("--secondary-label", default="eICU")
    ap.add_argument("--layout", choices=["grid", "pages"], default="grid")
    ap.add_argument("--max-edge-in", type=float, default=16.0)
    args = ap.parse_args()
    out = Path(args.out)

    owned: List[fitz.Document] = []
    try:
        if args.primary_a and args.secondary_a:
            pp = [
                Path(args.primary_a),
                Path(args.primary_b or args.primary_a),
                Path(args.primary_c or args.primary_a),
            ]
            sp = [
                Path(args.secondary_a),
                Path(args.secondary_b or args.secondary_a),
                Path(args.secondary_c or args.secondary_a),
            ]
            pd, ppg = _pages_from_list(pp)
            sd, spg = _pages_from_list(sp)
            owned.extend(pd + sd)
            if args.layout == "pages":
                # stack then interleave
                tmp_p = out.with_suffix(".prim.tmp.pdf")
                tmp_s = out.with_suffix(".sec.tmp.pdf")
                for paths, tmp in ((pp, tmp_p), (sp, tmp_s)):
                    d = fitz.open()
                    for pth in paths:
                        s = fitz.open(pth)
                        d.insert_pdf(s)
                        s.close()
                    d.save(tmp)
                    d.close()
                compose_pages_interleaved(
                    tmp_p, tmp_s, out, args.primary_label, args.secondary_label
                )
                tmp_p.unlink(missing_ok=True)
                tmp_s.unlink(missing_ok=True)
            else:
                compose_grid_one_page(
                    ppg,
                    spg,
                    pd,
                    sd,
                    out,
                    args.primary_label,
                    args.secondary_label,
                    max_edge_in=args.max_edge_in,
                )
        elif args.primary and args.secondary:
            dp, ppg = _pages_from_pdf(Path(args.primary))
            ds, spg = _pages_from_pdf(Path(args.secondary))
            owned.extend([dp, ds])
            if args.layout == "pages":
                compose_pages_interleaved(
                    Path(args.primary),
                    Path(args.secondary),
                    out,
                    args.primary_label,
                    args.secondary_label,
                )
            else:
                compose_grid_one_page(
                    ppg,
                    spg,
                    [dp],
                    [ds],
                    out,
                    args.primary_label,
                    args.secondary_label,
                    max_edge_in=args.max_edge_in,
                )
        else:
            raise SystemExit("provide --primary/--secondary or --primary-a/b/c + --secondary-a/b/c")
    finally:
        for d in owned:
            try:
                d.close()
            except Exception:
                pass
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
