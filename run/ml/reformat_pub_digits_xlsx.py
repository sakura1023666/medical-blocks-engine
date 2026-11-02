#!/usr/bin/env python3
"""Surgical pub-digits reformat for delivery xlsx (est/p = 3; P<0.001 → <0.001).

Preserves openpyxl styles; only overwrites cell values.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

from openpyxl import load_workbook

EST_HDR = re.compile(
    r"^(OR|HR|AUC|accuracy|Sensitivity|Specificity|F1|Kappa|MCC|"
    r"Difference(\s+of\s+AUC)?|Log.?Loss|Z statistic|"
    r"New model|Baseline model)\b",
    re.I,
)
P_HDR = re.compile(r"P(\s|-)?value|P for|^\s*P\s*$", re.I)
CI_HDR = re.compile(r"95%\s*CI|\bCI$", re.I)
SKIP_VAL = {"Ref", "ref", "NE", "-", "—", "", "N/A"}


def fmt_est(x: float) -> str:
    return f"{float(x):.3f}"


def fmt_p(s: str) -> str:
    s = str(s).strip()
    if s in SKIP_VAL:
        return s
    if s.startswith("<"):
        return "<0.001"
    if re.match(r"^>0\.999", s):
        return ">0.999"
    # bare 0 / 0.0 / 0.000 → <0.001
    if re.fullmatch(r"0+(\.0+)?", s):
        return "<0.001"
    try:
        v = float(s)
    except Exception:
        return s
    if v < 0.001 or v <= 0:
        return "<0.001"
    return f"{v:.3f}"


def fmt_ci(s: str) -> str:
    s0 = str(s).strip()
    # (a,b) or (a, b)
    m = re.match(r"^\(\s*([-+0-9.eE]+)\s*[,，]\s*([-+0-9.eE]+)\s*\)$", s0)
    if m:
        return f"({fmt_est(m.group(1))}, {fmt_est(m.group(2))})"
    m = re.match(r"^\(\s*([-+0-9.eE]+)\s*[-–]\s*([-+0-9.eE]+)\s*\)$", s0)
    if m:
        return f"({fmt_est(m.group(1))}, {fmt_est(m.group(2))})"
    m = re.match(r"^([-+0-9.eE]+)\s*[~～]\s*([-+0-9.eE]+)$", s0)
    if m:
        return f"{fmt_est(m.group(1))} ~ {fmt_est(m.group(2))}"
    # prefix: est [ lo - hi ]
    m = re.match(
        r"^(.*?:\s*)?([-+0-9.eE]+)\s*\[\s*([-+0-9.eE]+)\s*[-–]\s*([-+0-9.eE]+)\s*\]\s*$",
        s0,
    )
    if m:
        pref = m.group(1) or ""
        return (
            f"{pref}{fmt_est(m.group(2))} "
            f"[{fmt_est(m.group(3))} - {fmt_est(m.group(4))}]"
        )
    return s0


def is_footnote(s: str) -> bool:
    if len(s) > 100 and " " in s:
        return True
    return bool(
        re.match(
            r"^(The |Multiple |Population|Software|Continuous|Statistical|Note)",
            s,
            re.I,
        )
    )


def find_header_row(rows) -> int:
    """Prefer real column header (has 'P value'/'OR'/'AUC' as a cell), not Table title."""
    best = 0
    best_score = -1
    for i, row in enumerate(rows[:8]):
        cells = [str(c or "").strip() for c in row]
        joined = " ".join(cells).lower()
        if cells and re.match(r"^table\s", cells[0], re.I):
            continue  # title row
        score = 0
        for c in cells:
            cl = c.lower()
            if re.search(r"p(\s|-)?value|^or$|^hr$|^auc$|95%\s*ci|nri|idi|model", cl):
                score += 2
            if cl in {"or", "hr", "auc", "nri", "idi"}:
                score += 2
        if any(k in joined for k in ("p-value", "p value", "auc", "95%ci")):
            score += 1
        if score > best_score:
            best_score = score
            best = i
    return best


def reformat_file(path: Path) -> int:
    wb = load_workbook(path)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        return 0
    hdr_i = find_header_row(rows)
    hdr = [str(c or "") for c in rows[hdr_i]]
    changed = 0
    # hyperparameter table: leave alone (algorithm params)
    if re.search(r"Hyperparameter", path.name, re.I):
        return 0
    for r_idx, row in enumerate(rows):
        if r_idx <= hdr_i:
            continue
        for c_idx, val in enumerate(row):
            if val is None:
                continue
            if isinstance(val, (int,)) and not isinstance(val, bool):
                # integers (counts) — leave; except lone 0 in P column
                h = hdr[c_idx] if c_idx < len(hdr) else ""
                if P_HDR.search(h) and val == 0:
                    cell = ws.cell(row=r_idx + 1, column=c_idx + 1)
                    if cell.value != "<0.001":
                        cell.value = "<0.001"
                        changed += 1
                continue
            s = str(val).strip()
            if s in SKIP_VAL or is_footnote(s):
                continue
            h = hdr[c_idx] if c_idx < len(hdr) else ""
            new = s
            if P_HDR.search(h):
                new = fmt_p(s)
            elif CI_HDR.search(h) or (
                s.startswith("(") and s.endswith(")")
            ) or ("[" in s and "]" in s) or ("~" in s):
                new = fmt_ci(s)
            elif EST_HDR.search(h.strip()):
                if "/" in s and "%" in s:
                    pass
                elif re.match(r"^[-+0-9.eE]+$", s):
                    try:
                        new = fmt_est(float(s))
                    except Exception:
                        pass
                else:
                    new = fmt_ci(s)
            elif re.match(r"^[-+]?\d+\.\d{4,}$", s) or re.match(
                r"^[-+]?\d+e[-+]?\d+$", s, re.I
            ):
                # long float anywhere in ML/assoc tables
                try:
                    v = float(s)
                    if P_HDR.search(h) or (
                        "P value" in " ".join(hdr) and c_idx >= len(hdr) - 2
                    ):
                        new = fmt_p(s)
                    else:
                        new = fmt_est(v)
                except Exception:
                    pass
            # DeLong P column often last and numeric 0 as float
            if isinstance(val, float):
                if P_HDR.search(h):
                    new = fmt_p(str(val))
                elif EST_HDR.search(h.strip()) or CI_HDR.search(h):
                    new = fmt_est(val) if EST_HDR.search(h.strip()) else s
                elif abs(val) < 1 and len(f"{val}") > 6:
                    # likely metric with long repr
                    new = fmt_est(val)

            if new != s:
                ws.cell(row=r_idx + 1, column=c_idx + 1).value = new
                changed += 1
    if changed:
        wb.save(path)
    return changed


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: reformat_pub_digits_xlsx.py <dir-or-xlsx>...", file=sys.stderr)
        return 2
    total = 0
    for a in argv[1:]:
        p = Path(a)
        files = [p] if p.is_file() else sorted(p.glob("*.xlsx"))
        for f in files:
            n = reformat_file(f)
            print(f"{f.name}: changed={n}")
            total += n
    print(f"TOTAL_CHANGED={total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
