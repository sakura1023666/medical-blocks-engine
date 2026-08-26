#!/usr/bin/env python3
"""从现有超长 Table1.tex 剔除时间戳/ID 展开行，重写精简三线表 xlsx + tex。"""
from __future__ import annotations

import re
import shutil
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, Side
from openpyxl.utils import get_column_letter

FONT = "Times New Roman"
DROP_LABELS = {
    "admit time",
    "disch time",
    "icu intime",
    "icu outtime",
    "tst time zero",
    "hadm id",
    "subject id",
    "tst patient id",
    "stay id",
}

PROJ = Path("/mnt/g/02block_result/11_ischemic stroke/two_stage_transformer_40041421")
SRC_TEX = (
    PROJ
    / "_shared/step06_baseline_binary/Tables"
    / "Table 1-MIMIC. Baseline characteristics of IschemicStroke TwoStageTransformer.tex"
)
OUT_DIR = PROJ / "_shared/step06_baseline_binary/Tables"
SUMMARY = PROJ / "summary_results" / "Tables" / "Table 1-MIMIC-Baseline_characteristics.xlsx"


def _norm_label(s: str) -> str:
    s = re.sub(r"\\textbf\{([^}]*)\}", r"\1", s)
    s = re.sub(r"\\[a-zA-Z]+\{([^}]*)\}", r"\1", s)
    s = s.replace("\\{", "{").replace("\\}", "}")
    s = re.sub(r"\s+", " ", s).strip().lower()
    return s


def _split_row(line: str) -> list[str] | None:
    line = line.rstrip()
    if not line.endswith("\\\\"):
        return None
    body = line[:-2].strip()
    if "&" not in body:
        return None
    # strip leading \multicolumn{1}{c}{...}
    parts = [p.strip() for p in body.split("&")]
    return parts


def _cell_plain(tex_cell: str) -> str:
    s = tex_cell.strip()
    m = re.match(r"\\multicolumn\{1\}\{c\}\{(.*)\}$", s)
    if m:
        s = m.group(1)
    s = s.replace(r"\textless{}", "<").replace(r"\textgreater{}", ">")
    s = re.sub(r"\\textbf\{([^}]*)\}", r"\1", s)
    s = s.replace(r"\%", "%").replace(r"\_", "_")
    s = s.replace("{}", "").strip()
    return s


def filter_tex_rows(lines: list[str]) -> tuple[list[str], list[list[str]]]:
    """返回精简 tex 行 + 解析后的表体行（含表头）。"""
    out_lines: list[str] = []
    table_rows: list[list[str]] = []
    dropping = False
    in_tabular = False
    header_done = False

    for line in lines:
        if "\\begin{tabular}" in line:
            in_tabular = True
            out_lines.append(line)
            continue
        if "\\end{tabular}" in line:
            in_tabular = False
            dropping = False
            out_lines.append(line)
            continue
        if not in_tabular:
            out_lines.append(line)
            continue

        # booktabs rules / empty
        if any(k in line for k in ("\\toprule", "\\midrule", "\\bottomrule")):
            dropping = False
            out_lines.append(line)
            continue

        parts = _split_row(line)
        if parts is None:
            if not dropping:
                out_lines.append(line)
            continue

        first = parts[0].strip()
        plain0 = _cell_plain(first)
        label = _norm_label(plain0)
        is_level = first.startswith("\\multicolumn") and "characteristic" not in label

        # header row (often wrapped in \multicolumn + \textbf)
        if (not header_done) and ("characteristic" in label):
            header_done = True
            dropping = False
            out_lines.append(line)
            table_rows.append([_cell_plain(p) for p in parts])
            continue

        if is_level:
            if dropping:
                continue
            out_lines.append(line)
            if header_done:
                table_rows.append([_cell_plain(p) for p in parts])
            continue

        # characteristic / section
        if label in DROP_LABELS:
            dropping = True
            continue

        dropping = False
        out_lines.append(line)
        if header_done:
            table_rows.append([_cell_plain(p) for p in parts])

    return out_lines, table_rows


def write_xlsx(path: Path, title: str, rows: list[list[str]], footnotes: list[str]) -> None:
    if not rows:
        raise SystemExit("no table rows after filter")
    hdr = rows[0]
    body = rows[1:]
    nc = len(hdr)

    thick = Side(style="medium", color="000000")
    thin = Side(style="thin", color="000000")
    border_header = Border(top=thick, bottom=thin)
    border_last = Border(bottom=thick)
    border_foot = Border(top=thin)
    font_title = Font(name=FONT, size=12, bold=True)
    font_hdr = Font(name=FONT, size=12, bold=True)
    font_body = Font(name=FONT, size=12)
    font_sec = Font(name=FONT, size=12, bold=True)
    align_c = Alignment(horizontal="center", vertical="center", wrap_text=True)
    align_l = Alignment(horizontal="left", vertical="center", wrap_text=True)

    wb = Workbook()
    ws = wb.active
    ws.title = "Table"
    ws.sheet_view.showGridLines = False

    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=nc)
    c = ws.cell(1, 1, title)
    c.font = font_title
    c.alignment = align_c

    r0 = 2
    for j, h in enumerate(hdr, 1):
        cell = ws.cell(r0, j, h)
        cell.font = font_hdr
        cell.alignment = align_c
        cell.border = border_header

    for i, row in enumerate(body):
        er = r0 + 1 + i
        is_last = i == len(body) - 1
        # pad
        while len(row) < nc:
            row.append("")
        is_section = bool(row[0]) and all(not str(x).strip() for x in row[1:nc])
        for j in range(1, nc + 1):
            val = row[j - 1] if j - 1 < len(row) else ""
            cell = ws.cell(er, j, val)
            if is_section and j == 1:
                cell.font = font_sec
            else:
                cell.font = font_body
            cell.alignment = align_l if j == 1 and not (
                str(val).startswith(("Female", "Male", "Asian", "Black", "Hispanic", "Other", "White", "Married", "Single", "English"))
                or (str(val) and not any(row[k].strip() for k in range(1, nc) if k < len(row)) and False)
            ) else (align_c if j > 1 else align_l)
            # level rows often have empty p-value; center first col if looks like level (no stats in col0 long)
            if j == 1 and is_section:
                cell.alignment = align_l
            elif j == 1 and not is_section and row[1:]:
                # if first col short category level under parent — still left
                cell.alignment = align_l
            if is_last:
                cell.border = border_last

    last = r0 + len(body)
    for k, note in enumerate(footnotes):
        fr = last + 1 + k
        ws.merge_cells(start_row=fr, start_column=1, end_row=fr, end_column=nc)
        cell = ws.cell(fr, 1, note)
        cell.font = font_body
        cell.alignment = align_l
        if k == 0:
            cell.border = border_foot

    for j in range(1, nc + 1):
        maxlen = len(str(hdr[j - 1]))
        for row in body:
            if j - 1 < len(row):
                maxlen = max(maxlen, min(len(str(row[j - 1])), 40))
        ws.column_dimensions[get_column_letter(j)].width = min(max(maxlen + 2, 12), 36)
    ws.row_dimensions[1].height = 22
    path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(path)


def main() -> None:
    raw = SRC_TEX.read_text(encoding="utf-8", errors="replace")
    lines = raw.splitlines()
    n_before = sum(1 for ln in lines if ln.rstrip().endswith("\\\\") and "&" in ln)
    new_lines, rows = filter_tex_rows(lines)
    n_after = sum(1 for ln in new_lines if ln.rstrip().endswith("\\\\") and "&" in ln)
    print(f"tex data rows {n_before} -> {n_after}; parsed body+hdr={len(rows)}")

    # backup originals once
    bak = OUT_DIR / (SRC_TEX.name + ".with_timestamps.bak")
    if not bak.is_file() and SRC_TEX.is_file():
        shutil.copy2(SRC_TEX, bak)
        print(f"backup tex -> {bak.name}")
    xlsx_src = OUT_DIR / SRC_TEX.name.replace(".tex", ".xlsx")
    bak_x = OUT_DIR / (xlsx_src.name + ".with_timestamps.bak")
    if xlsx_src.is_file() and not bak_x.is_file():
        shutil.copy2(xlsx_src, bak_x)
        print(f"backup xlsx -> {bak_x.name}")

    out_tex = OUT_DIR / SRC_TEX.name
    out_tex.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
    print(f"wrote {out_tex}")

    title = "Table 1. Baseline characteristics of IschemicStroke TwoStageTransformer"
    footnotes = [
        "Continuous variables: median (IQR); categorical: n (%).",
        "Timestamp / ID columns (admit_time, disch_time, icu_intime, icu_outtime, tst_time_zero, hadm_id, subject_id, tst_patient_id) excluded — they expand to one row per unique value.",
        "【场景迁移】MIMIC ischemic stroke cohort (not paper eICU sepsis).",
    ]
    write_xlsx(xlsx_src, title, rows, footnotes)
    print(f"wrote {xlsx_src}")

    # summary_results copy
    SUMMARY.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(xlsx_src, SUMMARY)
    print(f"copied -> {SUMMARY}")

    # trim var lists
    for name in ("categorical_vars.txt", "continuous_vars.txt"):
        p = PROJ / "_shared/step06_baseline_binary" / name
        if not p.is_file():
            continue
        drop = {
            "admit_time",
            "disch_time",
            "icu_intime",
            "icu_outtime",
            "tst_time_zero",
            "hadm_id",
            "subject_id",
            "tst_patient_id",
            "stay_id",
        }
        lines0 = [ln.strip() for ln in p.read_text(encoding="utf-8").splitlines() if ln.strip()]
        kept = [ln for ln in lines0 if ln not in drop]
        if len(kept) != len(lines0):
            p.write_text("\n".join(kept) + "\n", encoding="utf-8")
            print(f"trimmed {name}: {len(lines0)} -> {len(kept)}")


if __name__ == "__main__":
    main()
