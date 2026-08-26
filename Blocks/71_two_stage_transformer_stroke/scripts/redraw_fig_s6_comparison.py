#!/usr/bin/env python3
"""Supplementary Figure S6：五模型 × AUC/Accuracy/F1 分组柱图（对齐 Yang pbaf003 补充图）。

口径：
  - 模型：Decision Tree / XGBoost / MLP / LSTM / Two-stage Transformer
  - 每个指标：Day1–5 在 los>=day 子集上算点估计，再报 mean±SD
  - 阈值：Youden（与 Fig3 一致）
  - DT 为本次补跑【场景迁移】；无伪造原文数值
"""
from __future__ import annotations

import csv
import os
import sys
from pathlib import Path

os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

import matplotlib

matplotlib.use("Agg")
import numpy as np
from matplotlib import pyplot as plt
from sklearn.metrics import f1_score, roc_auc_score, roc_curve
from torch.utils.data import DataLoader

REPO = Path(r"E:/01block/01Block-new-Final")
if not REPO.exists():
    REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO))

from python.two_stage_transformer.baselines import (  # noqa: E402
    _day_sequence_features,
    _tabular_features,
)
from python.two_stage_transformer.dataloader import TSTDataset  # noqa: E402
from python.two_stage_transformer.eval import load_model_for_eval, score_all_cutoffs  # noqa: E402

PROJ = Path(r"G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421")
DATA = PROJ / "by_unit/【success】L72_B_twostage/step09_tst_train_eval/Tables/npz"
MODEL_B = PROJ / "by_unit/【success】L72_B_twostage/step09_tst_train_eval/Tables/model_b.pth"
OUT = PROJ / "summary_results/Figures/Figure S6-MIMIC-Model_comparison_bar.pdf"
OUT_CSV = PROJ / "summary_results/by_landmark/L72/Tables/Table_S6_model_comparison_metrics.csv"


def youden_pred(y, scores):
    fpr, tpr, thr = roc_curve(y, scores)
    if len(thr) == 0:
        return np.zeros_like(y), 0.5
    opt = float(thr[np.argmax(tpr - fpr)])
    return (scores > opt).astype(int), opt


def metrics_at(y, scores):
    if len(y) == 0 or len(np.unique(y)) < 2:
        return float("nan"), float("nan"), float("nan")
    auc = float(roc_auc_score(y, scores))
    pred, _ = youden_pred(y, scores)
    acc = float((pred == y).mean())
    f1 = float(f1_score(y, pred, zero_division=0))
    return auc, acc, f1


def train_baseline_scores(seed: int = 42):
    """返回 {name: test_scores ndarray}。"""
    tr, va, te = TSTDataset("train", str(DATA)), TSTDataset("val", str(DATA)), TSTDataset("test", str(DATA))
    X_tr, y_tr = _tabular_features(tr), tr.y
    X_te, y_te = _tabular_features(te), te.y
    mu, sd = X_tr.mean(0), X_tr.std(0)
    sd[sd < 1e-8] = 1.0
    X_tr_s, X_te_s = (X_tr - mu) / sd, (X_te - mu) / sd
    out = {}

    from sklearn.tree import DecisionTreeClassifier

    dt = DecisionTreeClassifier(max_depth=6, random_state=seed, class_weight="balanced")
    dt.fit(X_tr, y_tr)
    out["Decision Tree"] = dt.predict_proba(X_te)[:, 1]

    try:
        from xgboost import XGBClassifier

        xgb = XGBClassifier(
            n_estimators=200,
            max_depth=4,
            random_state=seed,
            eval_metric="logloss",
            use_label_encoder=False,
        )
    except Exception:
        from sklearn.ensemble import GradientBoostingClassifier

        xgb = GradientBoostingClassifier(n_estimators=150, random_state=seed)
    xgb.fit(X_tr, y_tr)
    out["XGBoost"] = xgb.predict_proba(X_te)[:, 1]

    from sklearn.neural_network import MLPClassifier

    mlp = MLPClassifier(hidden_layer_sizes=(64, 32), max_iter=400, random_state=seed)
    mlp.fit(X_tr_s, y_tr)
    out["MLP"] = mlp.predict_proba(X_te_s)[:, 1]

    # LSTM
    import torch
    import torch.nn as nn

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    Xd_tr = _day_sequence_features(tr)
    Xd_te = _day_sequence_features(te)
    mu2 = Xd_tr.reshape(-1, Xd_tr.shape[-1]).mean(0)
    sd2 = Xd_tr.reshape(-1, Xd_tr.shape[-1]).std(0)
    sd2[sd2 < 1e-8] = 1.0
    Xd_tr = (Xd_tr - mu2) / sd2
    Xd_te = (Xd_te - mu2) / sd2

    class TinyLSTM(nn.Module):
        def __init__(self, n_feat, hidden=32):
            super().__init__()
            self.lstm = nn.LSTM(n_feat, hidden, batch_first=True)
            self.fc = nn.Linear(hidden, 1)

        def forward(self, x):
            o, _ = self.lstm(x)
            return torch.sigmoid(self.fc(o[:, -1, :])).squeeze(-1)

    net = TinyLSTM(Xd_tr.shape[-1]).to(device)
    opt = torch.optim.Adam(net.parameters(), lr=1e-3)
    xt = torch.tensor(Xd_tr, dtype=torch.float32, device=device)
    yt = torch.tensor(y_tr, dtype=torch.float32, device=device)
    net.train()
    for _ in range(30):
        opt.zero_grad()
        loss = nn.functional.binary_cross_entropy(net(xt), yt)
        loss.backward()
        opt.step()
    net.eval()
    with torch.no_grad():
        out["LSTM"] = net(torch.tensor(Xd_te, dtype=torch.float32, device=device)).cpu().numpy()

    return out, te


def main():
    te = TSTDataset("test", str(DATA))
    D, H, F = te.n_days, te.n_hours, te.n_features
    y = te.y
    los = te.day_mask.sum(1).astype(int)

    base_scores, _ = train_baseline_scores()
    # Transformer day scores
    dl = DataLoader(te, batch_size=64, shuffle=False)
    model = load_model_for_eval(str(MODEL_B), "b", D, H, F)
    t_scores = score_all_cutoffs(model, dl, D)

    model_order = [
        "Decision Tree",
        "XGBoost",
        "MLP",
        "LSTM",
        "Two-stage Transformer",
    ]
    # per model: list of (auc,acc,f1) over days
    series = {m: {"auc": [], "acc": [], "f1": []} for m in model_order}
    detail_rows = []

    for day in range(1, D + 1):
        sel = los >= day
        yy = y[sel]
        for name, scores in base_scores.items():
            auc, acc, f1 = metrics_at(yy, scores[sel])
            series[name]["auc"].append(auc)
            series[name]["acc"].append(acc)
            series[name]["f1"].append(f1)
            detail_rows.append(
                {"model": name, "day": day, "auc": round(auc, 4), "accuracy": round(acc, 4), "f1": round(f1, 4), "n": int(sel.sum())}
            )
        auc, acc, f1 = metrics_at(yy, t_scores[day][sel])
        series["Two-stage Transformer"]["auc"].append(auc)
        series["Two-stage Transformer"]["acc"].append(acc)
        series["Two-stage Transformer"]["f1"].append(f1)
        detail_rows.append(
            {
                "model": "Two-stage Transformer",
                "day": day,
                "auc": round(auc, 4),
                "accuracy": round(acc, 4),
                "f1": round(f1, 4),
                "n": int(sel.sum()),
            }
        )

    # Mann-Whitney across models' day-AUCs (overall annotation like paper)
    try:
        from scipy.stats import kruskal

        p_auc = kruskal(*[series[m]["auc"] for m in model_order]).pvalue
        p_acc = kruskal(*[series[m]["acc"] for m in model_order]).pvalue
        p_f1 = kruskal(*[series[m]["f1"] for m in model_order]).pvalue
    except Exception:
        p_auc = p_acc = p_f1 = float("nan")

    def plab(p):
        if p != p:
            return ""
        return r"$P < 0.001$" if p < 0.001 else rf"$P = {p:.3f}$"

    means = {m: {} for m in model_order}
    sds = {m: {} for m in model_order}
    for m in model_order:
        for k in ("auc", "acc", "f1"):
            arr = np.asarray(series[m][k], dtype=float)
            means[m][k] = float(np.nanmean(arr))
            sds[m][k] = float(np.nanstd(arr, ddof=1)) if len(arr) > 1 else 0.0

    # Plot Yang S6 style
    colors = {
        "Decision Tree": "#9ecae1",
        "XGBoost": "#a1d99b",
        "MLP": "#fcbba1",
        "LSTM": "#fff7bc",
        "Two-stage Transformer": "#bdbdbd",
    }
    metrics = [("auc", "AUC"), ("acc", "Accuracy"), ("f1", "F1-score")]
    x0 = np.arange(len(metrics))
    n_m = len(model_order)
    width = 0.15
    fig, ax = plt.subplots(figsize=(9.2, 5.6), dpi=160)

    for i, m in enumerate(model_order):
        xs = x0 + (i - (n_m - 1) / 2) * width
        vals = [means[m][k] for k, _ in metrics]
        errs = [sds[m][k] for k, _ in metrics]
        hatch = "///" if m == "Two-stage Transformer" else None
        ax.bar(
            xs,
            vals,
            width,
            yerr=errs,
            capsize=3,
            color=colors[m],
            edgecolor="black",
            linewidth=0.8,
            hatch=hatch,
            label=m,
            error_kw={"ecolor": "black", "lw": 1},
        )

    for j, ((k, _), p) in enumerate(zip(metrics, [p_auc, p_acc, p_f1])):
        tops = [means[m][k] + sds[m][k] for m in model_order]
        ax.text(j, min(max(tops) + 0.04, 1.05), plab(p), ha="center", va="bottom", color="#c62828", fontsize=10)

    ax.set_ylim(0, 1.08)
    ax.set_xticks(x0)
    ax.set_xticklabels([lab for _, lab in metrics], fontsize=11)
    ax.set_ylabel("Mean ± SD", fontsize=11)
    ax.set_title("Comparison of Models", fontsize=13)
    ax.yaxis.grid(True, linestyle="--", alpha=0.5)
    ax.set_axisbelow(True)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.legend(frameon=True, fontsize=9, loc="upper left")
    fig.tight_layout()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT, format="pdf")
    fig.savefig(OUT.with_suffix(".png"), dpi=160)
    plt.close(fig)

    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["model", "day", "auc", "accuracy", "f1", "n"])
        w.writeheader()
        w.writerows(detail_rows)
    # summary
    with (OUT_CSV.parent / "Table_S6_model_comparison_summary.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["model", "auc_mean", "auc_sd", "acc_mean", "acc_sd", "f1_mean", "f1_sd"])
        w.writeheader()
        for m in model_order:
            w.writerow(
                {
                    "model": m,
                    "auc_mean": round(means[m]["auc"], 4),
                    "auc_sd": round(sds[m]["auc"], 4),
                    "acc_mean": round(means[m]["acc"], 4),
                    "acc_sd": round(sds[m]["acc"], 4),
                    "f1_mean": round(means[m]["f1"], 4),
                    "f1_sd": round(sds[m]["f1"], 4),
                }
            )

    print("wrote", OUT)
    for m in model_order:
        print(
            f"{m}: AUC {means[m]['auc']:.3f}±{sds[m]['auc']:.3f} | "
            f"Acc {means[m]['acc']:.3f}±{sds[m]['acc']:.3f} | "
            f"F1 {means[m]['f1']:.3f}±{sds[m]['f1']:.3f}"
        )
    print(f"Kruskal p_auc={p_auc} p_acc={p_acc} p_f1={p_f1}")


if __name__ == "__main__":
    main()
