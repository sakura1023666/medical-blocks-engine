#!/usr/bin/env python3
"""Train seven base classifiers + TOPSIS fusion (PMID 40295871 TCF).

Usage:
  python train_tcf_bundle.py --train train.csv --valid valid.csv --out-dir OUT \\
      --outcome y --features f1,f2,... [--smote] [--seed 42]

CSV must contain outcome (0/1) and feature columns. Scaling: MinMax fit on train.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import RandomizedSearchCV
from sklearn.naive_bayes import BernoulliNB
from sklearn.preprocessing import MinMaxScaler
from sklearn.svm import SVC
from sklearn.tree import DecisionTreeClassifier

try:
    from imblearn.over_sampling import SMOTE
except ImportError:  # pragma: no cover
    SMOTE = None

try:
    from lightgbm import LGBMClassifier
except ImportError:  # pragma: no cover
    LGBMClassifier = None

try:
    from xgboost import XGBClassifier
except ImportError:  # pragma: no cover
    XGBClassifier = None

import sys

_SYS_DIR = Path(__file__).resolve().parent
if str(_SYS_DIR) not in sys.path:
    sys.path.insert(0, str(_SYS_DIR))
from topsis import fuse_proba, topsis_model_weights  # noqa: E402


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


def _fit_search(est, grid, X, y, seed: int, cv: int = 5):
    # 文献 / NPJ-codes：RandomizedSearchCV(..., scoring='roc_auc', cv=5)
    n_cand = 1
    for v in grid.values():
        n_cand *= max(len(v), 1)
    rs = RandomizedSearchCV(
        est,
        param_distributions=grid,
        n_iter=min(40, max(10, n_cand // 2 or 10)),
        scoring="roc_auc",
        cv=int(cv),
        random_state=seed,
        n_jobs=-1,
        refit=True,
    )
    rs.fit(X, y)
    return rs.best_estimator_


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train", required=True)
    ap.add_argument("--valid", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--outcome", default="y")
    ap.add_argument("--features", default="")
    ap.add_argument("--smote", action="store_true")
    ap.add_argument("--k-neighbors", type=int, default=20)
    ap.add_argument("--cv", type=int, default=5)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--threshold", type=float, default=0.5)
    args = ap.parse_args()

    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    tr = pd.read_csv(args.train)
    va = pd.read_csv(args.valid)
    feats = (
        [c.strip() for c in args.features.split(",") if c.strip()]
        if args.features
        else [c for c in tr.columns if c != args.outcome]
    )
    ytr = tr[args.outcome].astype(int).to_numpy()
    yva = va[args.outcome].astype(int).to_numpy()
    Xtr = tr[feats].astype(float).to_numpy()
    Xva = va[feats].astype(float).to_numpy()

    scaler = MinMaxScaler()
    Xtr_s = scaler.fit_transform(Xtr)
    Xva_s = scaler.transform(Xva)
    if args.smote:
        if SMOTE is None:
            raise SystemExit("imblearn not installed; pip install imbalanced-learn")
        # NPJ-codes: SMOTE(sampling_strategy=1, k_neighbors=20)
        k = max(1, min(int(args.k_neighbors), max(1, int(np.bincount(ytr).min()) - 1)))
        Xtr_s, ytr = SMOTE(
            sampling_strategy=1.0,
            k_neighbors=k,
            random_state=args.seed,
        ).fit_resample(Xtr_s, ytr)

    models = {}
    # 网格贴近公开 notebook（GBDT）并覆盖七模型；cv 默认 5
    grids = {
        "DT": (
            DecisionTreeClassifier(random_state=args.seed),
            {
                "criterion": ["gini", "entropy"],
                "max_depth": list(range(2, 21)),
                "min_samples_leaf": [5, 10, 20, 30],
                "min_samples_split": list(range(2, 21, 2)),
            },
        ),
        "RF": (
            RandomForestClassifier(random_state=args.seed, n_jobs=-1),
            {
                "n_estimators": list(range(10, 100, 10)),
                "max_depth": list(range(2, 21)),
                "min_samples_leaf": list(range(20, 50, 5)),
                "max_features": ["sqrt", "log2"],
            },
        ),
        "SVM": (
            SVC(probability=True, random_state=args.seed),
            {"C": [0.1, 1, 10], "kernel": ["rbf"], "gamma": ["scale", "auto"]},
        ),
        "NB": (BernoulliNB(), {"alpha": [0.1, 0.5, 1.0]}),
        "GBDT": (
            GradientBoostingClassifier(random_state=args.seed),
            {
                "n_estimators": list(range(10, 100, 10)),
                "learning_rate": [0.01, 0.05, 0.1],
                "max_depth": list(range(2, 20)),
                "subsample": [0.4, 0.5, 0.6, 0.7, 0.8],
                "min_samples_split": list(range(2, 20, 2)),
                "min_samples_leaf": list(range(20, 50, 5)),
                "max_features": ["sqrt", "log2"],
            },
        ),
    }
    if XGBClassifier is not None:
        grids["XGB"] = (
            XGBClassifier(
                random_state=args.seed,
                eval_metric="logloss",
                use_label_encoder=False,
            ),
            {
                "n_estimators": list(range(10, 100, 10)),
                "max_depth": list(range(2, 12)),
                "learning_rate": [0.01, 0.05, 0.1],
                "subsample": [0.5, 0.7, 0.9],
            },
        )
    if LGBMClassifier is not None:
        grids["LGBM"] = (
            LGBMClassifier(random_state=args.seed),
            {
                "n_estimators": list(range(10, 100, 10)),
                "num_leaves": [15, 31, 63, 127],
                "learning_rate": [0.01, 0.05, 0.1],
                "subsample": [0.5, 0.7, 0.9],
            },
        )

    metric_rows = {}
    proba_valid = {}
    for name, (est, grid) in grids.items():
        clf = _fit_search(est, grid, Xtr_s, ytr, args.seed, cv=int(args.cv))
        models[name] = clf
        pv = clf.predict_proba(Xva_s)[:, 1]
        pred = (pv > args.threshold).astype(int)
        metric_rows[name] = _metrics(yva, pv, pred)
        proba_valid[name] = pv
        joblib.dump(clf, out / f"model_{name}.joblib")

    metric_df = pd.DataFrame(metric_rows).T[
        ["AUC", "F1", "ACC", "PRE", "SEN", "SPE"]
    ]
    alpha = topsis_model_weights(metric_df, equal_weight=True)
    # align alpha index to models present
    alpha = alpha.reindex(list(proba_valid.keys())).fillna(0.0)
    alpha = alpha / alpha.sum()
    p_tcf, y_tcf = fuse_proba(proba_valid, alpha, threshold=args.threshold)
    metric_df.loc["TCF"] = _metrics(yva, p_tcf, y_tcf)

    metric_df.to_csv(out / "metrics_valid.csv")
    alpha.to_csv(out / "topsis_alpha.csv", header=True)
    joblib.dump(scaler, out / "minmax_scaler.joblib")
    pd.Series(feats).to_csv(out / "features.csv", index=False, header=False)
    with open(out / "tcf_summary.json", "w", encoding="utf-8") as f:
        json.dump(
            {
                "alpha": alpha.to_dict(),
                "metrics_valid": metric_df.to_dict(orient="index"),
                "threshold": args.threshold,
                "n_train": int(len(ytr)),
                "n_valid": int(len(yva)),
                "features": feats,
            },
            f,
            indent=2,
            ensure_ascii=False,
        )
    print(metric_df)
    print("alpha:\n", alpha)


if __name__ == "__main__":
    main()
