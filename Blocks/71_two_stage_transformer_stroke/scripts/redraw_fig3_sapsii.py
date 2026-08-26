#!/usr/bin/env python3
"""Figure 3: Transformer vs SAPSII (Yang layout). No methodology title banner."""
from __future__ import annotations

import csv
import os
import sys
from pathlib import Path

os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

import matplotlib

matplotlib.use("Agg")
import matplotlib.colors as mcolors
import numpy as np
from matplotlib import pyplot as plt
from sklearn.metrics import roc_auc_score, roc_curve
from torch.utils.data import DataLoader

REPO = Path(r"E:/01block/01Block-new-Final")
if not REPO.exists():
    REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO))

from python.two_stage_transformer.dataloader import TSTDataset
from python.two_stage_transformer.eval import load_model_for_eval, score_all_cutoffs

PROJ = Path(r"G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421")
_LM = int(os.environ.get("TST_FIG3_LANDMARK", "72"))
UD = PROJ / f"by_unit/【success】L{_LM}_B_twostage/step09_tst_train_eval/Tables"
DATA = UD / "npz"
MODEL = UD / "model_b.pth"
MAP = PROJ / "_tmp_sapsii_by_stay.csv"
OUT = Path(
    os.environ.get(
        "TST_FIG3_OUT",
        str(PROJ / "summary_results/Figures/Figure 3-MIMIC-ROC_confusion_model_comparison.pdf"),
    )
)


def youden_pred(y, scores):
    fpr, tpr, thr = roc_curve(y, scores)
    opt = float(thr[np.argmax(tpr - fpr)]) if len(thr) else 0.5
    return (scores > opt).astype(int), opt


# 原文 Fig 3：results derived from the testing data（单次 test）；
# 柱图 Mean±SD = 同 test 上 Day1–5 日间波动；Mann–Whitney 跨日比较。
# 与 Table 2 的折间 mean(SD) 分开：表可报重复划分，图固定为 testing 示意。


def main():
    saps_map = {}
    with MAP.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            saps_map[int(float(row["stay_id"]))] = float(row["SAPSII"])

    ds = TSTDataset("test", str(DATA))
    D, H, F = ds.n_days, ds.n_hours, ds.n_features
    pids = np.load(DATA / "test.npz", allow_pickle=False)["patient_id"].astype(np.int64)
    saps = np.array([saps_map.get(int(p), np.nan) for p in pids], dtype=np.float64)
    print(f"test n={len(ds)} SAPSII miss={int(np.isnan(saps).sum())}")

    dl = DataLoader(ds, batch_size=64, shuffle=False)
    model = load_model_for_eval(str(MODEL), "b", D, H, F)
    scores = score_all_cutoffs(model, dl, D)
    y = ds.y
    los = ds.day_mask.sum(1).astype(int)

    days = []
    for c in range(1, D + 1):
        sel = (los >= c) & ~np.isnan(saps)
        yy, ss, ap = y[sel], scores[c][sel], saps[sel]
        fpr, tpr, _ = roc_curve(yy, ss)
        auc_m = float(roc_auc_score(yy, ss))
        pred, _ = youden_pred(yy, ss)
        tn = int(((yy == 0) & (pred == 0)).sum())
        fp = int(((yy == 0) & (pred == 1)).sum())
        fn = int(((yy == 1) & (pred == 0)).sum())
        tp = int(((yy == 1) & (pred == 1)).sum())
        acc_m = float((tn + tp) / len(yy))
        sfpr, stpr, _ = roc_curve(yy, ap)
        auc_s = float(roc_auc_score(yy, ap))
        pred_s, _ = youden_pred(yy, ap)
        acc_s = float((pred_s == yy).mean())
        days.append(
            dict(
                day=c,
                auc=auc_m,
                acc=acc_m,
                tn=tn,
                fp=fp,
                fn=fn,
                tp=tp,
                fpr=fpr,
                tpr=tpr,
                saps_auc=auc_s,
                saps_acc=acc_s,
                saps_fpr=sfpr,
                saps_tpr=stpr,
            )
        )
        print(f"Day{c}: AUC {auc_m:.3f} vs {auc_s:.3f} | Acc {acc_m:.3f} vs {acc_s:.3f} | n={len(yy)}")

    try:
        from scipy.stats import mannwhitneyu

        p_auc = mannwhitneyu([d["auc"] for d in days], [d["saps_auc"] for d in days]).pvalue
        p_acc = mannwhitneyu([d["acc"] for d in days], [d["saps_acc"] for d in days]).pvalue
    except Exception:
        p_auc = p_acc = float("nan")

    def p_lab(p):
        if p != p:
            return ""
        return r"$P < 0.001$" if p < 0.001 else rf"$P = {p:.3f}$"

    day_colors = ["#00BCD4", "#FF7043", "#E91E63", "#8BC34A", "#F9A825"]
    fig = plt.figure(figsize=(12.5, 8.8), dpi=160)
    gs = fig.add_gridspec(4, 3, height_ratios=[1.15, 0.95, 1.15, 0.95], hspace=0.42, wspace=0.32)

    def add_roc(ax, d, color):
        ax.plot(d["fpr"], d["tpr"], color=color, lw=2.0, ls=":", label=f"ROC curve (area = {d['auc']:.2f})")
        ax.plot(
            d["saps_fpr"],
            d["saps_tpr"],
            color="#9E9E9E",
            lw=1.6,
            ls=":",
            label=f"SAPSII ROC curve (area = {d['saps_auc']:.2f})",
        )
        ax.plot([0, 1], [0, 1], "k--", lw=0.9)
        ax.set_xlim(0, 1)
        ax.set_ylim(0, 1.02)
        ax.set_xlabel("False Positive Rate", fontsize=8)
        ax.set_ylabel("True Positive Rate", fontsize=8)
        ax.set_title(f"Day-{d['day']}", fontsize=11, pad=4)
        ax.legend(loc="lower right", fontsize=6.2, frameon=True)
        ax.tick_params(labelsize=7)

    def add_cm(ax, d):
        cm = np.array([[d["tn"], d["fp"]], [d["fn"], d["tp"]]], dtype=float)
        base = mcolors.to_rgb(day_colors[d["day"] - 1])
        cmap = mcolors.LinearSegmentedColormap.from_list(f"cm{d['day']}", [(1, 1, 1), base])
        ax.imshow(cm, cmap=cmap, vmin=0, vmax=max(cm.max(), 1))
        for i in range(2):
            for j in range(2):
                ax.text(j, i, f"{int(cm[i, j])}", ha="center", va="center", fontsize=11)
        ax.set_xticks([0, 1])
        ax.set_yticks([0, 1])
        ax.set_xticklabels(["0", "1"], fontsize=8)
        ax.set_yticklabels(["0", "1"], fontsize=8)
        ax.set_xlabel("Predicted", fontsize=8)
        ax.set_ylabel("True", fontsize=8)
        ax.set_title(f"Day-{d['day']}", fontsize=10, pad=3)

    for i, d in enumerate(days[:3]):
        add_roc(fig.add_subplot(gs[0, i]), d, day_colors[i])
        add_cm(fig.add_subplot(gs[1, i]), d)
    for i, d in enumerate(days[3:5]):
        add_roc(fig.add_subplot(gs[2, i]), d, day_colors[3 + i])
        add_cm(fig.add_subplot(gs[3, i]), d)

    axb = fig.add_subplot(gs[2:4, 2])
    aucs = np.array([d["auc"] for d in days])
    accs = np.array([d["acc"] for d in days])
    sa = np.array([d["saps_auc"] for d in days])
    sc = np.array([d["saps_acc"] for d in days])
    mean_auc, sd_auc = float(aucs.mean()), float(aucs.std(ddof=1))
    mean_acc, sd_acc = float(accs.mean()), float(accs.std(ddof=1))
    mean_sa, sd_sa = float(sa.mean()), float(sa.std(ddof=1))
    mean_sc, sd_sc = float(sc.mean()), float(sc.std(ddof=1))
    x = np.arange(2)
    w = 0.35
    axb.bar(
        x - w / 2,
        [mean_auc, mean_acc],
        w,
        yerr=[sd_auc, sd_acc],
        capsize=4,
        color="white",
        edgecolor="black",
        hatch="///",
        label="Two-stage Transformer",
        error_kw={"ecolor": "black", "lw": 1},
    )
    axb.bar(
        x + w / 2,
        [mean_sa, mean_sc],
        w,
        yerr=[sd_sa, sd_sc],
        capsize=4,
        color="#BDBDBD",
        edgecolor="black",
        label="SAPSII",
        error_kw={"ecolor": "black", "lw": 1},
    )
    top = max(mean_auc + sd_auc, mean_acc + sd_acc, mean_sa + sd_sa, mean_sc + sd_sc) + 0.06
    for i, pl in enumerate([p_lab(p_auc), p_lab(p_acc)]):
        if pl:
            axb.text(i, min(top, 1.02), pl, ha="center", fontsize=8)
    axb.set_ylim(0, max(1.05, top + 0.04))
    axb.set_xticks(x)
    axb.set_xticklabels(["AUC", "Accuracy"], fontsize=9)
    axb.set_ylabel("Mean ± SD", fontsize=9)
    axb.set_title("Comparison of Models", fontsize=11)
    axb.legend(loc="upper right", fontsize=7)
    axb.tick_params(labelsize=8)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT, format="pdf", bbox_inches="tight")
    plt.close(fig)
    print("wrote", OUT)
    print(f"Transformer {mean_auc:.3f}±{sd_auc:.3f} / {mean_acc:.3f}±{sd_acc:.3f}")
    print(f"SAPSII      {mean_sa:.3f}±{sd_sa:.3f} / {mean_sc:.3f}±{sd_sc:.3f}")
    print(f"MWU p_auc={p_auc} p_acc={p_acc}")


if __name__ == "__main__":
    main()
