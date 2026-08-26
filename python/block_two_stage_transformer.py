#!/usr/bin/env python3
"""block_two_stage_transformer.py — 两阶段 Transformer 卒中管线 Python CLI。

模式 (--mode):
  tst_prepare            长表 CSV(--data-path) -> train/val/test.npz(--out-dir)
  tst_train_a1           A1: 公开实现(单截止训练)迁移
  tst_train_a2           A2: 统一规范管线单阶段公平基线
  tst_train_b            B : 两阶段 Transformer(小时+天,多截止监督)
  tst_baselines          Logistic / XGBoost / MLP / LSTM 传统基线
  tst_ablation           Mask / 特征子集 / 结构消融
  tst_calibrate          校准曲线 + DCA
  tst_shap               分日 SHAP 热图
  tst_external_synthetic 合成地理外推(is_synthetic=TRUE,默认路径)
  tst_external           真实第二中心外推(无数据自动回退合成,并打印警告)
  tst_summary_results    项目级 summary_results/ 文献图表汇总（--out-dir=项目产出根）

CLI 风格对齐 `python/block_literature_extensions.py`(--mode / --out-dir 等),
不改动该文件既有 mode。R 侧调用见 `R/python_literature.R`
(`literature_python_script(root, name="block_two_stage_transformer.py")`)。
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# Windows Anaconda 上 numpy/torch/sklearn 各自打包 OpenMP 运行时可能冲突
# (`OMP: Error #15`),在任何科学计算库导入前设置该变量规避,不影响 Linux/WSL 原生 python3。
os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")

sys.path.insert(0, str(Path(__file__).resolve().parent))

from two_stage_transformer import baselines as baselines_mod  # noqa: E402
from two_stage_transformer import eval as eval_mod  # noqa: E402
from two_stage_transformer import prepare as prepare_mod  # noqa: E402
from two_stage_transformer import shap_plot as shap_mod  # noqa: E402
from two_stage_transformer import synthetic_external as ext_mod  # noqa: E402
from two_stage_transformer import train as train_mod  # noqa: E402


def _ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def main() -> None:
    ap = argparse.ArgumentParser(description="两阶段 Transformer 卒中管线 CLI")
    ap.add_argument("--mode", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--data-path", default="", help="tst_prepare: 长表 CSV;tst_external: 真实第二中心 npz(可选)")
    ap.add_argument("--data-dir", default="", help="train/val/test.npz 所在目录(默认取 --out-dir)")
    ap.add_argument("--arch", default="b", choices=["a1", "a2", "b"], help="tst_ablation/tst_calibrate/tst_shap/tst_external* 使用")
    ap.add_argument("--model-path", default="", help="tst_calibrate/tst_shap/tst_external* 加载的模型权重;为空则用随机初始化")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--epochs", type=int, default=100)
    ap.add_argument("--patience", type=int, default=15, help="早停耐心（0=关闭）")
    ap.add_argument("--batch-size", type=int, default=32)
    ap.add_argument("--lr", type=float, default=1e-4)
    ap.add_argument("--split", default="test")

    # tst_prepare
    ap.add_argument("--patient-col", default="patient")
    ap.add_argument("--day-col", default="day")
    ap.add_argument("--hour-col", default="hour")
    ap.add_argument("--label-col", default="label")
    ap.add_argument("--los-col", default="los_days")
    ap.add_argument("--apache-col", default="apache")
    ap.add_argument("--n-days", type=int, default=5)
    ap.add_argument("--n-hours", type=int, default=24)
    ap.add_argument("--sliding-window", action="store_true", default=True)
    ap.add_argument("--no-sliding-window", action="store_true")
    ap.add_argument("--expand-hours", action="store_true", default=True)
    ap.add_argument("--no-expand-hours", action="store_true")
    ap.add_argument("--max-calendar-day", type=int, default=30)

    # tst_baselines / tst_ablation
    ap.add_argument("--baseline-models", default="logistic,xgboost,mlp,lstm")
    ap.add_argument("--ablations", default="mask,feature_subset,structure")

    # tst_calibrate
    ap.add_argument("--cutoff", type=int, default=0, help="0 表示用 --n-days(最后一天)")

    # tst_external_synthetic / tst_external
    ap.add_argument("--n", type=int, default=200, help="合成外推样本数")
    ap.add_argument("--n-features", type=int, default=16, help="合成外推特征数")
    ap.add_argument(
        "--primary-landmark",
        type=int,
        default=72,
        help="tst_summary_results: 主文 landmark（小时）",
    )

    args = ap.parse_args()
    out = Path(args.out_dir)
    mode = args.mode
    if mode != "tst_summary_results":
        _ensure_dir(out)
    data_dir = args.data_dir or args.out_dir

    if mode == "tst_prepare":
        sliding = not args.no_sliding_window
        expand = not args.no_expand_hours
        prepare_mod.prepare(
            out_dir=str(out), csv_path=args.data_path or None,
            patient_col=args.patient_col, day_col=args.day_col, hour_col=args.hour_col,
            label_col=args.label_col, los_col=args.los_col, apache_col=args.apache_col,
            n_days=args.n_days, n_hours=args.n_hours, seed=args.seed,
            sliding_window=sliding, expand_hours=expand,
            max_calendar_day=args.max_calendar_day,
        )
    elif mode in ("tst_train_a1", "tst_train_a2", "tst_train_b"):
        arch = {"tst_train_a1": "a1", "tst_train_a2": "a2", "tst_train_b": "b"}[mode]
        summary = train_mod.train(
            data_dir=data_dir, out_dir=str(out), arch=arch, epochs=args.epochs,
            batch_size=args.batch_size, lr=args.lr, seed=args.seed,
            patience=args.patience,
        )
        eval_mod.evaluate(
            data_dir=data_dir, out_dir=str(out), model_path=summary["model_path"], arch=arch,
            split="test", is_synthetic=False, metrics_name=f"Table_TST_Metrics_{arch}.csv",
        )
    elif mode == "tst_baselines":
        baselines_mod.run_baselines(
            data_dir=data_dir, out_dir=str(out), models=args.baseline_models,
            seed=args.seed, epochs=max(args.epochs, 1),
        )
    elif mode == "tst_ablation":
        train_mod.run_ablation(
            data_dir=data_dir, out_dir=str(out), arch=args.arch, ablations=args.ablations,
            epochs=args.epochs, batch_size=args.batch_size, lr=args.lr, seed=args.seed,
        )
    elif mode == "tst_calibrate":
        eval_mod.calibration_dca(
            data_dir=data_dir, out_dir=str(out), model_path=args.model_path, arch=args.arch,
            split=args.split, cutoff=(args.cutoff or None),
        )
    elif mode == "tst_shap":
        # project_root：含 _shared/step02_column_mapping，供特征展示名 mapping
        proj_guess = str(Path(args.out_dir).resolve())
        for _ in range(6):
            p = Path(proj_guess)
            if (p / "_shared").is_dir() or (p / "by_unit").is_dir():
                break
            if p.parent == p:
                break
            proj_guess = str(p.parent)
        shap_mod.run_shap(
            data_dir=data_dir, out_dir=str(out), model_path=args.model_path, arch=args.arch,
            split=args.split, project_root=proj_guess,
        )
    elif mode == "tst_external_synthetic":
        ext_mod.evaluate_synthetic(
            out_dir=str(out), model_path=(args.model_path or None), arch=args.arch,
            n=args.n, n_days=args.n_days, n_hours=args.n_hours, n_features=args.n_features,
            seed=args.seed, epochs=args.epochs,
        )
    elif mode == "tst_external":
        ext_mod.run_external(
            out_dir=str(out), data_path=(args.data_path or None), model_path=(args.model_path or None),
            arch=args.arch, seed=args.seed, epochs=args.epochs,
            n=args.n, n_days=args.n_days, n_hours=args.n_hours, n_features=args.n_features,
        )
    elif mode == "tst_summary_results":
        # --out-dir 视为研究产出根（含 by_unit/）
        run_dir = Path(__file__).resolve().parent.parent / "run" / "two_stage_transformer_stroke"
        sys.path.insert(0, str(run_dir))
        from build_summary_results import build_summary_results  # noqa: WPS433

        build_summary_results(
            project_root=str(out),
            primary_landmark=int(args.primary_landmark or 72),
        )
    else:
        sys.exit(f"未知 mode: {mode}")


if __name__ == "__main__":
    main()
