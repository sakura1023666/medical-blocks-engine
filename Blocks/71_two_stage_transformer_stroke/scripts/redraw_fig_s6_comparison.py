#!/usr/bin/env python3
"""Supplementary Figure S6：五模型 × AUC/Accuracy/F1 分组柱图（对齐 Yang pbaf003 补充图）。

口径：
  - 模型：Decision Tree / XGBoost / MLP / LSTM / Two-stage Transformer
  - 主文柱图：Day 5（L120）test 集 **bootstrap mean ± SD**（n_boot=400；与 Table 3 同口径）
  - 基线模型在 Day d 使用截至第 d 天的特征（与 Transformer cutoff 对齐）
  - 阈值：Youden（与 Fig2/Fig3 一致）
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

# 同目录星号工具（Windows 直接跑本脚本时需把 scripts 加入 path）
_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))
from pub_pvalue_stars import STAR_FOOTNOTE, pub_pvalue_stars  # noqa: E402


def _to_path(p: str | Path) -> Path:
    s = str(p)
    if s.startswith("/mnt/") and len(s) > 7 and s[6] == "/":
        return Path(f"{s[5].upper()}:/{s[7:]}".replace("\\", "/"))
    return Path(s)


def _parse_args():
    import argparse

    ap = argparse.ArgumentParser(description="Model comparison bar chart (Yang S6 layout)")
    ap.add_argument("--project-root", default=os.environ.get("TST_S6_PROJ", ""))
    ap.add_argument("--landmark", type=int, default=int(os.environ.get("TST_S6_LANDMARK", "120") or "120"))
    ap.add_argument("--out", default=os.environ.get("TST_S6_OUT", ""))
    ap.add_argument("--day", type=int, default=int(os.environ.get("TST_S6_DAY", "5") or "5"))
    ap.add_argument("--bootstrap", type=int, default=400)
    return ap.parse_args()


ARGS = _parse_args()
PROJ_CANDS = [
    Path(r"G:/02block_result/33_AKI/two_stage_transformer_40041421"),
    Path(r"G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
    Path("/mnt/g/02block_result/33_AKI/two_stage_transformer_40041421"),
    Path("/mnt/g/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
]
PROJ = _to_path(ARGS.project_root) if ARGS.project_root else next((p for p in PROJ_CANDS if p.exists()), PROJ_CANDS[0])
_LM = int(ARGS.landmark)
for _ud in (
    PROJ / f"by_unit/【success】L{_LM}_B_twostage/step09_tst_train_eval/Tables",
    PROJ / f"by_unit/L{_LM}_B_twostage/step09_tst_train_eval/Tables",
):
    if _ud.exists():
        UD = _ud
        break
else:
    UD = PROJ / f"by_unit/【success】L{_LM}_B_twostage/step09_tst_train_eval/Tables"
DATA = UD / "npz"
MODEL_B = UD / "model_b.pth"
OUT = _to_path(
    ARGS.out or str(PROJ / "summary_results/Figures/Figure S6-MIMIC-Model_comparison_bar.pdf")
)
OUT_CSV = PROJ / f"summary_results/by_landmark/L{_LM}/Tables/Table_S6_model_comparison_metrics.csv"
_BAR_DAY = int(ARGS.day)
_BOOT = max(50, int(ARGS.bootstrap))


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


def bootstrap_mean_sd(y, scores, *, n_boot: int = 400, seed: int = 42):
    """Patient-level bootstrap mean and SD for AUC/Acc/F1."""
    rng = np.random.default_rng(seed)
    y = np.asarray(y, dtype=int)
    scores = np.asarray(scores, dtype=float)
    n = len(y)
    if n < 10:
        a, c, f = metrics_at(y, scores)
        return a, c, f, 0.0, 0.0, 0.0
    aucs, accs, f1s = [], [], []
    for _ in range(n_boot):
        idx = rng.integers(0, n, size=n)
        yy, ss = y[idx], scores[idx]
        if len(np.unique(yy)) < 2:
            continue
        a, c, f = metrics_at(yy, ss)
        if a == a:
            aucs.append(a)
            accs.append(c)
            f1s.append(f)
    if len(aucs) < 2:
        a, c, f = metrics_at(y, scores)
        return a, c, f, 0.0, 0.0, 0.0
    return (
        float(np.mean(aucs)),
        float(np.mean(accs)),
        float(np.mean(f1s)),
        float(np.std(aucs, ddof=1)),
        float(np.std(accs, ddof=1)),
        float(np.std(f1s, ddof=1)),
    )


def bootstrap_sd(y, scores, *, n_boot: int = 400, seed: int = 42):
    """Backward-compatible: return SD only."""
    *_, sd_auc, sd_acc, sd_f1 = bootstrap_mean_sd(y, scores, n_boot=n_boot, seed=seed)
    return sd_auc, sd_acc, sd_f1


def tabular_features_upto(ds, max_day: int):
    """截至 max_day 天的展平特征（与 Transformer cutoff 对齐）。"""
    X = _day_sequence_features(ds)
    d = min(max_day, X.shape[1])
    return X[:, :d, :].reshape(X.shape[0], -1)


def lstm_scores_upto(tr, te, max_day: int, *, seed: int = 42):
    import torch
    import torch.nn as nn

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    Xd_tr = _day_sequence_features(tr)
    Xd_te = _day_sequence_features(te)
    d = min(max_day, Xd_tr.shape[1])
    Xd_tr = Xd_tr[:, :d, :]
    Xd_te = Xd_te[:, :d, :]
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
    yt = torch.tensor(tr.y, dtype=torch.float32, device=device)
    net.train()
    for _ in range(30):
        opt.zero_grad()
        loss = nn.functional.binary_cross_entropy(net(xt), yt)
        loss.backward()
        opt.step()
    net.eval()
    with torch.no_grad():
        return net(torch.tensor(Xd_te, dtype=torch.float32, device=device)).cpu().numpy()


def train_baseline_scores_day(tr, te, day: int, seed: int = 42):
    """Day d：基线仅使用截至第 d 天特征；返回 test 概率向量。"""
    X_tr = tabular_features_upto(tr, day)
    X_te = tabular_features_upto(te, day)
    y_tr = tr.y
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
    out["LSTM"] = lstm_scores_upto(tr, te, day, seed=seed)
    return out


def main():
    tr = TSTDataset("train", str(DATA))
    te = TSTDataset("test", str(DATA))
    D, H, F = te.n_days, te.n_hours, te.n_features
    y = te.y
    los = te.day_mask.sum(1).astype(int)

    model_order = [
        "Decision Tree",
        "XGBoost",
        "MLP",
        "LSTM",
        "Two-stage Transformer",
    ]
    detail_rows = []
    series = {m: {"auc": [], "acc": [], "f1": []} for m in model_order}

    # 全 Day1–5 明细写入 CSV（供 Table 3 / 审计）
    dl = DataLoader(te, batch_size=64, shuffle=False)
    model = load_model_for_eval(str(MODEL_B), "b", D, H, F)
    t_scores = score_all_cutoffs(model, dl, D)

    for day in range(1, D + 1):
        sel = los >= day
        yy = y[sel]
        base_day = train_baseline_scores_day(tr, te, day)
        for name, scores in base_day.items():
            auc, acc, f1 = metrics_at(yy, scores[sel])
            series[name]["auc"].append(auc)
            series[name]["acc"].append(acc)
            series[name]["f1"].append(f1)
            detail_rows.append(
                {
                    "model": name,
                    "day": day,
                    "auc": round(auc, 4),
                    "accuracy": round(acc, 4),
                    "f1": round(f1, 4),
                    "n": int(sel.sum()),
                }
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

    # 柱图：主 landmark Day 5 test 集
    bar_day = min(_BAR_DAY, D)
    sel = los >= bar_day
    yy = y[sel]
    base_bar = train_baseline_scores_day(tr, te, bar_day)
    bar_scores = dict(base_bar)
    bar_scores["Two-stage Transformer"] = t_scores[bar_day]

    means = {m: {} for m in model_order}
    sds = {m: {} for m in model_order}
    points = {m: {} for m in model_order}
    for m in model_order:
        sc = bar_scores[m][sel]
        pt_auc, pt_acc, pt_f1 = metrics_at(yy, sc)
        m_auc, m_acc, m_f1, sd_auc, sd_acc, sd_f1 = bootstrap_mean_sd(yy, sc, n_boot=_BOOT)
        # 柱高 = bootstrap mean（与 Table 3 同口径）；误差线 = bootstrap SD
        means[m]["auc"], means[m]["acc"], means[m]["f1"] = m_auc, m_acc, m_f1
        sds[m]["auc"], sds[m]["acc"], sds[m]["f1"] = sd_auc, sd_acc, sd_f1
        points[m]["auc"], points[m]["acc"], points[m]["f1"] = pt_auc, pt_acc, pt_f1

    try:
        from scipy.stats import mannwhitneyu

        def boot_metric(sc, idx_metric=0):
            rng = np.random.default_rng(42)
            out = []
            for _ in range(_BOOT):
                ii = rng.integers(0, len(yy), size=len(yy))
                yb, sb = yy[ii], sc[ii]
                if len(np.unique(yb)) < 2:
                    continue
                out.append(metrics_at(yb, sb)[idx_metric])
            return np.asarray(out, dtype=float)

        t_auc = boot_metric(bar_scores["Two-stage Transformer"][sel], 0)
        t_acc = boot_metric(bar_scores["Two-stage Transformer"][sel], 1)
        t_f1 = boot_metric(bar_scores["Two-stage Transformer"][sel], 2)
        p_auc = min(
            mannwhitneyu(t_auc, boot_metric(bar_scores[m][sel], 0)).pvalue
            for m in model_order
            if m != "Two-stage Transformer" and len(t_auc) > 10
        )
        p_acc = min(
            mannwhitneyu(t_acc, boot_metric(bar_scores[m][sel], 1)).pvalue
            for m in model_order
            if m != "Two-stage Transformer" and len(t_acc) > 10
        )
        p_f1 = min(
            mannwhitneyu(t_f1, boot_metric(bar_scores[m][sel], 2)).pvalue
            for m in model_order
            if m != "Two-stage Transformer" and len(t_f1) > 10
        )
    except Exception:
        p_auc = p_acc = p_f1 = float("nan")

    def plab(p):
        # 统一星号：* P<0.05, ** P<0.01, *** P<0.001（禁止再写 P=0.xxx）
        return pub_pvalue_stars(p, show_ns=False)

    # Plot Yang S6 style (Day 5 test, bootstrap SD)
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
        star = plab(p)
        if star:
            ax.text(
                j,
                min(max(tops) + 0.04, 1.05),
                star,
                ha="center",
                va="bottom",
                color="#c62828",
                fontsize=12,
                fontweight="bold",
            )

    ax.set_ylim(0, 1.08)
    ax.set_xticks(x0)
    ax.set_xticklabels([lab for _, lab in metrics], fontsize=11)
    ax.set_ylabel("Mean ± SD", fontsize=11)
    ax.set_title(f"Comparison of Models (Day {bar_day}, test set)", fontsize=13)
    ax.yaxis.grid(True, linestyle="--", alpha=0.5)
    ax.set_axisbelow(True)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    # F1 柱较低，图例放右上空白处，避免挡住 AUC 柱顶
    ax.legend(frameon=True, fontsize=8.5, loc="upper right", framealpha=0.95)
    ax.text(
        0.5,
        -0.12,
        rf"Mann–Whitney U (min vs baselines); {STAR_FOOTNOTE}",
        transform=ax.transAxes,
        ha="center",
        va="top",
        fontsize=7.5,
    )
    fig.tight_layout()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT, format="pdf", bbox_inches="tight")
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
    with (OUT_CSV.parent / "Table_S6_model_comparison_pvalues.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["metric", "pvalue", "star", "test", "note"])
        w.writeheader()
        for metric, p in (("auc", p_auc), ("acc", p_acc), ("f1", p_f1)):
            w.writerow(
                {
                    "metric": metric,
                    "pvalue": "" if p != p else f"{p:.6g}",
                    "star": pub_pvalue_stars(p, show_ns=False),
                    "test": "MannWhitney_min_vs_Transformer_bootstrap",
                    "note": (
                        f"Day{bar_day} test bootstrap mean(SD); "
                        "stars on figure: * P<0.05, ** P<0.01, *** P<0.001"
                    ),
                }
            )

    # 铁律：重导 S6 后必须同口径重写 Table 3，禁止图新表旧
    try:
        from build_summary_results import _build_table3_from_s6

        t3_dir = PROJ / "summary_results" / "Tables"
        t3_dir.mkdir(parents=True, exist_ok=True)
        ok = _build_table3_from_s6(PROJ, _LM, t3_dir)
        print(f"[S6→Table3] rebuild={'OK' if ok else 'FAIL'} lm=L{_LM}")
    except Exception as e:
        print(f"[S6→Table3] WARNING: Table 3 not rebuilt ({e}); run build_summary_results or _build_table3_from_s6")


if __name__ == "__main__":
    main()
