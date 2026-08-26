"""baselines.py — Logistic/XGBoost/MLP/LSTM 传统基线（`tst_baselines` 模式,新增文件）。

统一从同一 npz 张量(X,day_mask,y)取特征:
  - logistic / xgboost / mlp: 表格特征 = 按 (day,hour) 展平后对有效天做均值池化(patient-level)。
  - lstm: 序列特征 = 按天聚合的 (D, F) 序列,torch LSTM 做一个轻量深度基线。
xgboost 缺失时自动回退到 sklearn GradientBoostingClassifier(与本仓库既有 Python 脚本一致的
"try/except 回退" 风格),回退会在输出表 `note` 列注明。
"""
from __future__ import annotations

import csv
from pathlib import Path

import numpy as np

from .dataloader import TSTDataset


def _write_csv(path: Path, fieldnames: list[str], rows: list[dict]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for row in rows:
            w.writerow({k: row.get(k, "") for k in fieldnames})


def _auc_rank(y: np.ndarray, scores: np.ndarray) -> float:
    pos = scores[y == 1]
    neg = scores[y == 0]
    if len(pos) == 0 or len(neg) == 0:
        return 0.5
    wins = sum((p > n) + 0.5 * (p == n) for p in pos for n in neg)
    return float(wins / (len(pos) * len(neg)))


def _auc(y: np.ndarray, scores: np.ndarray) -> float:
    try:
        from sklearn.metrics import roc_auc_score

        return float(roc_auc_score(y, scores)) if len(np.unique(y)) > 1 else 0.5
    except Exception:
        return _auc_rank(y, scores)


def _tabular_features(ds: TSTDataset) -> np.ndarray:
    """(n,D,H,F) -> (n, D*F) 每天在有效小时上的均值(mask 之外置 0 不参与均值)。"""
    n, D, H, F = ds.X.shape
    day_valid = ds.day_mask[:, :, None, None]  # (n,D,1,1)
    day_mean = (ds.X * day_valid).sum(axis=2) / np.clip(day_valid.sum(axis=2) * H, 1e-6, None)
    return day_mean.reshape(n, D * F)


def _day_sequence_features(ds: TSTDataset) -> np.ndarray:
    """(n,D,H,F) -> (n,D,F) 每天在小时维上取均值,供 LSTM 用。"""
    return ds.X.mean(axis=2)


def run_baselines(
    data_dir: str,
    out_dir: str,
    models: str = "logistic,xgboost,mlp,lstm",
    seed: int = 42,
    epochs: int = 20,
) -> list[dict]:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    tr_ds = TSTDataset("train", data_dir)
    va_ds = TSTDataset("val", data_dir)
    te_ds = TSTDataset("test", data_dir)

    X_tr, y_tr = _tabular_features(tr_ds), tr_ds.y
    X_va, y_va = _tabular_features(va_ds), va_ds.y
    X_te, y_te = _tabular_features(te_ds), te_ds.y

    mu, sd = X_tr.mean(axis=0), X_tr.std(axis=0)
    sd[sd < 1e-8] = 1.0
    X_tr_s, X_va_s, X_te_s = (X_tr - mu) / sd, (X_va - mu) / sd, (X_te - mu) / sd

    model_list = [m.strip().lower() for m in models.split(",") if m.strip()]
    rows: list[dict] = []

    if "logistic" in model_list:
        try:
            from sklearn.linear_model import LogisticRegression

            clf = LogisticRegression(max_iter=1000, random_state=seed, class_weight="balanced")
            clf.fit(X_tr_s, y_tr)
            auc_te = _auc(y_te, clf.predict_proba(X_te_s)[:, 1])
            rows.append({"model": "logistic", "auc_val": _auc(y_va, clf.predict_proba(X_va_s)[:, 1]),
                         "auc_test": auc_te, "n_test": len(y_te), "note": ""})
        except Exception as e:
            rows.append({"model": "logistic", "auc_val": "", "auc_test": "", "n_test": len(y_te), "note": str(e)})

    if "xgboost" in model_list:
        note = ""
        try:
            from xgboost import XGBClassifier

            clf = XGBClassifier(n_estimators=200, max_depth=4, random_state=seed,
                                 eval_metric="logloss", use_label_encoder=False)
        except Exception:
            from sklearn.ensemble import GradientBoostingClassifier

            clf = GradientBoostingClassifier(n_estimators=150, random_state=seed)
            note = "xgboost 未安装,回退 sklearn GradientBoostingClassifier"
        try:
            clf.fit(X_tr, y_tr)
            rows.append({"model": "xgboost", "auc_val": _auc(y_va, clf.predict_proba(X_va)[:, 1]),
                         "auc_test": _auc(y_te, clf.predict_proba(X_te)[:, 1]), "n_test": len(y_te), "note": note})
        except Exception as e:
            rows.append({"model": "xgboost", "auc_val": "", "auc_test": "", "n_test": len(y_te), "note": f"{note} {e}".strip()})

    if "mlp" in model_list:
        try:
            from sklearn.neural_network import MLPClassifier

            clf = MLPClassifier(hidden_layer_sizes=(64, 32), max_iter=300, random_state=seed)
            clf.fit(X_tr_s, y_tr)
            rows.append({"model": "mlp", "auc_val": _auc(y_va, clf.predict_proba(X_va_s)[:, 1]),
                         "auc_test": _auc(y_te, clf.predict_proba(X_te_s)[:, 1]), "n_test": len(y_te), "note": ""})
        except Exception as e:
            rows.append({"model": "mlp", "auc_val": "", "auc_test": "", "n_test": len(y_te), "note": str(e)})

    if "lstm" in model_list:
        try:
            import torch
            import torch.nn as nn

            device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
            Xd_tr = _day_sequence_features(tr_ds)
            Xd_va = _day_sequence_features(va_ds)
            Xd_te = _day_sequence_features(te_ds)
            mu2 = Xd_tr.reshape(-1, Xd_tr.shape[-1]).mean(axis=0)
            sd2 = Xd_tr.reshape(-1, Xd_tr.shape[-1]).std(axis=0)
            sd2[sd2 < 1e-8] = 1.0
            Xd_tr, Xd_va, Xd_te = (Xd_tr - mu2) / sd2, (Xd_va - mu2) / sd2, (Xd_te - mu2) / sd2

            class TinyLSTM(nn.Module):
                def __init__(self, n_feat, hidden=32):
                    super().__init__()
                    self.lstm = nn.LSTM(n_feat, hidden, batch_first=True)
                    self.fc = nn.Linear(hidden, 1)

                def forward(self, x):
                    out, _ = self.lstm(x)
                    return torch.sigmoid(self.fc(out[:, -1, :])).squeeze(-1)

            net = TinyLSTM(Xd_tr.shape[-1]).to(device)
            opt = torch.optim.Adam(net.parameters(), lr=1e-3)
            xt = torch.tensor(Xd_tr, dtype=torch.float32, device=device)
            yt = torch.tensor(y_tr, dtype=torch.float32, device=device)
            for _ in range(epochs):
                opt.zero_grad()
                loss = nn.functional.binary_cross_entropy(net(xt), yt)
                loss.backward()
                opt.step()
            with torch.no_grad():
                p_va = net(torch.tensor(Xd_va, dtype=torch.float32, device=device)).cpu().numpy()
                p_te = net(torch.tensor(Xd_te, dtype=torch.float32, device=device)).cpu().numpy()
            rows.append({"model": "lstm", "auc_val": _auc(y_va, p_va), "auc_test": _auc(y_te, p_te),
                         "n_test": len(y_te), "note": ""})
        except Exception as e:
            rows.append({"model": "lstm", "auc_val": "", "auc_test": "", "n_test": len(y_te), "note": str(e)})

    path = out_dir / "Table_TST_Baselines.csv"
    _write_csv(path, ["model", "auc_val", "auc_test", "n_test", "note"], rows)
    print(f"[baselines] OK -> {path}")
    return rows
