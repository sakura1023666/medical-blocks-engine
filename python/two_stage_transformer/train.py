"""train.py — A1/A2/B 三轨训练（迁移自 code/main_5day.py，扩展 arch 参数）。

三轨定义(对齐 docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md §3):
  - b  两阶段 Transformer(TwoStageTransformer) + 多截止监督(每 batch 对 cutoff=1..D 各算一次
       loss,让 Day1..DayD 都被充分监督) —「统一规范管线」主轨。
  - a2 单阶段 Transformer(SingleStageTransformer) + 与 b 完全相同的多截止监督/优化器/损失/
       划分/预算 —「统一规范管线」下的单阶段公平基线,用于对比两阶段增量价值。
  - a1 与 b 结构相同的 TwoStageTransformer,但训练循环是原始公开仓库脚本的字面写法:
       只在固定 cutoff=D(最后一天)算 loss,不做多截止监督扩展 ——「公开代码实现」单独命名,
       不与 a2/b 的规范管线结果混名(对齐设计文档 3.1 节 A1 定义)。

FocalLoss(gamma=2, alpha=0.8) 处理类别不平衡；按验证集 AUC（末日本 cutoff）存盘，
patience 轮无提升则早停（默认 patience=15）。文件头勿再写 min val_loss。
"""
from __future__ import annotations

import csv
import json
import random
from pathlib import Path
from typing import Optional

import numpy as np
import torch
from torch.utils.data import DataLoader
from tqdm import tqdm

from .dataloader import TSTDataset, fit_feature_norm, write_feature_norm
from .eval import score_all_cutoffs
from .focal import FocalLoss
from .model import build_model

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")


def seed_everything(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)


def _write_train_log(out_dir: Path, rows: list[dict], name: str = "Table_TST_Train_Log.csv") -> None:
    if not rows:
        return
    path = out_dir / name
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)


def _train_epoch_multi_cutoff(model, crit, opt, loader, D: int,
                               day_weights: Optional[list] = None,
                               input_noise: float = 0.0) -> float:
    model.train()
    total = 0.0
    n_batches = max(len(loader), 1)
    if day_weights is None:
        day_weights = [1.0] * D
    wsum = float(sum(day_weights)) or 1.0
    for x, m, y in tqdm(loader, total=len(loader), leave=False, desc="train"):
        x, m, y = x.to(device), m.to(device), y.to(device)
        if input_noise and input_noise > 0:
            x = x + torch.randn_like(x) * float(input_noise)
        los = m.sum(1).long()
        loss = 0.0
        w_used = 0.0
        for c in range(1, D + 1):
            sel = los >= c
            if sel.sum() == 0:
                continue
            wc = float(day_weights[c - 1])
            loss = loss + wc * crit(model(x[sel], m[sel], c), y[sel])
            w_used += wc
        loss = loss / max(w_used, 1e-6)
        opt.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        opt.step()
        total += float(loss.item()) / n_batches
    return total


def _val_epoch_multi_cutoff(model, crit, loader, D: int) -> float:
    model.eval()
    total = 0.0
    n_batches = max(len(loader), 1)
    with torch.no_grad():
        for x, m, y in loader:
            x, m, y = x.to(device), m.to(device), y.to(device)
            total += float(crit(model(x, m, D), y).item()) / n_batches
    return total


def _train_epoch_single_cutoff(model, crit, opt, loader, D: int) -> float:
    """A1 轨:原始公开仓库脚本字面写法,只在固定 cutoff=D 算 loss(不做多截止监督)。"""
    model.train()
    total = 0.0
    n_batches = max(len(loader), 1)
    for x, m, y in tqdm(loader, total=len(loader), leave=False, desc="train[a1]"):
        x, m, y = x.to(device), m.to(device), y.to(device)
        loss = crit(model(x, m, D), y)
        opt.zero_grad()
        loss.backward()
        opt.step()
        total += float(loss.item()) / n_batches
    return total


def _val_auc_at_cutoff(model, loader: DataLoader, D: int) -> float:
    """Validation AUC at final day cutoff (aligns with Day-D test metric)."""
    model.eval()
    scores = score_all_cutoffs(model, loader, D)[D]
    ys = []
    for _, _, y in loader:
        ys.append(y.numpy())
    y = np.concatenate(ys) if ys else np.array([])
    if len(y) == 0 or len(np.unique(y)) < 2:
        return 0.5
    try:
        from sklearn.metrics import roc_auc_score

        return float(roc_auc_score(y, scores))
    except Exception:
        pos = scores[y == 1]
        neg = scores[y == 0]
        if len(pos) == 0 or len(neg) == 0:
            return 0.5
        wins = sum((p > n) + 0.5 * (p == n) for p in pos for n in neg)
        return float(wins / (len(pos) * len(neg)))


def train(
    data_dir: str,
    out_dir: str,
    arch: str = "b",
    epochs: int = 100,
    batch_size: int = 32,
    lr: float = 1e-4,
    seed: int = 42,
    d_model: int = 128,
    heads: int = 4,
    n_layers: int = 2,
    dropout: float = 0.3,
    patience: int = 15,
    day5_loss_weight: float = 3.0,
    input_noise: float = 0.01,
    rich_tabular: bool = True,
    tab_dim: int = 128,
    focal_alpha: float = 0.75,
    focal_gamma: float = 2.0,
    model_tag: str = "",
) -> dict:
    """训练主循环。

    A 轨对齐说明:
      - a1: 公开实现风格，仅 cutoff=D 单截止监督
      - a2: 规范单阶段 + 多截止监督（与 b 公平对比结构）
      - b : 两阶段 + 多截止监督（主轨）
    训练预算对齐原文「约 100 epoch + 早停」口径：默认 epochs=100、patience=15。
    day5_loss_weight: 多截止监督中最终日 cutoff 的损失权重（冲 Day-D AUC）。
    """
    seed_everything(seed)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    data_dir_p = Path(data_dir)

    tr_raw = np.load(data_dir_p / "train.npz", allow_pickle=False)
    mu, sd = fit_feature_norm(np.asarray(tr_raw["X"], dtype=np.float32))
    norm_path = write_feature_norm(data_dir_p, mu, sd)
    print(f"[train:{arch}] feature_norm -> {norm_path}", flush=True)

    tr_ds = TSTDataset("train", data_dir)
    va_ds = TSTDataset("val", data_dir)
    tr = DataLoader(tr_ds, batch_size=batch_size, shuffle=True, drop_last=len(tr_ds) > batch_size)
    va = DataLoader(va_ds, batch_size=batch_size, shuffle=False, drop_last=False)

    D, H, F = tr_ds.n_days, tr_ds.n_hours, tr_ds.n_features
    print(f"[train:{arch}] device={device} | F={F} D={D} H={H} | "
          f"train_batches={len(tr)} val_batches={len(va)} | "
          f"epochs={epochs} patience={patience}", flush=True)

    model = build_model(
        arch, D, H, F, d_model=d_model, heads=heads, N=n_layers, dropout=dropout,
        fusion=(arch in ("b", "a1")),
        rich_tabular=rich_tabular if arch in ("b", "a1") else False,
        tab_dim=tab_dim,
    ).to(device)
    crit = FocalLoss(gamma=float(focal_gamma), alpha=float(focal_alpha))
    opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=max(epochs, 1), eta_min=lr * 0.05)
    n_params = sum(p.numel() for p in model.parameters())
    day_weights = [1.0] * (D - 1) + [float(day5_loss_weight)]
    print(f"[train:{arch}] 参数量={n_params:,} fusion={getattr(model, 'fusion', False)} "
          f"rich_tab={getattr(model, 'rich_tabular', False)} "
          f"day5_w={day5_loss_weight} noise={input_noise} "
          f"focal(a={focal_alpha},g={focal_gamma})", flush=True)

    tag = f"_{model_tag}" if model_tag else ""
    model_path = out_dir / f"model_{arch}{tag}.pth"
    best_auc = -1.0
    best_loss = 1e9
    bad_epochs = 0
    best_ep = 0
    log_rows: list[dict] = []
    for ep in range(epochs):
        if arch == "a1":
            tl = _train_epoch_single_cutoff(model, crit, opt, tr, D)
            vl = _val_epoch_multi_cutoff(model, crit, va, D)
        else:
            tl = _train_epoch_multi_cutoff(
                model, crit, opt, tr, D,
                day_weights=day_weights, input_noise=input_noise,
            )
            vl = _val_epoch_multi_cutoff(model, crit, va, D)
        va_auc = _val_auc_at_cutoff(model, va, D)
        sched.step()
        saved = False
        if va_auc > best_auc + 1e-5:
            best_auc = va_auc
            best_loss = vl
            torch.save(model.state_dict(), model_path)
            saved = True
            bad_epochs = 0
            best_ep = ep + 1
        else:
            bad_epochs += 1
        log_rows.append({"epoch": ep + 1, "arch": arch, "train_loss": round(tl, 6),
                          "val_loss": round(vl, 6), "val_auc": round(va_auc, 6), "saved": int(saved)})
        print(f"[train:{arch}] Epoch {ep+1:2d}/{epochs}: loss={tl:.4f} "
              f"val_loss(Day{D})={vl:.4f} val_auc={va_auc:.4f}{' <- save' if saved else ''}", flush=True)
        if patience > 0 and bad_epochs >= patience:
            print(f"[train:{arch}] early stop @ epoch {ep+1} "
                  f"(best={best_ep}, best_val_auc={best_auc:.4f}, patience={patience})", flush=True)
            break

    _write_train_log(out_dir, log_rows, name=f"Table_TST_Train_Log_{arch}{tag}.csv")
    arch_cfg = {
        "arch": arch, "d_model": d_model, "heads": heads, "n_layers": n_layers,
        "dropout": dropout, "fusion": bool(getattr(model, "fusion", False)),
        "rich_tabular": bool(getattr(model, "rich_tabular", False)),
        "tab_dim": tab_dim, "n_days": D, "n_hours": H, "n_features": F,
    }
    summary = {
        **arch_cfg,
        "n_params": int(n_params), "best_val_loss": float(best_loss),
        "best_val_auc": float(best_auc), "feature_norm": str(norm_path),
        "epochs": epochs, "epochs_ran": len(log_rows), "best_epoch": best_ep,
        "patience": patience, "model_path": str(model_path), "seed": seed,
        "include_current_day": True,
        "optimizer": "AdamW",
        "day5_loss_weight": float(day5_loss_weight),
        "input_noise": float(input_noise),
        "focal_alpha": float(focal_alpha),
        "focal_gamma": float(focal_gamma),
    }
    (out_dir / f"train_meta_{arch}{tag}.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    (out_dir / f"model_{arch}{tag}.meta.json").write_text(json.dumps(arch_cfg, indent=2), encoding="utf-8")
    print(f"[train:{arch}] OK -> {model_path}", flush=True)
    return summary


def run_ablation(
    data_dir: str,
    out_dir: str,
    arch: str = "b",
    ablations: str = "mask,feature_subset,structure",
    epochs: int = 5,
    batch_size: int = 32,
    lr: float = 1e-4,
    seed: int = 42,
) -> list[dict]:
    """`tst_ablation` 模式:Mask/Δt、特征子集、结构消融(对齐复现方案 E8-E11)。

    - mask: day_mask 强制全 1(移除"是否在院/缺失天"这一信息),看指标是否下降。
    - feature_subset: 训练前把一半特征列随机置零,看指标是否下降(特征贡献度粗筛)。
    - structure: 用单阶段(SingleStageTransformer)代替两阶段结构(等价于跑 A2),
      对比"去掉小时级注意力"这一结构变化的影响。
    """
    seed_everything(seed)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    variants = [v.strip() for v in ablations.split(",") if v.strip()]
    rows: list[dict] = []

    for variant in variants:
        tr_ds = TSTDataset("train", data_dir)
        va_ds = TSTDataset("val", data_dir)
        D, H, F = tr_ds.n_days, tr_ds.n_hours, tr_ds.n_features
        use_arch = arch

        if variant == "mask":
            tr_ds.day_mask[:] = 1.0
            va_ds.day_mask[:] = 1.0
        elif variant == "feature_subset":
            rng = np.random.default_rng(seed)
            drop = rng.choice(F, size=max(1, F // 2), replace=False)
            tr_ds.X[:, :, :, drop] = 0.0
            va_ds.X[:, :, :, drop] = 0.0
        elif variant == "structure":
            use_arch = "a2" if arch != "a2" else "b"
        else:
            print(f"[ablation] 未知 variant={variant!r},跳过")
            continue

        tr = DataLoader(tr_ds, batch_size=batch_size, shuffle=True, drop_last=len(tr_ds) > batch_size)
        va = DataLoader(va_ds, batch_size=batch_size, shuffle=False, drop_last=False)
        model = build_model(use_arch, D, H, F).to(device)
        crit = FocalLoss(gamma=2, alpha=0.8)
        opt = torch.optim.Adam(model.parameters(), lr=lr)
        min_loss = 1e9
        for _ep in range(epochs):
            _train_epoch_multi_cutoff(model, crit, opt, tr, D)
            vl = _val_epoch_multi_cutoff(model, crit, va, D)
            min_loss = min(min_loss, vl)
        rows.append({"variant": variant, "base_arch": arch, "used_arch": use_arch,
                      "epochs": epochs, "best_val_loss": round(float(min_loss), 6)})
        print(f"[ablation] {variant} (arch={use_arch}) best_val_loss={min_loss:.4f}")

    path = out_dir / "Table_TST_Ablation.csv"
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["variant", "base_arch", "used_arch", "epochs", "best_val_loss"])
        w.writeheader()
        w.writerows(rows)
    print(f"[ablation] OK -> {path}")
    return rows
