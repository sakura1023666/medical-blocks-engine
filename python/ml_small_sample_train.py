"""Train TabPFN/CatBoost/XGBoost/LightGBM/AdaBoost with repeated stratified CV + hold-out.

Outputs ml_python_results.csv: model, idx, y, p, split (oof|val).

Usage:
  python ml_small_sample_train.py --matrix path/to/ml_matrix.csv --out path/to/ml_python_results.csv
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import RepeatedStratifiedKFold


def parse_args():
    p = argparse.ArgumentParser(description="Small-sample ML Python models (5x10 CV + val)")
    p.add_argument("--matrix", required=True, help="CSV with y, split, feature columns")
    p.add_argument("--out", required=True, help="Output ml_python_results.csv")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--cv-folds", type=int, default=5)
    p.add_argument("--cv-repeats", type=int, default=10)
    p.add_argument("--split-train", default="train")
    p.add_argument("--split-val", default="val")
    p.add_argument(
        "--tabpfn-ckpt",
        default=None,
        help="TabPFN checkpoint; default %APPDATA%/tabpfn/tabpfn-v2-classifier-finetuned-zk73skhh.ckpt",
    )
    return p.parse_args()


def model_factories(seed: int, ckpt: Path):
    def make_tabpfn():
        from tabpfn import TabPFNClassifier

        return TabPFNClassifier(
            model_path=str(ckpt),
            device="cpu",
            ignore_pretraining_limits=True,
            random_state=seed,
        )

    def make_catboost():
        from catboost import CatBoostClassifier

        return CatBoostClassifier(
            iterations=200,
            depth=4,
            learning_rate=0.05,
            eval_metric="AUC",
            random_seed=seed,
            verbose=0,
            allow_writing_files=False,
        )

    def make_xgb():
        from xgboost import XGBClassifier

        return XGBClassifier(
            n_estimators=200,
            max_depth=3,
            learning_rate=0.05,
            use_label_encoder=False,
            eval_metric="logloss",
            random_state=seed,
            verbosity=0,
        )

    def make_lgbm():
        from lightgbm import LGBMClassifier

        return LGBMClassifier(
            n_estimators=200,
            num_leaves=15,
            learning_rate=0.05,
            random_state=seed,
            verbose=-1,
        )

    def make_ada():
        from sklearn.ensemble import AdaBoostClassifier

        return AdaBoostClassifier(n_estimators=100, random_state=seed)

    return [
        ("TabPFN", make_tabpfn),
        ("CatBoost", make_catboost),
        ("XGBoost", make_xgb),
        ("LightGBM", make_lgbm),
        ("AdaBoost", make_ada),
    ]


def main():
    args = parse_args()
    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    os.environ.setdefault("TABPFN_ALLOW_CPU_LARGE_DATASET", "1")
    appdata = os.environ.get("APPDATA", "")
    ckpt = Path(args.tabpfn_ckpt) if args.tabpfn_ckpt else (
        Path(appdata) / "tabpfn" / "tabpfn-v2-classifier-finetuned-zk73skhh.ckpt"
    )

    df = pd.read_csv(args.matrix)
    feats = [c for c in df.columns if c not in ("y", "split")]
    tr = df[df["split"] == args.split_train].reset_index(drop=True)
    va = df[df["split"] == args.split_val].reset_index(drop=True)
    X_tr = tr[feats].to_numpy(dtype=float)
    y_tr = tr["y"].to_numpy(int)
    X_va = va[feats].to_numpy(dtype=float)
    y_va = va["y"].to_numpy(int)

    print(f"Features: {feats}")
    print(f"Train: {len(y_tr)} (events={y_tr.sum()})  Val: {len(y_va)} (events={y_va.sum()})")

    models = model_factories(args.seed, ckpt)
    cv = RepeatedStratifiedKFold(
        n_splits=args.cv_folds, n_repeats=args.cv_repeats, random_state=args.seed
    )
    all_rows = []

    for name, factory in models:
        print(f"\n== {name} ==")
        try:
            oof = np.zeros(len(y_tr))
            cnts = np.zeros(len(y_tr), dtype=int)
            for tr_idx, te_idx in cv.split(X_tr, y_tr):
                m = factory()
                m.fit(X_tr[tr_idx], y_tr[tr_idx])
                prob = m.predict_proba(X_tr[te_idx])[:, 1]
                oof[te_idx] += prob
                cnts[te_idx] += 1
            oof /= np.maximum(cnts, 1)
            print(f"  OOF AUC={roc_auc_score(y_tr, oof):.3f}")

            m_full = factory()
            m_full.fit(X_tr, y_tr)
            p_val = m_full.predict_proba(X_va)[:, 1]
            print(f"  Val AUC={roc_auc_score(y_va, p_val):.3f}")

            for i, (yi, pi) in enumerate(zip(y_tr, oof)):
                all_rows.append(
                    {"model": name, "idx": i, "y": int(yi), "p": float(pi), "split": "oof"}
                )
            for i, (yi, pi) in enumerate(zip(y_va, p_val)):
                all_rows.append(
                    {"model": name, "idx": i, "y": int(yi), "p": float(pi), "split": "val"}
                )
        except Exception as e:
            print(f"  ERROR: {e}")
            continue

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(all_rows).to_csv(out_path, index=False)
    print(f"\nwrote {out_path}")


if __name__ == "__main__":
    main()
