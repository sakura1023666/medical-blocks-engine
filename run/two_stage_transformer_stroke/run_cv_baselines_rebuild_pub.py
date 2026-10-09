#!/usr/bin/env python3
"""On existing CV folds: train DT/XGB/MLP/LSTM, eval Day1–5, rebuild Table3 + S6.

原文证据（Yang 2025 pbaf003）：
  - Table 2 / Table 3 标题均为 performance [mean (SD)] → 用重复 7:2:1 汇总
  - Supp Fig 6：模型对比柱图 Mean±SD（与 Table 3 同源）→ CV Day5
  - Figure 3：全文写明 results derived from the testing data；ROC/CM/柱图
    均来自**同一次 test**；柱图 Mean±SD = 该 test 上 Day1–5 的日间波动，
    Mann–Whitney 比较跨日指标。Fig 3 **不**混用 CV → 由 redraw_fig3_sapsii.py 单独出图
  - Table 1 / Fig 4 / S1–S5：非 CV → 不改

【证据不足】原文未写明 Table 2/3 的 SD 来自几折；公开代码为单次 seed=41。
"""
from __future__ import annotations

import csv
import json
import math
import os
import sys
from collections import defaultdict
from pathlib import Path

os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

import numpy as np
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, Side
from openpyxl.utils import get_column_letter
from torch.utils.data import DataLoader

REPO_CANDS = [
    Path(r"E:/01block/01Block-new-Final"),
    Path("/mnt/e/01block/01Block-new-Final"),
]
PROJ_CANDS = [
    Path(r"G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
    Path("/mnt/g/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
]
FONT = "Times New Roman"
MODEL_ORDER = [
    "Decision Tree",
    "XGBoost",
    "MLP",
    "LSTM",
    "Two-stage Transformer",
]


def find_path(cands: list[Path]) -> Path:
    for p in cands:
        if p.exists():
            return p
    raise SystemExit(f"not found: {cands}")


REPO = find_path(REPO_CANDS)
PROJ = find_path(PROJ_CANDS)
sys.path.insert(0, str(REPO))

from python.two_stage_transformer.baselines import (  # noqa: E402
    _day_sequence_features,
    _tabular_features,
)
from python.two_stage_transformer.dataloader import TSTDataset  # noqa: E402
from python.two_stage_transformer.eval import load_model_for_eval, score_all_cutoffs  # noqa: E402

CV_ROOT = PROJ / "summary_results" / "cv_table2_repeated_split"
SEEDS = [41, 42, 43, 44, 45]


def roc_curve_np(y_true, y_score):
    y_true = np.asarray(y_true).astype(int)
    y_score = np.asarray(y_score, dtype=float)
    order = np.argsort(-y_score)
    y_true, y_score = y_true[order], y_score[order]
    tps = np.cumsum(y_true == 1)
    fps = np.cumsum(y_true == 0)
    P = max(int((y_true == 1).sum()), 1)
    N = max(int((y_true == 0).sum()), 1)
    return fps / N, tps / P, y_score


def auc_trapz(fpr, tpr):
    fpr = np.concatenate([[0.0], np.asarray(fpr, float), [1.0]])
    tpr = np.concatenate([[0.0], np.asarray(tpr, float), [1.0]])
    order = np.argsort(fpr)
    fpr, tpr = fpr[order], tpr[order]
    return float(np.trapezoid(tpr, fpr)) if hasattr(np, "trapezoid") else float(np.trapz(tpr, fpr))


def roc_auc_score(y_true, y_score):
    if len(np.unique(y_true)) < 2:
        return float("nan")
    fpr, tpr, _ = roc_curve_np(y_true, y_score)
    return auc_trapz(fpr, tpr)


def youden_pred(y, scores):
    fpr, tpr, thr = roc_curve_np(y, scores)
    opt = float(thr[np.argmax(tpr - fpr)]) if len(thr) else 0.5
    return (scores > opt).astype(int), opt


def f1_score_binary(y_true, y_pred):
    y_true = np.asarray(y_true).astype(int)
    y_pred = np.asarray(y_pred).astype(int)
    tp = int(((y_true == 1) & (y_pred == 1)).sum())
    fp = int(((y_true == 0) & (y_pred == 1)).sum())
    fn = int(((y_true == 1) & (y_pred == 0)).sum())
    prec = tp / (tp + fp) if (tp + fp) else 0.0
    rec = tp / (tp + fn) if (tp + fn) else 0.0
    if prec + rec == 0:
        return 0.0
    return 2 * prec * rec / (prec + rec)


def metrics_at(y, scores):
    if len(y) < 5 or len(np.unique(y)) < 2:
        return float("nan"), float("nan"), float("nan")
    auc = float(roc_auc_score(y, scores))
    pred, _ = youden_pred(y, scores)
    acc = float((pred == y).mean())
    f1 = float(f1_score_binary(y, pred))
    return auc, acc, f1


def train_baseline_scores(data_dir: Path, seed: int = 42) -> dict[str, np.ndarray]:
    tr = TSTDataset("train", str(data_dir))
    te = TSTDataset("test", str(data_dir))
    X_tr, y_tr = _tabular_features(tr), tr.y
    X_te = _tabular_features(te)
    mu, sd = X_tr.mean(0), X_tr.std(0)
    sd[sd < 1e-8] = 1.0
    X_tr_s, X_te_s = (X_tr - mu) / sd, (X_te - mu) / sd
    out: dict[str, np.ndarray] = {}

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
    return out


def eval_transformer(data_dir: Path, model_path: Path) -> dict[int, tuple[float, float, float, int]]:
    te = TSTDataset("test", str(data_dir))
    D, H, F = te.n_days, te.n_hours, te.n_features
    dl = DataLoader(te, batch_size=64, shuffle=False)
    model = load_model_for_eval(str(model_path), "b", D, H, F)
    scores = score_all_cutoffs(model, dl, D)
    y, los = te.y, te.day_mask.sum(1).astype(int)
    out = {}
    for day in range(1, min(D, 5) + 1):
        sel = los >= day
        auc, acc, f1 = metrics_at(y[sel], scores[day][sel])
        out[day] = (auc, acc, f1, int(sel.sum()))
    return out


def eval_score_days(y, los, scores: np.ndarray) -> dict[int, tuple[float, float, float, int]]:
    out = {}
    for day in range(1, 6):
        sel = los >= day
        auc, acc, f1 = metrics_at(y[sel], scores[sel])
        out[day] = (auc, acc, f1, int(sel.sum()))
    return out


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        return
    keys = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)


def fmt_mean_sd(vals: list[float], *, kind: str) -> str:
    a = np.asarray(vals, dtype=float)
    a = a[np.isfinite(a)]
    if a.size == 0:
        return "—"
    if a.size == 1:
        v = float(a[0])
        if kind == "acc":
            return f"{100.0 * v:.2f}"
        if kind == "f1":
            return f"{v:.3f}"
        return f"{v:.2f}"
    m, s = float(a.mean()), float(a.std(ddof=1))
    if kind == "acc":
        return f"{100.0 * m:.2f} ({100.0 * s:.2f})"
    if kind == "f1":
        return f"{m:.3f} ({s:.3f})"
    return f"{m:.2f} ({s:.3f})"


def p_value_kruskal(groups: list[list[float]]) -> float:
    clean = [np.asarray(g, float)[np.isfinite(g)] for g in groups]
    clean = [g for g in clean if len(g) >= 2]
    if len(clean) < 2:
        return float("nan")
    try:
        from scipy.stats import kruskal

        return float(kruskal(*clean).pvalue)
    except Exception:
        # scipy 不可用时：手工 Kruskal–Wallis H → chi2 近似 p
        try:
            from scipy.stats import chi2
        except Exception:
            chi2 = None
        all_vals = np.concatenate(clean)
        ranks = all_vals.argsort().argsort().astype(float) + 1.0
        # tie-aware average ranks
        # simple rankdata midrank
        order = np.argsort(all_vals)
        sorted_vals = all_vals[order]
        midranks = np.empty_like(sorted_vals, dtype=float)
        i = 0
        n = len(sorted_vals)
        while i < n:
            j = i
            while j < n and sorted_vals[j] == sorted_vals[i]:
                j += 1
            midranks[i:j] = 0.5 * (i + j - 1) + 1.0
            i = j
        ranks = np.empty_like(midranks)
        ranks[order] = midranks
        N = len(all_vals)
        idx = 0
        h = 0.0
        for g in clean:
            rg = ranks[idx : idx + len(g)]
            idx += len(g)
            h += len(g) * (rg.mean() ** 2)
        h = 12.0 / (N * (N + 1)) * h - 3.0 * (N + 1)
        df = len(clean) - 1
        if chi2 is not None:
            return float(chi2.sf(h, df))
        # 极粗近似：无 chi2 时返回 nan 避免假显著
        return float("nan")


def run_fold_baselines(seed: int) -> list[dict]:
    fold = CV_ROOT / f"seed_{seed}"
    data_dir = fold / "npz"
    model_path = fold / "Tables" / "model_b.pth"
    out_csv = fold / "fold_all_models_day_metrics.csv"
    if out_csv.is_file():
        print(f"[cv-base] resume seed={seed}")
        with out_csv.open(encoding="utf-8-sig") as f:
            return list(csv.DictReader(f))

    print(f"[cv-base] seed={seed} training baselines...", flush=True)
    te = TSTDataset("test", str(data_dir))
    y, los = te.y, te.day_mask.sum(1).astype(int)
    base = train_baseline_scores(data_dir, seed=42)
    rows = []
    for name, scores in base.items():
        day_m = eval_score_days(y, los, scores)
        for day, (auc, acc, f1, n) in day_m.items():
            rows.append(
                {
                    "seed": seed,
                    "model": name,
                    "day": day,
                    "auc": auc,
                    "acc": acc,
                    "f1": f1,
                    "n": n,
                }
            )
            print(f"  {name} Day{day}: AUC={auc:.3f} Acc={acc:.3f} F1={f1:.3f}", flush=True)

    if model_path.is_file():
        tr = eval_transformer(data_dir, model_path)
        for day, (auc, acc, f1, n) in tr.items():
            rows.append(
                {
                    "seed": seed,
                    "model": "Two-stage Transformer",
                    "day": day,
                    "auc": auc,
                    "acc": acc,
                    "f1": f1,
                    "n": n,
                }
            )
            print(f"  Transformer Day{day}: AUC={auc:.3f} Acc={acc:.3f} F1={f1:.3f}", flush=True)
    write_csv(out_csv, rows)
    return rows


def collect_all() -> list[dict]:
    all_rows: list[dict] = []
    for seed in SEEDS:
        fold = CV_ROOT / f"seed_{seed}"
        if not (fold / "npz" / "test.npz").is_file():
            print(f"[cv-base] skip missing fold seed={seed}")
            continue
        raw = run_fold_baselines(seed)
        for r in raw:
            all_rows.append(
                {
                    "seed": int(float(r["seed"])),
                    "model": str(r["model"]),
                    "day": int(float(r["day"])),
                    "auc": float(r["auc"]) if r.get("auc") not in ("", None) else float("nan"),
                    "acc": float(r["acc"]) if r.get("acc") not in ("", None) else float("nan"),
                    "f1": float(r["f1"]) if r.get("f1") not in ("", None) else float("nan"),
                    "n": int(float(r["n"])) if r.get("n") not in ("", None) else 0,
                }
            )
    return all_rows


def rebuild_table3(rows: list[dict]) -> Path:
    """Yang Table 3: rows=metrics, cols=models + P; Day-5 mean(SD) across CV seeds."""
    day5 = [r for r in rows if r["day"] == 5]
    by_model: dict[str, dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))
    for r in day5:
        for k in ("auc", "acc", "f1"):
            if math.isfinite(r[k]):
                by_model[r["model"]][k].append(r[k])

    p_auc = p_value_kruskal([by_model[m]["auc"] for m in MODEL_ORDER])
    p_acc = p_value_kruskal([by_model[m]["acc"] for m in MODEL_ORDER])
    p_f1 = p_value_kruskal([by_model[m]["f1"] for m in MODEL_ORDER])

    def plab(p: float) -> str:
        if p != p:
            return "—"
        return "< 0.001" if p < 0.001 else f"{p:.3f}"

    headers = ["Metric"] + MODEL_ORDER + ["P-value"]
    table_rows = [
        ["AUC"]
        + [fmt_mean_sd(by_model[m]["auc"], kind="auc") for m in MODEL_ORDER]
        + [plab(p_auc)],
        ["Accuracy (%)"]
        + [fmt_mean_sd(by_model[m]["acc"], kind="acc") for m in MODEL_ORDER]
        + [plab(p_acc)],
        ["F1-scoreᵃ"]
        + [fmt_mean_sd(by_model[m]["f1"], kind="f1") for m in MODEL_ORDER]
        + [plab(p_f1)],
    ]

    title = (
        "Table 3-MIMIC. Comparative performance metrics [mean (SD)] of predictive models "
        "for in-hospital mortality"
    )
    footnotes = ["ᵃ F1-score, harmonic mean of precision and recall."]

    path = (
        PROJ
        / "summary_results/Tables"
        / f"{title}.xlsx"
    )
    _write_sci_table(path, title, headers, table_rows, footnotes, widths=[14, 14, 14, 14, 14, 16, 10])
    old = PROJ / "summary_results/Tables/Table 3-MIMIC-Comparative_model_performance.xlsx"
    if old.is_file() and old.resolve() != path.resolve():
        old.unlink(missing_ok=True)
    return path


def rebuild_s6(rows: list[dict]) -> Path:
    """Supp Fig S6: bar Mean±SD from Day-5 CV folds (same source as Table 3)."""
    import matplotlib

    matplotlib.use("Agg")
    from matplotlib import pyplot as plt

    day5 = [r for r in rows if r["day"] == 5]
    means = {m: {} for m in MODEL_ORDER}
    sds = {m: {} for m in MODEL_ORDER}
    groups = {k: [] for k in ("auc", "acc", "f1")}
    for m in MODEL_ORDER:
        for k in ("auc", "acc", "f1"):
            vals = [r[k] for r in day5 if r["model"] == m and math.isfinite(r[k])]
            arr = np.asarray(vals, float)
            means[m][k] = float(np.nanmean(arr)) if len(arr) else float("nan")
            sds[m][k] = float(np.nanstd(arr, ddof=1)) if len(arr) > 1 else 0.0
            groups[k].append(vals)

    p = {k: p_value_kruskal(groups[k]) for k in groups}

    def plab(pv):
        if pv != pv:
            return ""
        return r"$P < 0.001$" if pv < 0.001 else rf"$P = {pv:.3f}$"

    colors = {
        "Decision Tree": "#9ecae1",
        "XGBoost": "#a1d99b",
        "MLP": "#fcbba1",
        "LSTM": "#fff7bc",
        "Two-stage Transformer": "#bdbdbd",
    }
    metrics = [("auc", "AUC"), ("acc", "Accuracy"), ("f1", "F1-score")]
    x0 = np.arange(len(metrics))
    n_m = len(MODEL_ORDER)
    width = 0.15
    fig, ax = plt.subplots(figsize=(9.2, 5.6), dpi=160)
    for i, m in enumerate(MODEL_ORDER):
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
    for j, ((k, _), pv) in enumerate(zip(metrics, [p["auc"], p["acc"], p["f1"]])):
        tops = [means[m][k] + sds[m][k] for m in MODEL_ORDER]
        ax.text(j, min(max(tops) + 0.04, 1.05), plab(pv), ha="center", va="bottom", color="#c62828", fontsize=10)

    ax.set_ylim(0, 1.08)
    ax.set_xticks(x0)
    ax.set_xticklabels([lab for _, lab in metrics], fontsize=11)
    ax.set_ylabel("Mean ± SD (Day 5, 5×7:2:1)", fontsize=10)
    ax.set_title("Comparison of Models", fontsize=13)
    ax.yaxis.grid(True, linestyle="--", alpha=0.5)
    ax.set_axisbelow(True)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.legend(frameon=True, fontsize=9, loc="upper left")
    fig.tight_layout()

    out = PROJ / "summary_results/Figures/Figure S6-MIMIC-Model_comparison_bar.pdf"
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, format="pdf")
    fig.savefig(out.with_suffix(".png"), dpi=160)
    plt.close(fig)

    # refresh S6 summary csv
    s6_sum = PROJ / "summary_results/by_landmark/L72/Tables/Table_S6_model_comparison_summary.csv"
    s6_met = PROJ / "summary_results/by_landmark/L72/Tables/Table_S6_model_comparison_metrics.csv"
    s6_sum.parent.mkdir(parents=True, exist_ok=True)
    with s6_sum.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(
            f, fieldnames=["model", "auc_mean", "auc_sd", "acc_mean", "acc_sd", "f1_mean", "f1_sd", "source"]
        )
        w.writeheader()
        for m in MODEL_ORDER:
            w.writerow(
                {
                    "model": m,
                    "auc_mean": round(means[m]["auc"], 4),
                    "auc_sd": round(sds[m]["auc"], 4),
                    "acc_mean": round(means[m]["acc"], 4),
                    "acc_sd": round(sds[m]["acc"], 4),
                    "f1_mean": round(means[m]["f1"], 4),
                    "f1_sd": round(sds[m]["f1"], 4),
                    "source": "cv_day5_5x721",
                }
            )
    # day-level detail from CV
    with s6_met.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["model", "day", "auc", "accuracy", "f1", "n", "seed"])
        w.writeheader()
        for r in rows:
            w.writerow(
                {
                    "model": r["model"],
                    "day": r["day"],
                    "auc": round(r["auc"], 4) if math.isfinite(r["auc"]) else "",
                    "accuracy": round(r["acc"], 4) if math.isfinite(r["acc"]) else "",
                    "f1": round(r["f1"], 4) if math.isfinite(r["f1"]) else "",
                    "n": r["n"],
                    "seed": r["seed"],
                }
            )
    print("wrote", out)
    return out


def rebuild_fig3_bars_from_cv(rows: list[dict]) -> None:
    """Update Fig3 Comparison panel via full redraw using CV mean±SD for bars;
    ROC/CM still from paper seed=41 fold (testing-data style)."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.colors as mcolors
    from matplotlib import pyplot as plt
    from sklearn.metrics import roc_curve

    # --- CV bar stats: per fold, mean of Day1-5; then mean±SD across folds ---
    fold_t = defaultdict(lambda: {"auc": [], "acc": []})
    fold_s = defaultdict(lambda: {"auc": [], "acc": []})
    # Transformer from all-model rows
    for r in rows:
        if r["model"] == "Two-stage Transformer" and math.isfinite(r["auc"]):
            fold_t[r["seed"]]["auc"].append(r["auc"])
            fold_t[r["seed"]]["acc"].append(r["acc"])

    # SAPSII from original CV fold csv
    saps_csv = CV_ROOT / "Table_CV_fold_day_metrics.csv"
    if saps_csv.is_file():
        with saps_csv.open(encoding="utf-8-sig") as f:
            for r in csv.DictReader(f):
                if str(r.get("model", "")).upper().startswith("SAPS"):
                    seed = int(float(r["seed"]))
                    fold_s[seed]["auc"].append(float(r["auc"]))
                    fold_s[seed]["acc"].append(float(r["acc"]))

    t_auc = [float(np.mean(v["auc"])) for v in fold_t.values() if v["auc"]]
    t_acc = [float(np.mean(v["acc"])) for v in fold_t.values() if v["acc"]]
    s_auc = [float(np.mean(v["auc"])) for v in fold_s.values() if v["auc"]]
    s_acc = [float(np.mean(v["acc"])) for v in fold_s.values() if v["acc"]]

    def ms(a):
        a = np.asarray(a, float)
        a = a[np.isfinite(a)]
        if len(a) == 0:
            return float("nan"), 0.0
        if len(a) == 1:
            return float(a[0]), 0.0
        return float(a.mean()), float(a.std(ddof=1))

    mean_auc, sd_auc = ms(t_auc)
    mean_acc, sd_acc = ms(t_acc)
    mean_sa, sd_sa = ms(s_auc)
    mean_sc, sd_sc = ms(s_acc)
    try:
        from scipy.stats import mannwhitneyu

        p_auc = mannwhitneyu(t_auc, s_auc).pvalue if len(t_auc) and len(s_auc) else float("nan")
        p_acc = mannwhitneyu(t_acc, s_acc).pvalue if len(t_acc) and len(s_acc) else float("nan")
    except Exception:
        p_auc = p_acc = float("nan")

    # --- ROC/CM from seed 41 fold ---
    fold41 = CV_ROOT / "seed_41"
    data_dir = fold41 / "npz"
    model_path = fold41 / "Tables" / "model_b.pth"
    map_csv = PROJ / "_tmp_sapsii_by_stay.csv"
    saps_map = {}
    with map_csv.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            saps_map[int(float(row["stay_id"]))] = float(row["SAPSII"])

    ds = TSTDataset("test", str(data_dir))
    D, H, F = ds.n_days, ds.n_hours, ds.n_features
    pids = np.load(data_dir / "test.npz", allow_pickle=False)["patient_id"].astype(np.int64)
    saps = np.array([saps_map.get(int(p), np.nan) for p in pids], dtype=np.float64)
    dl = DataLoader(ds, batch_size=64, shuffle=False)
    model = load_model_for_eval(str(model_path), "b", D, H, F)
    scores = score_all_cutoffs(model, dl, D)
    y, los = ds.y, ds.day_mask.sum(1).astype(int)

    days = []
    for c in range(1, min(D, 5) + 1):
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
    axb.set_ylabel("Mean ± SD (5×7:2:1)", fontsize=9)
    axb.set_title("Comparison of Models", fontsize=11)
    axb.legend(loc="upper right", fontsize=7)
    axb.tick_params(labelsize=8)

    out = PROJ / "summary_results/Figures/Figure 3-MIMIC-ROC_confusion_model_comparison.pdf"
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, format="pdf", bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)
    print(f"Fig3 bars T {mean_auc:.3f}±{sd_auc:.3f} / {mean_acc:.3f}±{sd_acc:.3f}")
    print(f"Fig3 bars S {mean_sa:.3f}±{sd_sa:.3f} / {mean_sc:.3f}±{sd_sc:.3f}")


def _write_sci_table(path, title, headers, rows, footnotes, widths):
    thick = Side(style="medium", color="000000")
    thin = Side(style="thin", color="000000")
    border_header = Border(top=thick, bottom=thin)
    border_last = Border(bottom=thick)
    border_foot = Border(top=thin)
    font_title = Font(name=FONT, size=12, bold=True)
    font_hdr = Font(name=FONT, size=11, bold=True)
    font_body = Font(name=FONT, size=11)
    align_c = Alignment(horizontal="center", vertical="center", wrap_text=True)
    align_l = Alignment(horizontal="left", vertical="center", wrap_text=True)

    wb = Workbook()
    ws = wb.active
    ws.title = "Table"
    ws.sheet_view.showGridLines = False
    nc = len(headers)
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=nc)
    c = ws.cell(1, 1, title)
    c.font = font_title
    c.alignment = align_c
    r0 = 2
    for j, h in enumerate(headers, 1):
        cell = ws.cell(r0, j, h)
        cell.font = font_hdr
        cell.alignment = align_c
        cell.border = border_header
    for i, row in enumerate(rows):
        er = r0 + 1 + i
        is_last = i == len(rows) - 1
        for j, val in enumerate(row, 1):
            cell = ws.cell(er, j, val)
            cell.font = font_body
            cell.alignment = align_l if j == 1 else align_c
            if is_last:
                cell.border = border_last
    last = r0 + len(rows)
    for k, note in enumerate(footnotes):
        fr = last + 1 + k
        ws.merge_cells(start_row=fr, start_column=1, end_row=fr, end_column=nc)
        cell = ws.cell(fr, 1, note)
        cell.font = font_body
        cell.alignment = align_l
        if k == 0:
            cell.border = border_foot
    for j, w in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(j)].width = w
    ws.row_dimensions[1].height = 40
    path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(path)
    print("wrote", path)


def main() -> None:
    meta = {
        "protocol": "reuse_cv_folds_train_baselines",
        "seeds": SEEDS,
        "updates": ["Table 2", "Table 3", "Figure S6", "S6 csv"],
        "not_updated": [
            "Table 1 (descriptive mean/SD)",
            "Figure 4 / S1-S5 SHAP (single-model viz)",
            "Figure 3 (paper: single testing data — use redraw_fig3_sapsii.py)",
        ],
    }
    (CV_ROOT / "cv_pub_update_meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(json.dumps(meta, indent=2), flush=True)

    rows = collect_all()
    agg = CV_ROOT / "Table_CV_all_models_fold_day_metrics.csv"
    write_csv(agg, rows)
    print(f"[cv-base] wrote {agg} n={len(rows)}", flush=True)

    rebuild_table3(rows)
    rebuild_s6(rows)
    # Figure 3：按原文用单次 testing data，不在此用 CV 重画
    import subprocess

    t2 = Path(__file__).resolve().parents[2] / "Blocks/71_two_stage_transformer_stroke/scripts/rebuild_table2_yang_layout.py"
    subprocess.check_call([sys.executable, str(t2), "--from-cv", str(CV_ROOT)])
    fig3 = Path(__file__).resolve().parents[2] / "Blocks/71_two_stage_transformer_stroke/scripts/redraw_fig3_sapsii.py"
    subprocess.check_call([sys.executable, str(fig3)])
    print("[done] Table2/3 + S6 from CV; Figure 3 from single testing set (paper protocol)")


if __name__ == "__main__":
    main()
