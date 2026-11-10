#!/usr/bin/env python3
"""Compose Jin Fig3: 2x3 SHAP (A-C beeswarm, D-F dependence)."""
from __future__ import annotations

import argparse
from pathlib import Path

import fitz


def compose(
    bees: list[Path],
    deps: list[Path],
    out: Path,
    labels: list[str],
    exposure: str = "WPR",
    color: str = "SOFA",
    db_label: str = "",
    max_edge_in: float = 16.0,
) -> None:
    assert len(bees) == 3 and len(deps) == 3
    docs_b = [fitz.open(p) for p in bees]
    docs_d = [fitz.open(p) for p in deps]
    pages_b = [d[0] for d in docs_b]
    pages_d = [d[0] for d in docs_d]
    th_b = max(p.rect.height for p in pages_b)
    th_d = max(p.rect.height for p in pages_d)
    wb = [p.rect.width * (th_b / p.rect.height) for p in pages_b]
    wd = [p.rect.width * (th_d / p.rect.height) for p in pages_d]
    gap, margin, lab_h, title_h = 10.0, 16.0, 16.0, 22.0
    row_w = max(sum(wb) + 2 * gap, sum(wd) + 2 * gap)
    page_w0 = row_w + 2 * margin
    page_h0 = title_h + lab_h + th_b + gap + lab_h + th_d + 2 * margin + 16
    sc = min(1.0, max_edge_in * 72 / page_w0, max_edge_in * 72 / page_h0)

    out_doc = fitz.open()
    page = out_doc.new_page(width=page_w0 * sc, height=page_h0 * sc)
    title = "Figure 3. SHAP summary (A–C) and dependence (D–F)"
    if db_label:
        title = f"{title} — {db_label}"
    page.insert_text(
        (margin * sc, margin * sc + 14 * sc),
        title,
        fontsize=max(9, 11 * sc),
        fontname="times-bold",
    )

    def place(y0, pages, widths, th, docs, letters, sublabs):
        x = margin * sc
        total = (sum(widths) + 2 * gap) * sc
        if total < row_w * sc:
            x += (row_w * sc - total) / 2
        for i, (pg, w) in enumerate(zip(pages, widths)):
            page.insert_text(
                (x, y0 + 11 * sc),
                f"{letters[i]}. {sublabs[i]}",
                fontsize=max(7, 9 * sc),
                fontname="times-bold",
            )
            y = y0 + lab_h * sc
            page.show_pdf_page(
                fitz.Rect(x, y, x + w * sc, y + th * sc),
                docs[i],
                0,
            )
            x += w * sc + gap * sc
        return y0 + (lab_h + th) * sc

    y = margin * sc + title_h * sc
    y = place(y, pages_b, wb, th_b, docs_b, list("ABC"), labels)
    y = y + gap * sc
    dep_labs = [f"{exposure} impact on {labels[i]}" for i in range(3)]
    place(y, pages_d, wd, th_d, docs_d, list("DEF"), dep_labs)
    note = (
        f"Points = patients; color = feature value (A–C) or {color} (D–F). "
        "Feature set aligned with Fig2 nomogram (not a tree best model)."
    )
    page.insert_text(
        (margin * sc, page.rect.height - 12 * sc),
        note,
        fontsize=max(6, 7.5 * sc),
        fontname="times-roman",
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    out_doc.save(out)
    out_doc.close()
    for d in docs_b + docs_d:
        d.close()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bee-a", required=True)
    ap.add_argument("--bee-b", required=True)
    ap.add_argument("--bee-c", required=True)
    ap.add_argument("--dep-a", required=True)
    ap.add_argument("--dep-b", required=True)
    ap.add_argument("--dep-c", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--label-a", default="in-hospital Mortality")
    ap.add_argument("--label-b", default="30-day Mortality")
    ap.add_argument("--label-c", default="365-day Mortality")
    ap.add_argument("--exposure", default="WPR")
    ap.add_argument("--color", default="SOFA")
    ap.add_argument("--db-label", default="")
    ap.add_argument("--max-edge-in", type=float, default=16.0)
    args = ap.parse_args()
    compose(
        [Path(args.bee_a), Path(args.bee_b), Path(args.bee_c)],
        [Path(args.dep_a), Path(args.dep_b), Path(args.dep_c)],
        Path(args.out),
        [args.label_a, args.label_b, args.label_c],
        args.exposure,
        args.color,
        args.db_label,
        args.max_edge_in,
    )
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
