#!/usr/bin/env python3
"""Rebuild Table S1 (MOESM1 role) for a liver DB-pool cohort.

Layout columns match Additional File 1 Table S1:
  Variable | Total measurements (N) | Outliers clipped after normalisation
           |                        |   N clipped | % of total
           | Before / After removal/clipping (original scale) Median [IQR]
           | Normal physiological range

Formatting matches main Tables (Times New Roman 12, three-line, no blue fill).

N clipped (post-normalisation):
  Scale *raw* measurements with train-set q5/q95, count |x_norm| > 4.
  (Counting after physio-cap yields ~0 because q5/q95 were fit on clipped train data.)
Before/After medians: raw vs after physiological-range clip on the original scale.
"""
from __future__ import annotations

import argparse
import json
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import numpy as np
import pandas as pd
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, Side
from openpyxl.utils import get_column_letter

_DISPLAY = [
    ("heart_rate", "Heart rate (/min)"),
    ("invasive_systolic_blood_pressure", "Inv. Syst. Art. pressure (mmHg)"),
    ("invasive_diastolic_blood_pressure", "Inv. Diast. Art. pressure (mmHg)"),
    ("invasive_mean_blood_pressure", "Inv. Mean Art. pressure (mmHg)"),
    ("noninvasive_systolic_blood_pressure", "Non-inv. Syst. Art. pressure (mmHg)"),
    ("noninvasive_diastolic_blood_pressure", "Non-inv. Diast. Art. pressure (mmHg)"),
    ("noninvasive_mean_blood_pressure", "Non-inv. Mean Art. pressure (mmHg)"),
    ("O2_arterial_saturation", "O² Sat. in Art. blood (%)"),
    ("temperature", "Temperature (°C)"),
    ("lactate", "Lactate (mmol/L)"),
    ("blood_glucose", "Glucose (mmol/L)"),
    ("magnesium", "Magnesium (mmol/L)"),
    ("sodium", "Sodium (mmol/L)"),
    ("creatinine", "Creatinine (µmol/L)"),
    ("calcium", "Calcium (mmol/L)"),
    ("chloride", "Chloride (mmol/L)"),
    ("potassium", "Potassium (mmol/L)"),
    ("PTT", "PTT (s)"),
    ("bilirubine", "Bilirubin (µmol/L)"),
    ("alanine_aminotransferase", "ALT (U/L)"),
    ("aspartate_aminotransferase", "AST (U/L)"),
    ("alkaline_phosphatase", "Alkaline phosphatase (U/L)"),
    ("albumin", "Albumin (g/L)"),
    ("phosphate", "Phosphate (mmol/L)"),
    ("bicarbonate", "Bicarbonate (mmol/L)"),
    ("blood_urea_nitrogen", "BUN (mmol/L)"),
    ("pH", "pH"),
    ("paO2", "PaO₂ (mmHg)"),
    ("paCO2", "PaCO₂ (mmHg)"),
    ("hemoglobin", "Haemoglobin (g/dL)"),
    ("white_blood_cells", "White blood cells (G/L)"),
    ("platelets", "Platelets (G/L)"),
    ("urine_output", "Urine output (mL/h)"),
    ("glasgow_coma_score", "Glasgow Coma Score (total)"),
    ("glasgow_coma_score_eye", "GCS Eye"),
    ("glasgow_coma_score_motor", "GCS Motor"),
    ("glasgow_coma_score_verbal", "GCS Verbal"),
]

_PHYSIO_CLIP = {
    "heart_rate": (46.74, 122.7),
    "invasive_systolic_blood_pressure": (67.78, 175.8),
    "invasive_diastolic_blood_pressure": (33.34, 84.24),
    "invasive_mean_blood_pressure": (46.95, 113.2),
    "noninvasive_systolic_blood_pressure": (70.5, 169.5),
    "noninvasive_diastolic_blood_pressure": (32.87, 97.12),
    "noninvasive_mean_blood_pressure": (44.37, 115.6),
    "O2_arterial_saturation": (88.7, 103.7),
    "temperature": (35.61, 38.23),
    "lactate": (0.70, 2.2),
    "blood_glucose": (2.800, 12.4),
    "magnesium": (0.533, 1.193),
    "sodium": (130.0, 148.0),
    "creatinine": (46.6, 110.0),
    "calcium": (1.675, 2.425),
    "chloride": (92.5, 119.5),
    "potassium": (2.9, 5.299),
    "PTT": (1.449, 72.55),
    "bilirubine": (23.6, 51.47),
    "alanine_aminotransferase": (10.0, 40.0),
    "aspartate_aminotransferase": (10.0, 40.0),
    "alkaline_phosphatase": (28.5, 202.5),
    "albumin": (10.0, 40.0),
    "phosphate": (0.315, 1.816),
    "bicarbonate": (15.7, 32.5),
    "blood_urea_nitrogen": (-5.14, 22.15),
    "pH": (7.235, 7.564),
    "paO2": (25.90, 163.9),
    "paCO2": (22.59, 55.6),
    "hemoglobin": (6.021, 13.97),
    "white_blood_cells": (0.500, 22.09),
    "platelets": (150.0, 370.5),
    "urine_output": (100.0, 368.8),
    "glasgow_coma_score": (-1.0, 23.0),
    "glasgow_coma_score_eye": (2.5, 5.5),
    "glasgow_coma_score_motor": (0.5, 9.5),
    "glasgow_coma_score_verbal": (3.5, 6.5),
}


def _fmt_int(n: int) -> str:
    return f"{n:,}"


def _fmt_pct(n_clip: int, n_tot: int) -> str:
    if n_tot <= 0:
        return "—"
    if n_clip == 0:
        return "0"
    pct = 100.0 * n_clip / n_tot
    if pct < 0.01:
        return "< 0.01"
    if pct < 1:
        return f"{pct:.2f}".rstrip("0").rstrip(".")
    if pct < 10:
        return f"{pct:.2f}".rstrip("0").rstrip(".")
    return f"{pct:.1f}".rstrip("0").rstrip(".")


def _fmt_med_iqr(x: np.ndarray) -> str:
    if x.size == 0:
        return "—"
    q25, q50, q75 = np.percentile(x, [25, 50, 75])

    def f(v: float) -> str:
        av = abs(v)
        if av >= 100:
            s = f"{v:.1f}"
        elif av >= 10:
            s = f"{v:.2f}"
        else:
            s = f"{v:.3f}"
        return s.rstrip("0").rstrip(".") if "." in s else s

    return f"{f(q50)} [{f(q25)} - {f(q75)}]"


def _fmt_range(lo: float, hi: float) -> str:
    def f(v: float) -> str:
        return f"{v:.4f}".rstrip("0").rstrip(".")

    return f"[{f(lo)} - {f(hi)}]"


def _norm_clip_count(x: np.ndarray, q_lo: float, q_hi: float, clip_lo: float, clip_hi: float) -> int:
    denom = float(q_hi - q_lo)
    if denom <= 0:
        denom = 1e-12
    norm = 2.0 * (x - q_lo) / denom - 1.0
    return int(np.sum((norm < clip_lo) | (norm > clip_hi)))


def _read_stay(args):
    pth, cols = args
    try:
        df = pd.read_parquet(pth)
    except Exception:
        return None
    out = {}
    for c in cols:
        if c not in df.columns:
            continue
        s = pd.to_numeric(df[c], errors="coerce").to_numpy(dtype=np.float64)
        s = s[np.isfinite(s)]
        if s.size:
            out[c] = s
    return out


def collect_values(blended: Path, keep_patients: set[str], cols: list[str], workers: int):
    bags = {c: [] for c in cols}
    jobs = []
    for db in ("eicu", "amsterdam", "hirid", "mimic4"):
        idx_p = blended / "preprocessed_timeseries" / db / "index.csv"
        if not idx_p.exists():
            continue
        idx = pd.read_csv(idx_p, sep=";")
        if "patient" not in idx.columns or "ts_pth" not in idx.columns:
            continue
        idx = idx[idx["patient"].astype(str).isin(keep_patients)]
        for _, r in idx.iterrows():
            pth = Path(str(r["ts_pth"]))
            if pth.exists():
                jobs.append((str(pth), cols))
    print(f"[S1] scanning {len(jobs)} stays × {len(cols)} vars, workers={workers}", flush=True)
    done = 0
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = [ex.submit(_read_stay, j) for j in jobs]
        for fut in as_completed(futs):
            got = fut.result()
            done += 1
            if done % 2000 == 0 or done == len(jobs):
                print(f"[S1] {done}/{len(jobs)}", flush=True)
            if not got:
                continue
            for c, arr in got.items():
                bags[c].append(arr)
    merged = {}
    for c, parts in bags.items():
        merged[c] = np.concatenate(parts) if parts else np.array([], dtype=np.float64)
        print(f"[S1] {c}: n={merged[c].size:,}", flush=True)
    return merged


def build_rows(merged, q5: dict, q95: dict, drop: set[str], clip_lo=-4.0, clip_hi=4.0):
    rows = []
    for col, label in _DISPLAY:
        if col in drop or col not in _PHYSIO_CLIP:
            continue
        raw = merged.get(col)
        if raw is None or raw.size == 0:
            continue
        lo, hi = _PHYSIO_CLIP[col]
        after_phys = np.clip(raw, lo, hi)
        n_tot = int(raw.size)
        n_clip = 0
        q_note = ""
        if col in q5 and col in q95:
            q_lo = float(q5[col])
            q_hi = float(q95[col])
            # Count post-norm outliers on RAW (pre-physio) values — matches MOESM1
            # non-zero N clipped; physio-cap-then-count is ~0 when q5/q95 fit after clip.
            n_clip = _norm_clip_count(raw, q_lo, q_hi, clip_lo, clip_hi)
            if n_tot > 0 and (n_clip / n_tot > 0.5 or (q_hi - q_lo) < 1e-6):
                eq5, eq95 = np.percentile(raw, [5, 95])
                n_clip = _norm_clip_count(raw, float(eq5), float(eq95), clip_lo, clip_hi)
                q_note = "empirical_q"
        n_after = n_tot - n_clip
        tot_s = _fmt_int(n_tot) if n_clip == 0 else f"{_fmt_int(n_tot)} – {_fmt_int(n_after)}"
        rows.append(
            {
                "Variable": label,
                "Total measurements (N)": tot_s,
                "N clipped": _fmt_int(n_clip) if n_clip else "0",
                "% of total": _fmt_pct(n_clip, n_tot),
                "Before Median [IQR]": _fmt_med_iqr(raw),
                "After Median [IQR]": _fmt_med_iqr(after_phys),
                "Normal physiological range": _fmt_range(lo, hi),
                "_col": col,
                "_n": n_tot,
                "_n_clip": n_clip,
                "_q_note": q_note,
            }
        )
    return rows


def write_xlsx(rows, out_xlsx: Path, title: str, footnote: str):
    """Times New Roman 12 three-line table — same visual language as main Tables."""
    wb = Workbook()
    ws = wb.active
    ws.title = "Table"
    ws.sheet_view.showGridLines = False
    nc = 7
    thick = Side(style="medium", color="000000")
    thin = Side(style="thin", color="000000")
    font_title = Font(name="Times New Roman", bold=True, size=12)
    font_h = Font(name="Times New Roman", bold=True, size=12)
    font_b = Font(name="Times New Roman", size=12)
    font_fn = Font(name="Times New Roman", size=10)
    align_c = Alignment(horizontal="center", vertical="center", wrap_text=True)
    align_l = Alignment(horizontal="left", vertical="center", wrap_text=True)

    # title
    cell = ws.cell(1, 1, title)
    cell.font = font_title
    cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=nc)
    ws.row_dimensions[1].height = 28

    headers_top = [
        "Variable",
        "Total measurements (N)",
        "Outliers clipped after normalisation",
        "Outliers clipped after normalisation",
        "Before removal/clipping (original scale)",
        "After removal/clipping (original scale)",
        "Normal physiological range",
    ]
    headers_sub = ["", "", "N clipped", "% of total", "Median [IQR]", "Median [IQR]", ""]
    for c, (a, b) in enumerate(zip(headers_top, headers_sub), 1):
        cell = ws.cell(2, c, a)
        cell.font = font_h
        cell.alignment = align_c
        cell.border = Border(top=thick)
        cell2 = ws.cell(3, c, b if b else None)
        cell2.font = font_h
        cell2.alignment = align_c
        cell2.border = Border(bottom=thin)
    ws.merge_cells("C2:D2")
    ws.merge_cells("A2:A3")
    ws.merge_cells("B2:B3")
    ws.merge_cells("E2:E3")
    ws.merge_cells("F2:F3")
    ws.merge_cells("G2:G3")
    # restore merged header text on top-left of merges
    ws["A2"] = "Variable"
    ws["A2"].font = font_h
    ws["A2"].alignment = align_c
    ws["A2"].border = Border(top=thick, bottom=thin)
    ws["B2"] = "Total measurements (N)"
    ws["B2"].font = font_h
    ws["B2"].alignment = align_c
    ws["B2"].border = Border(top=thick, bottom=thin)
    ws["C2"] = "Outliers clipped after normalisation"
    ws["C2"].font = font_h
    ws["C2"].alignment = align_c
    ws["C2"].border = Border(top=thick)
    ws["C3"] = "N clipped"
    ws["C3"].font = font_h
    ws["C3"].alignment = align_c
    ws["C3"].border = Border(bottom=thin)
    ws["D3"] = "% of total"
    ws["D3"].font = font_h
    ws["D3"].alignment = align_c
    ws["D3"].border = Border(bottom=thin)
    for col, txt in (
        ("E2", "Before removal/clipping (original scale)\nMedian [IQR]"),
        ("F2", "After removal/clipping (original scale)\nMedian [IQR]"),
        ("G2", "Normal physiological range"),
    ):
        ws[col] = txt
        ws[col].font = font_h
        ws[col].alignment = align_c
        ws[col].border = Border(top=thick, bottom=thin)
    ws.row_dimensions[2].height = 32
    ws.row_dimensions[3].height = 18

    for i, r in enumerate(rows):
        rr = 4 + i
        last = i == len(rows) - 1
        vals = [
            r["Variable"],
            r["Total measurements (N)"],
            r["N clipped"],
            r["% of total"],
            r["Before Median [IQR]"],
            r["After Median [IQR]"],
            r["Normal physiological range"],
        ]
        for c, v in enumerate(vals, 1):
            cell = ws.cell(rr, c, v)
            cell.font = font_b
            cell.alignment = align_l if c == 1 else align_c
            if last:
                cell.border = Border(bottom=thick)

    if footnote:
        fr = 4 + len(rows) + 2
        cell = ws.cell(fr, 1, footnote)
        cell.font = font_fn
        cell.alignment = align_l
        ws.merge_cells(start_row=fr, start_column=1, end_row=fr, end_column=nc)
        cell.border = Border(top=thin)

    widths = [34, 20, 12, 11, 26, 26, 24]
    for i, w in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(i)].width = w
    out_xlsx.parent.mkdir(parents=True, exist_ok=True)
    wb.save(out_xlsx)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--blended", required=True, type=Path)
    ap.add_argument("--q5q95", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--drop", default="")
    ap.add_argument("--workers", type=int, default=int(os.environ.get("LIVER_TABLE1_WORKERS", "24")))
    ap.add_argument("--cohort-label", default="ACG-style enzyme elevation")
    args = ap.parse_args()

    drop = {x.strip() for x in args.drop.split(",") if x.strip()}
    lab = pd.read_parquet(args.blended / "preprocessed_labels.parquet")
    keep = (
        set(lab["patient"].astype(str))
        if "patient" in lab.columns
        else set(pd.Index(lab.index).astype(str))
    )
    print(f"[S1] cohort stays={len(keep):,}", flush=True)
    payload = json.loads(args.q5q95.read_text())
    q5 = payload.get("q5", {})
    q95 = payload.get("q95", {})
    clip = payload.get("clip", [-4, 4])
    clip_lo, clip_hi = float(clip[0]), float(clip[1])

    cols = [c for c, _ in _DISPLAY if c not in drop]
    merged = collect_values(args.blended, keep, cols, args.workers)
    rows = build_rows(merged, q5, q95, drop, clip_lo, clip_hi)

    title = (
        "Table S1. Distribution of variable values before and after removal of "
        "physiologically implausible values and outlier clipping"
    )
    drop_note = (
        f" Features excluded from the {args.cohort_label} model "
        f"(not tabulated): {', '.join(sorted(drop))}."
        if drop
        else ""
    )
    footnote = (
        "ALT: alanine aminotransferase; AST: aspartate aminotransferase; BUN: blood urea nitrogen; "
        "GCS: Glasgow Coma Scale; IQR: interquartile range; PTT: partial thromboplastin time. "
        "Prior to normalization, continuous measurements were clipped to the tabulated physiological ranges. "
        f"Post-normalization outliers: raw values scaled with training-set q5/q95 to [−1, 1] between quantiles; "
        f"observations with |scaled| > {abs(clip_hi):g} were counted (Total measurements = N before – N after). "
        f"Cohort: {args.cohort_label}; N stays={len(keep):,}.{drop_note}"
    )

    out = Path(args.out)
    if not str(out).lower().endswith(".xlsx"):
        out = Path(str(out) + ".xlsx")
    write_xlsx(rows, out, title, footnote)
    df_rows = pd.DataFrame(rows)
    pub_cols = [c for c in df_rows.columns if not c.startswith("_")]
    csv_stem = out.with_name(out.stem.replace(" ", "_"))
    df_rows[pub_cols].to_csv(csv_stem.with_suffix(".csv"), index=False)
    df_rows.to_csv(csv_stem.with_name(csv_stem.stem + "_internal.csv"), index=False)
    print("wrote", out, "nrows", len(rows))
    # quick sanity
    n_pos = sum(1 for r in rows if r["_n_clip"] > 0)
    print(f"[S1] vars with N clipped>0: {n_pos}/{len(rows)}", flush=True)


if __name__ == "__main__":
    main()
