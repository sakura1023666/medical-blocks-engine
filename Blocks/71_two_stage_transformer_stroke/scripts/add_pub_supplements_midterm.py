#!/usr/bin/env python3
"""Plan A midterm supplements v2 — redraw + renumber + SCI format + QA.

Tables (continuous after S1–S2; Figures keep S1–S7 already used):
  Table S3 ↔ Figure S8  Calibration (MIMIC Day5)
  Table S4 ↔ Figure S9  DCA (TF vs APSIII vs XGBoost)
  Table S5           Continuous NRI / IDI
  Table S6 ↔ Figure S10 eICU stratified AUC
  Table S7           Domain-shift summary (+ markdown note)

Does NOT rewrite Table 1–3, S1–S2, Figure 1–3, or S1–S7.

Usage:
  /mnt/c/ProgramData/Miniconda3/envs/torch/python.exe \\
    E:/01block/01Block-new-Final/Blocks/71_two_stage_transformer_stroke/scripts/add_pub_supplements_midterm.py \\
    --project-root G:/02block_result/42_AKI_spesis/two_stage_transformer_40041421_mimic_main \\
    --skip-eicu-score
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import sys
from pathlib import Path

os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score, roc_curve

REPO = Path(__file__).resolve().parents[3]
if str(REPO) not in sys.path:
    sys.path.insert(0, str(REPO))

# Reuse SCI three-line writer from summary builder
try:
    sys.path.insert(0, str(REPO / "Blocks/71_two_stage_transformer_stroke/scripts"))
    from build_summary_results import rows_to_xlsx as sci_rows_to_xlsx  # type: ignore
except Exception:
    sci_rows_to_xlsx = None  # fallback below


# ---------------------------------------------------------------------------
# paths / IO
# ---------------------------------------------------------------------------

def _is_windows_python() -> bool:
    return os.name == "nt" or sys.platform.startswith("win")


def _to_path(p: str | Path) -> Path:
    s = str(p).replace("\\", "/")
    if _is_windows_python():
        if s.startswith("/mnt/") and len(s) > 7 and s[6] == "/":
            s = f"{s[5].upper()}:/{s[7:]}"
        return Path(s)
    if len(s) >= 3 and s[1] == ":" and s[0].isalpha():
        return Path(f"/mnt/{s[0].lower()}{s[2:]}")
    return Path(s)


def md5_file(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def write_csv(path: Path, fieldnames: list[str], rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fieldnames})


def write_sci_xlsx(path: Path, title: str, rows: list[dict], footnotes: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if sci_rows_to_xlsx is not None:
        sci_rows_to_xlsx(path, rows, title, footnotes=footnotes)
        return
    # minimal fallback three-line
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Border, Font, Side
    from openpyxl.utils import get_column_letter

    cols = list(dict.fromkeys(k for r in rows for k in r.keys())) if rows else ["Note"]
    thick = Side(style="medium", color="000000")
    thin = Side(style="thin", color="000000")
    wb = Workbook()
    ws = wb.active
    ws.title = "Table"
    ws.sheet_view.showGridLines = False
    nc = len(cols)
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=nc)
    ws.cell(1, 1, title).font = Font(name="Times New Roman", size=12, bold=True)
    ws.cell(1, 1).alignment = Alignment(horizontal="center", wrap_text=True)
    for j, c in enumerate(cols, 1):
        cell = ws.cell(2, j, c)
        cell.font = Font(name="Times New Roman", size=12, bold=True)
        cell.border = Border(top=thick, bottom=thin)
        cell.alignment = Alignment(horizontal="center")
    for i, row in enumerate(rows):
        for j, c in enumerate(cols, 1):
            cell = ws.cell(3 + i, j, row.get(c, ""))
            cell.font = Font(name="Times New Roman", size=12)
            cell.alignment = Alignment(horizontal="center" if j > 1 else "left")
            if i == len(rows) - 1:
                cell.border = Border(bottom=thick)
    fr = 3 + len(rows)
    for k, note in enumerate(footnotes or []):
        ws.merge_cells(start_row=fr + k, start_column=1, end_row=fr + k, end_column=nc)
        cell = ws.cell(fr + k, 1, note)
        cell.font = Font(name="Times New Roman", size=12)
        if k == 0:
            cell.border = Border(top=thin)
    for j in range(1, nc + 1):
        ws.column_dimensions[get_column_letter(j)].width = 16
    wb.save(path)


def fmt3(x) -> str:
    if x == "" or x is None:
        return ""
    try:
        return f"{float(x):.3f}"
    except Exception:
        return str(x)


def fmt_int(n) -> str:
    try:
        return f"{int(n):,}"
    except Exception:
        return str(n)


def save_fig(fig, stem_name: str, figs_root: Path) -> None:
    for sub, ext in (("pdf", "pdf"), ("png", "png"), ("tiff", "tiff")):
        out = figs_root / sub / f"{stem_name}.{ext}"
        out.parent.mkdir(parents=True, exist_ok=True)
        kw = {"bbox_inches": "tight"}
        if ext == "png":
            kw["dpi"] = 300
        elif ext == "tiff":
            kw["dpi"] = 300
            kw["pil_kwargs"] = {"compression": "tiff_lzw"}
        fig.savefig(out, **kw)


def write_image_md(path: Path, title: str, visual: str, context: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"# {title}\n\n## 图面说明\n{visual}\n\n## 分析上下文\n{context}\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# metrics
# ---------------------------------------------------------------------------

def youden_thr(y, scores) -> float:
    fpr, tpr, thr = roc_curve(y, scores)
    if len(thr) == 0:
        return 0.5
    return float(thr[np.argmax(tpr - fpr)])


def calib_quantile(y, p, n_bins: int = 10, min_n: int = 20) -> list[dict]:
    """Equal-frequency bins; flag sparse bins."""
    y = np.asarray(y, dtype=int)
    p = np.asarray(p, dtype=float)
    # unique edges via ranks
    qs = np.linspace(0, 1, n_bins + 1)
    try:
        edges = np.unique(np.quantile(p, qs))
    except Exception:
        edges = np.linspace(float(p.min()), float(p.max()), n_bins + 1)
    if len(edges) < 3:
        edges = np.linspace(0, 1, n_bins + 1)
    rows = []
    for i in range(len(edges) - 1):
        lo, hi = edges[i], edges[i + 1]
        mask = (p >= lo) & (p < hi) if i < len(edges) - 2 else (p >= lo) & (p <= hi)
        n = int(mask.sum())
        if n == 0:
            continue
        rows.append(
            {
                "bin": i + 1,
                "predicted": round(float(p[mask].mean()), 3),
                "observed": round(float(y[mask].mean()), 3),
                "n": n,
                "include_in_figure": n >= min_n,
            }
        )
    return rows


def dca_curve(y, p, label: str, t_grid=None) -> list[dict]:
    y = np.asarray(y, dtype=int)
    p = np.asarray(p, dtype=float)
    n = len(y)
    prev = float(y.mean()) if n else 0.0
    if t_grid is None:
        t_grid = np.linspace(0.01, 0.99, 99)
    rows = []
    for t in t_grid:
        t = float(t)
        if t <= 0 or t >= 1:
            continue
        pred_pos = p >= t
        tp = float((pred_pos & (y == 1)).sum())
        fp = float((pred_pos & (y == 0)).sum())
        nb = (tp / n) - (fp / n) * (t / (1 - t))
        nb_all = prev - (1 - prev) * (t / (1 - t))
        rows.append(
            {
                "model": label,
                "threshold": round(t, 3),
                "net_benefit": round(float(nb), 4),
                "net_benefit_treat_all": round(float(nb_all), 4),
                "net_benefit_treat_none": 0.0,
            }
        )
    return rows


def continuous_nri_idi(y, p_new, p_old) -> dict:
    y = np.asarray(y, dtype=int)
    p_new = np.asarray(p_new, dtype=float)
    p_old = np.asarray(p_old, dtype=float)
    ev, ne = y == 1, y == 0
    up_e = float((p_new[ev] > p_old[ev]).mean() - (p_new[ev] < p_old[ev]).mean())
    up_ne = float((p_new[ne] < p_old[ne]).mean() - (p_new[ne] > p_old[ne]).mean())
    is_new = float(p_new[ev].mean() - p_new[ne].mean())
    is_old = float(p_old[ev].mean() - p_old[ne].mean())
    return {
        "Comparison": "",
        "N event": int(ev.sum()),
        "N non-event": int(ne.sum()),
        "NRI event": round(up_e, 3),
        "NRI non-event": round(up_ne, 3),
        "NRI total": round(up_e + up_ne, 3),
        "IDI": round(is_new - is_old, 3),
        "AUC new": round(float(roc_auc_score(y, p_new)), 3),
        "AUC old": round(float(roc_auc_score(y, p_old)), 3),
    }


def auc_bootstrap_ci(y, scores, n_boot=400, seed=42):
    rng = np.random.default_rng(seed)
    y = np.asarray(y, dtype=int)
    scores = np.asarray(scores, dtype=float)
    point = float(roc_auc_score(y, scores))
    boots = []
    n = len(y)
    for _ in range(n_boot):
        idx = rng.integers(0, n, size=n)
        yy, ss = y[idx], scores[idx]
        if len(np.unique(yy)) < 2:
            continue
        boots.append(float(roc_auc_score(yy, ss)))
    if len(boots) < 20:
        return point, point, point
    lo, hi = np.percentile(boots, [2.5, 97.5])
    return point, float(lo), float(hi)


# ---------------------------------------------------------------------------
# score helpers
# ---------------------------------------------------------------------------

def load_apsiii_map(csv_path: Path) -> dict[int, float]:
    out = {}
    with csv_path.open(encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        return out
    keys = {k.lower(): k for k in rows[0].keys()}
    id_k = keys.get("stay_id") or list(rows[0].keys())[0]
    sc_k = keys.get("apsiii") or keys.get("score") or list(rows[0].keys())[1]
    for r in rows:
        try:
            out[int(float(r[id_k]))] = float(r[sc_k])
        except Exception:
            continue
    return out


def static_channel(X, names, key):
    names = [str(n) for n in names]
    if key not in names:
        return np.full(X.shape[0], np.nan)
    j = names.index(key)
    return X[:, :, :, j].mean(axis=(1, 2))


def score_tf(model_path, data_dir, day, split="test"):
    from torch.utils.data import DataLoader
    from python.two_stage_transformer.dataloader import TSTDataset
    from python.two_stage_transformer.eval import load_model_for_eval, score_all_cutoffs

    ds = TSTDataset(split, str(data_dir))
    D, H, F = ds.n_days, ds.n_hours, ds.n_features
    model = load_model_for_eval(str(model_path), "b", D, H, F)
    dl = DataLoader(ds, batch_size=64, shuffle=False)
    scores = score_all_cutoffs(model, dl, D)
    y = ds.y.astype(int)
    los = ds.day_mask.sum(1).astype(int)
    day = min(day, D)
    sel = los >= day
    return y[sel], np.asarray(scores[day][sel], dtype=float), ds, sel


def score_tf_npz(model_path, npz_path, day):
    from torch.utils.data import DataLoader
    from python.two_stage_transformer.dataloader import TSTDataset
    from python.two_stage_transformer.eval import load_model_for_eval, score_all_cutoffs

    ds = TSTDataset(npz_path=str(npz_path))
    D, H, F = ds.n_days, ds.n_hours, ds.n_features
    model = load_model_for_eval(str(model_path), "b", D, H, F)
    dl = DataLoader(ds, batch_size=64, shuffle=False)
    scores = score_all_cutoffs(model, dl, D)
    y = ds.y.astype(int)
    los = ds.day_mask.sum(1).astype(int)
    day = min(day, D)
    sel = los >= day
    raw = np.load(npz_path, allow_pickle=True)
    names = [str(x) for x in raw["feature_names"]]
    X = raw["X"]
    return (
        y[sel],
        np.asarray(scores[day][sel], dtype=float),
        {k: static_channel(X, names, k)[sel] for k in names if k.startswith("static_")},
    )


def xgb_day5_probs(data_dir, day=5, seed=42):
    from python.two_stage_transformer.baselines import _day_sequence_features
    from python.two_stage_transformer.dataloader import TSTDataset

    tr = TSTDataset("train", str(data_dir))
    te = TSTDataset("test", str(data_dir))

    def feats(ds):
        X = _day_sequence_features(ds)
        d = min(day, X.shape[1])
        return X[:, :d, :].reshape(X.shape[0], -1)

    X_tr, X_te = feats(tr), feats(te)
    try:
        from xgboost import XGBClassifier

        clf = XGBClassifier(n_estimators=200, max_depth=4, random_state=seed, eval_metric="logloss")
    except Exception:
        from sklearn.ensemble import GradientBoostingClassifier

        clf = GradientBoostingClassifier(n_estimators=150, random_state=seed)
    clf.fit(X_tr, tr.y)
    return te.y.astype(int), clf.predict_proba(X_te)[:, 1]


def apsiii_probs(data_dir, aps_map, day=5, seed=42):
    from python.two_stage_transformer.dataloader import TSTDataset

    tr = TSTDataset("train", str(data_dir))
    te = TSTDataset("test", str(data_dir))
    los_te = te.day_mask.sum(1).astype(int)
    pid_tr = np.asarray(np.load(Path(data_dir) / "train.npz", allow_pickle=True)["patient_id"], dtype=np.int64)
    pid_te = np.asarray(np.load(Path(data_dir) / "test.npz", allow_pickle=True)["patient_id"], dtype=np.int64)
    s_tr = np.array([aps_map.get(int(p), np.nan) for p in pid_tr], dtype=float)
    s_te = np.array([aps_map.get(int(p), np.nan) for p in pid_te], dtype=float)
    ok_tr = np.isfinite(s_tr)
    ok_te = (los_te >= day) & np.isfinite(s_te)
    lr = LogisticRegression(max_iter=1000, random_state=seed)
    lr.fit(s_tr[ok_tr].reshape(-1, 1), tr.y[ok_tr])
    p_te = np.full(len(te.y), np.nan)
    p_te[ok_te] = lr.predict_proba(s_te[ok_te].reshape(-1, 1))[:, 1]
    return te.y.astype(int), p_te, ok_te


# ---------------------------------------------------------------------------
# plots
# ---------------------------------------------------------------------------

COLORS = {
    "Two-stage Transformer": "#2c7fb8",
    "XGBoost": "#31a354",
    "APSIII": "#e6550d",
    "Two-stage Transformer (eICU)": "#2c7fb8",
}


def plot_calibration(rows_by_model, figs_root, stem, title, subtitle=""):
    fig, ax = plt.subplots(figsize=(5.4, 5.0))
    ax.plot([0, 1], [0, 1], "--", color="#888888", lw=1.2, label="Ideal")
    for name, rows in rows_by_model.items():
        use = [r for r in rows if r.get("include_in_figure", True)]
        if not use:
            continue
        ax.plot(
            [r["predicted"] for r in use],
            [r["observed"] for r in use],
            "-o",
            color=COLORS.get(name, None),
            label=name,
            ms=5,
            lw=1.6,
        )
    ax.set_xlabel("Predicted probability")
    ax.set_ylabel("Observed frequency")
    ax.set_title(title + (f"\n{subtitle}" if subtitle else ""), fontsize=11)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.set_aspect("equal", adjustable="box")
    ax.legend(frameon=False, fontsize=8, loc="upper left")
    ax.grid(True, alpha=0.25)
    save_fig(fig, stem, figs_root)
    plt.close(fig)


def plot_dca(curves, figs_root, stem, title, t_min=0.05, t_max=0.50):
    fig, ax = plt.subplots(figsize=(6.4, 4.6))
    disp = {}
    for name, rows in curves.items():
        disp[name] = [r for r in rows if t_min - 1e-9 <= r["threshold"] <= t_max + 1e-9]
    any_rows = next(iter(disp.values()))
    thr = [r["threshold"] for r in any_rows]
    # Treat-all: only draw while net benefit stays clinically readable (>= -0.05)
    ta = [r["net_benefit_treat_all"] for r in any_rows]
    ta_thr, ta_y = [], []
    for t, v in zip(thr, ta):
        if v < -0.05:
            break
        ta_thr.append(t)
        ta_y.append(v)
    if ta_thr:
        ax.plot(ta_thr, ta_y, color="#636363", ls="--", lw=1.2, label="Treat all")
    ax.plot(thr, [0.0] * len(thr), color="#bdbdbd", ls=":", lw=1.2, label="Treat none")
    for name, rows in disp.items():
        ax.plot(thr, [r["net_benefit"] for r in rows], color=COLORS.get(name), lw=1.9, label=name)
    # ylim dominated by model curves (not plunging Treat-all)
    model_vals = [r["net_benefit"] for rows in disp.values() for r in rows] + [0.0] + ta_y
    ymin = min(model_vals)
    ymax = max(model_vals)
    pad = max(0.01, 0.10 * (ymax - ymin + 1e-6))
    ax.set_ylim(min(-0.05, ymin - pad), ymax + pad)
    ax.set_xlim(t_min, t_max)
    ax.set_xlabel("Threshold probability")
    ax.set_ylabel("Net benefit")
    ax.set_title(title, fontsize=11)
    ax.legend(frameon=False, fontsize=8, loc="upper right")
    ax.grid(True, alpha=0.25)
    save_fig(fig, stem, figs_root)
    plt.close(fig)


def plot_strata(rows, figs_root, stem, title):
    # rows already ordered; expect AUC as float and optional CI
    labels = [row["label"] for row in rows]
    aucs = [float(row["auc"]) for row in rows]
    los = [float(row.get("auc_lo", aucs[i])) for i, row in enumerate(rows)]
    his = [float(row.get("auc_hi", aucs[i])) for i, row in enumerate(rows)]
    fig, ax = plt.subplots(figsize=(7.2, max(3.2, 0.42 * len(rows) + 1.2)))
    y = np.arange(len(labels))
    xerr = np.vstack([np.array(aucs) - np.array(los), np.array(his) - np.array(aucs)])
    ax.barh(y, aucs, color="#2c7fb8", height=0.62, alpha=0.9)
    ax.errorbar(aucs, y, xerr=xerr, fmt="none", ecolor="#222222", capsize=3, lw=1)
    ax.set_yticks(y)
    ax.set_yticklabels(labels, fontsize=9)
    xmin = max(0.45, min(los) - 0.03)
    xmax = min(0.85, max(his) + 0.05)
    ax.set_xlim(xmin, xmax)
    ax.axvline(0.5, color="#999999", ls="--", lw=0.9)
    ax.set_xlabel("AUC (95% CI)")
    ax.set_title(title, fontsize=11)
    for i, r in enumerate(rows):
        ax.text(his[i] + 0.005, i, f"n={fmt_int(r['n'])}", va="center", fontsize=8, color="#333333")
    ax.invert_yaxis()
    fig.tight_layout()
    save_fig(fig, stem, figs_root)
    plt.close(fig)


# ---------------------------------------------------------------------------
# cleanup old wrong-numbered files
# ---------------------------------------------------------------------------

OLD_TABLE_GLOBS = [
    "Table S8-*.xlsx",
    "Table S9-*.xlsx",
    "Table S10-*.xlsx",
    "Table S11-*.xlsx",
    "Table S11b-*.md",
]


def remove_old_tables(tables: Path) -> list[str]:
    removed = []
    for pat in OLD_TABLE_GLOBS:
        for p in tables.glob(pat):
            p.unlink()
            removed.append(p.name)
    return removed


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-root", required=True)
    ap.add_argument("--day", type=int, default=5)
    ap.add_argument("--landmark", type=int, default=120)
    ap.add_argument("--skip-eicu-score", action="store_true")
    ap.add_argument("--dca-tmin", type=float, default=0.05)
    ap.add_argument("--dca-tmax", type=float, default=0.50)
    ap.add_argument("--calib-min-n", type=int, default=20)
    args = ap.parse_args()

    proj = _to_path(args.project_root)
    summary = proj / "summary_results"
    tables = summary / "Tables"
    figs = summary / "Figures"
    day = int(args.day)
    lm = int(args.landmark)
    cache_dir = summary / f"by_landmark/L{lm}/midterm_supplements"
    cache_dir.mkdir(parents=True, exist_ok=True)

    # lock pre-existing mains
    lock_needles = ("Table 1-", "Table 2-", "Table 3-", "Table S1-", "Table S2-")
    locked = [p for p in tables.glob("Table*.xlsx") if any(n in p.name for n in lock_needles)]
    locked += [
        p
        for p in (figs / "pdf").glob("Figure*.pdf")
        if not re.search(r"Figure S(8|9|10|11)\b", p.name)
    ]
    pre = {str(p): md5_file(p) for p in locked if p.is_file()}

    removed = remove_old_tables(tables)
    if removed:
        print("Removed old numbered tables:", ", ".join(removed))

    ud_cands = [
        proj / f"by_unit/L{lm}_B_twostage/step09_tst_train_eval/Tables",
        proj / f"by_unit/【success】L{lm}_B_twostage/step09_tst_train_eval/Tables",
    ]
    ud = next((p for p in ud_cands if (p / "npz" / "test.npz").is_file()), ud_cands[0])
    data_dir = ud / "npz"
    model_path = ud / "model_b.pth"
    aps_csv = proj / "_tmp_apsiii_by_stay.csv"
    eicu_npz = summary / f"by_landmark/L{lm}/eicu_external/eicu.npz"
    print(f"unit tables: {ud}")

    print("[1] MIMIC scores …")
    y_tf, p_tf, te_ds, day_sel_arr = score_tf(model_path, data_dir, day, "test")
    y_all = te_ds.y.astype(int)
    los = te_ds.day_mask.sum(1).astype(int)
    day_sel = los >= day
    assert int(day_sel.sum()) == len(y_tf)

    _, p_xgb_full = xgb_day5_probs(data_dir, day=day, seed=42)
    aps_map = load_apsiii_map(aps_csv)
    _, p_aps_full, ok_aps = apsiii_probs(data_dir, aps_map, day=day, seed=42)

    common = day_sel & ok_aps
    day_idx = np.where(day_sel)[0]
    pos = {int(i): k for k, i in enumerate(day_idx)}
    common_day_pos = [pos[int(i)] for i in np.where(common)[0]]
    y = y_all[common]
    p_tf_c = p_tf[common_day_pos]
    p_xgb_c = p_xgb_full[common]
    p_aps_c = p_aps_full[common]
    y849, p_tf849, p_xgb849 = y_tf, p_tf, p_xgb_full[day_sel]
    n_common, n_day = len(y), len(y849)
    auc_tf_point = float(roc_auc_score(y849, p_tf849))
    auc_xgb_point = float(roc_auc_score(y849, p_xgb849))
    auc_aps_point = float(roc_auc_score(y, p_aps_c))
    print(f"  Day{day} n={n_day}; common∩APSIII n={n_common}")
    print(f"  point AUC TF={auc_tf_point:.3f} XGB={auc_xgb_point:.3f} APSIII={auc_aps_point:.3f}")

    print("[2] Calibration / DCA / NRI …")
    cal_tf = calib_quantile(y849, p_tf849, min_n=args.calib_min_n)
    cal_xgb = calib_quantile(y849, p_xgb849, min_n=args.calib_min_n)
    cal_aps = calib_quantile(y, p_aps_c, min_n=args.calib_min_n)

    # Table S3
    s3_rows = []
    for model, rows in (
        ("Two-stage Transformer", cal_tf),
        ("XGBoost", cal_xgb),
        ("APSIII (logit-calibrated)", cal_aps),
    ):
        for r in rows:
            s3_rows.append(
                {
                    "Model": model,
                    "Bin": r["bin"],
                    "Predicted": fmt3(r["predicted"]),
                    "Observed": fmt3(r["observed"]),
                    "N": fmt_int(r["n"]),
                    "In figure": "Yes" if r["include_in_figure"] else "No (n < 20)",
                }
            )
    write_sci_xlsx(
        tables / "Table S3-MIMIC. Calibration of predicted probabilities for in-hospital mortality (Day 5).xlsx",
        "Table S3-MIMIC. Calibration of predicted probabilities for in-hospital mortality (Day 5)",
        s3_rows,
        footnotes=[
            f"Equal-frequency bins. Transformer/XGBoost: L{lm} Day{day} test n={fmt_int(n_day)}.",
            f"APSIII: logistic calibration on training set; evaluated on APSIII-available test n={fmt_int(n_common)}.",
            f"Figure S8 omits bins with n < {args.calib_min_n} to avoid unstable spikes.",
            "Additive supplement; does not alter Table 2/3.",
        ],
    )
    write_csv(cache_dir / "Table_S3_calibration.csv", list(s3_rows[0].keys()), s3_rows)
    plot_calibration(
        {"Two-stage Transformer": cal_tf, "XGBoost": cal_xgb, "APSIII": cal_aps},
        figs,
        "Figure S8-MIMIC-Calibration_Day5",
        "Figure S8. Calibration (MIMIC Day 5)",
        subtitle=f"Bins with n ≥ {args.calib_min_n} shown",
    )
    write_image_md(
        figs / "image_information" / "Figure S8-MIMIC-Calibration_Day5.md",
        "Figure S8-MIMIC-Calibration_Day5",
        f"校准曲线（等频分箱）；仅绘制 n≥{args.calib_min_n} 的箱。对角线为理想校准。"
        f"对应 Table S3。TF/XGB 基于 Day5 test n={fmt_int(n_day)}。",
        f"结局: 住院死亡；Grouping: L{lm}; 数据库: MIMIC；与 Table S3 同口径",
    )

    # DCA — store full for table subset, plot clinical window
    t_full = np.round(np.arange(0.01, 1.00, 0.01), 3)
    dca_tf = dca_curve(y, p_tf_c, "Two-stage Transformer", t_full)
    dca_xgb = dca_curve(y, p_xgb_c, "XGBoost", t_full)
    dca_aps = dca_curve(y, p_aps_c, "APSIII", t_full)
    tmin, tmax = float(args.dca_tmin), float(args.dca_tmax)
    s4_rows = []
    for rows in (dca_tf, dca_xgb, dca_aps):
        for r in rows:
            if tmin - 1e-9 <= r["threshold"] <= tmax + 1e-9:
                s4_rows.append(
                    {
                        "Model": r["model"],
                        "Threshold": fmt3(r["threshold"]),
                        "Net benefit": fmt3(r["net_benefit"]),
                        "Treat all": fmt3(r["net_benefit_treat_all"]),
                        "Treat none": "0.000",
                    }
                )
    write_sci_xlsx(
        tables / "Table S4-MIMIC. Decision curve analysis (Day 5; TF vs APSIII vs XGBoost).xlsx",
        "Table S4-MIMIC. Decision curve analysis (Day 5; TF vs APSIII vs XGBoost)",
        s4_rows,
        footnotes=[
            f"Same patients: Day{day} test ∩ APSIII available, n={fmt_int(n_common)}.",
            f"Table/Figure show thresholds {tmin:.2f}–{tmax:.2f} (clinically relevant window).",
            "APSIII converted to probability via training-set logistic calibration.",
            "Corresponds to Figure S9.",
        ],
    )
    write_csv(cache_dir / "Table_S4_dca.csv", list(s4_rows[0].keys()), s4_rows)
    plot_dca(
        {"Two-stage Transformer": dca_tf, "XGBoost": dca_xgb, "APSIII": dca_aps},
        figs,
        "Figure S9-MIMIC-DCA_Day5",
        "Figure S9. Decision curve analysis (MIMIC Day 5)",
        t_min=tmin,
        t_max=tmax,
    )
    write_image_md(
        figs / "image_information" / "Figure S9-MIMIC-DCA_Day5.md",
        "Figure S9-MIMIC-DCA_Day5",
        f"决策曲线；阈值概率限制在 {tmin:.2f}–{tmax:.2f}，纵轴按显示区间自适应，避免 Treat-all 在高阈值爆炸。"
        f"对应 Table S4。分析集 n={fmt_int(n_common)}。",
        f"模型: TF / XGBoost / APSIII；数据库: MIMIC；L{lm} Day{day}",
    )

    nri_aps_raw = continuous_nri_idi(y, p_tf_c, p_aps_c)
    nri_aps_raw["Comparison"] = "TF vs APSIII"
    nri_xgb_raw = continuous_nri_idi(y, p_tf_c, p_xgb_c)
    nri_xgb_raw["Comparison"] = "TF vs XGBoost"
    s5_rows = []
    for raw in (nri_aps_raw, nri_xgb_raw):
        s5_rows.append(
            {
                "Comparison": raw["Comparison"],
                "N event": fmt_int(raw["N event"]),
                "N non-event": fmt_int(raw["N non-event"]),
                "NRI event": fmt3(raw["NRI event"]),
                "NRI non-event": fmt3(raw["NRI non-event"]),
                "NRI total": fmt3(raw["NRI total"]),
                "IDI": fmt3(raw["IDI"]),
                "AUC new": fmt3(raw["AUC new"]),
                "AUC old": fmt3(raw["AUC old"]),
            }
        )
    write_sci_xlsx(
        tables / "Table S5-MIMIC. Continuous NRI and IDI (Day 5; TF vs APSIII and XGBoost).xlsx",
        "Table S5-MIMIC. Continuous NRI and IDI (Day 5; TF vs APSIII and XGBoost)",
        s5_rows,
        footnotes=[
            "Continuous NRI (Pencina) and IDI; TF = new model.",
            f"Cohort: Day{day} test ∩ APSIII available, n={fmt_int(n_common)} (same as Table S4 / Figure S9).",
            "APSIII probabilities from training-set logistic calibration.",
        ],
    )
    write_csv(cache_dir / "Table_S5_nri_idi.csv", list(s5_rows[0].keys()), s5_rows)

    print("[3] eICU strata + calibration …")
    eicu_cache = cache_dir / "eicu_day5_scores.npz"
    if args.skip_eicu_score and eicu_cache.is_file():
        z = np.load(eicu_cache, allow_pickle=True)
        y_e, p_e = z["y"], z["p"]
        statics = {k: z[k] for k in z.files if k.startswith("static_")}
    else:
        y_e, p_e, statics = score_tf_npz(model_path, eicu_npz, day)
        np.savez_compressed(eicu_cache, y=y_e, p=p_e, **statics)
    auc_e = float(roc_auc_score(y_e, p_e))
    thr_e = youden_thr(y_e, p_e)
    acc_e = float(((p_e > thr_e) == y_e).mean())
    print(f"  eICU Day{day} n={len(y_e)} AUC={auc_e:.4f} (lock-check vs S7=0.6398)")

    strata_plot = []
    s6_rows = []

    def add_stratum(stratum, level, mask, label):
        m = np.asarray(mask, dtype=bool)
        n = int(m.sum())
        ne = int(y_e[m].sum()) if n else 0
        if n < 50 or len(np.unique(y_e[m])) < 2:
            s6_rows.append(
                {
                    "Stratum": stratum,
                    "Level": level,
                    "N": fmt_int(n),
                    "Events": fmt_int(ne),
                    "AUC": "",
                    "AUC 95% CI": "",
                    "Accuracy": "",
                }
            )
            return
        a, lo, hi = auc_bootstrap_ci(y_e[m], p_e[m], n_boot=400, seed=42)
        thr = youden_thr(y_e[m], p_e[m])
        acc = float(((p_e[m] > thr) == y_e[m]).mean())
        s6_rows.append(
            {
                "Stratum": stratum,
                "Level": level,
                "N": fmt_int(n),
                "Events": fmt_int(ne),
                "AUC": fmt3(a),
                "AUC 95% CI": f"{fmt3(lo)}-{fmt3(hi)}",
                "Accuracy": fmt3(acc),
            }
        )
        strata_plot.append({"label": label, "auc": a, "auc_lo": lo, "auc_hi": hi, "n": n})

    a0, lo0, hi0 = auc_bootstrap_ci(y_e, p_e, n_boot=400, seed=42)
    s6_rows.append(
        {
            "Stratum": "Overall",
            "Level": "All",
            "N": fmt_int(len(y_e)),
            "Events": fmt_int(int(y_e.sum())),
            "AUC": fmt3(a0),
            "AUC 95% CI": f"{fmt3(lo0)}-{fmt3(hi0)}",
            "Accuracy": fmt3(acc_e),
        }
    )
    strata_plot.append({"label": "Overall", "auc": a0, "auc_lo": lo0, "auc_hi": hi0, "n": len(y_e)})

    if "static_Age" in statics:
        age = statics["static_Age"]
        add_stratum("Age", "< 65", age < 65, "Age < 65")
        add_stratum("Age", "≥ 65", age >= 65, "Age ≥ 65")
    if "static_Gender" in statics:
        g = statics["static_Gender"]
        add_stratum("Gender", "Female", g < 0.5, "Female")
        add_stratum("Gender", "Male", g >= 0.5, "Male")
    if "static_GCS" in statics:
        gcs = statics["static_GCS"]
        add_stratum("GCS", "< 15", gcs < 15, "GCS < 15")
        add_stratum("GCS", "≥ 15", gcs >= 15, "GCS ≥ 15")

    write_sci_xlsx(
        tables / "Table S6-eICU. Stratified external validation performance (Day 5).xlsx",
        "Table S6-eICU. Stratified external validation performance (Day 5)",
        s6_rows,
        footnotes=[
            "MIMIC-trained Two-stage Transformer (architecture B), weights not retrained.",
            "Day 5 = day_mask sum ≥ 5. Accuracy uses Youden threshold within each stratum.",
            "AUC 95% CI: patient-level bootstrap (n_boot=400, seed=42).",
            "Ventilation/CRRT omitted (non-informative on eICU static features).",
            "Overall AUC aligns with Figure S7; corresponds to Figure S10.",
        ],
    )
    write_csv(cache_dir / "Table_S6_eicu_strata.csv", list(s6_rows[0].keys()), s6_rows)
    plot_strata(strata_plot, figs, "Figure S10-eICU-Stratified_AUC", "Figure S10. eICU stratified AUC (Day 5)")
    write_image_md(
        figs / "image_information" / "Figure S10-eICU-Stratified_AUC.md",
        "Figure S10-eICU-Stratified_AUC",
        "eICU 外验分层 AUC（95% CI）；分层：Overall / Age / Gender / GCS。"
        f"Overall AUC={fmt3(a0)}，与 Figure S7（0.640）一致。对应 Table S6。",
        f"eICU Day5 n={fmt_int(len(y_e))}；不重训；L{lm}",
    )

    cal_e = calib_quantile(y_e, p_e, min_n=50)
    s7_cal_rows = [
        {
            "Bin": r["bin"],
            "Predicted": fmt3(r["predicted"]),
            "Observed": fmt3(r["observed"]),
            "N": fmt_int(r["n"]),
            "In figure": "Yes" if r["include_in_figure"] else "No (n < 50)",
        }
        for r in cal_e
    ]
    # Domain-shift summary rows + calibration in one Table S7 with two sections via footnotes
    s7_summary = [
        {"Item": "MIMIC Day5 TF AUC (point, test)", "Value": fmt3(auc_tf_point)},
        {"Item": "eICU Day5 TF AUC (point)", "Value": fmt3(auc_e)},
        {"Item": "Absolute AUC drop (MIMIC − eICU)", "Value": fmt3(auc_tf_point - auc_e)},
        {"Item": "MIMIC Day5 test event rate", "Value": fmt3(float(y849.mean()))},
        {"Item": "eICU Day5 event rate", "Value": fmt3(float(y_e.mean()))},
        {"Item": "eICU Day5 N", "Value": fmt_int(len(y_e))},
        {"Item": "eICU Day5 events", "Value": fmt_int(int(y_e.sum()))},
    ]
    write_sci_xlsx(
        tables / "Table S7-eICU. Domain-shift summary and external calibration (Day 5).xlsx",
        "Table S7-eICU. Domain-shift summary and external calibration (Day 5)",
        s7_summary + [{"Item": "— Calibration bins —", "Value": ""}] + [
            {"Item": f"Bin {r['Bin']}: pred={r['Predicted']}, obs={r['Observed']}, n={r['N']}", "Value": r["In figure"]}
            for r in s7_cal_rows
        ],
        footnotes=[
            "Transformer alone (no severity-score blend), matching Figure S7.",
            "Figure S11 shows calibration bins with n ≥ 50 only.",
            "See also Domain_shift_explanation.md in midterm_supplements/.",
        ],
    )
    note = "\n".join(
        [
            "# Domain-shift note (MIMIC → eICU)",
            "",
            f"- MIMIC Day5 TF AUC (point): {auc_tf_point:.3f} (n={n_day})",
            f"- eICU Day5 TF AUC: {auc_e:.3f} (n={len(y_e)}; Acc={acc_e:.3f})",
            f"- Drop: {auc_tf_point - auc_e:.3f}",
            f"- Event rate MIMIC→eICU: {float(y849.mean()):.3f} → {float(y_e.mean()):.3f}",
            "- Calibration on eICU is poor (over-confident high scores); discrimination attenuates under site shift.",
            "- Figure S7 headline AUC unchanged (0.640).",
            "- Strata: Age / Gender / GCS (Table S6 / Figure S10).",
        ]
    )
    (cache_dir / "Domain_shift_explanation.md").write_text(note + "\n", encoding="utf-8")
    (tables / "README_supplement_S3_S7.md").write_text(
        "\n".join(
            [
                "# Supplement table–figure map (v2)",
                "",
                "| Table | Figure | Content |",
                "|-------|--------|---------|",
                "| Table S3 | Figure S8 | MIMIC Day5 calibration |",
                "| Table S4 | Figure S9 | MIMIC Day5 DCA |",
                "| Table S5 | — | Continuous NRI/IDI |",
                "| Table S6 | Figure S10 | eICU stratified AUC |",
                "| Table S7 | Figure S11 | Domain-shift + eICU calibration |",
                "",
                "Main Table 1–3 / S1–S2 / Figure 1–3 / S1–S7 were not modified.",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    plot_calibration(
        {"Two-stage Transformer (eICU)": cal_e},
        figs,
        "Figure S11-eICU-Calibration_domain_shift",
        "Figure S11. eICU calibration (Day 5)",
        subtitle="Domain shift; bins with n ≥ 50",
    )
    write_image_md(
        figs / "image_information" / "Figure S11-eICU-Calibration_domain_shift.md",
        "Figure S11-eICU-Calibration_domain_shift",
        f"eICU Day5 校准（仅 n≥50 箱）。域偏移：MIMIC AUC {fmt3(auc_tf_point)} → eICU {fmt3(auc_e)}；"
        f"事件率 {fmt3(float(y849.mean()))} → {fmt3(float(y_e.mean()))}。对应 Table S7。",
        f"eICU n={fmt_int(len(y_e))}；与 Figure S7 同一权重、不重训",
    )

    # QA
    qa = []
    s7_json = summary / f"by_landmark/L{lm}/eicu_external/Table_External_eICU_Metrics.json"
    if s7_json.is_file():
        locked_auc = float(json.loads(s7_json.read_text())["auc"])
        if abs(locked_auc - auc_e) > 1e-3:
            qa.append(f"FAIL eICU AUC {auc_e:.4f} != S7 locked {locked_auc:.4f}")
        else:
            qa.append(f"OK eICU AUC matches S7 ({auc_e:.4f})")
    # calib n sum
    for name, rows, expect in (("TF", cal_tf, n_day), ("XGB", cal_xgb, n_day), ("APS", cal_aps, n_common)):
        s = sum(r["n"] for r in rows)
        qa.append(("OK" if s == expect else "FAIL") + f" {name} calib n sum={s} expect={expect}")
    auc_tf_common = float(roc_auc_score(y, p_tf_c))
    if abs(auc_tf_common - float(nri_aps_raw["AUC new"])) > 1e-3:
        qa.append(f"FAIL S5 AUC new {nri_aps_raw['AUC new']} != TF common {auc_tf_common:.3f}")
    else:
        qa.append(f"OK S5 AUC new = TF common AUC={auc_tf_common:.3f}")
    if abs(float(nri_aps_raw["AUC old"]) - auc_aps_point) > 1e-3:
        qa.append(f"FAIL S5 AUC old vs APSIII point")
    else:
        qa.append(f"OK S5 AUC old = APSIII {auc_aps_point:.3f}")
    if abs(auc_tf_point - 0.802) > 0.02:
        qa.append(f"WARN TF point AUC {auc_tf_point:.3f} far from Table2 mean 0.802")
    else:
        qa.append(f"OK TF point AUC {auc_tf_point:.3f} ≈ Table2 Day5 0.802")
    if abs(a0 - auc_e) > 1e-6:
        qa.append("FAIL Overall strata AUC != eICU point AUC")
    else:
        qa.append(f"OK Table S6 Overall AUC = eICU point {auc_e:.3f}")
    (cache_dir / "QA_consistency.txt").write_text("\n".join(qa) + "\n", encoding="utf-8")
    print("[QA]")
    for line in qa:
        print(" ", line)

    bad = []
    for p, h0 in pre.items():
        pp = Path(p)
        if not pp.is_file():
            bad.append(f"MISSING {p}")
            continue
        if md5_file(pp) != h0:
            bad.append(f"CHANGED {p}")
    if bad:
        raise SystemExit("Locked outputs modified:\n" + "\n".join(bad))
    print("[4] Locked mains unchanged — OK")

    (summary / "00_Supplement_S3_S7_map.txt").write_text(
        "\n".join(
            [
                "Supplement map v2 (tables renumbered continuously after S1–S2)",
                "Table S3 | Figure S8 | Calibration MIMIC Day5",
                "Table S4 | Figure S9 | DCA TF vs APSIII vs XGBoost",
                "Table S5 | — | Continuous NRI/IDI",
                "Table S6 | Figure S10 | eICU stratified AUC",
                "Table S7 | Figure S11 | Domain-shift + eICU calibration",
                f"NRI TF vs APSIII total={nri_aps_raw['NRI total']}; TF vs XGB total={nri_xgb_raw['NRI total']}",
                f"eICU overall AUC={auc_e:.4f} (Figure S7 locked)",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    old_map = summary / "00_Supplement_S8_S11_map.txt"
    if old_map.is_file():
        old_map.unlink()

    print("[5] Done v2")
    print(json.dumps({"n_day": n_day, "n_common": n_common, "n_eicu": int(len(y_e)), "auc_eicu": auc_e}, indent=2))


if __name__ == "__main__":
    main()
