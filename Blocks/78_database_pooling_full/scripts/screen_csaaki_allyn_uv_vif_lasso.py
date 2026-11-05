#!/usr/bin/env python3
"""Allyn-pool feature screen: missingness gate → univariate → VIF → LASSO.

Train-only (train_on_mimic4_sicdb/train). Always drops creatinine & urine_output.

Defaults (ICU hourly → patient mean):
  - max_missing = 0.50  (only variables with stay-level missing ≤ 50% enter UV)
  - univ_p < 0.05       (logistic Wald / fallback Mann-Whitney)
  - VIF < 10            (iterative drop highest VIF)
  - LASSO L1 logistic   (CV on train; keep |coef| > 0)

Outputs under --out-dir:
  FEATURE_SCREEN_STEPS.csv, FEATURE_SCREEN_REPORT.md,
  csaaki_uv_vif_lasso_keep_vars.txt, FEATURE_SCREEN_META.json
"""
from __future__ import annotations

import argparse
import json
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression, LogisticRegressionCV
from sklearn.metrics import roc_auc_score
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import StratifiedKFold

DROP_ALWAYS = {"creatinine", "urine_output", "time", "hour"}


def _patient_mean(path: Path, col: str) -> float:
    try:
        df = pd.read_parquet(path, columns=[col])
    except Exception:
        return np.nan
    if col not in df.columns:
        return np.nan
    s = pd.to_numeric(df[col], errors="coerce")
    if s.notna().sum() == 0:
        return np.nan
    return float(s.mean())


def _univ_p_auc(x: np.ndarray, y: np.ndarray) -> tuple[float, float]:
    """Return (p_value, auc). Higher x vs mortality via logistic if possible."""
    mask = np.isfinite(x)
    if mask.sum() < 50 or y[mask].sum() < 5 or (y[mask] == 0).sum() < 5:
        return np.nan, np.nan
    xx = x[mask].reshape(-1, 1)
    yy = y[mask].astype(int)
    try:
        auc = float(roc_auc_score(yy, xx.ravel()))
    except ValueError:
        auc = np.nan
    p = np.nan
    try:
        clf = LogisticRegression(penalty=None, solver="lbfgs", max_iter=2000)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            clf.fit(xx, yy)
        # Wald via statsmodels if available; else use coef/se bootstrap-ish from sklearn none
        # Use likelihood ratio via null comparison roughly: scipy
        from scipy import stats

        # simple two-sample on ranks as robust p (direction-free screen)
        p = float(stats.mannwhitneyu(xx[yy == 1].ravel(), xx[yy == 0].ravel(), alternative="two-sided").pvalue)
    except Exception:
        p = np.nan
    return p, auc


def _vif_series(df: pd.DataFrame) -> pd.Series:
    cols = list(df.columns)
    vifs = {}
    x = df.to_numpy(dtype=float)
    for i, c in enumerate(cols):
        y = x[:, i]
        Z = np.delete(x, i, axis=1)
        # add intercept
        Z = np.column_stack([np.ones(len(Z)), Z])
        try:
            beta, *_ = np.linalg.lstsq(Z, y, rcond=None)
            pred = Z @ beta
            ss_res = float(np.sum((y - pred) ** 2))
            ss_tot = float(np.sum((y - y.mean()) ** 2))
            r2 = 1.0 - ss_res / ss_tot if ss_tot > 0 else 1.0
            r2 = min(max(r2, 0.0), 0.999999)
            vifs[c] = 1.0 / (1.0 - r2)
        except Exception:
            vifs[c] = np.inf
    return pd.Series(vifs)


def iterative_vif(df: pd.DataFrame, thresh: float = 10.0) -> list[str]:
    cols = list(df.columns)
    dropped = []
    while len(cols) >= 2:
        v = _vif_series(df[cols])
        worst = v.idxmax()
        if float(v.max()) <= thresh:
            break
        dropped.append((worst, float(v.max())))
        cols = [c for c in cols if c != worst]
    return cols


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--blended-out",
        default="/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/blendedlos_csaaki",
    )
    ap.add_argument(
        "--ts-variables",
        default="/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/Output_database_pooling/csa_expD_pooled_mimic_sicdb/ts_variables.csv",
    )
    ap.add_argument(
        "--out-dir",
        default="/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/feature_screen_uv_vif_lasso",
    )
    ap.add_argument(
        "--max-missing",
        type=float,
        default=0.50,
        help="Only variables with stay-level missing rate <= this enter UV (default 0.50).",
    )
    ap.add_argument("--univ-p", type=float, default=0.05)
    ap.add_argument("--vif-thresh", type=float, default=10.0)
    ap.add_argument("--lasso-Cs", type=int, default=20)
    ap.add_argument("--seed", type=int, default=974)
    ap.add_argument("--max-stays", type=int, default=0)
    args = ap.parse_args()

    blended = Path(args.blended_out)
    train = blended / "extraction" / "train_on_mimic4_sicdb" / "train"
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    ts = pd.read_csv(args.ts_variables, sep=";")
    cand = [
        r.variable
        for r in ts.itertuples(index=False)
        if int(r.keep) == 1 and r.variable not in DROP_ALWAYS
    ]
    cat = ts.set_index("variable")["category"].to_dict()

    labels = pd.read_parquet(train / "labels.parquet")
    pths = pd.read_csv(train / "timeseries_pths.csv")
    lab_idx = labels.copy()
    lab_idx["patient"] = lab_idx.index.astype(str)
    lab = pths.merge(lab_idx[["patient", "mortality"]], on="patient", how="inner")
    if args.max_stays and args.max_stays < len(lab):
        lab = lab.sample(n=args.max_stays, random_state=args.seed).reset_index(drop=True)

    y = lab["mortality"].astype(int).to_numpy()
    paths = [Path(p) for p in lab["ts_pth"].tolist()]
    n = len(paths)
    print(
        f"[uv-vif-lasso] n={n} mort={y.mean():.4f} cand={len(cand)} "
        f"max_missing={args.max_missing}",
        flush=True,
    )

    # Build matrix
    from concurrent.futures import ThreadPoolExecutor, as_completed

    def _col_values(col: str) -> tuple[str, np.ndarray]:
        vals = np.array([_patient_mean(p, col) for p in paths], dtype=float)
        return col, vals

    mat = {}
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = [ex.submit(_col_values, c) for c in cand]
        for fut in as_completed(futs):
            c, v = fut.result()
            mat[c] = v
            miss = float(np.mean(~np.isfinite(v)))
            print(f"  loaded {c}: missing={miss:.3f}", flush=True)

    Xdf = pd.DataFrame(mat)
    step_rows = []

    # Gate 1: missingness
    keep_miss = []
    for c in Xdf.columns:
        miss = float(np.mean(~np.isfinite(Xdf[c].to_numpy())))
        ok = miss <= args.max_missing
        step_rows.append(
            {
                "variable": c,
                "category": cat.get(c, ""),
                "missing_rate": round(miss, 4),
                "pass_missing": ok,
                "univ_p": np.nan,
                "univ_auc": np.nan,
                "pass_univ": False,
                "pass_vif": False,
                "lasso_coef": np.nan,
                "selected_final": False,
            }
        )
        if ok:
            keep_miss.append(c)
    print(f"[gate1 missing≤{args.max_missing}] pass={len(keep_miss)}/{len(Xdf.columns)}", flush=True)

    # Gate 2: univariate
    keep_uv = []
    for c in keep_miss:
        p, auc = _univ_p_auc(Xdf[c].to_numpy(), y)
        for r in step_rows:
            if r["variable"] == c:
                r["univ_p"] = None if not np.isfinite(p) else round(float(p), 6)
                r["univ_auc"] = None if not np.isfinite(auc) else round(float(auc), 4)
                r["pass_univ"] = bool(np.isfinite(p) and p < args.univ_p)
        if np.isfinite(p) and p < args.univ_p:
            keep_uv.append(c)
        print(f"  UV {c}: p={p if np.isfinite(p) else float('nan'):.4g} auc={auc if np.isfinite(auc) else float('nan'):.3f}", flush=True)
    print(f"[gate2 univ p<{args.univ_p}] pass={len(keep_uv)}", flush=True)

    if len(keep_uv) < 2:
        raise SystemExit(f"too few UV vars: {keep_uv}")

    # Impute median for VIF/LASSO on UV set (train only)
    Xu = Xdf[keep_uv].copy()
    for c in Xu.columns:
        med = float(np.nanmedian(Xu[c].to_numpy()))
        Xu[c] = Xu[c].fillna(med)

    # Gate 3: VIF
    keep_vif = iterative_vif(Xu, thresh=float(args.vif_thresh))
    for r in step_rows:
        if r["variable"] in keep_vif:
            r["pass_vif"] = True
    print(f"[gate3 VIF<{args.vif_thresh}] pass={len(keep_vif)} dropped={sorted(set(keep_uv)-set(keep_vif))}", flush=True)

    # Gate 4: LASSO
    Xv = Xu[keep_vif].to_numpy(dtype=float)
    scaler = StandardScaler()
    Xs = scaler.fit_transform(Xv)
    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=args.seed)
    lasso = LogisticRegressionCV(
        Cs=args.lasso_Cs,
        cv=cv,
        penalty="l1",
        solver="saga",
        scoring="roc_auc",
        max_iter=5000,
        n_jobs=4,
        random_state=args.seed,
        refit=True,
    )
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        lasso.fit(Xs, y)
    coefs = lasso.coef_.ravel()
    keep_final = [c for c, b in zip(keep_vif, coefs) if abs(float(b)) > 1e-8]
    coef_map = {c: float(b) for c, b in zip(keep_vif, coefs)}
    for r in step_rows:
        if r["variable"] in coef_map:
            r["lasso_coef"] = round(coef_map[r["variable"]], 6)
        if r["variable"] in keep_final:
            r["selected_final"] = True

    # fallback if LASSO zeros everything: keep VIF set
    if not keep_final:
        print("[warn] LASSO selected 0; fallback to VIF set", flush=True)
        keep_final = list(keep_vif)
        for r in step_rows:
            if r["variable"] in keep_final:
                r["selected_final"] = True

    print(f"[gate4 LASSO] selected={len(keep_final)} C={lasso.C_}", flush=True)
    print("[final]", keep_final, flush=True)

    rep = pd.DataFrame(step_rows).sort_values(
        ["selected_final", "pass_vif", "pass_univ", "pass_missing", "univ_p"],
        ascending=[False, False, False, False, True],
    )
    rep.to_csv(out / "FEATURE_SCREEN_STEPS.csv", index=False)
    (out / "csaaki_uv_vif_lasso_keep_vars.txt").write_text("\n".join(keep_final) + "\n", encoding="utf-8")

    md = [
        "# CSA-AKI Allyn-pool screen: missing → UV → VIF → LASSO",
        "",
        f"- train stays: {n} (train_on_mimic4_sicdb/train only)",
        f"- max_missing (stay-level): **{args.max_missing}** (missing_rate = 1 - coverage)",
        f"- univariate: Mann–Whitney p < {args.univ_p}",
        f"- VIF threshold: {args.vif_thresh} (iterative)",
        f"- LASSO: L1 LogisticRegressionCV, keep nonzero coef",
        f"- always drop: creatinine, urine_output",
        f"- n pass missing: {len(keep_miss)}",
        f"- n pass UV: {len(keep_uv)}",
        f"- n pass VIF: {len(keep_vif)}",
        f"- n final LASSO: {len(keep_final)}",
        "",
        "## Final KEEP",
        "",
    ]
    for v in keep_final:
        r = rep.loc[rep.variable == v].iloc[0]
        md.append(
            f"- `{v}` ({r.category}): miss={r.missing_rate}, p={r.univ_p}, auc={r.univ_auc}, lasso={r.lasso_coef}"
        )
    md += [
        "",
        "## Why not top-20",
        "Fixed top-K is arbitrary; UV→VIF→LASSO follows the project assoc gate logic and lets the data decide dimension.",
        "",
    ]
    (out / "FEATURE_SCREEN_REPORT.md").write_text("\n".join(md), encoding="utf-8")
    (out / "FEATURE_SCREEN_META.json").write_text(
        json.dumps(
            {
                "n_train": n,
                "max_missing": args.max_missing,
                "univ_p": args.univ_p,
                "vif_thresh": args.vif_thresh,
                "n_miss_pass": len(keep_miss),
                "n_uv_pass": len(keep_uv),
                "n_vif_pass": len(keep_vif),
                "n_final": len(keep_final),
                "lasso_C": float(np.asarray(lasso.C_).ravel()[0]),
                "keep": keep_final,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print("[done]", out, flush=True)


if __name__ == "__main__":
    main()
