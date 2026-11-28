#!/usr/bin/env python3
"""从 sample×feature SHAP 矩阵重绘 Figure 4 / S1–S5。"""
from __future__ import annotations

import os
from pathlib import Path

os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

import matplotlib

matplotlib.use("Agg")
import numpy as np
import seaborn as sns
from matplotlib import pyplot as plt
from PIL import Image

PROJ = Path(r"G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421")
SHAP = PROJ / "by_unit/【success】L72_B_twostage/step11_tst_shap/Tables"
FIG = PROJ / "summary_results/Figures"
NPZ = SHAP / "shap_b_heatmaps.npz"


def plot_day(mat: np.ndarray, display: list[str], day: int, out_png: Path) -> None:
    # mat: (n_sample, F)
    val = mat.mean(0)
    order = np.argsort(val)[::-1]
    top = order[: min(15, mat.shape[1])]
    show = mat[:, top]
    col_max = np.maximum(show.max(axis=0, keepdims=True), 1e-12)
    show_n = show / col_max
    labels = [display[i] for i in top]

    fig, ax = plt.subplots(figsize=(11.5, 5.8), dpi=140)
    sns.heatmap(
        show_n,
        cmap="RdYlGn_r",
        vmin=0,
        vmax=1,
        xticklabels=labels,
        yticklabels=False,
        cbar_kws={"label": "Relative |SHAP|"},
        ax=ax,
    )
    ax.set_title(f"Day-{day} visualization results", fontsize=12)
    ax.set_xlabel("")
    ax.set_ylabel("Sample")
    n_s = show_n.shape[0]
    ax.set_yticks(np.linspace(0.5, max(n_s - 0.5, 0.5), min(5, max(n_s, 1))))
    ax.set_yticklabels([str(int(round(x))) for x in np.linspace(1, n_s, min(5, max(n_s, 1)))])
    plt.setp(ax.get_xticklabels(), rotation=35, ha="right", fontsize=8)
    fig.text(
        0.5,
        0.02,
        "Prominently activated features: " + ", ".join(labels[:6]),
        ha="center",
        fontsize=8,
        style="italic",
        color="#1a237e",
    )
    fig.tight_layout(rect=[0, 0.06, 1, 1])
    out_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_png, dpi=140)
    plt.close(fig)


def main() -> None:
    d = np.load(NPZ, allow_pickle=True)
    display = [str(x) for x in d["feature_display"]]
    day_pngs = []
    FIG.mkdir(parents=True, exist_ok=True)
    for c in range(1, 6):
        mat = d[f"day{c}"]
        if mat.ndim != 2 or mat.shape[0] < 2:
            raise SystemExit(f"day{c} 不是样本×特征矩阵 shape={mat.shape}；请先重跑 redraw_fig4_shap.py")
        png = SHAP / f"shap_b_day{c}.png"
        plot_day(mat, display, c, png)
        print(f"Day{c} shape={mat.shape}")
        day_pngs.append(png)
        out_s = FIG / f"Figure S{c}-MIMIC-SHAP_Day{c}.pdf"
        fig, ax = plt.subplots(figsize=(11, 5.5), dpi=140)
        ax.imshow(Image.open(png))
        ax.axis("off")
        fig.savefig(out_s, format="pdf", bbox_inches="tight")
        plt.close(fig)

    fig = plt.figure(figsize=(14.5, 9.2), dpi=140)
    gs = fig.add_gridspec(2, 3, hspace=0.12, wspace=0.08)
    for (r, c), p in zip([(0, 0), (0, 1), (0, 2), (1, 0), (1, 1)], day_pngs):
        ax = fig.add_subplot(gs[r, c])
        ax.imshow(Image.open(p))
        ax.axis("off")
    fig.add_subplot(gs[1, 2]).axis("off")
    out4 = FIG / "Figure 4-MIMIC-SHAP_daily_heatmap.pdf"
    fig.savefig(out4, format="pdf", bbox_inches="tight")
    plt.close(fig)
    print("wrote", out4)


if __name__ == "__main__":
    main()
