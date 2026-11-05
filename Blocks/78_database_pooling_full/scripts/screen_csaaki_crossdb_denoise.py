#!/usr/bin/env python3
"""Cross-database denoise + UV→VIF→LASSO on Allyn pool (CSA-AKI).

Goal: remove site/DB indicator noise before pooling/transfer.

Leakage-safe for outcomes: mortality UV/LASSO use TRAIN only.
Availability gates may use eICU/INSPIRE *coverage only* (no labels).

Gates (in order):
  0) drop creatinine, urine_output; drop all medication category
  1) per-DB stay coverage on TRAIN sources:
       cov(mimic4) >= min_cov_train AND cov(sicdb) >= min_cov_train
  2) asymmetric presence (DB indicator):
       drop if max(cov_a,cov_b) >= 0.50 and min(cov_a,cov_b) < 0.05
  3) external availability (label-free):
       cov(eicu) >= min_cov_ext AND cov(inspire) >= min_cov_ext
  4) distribution shift on TRAIN (mimic vs sicdb patient means):
       drop if |SMD| >= smd_max
  5) univariate p < univ_p
  6) VIF < vif_thresh
  7) LASSO L1 (stronger Cs grid toward sparsity)
"""
from __future__ import annotations

import argparse
import json
import warnings
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats
from sklearn.linear_model import LogisticRegressionCV
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import StratifiedKFold
from sklearn.preprocessing import StandardScaler

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


def _load_split(blended: Path, job: str, split: str) -> pd.DataFrame:
    d = blended / "extraction" / job / split
    labels = pd.read_parquet(d / "labels.parquet")
    pths = pd.read_csv(d / "timeseries_pths.csv")
    lab = labels.copy()
    lab["patient"] = lab.index.astype(str)
    out = pths.merge(lab[["patient", "mortality", "source_dataset"]], on="patient", how="inner")
    if "source_dataset" not in out.columns or out["source_dataset"].isna().all():
        out["source_dataset"] = out["patient"].astype(str).str.split("-").str[0]
    return out


def _vif_series(df: pd.DataFrame) -> pd.Series:
    cols = list(df.columns)
    x = df.to_numpy(dtype=float)
    vifs = {}
    for i, c in enumerate(cols):
        y = x[:, i]
        Z = np.delete(x, i, axis=1)
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
    while len(cols) >= 2:
        v = _vif_series(df[cols])
        if float(v.max()) <= thresh:
            break
        cols = [c for c in cols if c != v.idxmax()]
    return cols


def _smd(a: np.ndarray, b: np.ndarray) -> float:
    a = a[np.isfinite(a)]
    b = b[np.isfinite(b)]
    if len(a) < 30 or len(b) < 30:
        return np.nan
    m1, m2 = a.mean(), b.mean()
    s1, s2 = a.std(ddof=1), b.std(ddof=1)
    sp = np.sqrt(((len(a) - 1) * s1**2 + (len(b) - 1) * s2**2) / (len(a) + len(b) - 2))
    if sp < 1e-8:
        return 0.0
    return float((m1 - m2) / sp)


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
        default="/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/feature_screen_crossdb_denoise",
    )
    ap.add_argument("--min-cov-train", type=float, default=0.30)
    ap.add_argument("--min-cov-ext", type=float, default=0.20)
    ap.add_argument("--smd-max", type=float, default=1.25)
    ap.add_argument("--univ-p", type=float, default=0.05)
    ap.add_argument("--vif-thresh", type=float, default=10.0)
    ap.add_argument(
        "--keep-medications",
        action="store_true",
        help="Keep medication vars (default: drop all medications as site shortcuts).",
    )
    ap.add_argument("--seed", type=int, default=974)
    args = ap.parse_args()
    args.drop_medications = not bool(args.keep_medications)

    blended = Path(args.blended_out)
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    ts = pd.read_csv(args.ts_variables, sep=";")
    cat = ts.set_index("variable")["category"].to_dict()
    cand = []
    for r in ts.itertuples(index=False):
        if int(r.keep) != 1 or r.variable in DROP_ALWAYS:
            continue
        if args.drop_medications and str(r.category) == "medication":
            continue
        cand.append(r.variable)

    train = _load_split(blended, "train_on_mimic4_sicdb", "train")
    # external availability from main job test fold (paths only; mortality unused in gates 1-4)
    test = _load_split(blended, "train_on_mimic4_sicdb", "test")

    y = train["mortality"].astype(int).to_numpy()
    train_paths = [Path(p) for p in train["ts_pth"].tolist()]
    train_db = train["source_dataset"].astype(str).to_numpy()
    test_paths = [Path(p) for p in test["ts_pth"].tolist()]
    test_db = test["source_dataset"].astype(str).to_numpy()

    print(
        f"[crossdb] train={len(train)} test={len(test)} cand={len(cand)} "
        f"min_cov_train={args.min_cov_train} min_cov_ext={args.min_cov_ext} smd_max={args.smd_max}",
        flush=True,
    )

    def values_for(paths, col):
        return np.array([_patient_mean(p, col) for p in paths], dtype=float)

    mat_train = {}
    mat_test = {}
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = {ex.submit(values_for, train_paths, c): ("train", c) for c in cand}
        futs.update({ex.submit(values_for, test_paths, c): ("test", c) for c in cand})
        for fut in as_completed(futs):
            split, c = futs[fut]
            v = fut.result()
            if split == "train":
                mat_train[c] = v
            else:
                mat_test[c] = v

    rows = []
    survivors = []
    for c in cand:
        vt = mat_train[c]
        vx = mat_test[c]
        cov = {}
        for db in ("mimic4", "sicdb"):
            m = train_db == db
            cov[db] = float(np.isfinite(vt[m]).mean()) if m.any() else 0.0
        for db in ("eicu", "inspire"):
            m = test_db == db
            cov[db] = float(np.isfinite(vx[m]).mean()) if m.any() else 0.0

        pass_train_cov = cov["mimic4"] >= args.min_cov_train and cov["sicdb"] >= args.min_cov_train
        # asymmetric among train DBs
        asym = (max(cov["mimic4"], cov["sicdb"]) >= 0.50) and (
            min(cov["mimic4"], cov["sicdb"]) < 0.05
        )
        pass_ext = cov["eicu"] >= args.min_cov_ext and cov["inspire"] >= args.min_cov_ext

        smd = _smd(vt[train_db == "mimic4"], vt[train_db == "sicdb"])
        pass_smd = (not np.isfinite(smd)) or (abs(smd) < args.smd_max)

        pass_cross = pass_train_cov and (not asym) and pass_ext and pass_smd

        p = auc = np.nan
        pass_uv = False
        if pass_cross:
            mask = np.isfinite(vt)
            if mask.sum() >= 50 and y[mask].sum() >= 5 and (y[mask] == 0).sum() >= 5:
                try:
                    auc = float(roc_auc_score(y[mask], vt[mask]))
                    p = float(
                        stats.mannwhitneyu(
                            vt[mask & (y == 1)],
                            vt[mask & (y == 0)],
                            alternative="two-sided",
                        ).pvalue
                    )
                    pass_uv = bool(p < args.univ_p)
                except Exception:
                    pass

        rec = {
            "variable": c,
            "category": cat.get(c, ""),
            "cov_mimic4": round(cov["mimic4"], 4),
            "cov_sicdb": round(cov["sicdb"], 4),
            "cov_eicu": round(cov["eicu"], 4),
            "cov_inspire": round(cov["inspire"], 4),
            "smd_mimic_sicdb": None if not np.isfinite(smd) else round(float(smd), 4),
            "pass_train_cov": pass_train_cov,
            "flag_asymmetric": asym,
            "pass_ext_cov": pass_ext,
            "pass_smd": pass_smd,
            "pass_crossdb": pass_cross,
            "univ_p": None if not np.isfinite(p) else round(float(p), 6),
            "univ_auc": None if not np.isfinite(auc) else round(float(auc), 4),
            "pass_univ": pass_uv,
            "pass_vif": False,
            "lasso_coef": np.nan,
            "selected_final": False,
        }
        rows.append(rec)
        if pass_cross and pass_uv:
            survivors.append(c)
        print(
            f"  {c}: mimic={cov['mimic4']:.2f} sic={cov['sicdb']:.2f} "
            f"eicu={cov['eicu']:.2f} insp={cov['inspire']:.2f} "
            f"smd={smd if np.isfinite(smd) else float('nan'):.2f} "
            f"cross={pass_cross} uv={pass_uv}",
            flush=True,
        )

    print(f"[after crossdb+UV] n={len(survivors)}", flush=True)
    if len(survivors) < 2:
        # relax external gate once and report
        raise SystemExit(
            "Too few variables after cross-db+UV. "
            "Consider lowering --min-cov-ext or raising --smd-max."
        )

    X = pd.DataFrame({c: mat_train[c] for c in survivors})
    for c in X.columns:
        X[c] = X[c].fillna(float(np.nanmedian(X[c].to_numpy())))

    keep_vif = iterative_vif(X, thresh=float(args.vif_thresh))
    for r in rows:
        if r["variable"] in keep_vif:
            r["pass_vif"] = True
    print(f"[VIF] n={len(keep_vif)}", flush=True)

    Xs = StandardScaler().fit_transform(X[keep_vif].to_numpy(dtype=float))
    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=args.seed)
    # Prefer sparsity: smaller C => stronger L1
    lasso = LogisticRegressionCV(
        Cs=np.logspace(-3, 1, 25),
        cv=cv,
        penalty="l1",
        solver="saga",
        scoring="roc_auc",
        max_iter=8000,
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
    if not keep_final:
        keep_final = list(keep_vif)
    for r in rows:
        if r["variable"] in coef_map:
            r["lasso_coef"] = round(coef_map[r["variable"]], 6)
        if r["variable"] in keep_final:
            r["selected_final"] = True

    print(f"[LASSO] C={lasso.C_} n={len(keep_final)} -> {keep_final}", flush=True)

    rep = pd.DataFrame(rows).sort_values(
        ["selected_final", "pass_crossdb", "pass_univ", "univ_p"],
        ascending=[False, False, False, True],
    )
    rep.to_csv(out / "FEATURE_SCREEN_CROSSDB.csv", index=False)
    (out / "csaaki_crossdb_denoise_keep_vars.txt").write_text(
        "\n".join(keep_final) + "\n", encoding="utf-8"
    )

    md = [
        "# CSA-AKI cross-database denoise screen",
        "",
        "## Gates",
        f"- drop medications: {args.drop_medications}",
        f"- train coverage mimic&sicdb ≥ {args.min_cov_train}",
        "- drop asymmetric presence (one DB ≥0.50, other <0.05)",
        f"- external coverage eicu&inspire ≥ {args.min_cov_ext} (label-free)",
        f"- |SMD|(mimic vs sicdb) < {args.smd_max}",
        f"- UV Mann–Whitney p < {args.univ_p}",
        f"- VIF < {args.vif_thresh}",
        "- LASSO L1 (Cs favoring sparsity)",
        "",
        f"- n candidates (non-med): {len(cand)}",
        f"- n crossdb+UV: {len(survivors)}",
        f"- n VIF: {len(keep_vif)}",
        f"- n final: {len(keep_final)}",
        "",
        "## Final KEEP",
        "",
    ]
    for v in keep_final:
        r = rep.loc[rep.variable == v].iloc[0]
        md.append(
            f"- `{v}` ({r.category}): "
            f"cov M/S/E/I={r.cov_mimic4}/{r.cov_sicdb}/{r.cov_eicu}/{r.cov_inspire}, "
            f"SMD={r.smd_mimic_sicdb}, p={r.univ_p}, lasso={r.lasso_coef}"
        )
    (out / "FEATURE_SCREEN_REPORT.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    (out / "FEATURE_SCREEN_META.json").write_text(
        json.dumps(
            {
                "min_cov_train": args.min_cov_train,
                "min_cov_ext": args.min_cov_ext,
                "smd_max": args.smd_max,
                "n_final": len(keep_final),
                "keep": keep_final,
                "lasso_C": float(np.asarray(lasso.C_).ravel()[0]),
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print("[done]", out, flush=True)


if __name__ == "__main__":
    main()
