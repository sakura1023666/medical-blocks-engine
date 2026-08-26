# -*- coding: utf-8 -*-
"""
TabICL（soda-inria/tabicl）导出脚本 — 输出与 block_ml_models.R 中 tablcl_v2 读取版式一致的 Excel。

与 python/block_tabpfn_ml_export.py 相同的数据契约与 sheet 结构，仅工作表名后缀为 _tablcl_v2，
指标计算与 TabPFN 脚本一致（reference = 正例概率，yardstick event_level=\"first\" 对齐）。
R 端 reticulate 调用时请设 config$ml_models$tablcl_v2_skip_metric_swap = TRUE（与 TabPFN reticulate 相同）。

依赖: pip install -r python/requirements-tabicl.txt

命令行:
  python block_tabicl_ml_export.py --train train.csv --val val.csv --out out.xlsx \\
      --ref Control --ana Case --n-folds 5 --seed 42

Windows 若遇 OpenMP 冲突，可在运行前设置环境变量: set KMP_DUPLICATE_LIB_OK=TRUE
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd


def _tabpfn_helpers():
    """复用 TabPFN 导出脚本中的 CSV 读取与指标工具（不触发 tabpfn 导入）。"""
    p = Path(__file__).resolve().parent / "block_tabpfn_ml_export.py"
    spec = importlib.util.spec_from_file_location("_tabpfn_export_helpers", p)
    m = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(m)
    return m


_tabpfn_helpers_mod = None


def _get_tabpfn_helpers():
    global _tabpfn_helpers_mod
    if _tabpfn_helpers_mod is None:
        _tabpfn_helpers_mod = _tabpfn_helpers()
    return _tabpfn_helpers_mod


def export_tabicl_excel(
    train_csv: str,
    val_csv: str,
    out_xlsx: str,
    ref_label: str,
    ana_label: str,
    n_folds: int = 5,
    seed: int = 42,
    device: str | None = None,
    kv_cache: bool = False,
    n_estimators: int | None = None,
    checkpoint_version: str | None = None,
    batch_size: int | None = None,
):
    try:
        from tabicl import TabICLClassifier
    except ImportError as e:
        raise ImportError(
            "未安装 tabicl。请在当前 Python 环境中执行: pip install -r python/requirements-tabicl.txt"
        ) from e

    mod = _get_tabpfn_helpers()
    X_tr, y_tr = mod._read_xy(train_csv, ref_label, ana_label)
    X_va, y_va = mod._read_xy(val_csv, ref_label, ana_label)

    y_tr_bin = (y_tr.astype(str).values == str(ref_label)).astype(np.int32)
    y_va_bin = (y_va.astype(str).values == str(ref_label)).astype(np.int32)

    clf_kw: dict = {
        "random_state": int(seed % (2**31 - 1)),
        "kv_cache": bool(kv_cache),
        "verbose": False,
    }
    if device is not None and str(device).strip() != "":
        clf_kw["device"] = str(device)
    if n_estimators is not None:
        clf_kw["n_estimators"] = int(n_estimators)
    if checkpoint_version is not None and str(checkpoint_version).strip() != "":
        clf_kw["checkpoint_version"] = str(checkpoint_version)
    if batch_size is not None:
        clf_kw["batch_size"] = int(batch_size)

    clf = TabICLClassifier(**clf_kw)
    clf.fit(X_tr, y_tr.values)

    classes = [str(c) for c in np.asarray(clf.classes_).ravel().tolist()]
    if str(ref_label) not in classes or str(ana_label) not in classes:
        raise ValueError(f"TabICL classes_ 不包含 ref/ana: {classes}")
    idx_ref = classes.index(str(ref_label))

    prob_tr = clf.predict_proba(X_tr)
    prob_va = clf.predict_proba(X_va)
    pr_tr = prob_tr[:, idx_ref].astype(np.float64)
    pr_va = prob_va[:, idx_ref].astype(np.float64)

    thr = mod._youden_threshold(y_tr_bin, pr_tr)

    predtrain = pd.DataFrame(
        {
            ref_label: pr_tr,
            ana_label: 1.0 - pr_tr,
            "Group": y_tr.values,
            "dataset": "train",
            "model": "TablCL_v2",
        }
    )
    predtest = pd.DataFrame(
        {
            ref_label: pr_va,
            ana_label: 1.0 - pr_va,
            "Group": y_va.values,
            "dataset": "test",
            "model": "TablCL_v2",
        }
    )

    eval_t = mod._build_eval_long(y_tr_bin, pr_tr, y_va_bin, pr_va, thr, ref_label, ana_label)
    eval_t["model"] = "TablCL_v2"

    train_full = X_tr.reset_index(drop=True).copy()
    train_full[ref_label] = pr_tr
    train_full[ana_label] = 1.0 - pr_tr
    train_full["Group"] = y_tr.values
    train_full["dataset"] = "Training set"

    val_full = X_va.reset_index(drop=True).copy()
    val_full[ref_label] = pr_va
    val_full[ana_label] = 1.0 - pr_va
    val_full["Group"] = y_va.values
    val_full["dataset"] = "Validation set"
    final_predictions = pd.concat([val_full, train_full], axis=0, ignore_index=True)

    from sklearn.model_selection import StratifiedKFold

    skf = StratifiedKFold(n_splits=n_folds, shuffle=True, random_state=seed)
    cv_rows_auc = []
    cv_rows_spec = []
    cv_rows_sens = []
    fold_id = 0
    for train_idx, val_idx in skf.split(X_tr, y_tr.values):
        fold_id += 1
        fid = f"Fold{fold_id:02d}"
        Xa = X_tr.iloc[train_idx].reset_index(drop=True)
        ya = y_tr.values[train_idx]
        Xb = X_tr.iloc[val_idx].reset_index(drop=True)
        yb = y_tr.values[val_idx]
        yb_bin = (yb.astype(str) == str(ref_label)).astype(np.int32)
        cvi_kw = dict(clf_kw)
        cvi_kw["random_state"] = int((seed + fold_id) % (2**31 - 1))
        cvi = TabICLClassifier(**cvi_kw)
        cvi.fit(Xa, ya)
        cls_b = [str(c) for c in np.asarray(cvi.classes_).ravel().tolist()]
        ir = cls_b.index(str(ref_label))
        pr_b = cvi.predict_proba(Xb)[:, ir].astype(np.float64)
        auc = mod._roc_auc_binary(yb_bin, pr_b)
        thr_cv = mod._youden_threshold(yb_bin, pr_b)
        sens, spec, _ = mod._metrics_at_threshold(yb_bin, pr_b, thr_cv)
        cv_rows_auc.append(
            {
                "id": fid,
                ".metric": "roc_auc",
                ".estimator": "binary",
                ".estimate": auc,
                "mean": np.nan,
                "std_err": np.nan,
            }
        )
        cv_rows_spec.append(
            {
                "id": fid,
                ".metric": "spec",
                ".estimator": "binary",
                ".estimate": spec,
                "mean": np.nan,
                "std_err": np.nan,
            }
        )
        cv_rows_sens.append(
            {
                "id": fid,
                ".metric": "sens",
                ".estimator": "binary",
                ".estimate": sens,
                "mean": np.nan,
                "std_err": np.nan,
            }
        )

    stem = "tablcl_v2"
    eval_best_cv5 = pd.DataFrame(cv_rows_auc)
    eval_best_cv5_spec = pd.DataFrame(cv_rows_spec)
    eval_best_cv5_sens = pd.DataFrame(cv_rows_sens)
    for d in (eval_best_cv5, eval_best_cv5_spec, eval_best_cv5_sens):
        d["model"] = "TablCL_v2"

    eval_best_cv5["mean"] = eval_best_cv5[".estimate"].mean()
    eval_best_cv5["std_err"] = eval_best_cv5[".estimate"].std(ddof=1) if n_folds > 1 else 0.0
    eval_best_cv5_spec["mean"] = eval_best_cv5_spec[".estimate"].mean()
    eval_best_cv5_spec["std_err"] = (
        eval_best_cv5_spec[".estimate"].std(ddof=1) if n_folds > 1 else 0.0
    )
    eval_best_cv5_sens["mean"] = eval_best_cv5_sens[".estimate"].mean()
    eval_best_cv5_sens["std_err"] = (
        eval_best_cv5_sens[".estimate"].std(ddof=1) if n_folds > 1 else 0.0
    )

    hp_payload = {
        "backend": "tabicl.TabICLClassifier",
        "n_folds": n_folds,
        "seed": seed,
        "n_features": int(X_tr.shape[1]),
        "device": device,
        "kv_cache": kv_cache,
        "n_estimators": n_estimators,
        "checkpoint_version": checkpoint_version,
        "batch_size": batch_size,
    }
    paras = pd.DataFrame(
        {
            "key": ["model_id", "hyperparameters"],
            "value": [
                "TabICLClassifier_TabICLv2",
                json.dumps(hp_payload, ensure_ascii=False).replace(":", "="),
            ],
        }
    )

    out_path = Path(out_xlsx)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with pd.ExcelWriter(out_path, engine="openpyxl") as writer:
        paras.to_excel(writer, sheet_name="paras", index=True)
        eval_t.to_excel(writer, sheet_name=f"eval_{stem}", index=True)
        predtrain.to_excel(writer, sheet_name=f"predtrain_{stem}", index=True)
        predtest.to_excel(writer, sheet_name=f"predtest_{stem}", index=True)
        final_predictions.to_excel(writer, sheet_name=f"final_predictions_{stem}", index=True)
        eval_best_cv5.to_excel(writer, sheet_name=f"eval_best_cv5_{stem}", index=True)
        eval_best_cv5_spec.to_excel(writer, sheet_name=f"eval_best_cv5_{stem}_spec", index=True)
        eval_best_cv5_sens.to_excel(writer, sheet_name=f"eval_best_cv5_{stem}_sens", index=True)

    return str(out_path.resolve())


def main(argv=None):
    p = argparse.ArgumentParser(description="Export TabICL results to Excel for R tablcl_v2.")
    p.add_argument("--train", required=True)
    p.add_argument("--val", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--ref", required=True)
    p.add_argument("--ana", required=True)
    p.add_argument("--n-folds", type=int, default=5)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument(
        "--device",
        default="",
        help="传给 TabICLClassifier，如 cpu / cuda / cuda:0；留空则库自动选择",
    )
    p.add_argument("--kv-cache", action="store_true", help="TabICLClassifier(kv_cache=True)")
    p.add_argument("--n-estimators", type=int, default=None)
    p.add_argument("--checkpoint-version", default=None, help="如 tabicl-classifier-v1-20250208.ckpt")
    p.add_argument("--batch-size", type=int, default=None)
    args = p.parse_args(argv)
    dev = args.device.strip() or None
    out = export_tabicl_excel(
        args.train,
        args.val,
        args.out,
        args.ref,
        args.ana,
        n_folds=args.n_folds,
        seed=args.seed,
        device=dev,
        kv_cache=args.kv_cache,
        n_estimators=args.n_estimators,
        checkpoint_version=args.checkpoint_version,
        batch_size=args.batch_size,
    )
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
