#!/usr/bin/env python3
"""MinMax (fit on train) + SMOTE 1:1 for TCF (Wang 2025 / NPJ-codes).

Usage:
  python apply_smote_minmax.py --train train.csv --test test.csv --out-dir OUT \\
      --outcome y --features f1,f2,... [--k-neighbors 20] [--seed 42]

Writes:
  OUT/train_balanced.csv  (SMOTE on MinMax-scaled features; outcome + features)
  OUT/test_scaled.csv     (same MinMax; no SMOTE)
  OUT/scaler.joblib
"""
from __future__ import annotations

import argparse
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.preprocessing import MinMaxScaler

try:
    from imblearn.over_sampling import SMOTE
except ImportError as e:  # pragma: no cover
    raise SystemExit("imbalanced-learn required: pip install imbalanced-learn") from e


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train", required=True)
    ap.add_argument("--test", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--outcome", default="y")
    ap.add_argument("--features", default="")
    ap.add_argument("--k-neighbors", type=int, default=20)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    tr = pd.read_csv(args.train)
    te = pd.read_csv(args.test)
    feats = (
        [c.strip() for c in args.features.split(",") if c.strip()]
        if args.features
        else [c for c in tr.columns if c != args.outcome]
    )
    for c in feats:
        if c not in tr.columns or c not in te.columns:
            raise SystemExit(f"missing feature column: {c}")
    if args.outcome not in tr.columns:
        raise SystemExit(f"missing outcome: {args.outcome}")

    y = tr[args.outcome].astype(int).to_numpy()
    Xtr = tr[feats].astype(float).to_numpy()
    Xte = te[feats].astype(float).to_numpy()
    # median fill (train medians) so MinMax/SMOTE do not see NaN
    med = np.nanmedian(Xtr, axis=0)
    inds = np.where(np.isnan(Xtr))
    Xtr[inds] = np.take(med, inds[1])
    inds = np.where(np.isnan(Xte))
    Xte[inds] = np.take(med, inds[1])

    scaler = MinMaxScaler()
    Xtr_s = scaler.fit_transform(Xtr)
    Xte_s = scaler.transform(Xte)

    k = max(1, min(int(args.k_neighbors), max(1, int(np.bincount(y).min()) - 1)))
    sm = SMOTE(
        sampling_strategy=1.0,
        k_neighbors=k,
        random_state=int(args.seed),
    )
    Xb, yb = sm.fit_resample(Xtr_s, y)

    tr_out = pd.DataFrame(Xb, columns=feats)
    tr_out.insert(0, args.outcome, yb.astype(int))
    te_out = pd.DataFrame(Xte_s, columns=feats)
    if args.outcome in te.columns:
        te_out.insert(0, args.outcome, te[args.outcome].astype(int).to_numpy())

    tr_out.to_csv(out / "train_balanced.csv", index=False)
    te_out.to_csv(out / "test_scaled.csv", index=False)
    joblib.dump({"scaler": scaler, "features": feats, "k_neighbors": k}, out / "scaler.joblib")
    print(
        f"OK train {len(tr)}->{len(tr_out)} test={len(te_out)} "
        f"k_neighbors={k} features={len(feats)}"
    )


if __name__ == "__main__":
    main()
