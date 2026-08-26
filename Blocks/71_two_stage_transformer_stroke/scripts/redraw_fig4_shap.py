#!/usr/bin/env python3
"""重跑 L72_B SHAP，并写出 Figure 4 + Figure S1–S5（mapping 列名、Yang 配色）。"""
from __future__ import annotations

import os
import sys
from pathlib import Path

os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

REPO = Path(r"E:/01block/01Block-new-Final")
if not REPO.exists():
    REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO))

from PIL import Image

from python.two_stage_transformer.shap_plot import run_shap

PROJ = Path(r"G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421")
UD = PROJ / "by_unit/【success】L72_B_twostage"
DATA = UD / "step09_tst_train_eval/Tables/npz"
MODEL = UD / "step09_tst_train_eval/Tables/model_b.pth"
SHAP_OUT = UD / "step11_tst_shap/Tables"
FIG = PROJ / "summary_results/Figures"


def collage_yang(day_pngs: list[Path], out_pdf: Path) -> None:
    """2×3 网格：上排 Day1–3，下排 Day4–5 + 空白。"""
    import matplotlib

    matplotlib.use("Agg")
    from matplotlib import pyplot as plt

    fig = plt.figure(figsize=(14.5, 9.2), dpi=140)
    gs = fig.add_gridspec(2, 3, hspace=0.18, wspace=0.12)
    slots = [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1)]
    for (r, c), p in zip(slots, day_pngs):
        ax = fig.add_subplot(gs[r, c])
        if p.exists():
            ax.imshow(Image.open(p))
        ax.axis("off")
    ax_blank = fig.add_subplot(gs[1, 2])
    ax_blank.axis("off")
    out_pdf.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_pdf, format="pdf", bbox_inches="tight")
    plt.close(fig)
    print("wrote", out_pdf)


def main() -> None:
    SHAP_OUT.mkdir(parents=True, exist_ok=True)
    run_shap(
        data_dir=str(DATA),
        out_dir=str(SHAP_OUT),
        model_path=str(MODEL),
        arch="b",
        split="test",
        project_root=str(PROJ),
    )
    day_pngs = [SHAP_OUT / f"shap_b_day{d}.png" for d in range(1, 6)]
    FIG.mkdir(parents=True, exist_ok=True)
    # 单日 PDF → S1–S5
    import matplotlib

    matplotlib.use("Agg")
    from matplotlib import pyplot as plt

    for d, p in enumerate(day_pngs, 1):
        out = FIG / f"Figure S{d}-MIMIC-SHAP_Day{d}.pdf"
        if not p.exists():
            continue
        fig, ax = plt.subplots(figsize=(11, 5.5), dpi=140)
        ax.imshow(Image.open(p))
        ax.axis("off")
        fig.savefig(out, format="pdf", bbox_inches="tight")
        plt.close(fig)
        print("wrote", out)

    collage_yang(day_pngs, FIG / "Figure 4-MIMIC-SHAP_daily_heatmap.pdf")


if __name__ == "__main__":
    main()
