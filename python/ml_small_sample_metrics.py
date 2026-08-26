"""Shared ML classification metrics for small-sample studies.

Youden threshold, bootstrap 95% CI — used by Figure 4 and optional Python-side checks.
"""
from __future__ import annotations

import numpy as np
from sklearn.metrics import roc_auc_score, roc_curve


def auc_safe(y, p) -> float:
    try:
        return float(roc_auc_score(y, p))
    except Exception:
        return float("nan")


def youden_thr(y, p) -> float:
    y = np.asarray(y).astype(int)
    p = np.asarray(p, dtype=float)
    fpr, tpr, thr = roc_curve(y, p)
    i = int(np.nanargmax(tpr - fpr))
    t = float(thr[i])
    return t if np.isfinite(t) else 0.5


def metrics(y, p, thr: float | None = None) -> dict[str, float]:
    y = np.asarray(y)
    p = np.asarray(p)
    if thr is None:
        thr = youden_thr(y, p)
    pred = (p >= thr).astype(int)
    tp = int(np.sum((pred == 1) & (y == 1)))
    tn = int(np.sum((pred == 0) & (y == 0)))
    fp = int(np.sum((pred == 1) & (y == 0)))
    fn = int(np.sum((pred == 0) & (y == 1)))
    spec = tn / (tn + fp) if (tn + fp) else float("nan")
    sens = tp / (tp + fn) if (tp + fn) else float("nan")
    denom = 2 * tp + fp + fn
    return {
        "AUC": auc_safe(y, p),
        "accuracy": float((tp + tn) / len(y)),
        "Sensitivity": float(sens) if np.isfinite(sens) else 0.0,
        "Specificity": float(spec) if np.isfinite(spec) else 0.0,
        "F1": float(2 * tp / denom) if denom else 0.0,
    }


def bootstrap_metrics(y, p, thr: float, B: int = 1000, seed: int = 42):
    y = np.asarray(y).astype(int)
    p = np.asarray(p, dtype=float)
    rng = np.random.default_rng(seed)
    n = len(y)
    keys = ["AUC", "accuracy", "Sensitivity", "Specificity", "F1"]
    boots = {k: [] for k in keys}
    for _ in range(B):
        idx = rng.integers(0, n, n)
        yb, pb = y[idx], p[idx]
        boots["AUC"].append(auc_safe(yb, pb))
        pred = (pb >= thr).astype(int)
        tp = int(np.sum((pred == 1) & (yb == 1)))
        tn = int(np.sum((pred == 0) & (yb == 0)))
        fp = int(np.sum((pred == 1) & (yb == 0)))
        fn = int(np.sum((pred == 0) & (yb == 1)))
        boots["accuracy"].append((tp + tn) / n)
        boots["Sensitivity"].append(tp / (tp + fn) if (tp + fn) else float("nan"))
        boots["Specificity"].append(tn / (tn + fp) if (tn + fp) else float("nan"))
        denom = 2 * tp + fp + fn
        boots["F1"].append(2 * tp / denom if denom else float("nan"))
    pt = metrics(y, p, thr)
    ci = {}
    for k in keys:
        arr = np.asarray(boots[k], dtype=float)
        arr = arr[np.isfinite(arr)]
        if len(arr) >= 10:
            lo, hi = np.quantile(arr, [0.025, 0.975])
            ci[k] = (float(lo), float(hi))
        else:
            ci[k] = (float("nan"), float("nan"))
    return pt, ci


def net_benefit(y, p, thr_grid):
    y = np.asarray(y)
    p = np.asarray(p)
    out = []
    for t in thr_grid:
        pred = p >= t
        tp = np.sum((pred == 1) & (y == 1))
        fp = np.sum((pred == 1) & (y == 0))
        n = len(y)
        out.append(tp / n - fp / n * (t / (1 - t)))
    return np.array(out)
