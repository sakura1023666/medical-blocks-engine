"""TabNet binary fit/predict for one CV fold (called from R nested CV).

Usage:
  python ml_tabnet_fit_predict.py \\
    --x-train train.csv --y-train y_train.csv \\
    --x-test test.csv --out-pred pred.csv \\
    [--seed 1] [--max-epochs 80] [--patience 15] [--batch-size 128]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd


def parse_args():
    p = argparse.ArgumentParser(description="TabNet single-fold fit/predict")
    p.add_argument("--x-train", required=True)
    p.add_argument("--y-train", required=True)
    p.add_argument("--x-test", required=True)
    p.add_argument("--out-pred", required=True)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--max-epochs", type=int, default=80)
    p.add_argument("--patience", type=int, default=15)
    p.add_argument("--batch-size", type=int, default=128)
    p.add_argument("--virtual-batches", type=int, default=128)
    return p.parse_args()


def main() -> int:
    args = parse_args()
    try:
        from pytorch_tabnet.tab_model import TabNetClassifier
    except ImportError as exc:
        print("pytorch-tabnet not installed:", exc, file=sys.stderr)
        return 2

    x_tr = pd.read_csv(args.x_train).to_numpy(dtype=np.float32)
    y_tr = pd.read_csv(args.y_train).iloc[:, 0].to_numpy(dtype=np.int64)
    x_te = pd.read_csv(args.x_test).to_numpy(dtype=np.float32)

    if x_tr.ndim != 2 or x_te.ndim != 2:
        raise ValueError("x matrices must be 2D")
    if len(np.unique(y_tr)) < 2:
        raise ValueError("y_train needs two classes")

    n_features = x_tr.shape[1]
    batch_size = min(args.batch_size, max(8, x_tr.shape[0]))
    vbs = min(args.virtual_batches, max(batch_size, x_tr.shape[0]))

    clf = TabNetClassifier(
        seed=args.seed,
        verbose=0,
        n_d=min(16, max(8, n_features // 2)),
        n_a=min(16, max(8, n_features // 2)),
        n_steps=3,
        gamma=1.3,
        lambda_sparse=1e-4,
        optimizer_params=dict(lr=2e-2),
        mask_type="sparsemax",
    )
    clf.fit(
        x_tr,
        y_tr,
        eval_set=[(x_tr, y_tr)],
        eval_metric=["auc"],
        max_epochs=args.max_epochs,
        patience=args.patience,
        batch_size=batch_size,
        virtual_batch_size=vbs,
        num_workers=0,
        drop_last=False,
    )
    pred = clf.predict_proba(x_te)[:, 1].astype(float)
    out = Path(args.out_pred)
    out.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame({"pred": pred}).to_csv(out, index=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
