#!/usr/bin/env python3
"""External validation figures (Yang pbaf003 S7 / S8 layout).

Panel ``external`` — held-out test split (10%, never used in training).
Panel ``mimic`` — MIMIC hold-out validation set (val + test, excludes training patients).

Both use the frozen L*_B two-stage Transformer at Day 5 (last available ICU day in window).
"""
from __future__ import annotations

import argparse
import csv
import os
import sys
from pathlib import Path

os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Rectangle
from sklearn.metrics import roc_auc_score, roc_curve
from torch.utils.data import DataLoader


def _to_path(p: str | Path) -> Path:
    s = str(p)
    if s.startswith("/mnt/") and len(s) > 7 and s[6] == "/":
        return Path(f"{s[5].upper()}:/{s[7:]}".replace("\\", "/"))
    return Path(s)


def _parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Redraw external validation ROC + confusion matrix")
    ap.add_argument("--project-root", required=True)
    ap.add_argument("--landmark", type=int, default=120)
    ap.add_argument(
        "--panel",
        choices=("external", "mimic"),
        required=True,
        help="external=test split; mimic=val+test (non-training patients)",
    )
    ap.add_argument("--day", type=int, default=5)
    ap.add_argument("--out", default="")
    ap.add_argument(
        "--repo",
        default=os.environ.get("MEDICAL_BLOCKS_ROOT", r"E:/01block/01Block-new-Final"),
    )
    return ap.parse_args()


def youden_pred(y, scores):
    fpr, tpr, thr = roc_curve(y, scores)
    opt = float(thr[np.argmax(tpr - fpr)]) if len(thr) else 0.5
    return (scores > opt).astype(int), opt


def _resolve_unit_tables(proj: Path, lm: int) -> Path:
    for ud in (
        proj / f"by_unit/【success】L{lm}_B_twostage/step09_tst_train_eval/Tables",
        proj / f"by_unit/L{lm}_B_twostage/step09_tst_train_eval/Tables",
    ):
        if ud.exists():
            return ud
    raise SystemExit(f"L{lm}_B tables not found under {proj}")


def _load_split_arrays(tables: Path, splits: list[str]):
    repo = _to_path(os.environ.get("MEDICAL_BLOCKS_ROOT", r"E:/01block/01Block-new-Final"))
    if not repo.exists():
        repo = Path(__file__).resolve().parents[3]
    sys.path.insert(0, str(repo))
    from python.two_stage_transformer.dataloader import TSTDataset  # noqa: WPS433
    from python.two_stage_transformer.eval import load_model_for_eval, score_all_cutoffs  # noqa: WPS433

    npz_dir = tables / "npz"
    ds0 = TSTDataset(splits[0], str(npz_dir))
    D, H, F = ds0.n_days, ds0.n_hours, ds0.n_features
    model = load_model_for_eval(str(tables / "model_b.pth"), "b", D, H, F)

    ys, scores_day = [], []
    for sp in splits:
        ds = TSTDataset(sp, str(npz_dir))
        dl = DataLoader(ds, batch_size=64, shuffle=False)
        sc = score_all_cutoffs(model, dl, D)
        ys.append(ds.y)
        scores_day.append(sc)

    y = np.concatenate(ys).astype(int)
    merged = {}
    for day in range(1, D + 1):
        merged[day] = np.concatenate([sc[day] for sc in scores_day])
    masks = []
    for sp in splits:
        d = np.load(npz_dir / f"{sp}.npz", allow_pickle=False)
        masks.append(d["day_mask"])
    los = np.concatenate(masks).sum(1).astype(int)
    return y, merged, los, D


def _evaluate_panel(y, scores_by_day, los, day: int) -> dict:
    sel = los >= day
    yy = y[sel]
    ss = scores_by_day[day][sel]
    if len(yy) < 5 or len(np.unique(yy)) < 2:
        raise SystemExit(f"too few samples for Day{day}: n={len(yy)}")
    fpr, tpr, _ = roc_curve(yy, ss)
    auc = float(roc_auc_score(yy, ss))
    pred, _ = youden_pred(yy, ss)
    tn = int(((yy == 0) & (pred == 0)).sum())
    fp = int(((yy == 0) & (pred == 1)).sum())
    fn = int(((yy == 1) & (pred == 0)).sum())
    tp = int(((yy == 1) & (pred == 1)).sum())
    acc = float((pred == yy).mean())
    return dict(
        y=yy,
        scores=ss,
        fpr=fpr,
        tpr=tpr,
        auc=auc,
        acc=acc,
        tn=tn,
        fp=fp,
        fn=fn,
        tp=tp,
        n=len(yy),
        n_pos=int(yy.sum()),
        n_neg=int((yy == 0).sum()),
    )


def _draw_panel(stats: dict, *, title_roc: str, title_cm: str, legend_label: str, out: Path) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(9.2, 4.6), dpi=160)
    fig.subplots_adjust(left=0.09, right=0.90, top=0.82, bottom=0.14, wspace=0.28)
    for ax in axes:
        ax.set_facecolor("white")
    fig.patch.set_facecolor("white")
    rect = Rectangle(
        (0.02, 0.06),
        0.96,
        0.88,
        transform=fig.transFigure,
        fill=False,
        linestyle="--",
        linewidth=2.2,
        edgecolor="black",
    )
    fig.patches.append(rect)

    ax_r, ax_c = axes
    ax_r.plot(stats["fpr"], stats["tpr"], color="#1f77b4", lw=2.2)
    ax_r.plot([0, 1], [0, 1], "k--", lw=0.9, alpha=0.6)
    ax_r.set_xlim(0, 1)
    ax_r.set_ylim(0, 1.02)
    ax_r.set_xlabel("False Positive Rate", fontsize=9)
    ax_r.set_ylabel("True Positive Rate", fontsize=9)
    ax_r.set_title(title_roc, fontsize=9.5, loc="center", pad=10)
    ax_r.legend([legend_label], loc="lower right", fontsize=8, frameon=True)
    ax_r.grid(True, linestyle=":", alpha=0.4)

    cm = np.array([[stats["tn"], stats["fp"]], [stats["fn"], stats["tp"]]], dtype=float)
    im = ax_c.imshow(cm, cmap="Blues", vmin=0, vmax=max(cm.max(), 1))
    for i in range(2):
        for j in range(2):
            ax_c.text(j, i, f"{int(cm[i, j])}", ha="center", va="center", fontsize=13, color="black")
    ax_c.set_xticks([0, 1])
    ax_c.set_yticks([0, 1])
    ax_c.set_xticklabels(["0", "1"], fontsize=9)
    ax_c.set_yticklabels(["0", "1"], fontsize=9)
    ax_c.set_xlabel("Predicted", fontsize=9)
    ax_c.set_ylabel("True", fontsize=9)
    ax_c.set_title(title_cm, fontsize=9.5, loc="center", pad=10)
    cbar = fig.colorbar(im, ax=ax_c, fraction=0.046, pad=0.04)
    cbar.ax.tick_params(labelsize=8)
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, format="pdf", bbox_inches="tight", pad_inches=0.08)
    plt.close(fig)


def _write_metrics(out_tables: Path, row: dict) -> None:
    out_tables.mkdir(parents=True, exist_ok=True)
    path = out_tables / "Table_External_Real_Metrics.csv"
    fields = [
        "panel",
        "day",
        "arch",
        "auc",
        "accuracy",
        "n",
        "n_pos",
        "n_neg",
        "tn",
        "fp",
        "fn",
        "tp",
        "is_synthetic",
        "split_description",
    ]
    write_header = not path.exists()
    with path.open("a", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        if write_header:
            w.writeheader()
        w.writerow(row)


def main() -> None:
    args = _parse_args()
    proj = _to_path(args.project_root)
    lm = int(args.landmark)
    day = int(args.day)
    tables = _resolve_unit_tables(proj, lm)

    if args.panel == "external":
        splits = ["test"]
        default_out = proj / "summary_results/Figures/Figure 3-MIMIC-External_validation.pdf"
        title_roc = "Receiver Operating Characteristic (ROC) Curve"
        title_cm = "Confusion Matrix"
        legend_tpl = "External validation (AUC={:.3f})"
        split_desc = "held-out test split (10%)"
    else:
        splits = ["val", "test"]
        default_out = proj / "summary_results/Figures/Figure S7-MIMIC-MIMIC_validation.pdf"
        title_roc = "Receiver Operating Characteristic (ROC) Curve for mimic-iv"
        title_cm = "Confusion Matrix in mimic-iv-3.1"
        legend_tpl = "mimic-iv ROC Curve (AUC={:.3f})"
        split_desc = "MIMIC hold-out validation (val+test, excludes training)"

    out = _to_path(args.out) if args.out else default_out

    y, scores_by_day, los, _D = _load_split_arrays(tables, splits)
    stats = _evaluate_panel(y, scores_by_day, los, day)
    legend = legend_tpl.format(stats["auc"])

    _draw_panel(
        stats,
        title_roc=title_roc,
        title_cm=title_cm,
        legend_label=legend,
        out=out,
    )

    metrics_dir = proj / "summary_results/by_landmark" / f"L{lm}" / "Tables"
    _write_metrics(
        metrics_dir,
        {
            "panel": args.panel,
            "day": day,
            "arch": "b",
            "auc": round(stats["auc"], 4),
            "accuracy": round(stats["acc"], 4),
            "n": stats["n"],
            "n_pos": stats["n_pos"],
            "n_neg": stats["n_neg"],
            "tn": stats["tn"],
            "fp": stats["fp"],
            "fn": stats["fn"],
            "tp": stats["tp"],
            "is_synthetic": "FALSE",
            "split_description": split_desc,
        },
    )
    print(
        f"[external:{args.panel}] Day{day} AUC={stats['auc']:.4f} Acc={stats['acc']:.4f} "
        f"n={stats['n']} (dead={stats['n_pos']}, alive={stats['n_neg']}) -> {out}"
    )


if __name__ == "__main__":
    main()
