#!/usr/bin/env python3
"""Compose WPR Fig2/Fig3 with eICU as top (primary) panel, MIMIC below."""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ENGINE = Path("/mnt/e/01block/01Block-new-Final")
ROOT = Path("/mnt/g/02block_result/36_spesis/prediction_41194138/by_index/【success】WPR")
OUT_PDF = ROOT / "summary_results" / "Figures" / "pdf"


def run(cmd: list[str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.check_call(cmd)


def find_one(dirpath: Path, patterns: list[str]) -> Path:
    for pat in patterns:
        hits = sorted(dirpath.glob(pat))
        if hits:
            return hits[0]
    raise FileNotFoundError(f"no match in {dirpath}: {patterns}")


def compose_fig2() -> Path:
    """2x3 nomogram: eICU top, MIMIC bottom."""
    py = ENGINE / "R" / "dual_db_compose_nomogram_horizons.py"
    e = ROOT / "eICU" / "step25_logistic_nomogram" / "Figures"
    m = ROOT / "MIMIC" / "step25_logistic_nomogram" / "Figures"
    # prefer panel PDFs if present; else 3-page combined
    out = OUT_PDF / "Figure 2. Nomogram for in-hospital, 30-day and 365-day mortality.pdf"
    out.parent.mkdir(parents=True, exist_ok=True)
    try:
        ea = find_one(e, ["*panel*A*", "*hosp*nomogram*", "*Nomogram*hosp*"])
        # fall through to 3-page mode
        raise FileNotFoundError("use multipage")
    except FileNotFoundError:
        ep = find_one(
            e,
            [
                "Figure. Nomogram for in-hospital, 30-day and 365-day mortality.pdf",
                "*Nomogram for in-hospital*",
                "*Nomogram*",
            ],
        )
        mp = find_one(
            m,
            [
                "Figure. Nomogram for in-hospital, 30-day and 365-day mortality.pdf",
                "*Nomogram for in-hospital*",
                "*Nomogram*",
            ],
        )
        run(
            [
                sys.executable,
                str(py),
                "--primary",
                str(ep),
                "--secondary",
                str(mp),
                "--primary-label",
                "eICU",
                "--secondary-label",
                "MIMIC",
                "--out",
                str(out),
            ]
        )
    return out


def compose_fig3() -> Path:
    py = ENGINE / "R" / "compose_jin_shap_fig3_dual_onepage.py"
    e = find_one(
        ROOT / "eICU" / "step26_shap_glm" / "Figures",
        [
            "Figure. SHAP summary and dependence in-hospital 30-day 365-day mortality.pdf",
            "*SHAP summary*",
        ],
    )
    m = find_one(
        ROOT / "MIMIC" / "step26_shap_glm" / "Figures",
        [
            "Figure. SHAP summary and dependence in-hospital 30-day 365-day mortality.pdf",
            "*SHAP summary*",
        ],
    )
    # Script hardcodes MIMIC top / eICU bottom — swap file args AND patch labels via temp copy
    # Easiest: write a local swap version
    out = OUT_PDF / "Figure 3. SHAP summary and dependence for in-hospital, 30-day and 365-day mortality.pdf"
    import fitz

    de, dm = fitz.open(e), fitz.open(m)
    pe, pm = de[0], dm[0]
    margin, gap, title_h, lab_h = 12.0, 10.0, 18.0, 14.0
    tw = max(pe.rect.width, pm.rect.width)
    he = pe.rect.height * (tw / pe.rect.width)
    hm = pm.rect.height * (tw / pm.rect.width)
    page_w0 = tw + 2 * margin
    page_h0 = title_h + lab_h + he + gap + lab_h + hm + 2 * margin
    sc = min(1.0, 16.0 * 72 / page_w0, 16.0 * 72 / page_h0)
    doc = fitz.open()
    page = doc.new_page(width=page_w0 * sc, height=page_h0 * sc)
    page.insert_text(
        (margin * sc, margin * sc + 12 * sc),
        "Figure 3. SHAP summary (A–C) and dependence (D–F)",
        fontsize=max(9, 11 * sc),
        fontname="times-bold",
    )
    y = margin * sc + title_h * sc
    page.insert_text((margin * sc, y + 10 * sc), "eICU", fontsize=max(8, 10 * sc), fontname="times-bold")
    y += lab_h * sc
    page.show_pdf_page(fitz.Rect(margin * sc, y, margin * sc + tw * sc, y + he * sc), de, 0)
    y += he * sc + gap * sc
    page.insert_text((margin * sc, y + 10 * sc), "MIMIC", fontsize=max(8, 10 * sc), fontname="times-bold")
    y += lab_h * sc
    page.show_pdf_page(fitz.Rect(margin * sc, y, margin * sc + tw * sc, y + hm * sc), dm, 0)
    out.parent.mkdir(parents=True, exist_ok=True)
    doc.save(out)
    doc.close()
    de.close()
    dm.close()
    print(f"wrote {out}")
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fig", choices=["2", "3", "all"], default="all")
    args = ap.parse_args()
    if args.fig in ("2", "all"):
        compose_fig2()
    if args.fig in ("3", "all"):
        compose_fig3()


if __name__ == "__main__":
    main()
