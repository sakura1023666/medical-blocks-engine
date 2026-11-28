#!/usr/bin/env python3
"""Recompute metrics on the stays scored by every arm that evaluates that database."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import roc_auc_score

ROOT = Path("/mnt/sda/BlendedICU/data/cirrhosis_dzx_42151996/Output_database_pooling")
UNITS = [
    "cirr_expA_nwicu_solo",
    "cirr_expB_mimic_solo",
    "cirr_expC_mimic2nwicu_transfer",
    "cirr_expD_pooled_mimic_nwicu",
]


def _boot_ci(df, stat_fn, n_boot=1000, seed=974):
    persons = df["person"].drop_duplicates().to_numpy()
    if len(persons) < 2:
        return np.nan, np.nan
    groups = {p: g for p, g in df.groupby("person")}
    rng = np.random.default_rng(seed)
    stats = []
    for _ in range(n_boot):
        draw = rng.choice(persons, size=len(persons), replace=True)
        part = pd.concat([groups[p] for p in draw], axis=0)
        try:
            stats.append(float(stat_fn(part)))
        except ValueError:
            continue
    if len(stats) < 50:
        return np.nan, np.nan
    lo, hi = np.percentile(stats, [2.5, 97.5])
    return float(lo), float(hi)


def _one(df, arm, eval_on):
    g = df
    hourly = float(roc_auc_score(g["y_mort"], g["y_hat_mort"]))
    alive = g[g["y_mort"] == 0]
    mape = float(
        ((alive["y_los"] - alive["y_hat_los"]).abs() / alive["y_los"].clip(lower=4 / 24)).mean()
        * 100
    )
    stay = g.groupby("stay").agg(y=("y_mort", "max"), p=("y_hat_mort", "mean"))
    stay_auc = float(roc_auc_score(stay["y"], stay["p"]))

    def stat_hour(part):
        if part["y_mort"].nunique() < 2:
            raise ValueError("one class")
        return roc_auc_score(part["y_mort"], part["y_hat_mort"])

    def stat_stay(part):
        st = part.groupby("stay").agg(y=("y_mort", "max"), p=("y_hat_mort", "mean"))
        if st["y"].nunique() < 2:
            raise ValueError("one class")
        return roc_auc_score(st["y"], st["p"])

    h_lo, h_hi = _boot_ci(g, stat_hour)
    s_lo, s_hi = _boot_ci(g, stat_stay)
    return {
        "arm": arm,
        "eval_on": eval_on,
        "n_hours": int(len(g)),
        "n_stays": int(g["stay"].nunique()),
        "n_persons": int(g["person"].nunique()),
        "auc_hourly": hourly,
        "auc_hourly_lo": h_lo,
        "auc_hourly_hi": h_hi,
        "auc_stay": stay_auc,
        "auc_stay_lo": s_lo,
        "auc_stay_hi": s_hi,
        "mape_hourly": mape,
    }


def main():
    frames = []
    for unit in UNITS:
        folder = ROOT / unit / "reeval_full_test"
        for p in sorted(folder.glob("*_predictions.parquet")):
            df = pd.read_parquet(p)
            df["arm"] = p.name.replace("_predictions.parquet", "")
            frames.append(df)
    if not frames:
        raise SystemExit("no prediction parquet files")
    all_df = pd.concat(frames, ignore_index=True)
    rows = []
    for db, sub in all_df.groupby("eval_on"):
        sets = [set(g["stay"]) for _, g in sub.groupby("arm")]
        common = set.intersection(*sets)
        print(f"{db}: arms={sub['arm'].nunique()} common_stays={len(common)}")
        for arm, g in sub.groupby("arm"):
            rows.append(_one(g[g["stay"].isin(common)].copy(), arm, db))
    out = pd.DataFrame(rows).sort_values(["eval_on", "arm"])
    dest = ROOT / "reeval_full_test_common.csv"
    out.to_csv(dest, index=False)
    print(out.to_string(index=False))
    print(dest)


if __name__ == "__main__":
    sys.exit(main())
