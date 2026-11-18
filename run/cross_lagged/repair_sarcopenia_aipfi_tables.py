#!/usr/bin/env python3
"""Fix sarcopenia AIP×FI delivery tables (format only; numbers unchanged).

- Table 2-CHARLS/ELSA/HRS: align header to Pooled (Characteristic; Crude/Model merges;
  filename-matched A1; Times New Roman)
- Table S7/S10: fix shifted model header merges E:G/H:J/K:L → D:F/G:I/J:L
- Scrub Marital_Status → Marital Status in footnotes
"""
from __future__ import annotations

import re
import shutil
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.styles import Alignment, Border, Font, Side
from openpyxl.utils import get_column_letter

TAB = Path(
    "/mnt/g/02block_result/54_Sarcopenia/cross-laged_40595747/summary_result/Tables"
)
BACKUP = Path(
    "/mnt/g/02block_result/54_Sarcopenia/cross-laged_40595747/"
    "summary_result_delivery_workspace/tables_format_fix_20261104"
)
BACKUP.mkdir(parents=True, exist_ok=True)

TNR = Font(name="Times New Roman", size=11)
TNR_BOLD = Font(name="Times New Roman", size=11, bold=True)
THIN = Side(style="thin", color="000000")
BOTTOM = Border(bottom=THIN)
TOP = Border(top=THIN)


def scrub(s: str) -> str:
    if not isinstance(s, str):
        return s
    s = s.replace("Marital_Status", "Marital Status")
    s = s.replace("Characterisitic", "Characteristic")
    return s


def unmerge_all(ws):
    for rng in list(ws.merged_cells.ranges):
        ws.unmerge_cells(str(rng))


def apply_title_font(ws):
    for row in ws.iter_rows(min_row=1, max_row=ws.max_row, max_col=ws.max_column):
        for c in row:
            if c.value is None:
                continue
            bold = c.row <= 3 or (isinstance(c.value, str) and c.value.startswith("Table"))
            c.font = TNR_BOLD if bold and c.row <= 3 else TNR
            if isinstance(c.value, str):
                c.value = scrub(c.value)


def fix_logistic_header_like_pooled(ws, title: str):
    """Rewrite rows 1–3 header to Pooled layout; keep data rows."""
    # Capture data block starting at first body row (usually row 4)
    max_col = max(ws.max_column, 12)
    body = []
    start = 4
    for r in range(start, ws.max_row + 1):
        vals = [ws.cell(r, c).value for c in range(1, max_col + 1)]
        body.append(vals)

    unmerge_all(ws)
    # clear sheet content
    for r in range(1, ws.max_row + 1):
        for c in range(1, max_col + 1):
            ws.cell(r, c).value = None

    ws.cell(1, 1).value = title
    # row2 model labels at D/G/J
    ws.cell(2, 1).value = "Characteristic"
    ws.cell(2, 2).value = "Exposure cutoff"
    ws.cell(2, 3).value = "Case (%)"
    ws.cell(2, 4).value = "Crude Model"
    ws.cell(2, 7).value = "Model1"
    ws.cell(2, 10).value = "Model2"
    ws.cell(3, 1).value = ""
    ws.cell(3, 2).value = ""
    ws.cell(3, 3).value = ""
    for base, labs in ((4, ("OR", "95%CI", "P-value")),
                       (7, ("OR", "95%CI", "P-value")),
                       (10, ("OR", "95%CI", "P-value"))):
        for i, lab in enumerate(labs):
            ws.cell(3, base + i).value = lab

    for i, vals in enumerate(body):
        r = 4 + i
        for c, v in enumerate(vals, start=1):
            if c > 12:
                break
            ws.cell(r, c).value = scrub(v) if isinstance(v, str) else v

    # merges
    last = 3 + len(body)
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=12)
    ws.merge_cells("D2:F2")
    ws.merge_cells("G2:I2")
    ws.merge_cells("J2:L2")
    # footnote rows (empty Characteristic / starts with The / Analytic / Sensitivity / No AIP / Pooled)
    for r in range(4, last + 1):
        v0 = ws.cell(r, 1).value
        rest = [ws.cell(r, c).value for c in range(2, 13)]
        if v0 is None and all(x is None for x in rest):
            continue
        is_note = False
        if isinstance(v0, str) and (
            v0.startswith("The ")
            or v0.startswith("Analytic")
            or v0.startswith("Sensitivity")
            or v0.startswith("No AIP")
            or v0.startswith("Pooled")
            or v0.startswith("Note")
        ):
            is_note = True
        if is_note or (v0 is None and any(isinstance(x, str) and x.startswith("The ") for x in rest)):
            # consolidate note into A
            if v0 is None:
                for x in rest:
                    if isinstance(x, str) and x.strip():
                        ws.cell(r, 1).value = scrub(x)
                        break
            for c in range(2, 13):
                ws.cell(r, c).value = None
            ws.merge_cells(start_row=r, start_column=1, end_row=r, end_column=12)

    apply_title_font(ws)
    for c in range(1, 13):
        ws.cell(2, c).font = TNR_BOLD
        ws.cell(3, c).font = TNR_BOLD
        ws.cell(2, c).alignment = Alignment(horizontal="center", wrap_text=True)
        ws.cell(3, c).alignment = Alignment(horizontal="center", wrap_text=True)
    ws.cell(1, 1).font = Font(name="Times New Roman", size=12, bold=True)


def fix_s7_s10_header(path: Path):
    wb = load_workbook(path)
    ws = wb.active
    shutil.copy2(path, BACKUP / path.name)
    unmerge_all(ws)
    # Move model labels from E/H/K to D/G/J if needed
    r2 = [ws.cell(2, c).value for c in range(1, 13)]
    # expected wrong: '', '', '', '', 'Crude Model', ...
    if r2[4] == "Crude Model" and r2[3] in (None, ""):
        ws.cell(2, 4).value = "Crude Model"
        ws.cell(2, 5).value = None
        ws.cell(2, 6).value = None
        ws.cell(2, 7).value = "Model1"
        ws.cell(2, 8).value = None
        ws.cell(2, 9).value = None
        ws.cell(2, 10).value = "Model2"
        ws.cell(2, 11).value = None
        ws.cell(2, 12).value = None
    # ensure row3 OR headers start at D
    # already OR at D typically
    if ws.cell(3, 1).value and "Character" in str(ws.cell(3, 1).value):
        # Pooled-like: Characteristic should be row2; move up if needed
        pass
    # Put Characteristic on row2 cols A-C if empty
    if not ws.cell(2, 1).value:
        ws.cell(2, 1).value = "Characteristic"
        ws.cell(2, 2).value = "Exposure cutoff"
        ws.cell(2, 3).value = "Case (%)"
        # clear duplicate labels from row3 A-C if present
        if ws.cell(3, 1).value and "Character" in str(ws.cell(3, 1).value):
            ws.cell(3, 1).value = ""
            ws.cell(3, 2).value = ""
            ws.cell(3, 3).value = ""

    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=12)
    ws.merge_cells("D2:F2")
    ws.merge_cells("G2:I2")
    ws.merge_cells("J2:L2")
    # rematch A1 to filename stem
    ws.cell(1, 1).value = path.stem
    for r in range(1, ws.max_row + 1):
        for c in range(1, 13):
            v = ws.cell(r, c).value
            if isinstance(v, str):
                ws.cell(r, c).value = scrub(v)
    # footnote merges
    for r in range(13, ws.max_row + 1):
        v = ws.cell(r, 1).value
        if isinstance(v, str) and v.strip():
            for c in range(2, 13):
                ws.cell(r, c).value = None
            try:
                ws.merge_cells(start_row=r, start_column=1, end_row=r, end_column=12)
            except Exception:
                pass
    apply_title_font(ws)
    wb.save(path)
    print("fixed header", path.name)


def fix_table2_cohort(db: str):
    path = TAB / f"Table 2-{db}. Logistic regression analysis of AIP x FI and Sarcopenia - quintile.xlsx"
    if not path.exists():
        print("missing", path)
        return
    shutil.copy2(path, BACKUP / path.name)
    wb = load_workbook(path)
    ws = wb.active
    title = f"Table 2-{db}. Logistic regression analysis of AIP × FI and Sarcopenia - quintile"
    fix_logistic_header_like_pooled(ws, title)
    wb.save(path)
    print("fixed Table2", db)


def scrub_all_footnotes():
    for path in sorted(TAB.glob("*.xlsx")):
        wb = load_workbook(path)
        changed = False
        for ws in wb.worksheets:
            for row in ws.iter_rows():
                for c in row:
                    if isinstance(c.value, str) and "_" in c.value:
                        nv = scrub(c.value)
                        if nv != c.value:
                            c.value = nv
                            changed = True
        if changed:
            shutil.copy2(path, BACKUP / path.name)
            wb.save(path)
            print("scrubbed", path.name)


def style_table1_light():
    """Apply Times + header bold; merge title row if needed."""
    for path in sorted(TAB.glob("Table 1-*.xlsx")):
        shutil.copy2(path, BACKUP / path.name)
        wb = load_workbook(path)
        ws = wb.active
        unmerge_all(ws)
        # ensure A1 = filename
        ws.cell(1, 1).value = path.stem
        ncols = ws.max_column
        ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=ncols)
        apply_title_font(ws)
        for c in range(1, ncols + 1):
            ws.cell(2, c).font = TNR_BOLD
            ws.cell(2, c).border = Border(bottom=THIN, top=THIN)
        # bottom rule on last data row before empty
        last = ws.max_row
        for c in range(1, ncols + 1):
            ws.cell(last, c).border = Border(bottom=THIN)
        wb.save(path)
        print("styled Table1", path.name)


def main():
    for db in ("CHARLS", "ELSA", "HRS"):
        fix_table2_cohort(db)
    for path in sorted(TAB.glob("Table S7-*.xlsx")) + sorted(TAB.glob("Table S10-*.xlsx")):
        fix_s7_s10_header(path)
    scrub_all_footnotes()
    style_table1_light()
    # sync A1 for all tables to filename
    for path in sorted(TAB.glob("*.xlsx")):
        wb = load_workbook(path)
        ws = wb.active
        stem = path.stem
        if ws.cell(1, 1).value != stem:
            # keep × if already pretty, but role/number must match
            cur = str(ws.cell(1, 1).value or "")
            # if number/db prefix mismatch, force stem
            def norm(x: str) -> str:
                return re.sub(r"\s+", " ", x.replace("×", "x").replace("–", "-")).strip().lower()
            if norm(cur).split(".")[0] != norm(stem).split(".")[0]:
                ws.cell(1, 1).value = stem.replace(" x ", " × ")
                wb.save(path)
                print("A1 synced", path.name)


if __name__ == "__main__":
    main()
