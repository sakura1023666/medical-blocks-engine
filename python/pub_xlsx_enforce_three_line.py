#!/usr/bin/env python3
"""Surgically enforce SCI three-line (booktabs) borders on delivered xlsx.

Rules (display-layer only; zero value/row/column edits):
  * locate optional title row (single long cell at top), header row (first row
    with >=2 non-empty cells), and footnote block start (first single-cell row
    with len>=50 after the header; everything above = table body).
  * clear ALL borders in the sheet; then draw exactly three horizontal rules:
      top rule    = medium, above header row
      header rule = thin,   below header row
      bottom rule = medium, below last body row (never below footnotes)
  * no vertical borders anywhere; gridlines display off.
Idempotent: re-running produces the same result.

Usage:
  python3 python/pub_xlsx_enforce_three_line.py a.xlsx [b.xlsx ...]
  python3 python/pub_xlsx_enforce_three_line.py --dir Tables/
"""
from __future__ import annotations

import argparse
import re
import sys
import zipfile
from io import BytesIO
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.styles import Border, Side
from openpyxl.worksheet.properties import PageSetupProperties

THICK = Side(style="medium", color="FF000000")
THIN = Side(style="thin", color="FF000000")
NONE = Side(style=None)


def strip_dangling_drawings(path: Path) -> None:
    """openpyxl chokes on openxlsx dangling drawing rels -> remove refs in zip."""
    try:
        zin = zipfile.ZipFile(BytesIO(path.read_bytes()), "r")
        names = set(zin.namelist())
        bad = []
        for n in names:
            if not n.endswith(".rels"):
                continue
            txt = zin.read(n).decode("utf-8", "ignore")
            if "drawings/drawing" in txt and not any(x.startswith("xl/drawings/") for x in names):
                bad.append(n)
        if not bad:
            zin.close()
            return
        buf = BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                raw = zin.read(item.filename)
                if item.filename in bad:
                    raw = re.sub(
                        rb'<Relationship[^>]*Target="[^"]*drawings/[^"]*"[^>]*/>',
                        b"", raw,
                    )
                zout.writestr(item, raw)
        zin.close()
        path.write_bytes(buf.getvalue())
    except Exception as e:  # keep best-effort like sibling tools
        print(f"strip_dangling_drawings warn {path}: {e}", file=sys.stderr)


def _row_cells(ws, r):
    return [ws.cell(row=r, column=c) for c in range(1, ws.max_column + 1)]


def _nonempty_cells(row_cells):
    return [c for c in row_cells if c.value is not None and str(c.value).strip() != ""]


def _looks_like_footnote(v: str) -> bool:
    """Single-cell row text: footnote block vs in-body category/level label."""
    v = v.strip()
    if len(v) >= 50:
        return True
    # sentence-style label ending in punctuation = footnote ("NE = ... (n = 5).")
    if len(v) >= 15 and v.endswith((".", ";", ":")):
        return True
    return False


def find_layout(ws):
    """Return (header_row, last_body_row) 1-based, or None if not a table."""
    maxr = ws.max_row
    first_data = None
    for r in range(1, maxr + 1):
        if len(_nonempty_cells(_row_cells(ws, r))) >= 2:
            first_data = r
            break
    if first_data is None:
        return None
    header = first_data
    last_body = header
    for r in range(header + 1, maxr + 1):
        cells = _nonempty_cells(_row_cells(ws, r))
        if len(cells) == 0:
            continue
        if len(cells) >= 2:
            last_body = r
        else:
            v = str(cells[0].value)
            if _looks_like_footnote(v):
                break  # footnote/title block starts here
            last_body = r  # short in-body label (Yes / No / Class 1)
    return header, last_body


TITLE_RE = re.compile(r"^(Supplementary\s+)?Table\s+[S\d]", re.I)


def relocate_annotations_to_top(ws, title_stem=None) -> int:
    """Move table title + footnote block (single-cell rows below the body)
    ABOVE the header (reference/journal style: 标注在开头).

    Only touches display layout: cell values are preserved verbatim, reordered.
    Row 1 = filename-stem title (P0: 内题=文件名); other "Table N." descriptive
    lines are kept as subtitle rows, then the remaining annotation lines.
    Body rows are rewritten unchanged below them.
    Returns number of rows moved (0 = nothing to do / unsafe structure).
    """
    layout = find_layout(ws)
    if layout is None:
        return 0
    header, last_body = layout
    maxr, maxc = ws.max_row, ws.max_column

    ann_below = []
    for r in range(last_body + 1, maxr + 1):
        cells = _nonempty_cells(_row_cells(ws, r))
        if len(cells) == 0:
            continue
        if len(cells) > 1:
            return 0  # non-annotation multi-cell content below body: leave as is
        ann_below.append(str(cells[0].value).strip())

    ann_above = []
    for r in range(1, header):
        cells = _nonempty_cells(_row_cells(ws, r))
        if len(cells) >= 2:
            return 0
        if cells:
            ann_above.append(str(cells[0].value).strip())

    if not ann_below:
        return 0  # already top-annotated (engine title-only layout ok)

    # titles first (unique, keep order), then notes; dedup
    all_ann = ann_above + ann_below
    titles = [t for t in all_ann if TITLE_RE.match(t)]
    notes = [t for t in all_ann if not TITLE_RE.match(t)]
    seen, ordered = set(), []
    stem = (title_stem or "").strip()
    if stem and TITLE_RE.match(stem):
        # P0 内题=文件名：第 1 行固定为文件名 stem；更长的原标题行降为副题
        ordered.append(stem)
        seen.add(stem)
    for t in titles + notes:
        if t not in seen:
            seen.add(t)
            ordered.append(t)

    body = []
    for r in range(header, last_body + 1):
        body.append([ws.cell(row=r, column=c).value for c in range(1, maxc + 1)])

    # wipe sheet (values + merges), then rewrite: notes block + body
    for mr in list(ws.merged_cells.ranges):
        ws.unmerge_cells(str(mr))
    for row in ws.iter_rows():
        for c in row:
            c.value = None

    try:
        from openpyxl.styles import Alignment, Font
    except Exception:
        Alignment = Font = None

    for i, txt in enumerate(ordered, start=1):
        c = ws.cell(row=i, column=1, value=txt)
        if Alignment is not None:
            c.alignment = Alignment(
                horizontal="center" if i == 1 else "left",
                vertical="top", wrap_text=True)
            c.font = Font(name="Times New Roman", size=12,
                          bold=(i == 1 and bool(TITLE_RE.match(txt))))
        try:
            ws.merge_cells(start_row=i, start_column=1, end_row=i, end_column=maxc)
            est = max(1, (len(txt) // 110) + 1)
            ws.row_dimensions[i].height = 16 * est + 4
        except Exception:
            pass
    body_start = len(ordered) + 1
    for ri, rowvals in enumerate(body):
        r = body_start + ri
        for ci, v in enumerate(rowvals, start=1):
            cell = ws.cell(row=r, column=ci)
            cell.value = v
            # shifted rows lose their old per-row styles; re-apply base look
            if Font is not None:
                if ri == 0:  # header row
                    cell.font = Font(name="Times New Roman", size=12, bold=True)
                    if Alignment is not None:
                        cell.alignment = Alignment(horizontal="center",
                                                   vertical="center",
                                                   wrap_text=True)
                else:
                    cell.font = Font(name="Times New Roman", size=12)
                    if Alignment is not None:
                        cell.alignment = Alignment(
                            horizontal="left" if ci == 1 else "center",
                            vertical="center")
    return len(ann_below)


def enforce(path: Path, notes_top: bool = True) -> str:
    strip_dangling_drawings(path)
    wb = load_workbook(path)
    touched = 0
    moved = 0
    for ws in wb.worksheets:
        try:
            ws.sheet_view.showGridLines = False
        except Exception:
            pass
        if notes_top:
            moved += relocate_annotations_to_top(ws)
        layout = find_layout(ws)
        if layout is None:
            continue
        header, last_body = layout
        # clear every border in the sheet
        for row in ws.iter_rows():
            for c in row:
                c.border = Border()
        for c in _row_cells(ws, header):
            c.border = Border(top=THICK, bottom=THIN)
        for c in _row_cells(ws, last_body):
            b = c.border
            c.border = Border(top=b.top, bottom=THICK, left=b.left, right=b.right)
        touched += 1
    if touched == 0:
        return f"skip(no table): {path.name}"
    wb.save(path)
    # openpyxl roundtrip leaves xml:space / dangling refs -> sibling strip tool
    strip_tool = Path(__file__).resolve().parent.parent / "R" / "pub_xlsx_tools" / "xlsx_strip.py"
    if strip_tool.exists():
        import subprocess

        subprocess.run([sys.executable, str(strip_tool), str(path)],
                       check=False, capture_output=True)
    return (f"three-line enforced ({touched} sheet, {moved} note-block(s) moved to top): "
            f"{path.name}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", type=Path)
    ap.add_argument("--dir", type=Path, default=None)
    ns = ap.parse_args()
    files = list(ns.files)
    if ns.dir is not None:
        files += sorted(ns.dir.glob("*.xlsx"))
    if not files:
        ap.error("no xlsx given")
    # allow running from any cwd: import sibling strip helper
    here = Path(__file__).resolve().parent
    sys.path.insert(0, str(here))
    sys.path.insert(0, str(here.parent / "R" / "pub_xlsx_tools"))
    rc = 0
    for f in files:
        if f.name.startswith("~$"):
            continue
        try:
            print(enforce(f))
        except Exception as e:
            rc = 1
            print(f"FAIL {f}: {e}", file=sys.stderr)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
