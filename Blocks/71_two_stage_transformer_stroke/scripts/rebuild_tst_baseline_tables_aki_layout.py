#!/usr/bin/env python3
"""Rebuild TST Table 1 / S1 / S2 to match AKI two_stage_transformer delivery layout.

Reference: 33_AKI/.../summary_results/Tables
- Title: Table 1-MIMIC. Baseline characteristics of <disease> in-hospital mortality
- Columns: Overall | Survived (discharge alive) | In-hospital death | p-value
- Binary levels: No / Yes (never 0/1)
- Drop GCS components (eyes/motor/verbal) and redundant intubated when Ventilation present
- Include severity scores available on the analysis frame (SAPSII/APSIII/SOFA/OASIS/GCS)
- S2 feature labels: spaced display names (no camelCase / underscores)
- S1: same analytic vars; % and continuous to 2 decimals where applicable
"""
from __future__ import annotations

import argparse
import math
import re
from pathlib import Path

import numpy as np
import pandas as pd
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, Side
from openpyxl.utils import get_column_letter
from scipy import stats

FONT = "Times New Roman"

FEATURE_DISPLAY = {
    "heartrate": "heart rate",
    "sao2": "spo2",
    "respiration": "respiratory rate",
    "temperature": "temperature c",
    "noninvasivemean": "nibp mean",
    "noninvasivesystolic": "nibp systolic",
    "noninvasivediastolic": "nibp diastolic",
    "systemicmean": "abp mean",
    "systemicsystolic": "abp systolic",
    "systemicdiastolic": "abp diastolic",
    "anion_gap": "anion gap",
    "base_excess": "base excess",
    "total_rr": "total rr",
    "peak_insp_pressure": "peak insp pressure",
    "mean_airway_pressure": "mean airway pressure",
    "tidal_volume_set": "tidal volume set",
    "vent_rate": "vent rate",
    "exhaled_mv": "exhaled mv",
    "lpm_o2": "lpm o2",
    "plateau_pressure": "plateau pressure",
}

# Table 1 display labels (AKI-style units) for Day-1 first values of S2 dynamic features
TABLE1_FEATURE_LABELS: dict[str, str] = {
    "heartrate": "HR,bpm",
    "respiration": "RR",
    "temperature": "Temperature,°C",
    "systemicmean": "ABP mean,mmHg",
    "systemicsystolic": "ABP systolic,mmHg",
    "systemicdiastolic": "ABP diastolic,mmHg",
    "noninvasivemean": "NIBP mean,mmHg",
    "noninvasivesystolic": "NIBP systolic,mmHg",
    "noninvasivediastolic": "NIBP diastolic,mmHg",
    "sao2": "SpO2,%",
    "total_rr": "Total RR",
    "glucose": "Glucose,mg/dL",
    "creatinine": "Creatinine,mg/dL",
    "bun": "BUN,mg/dL",
    "bicarbonate": "Bicarbonate,mEq/L",
    "anion_gap": "Anion gap,mEq/L",
    "calcium": "Calcium,mg/dL",
    "sodium": "Sodium,mEq/L",
    "potassium": "Potassium,mEq/L",
    "chloride": "Chloride,mEq/L",
    "magnesium": "Magnesium,mg/dL",
    "phosphate": "Phosphate,mg/dL",
    "lactate": "Lactate,mmol/L",
    "albumin": "Albumin,g/dL",
    "wbc": "WBC,K/uL",
    "lymphs": "Lymphocytes,%",
    "polys": "Neutrophils,%",
    "hgb": "Hemoglobin,g/dL",
    "hct": "Hematocrit,%",
    "rdw": "RDW,%",
    "platelets": "Platelets,K/uL",
    "mcv": "MCV,fL",
    "pt": "PT,sec",
    "ptt": "PTT,sec",
    "inr": "INR",
    "ph": "pH",
    "paco2": "PaCO2,mmHg",
    "pao2": "PaO2,mmHg",
    "base_excess": "Base excess,mEq/L",
    "fio2": "FiO2",
    "peep": "PEEP,cmH2O",
    "lpm_o2": "O2 flow,L/min",
    "peak_insp_pressure": "Peak insp pressure,cmH2O",
    "plateau_pressure": "Plateau pressure,cmH2O",
    "mean_airway_pressure": "Mean airway pressure,cmH2O",
    "tidal_volume_set": "Tidal volume set,mL",
    "vent_rate": "Vent rate,/min",
    "exhaled_mv": "Exhaled MV,L/min",
    "alt": "ALT,IU/L",
    "ast": "AST,IU/L",
}

TABLE1_VITAL_COLS = [
    "heartrate",
    "respiration",
    "temperature",
    "sao2",
    "noninvasivesystolic",
    "noninvasivediastolic",
    "noninvasivemean",
    "systemicsystolic",
    "systemicdiastolic",
    "systemicmean",
    "total_rr",
]
TABLE1_LAB_COLS = [
    "wbc",
    "hgb",
    "hct",
    "platelets",
    "rdw",
    "mcv",
    "lymphs",
    "polys",
    "glucose",
    "creatinine",
    "bun",
    "sodium",
    "potassium",
    "chloride",
    "bicarbonate",
    "anion_gap",
    "calcium",
    "magnesium",
    "phosphate",
    "lactate",
    "albumin",
    "alt",
    "ast",
    "pt",
    "ptt",
    "inr",
    "ph",
    "paco2",
    "pao2",
    "base_excess",
]
TABLE1_VENT_PARAM_COLS = [
    "fio2",
    "peep",
    "lpm_o2",
    "peak_insp_pressure",
    "plateau_pressure",
    "mean_airway_pressure",
    "tidal_volume_set",
    "vent_rate",
    "exhaled_mv",
]
HOURLY_SKIP = {
    "patient",
    "day",
    "hour",
    "label",
    "los_days",
}


def _fmt_int(n: int) -> str:
    return f"{int(n):,}"


def _fmt_pct(n: int, d: int) -> str:
    if d <= 0:
        return f"{_fmt_int(n)} (—)"
    return f"{_fmt_int(n)} ({100.0 * n / d:.2f}%)"


def _fmt_med_iqr(x: np.ndarray) -> str:
    x = x[np.isfinite(x)]
    if x.size == 0:
        return "—"
    q1, med, q3 = np.percentile(x, [25, 50, 75])
    return f"{med:.2f} ({q1:.2f}, {q3:.2f})"


def _p_cont(a: np.ndarray, b: np.ndarray) -> float:
    a = a[np.isfinite(a)]
    b = b[np.isfinite(b)]
    if a.size < 2 or b.size < 2:
        return float("nan")
    try:
        return float(stats.mannwhitneyu(a, b, alternative="two-sided").pvalue)
    except Exception:
        return float("nan")


def _p_cat(tab: np.ndarray) -> float:
    if tab.size == 0 or tab.sum() == 0:
        return float("nan")
    try:
        if tab.shape[0] < 2 or tab.shape[1] < 2:
            return float("nan")
        # chi2; if sparse use fisher 2x2
        if tab.shape == (2, 2) and (tab < 5).any():
            return float(stats.fisher_exact(tab)[1])
        return float(stats.chi2_contingency(tab, correction=False)[1])
    except Exception:
        return float("nan")


def _fmt_p(p: float) -> str:
    if p != p:
        return ""
    if p < 0.001:
        return "<0.001"
    return f"{p:.3f}"


def _yes_no(series: pd.Series) -> pd.Series:
    s = series.copy()
    if pd.api.types.is_bool_dtype(s):
        return s.map({True: "Yes", False: "No"})
    # numeric / string
    mapping = {
        0: "No",
        1: "Yes",
        0.0: "No",
        1.0: "Yes",
        "0": "No",
        "1": "Yes",
        "No": "No",
        "Yes": "Yes",
        "no": "No",
        "yes": "Yes",
        False: "No",
        True: "Yes",
    }
    out = s.map(lambda v: mapping.get(v, mapping.get(str(v), v)))
    return out.astype(str)


def write_sci_xlsx(path: Path, title: str, rows: list[list[str]], footnotes: list[str]) -> None:
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

    hdr, body = rows[0], rows[1:]
    nc = len(hdr)
    wb = Workbook()
    ws = wb.active
    ws.title = "Table"
    ws.sheet_view.showGridLines = False
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=nc)
    c0 = ws.cell(1, 1, title)
    c0.font = font_title
    c0.alignment = align_c

    r0 = 2
    for j, h in enumerate(hdr, 1):
        cell = ws.cell(r0, j, h)
        cell.font = font_hdr
        cell.alignment = align_c
        cell.border = border_header

    for i, row in enumerate(body):
        er = r0 + 1 + i
        is_last = i == len(body) - 1
        row = list(row) + [""] * max(0, nc - len(row))
        is_section = bool(str(row[0]).strip()) and all(not str(x).strip() for x in row[1:nc])
        for j in range(1, nc + 1):
            val = row[j - 1]
            cell = ws.cell(er, j, val)
            cell.font = font_sec if (is_section and j == 1) else font_body
            cell.alignment = align_l if j == 1 else align_c
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
                maxlen = max(maxlen, min(len(str(row[j - 1])), 42))
        ws.column_dimensions[get_column_letter(j)].width = min(max(maxlen + 2, 12), 40)
    path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(path)
    print(f"[write] {path}")


def _outcome_dead_mask(series: pd.Series) -> pd.Series:
    """Map 0/1 or Survivor/Non-survivor (and synonyms) → dead=True."""
    s = series.copy()
    if pd.api.types.is_numeric_dtype(s):
        return pd.to_numeric(s, errors="coerce").fillna(-1).astype(int).eq(1)
    low = s.astype(str).str.strip().str.lower()
    dead_tokens = {
        "1", "dead", "death", "expired", "non-survivor", "nonsurvivor",
        "non survivor", "in-hospital death", "in hospital death",
    }
    alive_tokens = {
        "0", "alive", "survivor", "survived", "survived (discharge alive)",
        "discharge alive",
    }
    out = pd.Series(False, index=s.index)
    out[low.isin(dead_tokens)] = True
    # unknowns stay False only if clearly alive; else NaN rows excluded upstream
    unknown = ~low.isin(dead_tokens | alive_tokens)
    if unknown.any():
        # try numeric strings
        num = pd.to_numeric(low, errors="coerce")
        out[unknown & num.eq(1)] = True
        out[unknown & num.eq(0)] = False
    return out


def _normalize_temperature_c(series: pd.Series) -> pd.Series:
    """MIMIC chart temperature is often °F; convert values >45 to °C."""
    x = pd.to_numeric(series, errors="coerce")
    out = x.copy()
    mask = x.notna() & (x > 45)
    out.loc[mask] = (x.loc[mask] - 32.0) * 5.0 / 9.0
    return out


def extract_day1_first_values(hourly_csv: Path, feature_cols: list[str] | None = None) -> pd.DataFrame:
    """First non-missing value on ICU Day 1 for each dynamic feature (Table S2 aligned)."""
    peek = pd.read_csv(hourly_csv, nrows=0)
    avail = [c for c in peek.columns if c not in HOURLY_SKIP and not str(c).startswith("static_")]
    if feature_cols:
        want = [c for c in feature_cols if c in avail]
    else:
        want = avail
    usecols = ["patient", "day", "hour"] + want
    chunks: list[pd.DataFrame] = []
    for ch in pd.read_csv(hourly_csv, usecols=usecols, chunksize=400_000):
        chunks.append(ch.loc[ch["day"] == 1])
    if not chunks:
        raise SystemExit(f"no Day 1 rows in {hourly_csv}")
    d1 = pd.concat(chunks, ignore_index=True)
    d1 = d1.sort_values(["patient", "hour"])
    rows = []
    for pid, g in d1.groupby("patient", sort=False):
        rec: dict = {"stay_id": int(pid)}
        for c in want:
            s = pd.to_numeric(g[c], errors="coerce")
            nn = s.dropna()
            rec[c] = float(nn.iloc[0]) if len(nn) else float("nan")
        rows.append(rec)
    out = pd.DataFrame(rows)
    if "temperature" in out.columns:
        out["temperature"] = _normalize_temperature_c(out["temperature"])
    return out


def build_table1(df: pd.DataFrame, disease_short: str) -> tuple[str, list[list[str]], list[str]]:
    ycol = "is_hosp_dead"
    dead_m = _outcome_dead_mask(df[ycol])
    alive = df[~dead_m]
    dead = df[dead_m]
    n0, n1, n = len(alive), len(dead), len(df)
    if n0 == 0 or n1 == 0:
        raise SystemExit(
            f"outcome split empty (alive={n0}, dead={n1}); check is_hosp_dead encoding: "
            f"{df[ycol].value_counts(dropna=False).to_dict()}"
        )
    title = f"Table 1-MIMIC. Baseline characteristics of {disease_short} in-hospital mortality"
    hdr = [
        "Characteristic",
        f"Overall N = {_fmt_int(n)}",
        f"Survived (discharge alive) N = {_fmt_int(n0)}",
        f"In-hospital death N = {_fmt_int(n1)}",
        "p-value",
    ]
    rows: list[list[str]] = [hdr]

    def add_section(name: str) -> None:
        rows.append([name, "", "", "", ""])

    def add_cont(label: str, col: str) -> None:
        if col not in df.columns:
            return
        a = pd.to_numeric(df[col], errors="coerce").to_numpy(dtype=float)
        a0 = pd.to_numeric(alive[col], errors="coerce").to_numpy(dtype=float)
        a1 = pd.to_numeric(dead[col], errors="coerce").to_numpy(dtype=float)
        if not (np.isfinite(a).any() or np.isfinite(a0).any() or np.isfinite(a1).any()):
            return
        rows.append([label, _fmt_med_iqr(a), _fmt_med_iqr(a0), _fmt_med_iqr(a1), _fmt_p(_p_cont(a0, a1))])

    def add_binary(label: str, col: str) -> None:
        if col not in df.columns:
            return
        s = _yes_no(df[col])
        s0 = _yes_no(alive[col])
        s1 = _yes_no(dead[col])
        levels = ["No", "Yes"]
        tab = np.zeros((2, 2), dtype=int)
        for i, lv in enumerate(levels):
            tab[i, 0] = int((s0 == lv).sum())
            tab[i, 1] = int((s1 == lv).sum())
        rows.append([label, "", "", "", _fmt_p(_p_cat(tab))])
        for lv in levels:
            rows.append(
                [
                    lv,
                    _fmt_pct(int((s == lv).sum()), n),
                    _fmt_pct(int((s0 == lv).sum()), n0),
                    _fmt_pct(int((s1 == lv).sum()), n1),
                    "",
                ]
            )

    def add_gender() -> None:
        if "Gender" not in df.columns:
            return
        s = df["Gender"].astype(str)
        # normalize
        s = s.replace({"M": "Male", "F": "Female", "male": "Male", "female": "Female", "1": "Male", "0": "Female"})
        s0 = alive["Gender"].astype(str).replace({"M": "Male", "F": "Female", "male": "Male", "female": "Female", "1": "Male", "0": "Female"})
        s1 = dead["Gender"].astype(str).replace({"M": "Male", "F": "Female", "male": "Male", "female": "Female", "1": "Male", "0": "Female"})
        levels = [lv for lv in ["Female", "Male"] if ((s == lv).any())]
        if not levels:
            levels = sorted(s.dropna().unique().tolist())
        tab = np.zeros((len(levels), 2), dtype=int)
        for i, lv in enumerate(levels):
            tab[i, 0] = int((s0 == lv).sum())
            tab[i, 1] = int((s1 == lv).sum())
        rows.append(["Gender", "", "", "", _fmt_p(_p_cat(tab))])
        for lv in levels:
            rows.append(
                [
                    str(lv),
                    _fmt_pct(int((s == lv).sum()), n),
                    _fmt_pct(int((s0 == lv).sum()), n0),
                    _fmt_pct(int((s1 == lv).sum()), n1),
                    "",
                ]
            )

    def add_feature_block(section: str, cols: list[str]) -> None:
        present = [c for c in cols if c in df.columns]
        if not present:
            return
        add_section(section)
        for c in present:
            add_cont(TABLE1_FEATURE_LABELS.get(c, display_feature(c)), c)

    add_section("Demographics")
    add_cont("Age,years", "Age")
    add_gender()
    add_cont("Weight,kg", "Weight")

    # Align with Table S2 dynamic domains (Day-1 first value), AKI section order
    add_feature_block("Vital Signs", TABLE1_VITAL_COLS)
    add_feature_block("Laboratory Tests", TABLE1_LAB_COLS)

    add_section("Clinical Scores")
    add_cont("SAPSII,points", "SAPSII")
    add_cont("APSIII,points", "APSIII")
    add_cont("SOFA,points", "SOFA")
    add_cont("OASIS,points", "OASIS")
    add_cont("GCS,points", "GCS")

    add_section("Interventions and Hospital Course")
    vent_col = "Ventilation" if "Ventilation" in df.columns else None
    if vent_col:
        add_binary("Mechanical ventilation (ever)", vent_col)
    if "dialysis" in df.columns:
        add_binary("Dialysis", "dialysis")
    add_cont("icu day", "icu_day")
    add_feature_block("Respiratory support parameters (Day 1)", TABLE1_VENT_PARAM_COLS)

    # any leftover S2 dynamic cols not listed above
    known = set(TABLE1_VITAL_COLS) | set(TABLE1_LAB_COLS) | set(TABLE1_VENT_PARAM_COLS)
    leftovers = [
        c
        for c in df.columns
        if c in TABLE1_FEATURE_LABELS and c not in known
    ]
    if leftovers:
        add_feature_block("Other Day-1 features (Table S2)", leftovers)

    footnotes = [
        "Continuous variables are presented as median (interquartile range). Categorical variables are presented as count (percentage).",
        "Statistical comparisons were performed using the Wilcoxon rank-sum test or Pearson's chi-squared test.",
        "Vital signs, laboratory tests, and respiratory support parameters are the first non-missing value on ICU Day 1 for each patient, aligned with dynamic features in Table S2.",
        "Temperature values recorded in °F were converted to °C.",
    ]
    return title, rows, footnotes


def build_s1(df_before: pd.DataFrame, df_after: pd.DataFrame) -> tuple[str, list[list[str]], list[str]]:
    title = "Table S1-MIMIC. Baseline characteristics before and after imputation (analysis cohort)"
    hdr = ["Variable", "Statistic", "Before MI", "After MI", "P value"]
    rows: list[list[str]] = [hdr]
    cont = [
        ("Age", "Age"),
        ("Weight", "Weight"),
        ("SAPSII", "SAPSII"),
        ("APSIII", "APSIII"),
        ("SOFA", "SOFA"),
        ("OASIS", "OASIS"),
        ("GCS", "GCS"),
        ("icu day", "icu_day"),
    ]
    for lab, col in cont:
        if col not in df_after.columns:
            continue
        b = pd.to_numeric(df_before[col], errors="coerce") if col in df_before.columns else pd.Series(dtype=float)
        a = pd.to_numeric(df_after[col], errors="coerce")
        miss_b = float(b.isna().mean() * 100) if len(b) else float("nan")
        miss_a = float(a.isna().mean() * 100)
        rows.append([lab, "Median (Q1, Q3)", _fmt_med_iqr(b.to_numpy(dtype=float)), _fmt_med_iqr(a.to_numpy(dtype=float)), _fmt_p(_p_cont(b.to_numpy(dtype=float), a.to_numpy(dtype=float)))])
        rows.append(["Missing (%)", "", f"{miss_b:.2f}%" if miss_b == miss_b else "—", f"{miss_a:.2f}%", ""])

    # Gender
    if "Gender" in df_after.columns:
        def _g(s: pd.Series) -> pd.Series:
            return s.astype(str).replace({"M": "Male", "F": "Female", "male": "Male", "female": "Female", "1": "Male", "0": "Female"})

        gb = _g(df_before["Gender"]) if "Gender" in df_before.columns else pd.Series(dtype=str)
        ga = _g(df_after["Gender"])
        levels = [lv for lv in ["Female", "Male"] if (ga == lv).any()]
        tab = np.zeros((len(levels), 2), dtype=int)
        for i, lv in enumerate(levels):
            tab[i, 0] = int((gb == lv).sum()) if len(gb) else 0
            tab[i, 1] = int((ga == lv).sum())
        rows.append(["Gender", "n (%)", "", "", _fmt_p(_p_cat(tab)) if len(gb) else ""])
        nb, na = max(len(gb), 1), len(ga)
        for lv in levels:
            rows.append([lv, "", _fmt_pct(int((gb == lv).sum()), len(gb)) if len(gb) else "—", _fmt_pct(int((ga == lv).sum()), na), ""])
        rows.append(["Missing (%)", "", f"{100.0 * gb.isna().mean():.2f}%" if len(gb) else "—", f"{100.0 * ga.isna().mean():.2f}%", ""])

    for lab, col in [("Mechanical ventilation (ever)", "Ventilation"), ("dialysis", "dialysis")]:
        if col not in df_after.columns:
            continue
        bb = _yes_no(df_before[col]) if col in df_before.columns else pd.Series(dtype=str)
        aa = _yes_no(df_after[col])
        levels = ["No", "Yes"]
        tab = np.zeros((2, 2), dtype=int)
        for i, lv in enumerate(levels):
            tab[i, 0] = int((bb == lv).sum()) if len(bb) else 0
            tab[i, 1] = int((aa == lv).sum())
        rows.append([lab, "n (%)", "", "", _fmt_p(_p_cat(tab)) if len(bb) else ""])
        for lv in levels:
            rows.append(
                [
                    lv,
                    "",
                    _fmt_pct(int((bb == lv).sum()), len(bb)) if len(bb) else "—",
                    _fmt_pct(int((aa == lv).sum()), len(aa)),
                    "",
                ]
            )
        rows.append(
            [
                "Missing (%)",
                "",
                f"{100.0 * (df_before[col].isna().mean() if col in df_before.columns else 0):.2f}%",
                f"{100.0 * df_after[col].isna().mean():.2f}%",
                "",
            ]
        )

    footnotes = [
        "Before MI = complete-case descriptive on the analysis cohort prior to imputation; After MI = first completed imputed dataset (operation layer).",
        "Continuous variables: median (IQR); categorical: n (%).",
    ]
    return title, rows, footnotes


def display_feature(name: str) -> str:
    key = str(name).strip()
    if key in FEATURE_DISPLAY:
        return FEATURE_DISPLAY[key]
    # underscores / camel → spaces
    s = re.sub(r"[_\s]+", " ", key)
    s = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", s)
    return s.lower().strip()


def build_s2(feature_names: list[str], static_names: list[str] | None = None) -> tuple[str, list[list[str]], list[str]]:
    title = "Table S2-MIMIC. Features used in Transformer"
    rows = [["Section", "Feature"]]
    for f in feature_names:
        rows.append(["Dynamic (hourly)", display_feature(f)])
    for f in static_names or []:
        rows.append(["Static (baseline broadcast)", display_feature(f)])
    return title, rows, []


def load_frame_from_rdata_or_csv(project: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Return (before_mi-ish, after_mi). Prefer exported CSV from R helper beside script cache."""
    cache = project / "_shared" / "_tst_table1_rebuild_cache.csv"
    after_csv = project / "_shared" / "step05_imputation" / "Tables" / "_after_mi_for_table1.csv"
    # R export path written by caller
    for p in [cache, after_csv]:
        if p.is_file():
            df = pd.read_csv(p)
            return df.copy(), df.copy()
    raise SystemExit("missing analysis CSV; run with --from-rdata via companion R export first")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-root", required=True)
    ap.add_argument("--disease-short", default="ischemic stroke")
    ap.add_argument("--csv", default="", help="imputed analysis CSV (preferred)")
    ap.add_argument("--before-csv", default="", help="optional before-MI CSV for S1")
    ap.add_argument("--features-npz", default="", help="test.npz or feature list txt for S2")
    ap.add_argument(
        "--hourly-csv",
        default="",
        help="hourly long CSV; Day-1 first values merged into Table 1 (align with S2)",
    )
    ap.add_argument(
        "--no-hourly-table1",
        action="store_true",
        help="do not merge Day-1 dynamic features into Table 1",
    )
    args = ap.parse_args()
    proj = Path(args.project_root)

    if args.csv:
        after = pd.read_csv(args.csv)
        before = pd.read_csv(args.before_csv) if args.before_csv else after.copy()
    else:
        before, after = load_frame_from_rdata_or_csv(proj)

    # normalize outcome
    if "is_hosp_dead" not in after.columns:
        raise SystemExit("CSV missing is_hosp_dead")

    hourly = Path(args.hourly_csv) if args.hourly_csv else (
        proj / "_shared" / "step06_tst_timeseries" / "Tables" / "_tst_hourly_long.csv"
    )
    if (not args.no_hourly_table1) and hourly.is_file():
        day1 = extract_day1_first_values(hourly)
        id_col = "stay_id" if "stay_id" in after.columns else ("ID" if "ID" in after.columns else None)
        if id_col is None:
            raise SystemExit("analysis CSV missing stay_id/ID for hourly merge")
        after = after.copy()
        after[id_col] = pd.to_numeric(after[id_col], errors="coerce").astype("Int64")
        day1["stay_id"] = pd.to_numeric(day1["stay_id"], errors="coerce").astype("Int64")
        # drop overlapping dynamic cols from baseline before merge
        overlap = [c for c in day1.columns if c != "stay_id" and c in after.columns]
        if overlap:
            after = after.drop(columns=overlap)
        after = after.merge(day1, left_on=id_col, right_on="stay_id", how="left", suffixes=("", "_d1"))
        if "stay_id_d1" in after.columns:
            after = after.drop(columns=["stay_id_d1"])
        print(f"[merge] Day-1 first values from {hourly.name}: {len(day1.columns)-1} features → n={len(after)}")
    elif not args.no_hourly_table1:
        print(f"[warn] hourly CSV missing ({hourly}); Table 1 stays demographics/scores only")

    tables = proj / "summary_results" / "Tables"
    tables.mkdir(parents=True, exist_ok=True)

    t1_title, t1_rows, t1_notes = build_table1(after, args.disease_short)
    t1_path = tables / f"Table 1-MIMIC. Baseline characteristics of {args.disease_short} in-hospital mortality.xlsx"
    # remove stale Table 1*
    for stale in tables.glob("Table 1-*.xlsx"):
        if stale.resolve() != t1_path.resolve():
            stale.unlink(missing_ok=True)
    write_sci_xlsx(t1_path, t1_title, t1_rows, t1_notes)

    s1_title, s1_rows, s1_notes = build_s1(before, after)
    s1_path = tables / "Table S1-MIMIC. Baseline characteristics before and after imputation (analysis cohort).xlsx"
    write_sci_xlsx(s1_path, s1_title, s1_rows, s1_notes)

    # S2 features from npz if available
    feat_names: list[str] = []
    static_names: list[str] = []
    npz = Path(args.features_npz) if args.features_npz else (
        proj / "by_unit/【success】L120_B_twostage/step09_tst_train_eval/Tables/npz/test.npz"
    )
    if npz.is_file() and npz.suffix == ".npz":
        d = np.load(npz, allow_pickle=True)
        feat_names = [str(x) for x in d["feature_names"]]
        # heuristic: static_* not in hourly npz usually; use known static broadcast list
        static_names = ["Age", "Gender", "Weight", "GCS", "Ventilation", "dialysis"]
    else:
        # fallback from current S2 if exists
        s2_old = tables / "Table S2-MIMIC. Features used in Transformer.xlsx"
        if s2_old.is_file():
            import openpyxl

            wb = openpyxl.load_workbook(s2_old, data_only=True, read_only=True)
            ws = wb.active
            for i, row in enumerate(ws.iter_rows(values_only=True)):
                if i == 0:
                    continue
                if row and row[0] and row[1]:
                    if str(row[0]).lower().startswith("dynamic"):
                        feat_names.append(str(row[1]))
                    elif str(row[0]).lower().startswith("static"):
                        static_names.append(str(row[1]))
            wb.close()
    if feat_names:
        s2_title, s2_rows, s2_notes = build_s2(feat_names, static_names)
        write_sci_xlsx(tables / "Table S2-MIMIC. Features used in Transformer.xlsx", s2_title, s2_rows, s2_notes)

    print("[done] Table1/S1/S2 rebuilt to AKI layout")


if __name__ == "__main__":
    main()
