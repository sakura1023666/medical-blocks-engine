#!/usr/bin/env python3
"""Figure 4：五天 SHAP 样本×特征热图，单图紧凑排版（无嵌套 PNG、无大块空白）。"""
from __future__ import annotations

import os
from pathlib import Path

os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

import matplotlib

matplotlib.use("Agg")
import numpy as np
import seaborn as sns
from matplotlib import pyplot as plt
from mpl_toolkits.axes_grid1 import make_axes_locatable

PROJ = Path(r"G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421")
SHAP = PROJ / "by_unit/【success】L72_B_twostage/step11_tst_shap/Tables"
FIG = PROJ / "summary_results/Figures"
NPZ = SHAP / "shap_b_heatmaps.npz"


def _day_matrix(d, day: int, display: list[str], n_top: int = 12):
    mat = np.asarray(d[f"day{day}"], dtype=np.float64)
    if mat.ndim != 2 or mat.shape[0] < 2:
        raise ValueError(f"day{day} 需要样本×特征矩阵，got {mat.shape}")
    val = mat.mean(0)
    order = np.argsort(val)[::-1][: min(n_top, mat.shape[1])]
    show = mat[:, order]
    col_max = np.maximum(show.max(axis=0, keepdims=True), 1e-12)
    show_n = show / col_max
    labels = [display[i] for i in order]
    return show_n, labels, [display[i] for i in order[:5]]


def main() -> None:
    d = np.load(NPZ, allow_pickle=True)
    display = [str(x) for x in d["feature_display"]]
    FIG.mkdir(parents=True, exist_ok=True)

    # 5 行 × 1 列：放大可读；右侧统一色条；几乎无空白
    fig, axes = plt.subplots(
        5,
        1,
        figsize=(10.5, 14.0),
        dpi=180,
        sharex=False,
        constrained_layout=False,
    )
    fig.subplots_adjust(left=0.08, right=0.88, top=0.97, bottom=0.04, hspace=0.28)

    last_im = None
    for i, ax in enumerate(axes):
        day = i + 1
        show_n, labels, top5 = _day_matrix(d, day, display)
        last_im = ax.imshow(
            show_n,
            aspect="auto",
            cmap="RdYlGn_r",
            vmin=0,
            vmax=1,
            interpolation="nearest",
        )
        ax.set_title(f"Day-{day}", fontsize=11, loc="left", pad=3)
        ax.set_ylabel("Sample", fontsize=8)
        n_s, n_f = show_n.shape
        ax.set_yticks([0, n_s // 2, n_s - 1])
        ax.set_yticklabels(["1", str(n_s // 2 + 1), str(n_s)], fontsize=7)
        ax.set_xticks(range(n_f))
        ax.set_xticklabels(labels, rotation=28, ha="right", fontsize=7)
        ax.tick_params(length=2)
        ax.text(
            1.0,
            1.02,
            "Top: " + ", ".join(top5),
            transform=ax.transAxes,
            ha="right",
            va="bottom",
            fontsize=6.5,
            color="#283593",
            clip_on=False,
        )

        # 同步单日 PDF（补充图），同样紧凑
        fig_s, ax_s = plt.subplots(figsize=(10.5, 3.2), dpi=180)
        im_s = ax_s.imshow(show_n, aspect="auto", cmap="RdYlGn_r", vmin=0, vmax=1, interpolation="nearest")
        ax_s.set_title(f"Day-{day} visualization results", fontsize=11, loc="left")
        ax_s.set_ylabel("Sample", fontsize=8)
        ax_s.set_yticks([0, n_s // 2, n_s - 1])
        ax_s.set_yticklabels(["1", str(n_s // 2 + 1), str(n_s)], fontsize=7)
        ax_s.set_xticks(range(n_f))
        ax_s.set_xticklabels(labels, rotation=28, ha="right", fontsize=7)
        divider = make_axes_locatable(ax_s)
        cax = divider.append_axes("right", size="2.5%", pad=0.08)
        fig_s.colorbar(im_s, cax=cax, label="Relative |SHAP|")
        fig_s.tight_layout()
        out_s = FIG / f"Figure S{day}-MIMIC-SHAP_Day{day}.pdf"
        fig_s.savefig(out_s, format="pdf", bbox_inches="tight")
        plt.close(fig_s)
        # 也更新 png 供流水线拼贴备用
        png = SHAP / f"shap_b_day{day}.png"
        fig_s2, ax_s2 = plt.subplots(figsize=(10.5, 3.2), dpi=160)
        ax_s2.imshow(show_n, aspect="auto", cmap="RdYlGn_r", vmin=0, vmax=1, interpolation="nearest")
        ax_s2.set_title(f"Day-{day} visualization results", fontsize=11, loc="left")
        ax_s2.set_ylabel("Sample", fontsize=8)
        ax_s2.set_yticks([0, n_s // 2, n_s - 1])
        ax_s2.set_yticklabels(["1", str(n_s // 2 + 1), str(n_s)], fontsize=7)
        ax_s2.set_xticks(range(n_f))
        ax_s2.set_xticklabels(labels, rotation=28, ha="right", fontsize=7)
        fig_s2.tight_layout()
        fig_s2.savefig(png, dpi=160)
        plt.close(fig_s2)
        print("wrote", out_s.name)

    cax = fig.add_axes([0.90, 0.15, 0.02, 0.7])
    cb = fig.colorbar(last_im, cax=cax)
    cb.set_label("Relative |SHAP|", fontsize=9)

    out4 = FIG / "Figure 4-MIMIC-SHAP_daily_heatmap.pdf"
    fig.savefig(out4, format="pdf")
    plt.close(fig)
    print("wrote", out4)


if __name__ == "__main__":
    main()
