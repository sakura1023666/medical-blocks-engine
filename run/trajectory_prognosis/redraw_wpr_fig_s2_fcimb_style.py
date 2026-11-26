#!/usr/bin/env python3
"""Figure S2: Dynamic vs Static AUC (fcimb-16-1871653 style).

Literature layout (image 2.tif): stacked panels a/b, both Time-dependent AUC vs Days,
orange Dynamic + blue Static, error bars, per-day p labels, classic axes.

WPR:
  a = MIMIC-IV derivation
  b = eICU-CRD external validation
"""
from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

PROJ = Path("/mnt/g/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177")
IX_ROOT = PROJ / "by_index/【success】WPR"
MIMIC_CSV = [
    IX_ROOT / "summary_results/Tables/Table_Weibull_Dynamic_Compare_WPR_MIMIC.csv",
    IX_ROOT / "mimic/Tables/_archive/Table_Weibull_Dynamic_Compare_WPR.csv",
    IX_ROOT / "mimic/Tables/Table_Weibull_Dynamic_Compare_WPR.csv",
]
EICU_CSV = [
    IX_ROOT / "summary_results/Tables/Table_Weibull_Dynamic_Compare_WPR_eICU.csv",
    IX_ROOT / "eicu/Tables/Table_Weibull_Dynamic_Compare_WPR.csv",
    IX_ROOT / "eicu/Tables/_archive/Table_Weibull_Dynamic_Compare_WPR.csv",
    IX_ROOT / "eicu/step21_trajectory_weibull_compare/Tables/Table_Weibull_Dynamic_Compare_WPR.csv",
]
OUT_PDF = (
    IX_ROOT
    / "summary_results/Figures/pdf"
    / "Figure S2. Dynamic versus static prediction discrimination.pdf"
)
OUT_MD = (
    IX_ROOT
    / "summary_results/Figures/image_information"
    / "Figure S2. Dynamic versus static prediction discrimination.md"
)

COL_DYN = "#D55E00"
COL_STAT = "#0072B2"


def _fmt_p(p: float) -> str:
    if not np.isfinite(p):
        return ""
    if p < 0.001:
        return "<0.001"
    return f"{p:.3f}"


def _load_first(cands: list[Path]) -> tuple[pd.DataFrame, Path]:
    for p in cands:
        if p.is_file():
            df = pd.read_csv(p)
            df = df.sort_values("landmark").reset_index(drop=True)
            # require non-null AUC for at least one landmark
            if "auc_dyn" in df.columns and df["auc_dyn"].notna().any():
                return df, p
    raise FileNotFoundError(f"no usable CSV among: {[str(x) for x in cands]}")


def _panel(ax, df: pd.DataFrame, *, letter: str, title_note: str = "") -> None:
    ok = np.isfinite(df["auc_dyn"].to_numpy(float)) & np.isfinite(df["auc_weib"].to_numpy(float))
    d = df.loc[ok].reset_index(drop=True)
    x = d["landmark"].to_numpy(float)
    dyn = d["auc_dyn"].to_numpy(float)
    dyn_lo = d["auc_dyn_low"].to_numpy(float)
    dyn_hi = d["auc_dyn_high"].to_numpy(float)
    st = d["auc_weib"].to_numpy(float)
    st_lo = d["auc_weib_low"].to_numpy(float)
    st_hi = d["auc_weib_high"].to_numpy(float)
    pvals = d["p_auc"].to_numpy(float)

    # 防 CI 缺失导致负误差
    dyn_lo = np.where(np.isfinite(dyn_lo), dyn_lo, dyn)
    dyn_hi = np.where(np.isfinite(dyn_hi), dyn_hi, dyn)
    st_lo = np.where(np.isfinite(st_lo), st_lo, st)
    st_hi = np.where(np.isfinite(st_hi), st_hi, st)

    ax.errorbar(
        x,
        dyn,
        yerr=[np.maximum(dyn - dyn_lo, 0), np.maximum(dyn_hi - dyn, 0)],
        fmt="o-",
        color=COL_DYN,
        ecolor=COL_DYN,
        elinewidth=1.0,
        capsize=2.5,
        markersize=5.5,
        linewidth=1.6,
        label="Dynamic prediction model",
        zorder=3,
    )
    ax.errorbar(
        x,
        st,
        yerr=[np.maximum(st - st_lo, 0), np.maximum(st_hi - st, 0)],
        fmt="o-",
        color=COL_STAT,
        ecolor=COL_STAT,
        elinewidth=1.0,
        capsize=2.5,
        markersize=5.5,
        linewidth=1.6,
        label="Static prediction model",
        zorder=2,
    )

    y_top = np.nanmax(np.vstack([dyn_hi, st_hi]), axis=0)
    for xi, yi, pv in zip(x, y_top, pvals):
        lab = _fmt_p(float(pv))
        if not lab:
            continue
        ax.text(
            xi,
            min(yi + 0.035, 0.98),
            lab,
            ha="center",
            va="bottom",
            fontsize=7.5,
            color="black",
            fontfamily="serif",
        )

    ax.set_xlim(0.5, 14.5)
    ax.set_xticks(list(range(1, 15)))
    ax.set_ylim(0.4, 1.0)
    ax.set_yticks([0.4, 0.6, 0.8, 1.0])
    ax.set_ylabel("Time-dependent AUC", fontweight="bold", fontsize=11, fontfamily="serif")
    ax.set_xlabel("Days", fontweight="bold", fontsize=11, fontfamily="serif")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_linewidth(1.1)
    ax.spines["bottom"].set_linewidth(1.1)
    ax.tick_params(labelsize=9)
    for lab in ax.get_xticklabels() + ax.get_yticklabels():
        lab.set_fontfamily("serif")
    ax.grid(False)
    ax.text(
        -0.08,
        1.02,
        letter,
        transform=ax.transAxes,
        fontsize=14,
        fontweight="bold",
        fontfamily="serif",
        va="bottom",
        ha="left",
    )
    if title_note:
        ax.set_title(title_note, loc="left", fontsize=9, fontfamily="serif", pad=8)
    leg = ax.legend(
        loc="upper right",
        frameon=False,
        fontsize=9,
        handlelength=1.8,
        borderaxespad=0.2,
    )
    for t in leg.get_texts():
        t.set_fontfamily("serif")


def _row_line(df: pd.DataFrame) -> str:
    bits = []
    for _, r in df.iterrows():
        bits.append(
            f"D{int(r['landmark'])}: dyn={r['auc_dyn']:.3f}, "
            f"static={r['auc_weib']:.3f}, p={_fmt_p(float(r['p_auc']))}"
        )
    return "; ".join(bits)


def main() -> None:
    df_m, path_m = _load_first(MIMIC_CSV)
    df_e, path_e = _load_first(EICU_CSV)

    OUT_PDF.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)

    old = OUT_PDF.parent / "Figure S2. Piecewise Cox cut point search.pdf"
    old_md = OUT_MD.parent / "Figure S2. Piecewise Cox cut point search.md"
    if old.is_file():
        old.unlink()
    if old_md.is_file():
        old_md.unlink()

    plt.rcParams.update(
        {
            "font.family": "serif",
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
            "axes.unicode_minus": False,
        }
    )
    fig, axes = plt.subplots(2, 1, figsize=(7.2, 9.0), dpi=150, sharex=False)
    fig.patch.set_facecolor("white")
    _panel(axes[0], df_m, letter="a")
    _panel(axes[1], df_e, letter="b")
    fig.tight_layout(h_pad=2.2)
    fig.savefig(OUT_PDF, bbox_inches="tight", facecolor="white")
    plt.close(fig)

    md = "\n".join(
        [
            "# Figure S2. Dynamic versus static prediction discrimination",
            "",
            "## 图面说明",
            "",
            "上下双面板折线图（对齐 fcimb 文献 Supplementary Figure 2）：两面板均为 Time-dependent AUC；",
            "橙线=动态预测（JLCM landmark dynpred），蓝线=静态预测（Weibull）。",
            "误差棒=95% bootstrap CI；点上方=配对 permutation P（Dynamic vs Static）。",
            "",
            "### 图上标注",
            "",
            f"- **面板 a（MIMIC-IV derivation）**：{_row_line(df_m)}",
            f"- **面板 b（eICU-CRD validation）**：{_row_line(df_e)}",
            "- X 轴 Days 1–14（与文献同窗；Day1–2 经早 landmark 历史补点解锁 ns(df=2) dynpred）；Y 轴 0.4–1.0。",
            "",
            "## 分析上下文",
            "",
            "- 暴露：WPR 轨迹（JLCM ng=5；外验固定发现集参数与 MIMIC 协变量）",
            "- 结局：28 天院内死亡",
            f"- 样本量：面板 a n_landmark Day1={int(df_m.loc[df_m['landmark']==1,'n_landmark'].iloc[0])}；"
            f"面板 b Day1={int(df_e.loc[df_e['landmark']==1,'n_landmark'].iloc[0])}",
            f"- 数据：a←{path_m.name}；b←{path_e.name}",
            "- 数据库：MIMIC-IV（derivation）+ eICU-CRD（external validation）",
            "- 是否拼图：否（上下双面板）",
            "",
        ]
    )
    OUT_MD.write_text(md, encoding="utf-8")
    print(f"OK → {OUT_PDF}")
    print(f"  a MIMIC: {path_m}")
    print(f"  b eICU:  {path_e}")


if __name__ == "__main__":
    main()
