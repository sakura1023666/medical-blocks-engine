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

REPO = Path(r"E:/01block/01Block-new-Final")
if not REPO.exists():
    REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO))

PROJ_CANDS = [
    Path(r"G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
    Path("/mnt/g/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
]
FONT = "Times New Roman"


def find_proj() -> Path:
    for p in PROJ_CANDS:
        if p.exists():
            return p
    raise SystemExit("project root not found")


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
    tpr = tps / P
    fpr = fps / N
    thr = y_score
    return fpr, tpr, thr


def auc_trapz(fpr, tpr):
    fpr = np.concatenate([[0.0], fpr, [1.0]])
    tpr = np.concatenate([[0.0], tpr, [1.0]])
    order = np.argsort(fpr)
    fpr, tpr = fpr[order], tpr[order]
    return float(np.trapezoid(tpr, fpr)) if hasattr(np, "trapezoid") else float(np.trapz(tpr, fpr))


def roc_auc_score(y_true, y_score):
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


def fmt_point(x: float, *, pct: bool = False, kind: str = "auc") -> str:
    if x != x:
        return "—"
    if pct or kind == "acc":
        return f"{100.0 * x:.2f}"
    if kind == "f1":
        return f"{x:.3f}"
    return f"{x:.2f}"


def fmt_mean_sd(vals: list[float], *, pct: bool = False, kind: str = "auc") -> str:
    a = np.asarray(vals, dtype=float)
    a = a[np.isfinite(a)]
    if a.size == 0:
        return "—"
    if a.size == 1:
        return fmt_point(float(a[0]), pct=pct, kind=kind)
    m, s = float(a.mean()), float(a.std(ddof=1))
    if pct or kind == "acc":
        return f"{100.0 * m:.2f} ({100.0 * s:.2f})"
    if kind == "f1":
        return f"{m:.3f} ({s:.3f})"
    return f"{m:.2f} ({s:.3f})"


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


def compute_sapsii_by_day(proj: Path, lm: int = 72) -> dict[int, dict]:
    """从 test.npz + SAPSII map 计算每日对照指标（无需 torch）。"""
    ud = proj / f"by_unit/【success】L{lm}_B_twostage/step09_tst_train_eval/Tables"
    npz = ud / "npz" / "test.npz"
    map_csv = proj / "_tmp_sapsii_by_stay.csv"
    if not (npz.is_file() and map_csv.is_file()):
        print("[table2] missing test.npz/SAPSII map; SAPSII column empty")
        return {}

    saps_map = {}
    with map_csv.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            saps_map[int(float(row["stay_id"]))] = float(row["SAPSII"])

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
        print(f"SAPSII Day{c}: AUC={auc_s:.3f} Acc={acc_s:.3f} F1={f1_s:.3f} n={len(yy)}")
    return out


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
            elif "saps" in model.lower():
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
) -> None:
    days = [1, 2, 3, 4, 5]
    headers = ["Model"] + [f"Day {d}" for d in days] + ["SAPSII"]
    use_cv = day_lists is not None

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

    # 原文 Table 2 仅有一条脚注（F1 定义）
    title = (
        "Table 2. Performance comparison [mean (SD)] of the two-stage Transformer model and SAPSII "
        "in predicting in-hospital mortality across ICU days."
    )
    footnotes = footnotes or ["ᵃ F1-score, harmonic mean of precision and recall."]

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

    widths = [14, 12, 12, 12, 12, 12, 16]
    for j, w in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(j)].width = w
    ws.row_dimensions[1].height = 36

    path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(path)
    print(f"wrote {path}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--from-cv", default="", help="CV work dir with Table_CV_fold_day_metrics.csv")
    ap.add_argument("--landmark", type=int, default=72)
    args = ap.parse_args()

    proj = find_proj()
    lm = int(args.landmark)
    out = proj / "summary_results/Tables/Table 2-MIMIC-Daily_performance_Transformer.xlsx"

    if args.from_cv:
        cv_dir = Path(args.from_cv)
        day_lists, saps_lists, n_seeds = load_cv_lists(cv_dir)
        print(f"[table2] CV n_seeds={n_seeds} days={sorted(day_lists)}")
        write_yang_table2(out, day_lists=day_lists, saps_lists=saps_lists, n_seeds=n_seeds)
        return

    # Prefer existing CV dir if present
    cv_default = proj / "summary_results" / "cv_table2_repeated_split"
    cv_csv = cv_default / "Table_CV_fold_day_metrics.csv"
    if cv_csv.is_file():
        day_lists, saps_lists, n_seeds = load_cv_lists(cv_default)
        print(f"[table2] auto-using CV at {cv_default} n_seeds={n_seeds}")
        write_yang_table2(out, day_lists=day_lists, saps_lists=saps_lists, n_seeds=n_seeds)
        return

    day_m = load_transformer_days(proj, lm)
    if not day_m:
        raise SystemExit("no Transformer Day1–5 metrics from S6 csv")
    print("Transformer days:", {k: day_m[k] for k in sorted(day_m)})
    saps_m = compute_sapsii_by_day(proj, lm)
    write_yang_table2(out, day_metrics=day_m, saps_metrics=saps_m)


if __name__ == "__main__":
    main()
