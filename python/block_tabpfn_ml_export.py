# -*- coding: utf-8 -*-
"""
TabPFN 导出脚本 — 供 R 流水线 block_ml_models 通过 reticulate 或命令行调用。

输入: 训练/验证 CSV（首列为 Group，其余为特征；Group 取值与 ref_label / ana_label 一致）
输出: 与 C10_TabPFN.R / .ml_run_tabpfn 兼容的 Excel（多 sheet），指标按 R 端约定：
      阳性类 = reference（对照）= yardstick event_level=\"first\"，R 中 skip_metric_swap=TRUE 不再对调 sens/spec。

依赖: pip install -r python/requirements-tabpfn.txt

命令行:
  python block_tabpfn_ml_export.py --train train.csv --val val.csv --out out.xlsx \\
      --ref Control --ana Case --n-folds 5 --seed 42 --device cpu
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Optional

import os

import numpy as np
import pandas as pd

# 强制优先本地 Roaming/tabpfn ckpt：即便 R→reticulate 未透传 HF_HUB_OFFLINE，也禁止联网下载
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("HF_DATASETS_OFFLINE", "1")

# Worker 常缺 APPDATA；TabPFN 会落到项目/.tabpfn_models 并尝试 HF 下载
if not (os.environ.get("APPDATA") or "").strip():
    _up = (os.environ.get("USERPROFILE") or os.environ.get("HOME") or r"C:\Users\Administrator").strip()
    os.environ["APPDATA"] = str(Path(_up) / "AppData" / "Roaming")
if not (os.environ.get("LOCALAPPDATA") or "").strip():
    _up = (os.environ.get("USERPROFILE") or os.environ.get("HOME") or r"C:\Users\Administrator").strip()
    os.environ["LOCALAPPDATA"] = str(Path(_up) / "AppData" / "Local")


def _local_tabpfn_ckpt(filename: str) -> str:
    """绝对路径指向本机 Roaming/tabpfn/*.ckpt；缺失则硬失败（禁止联网兜底）。"""
    cache = Path(os.environ["APPDATA"]) / "tabpfn" / filename
    if not cache.is_file():
        raise FileNotFoundError(
            f"本地 TabPFN 权重不存在: {cache}. "
            f"请将 ckpt 放到 %APPDATA%\\tabpfn\\（离线强制，不走 HuggingFace）。"
        )
    return str(cache)


def _persist_tabpfn_token_for_auth(tok: str) -> None:
    """对齐 tabpfn.browser_auth.get_cached_token：先读 TABPFN_TOKEN，再读 ~/.cache/tabpfn/auth_token。

    嵌入式 reticulate 下环境变量常丢失，写入缓存文件与官方登录成功后的行为一致。
    """
    t = tok.strip()
    if not t:
        return
    os.environ["TABPFN_TOKEN"] = t
    os.environ.setdefault("TABPFN_API_KEY", t)
    try:
        cache_dir = Path.home() / ".cache" / "tabpfn"
        cache_dir.mkdir(parents=True, exist_ok=True)
        (cache_dir / "auth_token").write_text(t, encoding="utf-8")
    except OSError:
        pass


def _bootstrap_prior_labs_token() -> None:
    """在首次 import tabpfn 之前解析 JWT（env / TOKEN_FILE）并写入 TOKEN + 缓存文件。"""
    tok = (os.environ.get("TABPFN_TOKEN") or os.environ.get("TABPFN_API_KEY") or "").strip()
    if not tok:
        fp = os.environ.get("TABPFN_TOKEN_FILE")
        if fp:
            p = Path(fp)
            if p.is_file():
                tok = p.read_text(encoding="utf-8").strip()
    if tok:
        _persist_tabpfn_token_for_auth(tok)


_bootstrap_prior_labs_token()


def _read_xy(csv_path: str, ref_label: str, ana_label: str):
    df = pd.read_csv(csv_path, encoding="utf-8")
    if df.shape[1] < 2:
        raise ValueError(f"CSV 至少需要 2 列（Group + 特征）: {csv_path}")
    if str(df.columns[0]) != "Group":
        raise ValueError(f"首列须为 Group，当前为: {df.columns[0]!r} ({csv_path})")
    y = df["Group"].astype(str)
    X = df.iloc[:, 1:].copy()
    ok = y.isin([str(ref_label), str(ana_label)])
    X = X.loc[ok].reset_index(drop=True)
    y = y.loc[ok].reset_index(drop=True)
    if len(y) == 0:
        raise ValueError(f"无有效二分类标签: {csv_path}")
    return X, y


def _encode_xy(X_tr: pd.DataFrame, X_va: pd.DataFrame):
    """训练集拟合 one-hot，验证集按训练列对齐。"""
    tr_enc = pd.get_dummies(X_tr, dummy_na=False)
    va_enc = pd.get_dummies(X_va, dummy_na=False)
    va_enc = va_enc.reindex(columns=tr_enc.columns, fill_value=0)
    return tr_enc.astype(np.float32).values, va_enc.astype(np.float32).values


def _youden_threshold(y_bin: np.ndarray, score: np.ndarray) -> float:
    from sklearn.metrics import roc_curve

    fpr, tpr, thr = roc_curve(y_bin, score, drop_intermediate=True)
    youden = tpr - fpr
    i = int(np.argmax(youden))
    return float(thr[i])


def _metrics_at_threshold(y_bin: np.ndarray, score: np.ndarray, thr: float):
    pred = (score >= thr).astype(int)
    tp = int(np.sum((pred == 1) & (y_bin == 1)))
    tn = int(np.sum((pred == 0) & (y_bin == 0)))
    fp = int(np.sum((pred == 1) & (y_bin == 0)))
    fn = int(np.sum((pred == 0) & (y_bin == 1)))
    sens = tp / (tp + fn) if (tp + fn) > 0 else float("nan")
    spec = tn / (tn + fp) if (tn + fp) > 0 else float("nan")
    acc = (tp + tn) / max(len(y_bin), 1)
    return sens, spec, acc


def _roc_auc_binary(y_bin: np.ndarray, score: np.ndarray) -> float:
    from sklearn.metrics import roc_auc_score

    if len(np.unique(y_bin)) < 2:
        return float("nan")
    return float(roc_auc_score(y_bin, score))


def _pr_auc_binary(y_bin: np.ndarray, score: np.ndarray) -> float:
    from sklearn.metrics import average_precision_score

    if len(np.unique(y_bin)) < 2:
        return float("nan")
    return float(average_precision_score(y_bin, score))


def _kap(y_bin: np.ndarray, score: np.ndarray, thr: float) -> float:
    try:
        from sklearn.metrics import cohen_kappa_score

        pred = (score >= thr).astype(int)
        if len(np.unique(y_bin)) < 2:
            return float("nan")
        return float(cohen_kappa_score(y_bin, pred))
    except Exception:
        return float("nan")


def _build_eval_long(y_tr_bin, pr_tr, y_va_bin, pr_va, thr, ref_label: str, ana_label: str):
    rows = []
    for name, yb, pr in [("train", y_tr_bin, pr_tr), ("test", y_va_bin, pr_va)]:
        sens, spec, acc = _metrics_at_threshold(yb, pr, thr)
        roc = _roc_auc_binary(yb, pr)
        pr_auc = _pr_auc_binary(yb, pr)
        kap = _kap(yb, pr, thr)
        pred = (pr >= thr).astype(int)
        tp = int(np.sum((pred == 1) & (yb == 1)))
        fp = int(np.sum((pred == 1) & (yb == 0)))
        ppv = tp / (tp + fp) if (tp + fp) > 0 else float("nan")
        tn = int(np.sum((pred == 0) & (yb == 0)))
        fn = int(np.sum((pred == 0) & (yb == 1)))
        npv = tn / (tn + fn) if (tn + fn) > 0 else float("nan")
        f_meas = 2 * ppv * sens / (ppv + sens) if (ppv + sens) > 0 else float("nan")
        for metric, est, val in [
            ("accuracy", "binary", acc),
            ("kap", "binary", kap),
            ("sens", "binary", sens),
            ("spec", "binary", spec),
            ("ppv", "binary", ppv),
            ("npv", "binary", npv),
            ("f_meas", "binary", f_meas),
            ("mcc", "binary", float("nan")),
            ("j_index", "binary", float("nan")),
            ("bal_accuracy", "binary", float("nan")),
            ("precision", "binary", ppv),
            ("recall", "binary", sens),
            ("roc_auc", "binary", roc),
            ("pr_auc", "binary", pr_auc),
        ]:
            rows.append({".metric": metric, ".estimator": est, ".estimate": val, "dataset": name})
    out = pd.DataFrame(rows)
    return out


def _build_classifier(model_version: str, seed: int, device: str, ignore_pretraining_limits: bool):
    """根据 model_version 构建对应版本的 TabPFNClassifier。

    model_version:
      "v2"       — TabPFN v2 原始模型（本地 finetuned ckpt）
      "v2.5"     — TabPFN v2.5 标准默认 checkpoint
      "v2.5_real"— TabPFN v2.5 Real 变体
      "auto"/"v2.6" — 包默认 v2.6（本地 default ckpt）
    一律 model_path=本地绝对路径，禁止 create_default_for_version 触发下载。
    """
    from tabpfn import TabPFNClassifier

    kw = dict(
        random_state=int(seed % (2**31 - 1)),
        device=device,
        ignore_pretraining_limits=bool(ignore_pretraining_limits),
    )

    mv = str(model_version).strip().lower()
    if mv == "v2":
        return TabPFNClassifier(
            model_path=_local_tabpfn_ckpt("tabpfn-v2-classifier-finetuned-zk73skhh.ckpt"),
            **kw,
        )
    elif mv == "v2.5":
        return TabPFNClassifier(
            model_path=_local_tabpfn_ckpt("tabpfn-v2.5-classifier-v2.5_default.ckpt"),
            **kw,
        )
    elif mv == "v2.5_real":
        return TabPFNClassifier(
            model_path=_local_tabpfn_ckpt("tabpfn-v2.5-classifier-v2.5_real.ckpt"),
            n_estimators=8,
            softmax_temperature=0.9,
            **kw,
        )
    else:
        # "auto" / "v2.6" / 其他 → 本地 v2.6 default
        return TabPFNClassifier(
            model_path=_local_tabpfn_ckpt("tabpfn-v2.6-classifier-v2.6_default.ckpt"),
            **kw,
        )


def _ensure_tabpfn_token_env(tabpfn_token: Optional[str] = None) -> None:
    """在 export_tabpfn_excel 内再次对齐 TOKEN（含 R 传入的 tabpfn_token 字符串）。"""
    tok = None
    if tabpfn_token is not None and str(tabpfn_token).strip():
        tok = str(tabpfn_token).strip()
    if not tok:
        tok = (os.environ.get("TABPFN_TOKEN") or os.environ.get("TABPFN_API_KEY") or "").strip()
    fp = os.environ.get("TABPFN_TOKEN_FILE")
    if not tok and fp:
        p = Path(fp)
        if p.is_file():
            tok = p.read_text(encoding="utf-8").strip()
    if tok:
        _persist_tabpfn_token_for_auth(tok)


def export_tabpfn_excel(
    train_csv: str,
    val_csv: str,
    out_xlsx: str,
    ref_label: str,
    ana_label: str,
    n_folds: int = 5,
    seed: int = 42,
    device: str = "cpu",
    ignore_pretraining_limits: bool = False,
    tabpfn_token: Optional[str] = None,
    model_version: str = "v2",
):
    """导出 TabPFN 系列模型结果到 Excel。

    model_version:
      "v2"        → TabPFN v2（原始模型，ModelVersion.V2）
      "v2.5"      → TabPFN v2.5 标准 checkpoint（ModelVersion.V2_5）
      "v2.5_real" → TabPFN v2.5 Real 变体（真实数据训练）
      "auto"/"v2.6" → 包默认值（当前 V2_6）
    """
    _ensure_tabpfn_token_env(tabpfn_token)

    try:
        from tabpfn import TabPFNClassifier  # noqa: F401
    except ImportError as e:
        raise ImportError(
            "未安装 Python 包 tabpfn。请在当前 Python 环境中执行: pip install tabpfn"
        ) from e

    # 根据 model_version 决定模型标签（写入 Excel 及 R 端显示）
    _MV_LABEL = {
        "v2": "TabPFN",
        "v2.5": "TabPFNv2",
        "v2.5_real": "RealTabPFN-2.5",
    }
    model_label = _MV_LABEL.get(str(model_version).strip().lower(), "TabPFN")

    X_tr, y_tr = _read_xy(train_csv, ref_label, ana_label)
    X_va, y_va = _read_xy(val_csv, ref_label, ana_label)
    X_tr_np, X_va_np = _encode_xy(X_tr, X_va)

    y_tr_bin = (y_tr.astype(str).values == str(ref_label)).astype(np.int32)
    y_va_bin = (y_va.astype(str).values == str(ref_label)).astype(np.int32)

    clf = _build_classifier(model_version, seed, device, ignore_pretraining_limits)
    clf.fit(X_tr_np, y_tr.values)

    classes = [str(c) for c in np.asarray(clf.classes_).ravel().tolist()]
    if str(ref_label) not in classes or str(ana_label) not in classes:
        raise ValueError(f"TabPFN classes_ 不包含 ref/ana: {classes}")
    idx_ref = classes.index(str(ref_label))

    prob_tr = clf.predict_proba(X_tr_np)
    prob_va = clf.predict_proba(X_va_np)
    pr_tr = prob_tr[:, idx_ref].astype(np.float64)
    pr_va = prob_va[:, idx_ref].astype(np.float64)

    thr = _youden_threshold(y_tr_bin, pr_tr)

    predtrain = pd.DataFrame(
        {
            ref_label: pr_tr,
            ana_label: 1.0 - pr_tr,
            "Group": y_tr.values,
            "dataset": "train",
            "model": model_label,
        }
    )
    predtest = pd.DataFrame(
        {
            ref_label: pr_va,
            ana_label: 1.0 - pr_va,
            "Group": y_va.values,
            "dataset": "test",
            "model": model_label,
        }
    )

    eval_df = _build_eval_long(y_tr_bin, pr_tr, y_va_bin, pr_va, thr, ref_label, ana_label)
    eval_df["model"] = model_label

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
    for train_idx, val_idx in skf.split(X_tr_np, y_tr.values):
        fold_id += 1
        fid = f"Fold{fold_id:02d}"
        Xa, ya = X_tr_np[train_idx], y_tr.values[train_idx]
        Xb, yb = X_tr_np[val_idx], y_tr.values[val_idx]
        yb_bin = (yb.astype(str) == str(ref_label)).astype(np.int32)
        cvi = _build_classifier(
            model_version, seed + fold_id, device, ignore_pretraining_limits
        )
        cvi.fit(Xa, ya)
        cls_b = [str(c) for c in np.asarray(cvi.classes_).ravel().tolist()]
        ir = cls_b.index(str(ref_label))
        pr_b = cvi.predict_proba(Xb)[:, ir].astype(np.float64)
        auc = _roc_auc_binary(yb_bin, pr_b)
        thr_cv = _youden_threshold(yb_bin, pr_b)
        sens, spec, _ = _metrics_at_threshold(yb_bin, pr_b, thr_cv)
        cv_rows_auc.append({"id": fid, ".metric": "roc_auc", ".estimator": "binary",
                             ".estimate": auc, "mean": np.nan, "std_err": np.nan})
        cv_rows_spec.append({"id": fid, ".metric": "spec", ".estimator": "binary",
                              ".estimate": spec, "mean": np.nan, "std_err": np.nan})
        cv_rows_sens.append({"id": fid, ".metric": "sens", ".estimator": "binary",
                              ".estimate": sens, "mean": np.nan, "std_err": np.nan})

    eval_best_cv5 = pd.DataFrame(cv_rows_auc)
    eval_best_cv5_spec = pd.DataFrame(cv_rows_spec)
    eval_best_cv5_sens = pd.DataFrame(cv_rows_sens)
    for d in (eval_best_cv5, eval_best_cv5_spec, eval_best_cv5_sens):
        d["model"] = model_label

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

    paras = pd.DataFrame(
        {
            "key": ["model_id", "hyperparameters"],
            "value": [
                f"TabPFNClassifier_{model_version}",
                json.dumps(
                    {
                        "model_version": model_version,
                        "device": device,
                        "n_folds": n_folds,
                        "seed": seed,
                        "n_features": int(X_tr_np.shape[1]),
                        "ignore_pretraining_limits": ignore_pretraining_limits,
                    },
                    ensure_ascii=False,
                ).replace(":", "="),
            ],
        }
    )

    out_path = Path(out_xlsx)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with pd.ExcelWriter(out_path, engine="openpyxl") as writer:
        paras.to_excel(writer, sheet_name="paras", index=True)
        eval_df.to_excel(writer, sheet_name="eval_tabpfn", index=True)
        predtrain.to_excel(writer, sheet_name="predtrain_tabpfn", index=True)
        predtest.to_excel(writer, sheet_name="predtest_tabpfn", index=True)
        final_predictions.to_excel(writer, sheet_name="final_predictions_tabpfn", index=True)
        eval_best_cv5.to_excel(writer, sheet_name="eval_best_cv5_tabpfn", index=True)
        eval_best_cv5_spec.to_excel(writer, sheet_name="eval_best_cv5_tabpfn_spec", index=True)
        eval_best_cv5_sens.to_excel(writer, sheet_name="eval_best_cv5_tabpfn_sens", index=True)

    return str(out_path.resolve())


def export_tabpfnv2_excel(
    train_csv: str, val_csv: str, out_xlsx: str, ref_label: str, ana_label: str,
    n_folds: int = 5, seed: int = 42, device: str = "cpu",
    ignore_pretraining_limits: bool = False, tabpfn_token: Optional[str] = None,
):
    """TabPFN v2.5 标准 checkpoint。"""
    return export_tabpfn_excel(
        train_csv, val_csv, out_xlsx, ref_label, ana_label,
        n_folds=n_folds, seed=seed, device=device,
        ignore_pretraining_limits=ignore_pretraining_limits,
        tabpfn_token=tabpfn_token, model_version="v2.5",
    )


def export_realtabpfn_excel(
    train_csv: str, val_csv: str, out_xlsx: str, ref_label: str, ana_label: str,
    n_folds: int = 5, seed: int = 42, device: str = "cpu",
    ignore_pretraining_limits: bool = False, tabpfn_token: Optional[str] = None,
):
    """TabPFN v2.5 Real 变体（真实数据训练 checkpoint）。"""
    return export_tabpfn_excel(
        train_csv, val_csv, out_xlsx, ref_label, ana_label,
        n_folds=n_folds, seed=seed, device=device,
        ignore_pretraining_limits=ignore_pretraining_limits,
        tabpfn_token=tabpfn_token, model_version="v2.5_real",
    )


def main(argv=None):
    p = argparse.ArgumentParser(description="Export TabPFN results to Excel for R block.")
    p.add_argument("--train", required=True)
    p.add_argument("--val", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--ref", required=True, help="Reference / control label (R first level)")
    p.add_argument("--ana", required=True, help="Analysis / case label")
    p.add_argument("--n-folds", type=int, default=5)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--device", default="cpu")
    p.add_argument(
        "--model-version", default="v2",
        help="v2 | v2.5 | v2.5_real | auto  (默认 v2)",
    )
    p.add_argument(
        "--ignore-pretraining-limits",
        action="store_true",
        help="传给 TabPFNClassifier（样本/特征超限时）",
    )
    args = p.parse_args(argv)
    out = export_tabpfn_excel(
        args.train,
        args.val,
        args.out,
        args.ref,
        args.ana,
        n_folds=args.n_folds,
        seed=args.seed,
        device=args.device,
        ignore_pretraining_limits=args.ignore_pretraining_limits,
        model_version=args.model_version,
    )
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
