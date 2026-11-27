#!/usr/bin/env python3
"""Figure S3: PAMM Days × exposure Log(HR) contour (fcimb Supplementary Figure 3 style).

Literature layout (image 3.tif): stacked panels a/b, x=Days 0–28, y=exposure,
filled contour + black isolines, colorbar Log(HR) (blue→white→red, floor at 0).

WPR:
  a = MIMIC-IV derivation
  b = eICU-CRD external validation
"""
from __future__ import annotations

import subprocess
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib import colors
from matplotlib.ticker import MultipleLocator

PROJ = Path("/mnt/g/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177")
IX_ROOT = PROJ / "by_index/【success】WPR"
OUT_PDF = (
    IX_ROOT
    / "summary_results/Figures/pdf"
    / "Figure S3. PAMM time-varying Log HR surface.pdf"
)
OUT_MD = (
    IX_ROOT
    / "summary_results/Figures/image_information"
    / "Figure S3. PAMM time-varying Log HR surface.md"
)
# 原错位 S3：缺失总览 → 挪到 S12，腾出 S3 给文献等高面
OLD_S3_PDF = IX_ROOT / "summary_results/Figures/pdf/Figure S3. Missing value overview.pdf"
OLD_S3_MD = (
    IX_ROOT
    / "summary_results/Figures/image_information"
    / "Figure S3. Missing value overview.md"
)
NEW_MISS_PDF = IX_ROOT / "summary_results/Figures/pdf/Figure S12. Missing value overview.pdf"
NEW_MISS_MD = (
    IX_ROOT
    / "summary_results/Figures/image_information"
    / "Figure S12. Missing value overview.md"
)

GAM_CANDS = {
    "mimic": [
        IX_ROOT / "mimic/step22_trajectory_pamm/Tables/PAMM/PAMM_gam_WPR.rds",
        IX_ROOT / "mimic/step25_trajectory_pamm/Tables/PAMM/PAMM_gam_WPR.rds",
        IX_ROOT / "mimic/Tables/PAMM/PAMM_gam_WPR.rds",
    ],
    "eicu": [
        IX_ROOT / "eicu/step23_trajectory_pamm/Tables/PAMM/PAMM_gam_WPR.rds",
        IX_ROOT / "eicu/step25_trajectory_pamm/Tables/PAMM/PAMM_gam_WPR.rds",
        IX_ROOT / "eicu/Tables/PAMM/PAMM_gam_WPR.rds",
    ],
}


def _find(cands: list[Path]) -> Path:
    for p in cands:
        if p.is_file():
            return p
    raise FileNotFoundError(f"no GAM among: {[str(x) for x in cands]}")


def _predict_loghr_grid(rds: Path, *, n_day: int = 57, n_expo: int = 80) -> dict:
    """Call R once: eta grid, shift so min=0 → Log(HR) like literature."""
    import pandas as pd
    import tempfile

    csv_path = Path(tempfile.mkstemp(suffix="_pamm_grid.csv")[1])
    meta_path = csv_path.with_name(csv_path.stem + "_meta.csv")
    r_code = f"""
suppressPackageStartupMessages(library(mgcv))
obj <- readRDS({rds.as_posix()!r})
fit <- if (inherits(obj, "gam")) obj else obj$gam
mf <- fit$model
tend_rng <- range(mf$tend, na.rm = TRUE)
expo_q <- as.numeric(stats::quantile(mf$expo, c(0.02, 0.98), na.rm = TRUE))
days <- seq(0, 28, length.out = {n_day})
days_pred <- pmin(pmax(days, tend_rng[1]), tend_rng[2])
expos <- seq(expo_q[1], expo_q[2], length.out = {n_expo})
# expand.grid 先 tend 后 expo → 列优先填充与 matrix(nrow=n_day) 一致
grid <- expand.grid(tend = days_pred, expo = expos)
# 线性协变量用拟合样本均值填齐（否则 predict 报 CHARLSON not found）
covs <- character(0)
if (is.list(obj) && !is.null(obj$covs)) covs <- as.character(obj$covs)
need <- setdiff(all.vars(stats::formula(fit)), c("ped_status", "tend", "expo", "(offset)"))
covs <- unique(c(covs, need))
for (cv in covs) {{
  if (!cv %in% names(mf)) next
  fill <- suppressWarnings(mean(as.numeric(mf[[cv]]), na.rm = TRUE))
  if (!is.finite(fill)) fill <- 0
  grid[[cv]] <- fill
}}
eta <- as.numeric(stats::predict(fit, newdata = grid, type = "link"))
loghr <- eta - min(eta, na.rm = TRUE)
loghr[!is.finite(loghr)] <- NA_real_
df <- data.frame(day = grid$tend, expo = grid$expo, loghr = loghr)
# 恢复展示用 Days（含 0），预测已夹边界
df$day <- days[match(grid$tend, days_pred)]
# match 对重复边界会错位；直接按列块写回原始 days
df$day <- rep(days, times = length(expos))
utils::write.csv(df, {csv_path.as_posix()!r}, row.names = FALSE)
meta <- data.frame(
  expo_lab = "WPR", n = nrow(mf),
  tend_lo = tend_rng[1], tend_hi = tend_rng[2],
  expo_lo = min(mf$expo, na.rm = TRUE), expo_hi = max(mf$expo, na.rm = TRUE)
)
utils::write.csv(meta, {meta_path.as_posix()!r}, row.names = FALSE)
cat("OK\\n")
"""
    proc = subprocess.run(
        ["Rscript", "-e", r_code],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout)
    df = pd.read_csv(csv_path)
    meta = pd.read_csv(meta_path).iloc[0]
    days = np.sort(df["day"].unique())
    expos = np.sort(df["expo"].unique())
    Z = (
        df.pivot(index="day", columns="expo", values="loghr")
        .reindex(index=days, columns=expos)
        .to_numpy(dtype=float)
    )
    csv_path.unlink(missing_ok=True)
    meta_path.unlink(missing_ok=True)
    return {
        "days": days,
        "expos": expos,
        "Z": Z,
        "expo_lab": str(meta["expo_lab"]),
        "n": int(meta["n"]),
        "path": rds,
    }


def _panel(ax, pack: dict, *, letter: str) -> None:
    days = pack["days"]
    expos = pack["expos"]
    Z = np.clip(pack["Z"], 0, None)
    Z = np.nan_to_num(Z, nan=0.0)
    X, Y = np.meshgrid(days, expos, indexing="ij")

    vmax = float(np.nanpercentile(Z, 99.5))
    if not np.isfinite(vmax) or vmax <= 0:
        vmax = float(np.nanmax(Z)) if np.nanmax(Z) > 0 else 1.0
    # blue → white → red，对齐文献
    cmap = colors.LinearSegmentedColormap.from_list(
        "fcimb_loghr",
        ["#2166AC", "#67A9CF", "#D1E5F0", "#F7F7F7", "#FDDBC7", "#EF8A62", "#B2182B"],
        N=256,
    )
    levels = np.linspace(0, vmax, 18)
    cf = ax.contourf(X, Y, Z, levels=levels, cmap=cmap, extend="max")
    # 文献 S3：黑等值线、无线上数字（色条读数）
    ax.contour(X, Y, Z, levels=levels[::2], colors="k", linewidths=0.55, alpha=0.85)
    cbar = plt.colorbar(cf, ax=ax, fraction=0.046, pad=0.02)
    cbar.set_label("Log(HR)", fontsize=10, fontfamily="serif")
    cbar.ax.tick_params(labelsize=8)
    for t in cbar.ax.get_yticklabels():
        t.set_fontfamily("serif")

    ax.set_xlim(0, 28)
    ax.set_xticks([0, 7, 14, 21, 28])
    ax.xaxis.set_minor_locator(MultipleLocator(1))
    ax.set_xlabel("Days", fontweight="bold", fontsize=11, fontfamily="serif")
    ax.set_ylabel(pack["expo_lab"], fontweight="bold", fontsize=11, fontfamily="serif")
    ax.tick_params(labelsize=9)
    for lab in ax.get_xticklabels() + ax.get_yticklabels():
        lab.set_fontfamily("serif")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
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


def _relocate_missing() -> None:
    if OLD_S3_PDF.is_file():
        NEW_MISS_PDF.parent.mkdir(parents=True, exist_ok=True)
        OLD_S3_PDF.replace(NEW_MISS_PDF)
    if OLD_S3_MD.is_file():
        txt = OLD_S3_MD.read_text(encoding="utf-8")
        txt = txt.replace("Figure S3.", "Figure S12.").replace("# Figure S3", "# Figure S12")
        NEW_MISS_MD.write_text(txt, encoding="utf-8")
        OLD_S3_MD.unlink()


def main() -> None:
    pack_m = _predict_loghr_grid(_find(GAM_CANDS["mimic"]))
    pack_e = _predict_loghr_grid(_find(GAM_CANDS["eicu"]))

    _relocate_missing()
    OUT_PDF.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)

    plt.rcParams.update(
        {
            "font.family": "serif",
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
            "axes.unicode_minus": False,
        }
    )
    fig, axes = plt.subplots(2, 1, figsize=(7.2, 9.0), dpi=150)
    fig.patch.set_facecolor("white")
    _panel(axes[0], pack_m, letter="a")
    _panel(axes[1], pack_e, letter="b")
    fig.tight_layout(h_pad=2.4)
    fig.savefig(OUT_PDF, bbox_inches="tight", facecolor="white")
    plt.close(fig)

    def _summ(p: dict) -> str:
        z = np.clip(p["Z"], 0, None)
        return (
            f"n_ped≈{p['n']}; WPR 窗 {p['expos'].min():.3g}–{p['expos'].max():.3g}; "
            f"Log(HR) 0–{np.nanmax(z):.2f}（相对网格最小风险）"
        )

    md = "\n".join(
        [
            "# Figure S3. PAMM time-varying Log HR surface",
            "",
            "## 图面说明",
            "",
            "上下双面板等高/填色面（对齐 fcimb Supplementary Figure 3）：",
            "横轴 Days（0–28），纵轴 WPR，颜色=Log(HR)；黑线=等值线；右侧色条。",
            "PAMM：`s(tend)+s(expo)+ti(tend,expo)`；色标相对预测网格最小风险抬到 ≥0。",
            "",
            "### 图上标注",
            "",
            f"- **面板 a（MIMIC-IV derivation）**：{_summ(pack_m)}",
            f"- **面板 b（eICU-CRD validation）**：{_summ(pack_e)}",
            "- 原「Missing value overview」已改编号为 Figure S12。",
            "",
            "## 分析上下文",
            "",
            "- 暴露：WPR 连续时变（PAMM）",
            "- 结局：28 天院内死亡",
            f"- 数据：a←{pack_m['path'].name}；b←{pack_e['path'].name}",
            "- 数据库：MIMIC-IV（derivation）+ eICU-CRD（external validation）",
            "- 是否拼图：否（上下双面板）",
            "",
        ]
    )
    OUT_MD.write_text(md, encoding="utf-8")
    print(f"OK → {OUT_PDF}")
    print(f"  a {pack_m['path']}")
    print(f"  b {pack_e['path']}")
    if NEW_MISS_PDF.is_file():
        print(f"  relocated missing → {NEW_MISS_PDF.name}")


if __name__ == "__main__":
    main()
