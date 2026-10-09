#!/usr/bin/env python3
"""Inventory Tables/Figures for pub-qc-after-project (Layer A helper).

Usage (repo root or any cwd):
  python3 scripts/pub_qc_inventory.py --root /mnt/g/02block_result/<study>

Does not judge PASS/FAIL for numbers; only lists structure signals.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def _figures_status(fig_dir: Path) -> dict:
    out = {
        "path": str(fig_dir),
        "exists": fig_dir.is_dir(),
        "has_pdf_dir": False,
        "has_png_dir": False,
        "has_tiff_dir": False,
        "has_image_information": False,
        "root_loose_figure_pdfs": [],
        "pdf_stems": [],
        "missing_png": [],
        "missing_tiff": [],
        "zero_tiff": [],
        "missing_image_md": [],
    }
    if not fig_dir.is_dir():
        return out
    pdf_d = fig_dir / "pdf"
    png_d = fig_dir / "png"
    tiff_d = fig_dir / "tiff"
    imd = fig_dir / "image_information"
    out["has_pdf_dir"] = pdf_d.is_dir()
    out["has_png_dir"] = png_d.is_dir()
    out["has_tiff_dir"] = tiff_d.is_dir()
    out["has_image_information"] = imd.is_dir()
    out["root_loose_figure_pdfs"] = sorted(
        p.name for p in fig_dir.glob("Figure*.pdf") if p.is_file()
    )
    if not pdf_d.is_dir():
        return out
    pdfs = sorted(pdf_d.glob("*.pdf"))
    stems = [p.stem for p in pdfs]
    out["pdf_stems"] = stems
    for stem in stems:
        if not (png_d / f"{stem}.png").is_file():
            out["missing_png"].append(stem)
        tiff = tiff_d / f"{stem}.tiff"
        if not tiff.is_file():
            # also accept .tif
            tiff2 = tiff_d / f"{stem}.tif"
            if not tiff2.is_file():
                out["missing_tiff"].append(stem)
            elif tiff2.stat().st_size == 0:
                out["zero_tiff"].append(stem)
        elif tiff.stat().st_size == 0:
            out["zero_tiff"].append(stem)
        md = imd / f"{stem}.md"
        if not md.is_file():
            out["missing_image_md"].append(stem)
    return out


def _find_figure_dirs(root: Path, success_only: bool = True) -> list[Path]:
    hits: list[Path] = []
    # Default: ONLY 【success】 units (never 【failed】 or bare by_index/NAME)
    patterns = [
        "by_index/【success】*/Figures",
        "by_unit/【success】*/Figures",
    ]
    if not success_only:
        patterns.extend(
            [
                "by_index/*/Figures",
                "by_unit/*/Figures",
                "Figures",
                "summary_results/Figures",
                "summary_result/figure",
            ]
        )
    else:
        # Root Figures only if no success dirs exist (single-unit layouts)
        success_n = len(list(root.glob("by_index/【success】*"))) + len(
            list(root.glob("by_unit/【success】*"))
        )
        if success_n == 0:
            patterns.extend(
                ["Figures", "summary_results/Figures", "summary_result/figure"]
            )
    for pattern in patterns:
        hits.extend(root.glob(pattern))
    seen = set()
    uniq = []
    for p in hits:
        rp = p.resolve()
        if rp in seen:
            continue
        # hard skip failed paths even if pattern widened
        if any(str(x).startswith("【failed】") for x in p.parts):
            continue
        seen.add(rp)
        uniq.append(p)
    return uniq


def _list_tables(root: Path, success_only: bool = True) -> list[str]:
    tabs = []
    patterns = [
        "by_index/【success】*/Tables/*",
        "by_unit/【success】*/Tables/*",
    ]
    if not success_only:
        patterns.extend(["Tables/*", "by_index/*/Tables/*", "by_unit/*/Tables/*"])
    else:
        success_n = len(list(root.glob("by_index/【success】*"))) + len(
            list(root.glob("by_unit/【success】*"))
        )
        if success_n == 0:
            patterns.append("Tables/*")
    for pattern in patterns:
        for p in root.glob(pattern):
            if any(str(x).startswith("【failed】") for x in p.parts):
                continue
            if p.is_file() and p.suffix.lower() in {".xlsx", ".csv", ".rds"}:
                tabs.append(str(p.relative_to(root)))
    return sorted(set(tabs))[:200]


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Layer A inventory for pub-qc (default: 【success】 only)"
    )
    ap.add_argument("--root", required=True, help="Project output root")
    ap.add_argument("--json", action="store_true", help="Print JSON only")
    ap.add_argument(
        "--success-only",
        action="store_true",
        default=True,
        help="Only 【success】 dirs (default True)",
    )
    ap.add_argument(
        "--include-non-success",
        action="store_true",
        help="Also scan bare/root Figures (still skips 【failed】)",
    )
    args = ap.parse_args()
    root = Path(args.root)
    if not root.is_dir():
        print(f"ERROR: not a directory: {root}", file=sys.stderr)
        return 2
    success_only = not bool(args.include_non_success)
    fig_reports = [
        _figures_status(d) for d in _find_figure_dirs(root, success_only=success_only)
    ]
    success_dirs = sorted(
        [str(p.relative_to(root)) for p in root.glob("by_index/【success】*")]
        + [str(p.relative_to(root)) for p in root.glob("by_unit/【success】*")]
    )
    failed_dirs = sorted(
        [str(p.relative_to(root)) for p in root.glob("by_index/【failed】*")]
        + [str(p.relative_to(root)) for p in root.glob("by_unit/【failed】*")]
    )
    payload = {
        "root": str(root),
        "success_only": success_only,
        "success_units": success_dirs,
        "failed_units_count": len(failed_dirs),
        "failed_units_sample": failed_dirs[:20],
        "figures": fig_reports,
        "tables_sample": _list_tables(root, success_only=success_only),
        "has_pub_qc_report": any(root.glob("reports/pub_qc_*.md")),
    }
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0
    print(f"root: {payload['root']}")
    print(f"success_only: {success_only}")
    print(f"success_units ({len(success_dirs)}):")
    for s in success_dirs[:50]:
        print(f"  - {s}")
    if len(success_dirs) > 50:
        print(f"  … +{len(success_dirs) - 50} more")
    print(f"failed_units_skipped: {len(failed_dirs)} (not reviewed)")
    print(f"figure_dirs: {len(fig_reports)}")
    for fr in fig_reports:
        print(f"  - {fr['path']}")
        print(
            f"    dirs pdf/png/tiff/imd="
            f"{fr['has_pdf_dir']}/{fr['has_png_dir']}/{fr['has_tiff_dir']}/{fr['has_image_information']}"
        )
        print(f"    pdf_n={len(fr['pdf_stems'])} "
              f"miss_png={len(fr['missing_png'])} "
              f"miss_tiff={len(fr['missing_tiff'])} "
              f"zero_tiff={len(fr['zero_tiff'])} "
              f"miss_md={len(fr['missing_image_md'])} "
              f"loose_root_pdf={len(fr['root_loose_figure_pdfs'])}")
    print(f"tables_listed: {len(payload['tables_sample'])} (cap 200)")
    print(f"existing_pub_qc_md: {payload['has_pub_qc_report']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
