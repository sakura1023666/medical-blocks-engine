#!/usr/bin/env python3
"""Surgical P0 display fixes for ULN-triple summary delivery (numeric cells unchanged).

Fixes footnotes/titles: remove Cite-row ops, ACG residual, Literature retrieval note;
clarify equal-n / Mcomposite vs Mscan / BlendedICU mortality wording; S1 clip limitation.
"""
from __future__ import annotations

import argparse
import re
import shutil
import tempfile
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.styles import Font


def _scrub_fn(text: str) -> str:
    if not text:
        return text
    t = str(text)
    t = re.sub(
        r"\s*Cite row labels exactly\s*\(e\.g\.[^)]*\)\.?",
        "",
        t,
        flags=re.I,
    )
    t = re.sub(r"\s*Literature retrieval summary:\s*literature basis note\.?", "", t, flags=re.I)
    t = re.sub(
        r"\s*ACG\s*=\s*American College of Gastroenterology[^.]+\.",
        "",
        t,
        flags=re.I,
    )
    t = t.replace(
        "subsets of the BlendedICU dataset",
        "one BlendedICU source database",
    )
    t = t.replace(
        "four-strategy 70/15/15",
        "four-strategy patient-level split",
    )
    # Table Mcomposite clarification
    if "Mcomposite" in t and "Amsterdam-alone" in t and "Mscan" not in t:
        t = t.replace(
            "Mcomposite = 0.5×[(MAPE/MAPE₀)+( (1−AUROC)/(1−AUROC₀) )] with Amsterdam-alone on Amsterdam as baseline; point estimate.",
            "Mcomposite (table) = 0.5×[(MAPE/MAPE₀)+((1−AUROC)/(1−AUROC₀))] with Amsterdam-alone on Amsterdam as baseline; "
            "not the same baseline as Figure 2 Mscan (max training-size). Point estimate.",
        )
        t = t.replace(
            "Mcomposite = 0.5×[(MAPE/MAPE₀)+((1−AUROC)/(1−AUROC₀))] with Amsterdam-alone on Amsterdam as baseline; point estimate.",
            "Mcomposite (table) = 0.5×[(MAPE/MAPE₀)+((1−AUROC)/(1−AUROC₀))] with Amsterdam-alone on Amsterdam as baseline; "
            "not the same baseline as Figure 2 Mscan (max training-size). Point estimate.",
        )
    t = re.sub(r"\s{2,}", " ", t).strip()
    return t


def _fix_s2_title(title: str) -> str:
    if not title:
        return title
    t = title
    t = re.sub(
        r"when training on [\d,]+ patients from the BlendedICU dataset",
        "when training on 1,713 patients (equal-n cap = Amsterdam train persons per database; post min-LoS filter)",
        t,
    )
    return t


def _fix_s1_fn(text: str) -> str:
    if not text:
        return text
    extra = (
        " Clip bounds were transcribed from the reference MOESM1 physiological-range table, "
        "including non-physiological lower bounds (e.g. negative BUN / GCS total); "
        "hard clipping may pin medians to the bound when the unclipped median lies outside the interval."
    )
    if "non-physiological" in text:
        return text
    return text.rstrip() + extra


def _fix_s2_fn(text: str) -> str:
    if not text:
        return text
    if "equal-n cap" in text.lower() or "Amsterdam training person" in text:
        return _scrub_fn(text)
    base = _scrub_fn(text)
    add = (
        " Equal-n: each of the four databases was capped at the Amsterdam training person count "
        "(438; seed 974) before BlendedLoS inclusion filters; title n_train is the post-filter "
        "training headcount (1,713), not 4×438."
    )
    return base + add


def repair_xlsx(path: Path) -> list[str]:
    notes = []
    wb = load_workbook(path)
    ws = wb.active
    changed = False
    # title row
    title = ws.cell(1, 1).value
    if title and "Table S2" in str(title):
        nt = _fix_s2_title(str(title))
        if nt != title:
            ws.cell(1, 1).value = nt
            ws.cell(1, 1).font = Font(name="Times New Roman", bold=True, size=12)
            changed = True
            notes.append("S2 title")
    # scan long footnote cells
    for row in ws.iter_rows(min_row=1, max_row=ws.max_row, max_col=1):
        cell = row[0]
        val = cell.value
        if not val or not isinstance(val, str) or len(val) < 40:
            continue
        new = val
        bn = path.name
        if "Table S1" in bn:
            new = _fix_s1_fn(new)
        elif "Table S2" in bn:
            new = _fix_s2_fn(new)
        else:
            new = _scrub_fn(new)
        if new != val:
            cell.value = new
            cell.font = Font(name="Times New Roman", size=10)
            changed = True
            notes.append(f"fn@{cell.coordinate}")
    if changed:
        tmp = Path(tempfile.mkstemp(suffix=".xlsx")[1])
        wb.save(tmp)
        shutil.copy2(tmp, path)
        tmp.unlink(missing_ok=True)
    wb.close()
    return notes


def repair_md(path: Path) -> bool:
    t = path.read_text(encoding="utf-8")
    orig = t
    t = t.replace("Composite metric", "Mscan (vs max-N)")
    t = t.replace("Composite（Mcomposite）以最大训练规模为参照（=1）", "Mscan 以本图最大训练规模为参照（末点=1.000）；勿与 Table 3 Mcomposite 对读")
    t = t.replace("图内标注 Composite / RLoS / Mortality", "图内标注 Mscan / RLoS / Mortality")
    t = t.replace("(BlendedICU)", "(BlendedICU extract)")
    if "Mscan" in t and "Table 3 Mcomposite" not in t and "Figure 2" in path.name:
        if "## 分析上下文" in t and "勿与 Table 3" not in t:
            t = t.replace(
                "## 分析上下文",
                "Mscan 与 Table 3 Mcomposite（Amsterdam-alone 基线）同式不同基线，禁止对读。\n\n## 分析上下文",
            )
    if t != orig:
        path.write_text(t, encoding="utf-8")
        return True
    return False


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, type=Path)
    args = ap.parse_args()
    root = args.dir
    tabs = root / "Tables"
    for p in sorted(tabs.glob("Table*.xlsx")):
        notes = repair_xlsx(p)
        print(f"{p.name}: {notes or ['ok']}")
    info = root / "Figures" / "image_information"
    if info.is_dir():
        for p in sorted(info.glob("*.md")):
            print(f"{p.name}: md_fixed={repair_md(p)}")


if __name__ == "__main__":
    main()
