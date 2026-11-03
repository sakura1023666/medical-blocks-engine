#!/usr/bin/env python3
"""Surgical pub-digits reformat for delivery xlsx.

Journal / ICMJE–NEJM numerical reporting (clinical tables):
  - Effect sizes (OR/HR/AUC/ΔAUC/NRI/IDI/Log-Loss/Z): fixed 3 decimals
  - P values (NEJM / ICMJE style):
      * P > 0.01  → 2 decimals (e.g. 0.63)
      * 0.001 ≤ P ≤ 0.01 → 3 decimals (e.g. 0.007)
      * P < 0.001 → "<0.001"  (never bare 0 / 0.000 / scientific)
      * P > 0.999 → ">0.999"
  - CI: "(lo, hi)" or "lo, hi" — use comma, not tilde
  - Near-zero probability metrics (|x|<0.001): "<0.001" / "−<0.001"
  - Hyperparameter tables: untouched

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


def fmt_est(x: float | str) -> str:
    return f"{float(x):.3f}"


def fmt_prob_metric(x: float) -> str:
    """AUC / NRI / IDI / Δ — 3dp; |x|<0.001 → <0.001 (journal: no ±0.000)."""
    if abs(x) < 0.001:
        return "−<0.001" if x < 0 else "<0.001"
    return f"{x:.3f}"


def fmt_p(s: str) -> str:
    """NEJM/ICMJE P reporting (not uniform 3dp)."""
    s = str(s).strip()
    if s in SKIP_VAL:
        return s
    if re.match(r"^<\s*0\.001$", s) or s.startswith("<"):
        return "<0.001"
    if re.match(r"^>\s*0\.999", s):
        return ">0.999"
    # bare 0 / 0.0 / 0.000 from software underflow → <0.001
    if re.fullmatch(r"0+(\.0+)?", s):
        return "<0.001"
    try:
        v = float(s)
    except Exception:
        return s
    if not (v == v):  # NaN
        return s
    if v < 0.001 or v <= 0:
        return "<0.001"
    if v > 0.999:
        return ">0.999"
    if v > 0.01:
        return f"{v:.2f}"
    return f"{v:.3f}"


def fmt_ci(s: str) -> str:
    s0 = str(s).strip()

    def _num(tok: str) -> str:
        """CI / NRI·IDI 点估计与区间：固定 3 位；允许 0.000（不是 P）。"""
        try:
            return fmt_est(float(tok))
        except Exception:
            return tok

    # (a, b) or (a,b)
    m = re.match(r"^\(\s*([-+0-9.eE]+)\s*[,，]\s*([-+0-9.eE]+)\s*\)$", s0)
    if m:
        return f"({_num(m.group(1))}, {_num(m.group(2))})"
    # (a - b) / (a – b)
    m = re.match(r"^\(\s*([-+0-9.eE]+)\s*[-–]\s*([-+0-9.eE]+)\s*\)$", s0)
    if m:
        return f"({_num(m.group(1))}, {_num(m.group(2))})"
    # a ~ b  → a, b  (DeLong legacy)
    m = re.match(r"^([-+0-9.eE]+)\s*[~～]\s*([-+0-9.eE]+)$", s0)
    if m:
        return f"{_num(m.group(1))}, {_num(m.group(2))}"
    # already "a, b" bare pair
    m = re.match(r"^([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)$", s0)
    if m:
        return f"{_num(m.group(1))}, {_num(m.group(2))}"
    # prefix: est [ lo - hi ]  (NRI/IDI cells)
    m = re.match(
        r"^(.*?:\s*)?([-+0-9.eE]+)\s*\[\s*([-+0-9.eE]+)\s*[-–]\s*([-+0-9.eE]+)\s*\]\s*$",
        s0,
    )
    if m:
        pref = m.group(1) or ""
        return (
            f"{pref}{_num(m.group(2))} "
            f"[{_num(m.group(3))}, {_num(m.group(4))}]"
        )
    # NRI(Continuous) [95% CI]: -0.485 [-0.644 - -0.326]
    m = re.match(
        r"^(NRI(?:\(Continuous\))?|IDI)\s*\[95%\s*CI\]:\s*"
        r"([-+0-9.eE]+)\s*\[\s*([-+0-9.eE]+)\s*[-–]\s*([-+0-9.eE]+)\s*\]\s*$",
        s0,
        re.I,
    )
    if m:
        lab = m.group(1)
        if lab.upper().startswith("NRI"):
            lab = "NRI(Continuous)" if "Continuous" in s0 or "continuous" in s0 else "NRI"
        return (
            f"{lab} [95% CI]: {_num(m.group(2))} "
            f"[{_num(m.group(3))}, {_num(m.group(4))}]"
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
    best = 0
    best_score = -1
    for i, row in enumerate(rows[:8]):
        cells = [str(c or "").strip() for c in row]
        joined = " ".join(cells).lower()
        if cells and re.match(r"^table\s", cells[0], re.I):
            continue
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


def sync_a1_to_filename(path: Path, ws) -> bool:
    """A1 title stem = filename stem (drop .xlsx)."""
    stem = path.stem
    a1 = ws.cell(1, 1).value
    if a1 is None:
        ws.cell(1, 1).value = stem
        return True
    s = str(a1).strip()
    # "Table S. Foo" → filename; or truncated title
    if s != stem and (
        re.match(r"^Table S\.", s)
        or re.match(r"^Table S\d", s)
        or re.match(r"^Table \d", s)
        or s.startswith("Table ")
    ):
        if s != stem:
            ws.cell(1, 1).value = stem
            return True
    return False


def reformat_file(path: Path) -> int:
    wb = load_workbook(path)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        return 0
    if re.search(r"Hyperparameter", path.name, re.I):
        # still sync A1 if needed
        n = 0
        if sync_a1_to_filename(path, ws):
            n = 1
            wb.save(path)
        return n

    hdr_i = find_header_row(rows)
    hdr = [str(c or "") for c in rows[hdr_i]]
    changed = 0
    if sync_a1_to_filename(path, ws):
        changed += 1

    for r_idx, row in enumerate(rows):
        if r_idx <= hdr_i:
            continue
        for c_idx, val in enumerate(row):
            if val is None:
                continue
            h = hdr[c_idx] if c_idx < len(hdr) else ""
            if isinstance(val, (int,)) and not isinstance(val, bool):
                if P_HDR.search(h) and val == 0:
                    cell = ws.cell(row=r_idx + 1, column=c_idx + 1)
                    if cell.value != "<0.001":
                        cell.value = "<0.001"
                        changed += 1
                continue
            s = str(val).strip()
            if s in SKIP_VAL or is_footnote(s):
                continue
            new = s
            if P_HDR.search(h):
                new = fmt_p(s)
            elif CI_HDR.search(h) or (
                ("~" in s or "～" in s)
                and re.search(r"[-+0-9.]", s)
            ):
                new = fmt_ci(s)
            elif (
                s.startswith("(")
                and s.endswith(")")
                and re.search(r"[-+0-9.]", s)
            ):
                new = fmt_ci(s)
            elif "[" in s and "]" in s and re.search(r"95%\s*CI|NRI|IDI", s, re.I):
                new = fmt_ci(s)
            elif EST_HDR.search(h.strip()):
                if "/" in s and "%" in s:
                    pass
                elif re.match(r"^[-+0-9.eE]+$", s):
                    try:
                        v = float(s)
                        # Z can be large; still 3dp
                        if re.search(r"AUC|accuracy|Sensitivity|Specificity|F1|Kappa|MCC|Log|Difference|OR|HR|New model|Baseline", h, re.I):
                            if re.search(r"Difference|AUC|NRI|IDI|Log|accuracy|Sensitivity|Specificity|F1|Kappa|MCC|OR|HR", h, re.I):
                                new = fmt_prob_metric(v) if re.search(
                                    r"Difference|AUC|accuracy|Sens|Spec|F1|Kappa|MCC|Log|OR|HR", h, re.I
                                ) else fmt_est(v)
                            else:
                                new = fmt_est(v)
                        else:
                            new = fmt_est(v)
                    except Exception:
                        pass
                else:
                    new = fmt_ci(s)
            elif isinstance(val, float):
                if P_HDR.search(h):
                    new = fmt_p(str(val))
                elif EST_HDR.search(h.strip()):
                    new = fmt_est(val)
            elif re.match(r"^[-+]?\d+\.\d{4,}$", s) or re.match(
                r"^[-+]?\d+[eE][-+]?\d+$", s
            ):
                try:
                    v = float(s)
                    new = fmt_p(s) if P_HDR.search(h) else fmt_est(v)
                except Exception:
                    pass

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
