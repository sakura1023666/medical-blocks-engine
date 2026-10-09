#!/usr/bin/env python3
"""Figure 3: Two-stage Transformer vs clinical severity score (Yang layout).

原文对照 APACHE II；卒中课题迁移为 SAPSII；AKI/eICU 默认 APSIII。
路径 / 分数名 / landmark 用 CLI 参数（优先）或环境变量；勿写死卒中工程路径。
WSL→Windows python.exe 时 env 常丢失，调用方必须传 CLI。
"""
from __future__ import annotations

import argparse
import csv
import os
import sys
from pathlib import Path

os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

import matplotlib

matplotlib.use("Agg")
import matplotlib.colors as mcolors
import numpy as np
from matplotlib import pyplot as plt
from sklearn.metrics import roc_auc_score, roc_curve
from torch.utils.data import DataLoader


def _to_path(p: str | Path) -> Path:
    s = str(p)
    if s.startswith("/mnt/") and len(s) > 7 and s[6] == "/":
        # /mnt/g/foo -> G:/foo
        return Path(f"{s[5].upper()}:/{s[7:]}".replace("\\", "/"))
    return Path(s)


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Redraw Yang Fig3 vs clinical severity score")
    p.add_argument("--project-root", default=os.environ.get("TST_FIG3_PROJ", ""))
    p.add_argument("--landmark", type=int, default=int(os.environ.get("TST_FIG3_LANDMARK", "72") or "72"))
    p.add_argument("--score-name", default=os.environ.get("TST_FIG3_SCORE_NAME", "SAPSII"))
    p.add_argument("--score-map", default=os.environ.get("TST_FIG3_SCORE_MAP", ""))
    p.add_argument("--out", default=os.environ.get("TST_FIG3_OUT", ""))
    p.add_argument(
        "--repo",
        default=os.environ.get("MEDICAL_BLOCKS_ROOT", r"E:/01block/01Block-new-Final"),
    )
    return p.parse_args()


ARGS = _parse_args()
REPO = _to_path(ARGS.repo)
if not REPO.exists():
    REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO))

from python.two_stage_transformer.dataloader import TSTDataset
from python.two_stage_transformer.eval import load_model_for_eval, score_all_cutoffs

_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))
from pub_pvalue_stars import STAR_FOOTNOTE, pub_pvalue_stars  # noqa: E402

_DEFAULT_STROKE = r"G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421"
PROJ = _to_path(ARGS.project_root or _DEFAULT_STROKE)
_LM = int(ARGS.landmark)
SCORE_NAME = str(ARGS.score_name or "SAPSII").strip() or "SAPSII"
MAP = _to_path(ARGS.score_map or str(PROJ / f"_tmp_{SCORE_NAME.lower()}_by_stay.csv"))
UD = PROJ / f"by_unit/【success】L{_LM}_B_twostage/step09_tst_train_eval/Tables"
if not UD.exists():
    UD = PROJ / f"by_unit/L{_LM}_B_twostage/step09_tst_train_eval/Tables"
DATA = UD / "npz"
MODEL = UD / "model_b.pth"
OUT = _to_path(
    ARGS.out
    or str(PROJ / "summary_results/Figures/Figure 2-MIMIC-ROC_confusion_model_comparison.pdf")
)


def youden_pred(y, scores):
    fpr, tpr, thr = roc_curve(y, scores)
    opt = float(thr[np.argmax(tpr - fpr)]) if len(thr) else 0.5
    return (scores > opt).astype(int), opt


def _compute_midrank(x: np.ndarray) -> np.ndarray:
    """Midranks for DeLong (Sun & Xu)."""
    J = np.argsort(x)
    Z = x[J]
    N = x.size
    T = np.zeros(N, dtype=float)
    i = 0
    while i < N:
        j = i
        while j < N and Z[j] == Z[i]:
            j += 1
        T[i:j] = 0.5 * (i + j - 1) + 1
        i = j
    out = np.empty(N, dtype=float)
    out[J] = T
    return out


def delong_pvalue(y_true: np.ndarray, pred_a: np.ndarray, pred_b: np.ndarray) -> float:
    """Two-sided DeLong test P for paired AUCs (pred_a vs pred_b)."""
    y = np.asarray(y_true).astype(int)
    a = np.asarray(pred_a, dtype=float)
    b = np.asarray(pred_b, dtype=float)
    pos = y == 1
    neg = ~pos
    m = int(pos.sum())
    n = int(neg.sum())
    if m < 2 or n < 2:
        return float("nan")
    # structural components
    tx = _compute_midrank(a[pos])
    ty = _compute_midrank(a[neg])
    tz = _compute_midrank(a)
    auc_a = (tz[pos].sum() - m * (m + 1) / 2.0) / (m * n)

    txb = _compute_midrank(b[pos])
    tyb = _compute_midrank(b[neg])
    tzb = _compute_midrank(b)
    auc_b = (tzb[pos].sum() - m * (m + 1) / 2.0) / (m * n)

    v10_a = (tx - 1) / n
    v01_a = 1.0 - (ty - 1) / m
    v10_b = (txb - 1) / n
    v01_b = 1.0 - (tyb - 1) / m

    s10 = np.cov(np.vstack([v10_a, v10_b]))
    s01 = np.cov(np.vstack([v01_a, v01_b]))
    s = s10 / m + s01 / n
    diff = auc_a - auc_b
    var = float(s[0, 0] + s[1, 1] - 2.0 * s[0, 1])
    if var <= 0 or var != var:
        return float("nan")
    z = diff / np.sqrt(var)
    # two-sided normal
    from math import erfc

    return float(erfc(abs(z) / np.sqrt(2.0)))


def mcnemar_pvalue(y_true: np.ndarray, pred_a: np.ndarray, pred_b: np.ndarray) -> float:
    """Exact McNemar P comparing paired binary predictions vs truth."""
    y = np.asarray(y_true).astype(int)
    pa = np.asarray(pred_a).astype(int)
    pb = np.asarray(pred_b).astype(int)
    a_ok = pa == y
    b_ok = pb == y
    n01 = int((~a_ok & b_ok).sum())  # A wrong, B right
    n10 = int((a_ok & ~b_ok).sum())  # A right, B wrong
    n_disc = n01 + n10
    if n_disc == 0:
        return 1.0
    # exact binomial two-sided
    from math import comb

    k = min(n01, n10)
    # P = 2 * sum_{i=0..k} C(n,i) / 2^n , capped at 1
    cdf = sum(comb(n_disc, i) for i in range(k + 1)) / (2.0**n_disc)
    return float(min(1.0, 2.0 * cdf))


def bootstrap_metric_mean_sd(
    y: np.ndarray,
    score_tf: np.ndarray,
    score_ap: np.ndarray,
    *,
    n_boot: int = 400,
    seed: int = 42,
) -> dict[str, float]:
    """Patient-level bootstrap mean/SD of AUC and Accuracy (Youden)."""
    rng = np.random.default_rng(seed)
    y = np.asarray(y).astype(int)
    n = len(y)
    auc_tf, auc_ap, acc_tf, acc_ap = [], [], [], []
    for _ in range(n_boot):
        idx = rng.integers(0, n, size=n)
        yy = y[idx]
        if len(np.unique(yy)) < 2:
            continue
        st, sa = score_tf[idx], score_ap[idx]
        try:
            auc_tf.append(float(roc_auc_score(yy, st)))
            auc_ap.append(float(roc_auc_score(yy, sa)))
        except Exception:
            continue
        pt, _ = youden_pred(yy, st)
        ps, _ = youden_pred(yy, sa)
        acc_tf.append(float((pt == yy).mean()))
        acc_ap.append(float((ps == yy).mean()))

    def _ms(xs):
        a = np.asarray(xs, dtype=float)
        if a.size == 0:
            return float("nan"), float("nan")
        return float(a.mean()), float(a.std(ddof=1)) if a.size > 1 else 0.0

    m_auc_tf, s_auc_tf = _ms(auc_tf)
    m_auc_ap, s_auc_ap = _ms(auc_ap)
    m_acc_tf, s_acc_tf = _ms(acc_tf)
    m_acc_ap, s_acc_ap = _ms(acc_ap)
    return {
        "mean_auc_tf": m_auc_tf,
        "sd_auc_tf": s_auc_tf,
        "mean_auc_ap": m_auc_ap,
        "sd_auc_ap": s_auc_ap,
        "mean_acc_tf": m_acc_tf,
        "sd_acc_tf": s_acc_tf,
        "mean_acc_ap": m_acc_ap,
        "sd_acc_ap": s_acc_ap,
        "n_boot_ok": float(len(auc_tf)),
    }


def _load_score_map(path: Path) -> dict[int, float]:
    """CSV: stay_id + score column (SAPSII / APSIII / score / …)."""
    out: dict[int, float] = {}
    with path.open(encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        return out
    keys = {k.lower(): k for k in rows[0].keys()}
    id_key = keys.get("stay_id") or keys.get("patient") or keys.get("tst_patient_id") or list(rows[0].keys())[0]
    score_key = None
    for cand in (SCORE_NAME, "score", "SAPSII", "APSIII", "SOFA", "OASIS", "APACHE"):
        if cand.lower() in keys:
            score_key = keys[cand.lower()]
            break
    if score_key is None:
        # second column
        cols = list(rows[0].keys())
        score_key = cols[1] if len(cols) > 1 else cols[0]
    for row in rows:
        try:
            sid = int(float(row[id_key]))
            val = float(row[score_key])
        except (TypeError, ValueError, KeyError):
            continue
        if val == val:
            out[sid] = val
    return out


def main():
    if not MAP.exists():
        raise SystemExit(f"score map missing: {MAP}")
    if not MODEL.exists():
        raise SystemExit(f"model missing: {MODEL}")
    if not DATA.exists():
        raise SystemExit(f"npz dir missing: {DATA}")

    score_map = _load_score_map(MAP)
    ds = TSTDataset("test", str(DATA))
    D, H, F = ds.n_days, ds.n_hours, ds.n_features
    pids = np.load(DATA / "test.npz", allow_pickle=False)["patient_id"]
    # patient_id may be str or int
    def _pid_int(p):
        try:
            return int(float(p))
        except Exception:
            return None

    scores_arr = []
    for p in pids:
        pi = _pid_int(p)
        scores_arr.append(score_map.get(pi, np.nan) if pi is not None else np.nan)
    clin = np.asarray(scores_arr, dtype=np.float64)
    print(
        f"[fig3] proj={PROJ} lm=L{_LM} D={D} F={F} score={SCORE_NAME} "
        f"test_n={len(ds)} score_miss={int(np.isnan(clin).sum())} map_n={len(score_map)}"
    )

    dl = DataLoader(ds, batch_size=64, shuffle=False)
    model = load_model_for_eval(str(MODEL), "b", D, H, F)
    scores = score_all_cutoffs(model, dl, D)
    y = ds.y
    los = ds.day_mask.sum(1).astype(int)

    days = []
    n_plot = min(5, int(D))
    n_test = int(len(y))
    n_score_miss = int(np.isnan(clin).sum())
    for c in range(1, n_plot + 1):
        # 配对比较：仅 APSIII 可得者（避免 CM 合计与 test n=515 对不上）
        sel = (los >= c) & ~np.isnan(clin)
        if int(sel.sum()) < 5:
            print(f"Day{c}: skip (n={int(sel.sum())})")
            continue
        yy, ss, ap = y[sel], scores[c][sel], clin[sel]
        fpr, tpr, _ = roc_curve(yy, ss)
        auc_m = float(roc_auc_score(yy, ss))
        pred, _ = youden_pred(yy, ss)
        tn = int(((yy == 0) & (pred == 0)).sum())
        fp = int(((yy == 0) & (pred == 1)).sum())
        fn = int(((yy == 1) & (pred == 0)).sum())
        tp = int(((yy == 1) & (pred == 1)).sum())
        acc_m = float((tn + tp) / len(yy))
        sfpr, stpr, _ = roc_curve(yy, ap)
        auc_s = float(roc_auc_score(yy, ap))
        pred_s, _ = youden_pred(yy, ap)
        acc_s = float((pred_s == yy).mean())
        days.append(
            dict(
                day=c,
                n=int(sel.sum()),
                auc=auc_m,
                acc=acc_m,
                tn=tn,
                fp=fp,
                fn=fn,
                tp=tp,
                fpr=fpr,
                tpr=tpr,
                saps_auc=auc_s,
                saps_acc=acc_s,
                saps_fpr=sfpr,
                saps_tpr=stpr,
            )
        )
        print(
            f"Day{c}: AUC {auc_m:.3f} (label {auc_m:.2f}) vs {auc_s:.3f} | "
            f"Acc {acc_m:.3f} vs {acc_s:.3f} | n_pair={len(yy)} "
            f"(test={n_test}, APSIII_miss={n_score_miss})"
        )

    if len(days) < 1:
        raise SystemExit("no day panels could be built (check score map / LOS)")

    try:
        from scipy.stats import mannwhitneyu

        p_auc = mannwhitneyu([d["auc"] for d in days], [d["saps_auc"] for d in days]).pvalue
        p_acc = mannwhitneyu([d["acc"] for d in days], [d["saps_acc"] for d in days]).pvalue
    except Exception:
        p_auc = p_acc = float("nan")

    def p_lab(p):
        """Star notation: * P<0.05, ** P<0.01, *** P<0.001（禁止图上写 P=0.xxx）。"""
        return pub_pvalue_stars(p, show_ns=False)

    day_colors = ["#00BCD4", "#FF7043", "#E91E63", "#8BC34A", "#F9A825"]
    fig = plt.figure(figsize=(12.5, 8.8), dpi=160)
    gs = fig.add_gridspec(4, 3, height_ratios=[1.15, 0.95, 1.15, 0.95], hspace=0.42, wspace=0.32)

    def add_roc(ax, d, color):
        # 三位小数，避免 0.795→0.80 / 旧图 0.79 口径争议
        ax.plot(d["fpr"], d["tpr"], color=color, lw=2.0, ls=":", label=f"ROC curve (area = {d['auc']:.3f})")
        ax.plot(
            d["saps_fpr"],
            d["saps_tpr"],
            color="#9E9E9E",
            lw=1.6,
            ls=":",
            label=f"{SCORE_NAME} ROC curve (area = {d['saps_auc']:.3f})",
        )
        ax.plot([0, 1], [0, 1], "k--", lw=0.9)
        ax.set_xlim(0, 1)
        ax.set_ylim(0, 1.02)
        ax.set_xlabel("False Positive Rate", fontsize=8)
        ax.set_ylabel("True Positive Rate", fontsize=8)
        ax.set_title(f"Day-{d['day']} (n={d['n']})", fontsize=11, pad=4)
        ax.legend(loc="lower right", fontsize=6.2, frameon=True)
        ax.tick_params(labelsize=7)

    def add_cm(ax, d):
        cm = np.array([[d["tn"], d["fp"]], [d["fn"], d["tp"]]], dtype=float)
        base = mcolors.to_rgb(day_colors[d["day"] - 1])
        cmap = mcolors.LinearSegmentedColormap.from_list(f"cm{d['day']}", [(1, 1, 1), base])
        ax.imshow(cm, cmap=cmap, vmin=0, vmax=max(cm.max(), 1))
        for i in range(2):
            for j in range(2):
                ax.text(j, i, f"{int(cm[i, j])}", ha="center", va="center", fontsize=11)
        ax.set_xticks([0, 1])
        ax.set_yticks([0, 1])
        ax.set_xticklabels(["0", "1"], fontsize=8)
        ax.set_yticklabels(["0", "1"], fontsize=8)
        ax.set_xlabel("Predicted", fontsize=8)
        ax.set_ylabel("True", fontsize=8)
        ax.set_title(f"Day-{d['day']} (n={d['n']})", fontsize=10, pad=3)

    # Fill up to 5 day slots; missing days leave empty axes blank
    panels = {d["day"]: d for d in days}
    for i, day_i in enumerate([1, 2, 3]):
        ax_r = fig.add_subplot(gs[0, i])
        ax_c = fig.add_subplot(gs[1, i])
        if day_i in panels:
            add_roc(ax_r, panels[day_i], day_colors[day_i - 1])
            add_cm(ax_c, panels[day_i])
        else:
            ax_r.axis("off")
            ax_c.axis("off")
    for i, day_i in enumerate([4, 5]):
        ax_r = fig.add_subplot(gs[2, i])
        ax_c = fig.add_subplot(gs[3, i])
        if day_i in panels:
            add_roc(ax_r, panels[day_i], day_colors[day_i - 1])
            add_cm(ax_c, panels[day_i])
        else:
            ax_r.axis("off")
            ax_c.axis("off")

    axb = fig.add_subplot(gs[2:4, 2])
    aucs = np.array([d["auc"] for d in days])
    accs = np.array([d["acc"] for d in days])
    sa = np.array([d["saps_auc"] for d in days])
    sc = np.array([d["saps_acc"] for d in days])
    mean_auc, sd_auc = float(aucs.mean()), float(aucs.std(ddof=1) if len(aucs) > 1 else 0.0)
    mean_acc, sd_acc = float(accs.mean()), float(accs.std(ddof=1) if len(accs) > 1 else 0.0)
    mean_sa, sd_sa = float(sa.mean()), float(sa.std(ddof=1) if len(sa) > 1 else 0.0)
    mean_sc, sd_sc = float(sc.mean()), float(sc.std(ddof=1) if len(sc) > 1 else 0.0)
    x = np.arange(2)
    w = 0.35
    axb.bar(
        x - w / 2,
        [mean_auc, mean_acc],
        w,
        yerr=[sd_auc, sd_acc],
        capsize=4,
        color="white",
        edgecolor="black",
        hatch="///",
        label="Two-stage Transformer",
        error_kw={"ecolor": "black", "lw": 1},
    )
    axb.bar(
        x + w / 2,
        [mean_sa, mean_sc],
        w,
        yerr=[sd_sa, sd_sc],
        capsize=4,
        color="#BDBDBD",
        edgecolor="black",
        label=SCORE_NAME,
        error_kw={"ecolor": "black", "lw": 1},
    )
    top = max(mean_auc + sd_auc, mean_acc + sd_acc, mean_sa + sd_sa, mean_sc + sd_sc) + 0.06
    for i, pl in enumerate([p_lab(p_auc), p_lab(p_acc)]):
        if pl:
            axb.text(
                i,
                min(top, 1.02),
                pl,
                ha="center",
                va="bottom",
                fontsize=14,
                fontweight="bold",
                color="#c62828",
            )
    axb.set_ylim(0, max(1.08, top + 0.08))
    axb.set_xticks(x)
    axb.set_xticklabels(["AUC", "Accuracy"], fontsize=9)
    axb.set_ylabel("Mean ± SD", fontsize=9)
    axb.set_title("Comparison of Models", fontsize=11)
    axb.legend(loc="upper right", fontsize=7)
    axb.tick_params(labelsize=8)
    n_pair = int(days[0]["n"]) if days else 0
    axb.text(
        0.5,
        -0.12,
        (
            f"Test set n={n_test}; panels use n={n_pair} with available {SCORE_NAME} "
            f"({n_score_miss} missing). "
            f"Mann–Whitney U on Day-1–5 metrics; {STAR_FOOTNOTE}"
        ),
        transform=axb.transAxes,
        ha="center",
        va="top",
        fontsize=6.2,
    )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT, format="pdf", bbox_inches="tight")
    plt.close(fig)
    # provenance CSV next to figure / L120 tables
    pcsv = OUT.parent.parent / "by_landmark" / f"L{_LM}" / "Tables" / "Table_Fig2_comparison_pvalues.csv"
    if not (OUT.parent.parent / "by_landmark").exists():
        pcsv = PROJ / "summary_results" / "by_landmark" / f"L{_LM}" / "Tables" / "Table_Fig2_comparison_pvalues.csv"
    pcsv.parent.mkdir(parents=True, exist_ok=True)
    with pcsv.open("w", encoding="utf-8", newline="") as f:
        wri = csv.DictWriter(
            f, fieldnames=["metric", "pvalue", "star", "test", "note"]
        )
        wri.writeheader()
        for metric, p in (("auc", p_auc), ("acc", p_acc)):
            wri.writerow(
                {
                    "metric": metric,
                    "pvalue": "" if p != p else f"{p:.6g}",
                    "star": p_lab(p),
                    "test": "MannWhitney_Day1to5_summary",
                    "note": "Stars on Fig2 bar: * P<0.05, ** P<0.01, *** P<0.001",
                }
            )
    print("wrote", OUT)
    print("wrote", pcsv)
    print(f"Transformer {mean_auc:.3f}±{sd_auc:.3f} / {mean_acc:.3f}±{sd_acc:.3f}")
    print(f"{SCORE_NAME:12s} {mean_sa:.3f}±{sd_sa:.3f} / {mean_sc:.3f}±{sd_sc:.3f}")
    print(f"MWU p_auc={p_auc} ({p_lab(p_auc)}) p_acc={p_acc} ({p_lab(p_acc)})")


if __name__ == "__main__":
    main()
