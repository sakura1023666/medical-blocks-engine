#!/usr/bin/env python3
"""Surgical PDF fixes for EMs Fig5/Fig6 (paths with spaces; work on local copies)."""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

import pymupdf

ROOT = Path("/mnt/g/02block_result/35_EMs/ml_40395549/summary_results/Figures/pdf")
STUDY = Path(
    "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/"
    "20_子宫内膜异位症复发_仙人抚我顶/summary_results/Figures/pdf"
)
TMP = Path("/tmp/ems_pdf_fix")
TMP.mkdir(parents=True, exist_ok=True)


def _copy_local(name: str) -> Path:
    src = ROOT / name
    if not src.exists():
        raise FileNotFoundError(src)
    dst = TMP / name.replace("/", "_")
    shutil.copy2(src, dst)
    return dst


def _write_back(local: Path, name: str) -> None:
    dest = ROOT / name
    try:
        dest.chmod(0o666)
    except Exception:
        pass
    try:
        dest.unlink()
    except Exception:
        pass
    shutil.copy2(local, dest)
    if STUDY.is_dir():
        sdest = STUDY / name
        try:
            if sdest.exists():
                sdest.unlink()
        except Exception:
            pass
        try:
            shutil.copy2(local, sdest)
        except Exception as e:
            print("study mirror skip:", e)


def fix_fig5(name: str) -> None:
    local = _copy_local(name)
    doc = pymupdf.open(local)
    page = doc[0]
    bad = []
    for b in page.get_text("dict")["blocks"]:
        if b.get("type") != 0:
            continue
        for line in b.get("lines", []):
            t = "".join(s.get("text", "") for s in line.get("spans", [])).strip()
            # drop probability-scale overlays that contradict shapviz logit labels
            if t.startswith("f(x)=0.575") or t.startswith("E[f(x)]=0.500"):
                bad.append(pymupdf.Rect(line["bbox"]))
            # also any caption-like E[f(x)]=0.5xx near bottom of waterfall panel
            if t.startswith("E[f(x)]=0.") and "0.500" in t:
                bad.append(pymupdf.Rect(line["bbox"]))
    for r in bad:
        r = pymupdf.Rect(r.x0 - 1, r.y0 - 1, r.x1 + 1, r.y1 + 1)
        page.add_redact_annot(r, fill=(1, 1, 1))
    if bad:
        page.apply_redactions()
    out = TMP / ("fixed_" + local.name)
    doc.save(out, garbage=4, deflate=True)
    doc.close()
    shutil.move(out, local)
    _write_back(local, name)
    print(f"fig5 redacted={len(bad)} -> {name}")


def fix_fig6(name: str) -> None:
    local = _copy_local(name)
    doc = pymupdf.open(local)
    page = doc[0]
    # footer note
    rect = pymupdf.Rect(36, page.rect.height - 42, page.rect.width - 36, page.rect.height - 18)
    page.draw_rect(rect, color=(1, 1, 1), fill=(1, 1, 1))
    page.insert_textbox(
        rect,
        "Sparse stratum (N<10): Hydronephrosis n=8 — wide CI shown; interpret with caution.",
        fontsize=8,
        fontname="helv",
        color=(0.2, 0.2, 0.2),
        align=0,
    )
    stamped = 0
    for b in page.get_text("dict")["blocks"]:
        if b.get("type") != 0:
            continue
        for line in b.get("lines", []):
            t = "".join(s.get("text", "") for s in line.get("spans", []))
            if "Hydronephrosis" in t and "Not Checked" not in t and "Status" not in t and "[sparse]" not in t:
                r = pymupdf.Rect(line["bbox"])
                page.insert_text(
                    (min(r.x1 + 4, page.rect.width - 60), r.y1 - 2),
                    " [sparse]",
                    fontsize=7,
                    fontname="helv",
                    color=(0.55, 0.1, 0.1),
                )
                stamped += 1
    out = TMP / ("fixed_" + local.name)
    doc.save(out, garbage=4, deflate=True)
    doc.close()
    shutil.move(out, local)
    _write_back(local, name)
    print(f"fig6 sparse stamped rows={stamped} -> {name}")


def main() -> int:
    fig5 = "Figure 5-EMs Single. SHAP — Random survival forest.pdf"
    fig6 = "Figure 6-EMs Single. Subgroup Forest analyses of AMH (Q4 vs Q1 within each subgroup).pdf"
    fix_fig5(fig5)
    fix_fig6(fig6)
    # verify
    for nm in (fig5, fig6):
        doc = pymupdf.open(ROOT / nm)
        t = doc[0].get_text()
        doc.close()
        print("---", nm)
        for key in ("f(x)=0.575", "E[f(x)]=0.500", "pred=", "sparse", "Hydronephrosis"):
            print(f"  {key}:", key in t or key.lower() in t.lower())
    return 0


if __name__ == "__main__":
    sys.exit(main())
