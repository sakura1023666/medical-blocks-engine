#!/usr/bin/env python3
"""Figure S1 flowchart in fcimb-16-1871653 style (COPD WPR: MIMIC derivation / eICU validation)."""
from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

# Numbers (harvested): D02 raw → analytic imputed for WPR
N_MIMIC_START = 2692
N_EICU_START = 4388
N_MIMIC = 2610
N_EICU = 3737
N_START = N_MIMIC_START + N_EICU_START  # 7080
N_EX_M = N_MIMIC_START - N_MIMIC  # 82
N_EX_E = N_EICU_START - N_EICU  # 651
N_EX = N_EX_M + N_EX_E  # 733

OUT = Path(
    "/mnt/g/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177"
    "/by_index/【success】WPR/summary_results/Figures"
)


def _fmt(n: int) -> str:
    return f"{n:,}"


def _box(ax, x, y, w, h, text, fontsize=11, lw=1.6, weight="bold"):
    patch = FancyBboxPatch(
        (x - w / 2, y - h / 2),
        w,
        h,
        boxstyle="round,pad=0.012,rounding_size=0.08",
        linewidth=lw,
        edgecolor="black",
        facecolor="white",
        mutation_aspect=0.5,
    )
    ax.add_patch(patch)
    ax.text(
        x,
        y,
        text,
        ha="center",
        va="center",
        fontsize=fontsize,
        fontweight=weight,
        fontfamily="serif",
        linespacing=1.35,
        wrap=True,
    )


def _hline(ax, x0, x1, y, lw=1.4):
    ax.plot([x0, x1], [y, y], color="black", lw=lw, solid_capstyle="butt")


def _vline(ax, x, y0, y1, lw=1.4):
    ax.plot([x, x], [y0, y1], color="black", lw=lw, solid_capstyle="butt")


def _arrow_down(ax, x, y0, y1, lw=1.4):
    ax.annotate(
        "",
        xy=(x, y1),
        xytext=(x, y0),
        arrowprops=dict(arrowstyle="-|>", color="black", lw=lw, mutation_scale=12),
    )


def main() -> None:
    fig, ax = plt.subplots(figsize=(9.2, 7.2), dpi=150)
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis("off")
    fig.patch.set_facecolor("white")
    ax.set_facecolor("white")

    # --- layout coords ---
    cx = 4.0
    y_top = 9.0
    y_ex = 7.35
    y_db = 4.85
    y_bot = 2.35

    w_top = 7.2
    h_top = 0.95
    w_ex = 4.6
    h_ex = 1.35
    w_db = 2.55
    h_db = 0.85
    w_bot = 2.7
    h_bot = 0.9

    x_m = 2.55
    x_e = 6.55

    # Top
    _box(
        ax,
        cx,
        y_top,
        w_top,
        h_top,
        f"Patients with COPD identified from\nMIMIC-IV and eICU-CRD (n={_fmt(N_START)})",
        fontsize=11,
    )

    # Spine top → exclude junction
    y_junc = y_ex
    _vline(ax, cx, y_top - h_top / 2, y_junc)

    # Exclude to the right
    x_ex = 7.55
    _hline(ax, cx, x_ex - w_ex / 2, y_junc)
    _box(
        ax,
        x_ex,
        y_ex,
        w_ex,
        h_ex,
        "Excluded:\n"
        f"1. Insufficient WPR trajectory data,\n"
        f"   MIMIC-IV (n={_fmt(N_EX_M)})\n"
        f"2. Insufficient WPR trajectory data,\n"
        f"   eICU-CRD (n={_fmt(N_EX_E)})",
        fontsize=9.5,
        weight="bold",
    )

    # Continue spine to DB level
    y_db_bar = y_db + h_db / 2 + 0.55
    _vline(ax, cx, y_junc, y_db_bar)

    # Horizontal bar over DB boxes
    _hline(ax, x_m, x_e, y_db_bar)
    _vline(ax, x_m, y_db_bar, y_db + h_db / 2)
    _vline(ax, x_e, y_db_bar, y_db + h_db / 2)

    _box(ax, x_m, y_db, w_db, h_db, f"MIMIC-IV\nn={_fmt(N_MIMIC)}", fontsize=12)
    _box(ax, x_e, y_db, w_db, h_db, f"eICU-CRD\nn={_fmt(N_EICU)}", fontsize=12)

    # Derivation / Validation
    _arrow_down(ax, x_m, y_db - h_db / 2, y_bot + h_bot / 2)
    _arrow_down(ax, x_e, y_db - h_db / 2, y_bot + h_bot / 2)

    _box(
        ax,
        x_m,
        y_bot,
        w_bot,
        h_bot,
        f"Derivation cohort\nn={_fmt(N_MIMIC)}",
        fontsize=11,
    )
    _box(
        ax,
        x_e,
        y_bot,
        w_bot,
        h_bot,
        f"Validation cohort\nn={_fmt(N_EICU)}",
        fontsize=11,
    )

    pdf_dir = OUT / "pdf"
    md_dir = OUT / "image_information"
    pdf_dir.mkdir(parents=True, exist_ok=True)
    md_dir.mkdir(parents=True, exist_ok=True)
    dest = pdf_dir / "Figure S1. Flowchart of patient selection.pdf"
    fig.savefig(dest, bbox_inches="tight", pad_inches=0.15, facecolor="white")
    plt.close(fig)

    md = md_dir / "Figure S1. Flowchart of patient selection.md"
    md.write_text(
        "\n".join(
            [
                "# Figure S1. Flowchart of patient selection",
                "",
                "## 图面说明",
                "对齐文献 fcimb-16-1871653 Supplementary Figure 1 版式：",
                f"- 顶框：COPD ICU 提取合计 n={_fmt(N_START)}（MIMIC-IV {_fmt(N_MIMIC_START)} + eICU-CRD {_fmt(N_EICU_START)}）。",
                f"- 右侧 Exclude：WPR 轨迹不可用于分析（MIMIC {_fmt(N_EX_M)}；eICU {_fmt(N_EX_E)}；合计 {_fmt(N_EX)}）。",
                f"- 中部分库：MIMIC-IV n={_fmt(N_MIMIC)}；eICU-CRD n={_fmt(N_EICU)}。",
                f"- 底部分叉：Derivation（MIMIC）n={_fmt(N_MIMIC)}；Validation（eICU）n={_fmt(N_EICU)}。",
                "",
                "## 分析上下文",
                "暴露 WPR；结局 28 天院内死亡；发现集 MIMIC-IV / 外验 eICU-CRD。",
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(f"OK → {dest}")


if __name__ == "__main__":
    main()
