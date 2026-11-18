"""TOPSIS classification fusion utilities (from Wang et al. npj Digit Med 2025; PMID 40295871).

Upstream notebook: github.com/472404420/NPJ-codes (extracted into Blocks/22_ml_models/_extract_npj_tcf/).
"""
from __future__ import annotations

import numpy as np
import pandas as pd


def entropy_weight(data: pd.DataFrame) -> np.ndarray:
    """Optional entropy weights; paper uses equal 1/6 for six metrics."""
    x = data.astype(float).to_numpy()
    x = x / (x.sum(axis=0, keepdims=True) + 1e-12)
    e = -(x * np.log(x + 1e-12)).sum(axis=0) / np.log(len(x) + 1e-12)
    d = 1.0 - e
    w = d / (d.sum() + 1e-12)
    return w


def topsis(data: pd.DataFrame, weight=None) -> tuple[pd.DataFrame, pd.DataFrame, np.ndarray]:
    """TOPSIS ranking of models. Higher metric = better (AUC/F1/ACC/PRE/SEN/SPE).

    Parameters
    ----------
    data : DataFrame
        rows = models, columns = metrics (all benefit criteria).
    weight : optional length-p weights; default equal weights (paper: 1/6 each).
    """
    data = data.astype(float).copy()
    z = pd.DataFrame([data.max(), data.min()], index=["PIS", "NIS"])
    if weight is None:
        weight = np.ones(data.shape[1], dtype=float) / data.shape[1]
    else:
        weight = np.asarray(weight, dtype=float)
        weight = weight / (weight.sum() + 1e-12)
    result = data.copy()
    result["dist_pis"] = np.sqrt(((data - z.loc["PIS"]) ** 2 * weight).sum(axis=1))
    result["dist_nis"] = np.sqrt(((data - z.loc["NIS"]) ** 2 * weight).sum(axis=1))
    result["topsis_score"] = result["dist_nis"] / (
        result["dist_nis"] + result["dist_pis"] + 1e-12
    )
    result["rank"] = result["topsis_score"].rank(ascending=False)
    return result, z, weight


def topsis_model_weights(metric_table: pd.DataFrame, equal_weight: bool = True) -> pd.Series:
    """Normalize TOPSIS scores to fusion alphas (sum=1)."""
    w = None if equal_weight else entropy_weight(metric_table)
    scored, _, _ = topsis(metric_table, weight=w)
    alpha = scored["topsis_score"] / scored["topsis_score"].sum()
    alpha.name = "alpha"
    return alpha


def fuse_proba(proba_by_model: dict[str, np.ndarray], alpha: pd.Series, threshold: float = 0.5):
    """Weighted probability fusion; classify at threshold (paper default 0.5)."""
    models = list(alpha.index)
    p = np.zeros_like(next(iter(proba_by_model.values())), dtype=float)
    for m in models:
        p = p + float(alpha[m]) * np.asarray(proba_by_model[m], dtype=float)
    yhat = (p > threshold).astype(int)
    return p, yhat
