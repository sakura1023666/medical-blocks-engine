"""Figure 4 — ML performance 2×4 (ROC, calibration, metrics+CI, DCA).

Usage:
  python ml_figure_combined_2x4.py \\
    --root /path/to/study \\
    --out Figures/Figure\\ 4.\\ ML\\ performance\\ combined\\ 2x4.pdf
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.calibration import calibration_curve
from sklearn.metrics import roc_curve

# allow import from repo python/
_REPO = Path(__file__).resolve().parent
if str(_REPO) not in sys.path:
    sys.path.insert(0, str(_REPO))

from ml_small_sample_metrics import (  # noqa: E402
    auc_safe,
    bootstrap_metrics,
    metrics,
    net_benefit,
    youden_thr,
)

DEFAULT_ORDER = [
    "Logistic", "LASSO", "ElasticNet", "RF",
    "XGBoost", "LightGBM", "SVM", "TabNet",
    "TabPFN", "CatBoost", "AdaBoost",
]
COLORS = {
    "Logistic": "#1B9E77",
    "LASSO": "#D95F02",
    "ElasticNet": "#7570B3",
    "RF": "#A65628",
    "XGBoost": "#FF7F00",
    "LightGBM": "#984EA3",
    "SVM": "#E41A1C",
    "TabNet": "#377EB8",
    "TabPFN": "#E41A1C",
    "CatBoost": "#4DAF4A",
    "AdaBoost": "#377EB8",
}


def parse_args():
    p = argparse.ArgumentParser(description="ML Figure 4 combined 2x4")
    p.add_argument("--root", required=True, help="Study dir with ml_* csv files")
    p.add_argument("--out", required=True, help="Output PDF path")
    p.add_argument("--bootstrap", type=int, default=1000)
    p.add_argument("--rf-model", default="RF")
    return p.parse_args()


def load_probs(root: Path, rf_model: str) -> pd.DataFrame:
    py = pd.read_csv(root / "ml_python_results.csv")
    rf_path = root / "ml_all_probs.csv"
    if rf_path.exists():
        rf = pd.read_csv(rf_path)
        rf = rf[rf["model"] == rf_model]
        py = pd.concat([py, rf], ignore_index=True)
    return py


def main():
    args = parse_args()
    root = Path(args.root)
    out = Path(args.out)
    order = [m for m in DEFAULT_ORDER if m in load_probs(root, args.rf_model)["model"].unique()]
    if not order:
        order = list(DEFAULT_ORDER)

    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    plt.rcParams.update({"font.family": "Times New Roman", "pdf.fonttype": 42, "figure.dpi": 200})

    allp = load_probs(root, args.rf_model)
    cv_df = allp[allp["split"] == "oof"].copy()
    val_df = allp[allp["split"] == "val"].copy()
    y = cv_df[cv_df["model"] == order[0]]["y"].to_numpy(int)
    yte = val_df[val_df["model"] == order[0]]["y"].to_numpy(int)

    cv_p, hold = {}, {}
    cv_rows, val_rows, cv_ci, val_ci = {}, {}, {}, {}
    for i, nm in enumerate(order):
        so = cv_df[cv_df["model"] == nm].sort_values("idx")
        sv = val_df[val_df["model"] == nm].sort_values("idx")
        if len(so) == 0 or len(sv) == 0:
            raise SystemExit(f"missing model rows: {nm}")
        cv_p[nm] = so["p"].to_numpy(float)
        hold[nm] = sv["p"].to_numpy(float)
        y_tr = so["y"].to_numpy(int)
        thr = youden_thr(y_tr, cv_p[nm])
        cv_rows[nm], cv_ci[nm] = bootstrap_metrics(
            y_tr, cv_p[nm], thr, B=args.bootstrap, seed=1000 + i
        )
        y_val = sv["y"].to_numpy(int)
        val_rows[nm], val_ci[nm] = bootstrap_metrics(
            y_val, hold[nm], thr, B=args.bootstrap, seed=2000 + i
        )

    fig, axes = plt.subplots(2, 4, figsize=(14.2, 7.2))
    thr_grid = np.linspace(0.05, 0.80, 16)

    def roc_ax(ax, yv, pdata, title):
        ax.plot([0, 1], [0, 1], ls="--", c="0.7", lw=0.8)
        for name in order:
            p = np.asarray(pdata[name], dtype=float)
            fpr, tpr, _ = roc_curve(yv, p)
            ax.plot(fpr, tpr, color=COLORS.get(name, "0.3"), lw=1.3,
                    label=f"{name} {auc_safe(yv, p):.3f}")
        ax.set_xlim(0, 1)
        ax.set_ylim(0, 1)
        ax.set_xlabel("1 - Specificity")
        ax.set_ylabel("Sensitivity")
        ax.set_title(title)
        ax.legend(fontsize=6, loc="lower right", frameon=False)

    def cal_ax(ax, yv, pdata, title):
        ax.plot([0, 1], [0, 1], ls="--", c="0.7", lw=0.8)
        n_events = int(np.sum(yv))
        for name in order:
            p = np.asarray(pdata[name], dtype=float)
            if n_events < 2:
                continue
            # quantile first (stable ascending); uniform fallback — same look as ML 套路
            n_bins = max(3, min(5, max(2, n_events // 15)))
            frac = mp = None
            for strategy, nb in (("quantile", n_bins), ("quantile", 3), ("uniform", 4)):
                try:
                    frac, mp = calibration_curve(yv, p, n_bins=nb, strategy=strategy)
                    if len(mp) >= 2:
                        break
                except ValueError:
                    continue
            if mp is None or len(mp) < 2:
                continue
            ax.plot(mp, frac, marker="o", ms=4, color=COLORS.get(name, "0.3"), lw=1.2, label=name)
        ax.set_xlim(0, 1)
        ax.set_ylim(0, 1)
        ax.set_xlabel("Predicted risk")
        ax.set_ylabel("Observed frequency")
        ax.set_title(title, fontsize=8.5)
        ax.legend(fontsize=5.5, loc="upper left", frameon=False, ncol=2)

    def par_ax(ax, rows, ci_rows, mets, title):
        x = np.arange(len(mets))
        for name in order:
            vals = np.array([rows[name][m] for m in mets], dtype=float)
            lo = np.array([ci_rows[name][m][0] for m in mets], dtype=float)
            hi = np.array([ci_rows[name][m][1] for m in mets], dtype=float)
            yerr = np.vstack([
                np.where(np.isfinite(lo), vals - lo, 0.0),
                np.where(np.isfinite(hi), hi - vals, 0.0),
            ])
            ax.errorbar(
                x, vals, yerr=yerr, fmt="o-", ms=3.5, color=COLORS.get(name, "0.3"),
                lw=1.2, capsize=2.0, elinewidth=0.9, label=name
            )
        ax.set_xticks(x)
        ax.set_xticklabels(mets, rotation=20, ha="right", fontsize=7)
        ymax = max([rows[n][m] for n in order for m in mets if np.isfinite(rows[n][m])] + [1.0])
        ax.set_ylim(0.0, min(1.05, ymax + 0.12))
        ax.set_title(title + " (95% bootstrap CI)", fontsize=8.5)
        ax.legend(fontsize=5.5, loc="lower right", frameon=False, ncol=2)

    def dca_ax(ax, yv, pdata, title):
        prev = float(np.mean(yv))
        treat_all = np.maximum(prev - (1 - prev) * (thr_grid / (1 - thr_grid)), 0.0)
        ax.plot(thr_grid, np.zeros_like(thr_grid), c="0.5", lw=0.7, label="Treat none")
        ax.plot(thr_grid, treat_all, c="0.3", ls="--", lw=0.8, label="Treat all")
        nb_max = prev
        for name in order:
            p = np.asarray(pdata[name], dtype=float)
            nb = np.maximum(net_benefit(yv, p, thr_grid), 0.0)
            ax.plot(thr_grid, nb, color=COLORS.get(name, "0.3"), lw=1.2, label=name)
            if len(nb):
                nb_max = max(nb_max, float(np.nanmax(nb)))
        pad = max(nb_max * 0.12, 0.02)
        ax.set_xlim(0.05, 0.80)
        ax.set_ylim(0.0, nb_max + pad)
        ax.set_xlabel("Threshold probability")
        ax.set_ylabel("Net benefit")
        ax.set_title(title, fontsize=8.5)
        ax.legend(fontsize=5, loc="upper right", frameon=False, ncol=2)

    roc_ax(axes[0, 0], y, cv_p, "Internal validation (CV)")
    roc_ax(axes[0, 1], yte, hold, "Validation set")
    cal_ax(axes[0, 2], y, cv_p, "Internal validation (calibration)")
    cal_ax(axes[0, 3], yte, hold, "Validation set (calibration)")
    par_ax(axes[1, 0], cv_rows, cv_ci, ["AUC", "accuracy", "Sensitivity", "F1"],
           "Internal validation — metrics")
    par_ax(axes[1, 1], val_rows, val_ci,
           ["AUC", "accuracy", "Sensitivity", "Specificity", "F1"],
           "Validation set — metrics")
    dca_ax(axes[1, 2], y, cv_p, "Internal validation")
    dca_ax(axes[1, 3], yte, hold, "Validation set")
    for i, ax in enumerate(axes.ravel()):
        ax.text(-0.12, 1.08, list("ABCDEFGH")[i], transform=ax.transAxes,
                fontsize=11, fontweight="bold")
        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)
    fig.tight_layout(w_pad=1.2, h_pad=1.6)
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out, flush=True)


if __name__ == "__main__":
    main()
