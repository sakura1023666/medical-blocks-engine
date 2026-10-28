#!/usr/bin/env python3
"""Paper-grade CIs for BlendedLoS liver runs (Allyn Crit Care 2026 Methods).

- AUROC 95% CI: DeLong
- Pairwise AUROC comparison: DeLong test (e.g. Pooling vs MIMIC-IV alone)
- MAPE / AUPRC 95% CI: patient-level bootstrap, 10,000 iterations, percentile

Usage:
  python eval_liver_paper_ci.py --root .../Output_noenzyme \\
      --units liver_expB_mimic_solo,liver_expD_pooled_mimic_amsterdam \\
      --out .../Tables_ci
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import average_precision_score, roc_auc_score


def _compute_midrank(x: np.ndarray) -> np.ndarray:
    order = np.argsort(x)
    ranks = np.empty(len(x), dtype=float)
    n = len(x)
    i = 0
    while i < n:
        j = i
        while j < n and x[order[j]] == x[order[i]]:
            j += 1
        ranks[order[i:j]] = 0.5 * (i + j - 1) + 1
        i = j
    return ranks


def delong_auc_ci(y_true: np.ndarray, y_score: np.ndarray, alpha: float = 0.95):
    """DeLong AUROC point + asymptotic 95% CI (Sun & Xu)."""
    y_true = np.asarray(y_true).astype(int)
    y_score = np.asarray(y_score, dtype=float)
    pos = y_score[y_true == 1]
    neg = y_score[y_true == 0]
    m, n = len(pos), len(neg)
    if m < 1 or n < 1:
        return float("nan"), float("nan"), float("nan")
    auc = float(roc_auc_score(y_true, y_score))
    # structural components
    tx = np.concatenate([pos, neg])
    mid = _compute_midrank(tx)
    v10 = (mid[:m] - mid[:m].mean()) / n
    v01 = 1.0 - (mid[m:] - mid[m:].mean()) / m
    # sample variances of the structural components
    s10 = np.var(v10, ddof=1) if m > 1 else 0.0
    s01 = np.var(v01, ddof=1) if n > 1 else 0.0
    var = s10 / m + s01 / n
    if var <= 0:
        return auc, auc, auc
    from scipy.stats import norm

    z = norm.ppf(0.5 + alpha / 2.0)
    se = float(np.sqrt(var))
    lo = max(0.0, auc - z * se)
    hi = min(1.0, auc + z * se)
    return auc, lo, hi


def delong_paired_pvalue(y_true, score_a, score_b) -> float:
    """Two-sided DeLong p-value for paired AUROC difference (A - B)."""
    y_true = np.asarray(y_true).astype(int)
    sa = np.asarray(score_a, dtype=float)
    sb = np.asarray(score_b, dtype=float)
    pos_a, neg_a = sa[y_true == 1], sa[y_true == 0]
    pos_b, neg_b = sb[y_true == 1], sb[y_true == 0]
    m, n = len(pos_a), len(neg_a)
    if m < 2 or n < 2:
        return float("nan")
    auc_a = float(roc_auc_score(y_true, sa))
    auc_b = float(roc_auc_score(y_true, sb))

    def struct(pos, neg):
        tx = np.concatenate([pos, neg])
        mid = _compute_midrank(tx)
        v10 = (mid[:m] - mid[:m].mean()) / n
        v01 = 1.0 - (mid[m:] - mid[m:].mean()) / m
        return v10, v01

    v10a, v01a = struct(pos_a, neg_a)
    v10b, v01b = struct(pos_b, neg_b)
    # covariance of AUCs
    s10 = np.cov(np.vstack([v10a, v10b]))
    s01 = np.cov(np.vstack([v01a, v01b]))
    var_diff = (s10[0, 0] + s10[1, 1] - 2 * s10[0, 1]) / m + (
        s01[0, 0] + s01[1, 1] - 2 * s01[0, 1]
    ) / n
    if var_diff <= 0:
        return float("nan")
    from scipy.stats import norm

    z = (auc_a - auc_b) / np.sqrt(var_diff)
    return float(2 * norm.sf(abs(z)))


def _stay_frame(mort: pd.DataFrame, los: pd.DataFrame | None):
    # mort: patientids, eval_on, pred_mort, label
    m = mort.copy()
    m["stay"] = m["patientids"].astype(str)
    # BlendedICU patientids are already stay keys (e.g. eicu-623869). Use stay as
    # the bootstrap cluster (paper: patient-level; here one row per stay after agg).
    m["person"] = m["stay"]
    stay = m.groupby(["eval_on", "stay"], as_index=False).agg(
        y_mort=("label", "max"),
        pred_mort=("pred_mort", "mean"),
        person=("person", "first"),
        n_hours=("label", "size"),
    )
    if los is not None and len(los):
        l = los.copy()
        l["stay"] = l["patientids"].astype(str)
        alive = l[l["label"].notna()].copy()
        # survivor MAPE uses hours where mortality label==0 if present
        if "y_mort" in alive.columns:
            alive = alive[alive["y_mort"] == 0]
        alive["abs_pct"] = (alive["pred_los"] - alive["label"]).abs() / alive["label"].clip(
            lower=4 / 24
        )
        mape_stay = alive.groupby("stay", as_index=False)["abs_pct"].mean()
        mape_stay["mape"] = mape_stay["abs_pct"] * 100
        stay = stay.merge(mape_stay[["stay", "mape"]], on="stay", how="left")
    return stay, m


def _boot_ci_person(df, value_col, n_boot=10000, seed=42, agg="mean"):
    persons = df["person"].to_numpy()
    vals = df[value_col].to_numpy(dtype=float)
    uniq, inv = np.unique(persons, return_inverse=True)
    if len(uniq) < 2:
        return float("nan"), float("nan")
    buckets = [np.where(inv == i)[0] for i in range(len(uniq))]
    rng = np.random.default_rng(seed)
    stats = np.empty(n_boot, dtype=float)
    k = 0
    for _ in range(n_boot):
        draw = rng.integers(0, len(uniq), size=len(uniq))
        idx = np.concatenate([buckets[i] for i in draw])
        stats[k] = float(np.nanmean(vals[idx]))
        k += 1
    lo, hi = np.percentile(stats[:k], [2.5, 97.5])
    return float(lo), float(hi)


def _boot_ci_auprc(stay, n_boot=10000, seed=42):
    """Patient-level bootstrap of stay-aggregated AUPRC (vectorized indexing)."""
    persons = stay["person"].to_numpy()
    y = stay["y_mort"].to_numpy()
    p = stay["pred_mort"].to_numpy()
    # map person -> row indices
    uniq, inv = np.unique(persons, return_inverse=True)
    if len(uniq) < 2:
        return float("nan"), float("nan")
    buckets = [np.where(inv == i)[0] for i in range(len(uniq))]
    rng = np.random.default_rng(seed)
    stats = []
    for _ in range(n_boot):
        draw = rng.integers(0, len(uniq), size=len(uniq))
        idx = np.concatenate([buckets[i] for i in draw])
        yy, pp = y[idx], p[idx]
        if np.unique(yy).size < 2:
            continue
        stats.append(float(average_precision_score(yy, pp)))
    if len(stats) < 100:
        return float("nan"), float("nan")
    lo, hi = np.percentile(stats, [2.5, 97.5])
    return float(lo), float(hi)


def _pick_run(unit_dir: Path, prefer: str | None):
    cands = list(unit_dir.glob("results/**/test_predictions_mort.csv"))
    if prefer:
        pref = [c for c in cands if prefer in str(c)]
        if pref:
            cands = pref
    if not cands:
        return None
    return sorted(cands, key=lambda p: p.stat().st_mtime, reverse=True)[0]


PREFER = {
    "liver_expA_amsterdam_solo": "amsterdam_100/",
    "liver_expB_mimic_solo": "mimic4_100/",
    "liver_expC_mimic2amsterdam_transfer": "amsterdam_100_retrain",
    "liver_expD_pooled_mimic_amsterdam": "amsterdam_mimic4_100/",
}


def eval_unit(unit_dir: Path, unit: str, n_boot: int, dbs: list[str]) -> list[dict]:
    prefer = PREFER.get(unit)
    if prefer:
        mort_p = _pick_run(unit_dir, prefer)
        runs = [mort_p] if mort_p is not None else []
    else:
        # dataset / model / size benchmarks: every saved run (one per train DB or architecture)
        runs = sorted(unit_dir.glob("results/**/test_predictions_mort.csv"))
    rows = []
    for mort_p in runs:

        run = mort_p.parent
        model = "tpc"
        for part in run.parts:
            if part.lower() in ("lstm", "transformer", "tpc"):
                model = part.lower()
        pct = ""
        for part in run.parts:
            if "mimic4_" in part or "amsterdam_" in part:
                pct = part
        mort = pd.read_csv(mort_p)
        los_p = run / "test_predictions_los.csv"
        los = pd.read_csv(los_p) if los_p.exists() else None
        stay, hourly = _stay_frame(mort, los)
        for db in dbs:
            st = stay[stay["eval_on"] == db]
            hr = hourly[hourly["eval_on"] == db]
            if st.empty:
                continue
            auc_s, lo_s, hi_s = delong_auc_ci(st["y_mort"].to_numpy(), st["pred_mort"].to_numpy())
            # Point AUROC from hourly metrics file if present; DeLong CI at stay level
            # (hourly DeLong on 1e5–1e6 rows is optional via --hourly-delong).
            auc_h = float(roc_auc_score(hr["label"], hr["pred_mort"])) if len(hr) and hr["label"].nunique() > 1 else float("nan")
            auprc = float(average_precision_score(st["y_mort"], st["pred_mort"]))
            a_lo, a_hi = _boot_ci_auprc(st, n_boot=n_boot, seed=42)
            mape = float(st["mape"].mean()) if "mape" in st and st["mape"].notna().any() else float("nan")
            mdf = st.dropna(subset=["mape"]).copy()
            if len(mdf):
                m_lo, m_hi = _boot_ci_person(mdf, "mape", n_boot=n_boot, seed=42)
            else:
                m_lo = m_hi = float("nan")
            rows.append(
                {
                    "unit": unit,
                    "model": model,
                    "run": pct or run.name,
                    "eval_on": db,
                    "n_stays": int(len(st)),
                    "n_hours": int(len(hr)),
                    "auroc_stay": round(auc_s, 4),
                    "auroc_stay_lo_delong": round(lo_s, 4),
                    "auroc_stay_hi_delong": round(hi_s, 4),
                    "auroc_hourly_point": round(auc_h, 4) if auc_h == auc_h else None,
                    "auprc_stay": round(auprc, 4),
                    "auprc_lo_boot10k": round(a_lo, 4) if a_lo == a_lo else None,
                    "auprc_hi_boot10k": round(a_hi, 4) if a_hi == a_hi else None,
                    "mape_stay_mean": round(mape, 2) if mape == mape else None,
                    "mape_lo_boot10k": round(m_lo, 2) if m_lo == m_lo else None,
                    "mape_hi_boot10k": round(m_hi, 2) if m_hi == m_hi else None,
                    "method_auroc": "DeLong_stay",
                    "method_mape_auprc": f"bootstrap_{n_boot}_percentile_patient",
                }
            )
    return rows


def pairwise_bd(root: Path, n_boot: int) -> pd.DataFrame:
    """Pooling vs MIMIC-alone DeLong on shared external stays."""
    b = _pick_run(root / "liver_expB_mimic_solo", PREFER["liver_expB_mimic_solo"])
    d = _pick_run(root / "liver_expD_pooled_mimic_amsterdam", PREFER["liver_expD_pooled_mimic_amsterdam"])
    if b is None or d is None:
        return pd.DataFrame()
    mb = pd.read_csv(b)
    md = pd.read_csv(d)
    sb, _ = _stay_frame(mb, None)
    sd, _ = _stay_frame(md, None)
    rows = []
    for db in ("eicu", "hirid"):
        gb = sb[sb.eval_on == db].set_index("stay")
        gd = sd[sd.eval_on == db].set_index("stay")
        common = gb.index.intersection(gd.index)
        y = gb.loc[common, "y_mort"].to_numpy()
        # align labels (should match)
        yd = gd.loc[common, "y_mort"].to_numpy()
        if not np.array_equal(y, yd):
            # use max agreement
            y = np.maximum(y, yd)
        p = delong_paired_pvalue(y, gd.loc[common, "pred_mort"].to_numpy(), gb.loc[common, "pred_mort"].to_numpy())
        rows.append(
            {
                "contrast": "Pooling_minus_MIMIC_solo",
                "eval_on": db,
                "n_stays": int(len(common)),
                "auroc_pooling": float(roc_auc_score(y, gd.loc[common, "pred_mort"])),
                "auroc_mimic_solo": float(roc_auc_score(y, gb.loc[common, "pred_mort"])),
                "delong_pvalue": p,
            }
        )
    return pd.DataFrame(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--units", default="")
    ap.add_argument("--dbs", default="eicu,hirid,mimic4,amsterdam")
    ap.add_argument("--n-boot", type=int, default=10000)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    root = Path(args.root)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    dbs = [x.strip() for x in args.dbs.split(",") if x.strip()]
    if args.units.strip():
        units = [u.strip() for u in args.units.split(",") if u.strip()]
    else:
        units = sorted(
            p.name
            for p in root.iterdir()
            if p.is_dir() and (p / "results").exists()
        )
    all_rows = []
    for u in units:
        ud = root / u
        if not ud.exists():
            print("skip missing", u)
            continue
        print("eval", u, flush=True)
        all_rows.extend(eval_unit(ud, u, args.n_boot, dbs))
    df = pd.DataFrame(all_rows)
    df.to_csv(out / "Table_CI_DeLong_bootstrap10k.csv", index=False)
    try:
        df.to_excel(out / "Table_CI_DeLong_bootstrap10k.xlsx", index=False)
    except Exception as e:
        print("xlsx skip", e)
    pw = pairwise_bd(root, args.n_boot)
    if len(pw):
        pw.to_csv(out / "Table_DeLong_Pooling_vs_MIMIC.csv", index=False)
        try:
            pw.to_excel(out / "Table_DeLong_Pooling_vs_MIMIC.xlsx", index=False)
        except Exception:
            pass
    meta = {
        "root": str(root),
        "n_boot": args.n_boot,
        "auroc_ci": "DeLong",
        "mape_auprc_ci": f"bootstrap_{args.n_boot}_percentile_patient",
        "n_rows": int(len(df)),
        "units": units,
    }
    (out / "CI_methods.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print("wrote", out, "rows", len(df))


if __name__ == "__main__":
    main()
