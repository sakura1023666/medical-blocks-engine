#!/usr/bin/env python3
"""Apply frozen TCF sklearn models (joblib) + MIMIC TOPSIS alpha to external CSV.

Usage:
  python eval_external_tcf.py --model-dir MIMIC/Models/TCF_sklearn \\
      --external ext.csv --outcome y --out-dir OUT
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)

import sys

_SYS_DIR = Path(__file__).resolve().parent
if str(_SYS_DIR) not in sys.path:
    sys.path.insert(0, str(_SYS_DIR))
from topsis import fuse_proba  # noqa: E402


def _metrics(y_true, y_prob, y_pred) -> dict:
    return {
        "AUC": float(roc_auc_score(y_true, y_prob)),
        "F1": float(f1_score(y_true, y_pred, zero_division=0)),
        "ACC": float(accuracy_score(y_true, y_pred)),
        "PRE": float(precision_score(y_true, y_pred, zero_division=0)),
        "SEN": float(recall_score(y_true, y_pred, zero_division=0)),
        "SPE": float(
            recall_score(1 - np.asarray(y_true), 1 - np.asarray(y_pred), zero_division=0)
        ),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model-dir", required=True)
    ap.add_argument("--external", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--outcome", default="y")
    ap.add_argument("--threshold", type=float, default=None)
    args = ap.parse_args()

    md = Path(args.model_dir)
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    with open(md / "tcf_summary.json", encoding="utf-8") as f:
        summary = json.load(f)
    feats = summary["features"]
    alpha = pd.Series(summary["alpha"], dtype=float)
    thr = float(args.threshold if args.threshold is not None else summary.get("threshold", 0.5))
    scaler = joblib.load(md / "minmax_scaler.joblib")

    ext = pd.read_csv(args.external)
    y = ext[args.outcome].astype(int).to_numpy()
    X = ext[feats].astype(float).to_numpy()
    Xs = scaler.transform(X)

    proba = {}
    rows = {}
    for name in alpha.index:
        path = md / f"model_{name}.joblib"
        if not path.exists():
            continue
        clf = joblib.load(path)
        pv = clf.predict_proba(Xs)[:, 1]
        pred = (pv > thr).astype(int)
        proba[name] = pv
        rows[name] = _metrics(y, pv, pred)
        pd.DataFrame({"prob": pv}).to_csv(out / f"proba_{name}.csv", index=False)

    alpha = alpha.reindex(list(proba.keys())).fillna(0.0)
    alpha = alpha / alpha.sum()
    p_tcf, y_tcf = fuse_proba(proba, alpha, threshold=thr)
    rows["TCF"] = _metrics(y, p_tcf, y_tcf)
    metric_df = pd.DataFrame(rows).T[["AUC", "F1", "ACC", "PRE", "SEN", "SPE"]]
    metric_df.to_csv(out / "metrics_external.csv")
    alpha.rename("alpha").reset_index().rename(columns={"index": "model"}).to_csv(
        out / "topsis_alpha_used.csv", index=False
    )
    pd.DataFrame({"prob": p_tcf}).to_csv(out / "proba_TCF.csv", index=False)
    with open(out / "external_summary.json", "w", encoding="utf-8") as f:
        json.dump(
            {
                "n": int(len(y)),
                "event_rate": float(y.mean()),
                "metrics": metric_df.to_dict(orient="index"),
                "alpha": alpha.to_dict(),
                "threshold": thr,
                "note": "alpha frozen from development; not re-fit on external",
            },
            f,
            indent=2,
            ensure_ascii=False,
        )
    print(metric_df)


if __name__ == "__main__":
    main()
