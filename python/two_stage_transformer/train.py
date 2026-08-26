"""train.py — A1/A2/B 三轨训练（迁移自 code/main_5day.py，扩展 arch 参数）。

三轨定义(对齐 docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md §3):
  - b  两阶段 Transformer(TwoStageTransformer) + 多截止监督(每 batch 对 cutoff=1..D 各算一次
       loss,让 Day1..DayD 都被充分监督) —「统一规范管线」主轨。
  - a2 单阶段 Transformer(SingleStageTransformer) + 与 b 完全相同的多截止监督/优化器/损失/
       划分/预算 —「统一规范管线」下的单阶段公平基线,用于对比两阶段增量价值。
  - a1 与 b 结构相同的 TwoStageTransformer,但训练循环是原始公开仓库脚本的字面写法:
       只在固定 cutoff=D(最后一天)算 loss,不做多截止监督扩展 ——「公开代码实现」单独命名,
       不与 a2/b 的规范管线结果混名(对齐设计文档 3.1 节 A1 定义)。

FocalLoss(gamma=2, alpha=0.8) 处理类别不平衡；保存 min val_loss 的模型。
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

from .dataloader import TSTDataset
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


def _train_epoch_multi_cutoff(model, crit, opt, loader, D: int) -> float:
    model.train()
    total = 0.0
    n_batches = max(len(loader), 1)
    for x, m, y in tqdm(loader, total=len(loader), leave=False, desc="train"):
        x, m, y = x.to(device), m.to(device), y.to(device)
        los = m.sum(1).long()
        loss = 0.0
        cnt = 0
        for c in range(1, D + 1):
            sel = los >= c
            if sel.sum() == 0:
                continue
            loss = loss + crit(model(x[sel], m[sel], c), y[sel])
            cnt += 1
        loss = loss / max(cnt, 1)
        opt.zero_grad()
        loss.backward()
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
    dropout: float = 0.5,
    patience: int = 15,
) -> dict:
    """训练主循环。

    A 轨对齐说明:
      - a1: 公开实现风格，仅 cutoff=D 单截止监督
      - a2: 规范单阶段 + 多截止监督（与 b 公平对比结构）
      - b : 两阶段 + 多截止监督（主轨）
    训练预算对齐原文「约 100 epoch + 早停」口径：默认 epochs=100、patience=15。
    """
    seed_everything(seed)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    tr_ds = TSTDataset("train", data_dir)
    va_ds = TSTDataset("val", data_dir)
    tr = DataLoader(tr_ds, batch_size=batch_size, shuffle=True, drop_last=len(tr_ds) > batch_size)
    va = DataLoader(va_ds, batch_size=batch_size, shuffle=False, drop_last=False)

    D, H, F = tr_ds.n_days, tr_ds.n_hours, tr_ds.n_features
    print(f"[train:{arch}] device={device} | F={F} D={D} H={H} | "
          f"train_batches={len(tr)} val_batches={len(va)} | "
          f"epochs={epochs} patience={patience}", flush=True)

    model = build_model(arch, D, H, F, d_model=d_model, heads=heads, N=n_layers, dropout=dropout).to(device)
    crit = FocalLoss(gamma=2, alpha=0.8)
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    n_params = sum(p.numel() for p in model.parameters())
    print(f"[train:{arch}] 参数量={n_params:,}", flush=True)

    model_path = out_dir / f"model_{arch}.pth"
    min_loss = 1e9
    bad_epochs = 0
    best_ep = 0
    log_rows: list[dict] = []
    for ep in range(epochs):
        if arch == "a1":
            tl = _train_epoch_single_cutoff(model, crit, opt, tr, D)
            vl = _val_epoch_multi_cutoff(model, crit, va, D)
        else:
            tl = _train_epoch_multi_cutoff(model, crit, opt, tr, D)
            vl = _val_epoch_multi_cutoff(model, crit, va, D)
        saved = False
        if vl < min_loss:
            min_loss = vl
            torch.save(model.state_dict(), model_path)
            saved = True
            bad_epochs = 0
            best_ep = ep + 1
        else:
            bad_epochs += 1
        log_rows.append({"epoch": ep + 1, "arch": arch, "train_loss": round(tl, 6),
                          "val_loss": round(vl, 6), "saved": int(saved)})
        print(f"[train:{arch}] Epoch {ep+1:2d}/{epochs}: loss={tl:.4f} "
              f"val_loss(Day{D})={vl:.4f}{' <- save' if saved else ''}", flush=True)
        if patience > 0 and bad_epochs >= patience:
            print(f"[train:{arch}] early stop @ epoch {ep+1} "
                  f"(best={best_ep}, patience={patience})", flush=True)
            break

    _write_train_log(out_dir, log_rows, name=f"Table_TST_Train_Log_{arch}.csv")
    summary = {
        "arch": arch, "n_days": D, "n_hours": H, "n_features": F,
        "n_params": int(n_params), "best_val_loss": float(min_loss),
        "epochs": epochs, "epochs_ran": len(log_rows), "best_epoch": best_ep,
        "patience": patience, "model_path": str(model_path), "seed": seed,
    }
    (out_dir / f"train_meta_{arch}.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
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
