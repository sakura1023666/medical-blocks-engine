#!/usr/bin/env python3
"""Stack two Jin Fig3 pages (MIMIC + eICU) onto ONE page."""
from __future__ import annotations

import argparse
from pathlib import Path

import fitz


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mimic", required=True)
    ap.add_argument("--eicu", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-edge-in", type=float, default=16.0)
    args = ap.parse_args()

    dm, de = fitz.open(args.mimic), fitz.open(args.eicu)
    pm, pe = dm[0], de[0]
    margin, gap, title_h, lab_h = 12.0, 10.0, 18.0, 14.0
    tw = max(pm.rect.width, pe.rect.width)
    hm = pm.rect.height * (tw / pm.rect.width)
    he = pe.rect.height * (tw / pe.rect.width)
    page_w0 = tw + 2 * margin
    page_h0 = title_h + lab_h + hm + gap + lab_h + he + 2 * margin
    sc = min(1.0, args.max_edge_in * 72 / page_w0, args.max_edge_in * 72 / page_h0)

    out = fitz.open()
    page = out.new_page(width=page_w0 * sc, height=page_h0 * sc)
    page.insert_text(
        (margin * sc, margin * sc + 12 * sc),
        "Figure 3. SHAP summary (A–C) and dependence (D–F)",
        fontsize=max(9, 11 * sc),
        fontname="times-bold",
    )
    y = margin * sc + title_h * sc
    page.insert_text(
        (margin * sc, y + 10 * sc), "MIMIC", fontsize=max(8, 10 * sc), fontname="times-bold"
    )
    y += lab_h * sc
    page.show_pdf_page(fitz.Rect(margin * sc, y, margin * sc + tw * sc, y + hm * sc), dm, 0)
    y += hm * sc + gap * sc
    page.insert_text(
        (margin * sc, y + 10 * sc), "eICU", fontsize=max(8, 10 * sc), fontname="times-bold"
    )
    y += lab_h * sc
    page.show_pdf_page(fitz.Rect(margin * sc, y, margin * sc + tw * sc, y + he * sc), de, 0)
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    out.save(args.out)
    out.close()
    dm.close()
    de.close()
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
