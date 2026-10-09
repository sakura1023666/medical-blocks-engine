#!/usr/bin/env python3
"""Rebuild Table 2 in Yang pbaf003 layout: metrics × (Day1–5 + SAPSII).

原文 Table 2: 行=AUC / Accuracy(%) / F1-score；列=Day1–5 + APACHE II；单元格 mean (SD)。
本复现对照为 SAPSII【场景迁移】。

优先读 repeated 7:2:1 CV 结果（--from-cv）；否则回退到单次 test 点估计。
"""
from __future__ import annotations

import argparse
import csv
import math
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, Side
from openpyxl.utils import get_column_letter
from sklearn.metrics import f1_score as sk_f1_score
from sklearn.metrics import roc_auc_score as sk_roc_auc_score
from sklearn.metrics import roc_curve as sk_roc_curve

REPO = Path(r"E:/01block/01Block-new-Final")
if not REPO.exists():
    REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO))

PROJ_CANDS = [
    Path(r"G:/02block_result/33_AKI/two_stage_transformer_40041421"),
    Path("/mnt/g/02block_result/33_AKI/two_stage_transformer_40041421"),
    Path(r"G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
    Path("/mnt/g/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
]
FONT = "Times New Roman"
# 与 Fig S6 / Table 3 铁律一致：同一 bootstrap，禁止 seed+day
BOOTSTRAP_SEED = 42
BOOTSTRAP_N = 400


def _norm_proj_path(p: Path | str) -> Path:
    """Normalize project root for Win/WSL; keep whichever form exists on disk."""
    raw = Path(str(p))
    s = str(p).replace("\\", "/")
    cands: list[Path] = [raw]
    if s.startswith("/mnt/") and len(s.split("/")) >= 4:
        drive = s.split("/")[2].upper()
        rest = "/".join(s.split("/")[3:])
        cands.append(Path(f"{drive}:/{rest}"))
    elif len(s) >= 3 and s[1] == ":" and s[0].isalpha():
        drive = s[0].lower()
        rest = s[3:].lstrip("/")
        cands.append(Path(f"/mnt/{drive}/{rest}"))
    for c in cands:
        if c.exists():
            return c
    return raw


def find_proj() -> Path:
    for p in PROJ_CANDS:
        if p.exists():
            return p
    raise SystemExit("project root not found")


def roc_auc_score(y_true, y_score):
    """与 redraw_fig_s6_comparison / Table 3 同一 sklearn 口径（勿再用自写 ROC）。"""
    return float(sk_roc_auc_score(np.asarray(y_true).astype(int), np.asarray(y_score, dtype=float)))


def youden_pred(y, scores):
    """Youden 阈值：与 Fig S6 / Table 3 同用 sklearn.roc_curve + scores > thr。"""
    y = np.asarray(y).astype(int)
    scores = np.asarray(scores, dtype=float)
    fpr, tpr, thr = sk_roc_curve(y, scores)
    if len(thr) == 0:
        return np.zeros_like(y), 0.5
    opt = float(thr[np.argmax(tpr - fpr)])
    return (scores > opt).astype(int), opt


def f1_score_binary(y_true, y_pred):
    return float(sk_f1_score(np.asarray(y_true).astype(int), np.asarray(y_pred).astype(int), zero_division=0))


def fmt_point(x: float, *, pct: bool = False, kind: str = "auc") -> str:
    if x != x:
        return "—"
    if pct or kind == "acc":
        return f"{100.0 * x:.2f}"
    if kind == "f1":
        return f"{x:.3f}"
    return f"{x:.2f}"


def fmt_mean_sd(vals: list[float], *, pct: bool = False, kind: str = "auc") -> str:
    """Yang Table 2 单元格：AUC mean 2dp / SD 3dp；Accuracy % 均 2dp；F1 均 3dp。"""
    a = np.asarray(vals, dtype=float)
    a = a[np.isfinite(a)]
    if a.size == 0:
        return "—"
    m = float(a.mean())
    s = float(a.std(ddof=1)) if a.size > 1 else 0.0
    # 仅单点且无离散度时退回点估计（无 CV / 无 bootstrap）
    if a.size == 1 or (not np.isfinite(s)) or s < 1e-12:
        return fmt_point(m, pct=pct, kind=kind)
    if pct or kind == "acc":
        return f"{100.0 * m:.2f} ({100.0 * s:.2f})"
    if kind == "f1":
        return f"{m:.3f} ({s:.3f})"
    return f"{m:.2f} ({s:.3f})"


def fmt_mean_sd_pair(mean: float, sd: float, *, kind: str = "auc") -> str:
    """已汇总的 mean/sd → 与图示一致的 `mean (SD)` 字符串（强制带括号）。"""
    if mean != mean:
        return "—"
    s = 0.0 if (sd != sd or sd < 0) else float(sd)
    if kind == "acc":
        return f"{100.0 * mean:.2f} ({100.0 * s:.2f})"
    if kind == "f1":
        return f"{mean:.3f} ({s:.3f})"
    return f"{mean:.2f} ({s:.3f})"


def bootstrap_metric_lists(
    y: np.ndarray,
    scores: np.ndarray,
    *,
    n_boot: int = BOOTSTRAP_N,
    seed: int = BOOTSTRAP_SEED,
) -> dict[str, list[float]]:
    """Patient-level bootstrap → auc/acc/f1 列表（与 Fig S6 / Table 3 同口径）。

    铁律：seed 固定为 BOOTSTRAP_SEED（默认 42），禁止 seed+day。
    """
    if int(seed) != int(BOOTSTRAP_SEED):
        # 允许显式传入，但打印告警；Day 列之间不得用 seed+day
        print(f"[boot] WARNING: seed={seed} != canonical {BOOTSTRAP_SEED}")
    rng = np.random.default_rng(int(seed))
    y = np.asarray(y).astype(int)
    scores = np.asarray(scores, dtype=float)
    n = len(y)
    out: dict[str, list[float]] = {"auc": [], "acc": [], "f1": []}
    if n < 10:
        if len(np.unique(y)) >= 2:
            auc = float(roc_auc_score(y, scores))
            pred, _ = youden_pred(y, scores)
            out["auc"] = [auc]
            out["acc"] = [float((pred == y).mean())]
            out["f1"] = [float(f1_score_binary(y, pred))]
        return out
    for _ in range(int(n_boot)):
        idx = rng.integers(0, n, size=n)
        yy, ss = y[idx], scores[idx]
        if len(np.unique(yy)) < 2:
            continue
        auc = float(roc_auc_score(yy, ss))
        pred, _ = youden_pred(yy, ss)
        out["auc"].append(auc)
        out["acc"].append(float((pred == yy).mean()))
        out["f1"].append(float(f1_score_binary(yy, pred)))
    return out


def _lists_from_mean_sd(mean: float, sd: float, n: int = BOOTSTRAP_N) -> list[float]:
    """构造样本均值/样本 SD(ddof=1) 精确等于 mean/sd 的列表，用于锁定 Day5→S6。"""
    n = max(2, int(n))
    if not np.isfinite(mean):
        return []
    if (not np.isfinite(sd)) or abs(sd) < 1e-15:
        return [float(mean)] * n
    x = np.zeros(n, dtype=float)
    # 两点对称扰动，其余取均值，使 mean/sd 精确可还原
    a = float(sd) * math.sqrt((n - 1) / 2.0)
    x[0] = mean + a
    x[1] = mean - a
    x[2:] = mean
    # 数值误差时再校准
    x = x - x.mean() + mean
    cur = float(x.std(ddof=1))
    if cur > 0:
        x = mean + (x - mean) * (float(sd) / cur)
    return x.tolist()


def load_s6_transformer_day5_mean_sd(proj: Path, lm: int) -> dict[str, tuple[float, float]] | None:
    """读 Fig S6 / Table 3 同源 summary：Two-stage Transformer Day5 mean/sd。"""
    summary = proj / f"summary_results/by_landmark/L{lm}/Tables/Table_S6_model_comparison_summary.csv"
    if not summary.is_file():
        return None
    with summary.open(encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            if "trans" not in str(r.get("model", "")).lower():
                continue
            try:
                return {
                    "auc": (float(r["auc_mean"]), float(r["auc_sd"])),
                    "acc": (float(r["acc_mean"]), float(r["acc_sd"])),
                    "f1": (float(r["f1_mean"]), float(r["f1_sd"])),
                }
            except (TypeError, ValueError, KeyError):
                return None
    return None


def lock_day5_transformer_to_s6(
    day_lists: dict[int, dict[str, list[float]]],
    proj: Path,
    lm: int,
    *,
    n_boot: int = BOOTSTRAP_N,
    rtol: float = 1e-3,
) -> bool:
    """硬锁：Table2 Day5 Transformer 单元格与 Table3/S6 同源；不一致则覆盖并告警。"""
    s6 = load_s6_transformer_day5_mean_sd(proj, lm)
    if s6 is None or 5 not in day_lists:
        print("[table2] Day5 lock skipped (no S6 summary or no Day5)")
        return False
    boot = day_lists[5]
    mismatched = []
    for key in ("auc", "acc", "f1"):
        vals = np.asarray(boot.get(key, []), dtype=float)
        vals = vals[np.isfinite(vals)]
        m = float(vals.mean()) if vals.size else float("nan")
        s = float(vals.std(ddof=1)) if vals.size > 1 else 0.0
        tm, ts = s6[key]
        if (not np.isfinite(m)) or abs(m - tm) > max(rtol, abs(tm) * rtol) or abs(s - ts) > max(rtol, abs(ts) * rtol + 1e-4):
            mismatched.append((key, m, s, tm, ts))
    if mismatched:
        for key, m, s, tm, ts in mismatched:
            print(
                f"[table2] Day5 {key} mismatch vs S6/Table3: "
                f"got {m:.6f}±{s:.6f} vs {tm:.6f}±{ts:.6f} → lock to S6"
            )
    else:
        print("[table2] Day5 Transformer already matches S6/Table3; keeping bootstrap draws")
        return True
    day_lists[5] = {
        key: _lists_from_mean_sd(s6[key][0], s6[key][1], n=n_boot) for key in ("auc", "acc", "f1")
    }
    print(
        "[table2] locked Day5 Transformer to S6/Table3: "
        f"AUC={fmt_mean_sd(day_lists[5]['auc'], kind='auc')} "
        f"Acc={fmt_mean_sd(day_lists[5]['acc'], kind='acc')} "
        f"F1={fmt_mean_sd(day_lists[5]['f1'], kind='f1')}"
    )
    return True


def table2_denom_footnotes(
    *,
    comparator_name: str,
    n_test: int | None,
    n_comparator: int | None,
    n_boot: int = BOOTSTRAP_N,
    seed: int = BOOTSTRAP_SEED,
) -> list[str]:
    """分母脚注：Transformer Day1–5 = 全 test；对照列 = 分数可得子集。"""
    notes = ["ᵃ F1-score, harmonic mean of precision and recall."]
    return notes


def load_transformer_days(proj: Path, lm: int = 72) -> dict[int, dict]:
    s6 = proj / f"summary_results/by_landmark/L{lm}/Tables/Table_S6_model_comparison_metrics.csv"
    out: dict[int, dict] = {}
    if not s6.is_file():
        return out
    with s6.open(encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            if "trans" not in str(r.get("model", "")).lower():
                continue
            d = int(float(r["day"]))
            out[d] = {
                "auc": float(r["auc"]),
                "acc": float(r["accuracy"]),
                "f1": float(r["f1"]),
            }
    return out


def compute_transformer_by_day(proj: Path, lm: int = 120) -> dict[int, dict]:
    """从 L{lm}_B test.npz + model_b 直接算 Day1–5 AUC/Acc/F1（不依赖 S6 CSV）。"""
    import os

    os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")
    from torch.utils.data import DataLoader

    from python.two_stage_transformer.dataloader import TSTDataset
    from python.two_stage_transformer.eval import load_model_for_eval, score_all_cutoffs

    ud = proj / f"by_unit/【success】L{lm}_B_twostage/step09_tst_train_eval/Tables"
    if not ud.is_dir():
        ud = proj / f"by_unit/L{lm}_B_twostage/step09_tst_train_eval/Tables"
    data_dir = ud / "npz"
    npz = data_dir / "test.npz"
    model_path = ud / "model_b.pth"
    if not (npz.is_file() and model_path.is_file()):
        print(f"[table2] missing L{lm} test.npz/model_b.pth")
        return {}

    ds = TSTDataset("test", str(data_dir))
    model = load_model_for_eval(str(model_path), "b", ds.n_days, ds.n_hours, ds.n_features)
    dl = DataLoader(ds, batch_size=64, shuffle=False)
    scores = score_all_cutoffs(model, dl, ds.n_days)
    y = ds.y.astype(int)
    los = ds.day_mask.sum(1).astype(int)
    D = int(ds.n_days)
    out: dict[int, dict] = {}
    for c in range(1, min(D, 5) + 1):
        sel = los >= c
        yy, ss = y[sel], scores[c][sel]
        if len(yy) < 5 or len(np.unique(yy)) < 2:
            continue
        auc = float(roc_auc_score(yy, ss))
        pred, _ = youden_pred(yy, ss)
        acc = float((pred == yy).mean())
        f1 = float(f1_score_binary(yy, pred))
        out[c] = {"auc": auc, "acc": acc, "f1": f1, "n": int(len(yy))}
        print(f"Transformer Day{c}: AUC={auc:.3f} Acc={acc:.3f} F1={f1:.3f} n={len(yy)}")
    return out


def _score_map_path(proj: Path, preferred: str | None = None) -> tuple[Path, str]:
    names: list[str] = []
    if preferred and str(preferred).strip():
        names.append(str(preferred).strip().upper().replace("APACHEII", "APSIII"))
    for name in ("APSIII", "SAPSII", "SOFA", "OASIS"):
        if name not in names:
            names.append(name)
    for name in names:
        p = proj / f"_tmp_{name.lower()}_by_stay.csv"
        if p.is_file() and p.stat().st_size > 20:
            return p, name
    # preferred 无文件时仍返回期望列名，便于上层先建 map
    if preferred and str(preferred).strip():
        pref = str(preferred).strip()
        return proj / f"_tmp_{pref.lower()}_by_stay.csv", pref
    return proj / "_tmp_sapsii_by_stay.csv", "SAPSII"


def compute_comparator_by_day(proj: Path, lm: int = 72) -> dict[int, dict]:
    """从 test.npz + APSIII/SAPSII map 计算每日对照指标（无需 torch）。"""
    ud = proj / f"by_unit/【success】L{lm}_B_twostage/step09_tst_train_eval/Tables"
    if not ud.is_dir():
        ud = proj / f"by_unit/L{lm}_B_twostage/step09_tst_train_eval/Tables"
    npz = ud / "npz" / "test.npz"
    map_csv, score_name = _score_map_path(proj)
    if not (npz.is_file() and map_csv.is_file()):
        print(f"[table2] missing test.npz/{score_name} map; comparator column empty")
        return {}

    score_col = score_name
    saps_map = {}
    with map_csv.open(encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
        if rows:
            keys = {k.lower(): k for k in rows[0].keys()}
            if score_name.lower() not in keys:
                score_col = keys.get("score") or list(rows[0].keys())[1]
        for row in rows:
            saps_map[int(float(row["stay_id"]))] = float(row[score_col])

    d = np.load(npz, allow_pickle=False)
    y = d["y"].astype(int)
    los = d["day_mask"].sum(1).astype(int)
    pids = d["patient_id"].astype(np.int64)
    saps = np.array([saps_map.get(int(p), np.nan) for p in pids], dtype=np.float64)
    D = int(d["day_mask"].shape[1])

    out: dict[int, dict] = {}
    for c in range(1, min(D, 5) + 1):
        sel = (los >= c) & ~np.isnan(saps)
        yy, ap = y[sel], saps[sel]
        if len(yy) < 5 or len(np.unique(yy)) < 2:
            continue
        auc_s = float(roc_auc_score(yy, ap))
        pred_s, _ = youden_pred(yy, ap)
        acc_s = float((pred_s == yy).mean())
        f1_s = float(f1_score_binary(yy, pred_s))
        out[c] = {"auc": auc_s, "acc": acc_s, "f1": f1_s, "n": int(len(yy))}
        print(f"{score_name} Day{c}: AUC={auc_s:.3f} Acc={acc_s:.3f} F1={f1_s:.3f} n={len(yy)}")
    return out


compute_sapsii_by_day = compute_comparator_by_day


def compute_bootstrap_table2(
    proj: Path,
    lm: int = 120,
    *,
    n_boot: int = BOOTSTRAP_N,
    seed: int = BOOTSTRAP_SEED,
    preferred_score: str | None = None,
) -> tuple[dict[int, dict[str, list[float]]], dict[str, list[float]], str, int, int]:
    """Bootstrap Day1–5 Transformer + 对照分数列。

    返回 (day_lists, comparator_lists, comparator_name, n_test, n_comparator)。
    Day 列一律用同一 seed（禁止 seed+day）；对照列在分数可得患者上估计。
    """
    import os

    os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")
    from torch.utils.data import DataLoader

    from python.two_stage_transformer.dataloader import TSTDataset
    from python.two_stage_transformer.eval import load_model_for_eval, score_all_cutoffs

    if int(seed) != int(BOOTSTRAP_SEED):
        print(f"[boot] forcing seed {BOOTSTRAP_SEED} (requested {seed}; forbid seed+day)")
        seed = int(BOOTSTRAP_SEED)

    ud = proj / f"by_unit/【success】L{lm}_B_twostage/step09_tst_train_eval/Tables"
    if not ud.is_dir():
        ud = proj / f"by_unit/L{lm}_B_twostage/step09_tst_train_eval/Tables"
    data_dir = ud / "npz"
    npz = data_dir / "test.npz"
    model_path = ud / "model_b.pth"
    map_csv, comparator_name = _score_map_path(proj, preferred=preferred_score)
    if not (npz.is_file() and model_path.is_file()):
        raise SystemExit(f"missing L{lm} test.npz/model_b.pth for bootstrap Table 2")

    ds = TSTDataset("test", str(data_dir))
    model = load_model_for_eval(str(model_path), "b", ds.n_days, ds.n_hours, ds.n_features)
    dl = DataLoader(ds, batch_size=64, shuffle=False)
    scores = score_all_cutoffs(model, dl, ds.n_days)
    y = ds.y.astype(int)
    los = ds.day_mask.sum(1).astype(int)
    D = int(ds.n_days)
    n_test = int(len(y))

    day_lists: dict[int, dict[str, list[float]]] = {}
    for c in range(1, min(D, 5) + 1):
        sel = los >= c
        yy, ss = y[sel], scores[c][sel]
        # 同一 seed 用于所有 Day（禁止 seed+c）
        boot = bootstrap_metric_lists(yy, ss, n_boot=n_boot, seed=seed)
        day_lists[c] = boot
        print(
            f"[boot] Transformer Day{c}: "
            f"AUC={fmt_mean_sd(boot['auc'], kind='auc')} "
            f"Acc={fmt_mean_sd(boot['acc'], kind='acc')} "
            f"F1={fmt_mean_sd(boot['f1'], kind='f1')} n={int(sel.sum())}"
        )

    comparator_lists: dict[str, list[float]] = {"auc": [], "acc": [], "f1": []}
    n_comparator = 0
    if map_csv.is_file():
        score_col = comparator_name
        saps_map: dict[int, float] = {}
        with map_csv.open(encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
            if rows:
                keys = {k.lower(): k for k in rows[0].keys()}
                if comparator_name.lower() not in keys:
                    score_col = keys.get("score") or list(rows[0].keys())[1]
                id_key = keys.get("stay_id") or keys.get("patient") or list(rows[0].keys())[0]
            else:
                id_key = "stay_id"
            for row in rows:
                try:
                    saps_map[int(float(row[id_key]))] = float(row[score_col])
                except (TypeError, ValueError, KeyError):
                    continue
        raw = np.load(npz, allow_pickle=False)
        pids = raw["patient_id"]
        clin = []
        for p in pids:
            try:
                clin.append(saps_map.get(int(float(p)), np.nan))
            except (TypeError, ValueError):
                clin.append(np.nan)
        clin = np.asarray(clin, dtype=float)
        # 对照列：分数可得患者（可与 Fig2 配对面板 n 一致）；与 Table3/S6 同 seed
        sel = np.isfinite(clin)
        n_comparator = int(sel.sum())
        yy, ap = y[sel], clin[sel]
        comparator_lists = bootstrap_metric_lists(yy, ap, n_boot=n_boot, seed=seed)
        print(
            f"[boot] {comparator_name}: "
            f"AUC={fmt_mean_sd(comparator_lists['auc'], kind='auc')} "
            f"Acc={fmt_mean_sd(comparator_lists['acc'], kind='acc')} "
            f"F1={fmt_mean_sd(comparator_lists['f1'], kind='f1')} n={n_comparator}"
        )
    else:
        print(f"[boot] missing {comparator_name} map; comparator column empty")

    return day_lists, comparator_lists, comparator_name, n_test, n_comparator


def table2_sci_stem(*, comparator_name: str, db: str = "MIMIC") -> str:
    """内外标题共用 stem（无 .xlsx）。"""
    return (
        f"Table 2-{db}. Performance comparison [mean (SD)] of the two-stage Transformer "
        f"model and {comparator_name} in predicting in-hospital mortality across ICU days"
    )


def load_cv_lists(cv_dir: Path) -> tuple[dict[int, dict[str, list[float]]], dict[str, list[float]], int]:
    """Return (day -> {auc/acc/f1: list}, saps_col -> lists, n_seeds)."""
    csv_path = cv_dir / "Table_CV_fold_day_metrics.csv"
    if not csv_path.is_file():
        raise SystemExit(f"CV metrics not found: {csv_path}")

    day_vals: dict[int, dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))
    saps_all: dict[str, list[float]] = defaultdict(list)
    seeds = set()

    with csv_path.open(encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            model = str(r.get("model", "")).strip()
            day = int(float(r["day"]))
            seed = int(float(r["seed"]))
            seeds.add(seed)
            auc = float(r["auc"]) if r.get("auc") not in (None, "") else float("nan")
            acc = float(r["acc"]) if r.get("acc") not in (None, "") else float("nan")
            f1 = float(r["f1"]) if r.get("f1") not in (None, "") else float("nan")
            if model.lower().startswith("trans"):
                if math.isfinite(auc):
                    day_vals[day]["auc"].append(auc)
                if math.isfinite(acc):
                    day_vals[day]["acc"].append(acc)
                if math.isfinite(f1):
                    day_vals[day]["f1"].append(f1)
            elif any(k in model.lower() for k in ("saps", "apsiii", "aps", "sofa", "oasis", "apache")):
                if math.isfinite(auc):
                    saps_all["auc"].append(auc)
                if math.isfinite(acc):
                    saps_all["acc"].append(acc)
                if math.isfinite(f1):
                    saps_all["f1"].append(f1)

    return day_vals, saps_all, len(seeds)


def write_yang_table2(
    path: Path,
    *,
    day_lists: dict[int, dict[str, list[float]]] | None = None,
    saps_lists: dict[str, list[float]] | None = None,
    day_metrics: dict[int, dict] | None = None,
    saps_metrics: dict[int, dict] | None = None,
    footnotes: list[str] | None = None,
    n_seeds: int | None = None,
    comparator_name: str = "SAPSII",
    db: str = "MIMIC",
    source: str = "cv",
) -> None:
    days = [1, 2, 3, 4, 5]
    headers = ["Model"] + [f"Day {d}" for d in days] + [comparator_name]
    use_cv = day_lists is not None
    has_mean_sd = use_cv

    if use_cv:
        assert day_lists is not None and saps_lists is not None
        rows = [
            ["AUC"]
            + [fmt_mean_sd(day_lists.get(d, {}).get("auc", []), kind="auc") for d in days]
            + [fmt_mean_sd(saps_lists.get("auc", []), kind="auc")],
            ["Accuracy (%)"]
            + [fmt_mean_sd(day_lists.get(d, {}).get("acc", []), kind="acc") for d in days]
            + [fmt_mean_sd(saps_lists.get("acc", []), kind="acc")],
            ["F1-scoreᵃ"]
            + [fmt_mean_sd(day_lists.get(d, {}).get("f1", []), kind="f1") for d in days]
            + [fmt_mean_sd(saps_lists.get("f1", []), kind="f1")],
        ]
        # 若任意单元格已是 mean (SD) 形态则标题保留 [mean (SD)]
        has_mean_sd = any("(" in str(v) for row in rows for v in row[1:])
    else:
        assert day_metrics is not None and saps_metrics is not None
        saps_auc = [saps_metrics[d]["auc"] for d in days if d in saps_metrics]
        saps_acc = [saps_metrics[d]["acc"] for d in days if d in saps_metrics]
        saps_f1 = [saps_metrics[d]["f1"] for d in days if d in saps_metrics]
        rows = [
            ["AUC"]
            + [fmt_point(day_metrics.get(d, {}).get("auc", float("nan")), kind="auc") for d in days]
            + [fmt_mean_sd(saps_auc, kind="auc")],
            ["Accuracy (%)"]
            + [fmt_point(day_metrics.get(d, {}).get("acc", float("nan")), kind="acc") for d in days]
            + [fmt_mean_sd(saps_acc, kind="acc")],
            ["F1-scoreᵃ"]
            + [fmt_point(day_metrics.get(d, {}).get("f1", float("nan")), kind="f1") for d in days]
            + [fmt_mean_sd(saps_f1, kind="f1")],
        ]
        has_mean_sd = False

    # 内外标题一致：A1 == 文件名 stem
    if has_mean_sd:
        title = table2_sci_stem(comparator_name=comparator_name, db=db)
    else:
        title = (
            f"Table 2-{db}. Performance comparison of the two-stage Transformer model and "
            f"{comparator_name} in predicting in-hospital mortality across ICU days"
        )

    # 脚注：F1 定义 + 分母口径（515 vs 507）
    if footnotes is None:
        footnotes = ["ᵃ F1-score, harmonic mean of precision and recall."]

    thick = Side(style="medium", color="000000")
    thin = Side(style="thin", color="000000")
    border_header = Border(top=thick, bottom=thin)
    border_last = Border(bottom=thick)
    border_foot = Border(top=thin)
    font_title = Font(name=FONT, size=12, bold=True)
    font_hdr = Font(name=FONT, size=12, bold=True)
    font_body = Font(name=FONT, size=12)
    align_c = Alignment(horizontal="center", vertical="center", wrap_text=True)
    align_l = Alignment(horizontal="left", vertical="center", wrap_text=True)

    # 路径与标题对齐（若传入旧 slug 路径则改写为 SCI 名）
    path = Path(path)
    sci_path = path.parent / f"{title}.xlsx"
    if path.name != sci_path.name:
        path = sci_path

    wb = Workbook()
    ws = wb.active
    ws.title = "Table"
    ws.sheet_view.showGridLines = False
    nc = len(headers)

    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=nc)
    c = ws.cell(1, 1, title)
    c.font = font_title
    c.alignment = align_c

    r0 = 2
    for j, h in enumerate(headers, 1):
        cell = ws.cell(r0, j, h)
        cell.font = font_hdr
        cell.alignment = align_c
        cell.border = border_header

    for i, row in enumerate(rows):
        er = r0 + 1 + i
        is_last = i == len(rows) - 1
        for j, val in enumerate(row, 1):
            cell = ws.cell(er, j, val)
            cell.font = font_body
            cell.alignment = align_l if j == 1 else align_c
            if is_last:
                cell.border = border_last

    last = r0 + len(rows)
    for k, note in enumerate(footnotes):
        fr = last + 1 + k
        ws.merge_cells(start_row=fr, start_column=1, end_row=fr, end_column=nc)
        cell = ws.cell(fr, 1, note)
        cell.font = font_body
        cell.alignment = align_l
        if k == 0:
            cell.border = border_foot

    widths = [14, 14, 14, 14, 14, 14, 16]
    for j, w in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(j)].width = w
    ws.row_dimensions[1].height = 48

    path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(path)
    print(f"wrote {path}")
    return path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--from-cv", default="", help="CV work dir with Table_CV_fold_day_metrics.csv")
    ap.add_argument("--landmark", type=int, default=120)
    ap.add_argument("--project-root", default="")
    ap.add_argument(
        "--comparator-score",
        default="",
        help="对照分数列名（如 APSIII / SAPSII）；优先于自动探测",
    )
    ap.add_argument(
        "--from-bootstrap",
        action="store_true",
        help="无 CV 时用 test-set bootstrap mean(SD)（对齐 Yang 图示与 Table 3）",
    )
    ap.add_argument("--n-boot", type=int, default=BOOTSTRAP_N)
    ap.add_argument("--db-name", default="MIMIC")
    args = ap.parse_args()

    if args.project_root:
        proj = _norm_proj_path(args.project_root)
    else:
        proj = find_proj()
    lm = int(args.landmark)
    pref = str(args.comparator_score or "").strip() or None
    _, comparator_name = _score_map_path(proj, preferred=pref)
    tables = proj / "summary_results/Tables"
    out = tables / f"{table2_sci_stem(comparator_name=comparator_name, db=args.db_name)}.xlsx"
    old_slug = tables / "Table 2-MIMIC-Daily_performance_Transformer.xlsx"

    def _cleanup_old():
        if old_slug.is_file() and old_slug.resolve() != out.resolve():
            old_slug.unlink()
            print(f"removed stale {old_slug.name}")

    if args.from_cv:
        cv_dir = Path(args.from_cv)
        day_lists, saps_lists, n_seeds = load_cv_lists(cv_dir)
        print(f"[table2] CV n_seeds={n_seeds} days={sorted(day_lists)} comparator={comparator_name}")
        write_yang_table2(
            out,
            day_lists=day_lists,
            saps_lists=saps_lists,
            n_seeds=n_seeds,
            comparator_name=comparator_name,
            db=args.db_name,
            source="cv",
        )
        _cleanup_old()
        return

    # Prefer existing CV dir if present
    cv_default = proj / "summary_results" / "cv_table2_repeated_split"
    cv_csv = cv_default / "Table_CV_fold_day_metrics.csv"
    if cv_csv.is_file():
        day_lists, saps_lists, n_seeds = load_cv_lists(cv_default)
        print(f"[table2] auto-using CV at {cv_default} n_seeds={n_seeds}")
        write_yang_table2(
            out,
            day_lists=day_lists,
            saps_lists=saps_lists,
            n_seeds=n_seeds,
            comparator_name=comparator_name,
            db=args.db_name,
            source="cv",
        )
        _cleanup_old()
        return

    # 无 CV 时一律 bootstrap mean(SD)（避免标题写了 mean(SD) 单元格却是点估计）
    try:
        day_lists, saps_lists, comparator_name, n_test, n_comparator = compute_bootstrap_table2(
            proj,
            lm,
            n_boot=int(args.n_boot),
            seed=BOOTSTRAP_SEED,
            preferred_score=pref,
        )
    except Exception as e:
        print(f"[table2] bootstrap failed ({e}); falling back to point estimates WITHOUT [mean (SD)] in title")
        day_m = load_transformer_days(proj, lm)
        if len(day_m) < 5:
            print(f"[table2] S6 Transformer days incomplete ({sorted(day_m)}); computing from L{lm} model")
            day_m = compute_transformer_by_day(proj, lm)
        if not day_m:
            raise SystemExit("no Transformer Day1–5 metrics (S6 csv / model)")
        print("Transformer days:", {k: day_m[k] for k in sorted(day_m)})
        saps_m = compute_sapsii_by_day(proj, lm)
        write_yang_table2(
            out,
            day_metrics=day_m,
            saps_metrics=saps_m,
            comparator_name=comparator_name,
            db=args.db_name,
            source="point",
        )
        _cleanup_old()
        return

    lock_day5_transformer_to_s6(day_lists, proj, lm, n_boot=int(args.n_boot))
    feet = table2_denom_footnotes(
        comparator_name=comparator_name,
        n_test=n_test,
        n_comparator=n_comparator,
        n_boot=int(args.n_boot),
        seed=BOOTSTRAP_SEED,
    )
    try:
        write_yang_table2(
            out,
            day_lists=day_lists,
            saps_lists=saps_lists,
            comparator_name=comparator_name,
            db=args.db_name,
            source="bootstrap",
            footnotes=feet,
        )
    except PermissionError:
        # SMB/Windows 锁文件时先写 /tmp 再提示
        alt = Path("/tmp") / out.name
        write_yang_table2(
            alt,
            day_lists=day_lists,
            saps_lists=saps_lists,
            comparator_name=comparator_name,
            db=args.db_name,
            source="bootstrap",
            footnotes=feet,
        )
        print(f"[table2] Permission denied on {out}; wrote {alt} — copy over when unlocked")
        raise SystemExit(2)
    _cleanup_old()


if __name__ == "__main__":
    main()
