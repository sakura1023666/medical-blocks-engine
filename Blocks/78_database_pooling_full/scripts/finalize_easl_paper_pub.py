#!/usr/bin/env python3
"""Finalize liver multi-DB paper pack into summary_results (Allyn Crit Care 2026 aligned).

Default cohort = EASL/DILI. Override via env for ACG / MARS / etc.:
  EASL_ROOT / LIVER_ROOT, LIVER_BLENDED_SUBDIR, LIVER_COHORT_*, LIVER_PUB_OUT,
  EASL_MAIN_OUT, EASL_EXTRA_OUT.

Figures follow Allyn Fig.1 / Fig.2 visual language; tables follow manuscript +
MOESM1/MOESM2 wide layouts (SCI three-line xlsx).
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.patches import FancyBboxPatch
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, Side
from openpyxl.utils import get_column_letter
from sklearn.metrics import average_precision_score

ROOT = Path(os.environ.get(
    "LIVER_ROOT",
    os.environ.get(
        "EASL_ROOT",
        "/mnt/sda/BlendedICU/data/liver_dysfunction_easl_dili_42151996",
    ),
))
# Prefer physio-clip retrain dirs when env set; else Output_physclip if present.
_main_env = os.environ.get("EASL_MAIN_OUT", "").strip()
_extra_env = os.environ.get("EASL_EXTRA_OUT", "").strip()
if _main_env:
    MAIN_OUT = Path(_main_env)
elif (ROOT / "Output_physclip").is_dir():
    MAIN_OUT = ROOT / "Output_physclip"
else:
    MAIN_OUT = ROOT / "Output_noenzyme"
if _extra_env:
    EXTRA = Path(_extra_env)
elif (ROOT / "Output_paper_extras_physclip").is_dir():
    EXTRA = ROOT / "Output_paper_extras_physclip"
else:
    EXTRA = ROOT / "Output_paper_extras"
PUB = Path(os.environ.get(
    "LIVER_PUB_OUT",
    "/mnt/g/02block_result/50_Cirrhosis/database_pooled_42151996/summary_results",
))

# Cohort-specific labels (ACG / EASL / …). Defaults keep EASL/DILI behaviour.
BLENDED_SUBDIR = os.environ.get("LIVER_BLENDED_SUBDIR", "blendedlos_easl_dili").strip()
BLENDED_ROOT = ROOT / BLENDED_SUBDIR
COHORT_TITLE = os.environ.get("LIVER_COHORT_TITLE", "EASL/DILI").strip()
COHORT_RULE_SHORT = os.environ.get(
    "LIVER_COHORT_RULE_SHORT",
    "First ALT ≥200 or ALP ≥230 U/L; drop ALT+ALP from features",
).strip()
COHORT_NOTE_ZH = os.environ.get(
    "LIVER_COHORT_NOTE_ZH",
    "EASL/DILI 酶学门控（ALT≥200 或 ALP≥230），主分析去掉纳入用 ALT+ALP。",
).strip()
COHORT_SUBSET_ZH = os.environ.get(
    "LIVER_COHORT_SUBSET_ZH",
    "EASL/DILI 子集",
).strip()
FEATURE_DROP_EN = os.environ.get(
    "LIVER_FEATURE_DROP_EN",
    "ALT/ALP excluded from model features.",
).strip()
TABLE1_FOOTNOTE = os.environ.get(
    "LIVER_TABLE1_FOOTNOTE",
    "EASL/DILI cohort (first ALT≥200 or ALP≥230 U/L). "
    "Continuous: mean [SD] (vitals/labs = stay-level hourly mean after MOESM1 physiological-range clip, "
    "then cohort mean [SD]). Drug exposure: any hourly dose >0 during the stay. "
    "Unit type from BlendedICU labels (HiRID often Unknown). ALT/ALP excluded from model features. "
    "Vitals/labs clipped to MOESM1 physiological ranges (same bounds as model preprocess).",
).strip()
SCALE_FEATURE_NOTE = os.environ.get(
    "LIVER_SCALE_FEATURE_NOTE",
    "ALT/ALP not included.",
).strip()

ARM = {
    "Amsterdam only": ("liver_expA_amsterdam_solo", "amsterdam_100/"),
    "MIMIC-IV only": ("liver_expB_mimic_solo", "mimic4_100/"),
    "Transfer": ("liver_expC_mimic2amsterdam_transfer", "amsterdam_100_retrain"),
    "Pooling": ("liver_expD_pooled_mimic_amsterdam", "amsterdam_mimic4_100/"),
}
DB_LAB = {"amsterdam": "AmsterdamUMC", "mimic4": "MIMIC-IV", "eicu": "eICU", "hirid": "HiRID"}
DB_ORDER = ["amsterdam", "mimic4", "eicu", "hirid"]
INK = "#1b2430"
MUTED = "#3d4a5c"
EDGE = "#243040"
DB_FACE = {
    "AmsterdamUMC": "#d7e6f5",
    "MIMIC-IV": "#f6dfd4",
    "eICU": "#dceee4",
    "HiRID": "#efe6c9",
}

# matplotlib publication defaults
plt.rcParams.update(
    {
        "font.family": "DejaVu Sans",
        "font.size": 9,
        "axes.labelsize": 10,
        "axes.titlesize": 11,
        "axes.linewidth": 0.8,
        "xtick.major.width": 0.7,
        "ytick.major.width": 0.7,
        "legend.fontsize": 9,
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
    }
)


def _disp(s: str) -> str:
    return re.sub(r"_+", " ", str(s)).strip()


def _fmt_n(n) -> str:
    try:
        return f"{int(n):,}"
    except Exception:
        return "–"


def _fmt_est(x, digits=3):
    if x is None or (isinstance(x, float) and not np.isfinite(x)):
        return "–"
    return f"{float(x):.{digits}f}"


def _fmt_ci(est, lo, hi, digits=3) -> str:
    if est is None or (isinstance(est, float) and not np.isfinite(est)):
        return "–"
    if lo is None or hi is None or not (np.isfinite(lo) and np.isfinite(hi)):
        return _fmt_est(est, digits)
    return f"{float(est):.{digits}f} [{float(lo):.{digits}f}, {float(hi):.{digits}f}]"


def _xlsx_cell_value(val):
    """Scalarize cell values for openpyxl (lists/arrays break pd.isna)."""
    if val is None:
        return ""
    if isinstance(val, (list, tuple)):
        if len(val) == 2 and all(isinstance(x, (int, float, np.integer, np.floating)) for x in val):
            return f"{val[0]} to {val[1]}"
        return ", ".join(str(x) for x in val)
    if isinstance(val, np.ndarray):
        if val.size == 0:
            return ""
        if val.size == 1:
            val = val.item()
        else:
            return ", ".join(str(x) for x in val.tolist())
    try:
        if pd.isna(val):
            return ""
    except (ValueError, TypeError):
        return str(val)
    return val


def _save_table(
    df: pd.DataFrame,
    path: Path,
    *,
    title: str,
    footnote: str | None = None,
):
    """Manuscript SCI three-line xlsx only (no CSV twin).

    Lines: title (optional) → header (thick top + thin bottom) → body → last row thick bottom.
    Times New Roman 12; no vertical borders.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    out = df.copy()
    out.columns = [_disp(c) for c in out.columns]
    for c in out.columns:
        if out[c].dtype == object:
            out[c] = out[c].map(
                lambda v: _disp(v) if isinstance(v, str) else _xlsx_cell_value(v)
            )
    xlsx_p = Path(str(path) + ".xlsx")
    # drop any legacy csv twin
    csv_legacy = Path(str(path) + ".csv")
    if csv_legacy.exists():
        csv_legacy.unlink()

    wb = Workbook()
    ws = wb.active
    ws.title = "Table"
    ws.sheet_view.showGridLines = False
    nc = max(1, len(out.columns))
    thick = Side(style="medium", color="000000")
    thin = Side(style="thin", color="000000")
    font_title = Font(name="Times New Roman", bold=True, size=12)
    font_h = Font(name="Times New Roman", bold=True, size=12)
    font_b = Font(name="Times New Roman", size=12)
    font_fn = Font(name="Times New Roman", size=10)
    align_c = Alignment(horizontal="center", vertical="center", wrap_text=True)
    align_l = Alignment(horizontal="left", vertical="center", wrap_text=True)

    r0 = 1
    if title:
        cell = ws.cell(1, 1, title)
        cell.font = font_title
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        if nc > 1:
            ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=nc)
        ws.row_dimensions[1].height = 22
        r0 = 2

    # header
    for j, col in enumerate(out.columns, 1):
        cell = ws.cell(r0, j, col)
        cell.font = font_h
        cell.alignment = align_c
        cell.border = Border(top=thick, bottom=thin)
    # body (section header rows: only first column filled → bold)
    n = len(out)
    for i, row in enumerate(out.itertuples(index=False), r0 + 1):
        last = i == r0 + n
        vals = [_xlsx_cell_value(v) for v in row]
        is_section = len(vals) >= 2 and any(str(vals[0]).strip()) and all(
            (v is None or str(v).strip() in ("", "–", "-")) for v in vals[1:]
        )
        for j, val in enumerate(vals, 1):
            cell = ws.cell(i, j, val)
            cell.font = Font(name="Times New Roman", bold=True, size=12) if is_section else font_b
            cell.alignment = align_l if j == 1 else align_c
            if last:
                cell.border = Border(bottom=thick)
    if footnote:
        fr = r0 + n + 2
        cell = ws.cell(fr, 1, footnote)
        cell.font = font_fn
        cell.alignment = align_l
        if nc > 1:
            ws.merge_cells(start_row=fr, start_column=1, end_row=fr, end_column=nc)
        cell.border = Border(top=thin)
    for j in range(1, nc + 1):
        header = str(out.columns[j - 1]) if j <= len(out.columns) else ""
        ws.column_dimensions[get_column_letter(j)].width = min(36, max(14, len(header) + 2))
    wb.save(xlsx_p)


def _png_save_dpi(dpi: int = 600) -> tuple[float, float]:
    """pHYs integer ppm: round(600/0.0254)=23622 → 599.9988; bump +1 ppm so readback ≥600."""
    ppm = int(int(dpi) / 0.0254) + 1
    d = ppm * 0.0254
    return (d, d)


def _write_fig(fig, out_root: Path, name: str):
    from PIL import Image

    for kind, ext in (("pdf", "pdf"), ("png", "png"), ("tiff", "tiff")):
        d = out_root / "Figures" / kind
        d.mkdir(parents=True, exist_ok=True)
        target = d / f"{name}.{ext}"
        if ext == "pdf":
            fig.savefig(target, bbox_inches="tight")
        else:
            fig.savefig(target, dpi=600, bbox_inches="tight")
            if ext == "png":
                # matplotlib writes 599.9988; rewrite pHYs so Explorer/PIL ≥600
                with Image.open(target) as im:
                    rgba = im.convert("RGBA")
                    rgba.save(target, format="PNG", dpi=_png_save_dpi(600))
    plt.close(fig)


def _pick_metrics(unit_dir: Path, prefer: str | None) -> Path | None:
    cands = list(unit_dir.glob("results/**/metrics_multitask.csv"))
    if prefer:
        pref = [c for c in cands if prefer in str(c)]
        if pref:
            cands = pref
    if not cands:
        return None
    return sorted(cands, key=lambda p: p.stat().st_mtime, reverse=True)[0]


def _last_test(mpath: Path) -> dict:
    df = pd.read_csv(mpath)
    te = df[df["set"].astype(str).str.lower() == "test"].copy()
    te = te[te["epoch"] == te["epoch"].max()]
    out = {"n_train": int(df["n_train"].iloc[0])}
    for _, r in te.iterrows():
        task = str(r["task"]).lower()
        db = str(r["source_dataset"])
        if "mort" in task:
            out.setdefault(db, {})["auc"] = float(r["auc"]) if pd.notna(r.get("auc")) else float("nan")
        if "los" in task:
            out.setdefault(db, {})["mape"] = float(r["mape"]) if pd.notna(r.get("mape")) else float("nan")
    return out


def _auprc_from_preds(unit_dir: Path, prefer: str, db: str) -> float:
    cands = list(unit_dir.glob("results/**/test_predictions_mort.csv"))
    pref = [c for c in cands if prefer in str(c)] or cands
    if not pref:
        return float("nan")
    mort = pd.read_csv(sorted(pref, key=lambda p: p.stat().st_mtime, reverse=True)[0])
    g = mort[mort["eval_on"] == db]
    if g.empty or g["label"].nunique() < 2:
        return float("nan")
    stay = g.groupby("patientids").agg(y=("label", "max"), p=("pred_mort", "mean"))
    return float(average_precision_score(stay["y"], stay["p"]))


def mcomposite(auc, mape, auc0, mape0) -> float:
    if not all(np.isfinite([auc, mape, auc0, mape0])) or auc0 >= 1 or mape0 == 0:
        return float("nan")
    return float(0.5 * ((mape / mape0) + ((1 - auc) / (1 - auc0))))


def collect_main() -> dict:
    store = {}
    for arm, (unit, prefer) in ARM.items():
        mpath = _pick_metrics(MAIN_OUT / unit, prefer)
        if mpath is None:
            continue
        store[arm] = _last_test(mpath)
        store[arm]["auprc"] = {}
        for db in DB_ORDER:
            store[arm]["auprc"][db] = _auprc_from_preds(MAIN_OUT / unit, prefer, db)
    return store


def _ci_lookup(ci: pd.DataFrame | None, unit: str, db: str) -> dict:
    if ci is None or ci.empty:
        return {}
    hit = ci[(ci["unit"] == unit) & (ci["eval_on"] == db)]
    if hit.empty:
        return {}
    return hit.iloc[0].to_dict()


# --- Tables (manuscript / MOESM layouts) ---------------------------------


def _mean_sd(x: pd.Series, digits=1) -> str:
    x = pd.to_numeric(x, errors="coerce").dropna()
    if x.empty:
        return "–"
    return f"{x.mean():.{digits}f} [{x.std():.{digits}f}]"


def _n_pct(num: int, den: int) -> str:
    if den <= 0:
        return "–"
    return f"{num:,} ({100.0 * num / den:.1f}%)"


# Allyn Table 1 continuous / drug rows (Critical Care 2026)
_T1_VITALS = [
    ("heart_rate", "   Heart rate (/min)"),
    ("invasive_systolic_blood_pressure", "   Invasive Systolic Arterial pressure (mmHg)"),
    ("O2_arterial_saturation", "   O2 Saturation in Arterial blood (%)"),
    ("temperature", "   Temperature (°C)"),
]
_T1_LABS = [
    ("pH", "   pH"),
    ("platelets", "   Platelets count (G/L)"),
]
# MOESM1 "Normal physiological range" — clip before stay-level mean for Table 1 display
# (training path: same MOESM1 physio clip → q5/q95 → [-4,4]).
_T1_PHYSIO_CLIP = {
    "heart_rate": (46.74, 122.7),
    "invasive_systolic_blood_pressure": (67.78, 175.8),
    "O2_arterial_saturation": (88.7, 103.7),
    "temperature": (35.61, 38.23),
    "pH": (7.235, 7.564),
    "platelets": (150.0, 370.5),
}
_T1_DRUGS = [
    "dobutamine",
    "dopamine",
    "epinephrine",
    "fentanyl",
    "furosemide",
    "midazolam",
    "norepinephrine",
    "propofol",
]
_T1_UNITS = [
    "Cardiac",
    "Gastrosurgery",
    "Medical",
    "Medical-Surgical",
    "Neurological",
    "Other",
    "Surgical",
    "Trauma",
    "Unknown",
]


def _table1_one_stay(args):
    """Worker: one stay parquet → stay-level means / drug flags."""
    pid, db, pth, want_cols = args
    try:
        df = pd.read_parquet(pth)
    except Exception:
        return None
    out = {"patient": pid, "source_dataset": db}
    for c in want_cols:
        if c not in df.columns:
            out[c] = np.nan
            out[f"exp_{c}"] = 0
            continue
        s = pd.to_numeric(df[c], errors="coerce")
        if c in _T1_PHYSIO_CLIP and c not in _T1_DRUGS:
            lo, hi = _T1_PHYSIO_CLIP[c]
            s = s.clip(lower=lo, upper=hi)
        out[c] = float(s.mean()) if s.notna().any() else np.nan
        out[f"exp_{c}"] = int((s.fillna(0) > 0).any()) if c in _T1_DRUGS else 0
    return out


def _table1_scan_timeseries(lab: pd.DataFrame) -> tuple[dict, dict]:
    """Stay-level mean of vitals/labs + drug exposure flags; cache under _internal.

    Continuous vitals/labs are clipped to MOESM1 physiological ranges *before*
    the stay-level mean (Table 1 display only; does not retrain the model).
    """
    cache = PUB / "_internal" / f"table1_ts_cache_physclip_{BLENDED_SUBDIR}.parquet"
    cache.parent.mkdir(parents=True, exist_ok=True)
    if cache.exists():
        cached = pd.read_parquet(cache)
        if set(cached["patient"]) >= set(lab["patient"].astype(str)) and len(cached) >= len(lab) * 0.98:
            return (
                cached.set_index("patient"),
                {"from_cache": True},
            )

    ts_root = BLENDED_ROOT / "preprocessed_timeseries"
    want_cols = [c for c, _ in _T1_VITALS + _T1_LABS] + list(_T1_DRUGS)
    jobs = []
    for db in ("eicu", "amsterdam", "hirid", "mimic4"):
        idx_p = ts_root / db / "index.csv"
        if not idx_p.exists():
            continue
        idx = pd.read_csv(idx_p, sep=";")
        if "patient" not in idx.columns or "ts_pth" not in idx.columns:
            continue
        keep = set(lab.loc[lab["source_dataset"] == db, "patient"].astype(str))
        idx = idx[idx["patient"].astype(str).isin(keep)]
        for _, r in idx.iterrows():
            pth = Path(str(r["ts_pth"]))
            if pth.exists():
                jobs.append((str(r["patient"]), db, str(pth), want_cols))

    rows = []
    n_workers = int(os.environ.get("LIVER_TABLE1_WORKERS", "24"))
    print(f"[table1] scanning {len(jobs)} stays with {n_workers} threads…", flush=True)
    done = 0
    with ThreadPoolExecutor(max_workers=n_workers) as ex:
        futs = [ex.submit(_table1_one_stay, j) for j in jobs]
        for fut in as_completed(futs):
            rec = fut.result()
            if rec is not None:
                rows.append(rec)
            done += 1
            if done % 2000 == 0 or done == len(jobs):
                print(f"[table1] {done}/{len(jobs)}", flush=True)
    if not rows:
        return pd.DataFrame().set_index(pd.Index([], name="patient")), {"from_cache": False}
    tab = pd.DataFrame(rows)
    tab.to_parquet(cache, index=False)
    return tab.set_index("patient"), {"from_cache": False, "n": len(tab)}


def table1_wide() -> pd.DataFrame:
    """Allyn Table 1 full layout: demographics + vitals + labs + unit + 8 drugs."""
    lab = pd.read_parquet(BLENDED_ROOT / "preprocessed_labels.parquet")
    if "patient" not in lab.columns:
        lab = lab.reset_index()
    lab["patient"] = lab["patient"].astype(str)

    # Join ready labels for unit_type + raw demography when available
    ready_lab = Path("/mnt/sda/BlendedICU/data/blendedlos_ready/preprocessed_labels.parquet")
    if ready_lab.exists():
        rl = pd.read_parquet(ready_lab)
        if "patient" not in rl.columns:
            rl = rl.reset_index()
        rl["patient"] = rl["patient"].astype(str)
        keep_cols = [
            c
            for c in ("patient", "unit_type", "care_site", "raw_age", "raw_height", "raw_weight")
            if c in rl.columns
        ]
        lab = lab.merge(rl[keep_cols], on="patient", how="left", suffixes=("", "_ready"))

    ts_by_pid, _meta = _table1_scan_timeseries(lab)

    col_keys = ["eicu", "amsterdam", "hirid", "mimic4"]
    cols = [DB_LAB[d] for d in col_keys]
    data: dict[str, dict] = {c: {} for c in cols}

    for db in col_keys:
        g = lab[lab["source_dataset"] == db].copy()
        n_stay = len(g)
        labname = DB_LAB[db]
        age = pd.to_numeric(g["raw_age"] if "raw_age" in g.columns else g["age"], errors="coerce")
        sex = pd.to_numeric(g["sex"], errors="coerce")
        ht = pd.to_numeric(g["raw_height"] if "raw_height" in g.columns else g.get("height"), errors="coerce")
        wt = pd.to_numeric(g["raw_weight"] if "raw_weight" in g.columns else g.get("weight"), errors="coerce")
        los_d = pd.to_numeric(g["true_lengthofstay"], errors="coerce")
        los_h = los_d * 24.0
        mort = pd.to_numeric(g["mortality"], errors="coerce")
        n_male = int((sex == 1).sum())
        n_female = int((sex == 0).sum())
        n_unk = max(0, n_stay - n_male - n_female)

        # Allyn: Multi-centric = Yes (N = n hospitals); eICU care_site = hospitalid
        if "care_site" in g.columns:
            n_sites = int(g["care_site"].dropna().astype(str).nunique())
        else:
            n_sites = 0
        if n_sites > 1:
            multicentric = f"Yes (N = {n_sites:,})"
        else:
            multicentric = "No"

        cell = {
            "multicentric": multicentric,
            "patients": _fmt_n(int(g["uniquepid"].nunique())),
            "stays": _fmt_n(n_stay),
            "age": _mean_sd(age, 1),
            "female": _n_pct(n_female, n_stay),
            "male": _n_pct(n_male, n_stay),
            "unknown_sex": _n_pct(n_unk, n_stay) if n_unk else "–",
            "height": _mean_sd(ht, 1),
            "weight": _mean_sd(wt, 1),
            "los_h": _mean_sd(los_h, 1),
            "los_gt10": _n_pct(int((los_d > 10).sum()), n_stay),
            "mort": _n_pct(int(mort.fillna(0).sum()), n_stay),
        }

        # unit types
        if "unit_type" in g.columns:
            ut = g["unit_type"].fillna("Unknown").astype(str)
            ut = ut.replace({"nan": "Unknown", "None": "Unknown", "": "Unknown"})
            # normalize capitalization to paper labels
            ut = ut.map(lambda x: x if x in _T1_UNITS else (x.title() if x.lower() != "unknown" else "Unknown"))
            ut = ut.map(lambda x: "Medical-Surgical" if x.replace(" ", "").lower() in ("medicalsurgical", "medical-surgical") else x)
            for u in _T1_UNITS:
                cell[f"unit_{u}"] = _n_pct(int((ut == u).sum()), n_stay) if (ut == u).any() else "–"
        else:
            for u in _T1_UNITS:
                cell[f"unit_{u}"] = "–"

        # vitals / labs / drugs from stay-level TS summary
        if len(ts_by_pid):
            sub = ts_by_pid.loc[ts_by_pid.index.intersection(g["patient"])]
        else:
            sub = pd.DataFrame()
        for col, _lab in _T1_VITALS + _T1_LABS:
            if len(sub) and col in sub.columns:
                cell[f"ts_{col}"] = _mean_sd(sub[col], 1)
            else:
                cell[f"ts_{col}"] = "–"
        for drug in _T1_DRUGS:
            key = f"exp_{drug}"
            if len(sub) and key in sub.columns:
                n_exp = int(pd.to_numeric(sub[key], errors="coerce").fillna(0).sum())
                cell[f"drug_{drug}"] = _n_pct(n_exp, n_stay) if n_exp else "–"
            else:
                cell[f"drug_{drug}"] = "–"

        data[labname] = cell

    rows_spec: list[tuple[str, str | None]] = [
        ("Multi-centric database", "multicentric"),
        ("Patients, n", "patients"),
        ("ICU stays, n", "stays"),
        ("Demographics", None),
        ("Age (years), mean [SD]", "age"),
        ("Sex, n (%)", None),
        ("   Female", "female"),
        ("   Male", "male"),
        ("   Unknown", "unknown_sex"),
        ("Height (cm), mean [SD]", "height"),
        ("Weight (kg), mean [SD]", "weight"),
        ("ICU LoS (hours), mean [SD]", "los_h"),
        ("ICU LoS > 10 days, n (%)", "los_gt10"),
        ("ICU mortality, n (%)", "mort"),
        ("Continuous variables", None),
        ("Vitals, mean [SD]", None),
    ]
    for col, lab_txt in _T1_VITALS:
        rows_spec.append((lab_txt, f"ts_{col}"))
    rows_spec.append(("Laboratory, mean [SD]", None))
    for col, lab_txt in _T1_LABS:
        rows_spec.append((lab_txt, f"ts_{col}"))
    rows_spec.append(("Unit type, n (%)", None))
    for u in _T1_UNITS:
        rows_spec.append((f"   {u}", f"unit_{u}"))
    rows_spec.append(("Drug exposure, n (%)", None))
    for drug in _T1_DRUGS:
        rows_spec.append((f"   {drug.capitalize()}", f"drug_{drug}"))

    out_rows = []
    for label, key in rows_spec:
        row = {"Characteristics": label}
        for c in cols:
            row[c] = "" if key is None else data[c].get(key, "–")
        out_rows.append(row)
    return pd.DataFrame(out_rows)


def _fmt_var_pct(rel: float) -> str:
    if not np.isfinite(rel):
        return "–"
    sign = "+" if rel > 0 else ""
    return f"{sign}{rel:.1f}%"


def _fmt_ci_en(est, lo, hi, digits: int) -> str:
    """Allyn-style point [lo–hi] with en-dash."""
    if est is None or (isinstance(est, float) and not np.isfinite(est)):
        return "–"
    if lo is None or hi is None or not (np.isfinite(lo) and np.isfinite(hi)):
        return _fmt_est(est, digits)
    return f"{float(est):.{digits}f} [{float(lo):.{digits}f}–{float(hi):.{digits}f}]"


def _fmt_auprc_ci_cell(est, lo, hi, baseline: float) -> str:
    core = _fmt_ci_en(est, lo, hi, 3)
    if core == "–":
        return core
    if np.isfinite(baseline):
        return f"{core} (Baseline: {baseline:.3f})"
    return core


def _import_paper_ci():
    """Load DeLong/bootstrap helpers from eval_liver_paper_ci.py (same dir or /tmp)."""
    import importlib.util

    cands = [
        Path(__file__).resolve().parent / "eval_liver_paper_ci.py",
        Path("/tmp/eval_liver_paper_ci.py"),
    ]
    for p in cands:
        if not p.is_file():
            continue
        spec = importlib.util.spec_from_file_location("eval_liver_paper_ci", p)
        if spec is None or spec.loader is None:
            continue
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    raise FileNotFoundError("eval_liver_paper_ci.py not found next to finalize or in /tmp")


def _table2_block_metrics(stay: pd.DataFrame, n_boot: int, ci_mod) -> dict:
    """Stay-level MAPE / AUROC / AUPRC + CIs for one stay frame (internal or pooled external)."""
    out = {
        "mape": float("nan"),
        "mape_lo": float("nan"),
        "mape_hi": float("nan"),
        "auc": float("nan"),
        "auc_lo": float("nan"),
        "auc_hi": float("nan"),
        "auprc": float("nan"),
        "auprc_lo": float("nan"),
        "auprc_hi": float("nan"),
        "baseline": float("nan"),
    }
    if stay is None or stay.empty:
        return out
    y = stay["y_mort"].to_numpy()
    p = stay["pred_mort"].to_numpy()
    if np.unique(y).size >= 2:
        auc, lo, hi = ci_mod.delong_auc_ci(y, p)
        out["auc"], out["auc_lo"], out["auc_hi"] = auc, lo, hi
        out["auprc"] = float(average_precision_score(y, p))
        a_lo, a_hi = ci_mod._boot_ci_auprc(stay, n_boot=n_boot, seed=42)
        out["auprc_lo"], out["auprc_hi"] = a_lo, a_hi
        out["baseline"] = float(np.mean(y))
    if "mape" in stay.columns and stay["mape"].notna().any():
        mdf = stay.dropna(subset=["mape"]).copy()
        out["mape"] = float(mdf["mape"].mean())
        m_lo, m_hi = ci_mod._boot_ci_person(mdf, "mape", n_boot=n_boot, seed=42)
        out["mape_lo"], out["mape_hi"] = m_lo, m_hi
    return out


def table2_manuscript(extra_root: Path) -> pd.DataFrame:
    """Allyn Table 2: Task|Internal|External|Variation with 95% CIs.

    Internal = train DB; External = pooled other three DBs (one CI, not mean of three).
    AUROC CI: DeLong (stay). MAPE/AUPRC CI: patient-level bootstrap 10,000.
    """
    ud = extra_root / "liver_dataset_benchmark"
    if not ud.exists():
        return pd.DataFrame()

    n_boot = int(os.environ.get("LIVER_TABLE2_N_BOOT", "10000"))
    ci_mod = _import_paper_ci()
    train_order = ["amsterdam", "eicu", "hirid", "mimic4"]
    col_task = "Task and training dataset"
    col_int = "Internal validation"
    col_ext = "External validation"
    col_var = "Variation between internal and external validation"

    by_train: dict[str, dict] = {}
    for mort_p in sorted(ud.glob("results/**/test_predictions_mort.csv")):
        train_db = None
        for part in mort_p.parts:
            for key in DB_LAB:
                if part.startswith(key + "_") or part == f"{key}_100":
                    train_db = key
                    break
            if train_db:
                break
        if train_db is None:
            continue
        los_p = mort_p.parent / "test_predictions_los.csv"
        mort = pd.read_csv(mort_p)
        los = pd.read_csv(los_p) if los_p.exists() else None
        stay, _hourly = ci_mod._stay_frame(mort, los)
        st_int = stay[stay["eval_on"] == train_db]
        st_ext = stay[stay["eval_on"] != train_db]
        print(
            f"[table2] CI train={train_db} n_boot={n_boot} "
            f"n_int={len(st_int)} n_ext={len(st_ext)}",
            flush=True,
        )
        by_train[train_db] = {
            "internal": _table2_block_metrics(st_int, n_boot, ci_mod),
            "external": _table2_block_metrics(st_ext, n_boot, ci_mod),
        }

    sections = [
        ("Remaining length of stay prediction, MAPE [CI 95%]", "mape", 1, False),
        ("Mortality prediction, AUROC [CI 95%]", "auc", 3, False),
        ("Mortality prediction, AUPRC [CI 95%]", "auprc", 3, True),
    ]

    rows: list[dict] = []
    for sect_title, mkey, digits, with_base in sections:
        rows.append({col_task: sect_title, col_int: "", col_ext: "", col_var: ""})
        for train_db in train_order:
            if train_db not in by_train:
                continue
            iv = by_train[train_db]["internal"]
            ev = by_train[train_db]["external"]
            if mkey == "mape":
                iv_s = _fmt_ci_en(iv["mape"], iv["mape_lo"], iv["mape_hi"], digits)
                ev_s = _fmt_ci_en(ev["mape"], ev["mape_lo"], ev["mape_hi"], digits)
                iv_pt, ev_pt = iv["mape"], ev["mape"]
            elif mkey == "auc":
                iv_s = _fmt_ci_en(iv["auc"], iv["auc_lo"], iv["auc_hi"], digits)
                ev_s = _fmt_ci_en(ev["auc"], ev["auc_lo"], ev["auc_hi"], digits)
                iv_pt, ev_pt = iv["auc"], ev["auc"]
            else:
                iv_s = _fmt_auprc_ci_cell(
                    iv["auprc"], iv["auprc_lo"], iv["auprc_hi"], iv["baseline"]
                )
                ev_s = _fmt_auprc_ci_cell(
                    ev["auprc"], ev["auprc_lo"], ev["auprc_hi"], ev["baseline"]
                )
                iv_pt, ev_pt = iv["auprc"], ev["auprc"]
            rel = (
                (ev_pt - iv_pt) / iv_pt * 100
                if np.isfinite(iv_pt) and iv_pt and np.isfinite(ev_pt)
                else float("nan")
            )
            rows.append(
                {
                    col_task: DB_LAB[train_db],
                    col_int: iv_s,
                    col_ext: ev_s,
                    col_var: _fmt_var_pct(rel),
                }
            )

    return pd.DataFrame(rows, columns=[col_task, col_int, col_ext, col_var])


def _table3_col_header(arm: str, n_train) -> str:
    """Allyn Table 3 column titles (with N)."""
    n = _fmt_n(n_train) if n_train is not None else "–"
    if arm == "Amsterdam only":
        return f"Training on AmsterdamUMC\nN = {n}"
    if arm == "MIMIC-IV only":
        return f"Training on MIMIC-IV\nN = {n}"
    if arm == "Transfer":
        return f"Training by Transfer Learning¹\nN = {n}"
    if arm == "Pooling":
        return f"Training by Data Pooling²\nN = {n}"
    return arm


def _table3_metric_from_ci(
    ci: pd.DataFrame | None,
    unit: str,
    db: str,
    *,
    base_auc: float,
    base_mape: float,
) -> dict:
    """Stay-level AUROC/MAPE (+CI) and Mcomposite for one unit×eval_on."""
    h = _ci_lookup(ci, unit, db)
    out = {
        "auc": float("nan"),
        "auc_lo": float("nan"),
        "auc_hi": float("nan"),
        "mape": float("nan"),
        "mape_lo": float("nan"),
        "mape_hi": float("nan"),
        "mcomp": float("nan"),
    }
    if not h:
        return out
    auc = h.get("auroc_stay")
    mape = h.get("mape_stay_mean")
    if auc is not None and pd.notna(auc):
        out["auc"] = float(auc)
        out["auc_lo"] = float(h.get("auroc_stay_lo_delong", float("nan")))
        out["auc_hi"] = float(h.get("auroc_stay_hi_delong", float("nan")))
    if mape is not None and pd.notna(mape):
        out["mape"] = float(mape)
        out["mape_lo"] = float(h.get("mape_lo_boot10k", float("nan")))
        out["mape_hi"] = float(h.get("mape_hi_boot10k", float("nan")))
    out["mcomp"] = mcomposite(out["auc"], out["mape"], base_auc, base_mape)
    return out


def _table3_gen_pool_from_ci(
    ci: pd.DataFrame | None,
    unit: str,
    *,
    base_auc: float,
    base_mape: float,
) -> dict:
    """Generalization = mean of eICU + HiRID stay-level metrics (Allyn single Gen block)."""
    parts = [
        _table3_metric_from_ci(ci, unit, db, base_auc=base_auc, base_mape=base_mape)
        for db in ("eicu", "hirid")
    ]
    parts = [p for p in parts if np.isfinite(p["auc"]) or np.isfinite(p["mape"])]
    out = {
        "auc": float("nan"),
        "auc_lo": float("nan"),
        "auc_hi": float("nan"),
        "mape": float("nan"),
        "mape_lo": float("nan"),
        "mape_hi": float("nan"),
        "mcomp": float("nan"),
    }
    if not parts:
        return out
    for key in ("auc", "auc_lo", "auc_hi", "mape", "mape_lo", "mape_hi"):
        vals = [p[key] for p in parts if np.isfinite(p[key])]
        if vals:
            out[key] = float(np.mean(vals))
    out["mcomp"] = mcomposite(out["auc"], out["mape"], base_auc, base_mape)
    return out


def table3_wide_matrix(store: dict, ci: pd.DataFrame | None) -> pd.DataFrame:
    """Allyn Table 3 layout: one metric column + four training-strategy columns.

    Sections: Specialization on AmsterdamUMC | Specialization on MIMIC-IV | Generalization.
    Metrics: Mortality AUROC, RLoS MAPE, Mcomposite (no AUPRC). Transfer blank except
    Amsterdam specialization. Points/CIs from stay-level DeLong / bootstrap tables.
    """
    arms = ["Amsterdam only", "MIMIC-IV only", "Transfer", "Pooling"]
    col0 = "Evaluation set and metric [CI 95%]"

    # Baseline for Mcomposite: Amsterdam-alone on Amsterdam (stay-level when CI present)
    base = _table3_metric_from_ci(
        ci, ARM["Amsterdam only"][0], "amsterdam", base_auc=0.5, base_mape=100.0
    )
    if not np.isfinite(base["auc"]):
        base_auc = store.get("Amsterdam only", {}).get("amsterdam", {}).get("auc", float("nan"))
        base_mape = store.get("Amsterdam only", {}).get("amsterdam", {}).get("mape", float("nan"))
    else:
        base_auc, base_mape = base["auc"], base["mape"]

    col_map = {arm: _table3_col_header(arm, store.get(arm, {}).get("n_train")) for arm in arms}

    sections = [
        ("Specialization on AmsterdamUMC", "amsterdam", False),
        ("Specialization on MIMIC-IV", "mimic4", False),
        ("Generalization", "gen", True),
    ]
    metric_specs = [
        ("Mortality, AUROC", "auc", 2),
        ("RLoS, MAPE", "mape", 2),
        ("Mcomposite", "mcomp", 2),
    ]

    rows: list[dict] = []
    for sect_title, db_key, is_gen in sections:
        rows.append({col0: sect_title, **{col_map[a]: "" for a in arms}})
        for mlab, mkey, digits in metric_specs:
            row = {col0: mlab}
            for arm in arms:
                # Allyn: Transfer Learning only reported on Amsterdam specialization
                if arm == "Transfer" and db_key != "amsterdam":
                    row[col_map[arm]] = "–"
                    continue
                unit = ARM[arm][0]
                if is_gen:
                    met = _table3_gen_pool_from_ci(
                        ci, unit, base_auc=base_auc, base_mape=base_mape
                    )
                else:
                    met = _table3_metric_from_ci(
                        ci, unit, db_key, base_auc=base_auc, base_mape=base_mape
                    )
                if mkey == "auc":
                    if not np.isfinite(met["auc"]):
                        row[col_map[arm]] = "–"
                    else:
                        row[col_map[arm]] = _fmt_ci_en(
                            met["auc"], met["auc_lo"], met["auc_hi"], digits
                        )
                elif mkey == "mape":
                    if not np.isfinite(met["mape"]):
                        row[col_map[arm]] = "–"
                    else:
                        row[col_map[arm]] = _fmt_ci_en(
                            met["mape"], met["mape_lo"], met["mape_hi"], digits
                        )
                else:
                    row[col_map[arm]] = (
                        _fmt_est(met["mcomp"], digits) if np.isfinite(met["mcomp"]) else "–"
                    )
            rows.append(row)

    cols = [col0] + [col_map[a] for a in arms]
    return pd.DataFrame(rows, columns=cols)


def table_s2_wide(extra_root: Path) -> pd.DataFrame:
    """MOESM2 layout: equal-n four-DB training; Prediction × Validation × LSTM|Transformer|TPC.

    Prefer rebuild_table_s2_moesm2.py for CI + bold. This returns a thin DataFrame
    only as a fallback when the dedicated rebuild is unavailable.
    """
    # MOESM2 validation order
    s2_dbs = ["amsterdam", "eicu", "hirid", "mimic4"]
    ud = extra_root / "liver_model_benchmark_equaln"
    if not ud.exists():
        ud = extra_root / "liver_model_benchmark"
    if not ud.exists():
        return pd.DataFrame()
    ci_path = extra_root / "ci_liver_model_benchmark_equaln" / "Table_CI_DeLong_bootstrap10k.csv"
    if not ci_path.exists() and (extra_root / "liver_model_benchmark").exists():
        ci_path = extra_root / "ci_liver_model_benchmark" / "Table_CI_DeLong_bootstrap10k.csv"
    ci = pd.read_csv(ci_path) if ci_path.exists() else pd.DataFrame()
    if len(ci):
        ci = ci.copy()
        ci["model"] = ci["model"].astype(str).str.lower().map(
            {"lstm": "LSTM", "transformer": "Transformer", "tpc": "TPC"}
        )
    grid = {m: {} for m in ("LSTM", "Transformer", "TPC")}
    n_train = None
    for mpath in sorted(ud.glob("results/**/metrics_multitask.csv")):
        model = "TPC"
        for part in mpath.parts:
            pl = part.lower()
            if pl == "lstm":
                model = "LSTM"
            elif pl == "transformer":
                model = "Transformer"
            elif pl == "tpc":
                model = "TPC"
        spec = _last_test(mpath)
        n_train = spec.get("n_train", n_train)
        for db in s2_dbs:
            if db in spec:
                grid[model][db] = spec[db]
    rows = []
    for task, key, digits in (
        ("Remaining length of stay, MAPE [95% CI]", "mape", 1),
        ("Mortality, AUROC [95% CI]", "auc", 3),
    ):
        for db in s2_dbs:
            row = {"Prediction": task, "Validation dataset": DB_LAB[db]}
            for model in ("LSTM", "Transformer", "TPC"):
                est = grid[model].get(db, {}).get(key, float("nan"))
                lo = hi = float("nan")
                if len(ci):
                    sub = ci[(ci["model"] == model) & (ci["eval_on"] == db)]
                    if len(sub):
                        r0 = sub.iloc[0]
                        if key == "auc":
                            est = float(r0.get("auroc_stay", est))
                            lo = float(r0.get("auroc_stay_lo_delong", np.nan))
                            hi = float(r0.get("auroc_stay_hi_delong", np.nan))
                        else:
                            est = float(r0.get("mape_stay_mean", est))
                            lo = float(r0.get("mape_lo_boot10k", np.nan))
                            hi = float(r0.get("mape_hi_boot10k", np.nan))
                row[model] = _fmt_ci_en(est, lo, hi, digits)
            rows.append(row)
    df = pd.DataFrame(rows)
    if n_train is not None:
        df.attrs["n_train"] = n_train
    return df


def table_s2_equaln_long(extra_root: Path) -> pd.DataFrame:
    """Keep equal-n three-model as supplementary long/wide hybrid."""
    ud = extra_root / "liver_model_benchmark_equaln"
    if not ud.exists():
        return pd.DataFrame()
    grid = {m: {} for m in ("LSTM", "Transformer", "TPC")}
    n_train = None
    for mpath in sorted(ud.glob("results/**/metrics_multitask.csv")):
        model = "TPC"
        for part in mpath.parts:
            pl = part.lower()
            if pl in ("lstm", "transformer", "tpc"):
                model = "TPC" if pl == "tpc" else pl.upper() if pl != "transformer" else "Transformer"
                if pl == "lstm":
                    model = "LSTM"
        spec = _last_test(mpath)
        n_train = spec.get("n_train", n_train)
        for db in ("eicu", "hirid"):
            if db in spec:
                grid[model][db] = spec[db]
    rows = []
    for task, key, digits in (
        ("Remaining length of stay, MAPE", "mape", 1),
        ("Mortality, AUROC", "auc", 3),
    ):
        for db in ("eicu", "hirid"):
            row = {"Prediction": task, "Validation dataset": DB_LAB[db], "Setting": "Equal-n four databases"}
            for model in ("LSTM", "Transformer", "TPC"):
                row[model] = _fmt_est(grid[model].get(db, {}).get(key, float("nan")), digits)
            if n_train:
                row["N train"] = _fmt_n(n_train)
            rows.append(row)
    return pd.DataFrame(rows)


# --- Figures --------------------------------------------------------------


def _flow_box(ax, x, y, w, h, title, subtitle, face):
    ax.add_patch(
        FancyBboxPatch(
            (x, y),
            w,
            h,
            boxstyle="round,pad=0.012,rounding_size=0.08",
            facecolor=face,
            edgecolor=EDGE,
            linewidth=0.75,
            mutation_aspect=0.6,
        )
    )
    ax.text(x + w / 2, y + h * 0.62, title, ha="center", va="center", fontsize=8.3, color=INK, fontweight="medium")
    if subtitle:
        ax.text(x + w / 2, y + h * 0.28, subtitle, ha="center", va="center", fontsize=6.5, color=MUTED)


def _chip(ax, x, y, w, h, text, face):
    ax.add_patch(
        FancyBboxPatch(
            (x, y),
            w,
            h,
            boxstyle="round,pad=0.01,rounding_size=0.06",
            facecolor=face,
            edgecolor=EDGE,
            linewidth=0.6,
        )
    )
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=7.2, color=INK)


def make_fig1(out: Path, store: dict):
    """Allyn Fig.1: seven-step pipeline + four strategies with N and eval notes.

    No figure-level caption/footnote on the canvas (caption lives in manuscript / image_information).
    """
    fig, axes = plt.subplots(1, 2, figsize=(11.6, 7.0), gridspec_kw={"width_ratios": [1.05, 1.18]})
    ax = axes[0]
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 11.0)
    ax.axis("off")
    # Panel title clear of first box (first box top = top + box_h ≤ 9.2)
    ax.text(0.12, 10.55, "A", fontsize=14, fontweight="bold", color=INK, ha="left", va="center")
    ax.text(0.65, 10.55, "Study pipeline", fontsize=12, color=INK, ha="left", va="center")

    steps = [
        (f"1  {COHORT_TITLE} cohort", COHORT_RULE_SHORT, "#d7e6f5"),
        ("2  Four ICU databases", "AmsterdamUMC, MIMIC-IV, eICU, HiRID (BlendedICU)", "#dceee4"),
        ("3  Preprocess", "Physiological clip, MNAR ffill + mask, q5–q95 scale", "#efe6c9"),
        ("4  Patient-level split", "70% / 15% / 15% (seed 974); main arms hold out eICU+HiRID", "#f6dfd4"),
        ("5  TPC multitask model", "Hourly ICU death risk + remaining length of stay", "#e8dff5"),
        ("6  Internal then external test", "AUROC, AUPRC, MAPE; four strategies in panel B", "#e6e4f4"),
        ("7  Hourly clinical outputs", "Death probability; RLoS if predicted alive", "#f7f3ea"),
    ]
    box_w, box_h, x0, top, gap = 8.75, 0.86, 0.6, 8.25, 0.16
    for i, (title, sub, face) in enumerate(steps):
        y = top - i * (box_h + gap)
        _flow_box(ax, x0, y, box_w, box_h, title, sub, face)
        if i < len(steps) - 1:
            ax.annotate(
                "",
                xy=(x0 + box_w / 2, y - gap + 0.02),
                xytext=(x0 + box_w / 2, y),
                arrowprops=dict(arrowstyle="-|>", color=EDGE, lw=0.85, mutation_scale=9),
            )

    ax = axes[1]
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 11.0)
    ax.axis("off")
    ax.text(0.12, 10.55, "B", fontsize=14, fontweight="bold", color=INK, ha="left", va="center")
    ax.text(0.65, 10.55, "Four training strategies", fontsize=12, color=INK, ha="left", va="center")

    n_ams = store.get("Amsterdam only", {}).get("n_train")
    n_mim = store.get("MIMIC-IV only", {}).get("n_train")
    n_tr = store.get("Transfer", {}).get("n_train")
    n_pool = store.get("Pooling", {}).get("n_train")

    rows = [
        (
            7.15,
            "1",
            "AmsterdamUMC alone",
            [("AmsterdamUMC", 1.1, 2.2)],
            "Specialization on AmsterdamUMC",
            f"N = {_fmt_n(n_ams)}",
        ),
        (
            5.20,
            "2",
            "MIMIC-IV alone",
            [("MIMIC-IV", 1.1, 1.75)],
            "Specialization on MIMIC-IV; generalization eICU+HiRID",
            f"N = {_fmt_n(n_mim)}",
        ),
        (
            3.25,
            "3",
            "Transfer: MIMIC-IV → AmsterdamUMC",
            [("MIMIC-IV", 1.1, 1.75), ("AmsterdamUMC", 3.55, 2.2)],
            "Evaluated after fine-tuning (Amsterdam specialization)",
            f"N = {_fmt_n(n_tr)}",
        ),
        (
            1.15,
            "4",
            "Pooling (single training run)",
            [("AmsterdamUMC", 1.1, 2.2), ("MIMIC-IV", 3.5, 1.75)],
            "Specialization + generalization (eICU and HiRID)",
            f"N = {_fmt_n(n_pool)}",
        ),
    ]
    for y, num, name, chips, outcome, nlab in rows:
        ax.add_patch(plt.Circle((0.45, y + 0.78), 0.28, facecolor=EDGE, edgecolor="none"))
        ax.text(0.45, y + 0.78, num, ha="center", va="center", fontsize=9, color="white", fontweight="bold")
        ax.text(0.95, y + 1.32, name, ha="left", va="center", fontsize=9.0, color=INK)
        for src, cx, cw in chips:
            _chip(ax, cx, y + 0.48, cw, 0.42, src, DB_FACE[src])
        if num == "3":
            ax.annotate(
                "",
                xy=(3.48, y + 0.69),
                xytext=(2.95, y + 0.69),
                arrowprops=dict(arrowstyle="-|>", color=EDGE, lw=0.85, mutation_scale=8),
            )
        ax.text(0.95, y + 0.12, outcome, ha="left", va="center", fontsize=7.0, color=MUTED)
        ax.text(9.75, y + 0.78, nlab, ha="right", va="center", fontsize=8.0, color=MUTED, fontstyle="italic")

    # Avoid tight_layout collapsing the title–box gap; no figtext/suptitle/caption.
    fig.subplots_adjust(left=0.03, right=0.99, top=0.97, bottom=0.03, wspace=0.08)
    _write_fig(fig, out, "Figure 1. Study pipeline")


def fig2_training_size(extra_root: Path, out: Path) -> pd.DataFrame:
    """Allyn Fig.2 layout: left=Composite; right inner=RLoS MAPE; right outer=Mortality AUROC."""
    ud = extra_root / "liver_training_size_study"
    rows = []
    for mpath in sorted(ud.glob("results/**/metrics_multitask.csv")):
        spec = _last_test(mpath)
        aucs = [spec[d]["auc"] for d in ("eicu", "hirid") if d in spec]
        mapes = [spec[d]["mape"] for d in ("eicu", "hirid") if d in spec]
        if not aucs:
            continue
        pct = None
        for part in mpath.parts:
            if part.startswith("mimic4_"):
                try:
                    pct = int(part.split("_")[1])
                except Exception:
                    pass
        rows.append(
            {
                "n_train": spec["n_train"],
                "pct_trainval": pct,
                "auc": float(np.mean(aucs)),
                "mape": float(np.mean(mapes)),
            }
        )
    tab = pd.DataFrame(rows).drop_duplicates("n_train").sort_values("n_train")
    if tab.empty:
        return tab
    base_mape = float(tab["mape"].iloc[-1])
    base_auc = float(tab["auc"].iloc[-1])
    tab["Mcomposite"] = [
        mcomposite(a, m, base_auc, base_mape) for a, m in zip(tab["auc"], tab["mape"])
    ]

    # Paper colours (approx.)
    c_comp, c_rlos, c_mort = "#6b7280", "#3b82f6", "#f59a2f"

    fig, ax = plt.subplots(figsize=(8.2, 4.8))
    fig.patch.set_facecolor("white")
    ax.set_facecolor("#eceff3")
    ax.yaxis.grid(False)
    ax.xaxis.grid(True, linestyle="-", linewidth=0.7, color="#d5dae2", zorder=0)
    ax.set_axisbelow(True)

    # Left axis: Composite
    ax.plot(
        tab["n_train"],
        tab["Mcomposite"],
        "x",
        ms=7.5,
        mew=1.35,
        color=c_comp,
        zorder=3,
    )
    ax.set_ylabel("Composite metric (arbitrary unit)", color=c_comp, fontsize=10)
    ax.tick_params(axis="y", colors=c_comp, labelsize=9)
    ax.spines["left"].set_color(c_comp)
    ax.spines["left"].set_linewidth(1.1)
    ax.spines["top"].set_visible(False)
    ax.set_xlabel("Number of patients for training", color=INK, fontsize=10)
    ax.tick_params(axis="x", colors=INK, labelsize=9)
    ax.spines["bottom"].set_color("#9aa3af")

    # Right-inner: RLoS MAPE
    ax_r1 = ax.twinx()
    ax_r1.plot(
        tab["n_train"],
        tab["mape"],
        "x",
        ms=7.5,
        mew=1.35,
        color=c_rlos,
        zorder=3,
    )
    ax_r1.set_ylabel("Remaining length of stay (MAPE)", color=c_rlos, fontsize=10)
    ax_r1.tick_params(axis="y", colors=c_rlos, labelsize=9)
    ax_r1.spines["right"].set_color(c_rlos)
    ax_r1.spines["right"].set_linewidth(1.1)
    ax_r1.spines["top"].set_visible(False)
    ax_r1.spines["left"].set_visible(False)

    # Right-outer: Mortality AUROC
    ax_r2 = ax.twinx()
    ax_r2.spines["right"].set_position(("outward", 58))
    ax_r2.plot(
        tab["n_train"],
        tab["auc"],
        "x",
        ms=7.5,
        mew=1.35,
        color=c_mort,
        zorder=3,
    )
    ax_r2.set_ylabel("Mortality (AUROC)", color=c_mort, fontsize=10)
    ax_r2.tick_params(axis="y", colors=c_mort, labelsize=9)
    ax_r2.spines["right"].set_color(c_mort)
    ax_r2.spines["right"].set_linewidth(1.1)
    ax_r2.spines["top"].set_visible(False)
    ax_r2.spines["left"].set_visible(False)

    # In-panel series labels (paper style), near last points
    x_last = float(tab["n_train"].iloc[-1])
    x_pad = max(80.0, 0.03 * (float(tab["n_train"].max()) - float(tab["n_train"].min()) + 1))
    ax.text(
        x_last - x_pad,
        float(tab["Mcomposite"].iloc[-1]),
        "Composite",
        color=c_comp,
        fontsize=10,
        ha="right",
        va="bottom",
    )
    ax_r1.text(
        x_last - x_pad,
        float(tab["mape"].iloc[-1]),
        "RLoS",
        color=c_rlos,
        fontsize=10,
        ha="right",
        va="bottom",
    )
    ax_r2.text(
        x_last - x_pad,
        float(tab["auc"].iloc[-1]),
        "Mortality",
        color=c_mort,
        fontsize=10,
        ha="right",
        va="top",
    )

    # Reasonable y-limits with padding (paper-like)
    def _pad_lim(s, lo_floor=None, hi_ceil=None):
        lo, hi = float(s.min()), float(s.max())
        span = max(hi - lo, 1e-6)
        lo2, hi2 = lo - 0.12 * span, hi + 0.12 * span
        if lo_floor is not None:
            lo2 = min(lo2, lo_floor) if lo < lo_floor else lo2
        if hi_ceil is not None:
            hi2 = max(hi2, hi_ceil) if hi > hi_ceil else hi2
        return lo2, hi2

    ax.set_ylim(*_pad_lim(tab["Mcomposite"]))
    ax_r1.set_ylim(*_pad_lim(tab["mape"]))
    ax_r2.set_ylim(*_pad_lim(tab["auc"]))

    fig.subplots_adjust(left=0.11, right=0.82, top=0.96, bottom=0.12)
    _write_fig(fig, out, "Figure 2. Training size")
    return tab


def write_notes(out: Path, store: dict, size_tab: pd.DataFrame):
    b = store.get("MIMIC-IV only", {})
    d = store.get("Pooling", {})
    lines = [
        "# 和原文的差别",
        "",
        "原文：Allyn 等，Critical Care 2026，BlendedLoS（全体 ICU）。",
        f"本包：{COHORT_NOTE_ZH}",
        "",
        "## 已对齐原文的分析内容",
        "",
        "- Figure 1：七步流程 + 四训练策略（含 N、Transfer 箭头、specialization/generalization）",
        "- Figure 2：三轴（左 Composite，右 MAPE + AUROC）；× 点；不插值",
        "- Tables 仅保留原文角色：Table 1–3、Table S1（Scaling）、Table S2（MOESM2 三模型）",
        "- 发表表为 Times New Roman 标准三线 xlsx（无 CSV 双份；CI/Fig2 数据在 _internal）",
        "",
        "## 与原文仍不同的地方",
        "",
        f"- 入组不是全体 ICU，是 {COHORT_SUBSET_ZH}；每库人数不是原文的约 19,573。",
        "- 规模扫描上限受本队列 MIMIC 训练人数限制，不是原文 1k–55k。",
        "- equal-n 受 Amsterdam 训练人数限制，达不到原文每库约 3,000。",
        "- 主四臂仍把 eICU/HiRID 作外验；四库单训/equal-n 使用另写的可训练划分。",
        "- 时序长度按原文 max_los×24（240 h）封顶，防止异常超长 stay 破坏 batch pad（不改 batch_size=32）。",
        "",
        "## 主结果摘要（外验点估计，hourly metrics）",
        "",
        f"- MIMIC 单源：eICU AUROC {b.get('eicu',{}).get('auc')}, HiRID {b.get('hirid',{}).get('auc')}",
        f"- 合并：eICU AUROC {d.get('eicu',{}).get('auc')}, HiRID {d.get('hirid',{}).get('auc')}",
        f"- 规模扫描点数：{len(size_tab)}",
        "",
    ]
    (out / "与原文的差别.md").write_text("\n".join(lines), encoding="utf-8")
    info = out / "Figures" / "image_information"
    info.mkdir(parents=True, exist_ok=True)
    n_ams = store.get("Amsterdam only", {}).get("n_train")
    n_mim = store.get("MIMIC-IV only", {}).get("n_train")
    n_tr = store.get("Transfer", {}).get("n_train")
    n_pool = store.get("Pooling", {}).get("n_train")
    (info / "Figure 1. Study pipeline.md").write_text(
        "# Figure 1. Study pipeline\n\n"
        "## 图面说明\n\n"
        f"A 为七步研究流程（{COHORT_TITLE} 纳排 → 四库 → 预处理 → 划分 → TPC → 内外验 → 小时级输出）。\n"
        "B 为四种训练策略：① Amsterdam 单训；② MIMIC 单训；③ Transfer（MIMIC→Amsterdam）；"
        "④ Pooling。圆角色块标识数据库；策略 3 有预训练→微调箭头。\n\n"
        "图上标注：\n"
        f"- Amsterdam alone N={_fmt_n(n_ams)}\n"
        f"- MIMIC-IV alone N={_fmt_n(n_mim)}\n"
        f"- Transfer N={_fmt_n(n_tr)}\n"
        f"- Pooling N={_fmt_n(n_pool)}\n\n"
        "## 分析上下文\n\n"
        "暴露为多库融合训练策略；结局为 ICU 死亡与存活者剩余住院时间；"
        "主分析外验库为 eICU 与 HiRID。\n",
        encoding="utf-8",
    )
    bits = []
    for _, r in size_tab.iterrows():
        bits.append(
            f"n={int(r['n_train'])}: AUROC {r['auc']:.3f}, MAPE {r['mape']:.1f}, Mcomp {r['Mcomposite']:.3f}"
        )
    (info / "Figure 2. Training size.md").write_text(
        "# Figure 2. Training size\n\n"
        "## 图面说明\n\n"
        "三轴布局：左轴灰色 Composite metric；"
        "右内轴蓝色 Remaining length of stay (MAPE)；右外轴橙色 Mortality (AUROC)。"
        "散点均为 ×，无连线、无插值。图内标注 Composite / RLoS / Mortality。\n\n"
        "图上标注：" + "；".join(bits) + "\n\n"
        "## 分析上下文\n\n"
        "TPC；MIMIC-IV 训练人数扫描；外验为 eICU 与 HiRID 均值；"
        "Composite（Mcomposite）以最大训练规模为参照（=1）。\n",
        encoding="utf-8",
    )


def _purge_non_manuscript_tables(tables_dir: Path):
    """Keep only Allyn main/supplement table xlsx; drop CSV twins and extras."""
    keep = {
        "Table 1. Cohort characteristics.xlsx",
        "Table 2. Internal and external.xlsx",
        "Table 3. Four training strategies.xlsx",
        "Table 4. Literature comparison.xlsx",
        # Allyn MOESM1 layout (physio clip + post-norm outliers); not the old q5/q95-only Scaling sheet
        "Table S1. Physio clip and outliers.xlsx",
        "Table S2. Model architectures.xlsx",
    }
    if not tables_dir.exists():
        return
    for p in tables_dir.iterdir():
        if not p.is_file():
            continue
        if p.name not in keep:
            p.unlink(missing_ok=True)


def main():
    out = PUB
    tables = out / "Tables"
    internal = out / "_internal"
    tables.mkdir(parents=True, exist_ok=True)
    internal.mkdir(parents=True, exist_ok=True)

    store = collect_main()
    ci_path = EXTRA / "ci_main_four_arms" / "Table_CI_DeLong_bootstrap10k.csv"
    ci = pd.read_csv(ci_path) if ci_path.exists() else None
    print("[finalize] metrics store ready; writing Table2/3/S1/S2 + figures first", flush=True)

    # Metrics / figures first (fast); Table 1 last (slow TS scan on large cohorts).
    t2 = table2_manuscript(EXTRA)
    if len(t2):
        _save_table(
            t2,
            tables / "Table 2. Internal and external",
            title="Table 2. Comparison of the TPC model's internal and external validation when training on subsets of the BlendedICU dataset",
            footnote="TPC trained on one database (100% trainval). "
            "Internal = same-database test stays; External = pooled stays from the other three databases (single CI). "
            "AUROC 95% CI: DeLong (stay-level). MAPE/AUPRC 95% CI: patient-level bootstrap 10,000 (percentile). "
            "AUPRC cells include class-prevalence Baseline. "
            "Variation = (external − internal) / internal × 100%.",
        )
    t3 = table3_wide_matrix(store, ci)
    _save_table(
        t3,
        tables / "Table 3. Four training strategies",
        title="Table 3. Model performance on specialization and generalization in four separate training methods",
        footnote="AUROC 95% CI: DeLong (stay-level). MAPE 95% CI: patient-level bootstrap 10,000. "
        "Mcomposite = 0.5×[(MAPE/MAPE₀)+( (1−AUROC)/(1−AUROC₀) )] with Amsterdam-alone on Amsterdam as baseline; point estimate. "
        "¹Transfer learning: pretrain on MIMIC-IV then fine-tune on AmsterdamUMC; only Amsterdam specialization is reported. "
        "²Data pooling: AmsterdamUMC + MIMIC-IV. "
        "Generalization = mean of eICU and HiRID (held out from training). "
        "Dashes: strategy not applicable or evaluation database absent from that run's test predictions.",
    )

    q = list((MAIN_OUT / "liver_expD_pooled_mimic_amsterdam").rglob("train_q5q95.json"))
    if q:
        payload = json.loads(q[0].read_text())
        clip = payload.get("clip", [-4, 4])
        if isinstance(clip, (list, tuple)) and len(clip) == 2:
            clip_s = f"{clip[0]} to {clip[1]}"
        else:
            clip_s = _xlsx_cell_value(clip) if clip is not None else "−4 to 4"
        rows = []
        for block, prefix in (("q5", "Time series"), ("flat_q5", "Static")):
            for name, lo in payload.get(block, {}).items():
                hi_key = "q95" if block == "q5" else "flat_q95"
                rows.append(
                    {
                        "Variable": _disp(name),
                        "Block": prefix,
                        "Train q5": lo,
                        "Train q95": payload.get(hi_key, {}).get(name),
                        "Clip after scale": clip_s,
                        "Fit sample": payload.get("n_sample"),
                    }
                )
        # q5/q95 sheet is audit-only; manuscript Table S1 is Allyn MOESM1 physio layout
        # (rebuild_table_s1_allyn.py). Do not write "Table S1. Scaling.xlsx" into Tables/.
        pd.DataFrame(rows).to_csv(internal / "Table_S1_train_q5q95_scaling.csv", index=False)
        s1_script = Path(__file__).resolve().parent / "rebuild_table_s1_allyn.py"
        blended = BLENDED_ROOT
        drop_ts = os.environ.get("DBPOOL_DROP_TS", "").strip()
        if s1_script.exists() and blended.exists() and (blended / "preprocessed_labels.parquet").exists():
            s1_out = tables / "Table S1. Physio clip and outliers.xlsx"
            cmd = [
                sys.executable,
                str(s1_script),
                "--blended",
                str(blended),
                "--q5q95",
                str(q[0]),
                "--out",
                str(s1_out),
                "--cohort-label",
                COHORT_TITLE,
            ]
            if drop_ts:
                cmd.extend(["--drop", drop_ts])
            print("[finalize] building Table S1 …", flush=True)
            try:
                subprocess.run(cmd, check=True)
            except Exception as e:
                print(f"[finalize] WARN Table S1 rebuild failed: {e}", flush=True)
        else:
            print(
                "[finalize] skip Table S1 (missing script/blended); "
                "run rebuild_table_s1_allyn.py manually",
                flush=True,
            )

    s2_script = Path(__file__).resolve().parent / "rebuild_table_s2_moesm2.py"
    s2_out = tables / "Table S2. Model architectures.xlsx"
    if s2_script.exists() and (EXTRA / "liver_model_benchmark_equaln").exists():
        print("[finalize] building Table S2 (equal-n + CI) …", flush=True)
        try:
            subprocess.run(
                [
                    sys.executable,
                    str(s2_script),
                    "--extra",
                    str(EXTRA),
                    "--out",
                    str(s2_out),
                    "--cohort-label",
                    COHORT_TITLE,
                ],
                check=True,
            )
        except Exception as e:
            print(f"[finalize] WARN Table S2 rebuild failed: {e}; fallback", flush=True)
            s2 = table_s2_wide(EXTRA)
            if len(s2):
                ntr = s2.attrs.get("n_train")
                _save_table(
                    s2,
                    tables / "Table S2. Model architectures",
                    title="Table S2. Performance comparison of the LSTM, Transformer, and TPC architectures"
                    + (f" when training on {_fmt_n(ntr)} patients from the BlendedICU dataset" if ntr else ""),
                    footnote="Equal-n training across four databases; validation reported separately by source database. "
                    "AUROC 95% CI: DeLong (stay-level); MAPE 95% CI: patient-level bootstrap 10,000.",
                )
    else:
        s2 = table_s2_wide(EXTRA)
        if len(s2):
            ntr = s2.attrs.get("n_train")
            _save_table(
                s2,
                tables / "Table S2. Model architectures",
                title="Table S2. Performance comparison of the LSTM, Transformer, and TPC architectures"
                + (f" when training on {_fmt_n(ntr)} patients from the BlendedICU dataset" if ntr else ""),
                footnote="Equal-n training across four databases; validation reported separately by source database. "
                "AUROC 95% CI: DeLong (stay-level); MAPE 95% CI: patient-level bootstrap 10,000.",
            )

    # Non-manuscript diagnostics → _internal only (not in Tables/)
    if ci is not None:
        ci.to_csv(internal / "Table_CI_DeLong_bootstrap10k.csv", index=False)
    pw = EXTRA / "ci_main_four_arms" / "Table_DeLong_Pooling_vs_MIMIC.csv"
    if pw.exists():
        pd.read_csv(pw).to_csv(internal / "Table_DeLong_Pooling_vs_MIMIC.csv", index=False)
    s2e = table_s2_equaln_long(EXTRA)
    if len(s2e):
        s2e.to_csv(internal / "equaln_model_architectures.csv", index=False)

    make_fig1(out, store)
    size_tab = fig2_training_size(EXTRA, out)
    if len(size_tab):
        size_tab.to_csv(internal / "Figure_2_data.csv", index=False)
    write_notes(out, store, size_tab if len(size_tab) else pd.DataFrame())
    print("[finalize] metrics pack written; starting Table 1", flush=True)
    (out / "METRICS_PACK_READY.time").write_text(
        pd.Timestamp.utcnow().isoformat() + "Z\n", encoding="utf-8"
    )

    _save_table(
        table1_wide(),
        tables / "Table 1. Cohort characteristics",
        title="Table 1. Characteristics of ICU patient stays included in the study, according to the original database",
        footnote=TABLE1_FOOTNOTE,
    )
    _purge_non_manuscript_tables(tables)
    (out / "PUBLISH_READY.time").write_text(
        pd.Timestamp.utcnow().isoformat() + "Z\n", encoding="utf-8"
    )
    print("wrote", out)
    print("tables:", sorted(p.name for p in tables.glob("*.xlsx")))

    # Engine-level delivery: Methods + software versions + figure formats + whitelist prune.
    # summary_results keeps only Figures/ Tables/ Methods_*.md|txt / *中期*.pdf
    _finalize_delivery_root(out)


def _finalize_delivery_root(pub: Path) -> None:
    """Call run/pub/finalize_delivery_root.R --study-type dbpool (best-effort)."""
    engine = Path(__file__).resolve().parents[3]
    if not (engine / "R").exists():
        engine = Path("/mnt/e/01block/01Block-new-Final")
    cli = engine / "run" / "pub" / "finalize_delivery_root.R"
    if not cli.exists():
        print(f"[finalize] WARN missing {cli}; skip delivery finalize", flush=True)
        return
    env = os.environ.copy()
    env["MEDICAL_BLOCKS_ROOT"] = str(engine)
    env.setdefault("DBPOOL_COHORT", COHORT_TITLE)
    env.setdefault(
        "DBPOOL_DROP_FEATURES",
        os.environ.get("DBPOOL_DROP_TS", "ALT and AST").replace(",", " and ").replace("_", " "),
    )
    cmd = [
        "Rscript",
        str(cli),
        "--dir",
        str(pub),
        "--study-type",
        "dbpool",
        "--outcome",
        "ICU mortality and remaining length of stay",
        "--exposure",
        "Multi-database pooling / transfer learning (TPC)",
        "--databases",
        "AmsterdamUMC,MIMIC-IV,eICU,HiRID",
    ]
    print("[finalize] delivery root finalize …", flush=True)
    try:
        subprocess.run(cmd, check=False, env=env)
    except Exception as e:
        print(f"[finalize] WARN delivery finalize failed: {e}", flush=True)
    # Structure QC stub (Agent still runs Nature Layer D)
    qc = engine / "run" / "pub" / "run_pub_qc_after_project.R"
    if qc.exists():
        try:
            subprocess.run(
                ["Rscript", str(qc), "--project", str(pub)],
                check=False,
                env=env,
            )
        except Exception as e:
            print(f"[finalize] WARN pub QC CLI failed: {e}", flush=True)


if __name__ == "__main__":
    main()
