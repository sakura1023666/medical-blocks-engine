"""synthetic_external.py — 合成地理外推队列（新增文件,`tst_external_synthetic` 模式）。

无第二卒中中心真实数据时的代码路径:生成随机合成队列(标准正态特征 + 随机二分类标签),
跑一次模型前向(有训练好的 checkpoint 就加载,否则用随机初始化权重),写出
`is_synthetic=TRUE` 的指标表 + `meta.json`。结果不得当作真实外部验证结论使用
(见 docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md §0/§9)。
"""
from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Optional

import numpy as np


def generate(
    out_dir,
    n: int = 200,
    n_days: int = 5,
    n_hours: int = 24,
    n_features: int = 16,
    seed: int = 42,
) -> Path:
    rng = np.random.default_rng(seed)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    X = rng.normal(0, 1, size=(n, n_days, n_hours, n_features)).astype(np.float32)
    y = rng.integers(0, 2, size=(n,)).astype(np.int64)
    day_mask = np.ones((n, n_days), dtype=np.float32)
    meta = {"is_synthetic": True, "n": n, "seed": seed, "n_days": n_days,
            "n_hours": n_hours, "n_features": n_features}
    np.savez_compressed(
        out_dir / "synthetic_external.npz", X=X, y=y, day_mask=day_mask,
        feature_names=np.array([f"f{i}" for i in range(n_features)]),
    )
    (out_dir / "meta.json").write_text(json.dumps(meta), encoding="utf-8")
    print(f"[synthetic_external] 生成合成外推队列 n={n} D={n_days} H={n_hours} F={n_features} -> {out_dir}")
    return out_dir


def _auc(y: np.ndarray, scores: np.ndarray) -> float:
    try:
        from sklearn.metrics import roc_auc_score

        return float(roc_auc_score(y, scores)) if len(np.unique(y)) > 1 else 0.5
    except Exception:
        pos, neg = scores[y == 1], scores[y == 0]
        if len(pos) == 0 or len(neg) == 0:
            return 0.5
        wins = sum((p > nn_) + 0.5 * (p == nn_) for p in pos for nn_ in neg)
        return float(wins / (len(pos) * len(neg)))


def evaluate_synthetic(
    out_dir,
    model_path: Optional[str] = None,
    arch: str = "b",
    n: int = 200,
    n_days: int = 5,
    n_hours: int = 24,
    n_features: int = 16,
    seed: int = 42,
    epochs: int = 1,
    metrics_name: str = "Table_External_Synthetic_Metrics.csv",
) -> list[dict]:
    """`tst_external_synthetic` 模式主入口。

    `epochs` 仅用于满足 CLI `--epochs` 冒烟参数(合成数据无真实标签结构,不做多轮训练;
    该模式只跑一次前向评估,`epochs` 记录进 meta 供追溯,不驱动额外循环)。
    """
    import torch

    from .model import build_model

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    npz_path = generate(out_dir, n=n, n_days=n_days, n_hours=n_hours, n_features=n_features, seed=seed)
    d = np.load(npz_path / "synthetic_external.npz")
    X, y, day_mask = d["X"], d["y"], d["day_mask"]
    D, H, F = X.shape[1], X.shape[2], X.shape[3]

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = build_model(arch, D, H, F).to(device)
    loaded_from = "random_init"
    if model_path and Path(model_path).exists():
        state = torch.load(model_path, map_location=device)
        model.load_state_dict(state)
        loaded_from = str(model_path)
    model.eval()

    xb = torch.tensor(X, dtype=torch.float32, device=device)
    mb = torch.tensor(day_mask, dtype=torch.float32, device=device)
    rows = []
    with torch.no_grad():
        for c in range(1, D + 1):
            out = model(xb, mb, c)
            scores = np.exp(out[:, 1].cpu().numpy())
            a = _auc(y, scores)
            rows.append({
                "day": c, "arch": arch, "auc": round(a, 4), "n": int(len(y)),
                "n_pos": int(y.sum()), "is_synthetic": "TRUE", "model_source": loaded_from,
            })
            print(f"[external_synthetic:{arch}] Day{c}: AUC={a:.4f} (n={len(y)}, is_synthetic=TRUE)")

    path = out_dir / metrics_name
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["day", "arch", "auc", "n", "n_pos", "is_synthetic", "model_source"])
        w.writeheader()
        w.writerows(rows)

    meta_path = out_dir / "meta.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.exists() else {}
    meta.update({"is_synthetic": True, "arch": arch, "model_source": loaded_from, "epochs_requested": epochs})
    meta_path.write_text(json.dumps(meta), encoding="utf-8")

    print(f"[external_synthetic:{arch}] OK -> {path} (is_synthetic=TRUE, model_source={loaded_from})")
    return rows


def run_external(
    out_dir,
    data_path: Optional[str] = None,
    model_path: Optional[str] = None,
    arch: str = "b",
    seed: int = 42,
    epochs: int = 1,
    **synthetic_kwargs,
) -> list[dict]:
    """`tst_external` 模式:若给出真实第二中心 npz(`--data-path`)则直接评估;
    否则回退到合成外推(打印明确警告,不得当真实结论使用)。
    """
    out_dir = Path(out_dir)
    if data_path and Path(data_path).exists():
        import torch

        from .eval import evaluate

        print(f"[external] 使用真实第二中心数据: {data_path}")
        return evaluate(
            data_dir=str(Path(data_path).parent), out_dir=str(out_dir), model_path=model_path,
            arch=arch, split=Path(data_path).stem, is_synthetic=False,
            metrics_name="Table_External_Real_Metrics.csv",
        )
    print("[external] 未提供真实第二中心数据(--data-path),回退合成外推(is_synthetic=TRUE,"
          "不得作为真实外部验证结论)。")
    return evaluate_synthetic(out_dir, model_path=model_path, arch=arch, seed=seed, epochs=epochs, **synthetic_kwargs)
