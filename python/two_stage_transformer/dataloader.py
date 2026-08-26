"""dataloader.py — 通用纵向时序数据加载器（迁移自 code/custom_dataloader_5day.py）。

npz 结构统一为 X(n,D,H,F) / y(n,) / day_mask(n,D)(可选,缺省全 1) /
feature_names(F,)(可选) / apache(n,)(可选,基线评分对比用)。

支持两种寻址方式(向后兼容原脚本调用习惯):
  1. TSTDataset(split='train', data_dir='data')              -> 读 {data_dir}/train.npz
  2. TSTDataset(npz_path='.../custom.npz')                   -> 直接读指定文件
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Optional

import numpy as np
import torch
from torch.utils.data import DataLoader, Dataset


class TSTDataset(Dataset):
    def __init__(self, split: str = "train", data_dir: str = "data",
                 npz_path: Optional[str] = None, filename_template: str = "{split}.npz"):
        if npz_path is not None:
            path = Path(npz_path)
        else:
            path = Path(data_dir) / filename_template.format(split=split)
        if not path.exists():
            raise FileNotFoundError(f"未找到数据文件: {path}")
        d = np.load(path, allow_pickle=False)
        self.X = np.asarray(d["X"], dtype=np.float32)  # (n,D,H,F)
        n, D = self.X.shape[0], self.X.shape[1]
        self.day_mask = (
            np.asarray(d["day_mask"], dtype=np.float32)
            if "day_mask" in d else np.ones((n, D), dtype=np.float32)
        )
        self.y = np.asarray(d["y"], dtype=np.int64)  # (n,)
        self.feature_names = (
            [str(s) for s in d["feature_names"]] if "feature_names" in d
            else [f"feature_{i}" for i in range(self.X.shape[-1])]
        )
        self.apache = np.asarray(d["apache"], dtype=np.float32) if "apache" in d else None
        self.path = path

    @property
    def n_days(self) -> int:
        return self.X.shape[1]

    @property
    def n_hours(self) -> int:
        return self.X.shape[2]

    @property
    def n_features(self) -> int:
        return self.X.shape[3]

    def __getitem__(self, i):
        return (
            torch.from_numpy(self.X[i]),
            torch.from_numpy(self.day_mask[i]),
            torch.tensor(self.y[i]),
        )

    def __len__(self):
        return len(self.y)


# 向后兼容别名(原 code/custom_dataloader_5day.py 类名)
Custom_dataset_5day = TSTDataset


def make_loader(split: str, data_dir: str, batch_size: int = 32, shuffle: bool = False,
                 drop_last: bool = False, npz_path: Optional[str] = None) -> DataLoader:
    ds = TSTDataset(split=split, data_dir=data_dir, npz_path=npz_path)
    return DataLoader(ds, batch_size=batch_size, shuffle=shuffle, drop_last=drop_last)


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser(description="验证 dataloader batch shape")
    ap.add_argument("--data_dir", default="data")
    ap.add_argument("--split", default="val")
    a = ap.parse_args()
    ds = TSTDataset(a.split, a.data_dir)
    print(f"[dl] len={len(ds)} x0={tuple(ds[0][0].shape)} "
          f"mask0={tuple(ds[0][1].shape)} y0={ds[0][2].item()}")
    xb, mb, yb = next(iter(DataLoader(ds, batch_size=min(8, len(ds)), shuffle=False)))
    print(f"[dl] batch x={tuple(xb.shape)} mask={tuple(mb.shape)} y={tuple(yb.shape)}")
