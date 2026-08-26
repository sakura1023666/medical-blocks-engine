"""eval.py — Day1..D ROC/AUC 指标表 + 校准/DCA（迁移自 code/plot_roc_5day.py + 指标 CSV 写出）。

test 集分别 cutoff=1..D 预测;Day d 只评估 los>=d 的患者(在院患者,公平口径)。
Day-k 语义见 model.day_k_keep_count：只用前 k-1 天（后续 mask）。
APACHE 列缺失时自动跳过 APACHE 曲线。DayD 混淆矩阵用 Youden 最优阈值。
"""
from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Optional

import numpy as np
import torch
from torch.utils.data import DataLoader

from .dataloader import TSTDataset
from .model import build_model

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")


def _write_csv(path: Path, fieldnames: list[str], rows: list[dict]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for row in rows:
            w.writerow({k: row.get(k, "") for k in fieldnames})


def _auc_rank(y: np.ndarray, scores: np.ndarray) -> float:
    """无 sklearn 依赖的秩和 AUC 回退实现。"""
    pos = scores[y == 1]
    neg = scores[y == 0]
    if len(pos) == 0 or len(neg) == 0:
        return 0.5
    wins = sum((p > n) + 0.5 * (p == n) for p in pos for n in neg)
    return float(wins / (len(pos) * len(neg)))


def load_model_for_eval(model_path: str, arch: str, n_days: int, n_hours: int, n_features: int):
    model = build_model(arch, n_days, n_hours, n_features).to(device)
    state = torch.load(model_path, map_location=device)
    model.load_state_dict(state)
    model.eval()
    return model


def score_all_cutoffs(model, loader: DataLoader, D: int) -> dict:
    scores = {c: [] for c in range(1, D + 1)}
    with torch.no_grad():
        for x, dm, _ in loader:
            x, dm = x.to(device), dm.to(device)
            for c in range(1, D + 1):
                out = model(x, dm, c)
                scores[c].append(np.exp(out[:, 1].cpu().numpy()))
    return {c: np.concatenate(v) if v else np.array([]) for c, v in scores.items()}


def evaluate(
    data_dir: str,
    out_dir: str,
    model_path: str,
    arch: str = "b",
    split: str = "test",
    is_synthetic: bool = False,
    metrics_name: str = "Table_TST_Metrics.csv",
    make_plot: bool = True,
) -> list[dict]:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    ds = TSTDataset(split, data_dir)
    D, H, F = ds.n_days, ds.n_hours, ds.n_features
    dl = DataLoader(ds, batch_size=64, shuffle=False)

    model = load_model_for_eval(model_path, arch, D, H, F)
    scores = score_all_cutoffs(model, dl, D)
    y = ds.y
    los = ds.day_mask.sum(1).astype(int)

    try:
        from sklearn.metrics import roc_auc_score

        def _auc(yy, ss):
            return float(roc_auc_score(yy, ss)) if len(np.unique(yy)) > 1 else 0.5
    except Exception:
        def _auc(yy, ss):
            return _auc_rank(yy, ss)

    rows = []
    for c in range(1, D + 1):
        sel = los >= c
        n_sel = int(sel.sum())
        n_pos = int(y[sel].sum()) if n_sel else 0
        a = _auc(y[sel], scores[c][sel]) if n_sel else float("nan")
        rows.append({
            "split": split, "arch": arch, "day": c, "auc": round(a, 4) if a == a else "",
            "n": n_sel, "n_pos": n_pos, "is_synthetic": str(bool(is_synthetic)).upper(),
        })
        print(f"[eval:{arch}] Day{c}: AUC={a:.4f} (n={n_sel}, 正例 {n_pos})")

    _write_csv(out_dir / metrics_name, ["split", "arch", "day", "auc", "n", "n_pos", "is_synthetic"], rows)

    if make_plot:
        try:
            import matplotlib

            matplotlib.use("Agg")
            from matplotlib import pyplot as plt
            from sklearn.metrics import roc_curve

            plt.figure(figsize=(7, 6))
            colors = plt.cm.viridis(np.linspace(0.1, 0.9, D))
            for c in range(1, D + 1):
                sel = los >= c
                if sel.sum() == 0 or len(np.unique(y[sel])) < 2:
                    continue
                fpr, tpr, _ = roc_curve(y[sel], scores[c][sel])
                plt.plot(fpr, tpr, color=colors[c - 1], lw=2.0,
                         label=f"Day{c} (AUC={rows[c-1]['auc']}, n={rows[c-1]['n']})")
            plt.plot([0, 1], [0, 1], "k:", lw=1)
            plt.xlim(0, 1)
            plt.ylim(0, 1.02)
            plt.xlabel("False Positive Rate")
            plt.ylabel("True Positive Rate")
            plt.title(f"{arch}: Day1-{D} ROC ({split})")
            plt.legend(loc="lower right")
            plt.tight_layout()
            plt.savefig(out_dir / f"roc_{arch}_{split}.png", dpi=150)
            plt.close()
        except Exception as e:  # 绘图失败不阻断指标产出
            print(f"[eval:{arch}] 绘图跳过: {e}")

    return rows


def calibration_dca(
    data_dir: str,
    out_dir: str,
    model_path: str,
    arch: str = "b",
    split: str = "test",
    cutoff: Optional[int] = None,
) -> dict:
    """`tst_calibrate` 模式:校准曲线(10 bins)+ 决策曲线分析(DCA net benefit)。"""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    ds = TSTDataset(split, data_dir)
    D, H, F = ds.n_days, ds.n_hours, ds.n_features
    c = cutoff or D
    dl = DataLoader(ds, batch_size=64, shuffle=False)

    model = load_model_for_eval(model_path, arch, D, H, F)
    scores = score_all_cutoffs(model, dl, D)[c]
    y = ds.y
    los = ds.day_mask.sum(1).astype(int)
    sel = los >= c
    p, yy = scores[sel], y[sel]

    bins = np.linspace(0, 1, 11)
    cal_rows = []
    for i in range(len(bins) - 1):
        lo, hi = bins[i], bins[i + 1]
        mask = (p >= lo) & (p < hi) if hi < 1.0 else (p >= lo) & (p <= hi)
        if not mask.any():
            continue
        cal_rows.append({"bin": i + 1, "predicted": float(p[mask].mean()), "observed": float(yy[mask].mean()),
                          "n": int(mask.sum())})
    _write_csv(out_dir / "Table_TST_Calibration.csv", ["bin", "predicted", "observed", "n"], cal_rows)

    thresholds = np.linspace(0.01, 0.99, 49)
    n = len(yy)
    dca_rows = []
    prevalence = float(yy.mean()) if n else 0.0
    for t in thresholds:
        pred_pos = p >= t
        tp = float((pred_pos & (yy == 1)).sum())
        fp = float((pred_pos & (yy == 0)).sum())
        nb_model = (tp / n) - (fp / n) * (t / (1 - t)) if n and t < 1 else 0.0
        nb_all = prevalence - (1 - prevalence) * (t / (1 - t)) if t < 1 else 0.0
        dca_rows.append({"threshold": round(float(t), 3), "net_benefit_model": round(float(nb_model), 6),
                          "net_benefit_treat_all": round(float(nb_all), 6), "net_benefit_treat_none": 0.0})
    _write_csv(out_dir / "Table_TST_DCA.csv",
               ["threshold", "net_benefit_model", "net_benefit_treat_all", "net_benefit_treat_none"], dca_rows)

    summary = {"arch": arch, "split": split, "cutoff": c, "n": n, "prevalence": prevalence}
    (out_dir / "calibration_meta.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"[calibrate:{arch}] OK -> Table_TST_Calibration.csv, Table_TST_DCA.csv (cutoff=Day{c})")
    return summary
