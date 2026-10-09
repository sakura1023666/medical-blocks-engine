#!/usr/bin/env python3
"""Nature/Cell-style Figure 3 for ml_nafld_cm — cleaned layout, fixed calibration."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.calibration import calibration_curve
from sklearn.metrics import roc_curve

_REPO = Path(__file__).resolve().parent
if str(_REPO) not in sys.path:
    sys.path.insert(0, str(_REPO))

from ml_small_sample_metrics import (  # noqa: E402
    auc_safe,
    bootstrap_metrics,
    net_benefit,
    youden_thr,
)

PALETTE = {
    "LightGBM": "#0072B2",
    "XGBoost": "#E69F00",
    "RF": "#009E73",
    "TabNet": "#CC79A7",
    "SVM": "#D55E00",
    "ElasticNet": "#56B4E9",
    "LASSO": "#F0E442",
    "Logistic": "#999999",
}
PREFERRED = [
    "LightGBM", "XGBoost", "RF", "TabNet",
    "SVM", "ElasticNet", "LASSO", "Logistic",
]


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--root", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--bootstrap", type=int, default=400)
    p.add_argument("--top", type=int, default=5)
    return p.parse_args()


def _collapse_near_x(mp: np.ndarray, fr: np.ndarray, tol: float = 0.03):
    """Merge consecutive bins with nearly identical mean predicted (pile-up near 0/1)."""
    if len(mp) < 2:
        return mp, fr
    xs, ys, ns = [float(mp[0])], [float(fr[0])], [1]
    for i in range(1, len(mp)):
        if abs(float(mp[i]) - xs[-1]) < tol:
            n = ns[-1]
            xs[-1] = (xs[-1] * n + float(mp[i])) / (n + 1)
            ys[-1] = (ys[-1] * n + float(fr[i])) / (n + 1)
            ns[-1] = n + 1
        else:
            xs.append(float(mp[i]))
            ys.append(float(fr[i]))
            ns.append(1)
    return np.asarray(xs), np.asarray(ys)


def reliability_curve(y: np.ndarray, p: np.ndarray, n_bins: int = 5):
    """Return (mean_predicted, observed_freq) ascending in x (bottom-left → top-right).

    Prefer quantile bins so each point has similar n; avoids equal-width zigzags
    when predictions pile near 0/1 (common in high-AUC, imbalanced cohorts).
    """
    y = np.asarray(y, dtype=int)
    p = np.asarray(p, dtype=float)
    n_events = int(np.sum(y))
    if len(y) < 20 or n_events < 2:
        return np.array([]), np.array([])

    n_bins = int(max(3, min(n_bins, n_events // 10, len(y) // 30)))
    for strategy, nb in (("quantile", n_bins), ("quantile", 4), ("quantile", 3),
                         ("uniform", 4)):
        try:
            frac, mp = calibration_curve(y, p, n_bins=nb, strategy=strategy)
        except ValueError:
            continue
        if len(mp) < 2:
            continue
        ord_ = np.argsort(mp)
        mp2, fr2 = _collapse_near_x(
            np.asarray(mp, dtype=float)[ord_],
            np.asarray(frac, dtype=float)[ord_],
            tol=0.035,
        )
        if len(mp2) >= 2:
            return mp2, fr2
    return np.array([]), np.array([])


def main():
    args = parse_args()
    root = Path(args.root)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    import matplotlib as mpl
    import matplotlib.pyplot as plt
    from matplotlib.gridspec import GridSpec

    mpl.rcParams.update({
        "font.family": "sans-serif",
        "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
        "axes.linewidth": 0.7,
        "xtick.major.width": 0.7,
        "ytick.major.width": 0.7,
        "figure.dpi": 300,
        "savefig.dpi": 300,
    })

    allp = pd.read_csv(root / "ml_python_results.csv")
    ranks = []
    for m in allp["model"].unique():
        sv = allp[(allp["model"] == m) & (allp["split"] == "val")].sort_values("idx")
        if len(sv) == 0:
            continue
        ranks.append((m, auc_safe(sv["y"].to_numpy(int), sv["p"].to_numpy(float))))
    ranks.sort(key=lambda x: -x[1])
    order = [m for m, _ in ranks[: max(1, args.top)]]
    order = [m for m in PREFERRED if m in order] + [m for m in order if m not in PREFERRED]

    cv = allp[allp["split"] == "oof"]
    val = allp[allp["split"] == "val"]
    y = cv[cv["model"] == order[0]].sort_values("idx")["y"].to_numpy(int)
    yte = val[val["model"] == order[0]].sort_values("idx")["y"].to_numpy(int)

    cv_p, hold = {}, {}
    cv_rows, val_rows, cv_ci, val_ci = {}, {}, {}, {}
    for i, nm in enumerate(order):
        so = cv[cv["model"] == nm].sort_values("idx")
        sv = val[val["model"] == nm].sort_values("idx")
        cv_p[nm] = so["p"].to_numpy(float)
        hold[nm] = sv["p"].to_numpy(float)
        thr = youden_thr(so["y"].to_numpy(int), cv_p[nm])
        cv_rows[nm], cv_ci[nm] = bootstrap_metrics(
            so["y"].to_numpy(int), cv_p[nm], thr, B=args.bootstrap, seed=1000 + i
        )
        val_rows[nm], val_ci[nm] = bootstrap_metrics(
            sv["y"].to_numpy(int), hold[nm], thr, B=args.bootstrap, seed=2000 + i
        )
        for d in (cv_rows[nm], val_rows[nm], cv_ci[nm], val_ci[nm]):
            if "accuracy" in d and "Accuracy" not in d:
                d["Accuracy"] = d["accuracy"]

    # slightly larger canvas + dedicated legend row
    fig = plt.figure(figsize=(8.0, 5.0))
    gs = GridSpec(
        3, 4, figure=fig,
        height_ratios=[1.0, 1.0, 0.16],
        hspace=0.48, wspace=0.42,
        left=0.07, right=0.98, top=0.93, bottom=0.07,
    )
    axes = np.array([[fig.add_subplot(gs[r, c]) for c in range(4)] for r in range(2)])
    leg_ax = fig.add_subplot(gs[2, :])
    leg_ax.axis("off")

    thr_grid = np.linspace(0.05, 0.80, 24)

    def style_ax(ax, letter: str):
        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)
        ax.tick_params(labelsize=6.5, length=2.5, width=0.7)
        ax.text(
            -0.16, 1.12, letter, transform=ax.transAxes,
            fontsize=10, fontweight="bold", fontfamily="sans-serif", va="bottom",
            clip_on=False,
        )

    def roc_ax(ax, yv, pdata, title):
        ax.plot([0, 1], [0, 1], ls="--", c="0.75", lw=0.7, zorder=0)
        aucs = []
        for name in order:
            p = pdata[name]
            fpr, tpr, _ = roc_curve(yv, p)
            ax.plot(fpr, tpr, color=PALETTE.get(name, "0.3"), lw=1.25, label=name)
            aucs.append(f"{name} {auc_safe(yv, p):.3f}")
        # mid-bottom: left of diagonal clutter, clear of top-left ROC hug
        ax.text(
            0.55, 0.04, "\n".join(aucs), transform=ax.transAxes,
            ha="left", va="bottom", fontsize=5.0, linespacing=1.2,
            bbox=dict(boxstyle="round,pad=0.28", fc="white", ec="0.85", lw=0.4, alpha=0.94),
            clip_on=False, zorder=5,
        )
        ax.set_xlim(0, 1)
        ax.set_ylim(0, 1)
        ax.set_xlabel("1 − Specificity", fontsize=7, labelpad=2)
        ax.set_ylabel("Sensitivity", fontsize=7, labelpad=2)
        ax.set_title(title, fontsize=8, pad=4)
        ax.set_xticks([0, 0.5, 1.0])
        ax.set_yticks([0, 0.5, 1.0])

    def cal_ax(ax, yv, pdata, title):
        # ideal: bottom-left → top-right along y = x
        ax.plot([0, 1], [0, 1], ls="--", c="0.75", lw=0.7, zorder=0)
        for name in order:
            mp, fr = reliability_curve(yv, pdata[name], n_bins=5)
            if len(mp) < 2:
                continue
            ax.plot(
                mp, fr, "-o", color=PALETTE.get(name, "0.3"),
                lw=1.35, ms=3.5, label=name, zorder=2,
            )
        ax.set_xlim(0, 1)
        ax.set_ylim(0, 1)
        ax.set_xlabel("Predicted probability", fontsize=7, labelpad=2)
        ax.set_ylabel("Observed frequency", fontsize=7, labelpad=2)
        ax.set_title(title, fontsize=8, pad=4)
        ax.set_xticks([0, 0.5, 1.0])
        ax.set_yticks([0, 0.5, 1.0])

    def met_ax(ax, rows, ci_rows, mets, title):
        # 与参考 2×4 / ml_figure_combined_2x4 一致：同 x 上 o- 连线 + CI（不横向 dodge）
        short = {
            "AUC": "AUC", "Accuracy": "Acc", "Sensitivity": "Sens",
            "Specificity": "Spec", "F1": "F1",
        }
        x = np.arange(len(mets), dtype=float)
        for name in order:
            vals = np.array([rows[name][m] for m in mets], dtype=float)
            lo = np.array([ci_rows[name][m][0] for m in mets], dtype=float)
            hi = np.array([ci_rows[name][m][1] for m in mets], dtype=float)
            yerr = np.vstack([
                np.where(np.isfinite(lo), vals - lo, 0.0),
                np.where(np.isfinite(hi), hi - vals, 0.0),
            ])
            ax.errorbar(
                x, vals, yerr=yerr, fmt="o-", ms=3.2,
                color=PALETTE.get(name, "0.3"),
                lw=1.1, capsize=1.6, elinewidth=0.7, label=name,
            )
        ax.set_xticks(x)
        ax.set_xticklabels([short.get(m, m) for m in mets], fontsize=6.5, rotation=0)
        ax.set_xlim(-0.35, len(mets) - 0.65)
        ax.set_ylim(0.55, 1.03)
        ax.set_ylabel("Estimate", fontsize=7, labelpad=2)
        ax.set_title(title, fontsize=8, pad=4)

    def dca_ax(ax, yv, pdata, title):
        prev = float(np.mean(yv))
        treat_all = np.maximum(prev - (1 - prev) * (thr_grid / (1 - thr_grid)), 0.0)
        ax.plot(thr_grid, np.zeros_like(thr_grid), c="0.55", lw=0.7, label="Treat none")
        ax.plot(thr_grid, treat_all, c="0.35", ls="--", lw=0.8, label="Treat all")
        nb_max = prev
        for name in order:
            nb = np.maximum(net_benefit(yv, pdata[name], thr_grid), 0.0)
            ax.plot(thr_grid, nb, color=PALETTE.get(name, "0.3"), lw=1.15, label=name)
            if len(nb):
                nb_max = max(nb_max, float(np.nanmax(nb)))
        ax.set_xlim(0.05, 0.80)
        ax.set_ylim(0.0, nb_max * 1.10 + 0.01)
        ax.set_xlabel("Threshold probability", fontsize=7, labelpad=2)
        ax.set_ylabel("Net benefit", fontsize=7, labelpad=2)
        ax.set_title(title, fontsize=8, pad=4)

    roc_ax(axes[0, 0], y, cv_p, "Internal CV — ROC")
    roc_ax(axes[0, 1], yte, hold, "Hold-out — ROC")
    cal_ax(axes[0, 2], y, cv_p, "Internal CV — calibration")
    cal_ax(axes[0, 3], yte, hold, "Hold-out — calibration")
    met_ax(axes[1, 0], cv_rows, cv_ci, ["AUC", "Accuracy", "Sensitivity", "F1"],
           "Internal CV — metrics")
    met_ax(axes[1, 1], val_rows, val_ci,
           ["AUC", "Accuracy", "Sensitivity", "Specificity", "F1"],
           "Hold-out — metrics")
    dca_ax(axes[1, 2], y, cv_p, "Internal CV — DCA")
    dca_ax(axes[1, 3], yte, hold, "Hold-out — DCA")

    for i, ax in enumerate(axes.ravel()):
        style_ax(ax, list("abcdefgh")[i])

    handles, labels = axes[0, 0].get_legend_handles_labels()
    leg_ax.legend(
        handles, labels, loc="center", ncol=len(order),
        fontsize=7, frameon=False, handlelength=1.8,
        columnspacing=1.2, handletextpad=0.4,
    )

    fig.savefig(out, bbox_inches="tight", pad_inches=0.04)
    if out.suffix.lower() == ".pdf":
        fig.savefig(out.with_suffix(".png"), bbox_inches="tight", pad_inches=0.04)
    plt.close(fig)
    print(f"wrote {out} models={order}")


if __name__ == "__main__":
    main()
