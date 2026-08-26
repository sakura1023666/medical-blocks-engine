"""prepare.py — 长表 CSV -> 标准 npz + 7:2:1 split。

方案 A（日级对齐增强）:
  - expand_hours=True: 将每日快照广播到 24 个相同小时槽（对齐原文 24×F 形状；
    【场景迁移】非真小时采样）。
  - sliding_window=True: ICU 住院 > window_days 时，按天滑动窗口生成多样本
    （对齐原文 >5 天 sliding window；窗口内日历日映射到 Day1..D）。
  - 患者级先划分再扩窗，避免同一患者窗口泄漏到 train/test 两侧。
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd


def _patient_day_table(
    df: pd.DataFrame,
    patient_col: str,
    day_col: str,
    label_col: str,
    los_col: str,
    apache_col: str,
    feat_cols: list[str],
    max_calendar_day: int,
) -> tuple[list, dict, dict, dict, dict]:
    """Build per-patient day->feature maps (calendar day 1..max_calendar_day)."""
    df = df.copy()
    df[day_col] = df[day_col].astype(int)
    df = df[(df[day_col] >= 1) & (df[day_col] <= max_calendar_day)]
    patients = sorted(df[patient_col].unique().tolist())
    feat = {}
    y = {}
    los = {}
    apache = {}
    g = df.groupby(patient_col, sort=False)
    for p, sub in g:
        day_map = {}
        for d, s2 in sub.groupby(day_col, sort=True):
            # 同日多行取末行（日级宽表通常一行/天）
            row = s2.iloc[-1]
            day_map[int(d)] = row[feat_cols].fillna(0).values.astype(np.float32)
        feat[p] = day_map
        y[p] = int(sub[label_col].iloc[0])
        if los_col in sub.columns:
            lv = sub[los_col].iloc[0]
            los[p] = int(lv) if pd.notna(lv) else max(day_map.keys() or [1])
        else:
            los[p] = max(day_map.keys() or [1])
        if apache_col in sub.columns and pd.notna(sub[apache_col].iloc[0]):
            apache[p] = float(sub[apache_col].iloc[0])
    return patients, feat, y, los, apache


def _expand_windows(
    patients: list,
    feat: dict,
    y: dict,
    los: dict,
    apache: dict,
    feat_cols: list[str],
    n_days: int,
    n_hours: int,
    sliding_window: bool,
    expand_hours: bool,
) -> dict:
    """Materialize (possibly multi-window) tensors X/y/day_mask/[apache]."""
    D, H, F = n_days, n_hours, len(feat_cols)
    Xs, ys, masks, aps, pids, starts = [], [], [], [], [], []

    for p in patients:
        day_map = feat[p]
        L = max(1, int(los[p]))
        # 滑动窗口只按真实住院天数 los，不用导出表里的空日历日（R 会导出 1..max_export_day）
        cal_max = min(L, max(day_map.keys()) if day_map else L)
        cal_max = max(1, int(cal_max))

        if sliding_window and cal_max > D:
            starts_list = list(range(1, cal_max - D + 2))  # 1..cal_max-D+1
        else:
            starts_list = [1]

        for start in starts_list:
            x = np.zeros((D, H, F), dtype=np.float32)
            m = np.zeros((D,), dtype=np.float32)
            for i in range(D):
                cal_d = start + i
                if cal_d > cal_max:
                    break
                m[i] = 1.0
                if cal_d in day_map:
                    vec = day_map[cal_d]
                else:
                    # 窗口内缺日：保持 0（前向填充已在 R 侧尽量完成）
                    vec = np.zeros((F,), dtype=np.float32)
                if expand_hours:
                    x[i, :, :] = vec[None, :]
                else:
                    # 兼容旧 CSV hour=day*24：写入最后一个小时槽
                    x[i, H - 1, :] = vec
            Xs.append(x)
            ys.append(y[p])
            masks.append(m)
            pids.append(p)
            starts.append(start)
            if p in apache:
                aps.append(apache[p])

    out = {
        "X": np.stack(Xs, axis=0) if Xs else np.zeros((0, D, H, F), dtype=np.float32),
        "y": np.asarray(ys, dtype=np.int64),
        "day_mask": np.stack(masks, axis=0) if masks else np.zeros((0, D), dtype=np.float32),
        "feature_names": np.array(feat_cols),
        "patient_id": np.array(pids),
        "window_start_day": np.asarray(starts, dtype=np.int32),
    }
    if len(aps) == len(ys):
        out["apache"] = np.asarray(aps, dtype=np.float32)
    return out


def long_csv_to_npz(
    csv_path: str,
    out_path: str,
    patient_col: str = "patient",
    day_col: str = "day",
    hour_col: str = "hour",
    label_col: str = "label",
    los_col: str = "los_days",
    apache_col: str = "apache",
    n_days: int = 5,
    n_hours: int = 24,
    sliding_window: bool = True,
    expand_hours: bool = True,
    max_calendar_day: int = 30,
) -> dict:
    df = pd.read_csv(csv_path)
    meta_cols = {patient_col, day_col, hour_col, label_col, los_col, apache_col}
    feat_cols = [c for c in df.columns if c not in meta_cols]
    D, H, F = n_days, n_hours, len(feat_cols)
    print(
        f"[prepare] 特征 F={F} | D={D} H={H} | sliding={sliding_window} "
        f"expand_hours={expand_hours} max_cal_day={max_calendar_day}"
    )
    print(f"[prepare] 特征列示例: {feat_cols[:8]}{'...' if F > 8 else ''}")

    patients, feat, y, los, apache = _patient_day_table(
        df, patient_col, day_col, label_col, los_col, apache_col, feat_cols, max_calendar_day
    )
    packed = _expand_windows(
        patients, feat, y, los, apache, feat_cols, D, H, sliding_window, expand_hours
    )

    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(out_path, **packed)

    y_arr = packed["y"]
    n = int(len(y_arr))
    n_patients = len(patients)
    summary = {
        "out": str(out_path),
        "n_samples": n,
        "n_patients": n_patients,
        "D": D,
        "H": H,
        "F": F,
        "sliding_window": bool(sliding_window),
        "expand_hours": bool(expand_hours),
        "mortality_rate": float(y_arr.mean()) if n else 0.0,
        "median_los": int(np.median(list(los.values()))) if los else 0,
        "windows_per_patient_mean": float(n / max(n_patients, 1)),
    }
    print(
        f"[prepare] OK {out_path}: X={packed['X'].shape} | patients={n_patients} "
        f"samples={n} | F={F} D={D} H={H} | 死亡率={summary['mortality_rate']:.3f} | "
        f"窗/人≈{summary['windows_per_patient_mean']:.2f}"
    )
    return summary


def split_npz(
    in_path: str,
    out_dir: str,
    test_size: float = 0.1,
    val_size: float = 0.2,
    seed: int = 41,
) -> dict:
    """按 patient_id 划分，再展开所属窗口样本（防泄漏）。"""
    from sklearn.model_selection import train_test_split

    d = np.load(in_path, allow_pickle=True)
    X, y = d["X"], d["y"]
    if "patient_id" in d:
        pids = d["patient_id"]
        # 唯一患者（取该患者任一窗口的标签做分层）
        uniq, first_idx = np.unique(pids, return_index=True)
        y_pat = y[first_idx]
        idx_pat = np.arange(len(uniq))
        stratify = y_pat if len(np.unique(y_pat)) > 1 else None
        tr_p, te_p = train_test_split(idx_pat, test_size=test_size, random_state=seed, stratify=stratify)
        strat_tr = y_pat[tr_p] if stratify is not None else None
        val_frac = val_size / (1 - test_size)
        tr_p, va_p = train_test_split(tr_p, test_size=val_frac, random_state=seed, stratify=strat_tr)

        def mask_for(pat_sel):
            chosen = set(uniq[pat_sel].tolist())
            return np.array([p in chosen for p in pids], dtype=bool)

        train_idx = np.where(mask_for(tr_p))[0]
        val_idx = np.where(mask_for(va_p))[0]
        test_idx = np.where(mask_for(te_p))[0]
    else:
        idx = np.arange(len(y))
        stratify = y if len(np.unique(y)) > 1 else None
        train_idx, test_idx = train_test_split(idx, test_size=test_size, random_state=seed, stratify=stratify)
        strat_tr = y[train_idx] if stratify is not None else None
        val_frac = val_size / (1 - test_size)
        train_idx, val_idx = train_test_split(train_idx, test_size=val_frac, random_state=seed, stratify=strat_tr)

    optional = [k for k in ["day_mask", "apache", "patient_id", "window_start_day"] if k in d]
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    def pack(sel):
        packed = {"X": X[sel], "y": y[sel]}
        for k in optional:
            packed[k] = d[k][sel]
        if "feature_names" in d:
            packed["feature_names"] = d["feature_names"]
        return packed

    counts = {}
    for name, sel in [("train", train_idx), ("val", val_idx), ("test", test_idx)]:
        np.savez_compressed(out_dir / f"{name}.npz", **pack(sel))
        counts[name] = {"n": int(len(sel)), "n_pos": int(y[sel].sum())}
        print(f"[prepare/split] {name}: {len(sel)} (正例 {int(y[sel].sum())})")
    print("[prepare/split] OK 患者级 7:2:1（窗口样本随患者归属）")
    return counts


def prepare(
    out_dir: str,
    csv_path: Optional[str] = None,
    patient_col: str = "patient",
    day_col: str = "day",
    hour_col: str = "hour",
    label_col: str = "label",
    los_col: str = "los_days",
    apache_col: str = "apache",
    n_days: int = 5,
    n_hours: int = 24,
    seed: int = 42,
    sliding_window: bool = True,
    expand_hours: bool = True,
    max_calendar_day: int = 30,
) -> dict:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    if not csv_path:
        raise ValueError("tst_prepare 需要 --data-path 指向 R 导出的长表 CSV")
    full_path = out_dir / "full.npz"
    prep_summary = long_csv_to_npz(
        csv_path, full_path, patient_col, day_col, hour_col, label_col, los_col,
        apache_col, n_days, n_hours, sliding_window, expand_hours, max_calendar_day,
    )
    split_counts = split_npz(full_path, out_dir, seed=seed)
    meta = {
        "prepare": prep_summary,
        "split": split_counts,
        "seed": seed,
        "sliding_window": sliding_window,
        "expand_hours": expand_hours,
    }
    (out_dir / "prepare_meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    return meta


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser(description="ICU 长表 CSV -> 标准 npz + split")
    ap.add_argument("--csv", required=True)
    ap.add_argument("--out-dir", default="data")
    ap.add_argument("--patient-col", default="patient")
    ap.add_argument("--day-col", default="day")
    ap.add_argument("--hour-col", default="hour")
    ap.add_argument("--label-col", default="label")
    ap.add_argument("--los-col", default="los_days")
    ap.add_argument("--apache-col", default="apache")
    ap.add_argument("--n-days", type=int, default=5)
    ap.add_argument("--n-hours", type=int, default=24)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--sliding-window", action="store_true", default=True)
    ap.add_argument("--no-sliding-window", action="store_true")
    ap.add_argument("--expand-hours", action="store_true", default=True)
    ap.add_argument("--no-expand-hours", action="store_true")
    ap.add_argument("--max-calendar-day", type=int, default=30)
    args = ap.parse_args()
    sliding = not args.no_sliding_window
    expand = not args.no_expand_hours
    prepare(
        args.out_dir, args.csv, args.patient_col, args.day_col, args.hour_col,
        args.label_col, args.los_col, args.apache_col, args.n_days, args.n_hours, args.seed,
        sliding, expand, args.max_calendar_day,
    )
