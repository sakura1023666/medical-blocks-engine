#!/usr/bin/env python3
"""Surgical display scrub for published xlsx (全项目交付收口).

- underscores -> spaces; strip/replace CJK
- force Times New Roman on all cell/style fonts (pub_times_new_roman)

Preserves styles via openpyxl after stripping dangling drawings.
Usage:
  python3 python/pub_xlsx_scrub_display.py path.xlsx [path2.xlsx ...]
  python3 python/pub_xlsx_scrub_display.py --dir Tables/
  python3 python/pub_xlsx_scrub_display.py --dir Tables/ --times-only
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

CJK_RE = re.compile(r"[\u4e00-\u9fff]")

# Longest-first phrase map (Chinese -> English)
DICT = [
    (
        "无 Acute Renal Failure 列；eICU 队列依赖上游 D02 预筛（用户确认全部为 AKI），但上游 ICD/KDIGO 提取代码未随数据提供，无法在数据层复核 → 证据不足，不编造 ICD",
        "No Acute Renal Failure column; eICU cohort depends on upstream D02 pre-screen (user-confirmed AKI). Upstream ICD/KDIGO extraction code was not shipped with the data, so cohort definition cannot be re-verified at the data layer (insufficient evidence; no ICD codes invented).",
    ),
    (
        "主库含 Acute Renal Failure 旗标列（取值 Yes/No），据此识别 AKI 队列",
        "Primary database includes Acute Renal Failure flag (Yes/No) used to identify the AKI cohort",
    ),
    (
        "结局=28 天全因死亡（Survivor / Non-survivor）；随访上限 28 天，不存在任何更长随访窗",
        "Outcome = 28-day all-cause mortality (Survivor / Non-survivor); follow-up censored at 28 days",
    ),
    (
        "两库 fustatus 0/1 经 pipeline outcome as 01 正确映射死亡=1（Non-survivor）",
        "Both databases: fustatus 0/1 mapped via pipeline outcome as 01 (death=1, Non-survivor)",
    ),
    (
        "eICU 与 MIMIC-IV 同用 28 天口径；外验冻结主库资产、不重训",
        "eICU uses the same 28-day horizon as MIMIC-IV; external validation freezes primary-database assets without refitting",
    ),
    (
        "eICU 无 Acute Renal Failure 列；依赖上游 D02 预筛队列",
        "eICU has no Acute Renal Failure column; cohort relies on upstream D02 pre-screen",
    ),
    (
        "Acute Renal Failure 旗标（Yes/No）；已核实存在，n=26,055",
        "Acute Renal Failure flag (Yes/No); verified present, n=26,055",
    ),
    ("AKI 队列识别", "AKI cohort identification"),
    ("随访/结局", "Follow-up / outcome"),
    ("证据不足", "Insufficient evidence"),
    ("已证实", "Verified"),
    ("继承自 MIMIC-IV 冻结资产", "Inherited from MIMIC-IV frozen assets"),
    ("D02 result MIMIC.RData（实测）", "D02 result MIMIC.RData (verified)"),
    ("D02 result eICU.RData（实测）", "D02 result eICU.RData (verified)"),
    ("config 结局列 fustatus / 引擎 0-1 映射", "Config outcome column fustatus / engine 0-1 mapping"),
]


def scrub_text(s: str) -> str:
    out = s
    for zh, en in DICT:
        if zh in out:
            out = out.replace(zh, en)
    if "_" in out:
        out = out.replace("_", " ")
    if CJK_RE.search(out):
        out = CJK_RE.sub("", out)
        out = re.sub(r"\s{2,}", " ", out).strip()
        if not out:
            out = "[Chinese text removed]"
    return out


def strip_drawings(path: Path) -> None:
    """Best-effort: remove dangling drawing rels via zip rewrite if needed."""
    try:
        import zipfile
        from io import BytesIO

        data = path.read_bytes()
        zin = zipfile.ZipFile(BytesIO(data), "r")
        names = set(zin.namelist())
        bad_rels = []
        for n in names:
            if not n.endswith(".rels"):
                continue
            txt = zin.read(n).decode("utf-8", "ignore")
            if "drawings/drawing" in txt and not any(
                x.startswith("xl/drawings/") for x in names
            ):
                bad_rels.append(n)
        if not bad_rels:
            zin.close()
            return
        buf = BytesIO()
        with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                raw = zin.read(item.filename)
                if item.filename in bad_rels:
                    raw = re.sub(
                        rb'<Relationship[^>]*Target="[^"]*drawings/[^"]*"[^>]*/>',
                        b"",
                        raw,
                    )
                zout.writestr(item, raw)
        zin.close()
        path.write_bytes(buf.getvalue())
    except Exception as e:
        print(f"strip_drawings warn {path}: {e}", file=sys.stderr)


def force_times_fonts(wb) -> int:
    """Force Times New Roman on cell fonts and workbook style fonts (pub_times_new_roman)."""
    from copy import copy

    changed = 0
    for ws in wb.worksheets:
        for row in ws.iter_rows():
            for cell in row:
                f = cell.font
                if f is None:
                    continue
                name = f.name or ""
                if name != "Times New Roman":
                    nf = copy(f)
                    nf.name = "Times New Roman"
                    cell.font = nf
                    changed += 1
    fonts = getattr(wb, "_fonts", None)
    if fonts is not None:
        for style in list(fonts):
            if style is None:
                continue
            name = getattr(style, "name", None) or ""
            if name and name != "Times New Roman":
                try:
                    style.name = "Times New Roman"
                    changed += 1
                except Exception:
                    pass
    return changed


def scrub_file(path: Path, *, times_only: bool = False) -> tuple[int, int]:
    from openpyxl import load_workbook

    strip_drawings(path)
    wb = load_workbook(path)
    n_text = 0
    if not times_only:
        for ws in wb.worksheets:
            for row in ws.iter_rows():
                for cell in row:
                    v = cell.value
                    if not isinstance(v, str):
                        continue
                    s1 = scrub_text(v)
                    if s1 != v:
                        cell.value = s1
                        n_text += 1
            # sheet title
            if "_" in (ws.title or "") or CJK_RE.search(ws.title or ""):
                ws.title = scrub_text(ws.title)[:31]
                n_text += 1
    n_font = force_times_fonts(wb)
    if n_text or n_font:
        wb.save(path)
        strip_drawings(path)
    return n_text, n_font


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--dir", default="")
    ap.add_argument(
        "--times-only",
        action="store_true",
        help="Only force Times New Roman fonts (no underscore/CJK scrub)",
    )
    args = ap.parse_args()
    files: list[Path] = []
    if args.dir:
        files.extend(sorted(Path(args.dir).glob("*.xlsx")))
    files.extend(Path(p) for p in args.paths)
    if not files:
        print("no files", file=sys.stderr)
        return 1
    total_text = 0
    total_font = 0
    for f in files:
        if not f.exists():
            print(f"missing {f}", file=sys.stderr)
            continue
        n_text, n_font = scrub_file(f, times_only=bool(args.times_only))
        print(f"{f.name}\tedits={n_text}\tfonts={n_font}")
        total_text += n_text
        total_font += n_font
    print(f"TOTAL_EDITS\t{total_text}")
    print(f"TIMES_FONT_EDITS\t{total_font}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
