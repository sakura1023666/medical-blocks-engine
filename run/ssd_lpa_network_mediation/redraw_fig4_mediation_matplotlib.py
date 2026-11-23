#!/usr/bin/env python3
"""Figure 4 — Ma et al. Fig.4 geometry (Class|All dual path), three mediators stacked.

Faithful details vs reference screenshot:
- composite left boxes (solid light-blue header flush on white body)
- shared centre mediator + right outcome
- Class a/c′ from upper left; All a/c′ from lower left
- c′ nearly straight diagonals clearing above/below mediator (small arc only)
- two close parallel horizontal b arrows
- no in-figure n= clutter; footnote only *** legend
"""
from __future__ import annotations

import csv
import shutil
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.font_manager import FontProperties, findfont
from matplotlib.patches import FancyArrowPatch, Rectangle

PROJ = Path(
    "/mnt/g/02block_result/63_SSD/LPA_Network_Mediaton_42214160/by_index/main_full_sample"
)
OUT_PDF = PROJ / "summary_results/Figures/pdf/Figure 4. Mediation path diagram.pdf"
OUT_MD = PROJ / "summary_results/Figures/image_information/Figure 4. Mediation path diagram.md"
WS = PROJ / "summary_results_delivery_workspace"
CSV = WS / "mediation_ACME_all_scale_mediators_by_LCA.csv"

SPECS = [
    {"panel": "A", "m": "SSD12", "mlab": "SSD-12", "spot": "C1"},
    {"panel": "B", "m": "Whiteley8", "mlab": "Whiteley-8", "spot": "C3"},
    {"panel": "C", "m": "GAD7", "mlab": "GAD-7", "spot": "C3"},
]

HDR = "#A9C4DE"  # paper-like powder blue
EDGE = "#1a1a1a"
ARROW = "#6e6e6e"
XLAB, YLAB = "PHQ-15", "WHO-DAS"


def pick_serif() -> str:
    for name in ("Times New Roman", "Nimbus Roman", "Liberation Serif", "DejaVu Serif"):
        path = findfont(FontProperties(family=name), fallback_to_default=False)
        if path and "DejaVuSans" not in path and "comic" not in path.lower():
            # accept if requested family resolved
            if name.split()[0].lower() in path.lower() or "times" in path.lower() or "liberation" in path.lower() or "nimbus" in path.lower() or "dejavu" in path.lower():
                return name
    return "DejaVu Serif"


def star(p: float) -> str:
    if p < 0.001:
        return "***"
    if p < 0.01:
        return "**"
    if p < 0.05:
        return "*"
    return ""


def fmt(est: float, p: float) -> str:
    return f"{est:.3f}{star(p)}"


def load_row(rows, mediator: str, group: str):
    for r in rows:
        if r["mediator"] == mediator and r["group"] == group:
            return r
    raise KeyError(mediator, group)


def composite(ax, x, y, w, hh, hb, hdr, body, fp_h, fp_b):
    ax.add_patch(Rectangle((x, y + hb), w, hh, facecolor=HDR, edgecolor=EDGE, lw=0.85, zorder=3))
    ax.add_patch(Rectangle((x, y), w, hb, facecolor="white", edgecolor=EDGE, lw=0.85, zorder=3))
    ax.text(x + w / 2, y + hb + hh / 2, hdr, ha="center", va="center", fontproperties=fp_h, zorder=4)
    ax.text(x + w / 2, y + hb / 2, body, ha="center", va="center", fontproperties=fp_b, zorder=4)
    return dict(
        x=x, y=y, w=w, hh=hh, hb=hb,
        right=x + w,
        top=y + hb + hh,
        mid_y=y + hb / 2,
        upper_y=y + hb * 0.78,
        lower_y=y + hb * 0.22,
    )


def plain(ax, x, y, w, h, text, fp):
    ax.add_patch(Rectangle((x, y), w, h, facecolor="white", edgecolor=EDGE, lw=0.85, zorder=3))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontproperties=fp, zorder=4)
    return dict(
        x=x, y=y, w=w, h=h,
        left=x, right=x + w,
        top=y + h, bottom=y,
        mid_y=y + h / 2,
        upper_y=y + h * 0.72,
        lower_y=y + h * 0.28,
    )


def arr(ax, p0, p1, lab, lxy, fp, rad=0.0):
    ax.add_patch(
        FancyArrowPatch(
            p0, p1,
            arrowstyle="-|>",
            mutation_scale=8.5,
            lw=0.9,
            color=ARROW,
            connectionstyle=f"arc3,rad={rad}",
            shrinkA=1.0,
            shrinkB=1.0,
            zorder=2,
        )
    )
    ax.text(lxy[0], lxy[1], lab, ha="center", va="center", fontproperties=fp, color="black", zorder=5)


def draw_panel(ax, panel, spot_lab, a_s, b_s, c_s, a_a, b_a, c_a, mlab, fp_b, fp_h, fp_n, fp_panel):
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 4.6)
    ax.set_aspect("equal")
    ax.axis("off")

    # Panel letter (A/B/C) — top-left outside the path boxes
    ax.text(
        0.08, 4.42, panel,
        ha="left", va="top", fontproperties=fp_panel, color="black", zorder=6,
    )

    # Paper: left stacks with modest gap; mediator sits in the vertical middle of that gap
    w_l, hh, hb = 2.15, 0.36, 0.66
    cl = composite(ax, 0.45, 2.85, w_l, hh, hb, spot_lab, XLAB, fp_h, fp_b)
    al = composite(ax, 0.45, 0.35, w_l, hh, hb, "All", XLAB, fp_h, fp_b)

    w_m, h_m = 1.95, 0.78
    # vertical centre between class body bottom and all header top
    gap_lo = al["top"]
    gap_hi = cl["y"]
    my = (gap_lo + gap_hi) / 2 - h_m / 2
    med = plain(ax, 4.05, my, w_m, h_m, mlab, fp_b)
    out = plain(ax, 7.55, my, w_m, h_m, YLAB, fp_b)

    # Class → mediator (a)
    p0 = (cl["right"], cl["upper_y"])
    p1 = (med["left"], med["upper_y"])
    arr(ax, p0, p1, a_s, ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2 + 0.18), fp_n, 0.0)

    # Class → outcome (c′) above mediator — nearly straight like paper
    p0 = (cl["right"], cl["top"] - 0.02)
    p1 = (out["left"], out["top"] + 0.12)
    arr(ax, p0, p1, c_s, ((p0[0] + p1[0]) / 2 + 0.55, (p0[1] + p1[1]) / 2 + 0.12), fp_n, -0.04)

    # All → mediator (a)
    p0 = (al["right"], al["lower_y"])
    p1 = (med["left"], med["lower_y"])
    arr(ax, p0, p1, a_a, ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2 - 0.18), fp_n, 0.0)

    # All → outcome (c′) below mediator
    p0 = (al["right"], al["y"] + 0.06)
    p1 = (out["left"], out["bottom"] - 0.10)
    arr(ax, p0, p1, c_a, ((p0[0] + p1[0]) / 2 + 0.55, (p0[1] + p1[1]) / 2 - 0.12), fp_n, 0.04)

    # parallel b
    p0 = (med["right"], med["upper_y"])
    p1 = (out["left"], out["upper_y"])
    arr(ax, p0, p1, b_s, ((p0[0] + p1[0]) / 2, p0[1] + 0.16), fp_n, 0.0)
    p0 = (med["right"], med["lower_y"])
    p1 = (out["left"], out["lower_y"])
    arr(ax, p0, p1, b_a, ((p0[0] + p1[0]) / 2, p0[1] - 0.16), fp_n, 0.0)


def main():
    rows = list(csv.DictReader(CSV.open()))
    for r in rows:
        for k in ("a", "b", "cprime", "p_a", "p_b", "p_cprime"):
            r[k] = float(r[k])

    fam = pick_serif()
    print("font:", fam)
    fp_b = FontProperties(family=fam, size=10.5)
    fp_h = FontProperties(family=fam, size=10.5, weight="bold")
    fp_n = FontProperties(family=fam, size=9.5, weight="bold")
    fp_panel = FontProperties(family=fam, size=13, weight="bold")
    fp_note = FontProperties(family=fam, size=8)

    fig, axes = plt.subplots(3, 1, figsize=(7.8, 9.0))
    fig.subplots_adjust(left=0.01, right=0.99, top=0.995, bottom=0.04, hspace=0.04)

    ann = []
    for ax, sp in zip(axes, SPECS):
        rs = load_row(rows, sp["m"], sp["spot"])
        ra = load_row(rows, sp["m"], "All")
        a_s, b_s, c_s = fmt(rs["a"], rs["p_a"]), fmt(rs["b"], rs["p_b"]), fmt(rs["cprime"], rs["p_cprime"])
        a_a, b_a, c_a = fmt(ra["a"], ra["p_a"]), fmt(ra["b"], ra["p_b"]), fmt(ra["cprime"], ra["p_cprime"])
        draw_panel(
            ax,
            sp["panel"],
            sp["spot"].replace("C", "Class "),
            a_s, b_s, c_s, a_a, b_a, c_a,
            sp["mlab"], fp_b, fp_h, fp_n, fp_panel,
        )
        ann.append(
            f"{sp['panel']} {sp['mlab']} {sp['spot']}: a={a_s} b={b_s} c′={c_s}; "
            f"All: a={a_a} b={b_a} c′={c_a}"
        )

    fig.text(
        0.5, 0.008,
        "***P < 0.001.  Top path of each pair = spotlight class; bottom = All.",
        ha="center", va="bottom", fontproperties=fp_note,
    )

    tmp = Path("/tmp/fig4_mediation_paperstyle.pdf")
    fig.savefig(tmp, format="pdf", facecolor="white", bbox_inches="tight", pad_inches=0.08)
    plt.close(fig)
    OUT_PDF.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(tmp, OUT_PDF)
    print("wrote", OUT_PDF)

    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.write_text(
        "\n".join(
            [
                "# Figure 4. Mediation path diagram",
                "",
                "## 图面说明",
                "",
                "按参考文献 Fig 4 几何重绘：左侧 Class/All 复合框、中间共用中介、右侧共用结局；"
                "Class 路径走上方、All 走下方；中介→结局双平行 b。三面板为 SSD-12（Class 1）、"
                "Whiteley-8（Class 3）、GAD-7（Class 3）。",
                "",
                "## 图上标注",
                "",
                *[f"- {s}" for s in ann],
                "",
                "## 分析上下文",
                "",
                "- 暴露 PHQ-15；结局 WHO-DAS；协变量同 Table 3",
                "",
            ]
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
