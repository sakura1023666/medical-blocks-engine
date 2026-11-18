#!/usr/bin/env python3
"""Train-only feature screen on Allyn BlendedLoS pool (CSA-AKI).

Leakage-safe: ONLY extraction/train_on_mimic4_sicdb/train (no val/test).
Always drops inclusion features: creatinine, urine_output.

Gates:
  1) stay-level coverage >= min_coverage
  2) keep top_k by |univ_auc - 0.5| (patient-level mean vs mortality)
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import roc_auc_score

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
        default="/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/feature_screen_allyn",
    )
    ap.add_argument("--min-coverage", type=float, default=0.20)
    ap.add_argument("--top-k", type=int, default=20)
    ap.add_argument("--max-stays", type=int, default=0)
    ap.add_argument("--seed", type=int, default=974)
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
    # labels index = stay id (patient), e.g. mimic4-30001148
    lab_idx = labels.copy()
    lab_idx["patient"] = lab_idx.index.astype(str)
    lab = pths.merge(
        lab_idx[["patient", "mortality"]],
        on="patient",
        how="inner",
    )
    if "mortality" not in lab.columns or lab.empty:
        raise SystemExit(f"merge failed cols={lab.columns.tolist()} n={len(lab)}")

    if args.max_stays and args.max_stays < len(lab):
        lab = lab.sample(n=args.max_stays, random_state=args.seed).reset_index(drop=True)

    y = lab["mortality"].astype(int).to_numpy()
    paths = [Path(p) for p in lab["ts_pth"].tolist()]
    n = len(paths)
    print(f"[screen] train stays={n} mort={y.mean():.4f} candidates={len(cand)}", flush=True)

    from concurrent.futures import ThreadPoolExecutor, as_completed

    def _score_one(col: str):
        vals = np.array([_patient_mean(p, col) for p in paths], dtype=float)
        cov = float(np.isfinite(vals).mean())
        mask = np.isfinite(vals)
        auc = np.nan
        n_used = int(mask.sum())
        if (
            cov >= args.min_coverage
            and n_used >= 50
            and y[mask].sum() >= 5
            and (y[mask] == 0).sum() >= 5
        ):
            try:
                auc = float(roc_auc_score(y[mask], vals[mask]))
            except ValueError:
                auc = np.nan
        return {
            "variable": col,
            "category": cat.get(col, ""),
            "coverage": round(cov, 4),
            "n_non_null_stays": n_used,
            "univ_auc": None if not np.isfinite(auc) else round(auc, 4),
            "abs_auc_edge": None if not np.isfinite(auc) else round(abs(auc - 0.5), 4),
            "pass_coverage": bool(cov >= args.min_coverage),
        }

    rows = []
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = {ex.submit(_score_one, c): c for c in cand}
        for fut in as_completed(futs):
            r = fut.result()
            rows.append(r)
            print(
                f"  {r['variable']}: cov={r['coverage']:.3f} auc={r['univ_auc']}",
                flush=True,
            )

    rep = pd.DataFrame(rows).sort_values(
        ["pass_coverage", "abs_auc_edge", "coverage"],
        ascending=[False, False, False],
        na_position="last",
    )
    rep.to_csv(out / "FEATURE_SCREEN_REPORT.csv", index=False)

    passed = rep[rep["pass_coverage"] & rep["univ_auc"].notna()].copy()
    keep = passed.head(int(args.top_k))["variable"].tolist()
    (out / "csaaki_screened_keep_vars.txt").write_text("\n".join(keep) + "\n", encoding="utf-8")

    md = [
        "# CSA-AKI Allyn-pool feature screen (train-only)",
        "",
        f"- train stays: {n} (`train_on_mimic4_sicdb/train`)",
        f"- min_coverage: {args.min_coverage}",
        f"- top_k: {args.top_k}",
        f"- always drop: {sorted(DROP_ALWAYS - {'time','hour'})}",
        f"- Allyn keep=1 candidates: {len(cand)}",
        f"- pass coverage: {int(rep['pass_coverage'].sum())}",
        f"- final keep: {len(keep)}",
        "",
        "## Kept (ranked by |AUROC-0.5|)",
        "",
    ]
    for v in keep:
        r = rep.loc[rep.variable == v].iloc[0]
        md.append(f"- `{v}` ({r.category}): coverage={r.coverage:.3f}, univ_auc={r.univ_auc}")
    md += [
        "",
        "## Method",
        "Patient-level mean of hourly values; univariate AUROC vs ICU mortality; TRAIN only.",
        "Then TPC retrained with DBPOOL_KEEP_TS=this list (third arm).",
        "",
    ]
    (out / "FEATURE_SCREEN_REPORT.md").write_text("\n".join(md), encoding="utf-8")
    (out / "FEATURE_SCREEN_META.json").write_text(
        json.dumps(
            {
                "n_train_stays": n,
                "min_coverage": args.min_coverage,
                "top_k": args.top_k,
                "n_keep": len(keep),
                "keep": keep,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print("[screen] kept", keep, flush=True)
    print("[screen] wrote", out, flush=True)


if __name__ == "__main__":
    main()
