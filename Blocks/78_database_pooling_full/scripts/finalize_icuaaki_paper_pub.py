#!/usr/bin/env python3
"""Finalize ICUAKI 4DB Allyn pack into summary_results (cirrhosis layout + extras).

Base (aligned with 50_Cirrhosis/summary_results):
  Table 1–4, Table S1–S2, Figure 1–2, Methods_*

Extras (appended after base numbering):
  Table S3  DeLong / bootstrap CI + Pooling vs MIMIC-IV DeLong p
  Table S4  Stronger baseline (Age+Sex logistic) vs TPC B/D
  Table S5  Clinical risk strata / deployment thresholds
  Figure 3   Calibration (B vs D on eICU / HiRID)
  Figure 4   Decision curves (B vs D)
  Figure 5   Risk-strata mortality

Env:
  ICUAKI_ROOT, ICUAKI_PUB_OUT, ICUAKI_N_BOOT (default 10000)
"""
from __future__ import annotations

import importlib.util
import json
import os
import re
import subprocess
import sys
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
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    average_precision_score,
    brier_score_loss,
    roc_auc_score,
    roc_curve,
)

ROOT = Path(
    os.environ.get(
        "ICUAKI_ROOT",
        "/mnt/sda/BlendedICU/data/icuaaki_4db_20261106",
    )
)
MAIN_OUT = Path(
    os.environ.get("ICUAKI_MAIN_OUT", str(ROOT / "Output_database_pooling"))
)
EXTRA = Path(os.environ.get("ICUAKI_EXTRA_OUT", str(ROOT / "Output_paper_extras")))
PUB = Path(
    os.environ.get(
        "ICUAKI_PUB_OUT",
        str(ROOT / "summary_results"),
    )
)
BLENDED = ROOT / os.environ.get(
    "LIVER_BLENDED_SUBDIR",
    os.environ.get("ICUAKI_BLENDED_SUBDIR", "blendedlos_icuaaki"),
).strip()
N_BOOT = int(os.environ.get("ICUAKI_N_BOOT", "10000"))
ENGINE_SCRIPTS = Path(__file__).resolve().parent

ARM = {
    "Amsterdam only": ("liver_expA_amsterdam_solo", "amsterdam_100/"),
    "MIMIC-IV only": ("liver_expB_mimic_solo", "mimic4_100/"),
    "Transfer": ("liver_expC_mimic2amsterdam_transfer", "amsterdam_100_retrain"),
    "Pooling": ("liver_expD_pooled_mimic_amsterdam", "amsterdam_mimic4_100/"),
}
DB_LAB = {
    "amsterdam": "AmsterdamUMC",
    "mimic4": "MIMIC-IV",
    "eicu": "eICU",
    "hirid": "HiRID",
}
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

plt.rcParams.update(
    {
        "font.family": "serif",
        "font.serif": [
            "Times New Roman",
            "Times",
            "Nimbus Roman",
            "Liberation Serif",
            "DejaVu Serif",
        ],
        "font.size": 9,
        "axes.labelsize": 10,
        "axes.titlesize": 11,
        "axes.linewidth": 0.8,
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


def _fmt_p(p) -> str:
    if p is None or (isinstance(p, float) and not np.isfinite(p)):
        return "–"
    p = float(p)
    if p < 0.001:
        return "<0.001"
    if p > 0.999:
        return ">0.999"
    return f"{p:.3f}"


def _xlsx_cell_value(val):
    if val is None or (isinstance(val, float) and not np.isfinite(val)):
        return "–"
    if isinstance(val, (np.floating,)):
        return float(val)
    if isinstance(val, (np.integer,)):
        return int(val)
    return val


def _save_table(df: pd.DataFrame, path: Path, *, title: str, footnote: str | None = None):
    path.parent.mkdir(parents=True, exist_ok=True)
    out = df.copy()
    out.columns = [_disp(c) for c in out.columns]
    for c in out.columns:
        if out[c].dtype == object:
            out[c] = out[c].map(
                lambda v: _disp(v) if isinstance(v, str) else _xlsx_cell_value(v)
            )
    xlsx_p = Path(str(path) + ".xlsx")
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
        r0 = 2
    for j, col in enumerate(out.columns, 1):
        cell = ws.cell(r0, j, col)
        cell.font = font_h
        cell.alignment = align_c
        cell.border = Border(top=thick, bottom=thin)
    n = len(out)
    for i, row in enumerate(out.itertuples(index=False), r0 + 1):
        last = i == r0 + n
        vals = [_xlsx_cell_value(v) for v in row]
        is_section = len(vals) >= 2 and any(str(vals[0]).strip()) and all(
            (v is None or str(v).strip() in ("", "–", "-")) for v in vals[1:]
        )
        for j, val in enumerate(vals, 1):
            cell = ws.cell(i, j, val)
            cell.font = (
                Font(name="Times New Roman", bold=True, size=12) if is_section else font_b
            )
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
        ws.column_dimensions[get_column_letter(j)].width = min(40, max(14, len(header) + 2))
    wb.save(xlsx_p)


def _png_save_dpi(dpi: int = 600):
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
                with Image.open(target) as im:
                    rgba = im.convert("RGBA")
                    rgba.save(target, format="PNG", dpi=_png_save_dpi(600))
    plt.close(fig)


def _load_ci_mod():
    p = ENGINE_SCRIPTS / "eval_liver_paper_ci.py"
    spec = importlib.util.spec_from_file_location("eval_liver_paper_ci", p)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


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
            out.setdefault(db, {})["auc"] = (
                float(r["auc"]) if pd.notna(r.get("auc")) else float("nan")
            )
        if "los" in task:
            out.setdefault(db, {})["mape"] = (
                float(r["mape"]) if pd.notna(r.get("mape")) else float("nan")
            )
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


def ensure_ci(ci_mod) -> tuple[pd.DataFrame, pd.DataFrame]:
    out = EXTRA / "ci_main_four_arms"
    out.mkdir(parents=True, exist_ok=True)
    ci_csv = out / "Table_CI_DeLong_bootstrap10k.csv"
    pw_csv = out / "Table_DeLong_Pooling_vs_MIMIC.csv"
    if ci_csv.exists() and pw_csv.exists():
        print("[ci] reuse", ci_csv, flush=True)
        return pd.read_csv(ci_csv), pd.read_csv(pw_csv)
    units = ",".join(u for u, _ in ARM.values())
    cmd = [
        sys.executable,
        str(ENGINE_SCRIPTS / "eval_liver_paper_ci.py"),
        "--root",
        str(MAIN_OUT),
        "--units",
        units,
        "--dbs",
        "amsterdam,mimic4,eicu,hirid",
        "--n-boot",
        str(N_BOOT),
        "--out",
        str(out),
    ]
    print("[ci] running", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)
    return pd.read_csv(ci_csv), pd.read_csv(pw_csv) if pw_csv.exists() else pd.DataFrame()


def _ci_lookup(ci: pd.DataFrame, unit: str, db: str) -> dict:
    hit = ci[(ci["unit"] == unit) & (ci["eval_on"] == db)]
    if hit.empty:
        return {}
    return hit.iloc[0].to_dict()


def table1_labels() -> pd.DataFrame:
    """Fast Table 1 from labels (demographics + mortality + LoS); no TS scan."""
    lab = pd.read_parquet(BLENDED / "preprocessed_labels.parquet")
    rows = []
    metrics = [
        ("N stays", "n"),
        ("Age, years", "age"),
        ("Male, n (%)", "male"),
        ("ICU mortality, n (%)", "mort"),
        ("ICU length of stay, days", "los"),
    ]
    for label, key in metrics:
        row = {"Characteristic": label}
        for db in DB_ORDER:
            g = lab[lab["source_dataset"] == db]
            n = len(g)
            if key == "n":
                row[DB_LAB[db]] = _fmt_n(n)
            elif key == "age":
                x = pd.to_numeric(g["age"], errors="coerce").dropna()
                row[DB_LAB[db]] = (
                    f"{x.mean():.1f} [{x.std():.1f}]" if len(x) else "–"
                )
            elif key == "male":
                sex = pd.to_numeric(g["sex"], errors="coerce")
                # BlendedICU: often 1=male
                n_m = int((sex == 1).sum())
                row[DB_LAB[db]] = f"{n_m:,} ({100.0 * n_m / n:.1f}%)" if n else "–"
            elif key == "mort":
                y = pd.to_numeric(g["mortality"], errors="coerce").fillna(0).astype(int)
                n_d = int(y.sum())
                row[DB_LAB[db]] = f"{n_d:,} ({100.0 * n_d / n:.1f}%)" if n else "–"
            else:
                x = pd.to_numeric(g["lengthofstay"], errors="coerce").dropna()
                row[DB_LAB[db]] = (
                    f"{x.mean():.1f} [{x.std():.1f}]" if len(x) else "–"
                )
        rows.append(row)
    # unit type top categories
    rows.append({"Characteristic": "ICU unit type", **{DB_LAB[d]: "" for d in DB_ORDER}})
    units = sorted(set(lab["unit_type"].dropna().astype(str)))[:8]
    for u in units:
        row = {"Characteristic": f"   {u}"}
        for db in DB_ORDER:
            g = lab[lab["source_dataset"] == db]
            n = len(g)
            k = int((g["unit_type"].astype(str) == u).sum())
            row[DB_LAB[db]] = f"{k:,} ({100.0 * k / n:.1f}%)" if n else "–"
        rows.append(row)
    return pd.DataFrame(rows)


def table2_from_ab(ci_mod, ci: pd.DataFrame) -> pd.DataFrame:
    """Internal vs external for Amsterdam-alone and MIMIC-IV-alone (no 4-solo benchmark)."""
    col_task = "Task and training dataset"
    col_int = "Internal validation"
    col_ext = "External validation"
    col_var = "Variation between internal and external validation"
    rows = []
    rows.append({col_task: "Mortality prediction, AUROC [CI 95%]", col_int: "", col_ext: "", col_var: ""})
    for arm_name, train_db in (("Amsterdam only", "amsterdam"), ("MIMIC-IV only", "mimic4")):
        unit, prefer = ARM[arm_name]
        mort_p = ci_mod._pick_run(MAIN_OUT / unit, prefer)
        if mort_p is None:
            continue
        mort = pd.read_csv(mort_p)
        stay, _ = ci_mod._stay_frame(mort, None)
        st_int = stay[stay["eval_on"] == train_db]
        st_ext = stay[stay["eval_on"].isin(["eicu", "hirid"])]
        auc_i, lo_i, hi_i = ci_mod.delong_auc_ci(
            st_int["y_mort"].to_numpy(), st_int["pred_mort"].to_numpy()
        )
        auc_e, lo_e, hi_e = ci_mod.delong_auc_ci(
            st_ext["y_mort"].to_numpy(), st_ext["pred_mort"].to_numpy()
        )
        rel = (auc_e - auc_i) / auc_i * 100 if auc_i and np.isfinite(auc_i) else float("nan")
        rows.append(
            {
                col_task: DB_LAB[train_db],
                col_int: _fmt_ci(auc_i, lo_i, hi_i, 3),
                col_ext: _fmt_ci(auc_e, lo_e, hi_e, 3),
                col_var: f"{rel:+.1f}%" if np.isfinite(rel) else "–",
            }
        )
    # also AUPRC
    rows.append({col_task: "Mortality prediction, AUPRC [CI 95%]", col_int: "", col_ext: "", col_var: ""})
    for arm_name, train_db in (("Amsterdam only", "amsterdam"), ("MIMIC-IV only", "mimic4")):
        unit, prefer = ARM[arm_name]
        mort_p = ci_mod._pick_run(MAIN_OUT / unit, prefer)
        if mort_p is None:
            continue
        mort = pd.read_csv(mort_p)
        stay, _ = ci_mod._stay_frame(mort, None)
        st_int = stay[stay["eval_on"] == train_db]
        st_ext = stay[stay["eval_on"].isin(["eicu", "hirid"])]
        a_i = float(average_precision_score(st_int["y_mort"], st_int["pred_mort"]))
        a_e = float(average_precision_score(st_ext["y_mort"], st_ext["pred_mort"]))
        lo_i, hi_i = ci_mod._boot_ci_auprc(st_int, n_boot=min(N_BOOT, 2000), seed=42)
        lo_e, hi_e = ci_mod._boot_ci_auprc(st_ext, n_boot=min(N_BOOT, 2000), seed=42)
        rel = (a_e - a_i) / a_i * 100 if a_i else float("nan")
        rows.append(
            {
                col_task: DB_LAB[train_db],
                col_int: _fmt_ci(a_i, lo_i, hi_i, 3),
                col_ext: _fmt_ci(a_e, lo_e, hi_e, 3),
                col_var: f"{rel:+.1f}%" if np.isfinite(rel) else "–",
            }
        )
    return pd.DataFrame(rows, columns=[col_task, col_int, col_ext, col_var])


def table3_wide(store: dict, ci: pd.DataFrame) -> pd.DataFrame:
    arms = ["Amsterdam only", "MIMIC-IV only", "Transfer", "Pooling"]
    col0 = "Evaluation set and metric [CI 95%]"

    def col_header(arm):
        n = store.get(arm, {}).get("n_train")
        ns = _fmt_n(n)
        if arm == "Amsterdam only":
            return f"Training on AmsterdamUMC\nN = {ns}"
        if arm == "MIMIC-IV only":
            return f"Training on MIMIC-IV\nN = {ns}"
        if arm == "Transfer":
            return f"Training by Transfer Learning¹\nN = {ns}"
        return f"Training by Data Pooling²\nN = {ns}"

    col_map = {a: col_header(a) for a in arms}
    base_h = _ci_lookup(ci, ARM["Amsterdam only"][0], "amsterdam")
    base_auc = float(base_h.get("auroc_stay", float("nan"))) if base_h else float("nan")
    base_mape = float(base_h.get("mape_stay_mean", float("nan"))) if base_h else float("nan")
    if not np.isfinite(base_auc):
        base_auc = store.get("Amsterdam only", {}).get("amsterdam", {}).get("auc", float("nan"))
        base_mape = store.get("Amsterdam only", {}).get("amsterdam", {}).get("mape", float("nan"))

    def met(unit, db):
        h = _ci_lookup(ci, unit, db)
        out = {
            "auc": float(h.get("auroc_stay", np.nan)) if h else np.nan,
            "auc_lo": float(h.get("auroc_stay_lo_delong", np.nan)) if h else np.nan,
            "auc_hi": float(h.get("auroc_stay_hi_delong", np.nan)) if h else np.nan,
            "mape": float(h.get("mape_stay_mean", np.nan)) if h else np.nan,
            "mape_lo": float(h.get("mape_lo_boot10k", np.nan)) if h else np.nan,
            "mape_hi": float(h.get("mape_hi_boot10k", np.nan)) if h else np.nan,
        }
        out["mcomp"] = mcomposite(out["auc"], out["mape"], base_auc, base_mape)
        return out

    def gen(unit):
        parts = [met(unit, db) for db in ("eicu", "hirid")]
        out = {k: float("nan") for k in ("auc", "auc_lo", "auc_hi", "mape", "mape_lo", "mape_hi", "mcomp")}
        for key in ("auc", "auc_lo", "auc_hi", "mape", "mape_lo", "mape_hi"):
            vals = [p[key] for p in parts if np.isfinite(p[key])]
            if vals:
                out[key] = float(np.mean(vals))
        out["mcomp"] = mcomposite(out["auc"], out["mape"], base_auc, base_mape)
        return out

    rows = []
    for sect, key, is_gen in (
        ("Specialization on AmsterdamUMC", "amsterdam", False),
        ("Specialization on MIMIC-IV", "mimic4", False),
        ("Generalization", "gen", True),
    ):
        rows.append({col0: sect, **{col_map[a]: "" for a in arms}})
        for mlab, mkey, digits in (
            ("Mortality, AUROC", "auc", 3),
            ("RLoS, MAPE", "mape", 2),
            ("Mcomposite", "mcomp", 2),
        ):
            row = {col0: mlab}
            for arm in arms:
                if arm == "Transfer" and key != "amsterdam":
                    row[col_map[arm]] = "–"
                    continue
                unit = ARM[arm][0]
                m = gen(unit) if is_gen else met(unit, key)
                if mkey == "mcomp":
                    row[col_map[arm]] = _fmt_est(m["mcomp"], digits) if np.isfinite(m["mcomp"]) else "–"
                elif mkey == "auc":
                    row[col_map[arm]] = (
                        _fmt_ci(m["auc"], m["auc_lo"], m["auc_hi"], digits)
                        if np.isfinite(m["auc"])
                        else "–"
                    )
                else:
                    row[col_map[arm]] = (
                        _fmt_ci(m["mape"], m["mape_lo"], m["mape_hi"], digits)
                        if np.isfinite(m["mape"])
                        else "–"
                    )
            rows.append(row)
    return pd.DataFrame(rows, columns=[col0] + [col_map[a] for a in arms])


def table4_literature(store: dict, ci: pd.DataFrame) -> pd.DataFrame:
    """Own study vs published multi-DB ICU mortality DL baselines (context only)."""
    h_b_e = _ci_lookup(ci, ARM["MIMIC-IV only"][0], "eicu")
    h_d_e = _ci_lookup(ci, ARM["Pooling"][0], "eicu")
    h_b_h = _ci_lookup(ci, ARM["MIMIC-IV only"][0], "hirid")
    h_d_h = _ci_lookup(ci, ARM["Pooling"][0], "hirid")
    rows = [
        {
            "Study / model": "Present study — TPC pooling (AmsterdamUMC+MIMIC-IV)",
            "Cohort": "KDIGO ICU-AKI (DN=1); Cr/UO dropped from features",
            "External AUROC eICU": _fmt_ci(
                h_d_e.get("auroc_stay"),
                h_d_e.get("auroc_stay_lo_delong"),
                h_d_e.get("auroc_stay_hi_delong"),
                3,
            )
            if h_d_e
            else "–",
            "External AUROC HiRID": _fmt_ci(
                h_d_h.get("auroc_stay"),
                h_d_h.get("auroc_stay_lo_delong"),
                h_d_h.get("auroc_stay_hi_delong"),
                3,
            )
            if h_d_h
            else "–",
            "Notes": "Stay-level DeLong CI; multitask RLoS+mortality",
        },
        {
            "Study / model": "Present study — TPC MIMIC-IV alone",
            "Cohort": "Same ICU-AKI extract",
            "External AUROC eICU": _fmt_ci(
                h_b_e.get("auroc_stay"),
                h_b_e.get("auroc_stay_lo_delong"),
                h_b_e.get("auroc_stay_hi_delong"),
                3,
            )
            if h_b_e
            else "–",
            "External AUROC HiRID": _fmt_ci(
                h_b_h.get("auroc_stay"),
                h_b_h.get("auroc_stay_lo_delong"),
                h_b_h.get("auroc_stay_hi_delong"),
                3,
            )
            if h_b_h
            else "–",
            "Notes": "Primary single-database comparator",
        },
        {
            "Study / model": "Allyn et al. Crit Care 2024/2026 (TPC BlendedICU)",
            "Cohort": "Heterogeneous ICU (not AKI-restricted)",
            "External AUROC eICU": "see source paper",
            "External AUROC HiRID": "see source paper",
            "Notes": "Architecture / training protocol template for this study",
        },
    ]
    return pd.DataFrame(rows)


def table_s1_scaling() -> pd.DataFrame:
    q = list((MAIN_OUT / "liver_expD_pooled_mimic_amsterdam").rglob("train_q5q95.json"))
    if not q:
        return pd.DataFrame()
    payload = json.loads(q[0].read_text())
    clip = payload.get("clip", [-4, 4])
    clip_s = f"{clip[0]} to {clip[1]}" if isinstance(clip, (list, tuple)) else str(clip)
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
    return pd.DataFrame(rows)


def table_s2_architecture() -> pd.DataFrame:
    """No equal-n LSTM/Transformer run for ICUAKI — document TPC protocol instead."""
    return pd.DataFrame(
        [
            {
                "Item": "Architecture",
                "Specification": "Temporal Pointwise Convolution (TPC), multitask",
            },
            {
                "Item": "Tasks",
                "Specification": "Hourly ICU mortality + remaining ICU LoS (cap 10 days)",
            },
            {
                "Item": "Prediction start",
                "Specification": "From ICU hour 5 (time_before_pred)",
            },
            {
                "Item": "Split",
                "Specification": "Patient-level 70/15/15; seed 974; eICU/HiRID held out from training",
            },
            {
                "Item": "Feature exclusion",
                "Specification": "Creatinine and urine_output dropped (AKI definition leakage)",
            },
            {
                "Item": "Equal-n LSTM/Transformer benchmark",
                "Specification": "Not run in this delivery (TPC-only four-strategy pack)",
            },
        ]
    )


def table_s3_ci(ci: pd.DataFrame, pw: pd.DataFrame) -> pd.DataFrame:
    rows = []
    name_map = {v[0]: k for k, v in ARM.items()}
    for _, r in ci.iterrows():
        rows.append(
            {
                "Training strategy": name_map.get(r["unit"], r["unit"]),
                "Evaluation database": DB_LAB.get(r["eval_on"], r["eval_on"]),
                "N stays": _fmt_n(r.get("n_stays")),
                "AUROC (DeLong 95% CI)": _fmt_ci(
                    r.get("auroc_stay"),
                    r.get("auroc_stay_lo_delong"),
                    r.get("auroc_stay_hi_delong"),
                    3,
                ),
                "AUPRC (bootstrap 95% CI)": _fmt_ci(
                    r.get("auprc_stay"),
                    r.get("auprc_lo_boot10k"),
                    r.get("auprc_hi_boot10k"),
                    3,
                ),
                "MAPE (bootstrap 95% CI)": _fmt_ci(
                    r.get("mape_stay_mean"),
                    r.get("mape_lo_boot10k"),
                    r.get("mape_hi_boot10k"),
                    2,
                ),
            }
        )
    if len(pw):
        rows.append(
            {
                "Training strategy": "Statistical comparison",
                "Evaluation database": "",
                "N stays": "",
                "AUROC (DeLong 95% CI)": "",
                "AUPRC (bootstrap 95% CI)": "",
                "MAPE (bootstrap 95% CI)": "",
            }
        )
        for _, r in pw.iterrows():
            rows.append(
                {
                    "Training strategy": "Pooling vs MIMIC-IV alone",
                    "Evaluation database": DB_LAB.get(r["eval_on"], r["eval_on"]),
                    "N stays": _fmt_n(r.get("n_stays")),
                    "AUROC (DeLong 95% CI)": (
                        f"Pooling {_fmt_est(r.get('auroc_pooling'), 3)} vs "
                        f"MIMIC {_fmt_est(r.get('auroc_mimic_solo'), 3)}; "
                        f"DeLong P = {_fmt_p(r.get('delong_pvalue'))}"
                    ),
                    "AUPRC (bootstrap 95% CI)": "–",
                    "MAPE (bootstrap 95% CI)": "–",
                }
            )
    return pd.DataFrame(rows)


def _stay_preds(ci_mod, arm_key: str, db: str) -> pd.DataFrame:
    unit, prefer = ARM[arm_key]
    mort_p = ci_mod._pick_run(MAIN_OUT / unit, prefer)
    if mort_p is None:
        return pd.DataFrame()
    stay, _ = ci_mod._stay_frame(pd.read_csv(mort_p), None)
    return stay[stay["eval_on"] == db].copy()


def _labels_by_stay() -> pd.DataFrame:
    lab = pd.read_parquet(BLENDED / "preprocessed_labels.parquet")
    # uniquepid is typically "<db>-<id>" matching prediction patientids
    lab = lab.copy()
    lab["stay"] = lab["uniquepid"].astype(str)
    return lab


def table_s4_baseline(ci_mod) -> pd.DataFrame:
    """Age+Sex logistic fit on MIMIC-IV train stays; compare AUROC on eICU/HiRID vs TPC B/D."""
    lab = _labels_by_stay()
    split = json.loads((BLENDED / "split_summary.json").read_text())
    # Use MIMIC labels with mortality; train = not in external-only DBs and mimic train split if available
    mim = lab[lab["source_dataset"] == "mimic4"].copy()
    mim["age"] = pd.to_numeric(mim["age"], errors="coerce")
    mim["sex"] = pd.to_numeric(mim["sex"], errors="coerce")
    mim["y"] = pd.to_numeric(mim["mortality"], errors="coerce").fillna(0).astype(int)
    mim = mim.dropna(subset=["age", "sex"])
    # Prefer stays appearing in B train via absence from B test preds? Use 70% random of MIMIC as train proxy
    # Better: use labels with lengthofstay and match B train stays from predictions folder train list if present.
    rng = np.random.default_rng(974)
    idx = np.arange(len(mim))
    rng.shuffle(idx)
    n_tr = int(0.7 * len(idx))
    tr = mim.iloc[idx[:n_tr]]
    Xtr = tr[["age", "sex"]].to_numpy()
    ytr = tr["y"].to_numpy()
    clf = LogisticRegression(max_iter=1000)
    clf.fit(Xtr, ytr)

    rows = []
    for db in ("eicu", "hirid"):
        ext = lab[lab["source_dataset"] == db].copy()
        ext["age"] = pd.to_numeric(ext["age"], errors="coerce")
        ext["sex"] = pd.to_numeric(ext["sex"], errors="coerce")
        ext["y"] = pd.to_numeric(ext["mortality"], errors="coerce").fillna(0).astype(int)
        ext = ext.dropna(subset=["age", "sex"])
        p_base = clf.predict_proba(ext[["age", "sex"]].to_numpy())[:, 1]
        auc_base = float(roc_auc_score(ext["y"], p_base))
        for arm in ("MIMIC-IV only", "Pooling"):
            st = _stay_preds(ci_mod, arm, db)
            if st.empty:
                continue
            # align on stay id
            m = st.merge(ext[["stay", "age", "sex"]], on="stay", how="inner")
            if m.empty or m["y_mort"].nunique() < 2:
                continue
            p_b2 = clf.predict_proba(m[["age", "sex"]].to_numpy())[:, 1]
            auc_b2 = float(roc_auc_score(m["y_mort"], p_b2))
            auc_tpc = float(roc_auc_score(m["y_mort"], m["pred_mort"]))
            rows.append(
                {
                    "Evaluation database": DB_LAB[db],
                    "Model": f"Age+Sex logistic (aligned stays)",
                    "N stays": _fmt_n(len(m)),
                    "AUROC": _fmt_est(auc_b2, 3),
                    "Δ vs Age+Sex": "Ref",
                }
            )
            rows.append(
                {
                    "Evaluation database": DB_LAB[db],
                    "Model": f"TPC — {arm}",
                    "N stays": _fmt_n(len(m)),
                    "AUROC": _fmt_est(auc_tpc, 3),
                    "Δ vs Age+Sex": _fmt_est(auc_tpc - auc_b2, 3),
                }
            )
        # also report full-label baseline AUROC
        rows.append(
            {
                "Evaluation database": DB_LAB[db],
                "Model": "Age+Sex logistic (all labelled stays)",
                "N stays": _fmt_n(len(ext)),
                "AUROC": _fmt_est(auc_base, 3),
                "Δ vs Age+Sex": "–",
            }
        )
    return pd.DataFrame(rows)


def table_s5_risk_strata(ci_mod) -> pd.DataFrame:
    rows = []
    for db in ("eicu", "hirid"):
        st = _stay_preds(ci_mod, "Pooling", db)
        if st.empty or st["y_mort"].nunique() < 2:
            continue
        y = st["y_mort"].to_numpy()
        p = st["pred_mort"].to_numpy()
        # tertiles
        qs = np.quantile(p, [1 / 3, 2 / 3])
        bins = np.digitize(p, qs, right=True)
        for b, lab in enumerate(["Low", "Middle", "High"]):
            m = bins == b
            n = int(m.sum())
            ev = int(y[m].sum()) if n else 0
            rows.append(
                {
                    "Evaluation database": DB_LAB[db],
                    "Stratum (Pooling risk tertile)": lab,
                    "N stays": _fmt_n(n),
                    "Deaths, n (%)": f"{ev:,} ({100.0 * ev / n:.1f}%)" if n else "–",
                    "Mean predicted risk": _fmt_est(p[m].mean(), 3) if n else "–",
                }
            )
        # Youden threshold
        fpr, tpr, thr = roc_curve(y, p)
        j = tpr - fpr
        k = int(np.argmax(j))
        t_star = float(thr[k]) if k < len(thr) else 0.5
        pred = (p >= t_star).astype(int)
        tp = int(((pred == 1) & (y == 1)).sum())
        fp = int(((pred == 1) & (y == 0)).sum())
        tn = int(((pred == 0) & (y == 0)).sum())
        fn = int(((pred == 0) & (y == 1)).sum())
        sens = tp / (tp + fn) if (tp + fn) else float("nan")
        spec = tn / (tn + fp) if (tn + fp) else float("nan")
        ppv = tp / (tp + fp) if (tp + fp) else float("nan")
        npv = tn / (tn + fn) if (tn + fn) else float("nan")
        rows.append(
            {
                "Evaluation database": DB_LAB[db],
                "Stratum (Pooling risk tertile)": f"Youden threshold ≥ {t_star:.3f}",
                "N stays": _fmt_n(len(st)),
                "Deaths, n (%)": (
                    f"Sens {_fmt_est(sens, 3)}; Spec {_fmt_est(spec, 3)}; "
                    f"PPV {_fmt_est(ppv, 3)}; NPV {_fmt_est(npv, 3)}"
                ),
                "Mean predicted risk": _fmt_est(p.mean(), 3),
            }
        )
        for t_fix in (0.10, 0.20):
            pred = (p >= t_fix).astype(int)
            tp = int(((pred == 1) & (y == 1)).sum())
            fp = int(((pred == 1) & (y == 0)).sum())
            tn = int(((pred == 0) & (y == 0)).sum())
            fn = int(((pred == 0) & (y == 1)).sum())
            sens = tp / (tp + fn) if (tp + fn) else float("nan")
            spec = tn / (tn + fp) if (tn + fp) else float("nan")
            ppv = tp / (tp + fp) if (tp + fp) else float("nan")
            rows.append(
                {
                    "Evaluation database": DB_LAB[db],
                    "Stratum (Pooling risk tertile)": f"Fixed threshold ≥ {t_fix:.2f}",
                    "N stays": _fmt_n(int(pred.sum())),
                    "Deaths, n (%)": (
                        f"Sens {_fmt_est(sens, 3)}; Spec {_fmt_est(spec, 3)}; "
                        f"PPV {_fmt_est(ppv, 3)}"
                    ),
                    "Mean predicted risk": _fmt_est(p[pred == 1].mean(), 3) if pred.any() else "–",
                }
            )
    return pd.DataFrame(rows)


def make_fig1(out: Path, store: dict):
    fig, axes = plt.subplots(1, 2, figsize=(11.6, 7.0), gridspec_kw={"width_ratios": [1.05, 1.18]})
    ax = axes[0]
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 11.0)
    ax.axis("off")
    ax.text(0.12, 10.55, "A", fontsize=14, fontweight="bold", color=INK)
    ax.text(0.65, 10.55, "Study pipeline", fontsize=12, color=INK)

    def box(ax, x, y, w, h, title, subtitle, face):
        ax.add_patch(
            FancyBboxPatch(
                (x, y),
                w,
                h,
                boxstyle="round,pad=0.012,rounding_size=0.08",
                facecolor=face,
                edgecolor=EDGE,
                linewidth=0.75,
            )
        )
        ax.text(x + w / 2, y + h * 0.62, title, ha="center", va="center", fontsize=8.0, color=INK)
        ax.text(x + w / 2, y + h * 0.28, subtitle, ha="center", va="center", fontsize=6.3, color=MUTED)

    steps = [
        ("1  ICU-AKI cohort (KDIGO DN=1)", "Creatinine / urine_output dropped from features", "#d7e6f5"),
        ("2  Four ICU databases", "AmsterdamUMC, MIMIC-IV, eICU, HiRID (BlendedICU)", "#dceee4"),
        ("3  Time zero t0 = ICU admission", "Predict from hour 5 through ICU discharge", "#efe6c9"),
        ("4  Preprocess + patient split", "Phys clip, MNAR ffill+mask, q5–q95; 70/15/15 seed 974", "#f6dfd4"),
        ("5  TPC multitask model", "Hourly ICU mortality + remaining ICU LoS (RLoS)", "#e8dff5"),
        ("6  Internal then external test", "AUROC / AUPRC / MAPE; four strategies in panel B", "#e6e4f4"),
        ("7  Clinical outputs", "Risk strata, calibration, decision curves (Figs 3–5)", "#f7f3ea"),
    ]
    box_w, box_h, x0, top, gap = 8.75, 0.86, 0.6, 8.25, 0.16
    for i, (title, sub, face) in enumerate(steps):
        y = top - i * (box_h + gap)
        box(ax, x0, y, box_w, box_h, title, sub, face)
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
    ax.text(0.12, 10.55, "B", fontsize=14, fontweight="bold", color=INK)
    ax.text(0.65, 10.55, "Four training strategies", fontsize=12, color=INK)

    def chip(ax, x, y, w, h, text, face):
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
        ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=7.0, color=INK)

    rows = [
        (7.15, "1", "AmsterdamUMC alone", [("AmsterdamUMC", 1.1, 2.2)], store.get("Amsterdam only", {}).get("n_train")),
        (5.20, "2", "MIMIC-IV alone", [("MIMIC-IV", 1.1, 1.75)], store.get("MIMIC-IV only", {}).get("n_train")),
        (
            3.25,
            "3",
            "Transfer: MIMIC-IV → AmsterdamUMC",
            [("MIMIC-IV", 1.1, 1.75), ("AmsterdamUMC", 3.55, 2.2)],
            store.get("Transfer", {}).get("n_train"),
        ),
        (
            1.15,
            "4",
            "Pooling (single training run)",
            [("AmsterdamUMC", 1.1, 2.2), ("MIMIC-IV", 3.5, 1.75)],
            store.get("Pooling", {}).get("n_train"),
        ),
    ]
    for y, num, name, chips, ntr in rows:
        ax.add_patch(plt.Circle((0.45, y + 0.78), 0.28, facecolor=EDGE, edgecolor="none"))
        ax.text(0.45, y + 0.78, num, ha="center", va="center", fontsize=9, color="white", fontweight="bold")
        ax.text(0.95, y + 1.32, name, ha="left", va="center", fontsize=9.0, color=INK)
        for src, cx, cw in chips:
            chip(ax, cx, y + 0.48, cw, 0.42, src, DB_FACE[src])
        if num == "3":
            ax.annotate(
                "",
                xy=(3.48, y + 0.69),
                xytext=(2.95, y + 0.69),
                arrowprops=dict(arrowstyle="-|>", color=EDGE, lw=0.85, mutation_scale=8),
            )
        ax.text(9.75, y + 0.78, f"N = {_fmt_n(ntr)}", ha="right", va="center", fontsize=8.0, color=MUTED)
    fig.subplots_adjust(left=0.03, right=0.99, top=0.97, bottom=0.03, wspace=0.08)
    _write_fig(fig, out, "Figure 1. Study pipeline")


def make_fig2(out: Path, store: dict, ci: pd.DataFrame):
    """Generalization AUROC (eICU / HiRID) by strategy — replaces size-study Fig2."""
    arms = ["Amsterdam only", "MIMIC-IV only", "Transfer", "Pooling"]
    fig, axes = plt.subplots(1, 2, figsize=(10.5, 4.2))
    x = np.arange(len(arms))
    width = 0.35
    for ax, db, title in (
        (axes[0], "eicu", "eICU external AUROC"),
        (axes[1], "hirid", "HiRID external AUROC"),
    ):
        est, lo, hi = [], [], []
        for arm in arms:
            h = _ci_lookup(ci, ARM[arm][0], db)
            if not h and arm == "Transfer":
                # transfer may lack external — use store point if any
                v = store.get(arm, {}).get(db, {}).get("auc", np.nan)
                est.append(v)
                lo.append(v)
                hi.append(v)
                continue
            est.append(float(h.get("auroc_stay", np.nan)) if h else np.nan)
            lo.append(float(h.get("auroc_stay_lo_delong", np.nan)) if h else np.nan)
            hi.append(float(h.get("auroc_stay_hi_delong", np.nan)) if h else np.nan)
        est = np.array(est, dtype=float)
        yerr = np.vstack([est - np.array(lo), np.array(hi) - est])
        yerr = np.where(np.isfinite(yerr), yerr, 0.0)
        ax.bar(x, est, width=0.55, color=["#d7e6f5", "#f6dfd4", "#e8dff5", "#dceee4"], edgecolor=EDGE)
        ax.errorbar(x, est, yerr=yerr, fmt="none", ecolor=EDGE, capsize=3, lw=0.9)
        ax.set_ylim(0.5, 1.0)
        ax.set_xticks(x)
        ax.set_xticklabels(["Ams", "MIMIC", "Transfer", "Pooling"], rotation=0)
        ax.set_ylabel("AUROC")
        ax.set_title(title)
        ax.axhline(0.5, color="#bbbbbb", lw=0.6, ls="--")
    fig.tight_layout()
    _write_fig(fig, out, "Figure 2. External validation AUROC")


def make_fig3_calibration(out: Path, ci_mod):
    fig, axes = plt.subplots(1, 2, figsize=(9.5, 4.3))
    for ax, db in zip(axes, ("eicu", "hirid")):
        for arm, color in (("MIMIC-IV only", "#c47b5b"), ("Pooling", "#3d7a5a")):
            st = _stay_preds(ci_mod, arm, db)
            if st.empty:
                continue
            y = st["y_mort"].to_numpy()
            p = st["pred_mort"].to_numpy()
            # 10 equal-frequency bins
            qs = np.quantile(p, np.linspace(0, 1, 11))
            qs[0], qs[-1] = -np.inf, np.inf
            bins = pd.cut(p, bins=np.unique(qs), include_lowest=True)
            df = pd.DataFrame({"y": y, "p": p, "bin": bins}).dropna()
            g = df.groupby("bin", observed=True).agg(obs=("y", "mean"), pred=("p", "mean"), n=("y", "size"))
            g = g[g["n"] >= 20]
            ax.plot(g["pred"], g["obs"], "o-", color=color, label=arm, markersize=4, lw=1.2)
            brier = brier_score_loss(y, p)
            ax.text(
                0.05,
                0.95 - 0.08 * (0 if arm.startswith("M") else 1),
                f"{arm.split()[0]} Brier={brier:.3f}",
                transform=ax.transAxes,
                fontsize=7.5,
                color=color,
                va="top",
            )
        ax.plot([0, 1], [0, 1], "--", color="#999999", lw=0.8)
        ax.set_xlim(0, 1)
        ax.set_ylim(0, 1)
        ax.set_xlabel("Predicted risk")
        ax.set_ylabel("Observed mortality")
        ax.set_title(DB_LAB[db])
        ax.legend(frameon=False, fontsize=8)
    fig.tight_layout()
    _write_fig(fig, out, "Figure 3. Calibration")


def _net_benefit(y, p, thresholds):
    n = len(y)
    out = []
    prevalence = y.mean()
    for t in thresholds:
        if t <= 0 or t >= 1:
            out.append(np.nan)
            continue
        pred = p >= t
        tp = ((pred == 1) & (y == 1)).sum()
        fp = ((pred == 1) & (y == 0)).sum()
        out.append((tp / n) - (fp / n) * (t / (1 - t)))
    treat_all = [prevalence - (1 - prevalence) * (t / (1 - t)) if 0 < t < 1 else np.nan for t in thresholds]
    return np.array(out), np.array(treat_all)


def make_fig4_dca(out: Path, ci_mod):
    thresholds = np.linspace(0.01, 0.50, 50)
    fig, axes = plt.subplots(1, 2, figsize=(9.5, 4.3))
    for ax, db in zip(axes, ("eicu", "hirid")):
        plotted_all = False
        for arm, color in (("MIMIC-IV only", "#c47b5b"), ("Pooling", "#3d7a5a")):
            st = _stay_preds(ci_mod, arm, db)
            if st.empty:
                continue
            y = st["y_mort"].to_numpy().astype(int)
            p = st["pred_mort"].to_numpy()
            nb, ta = _net_benefit(y, p, thresholds)
            ax.plot(thresholds, nb, color=color, lw=1.4, label=arm)
            if not plotted_all:
                ax.plot(thresholds, ta, "--", color="#888888", lw=0.9, label="Treat all")
                ax.axhline(0, color="#444444", lw=0.8, label="Treat none")
                plotted_all = True
        ax.set_xlabel("Threshold probability")
        ax.set_ylabel("Net benefit")
        ax.set_title(DB_LAB[db])
        ax.set_xlim(0.01, 0.50)
        ax.legend(frameon=False, fontsize=8)
    fig.tight_layout()
    _write_fig(fig, out, "Figure 4. Decision curve analysis")


def make_fig5_risk_strata(out: Path, ci_mod):
    fig, axes = plt.subplots(1, 2, figsize=(9.0, 4.0))
    for ax, db in zip(axes, ("eicu", "hirid")):
        st = _stay_preds(ci_mod, "Pooling", db)
        if st.empty:
            continue
        y = st["y_mort"].to_numpy()
        p = st["pred_mort"].to_numpy()
        qs = np.quantile(p, [1 / 3, 2 / 3])
        bins = np.digitize(p, qs, right=True)
        rates = []
        ns = []
        for b in range(3):
            m = bins == b
            ns.append(int(m.sum()))
            rates.append(float(y[m].mean()) if m.any() else 0.0)
        ax.bar(["Low", "Middle", "High"], rates, color=["#dceee4", "#efe6c9", "#f6dfd4"], edgecolor=EDGE)
        for i, (r, n) in enumerate(zip(rates, ns)):
            ax.text(i, r + 0.01, f"{100*r:.1f}%\nn={n:,}", ha="center", va="bottom", fontsize=8)
        ax.set_ylim(0, max(rates) * 1.35 if rates else 1)
        ax.set_ylabel("Observed mortality")
        ax.set_title(f"{DB_LAB[db]} — Pooling risk tertiles")
    fig.tight_layout()
    _write_fig(fig, out, "Figure 5. Risk strata")


def write_image_information(out: Path, store: dict, ci: pd.DataFrame, pw: pd.DataFrame):
    d = out / "Figures" / "image_information"
    d.mkdir(parents=True, exist_ok=True)
    split = json.loads((BLENDED / "split_summary.json").read_text())
    n_by = {db: int(split[db]["stays"].get("test", 0) + split[db]["stays"].get("train", 0) + split[db]["stays"].get("val", 0)) for db in DB_ORDER}
    figs = {
        "Figure 1. Study pipeline.md": (
            "# Figure 1. Study pipeline\n\n"
            "## 图面说明\n\n"
            "A 面板为 ICU-AKI（KDIGO DN=1）四库池化研究流水线；B 面板为四策略（Amsterdam 单库、MIMIC-IV 单库、迁移、池化）及训练 N。\n\n"
            "## 分析上下文\n\n"
            f"- 暴露/模型：TPC multitask；结局：ICU 死亡 + RLoS\n"
            f"- 样本量（stays）：Amsterdam {_fmt_n(n_by['amsterdam'])}; MIMIC-IV {_fmt_n(n_by['mimic4'])}; "
            f"eICU {_fmt_n(n_by['eicu'])}; HiRID {_fmt_n(n_by['hirid'])}\n"
            "- 数据库：AmsterdamUMC / MIMIC-IV / eICU / HiRID\n"
        ),
        "Figure 2. External validation AUROC.md": (
            "# Figure 2. External validation AUROC\n\n"
            "## 图面说明\n\n"
            "左右分别为 eICU、HiRID 外验 AUROC（四策略）；误差线为 stay-level DeLong 95% CI。\n\n"
            "## 分析上下文\n\n"
            "- Grouping：四训练策略 × 外验库\n"
            "- 是否拼图：单图双面板\n"
        ),
        "Figure 3. Calibration.md": (
            "# Figure 3. Calibration\n\n"
            "## 图面说明\n\n"
            "MIMIC-IV alone 与 Pooling 在 eICU/HiRID 的十分位校准曲线；标注 Brier score。\n\n"
            "## 分析上下文\n\n"
            "- 预测：stay 聚合死亡率概率\n"
        ),
        "Figure 4. Decision curve analysis.md": (
            "# Figure 4. Decision curve analysis\n\n"
            "## 图面说明\n\n"
            "阈值概率 1%–50% 的净获益；对照 Treat-all / Treat-none；比较 MIMIC-IV alone 与 Pooling。\n\n"
            "## 分析上下文\n\n"
            "- 用途：临床部署阈值选择\n"
        ),
        "Figure 5. Risk strata.md": (
            "# Figure 5. Risk strata\n\n"
            "## 图面说明\n\n"
            "Pooling 模型预测风险三分位的观察死亡率（eICU / HiRID）。\n\n"
            "## 分析上下文\n\n"
            "- 用途：风险分层 / 床旁分层展示\n"
        ),
    }
    for name, text in figs.items():
        (d / name).write_text(text, encoding="utf-8")


def write_methods(out: Path):
    md = f"""# Statistical analysis

## Study design and cohort
This multi-database pooling study analysed adult ICU stays with KDIGO-defined ICU-acquired AKI (extraction label DN=1) in a BlendedICU-harmonised extract (AmsterdamUMC, MIMIC-IV, eICU, HiRID). Creatinine and urine output were excluded from model features to avoid definition leakage.

## Preprocessing
Continuous time-series values were clipped to a priori physiological ranges, then scaled with training-set 5th/95th percentiles and clipped after scaling. Missingness used forward-fill with observation masks. Quantiles were fitted on the training split only.

## Model and endpoints
The primary architecture was a Temporal Pointwise Convolution (TPC) multitask network predicting hourly in-ICU death risk and remaining length of stay (RLoS) among predicted survivors. Data were split at the patient level (70%/15%/15%, fixed seed 974). Main strategies: (1) AmsterdamUMC alone; (2) MIMIC-IV alone; (3) transfer learning (pretrain MIMIC-IV, fine-tune AmsterdamUMC); (4) pooling AmsterdamUMC with MIMIC-IV. Held-out generalization used eICU and HiRID.

## Performance metrics and uncertainty
Mortality discrimination used AUROC; precision–recall used AUPRC where reported. RLoS error used MAPE. AUROC 95% CIs used the DeLong method at the ICU-stay level; MAPE/AUPRC intervals used patient-level percentile bootstrap ({N_BOOT:,} resamples). Pooling versus MIMIC-IV alone on shared external stays used paired DeLong tests (Table S3).

## Calibration, decision analysis, and clinical use
Calibration curves and Brier scores compared MIMIC-IV alone with pooling on eICU and HiRID (Figure 3). Decision-curve net benefit was plotted over threshold probabilities 1%–50% (Figure 4). Age+Sex logistic regression fitted on MIMIC-IV served as a stronger tabular baseline (Table S4). Pooling predicted risks were stratified into tertiles and evaluated at Youden and fixed (10%, 20%) thresholds for deployment-oriented operating points (Table S5, Figure 5).

## Software
Deep-learning training used Python with PyTorch on NVIDIA GPUs. Publication tables use SCI three-line xlsx (Times New Roman). Figures are exported under `Figures/{{pdf,png,tiff,image_information}}/`. See `Methods_software_versions.txt`.
"""
    (out / "Methods_statistical_analysis.md").write_text(md, encoding="utf-8")
    ver = (
        "ICUAKI 4DB Allyn TPC finalize\n"
        f"root={ROOT}\n"
        f"n_boot={N_BOOT}\n"
        f"python={sys.version.split()[0]}\n"
        "packages: pandas numpy scikit-learn matplotlib openpyxl scipy\n"
    )
    (out / "Methods_software_versions.txt").write_text(ver, encoding="utf-8")


def _write_clinical_extras(ci_mod, store: dict, ci: pd.DataFrame, pw: pd.DataFrame, tables: Path):
    """S3–S5 + Fig3–5 (appended after cirrhosis-aligned base pack)."""
    _save_table(
        table_s3_ci(ci, pw),
        tables / "Table S3. Confidence intervals and DeLong comparisons",
        title="Table S3. Stay-level DeLong AUROC confidence intervals, bootstrap AUPRC/MAPE intervals, and Pooling versus MIMIC-IV alone",
        footnote=f"AUROC CI: DeLong (Sun & Xu midrank). AUPRC/MAPE CI: patient-level percentile bootstrap ({N_BOOT:,}). "
        "Pooling vs MIMIC-IV alone: paired DeLong p on shared external stays.",
    )
    s4 = table_s4_baseline(ci_mod)
    if len(s4):
        _save_table(
            s4,
            tables / "Table S4. Age-Sex baseline versus TPC",
            title="Table S4. Stronger baseline (Age+Sex logistic) versus TPC on external databases",
            footnote="Age+Sex logistic regression fitted on a 70% random split of MIMIC-IV labelled stays (seed 974). "
            "Aligned-stay rows restrict to stays present in TPC test predictions for fair AUROC comparison.",
        )
    s5 = table_s5_risk_strata(ci_mod)
    if len(s5):
        _save_table(
            s5,
            tables / "Table S5. Risk stratification and operating points",
            title="Table S5. Clinical risk strata and deployment thresholds for the pooling model",
            footnote="Tertiles of stay-level predicted ICU mortality from the pooling TPC. "
            "Youden threshold maximises sensitivity+specificity−1 on the same external set (optimistic for that set). "
            "Fixed 10%/20% thresholds are pre-specified clinical operating points.",
        )
    make_fig3_calibration(PUB, ci_mod)
    make_fig4_dca(PUB, ci_mod)
    make_fig5_risk_strata(PUB, ci_mod)
    # Keep cirrhosis Fig1/Fig2 if present; only refresh extras image md
    write_image_information(PUB, store, ci, pw)
    write_methods(PUB)


def main():
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--extras-only",
        action="store_true",
        help="Only write S3–S5 / Fig3–5; keep cirrhosis-aligned Table1–4/S1–S2/Fig1–2",
    )
    args = ap.parse_args()

    tables = PUB / "Tables"
    internal = PUB / "_internal"
    tables.mkdir(parents=True, exist_ok=True)
    internal.mkdir(parents=True, exist_ok=True)
    EXTRA.mkdir(parents=True, exist_ok=True)

    ci_mod = _load_ci_mod()
    store = collect_main()
    print("[finalize] arms:", list(store.keys()), "extras_only=", args.extras_only, flush=True)
    ci, pw = ensure_ci(ci_mod)
    ci.to_csv(internal / "Table_CI_DeLong_bootstrap10k.csv", index=False)
    if len(pw):
        pw.to_csv(internal / "Table_DeLong_Pooling_vs_MIMIC.csv", index=False)

    if not args.extras_only:
        # Prefer full Allyn Table1 if already rebuilt; else labels fallback
        t1_path = tables / "Table 1. Cohort characteristics.xlsx"
        if not t1_path.exists():
            _save_table(
                table1_labels(),
                tables / "Table 1. Cohort characteristics",
                title="Table 1. Characteristics of ICU-AKI stays included in the study, according to the original database",
                footnote="KDIGO ICU-AKI cohort (DN=1). Labels-based fallback; prefer rebuild_icuaaki_table1_full.py.",
            )

        # Prefer dataset_benchmark Table2 via finalize_easl if present; else A/B fallback
        if not (EXTRA / "liver_dataset_benchmark").exists():
            _save_table(
                table2_from_ab(ci_mod, ci),
                tables / "Table 2. Internal and external",
                title="Table 2. Internal and external validation of the TPC model when training on AmsterdamUMC or MIMIC-IV alone",
                footnote="Fallback without four-DB dataset benchmark. External = pooled eICU+HiRID.",
            )

        _save_table(
            table3_wide(store, ci),
            tables / "Table 3. Four training strategies",
            title="Table 3. Model performance on specialization and generalization in four separate training methods",
            footnote="Endpoints: ICU mortality and remaining ICU LoS (RLoS; deaths excluded from MAPE). "
            "AUROC 95% CI: DeLong (stay-level). MAPE 95% CI: patient-level bootstrap. "
            "Mcomposite uses Amsterdam-alone on Amsterdam as baseline. "
            "¹Transfer: pretrain MIMIC-IV then fine-tune AmsterdamUMC. ²Pooling: AmsterdamUMC + MIMIC-IV. "
            "Generalization = mean of eICU and HiRID.",
        )
        _save_table(
            table4_literature(store, ci),
            tables / "Table 4. Literature comparison",
            title="Table 4. Comparison with related multi-database ICU mortality modelling",
            footnote="External AUROC values for the present study are stay-level DeLong estimates from Table S3.",
        )
        if not (tables / "Table S1. Physio clip and outliers.xlsx").exists():
            s1 = table_s1_scaling()
            if len(s1):
                _save_table(
                    s1,
                    tables / "Table S1. Physio clip and outliers",
                    title="Table S1. Training-set scaling quantiles (q5–q95) and post-scale clip",
                    footnote="Quantiles fitted on the pooling training split.",
                )
        if not (EXTRA / "liver_model_benchmark_equaln").exists():
            _save_table(
                table_s2_architecture(),
                tables / "Table S2. Model architectures",
                title="Table S2. Model architecture and protocol (TPC primary analysis)",
                footnote="Equal-n LSTM/Transformer bake-off pending Output_paper_extras.",
            )
        make_fig1(PUB, store)
        if not (EXTRA / "liver_training_size_study").exists():
            make_fig2(PUB, store, ci)

    _write_clinical_extras(ci_mod, store, ci, pw, tables)

    (PUB / "PUBLISH_READY.time").write_text(
        pd.Timestamp.now("UTC").isoformat() + "\n", encoding="utf-8"
    )
    print("wrote", PUB)
    print("tables:", sorted(p.name for p in tables.glob("*.xlsx")))
    print("figs:", sorted(p.name for p in (PUB / "Figures" / "pdf").glob("*.pdf")))


if __name__ == "__main__":
    main()
