#!/usr/bin/env python3
"""Repeated patient-level 7:2:1 splits → Day1–5 mean(SD) for Table 2.

原文公开代码仅为单次 random_state=41 的 7:2:1，Table 2 的 mean(SD) 来源
原文未明确说明【证据不足】。本脚本用患者级分层重复 7:2:1（默认 5 seeds）
估计折间 mean±SD，并同步计算同折 test 上的 SAPSII 对照【场景迁移】。
"""
from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader

REPO_CANDS = [
    Path(r"E:/01block/01Block-new-Final"),
    Path("/mnt/e/01block/01Block-new-Final"),
]
PROJ_CANDS = [
    Path(r"G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
    Path("/mnt/g/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
]


def find_path(cands: list[Path]) -> Path:
    for p in cands:
        if p.exists():
            return p
    raise SystemExit(f"path not found among {[str(c) for c in cands]}")


REPO = find_path(REPO_CANDS)
PROJ = find_path(PROJ_CANDS)
sys.path.insert(0, str(REPO))

from python.two_stage_transformer.dataloader import TSTDataset  # noqa: E402
from python.two_stage_transformer.eval import load_model_for_eval, score_all_cutoffs  # noqa: E402
from python.two_stage_transformer.prepare import split_npz  # noqa: E402
from python.two_stage_transformer.train import train  # noqa: E402


def roc_curve_np(y_true, y_score):
    y_true = np.asarray(y_true).astype(int)
    y_score = np.asarray(y_score, dtype=float)
    order = np.argsort(-y_score)
    y_true = y_true[order]
    y_score = y_score[order]
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


def load_saps_map(proj: Path) -> dict[int, float]:
    path = proj / "_tmp_sapsii_by_stay.csv"
    out: dict[int, float] = {}
    if not path.is_file():
        print(f"[cv] WARN missing SAPSII map: {path}")
        return out
    with path.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            out[int(float(row["stay_id"]))] = float(row["SAPSII"])
    return out


def day_metrics_from_scores(y, los, scores_by_day: dict[int, np.ndarray], max_day: int = 5) -> list[dict]:
    rows = []
    for c in range(1, max_day + 1):
        sel = los >= c
        yy = y[sel]
        ss = scores_by_day[c][sel]
        if len(yy) < 5 or len(np.unique(yy)) < 2:
            rows.append({"day": c, "auc": float("nan"), "acc": float("nan"), "f1": float("nan"), "n": int(len(yy))})
            continue
        auc = float(roc_auc_score(yy, ss))
        pred, thr = youden_pred(yy, ss)
        acc = float((pred == yy).mean())
        f1 = float(f1_score_binary(yy, pred))
        rows.append({"day": c, "auc": auc, "acc": acc, "f1": f1, "n": int(len(yy)), "thr": thr})
    return rows


def eval_transformer_days(data_dir: Path, model_path: Path, arch: str = "b") -> list[dict]:
    ds = TSTDataset("test", str(data_dir))
    D, H, F = ds.n_days, ds.n_hours, ds.n_features
    dl = DataLoader(ds, batch_size=64, shuffle=False)
    model = load_model_for_eval(str(model_path), arch, D, H, F)
    scores = score_all_cutoffs(model, dl, D)
    los = ds.day_mask.sum(1).astype(int)
    return day_metrics_from_scores(ds.y, los, scores, max_day=min(D, 5))


def eval_sapsii_days(data_dir: Path, saps_map: dict[int, float], max_day: int = 5) -> list[dict]:
    d = np.load(data_dir / "test.npz", allow_pickle=False)
    y = d["y"].astype(int)
    los = d["day_mask"].sum(1).astype(int)
    if "patient_id" not in d:
        return [{"day": c, "auc": float("nan"), "acc": float("nan"), "f1": float("nan"), "n": 0} for c in range(1, max_day + 1)]
    pids = d["patient_id"].astype(np.int64)
    saps = np.array([saps_map.get(int(p), np.nan) for p in pids], dtype=np.float64)
    ok = ~np.isnan(saps)
    # zero-out LOS for missing SAPS so day selection excludes them
    los_eff = los.copy()
    los_eff[~ok] = 0
    scores = {c: saps for c in range(1, max_day + 1)}
    return day_metrics_from_scores(y, los_eff, scores, max_day=max_day)


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        return
    keys = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)


def run_one_seed(
    *,
    full_npz: Path,
    work_root: Path,
    seed: int,
    saps_map: dict[int, float],
    epochs: int,
    patience: int,
    arch: str,
    train_seed: int,
) -> list[dict]:
    fold_dir = work_root / f"seed_{seed}"
    data_dir = fold_dir / "npz"
    out_dir = fold_dir / "Tables"
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n===== CV seed={seed} =====", flush=True)
    t0 = time.time()
    counts = split_npz(str(full_npz), str(data_dir), seed=seed)
    (fold_dir / "split_counts.json").write_text(json.dumps(counts, indent=2), encoding="utf-8")

    summary = train(
        data_dir=str(data_dir),
        out_dir=str(out_dir),
        arch=arch,
        epochs=epochs,
        patience=patience,
        seed=train_seed,
    )
    model_path = Path(summary["model_path"])
    tr_rows = eval_transformer_days(data_dir, model_path, arch=arch)
    sa_rows = eval_sapsii_days(data_dir, saps_map, max_day=5)

    rows = []
    for r in tr_rows:
        rows.append({
            "seed": seed,
            "model": "Transformer",
            "day": r["day"],
            "auc": r["auc"],
            "acc": r["acc"],
            "f1": r["f1"],
            "n": r["n"],
            "epochs_ran": summary.get("epochs_ran"),
            "best_epoch": summary.get("best_epoch"),
            "best_val_loss": summary.get("best_val_loss"),
            "elapsed_sec": round(time.time() - t0, 1),
        })
    for r in sa_rows:
        rows.append({
            "seed": seed,
            "model": "SAPSII",
            "day": r["day"],
            "auc": r["auc"],
            "acc": r["acc"],
            "f1": r["f1"],
            "n": r["n"],
            "epochs_ran": "",
            "best_epoch": "",
            "best_val_loss": "",
            "elapsed_sec": round(time.time() - t0, 1),
        })
    write_csv(fold_dir / "fold_day_metrics.csv", rows)
    print(f"[cv] seed={seed} done in {time.time() - t0:.0f}s", flush=True)
    return rows


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--landmark", type=int, default=72)
    ap.add_argument("--seeds", default="41,42,43,44,45", help="comma-separated split seeds")
    ap.add_argument("--epochs", type=int, default=100)
    ap.add_argument("--patience", type=int, default=15)
    ap.add_argument("--arch", default="b")
    ap.add_argument("--train-seed", type=int, default=42, help="torch init seed (fixed across folds)")
    ap.add_argument(
        "--full-npz",
        default="",
        help="override full.npz path",
    )
    ap.add_argument(
        "--work-dir",
        default="",
        help="CV working directory (default: summary_results/cv_table2_repeated_split)",
    )
    args = ap.parse_args()

    lm = int(args.landmark)
    seeds = [int(x) for x in args.seeds.split(",") if x.strip()]
    unit = PROJ / f"by_unit/【success】L{lm}_B_twostage/step09_tst_train_eval/Tables/npz/full.npz"
    full_npz = Path(args.full_npz) if args.full_npz else unit
    if not full_npz.is_file():
        raise SystemExit(f"full.npz not found: {full_npz}")

    work_root = Path(args.work_dir) if args.work_dir else (
        PROJ / "summary_results" / "cv_table2_repeated_split"
    )
    work_root.mkdir(parents=True, exist_ok=True)

    meta = {
        "protocol": "repeated_patient_level_7_2_1",
        "n_repeats": len(seeds),
        "seeds": seeds,
        "epochs": args.epochs,
        "patience": args.patience,
        "arch": args.arch,
        "train_seed": args.train_seed,
        "full_npz": str(full_npz),
        "device": str(torch.device("cuda" if torch.cuda.is_available() else "cpu")),
        "note": (
            "Paper Table2 mean(SD) source not specified 【证据不足】; "
            "public code is single seed=41 split. "
            "Here: patient-level stratified 7:2:1 × N seeds 【场景迁移】."
        ),
    }
    (work_root / "cv_meta.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(meta, indent=2, ensure_ascii=False), flush=True)

    saps_map = load_saps_map(PROJ)
    all_rows: list[dict] = []
    for seed in seeds:
        fold_csv = work_root / f"seed_{seed}" / "fold_day_metrics.csv"
        if fold_csv.is_file():
            print(f"[cv] resume skip train seed={seed} (found {fold_csv})", flush=True)
            with fold_csv.open(encoding="utf-8-sig") as f:
                all_rows.extend(list(csv.DictReader(f)))
            continue
        all_rows.extend(
            run_one_seed(
                full_npz=full_npz,
                work_root=work_root,
                seed=seed,
                saps_map=saps_map,
                epochs=args.epochs,
                patience=args.patience,
                arch=args.arch,
                train_seed=args.train_seed,
            )
        )

    # normalize numeric fields for aggregate csv
    norm_rows = []
    for r in all_rows:
        nr = dict(r)
        for k in ("seed", "day", "n"):
            if nr.get(k) not in (None, ""):
                nr[k] = int(float(nr[k]))
        for k in ("auc", "acc", "f1"):
            if nr.get(k) not in (None, ""):
                nr[k] = float(nr[k])
        norm_rows.append(nr)

    out_csv = work_root / "Table_CV_fold_day_metrics.csv"
    write_csv(out_csv, norm_rows)
    print(f"[cv] wrote {out_csv} n_rows={len(norm_rows)}", flush=True)

    # invoke table rebuild
    rebuild = (
        Path(__file__).resolve().parents[2]
        / "Blocks/71_two_stage_transformer_stroke/scripts/rebuild_table2_yang_layout.py"
    )
    subprocess.check_call([sys.executable, str(rebuild), "--from-cv", str(work_root)])


if __name__ == "__main__":
    main()
