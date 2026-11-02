#!/usr/bin/env python3
"""Rebuild Wang 2025 npj Digit Med–aligned publication figures for SA-AKI TCF.

Roles: Fig1–6 + Fig S1–S7 (SKIP Fig7). Writes PDFs under summary_results/Figures/pdf/,
custom image_information/*.md, then R pub_figure_ensure_formats (PDF-only by default).

Usage (engine canonical):
  python3 python/ml_tcf/pub/rebuild_wang2025_figures.py --success-root PATH
  Rscript run/ml_tcf_sepsis_aki/rebuild_wang2025_figures.R --success-root PATH

Writes PDF + image_information; default delivery is PDF-only
(config$pub_figures$export_png/tiff = FALSE).
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import warnings
from pathlib import Path

import joblib
import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
from sklearn.calibration import calibration_curve
from sklearn.metrics import (
    accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
    roc_curve,
)

warnings.filterwarnings("ignore", category=UserWarning)
warnings.filterwarnings("ignore", category=FutureWarning)

# ---------------------------------------------------------------------------
# Paths / constants
# ---------------------------------------------------------------------------
_HERE = Path(__file__).resolve().parent
_ENGINE_CANDIDATES = [
    Path(os.environ.get("MEDICAL_BLOCKS_ROOT", "")),
    _HERE.parents[3],  # python/ml_tcf/pub → repo root
    Path("/mnt/e/01block/01Block-new-Final"),
    Path("E:/01block/01Block-new-Final"),
]
ENGINE_ROOT = next((p for p in _ENGINE_CANDIDATES if p and (p / "R/pub_figure_export.R").exists()), _HERE.parents[3])
sys.path.insert(0, str(ENGINE_ROOT / "python"))
from ml_tcf.pub.bootstrap import (  # noqa: E402
    BOOT_SEED,
    N_BOOT,
    SEED_OFF_C1,
    SEED_OFF_C2,
    SEED_OFF_INTERNAL,
    SEED_OFF_TRAIN,
)

DEFAULT_SUCCESS = Path(
    "/mnt/g/02block_result/42_AKI_spesis/multi-algorithm fusion_40295871"
    "/by_index/【success】ALLVARS"
)
SHAP_SUBSAMPLE = 500
SHAP_SEED = 42
MODEL_ORDER = ["DT", "RF", "SVM", "NB", "GBDT", "XGB", "LGBM", "TCF"]
TREE_CANDIDATES = ["GBDT", "RF", "LGBM"]  # pick best by internal AUC for SHAP

# Publication palette (colorblind-friendly)
MODEL_COLORS = {
    "DT": "#7f7f7f",
    "RF": "#1f77b4",
    "SVM": "#ff7f0e",
    "NB": "#2ca02c",
    "GBDT": "#d62728",
    "XGB": "#9467bd",
    "LGBM": "#8c564b",
    "TCF": "#000000",
}

DISPLAY_MAP = {
    "Heart_Failure": "Heart failure",
    "Myocardial_Infarction": "Myocardial infarction",
    "Liver_cirrhosis": "Liver cirrhosis",
    "CalciumTotal": "Total calcium",
    "FreeCalcium": "Free calcium",
    "AnionGap": "Anion gap",
    "Hyperlipidemia": "Hyperlipidemia",
    "SpO2": "SpO2",
    "RDW": "RDW",
    "GCS": "GCS",
    "WBC": "WBC",
    "RBC": "RBC",
    "AST": "AST",
    "ALT": "ALT",
    "RR": "Respiratory rate",
    "PP": "Pulse pressure",
    "SI": "Shock index",
    "PAR": "PAR",
    "COPD": "COPD",
    "HR": "Heart rate",
    "CRP": "CRP",
}


def display_label(name: str) -> str:
    if name in DISPLAY_MAP:
        return DISPLAY_MAP[name]
    return str(name).replace("_", " ")


def fmt_auc(v) -> str:
    """Publication AUC string from metrics CSV float (3 decimals)."""
    return f"{float(v):.3f}"


def setup_mpl():
    mpl.rcParams.update(
        {
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
            "font.size": 9,
            "axes.titlesize": 11,
            "axes.labelsize": 10,
            "legend.fontsize": 8,
            "figure.dpi": 150,
            "savefig.dpi": 300,
            "axes.spines.top": False,
            "axes.spines.right": False,
        }
    )


def patch_numpy_joblib():
    """Allow loading RF/etc. pickled under a different numpy / BitGenerator API.

    Models were often pickled on Windows Anaconda (numpy 2.x layout ``numpy._core``)
    while this host may run numpy 1.26 (``numpy.core``). Also remaps MT19937
    BitGenerator ctor failures seen with GBDT/RF pickles.
    """
    import types

    try:
        import numpy as _np

        # numpy 2 pickle → numpy 1.26: expose numpy._core.* aliases
        if "numpy._core" not in sys.modules:
            try:
                import numpy._core  # noqa: F401
            except Exception:
                core_pkg = types.ModuleType("numpy._core")
                sys.modules["numpy._core"] = core_pkg
                try:
                    _np._core = core_pkg
                except Exception:
                    pass
        for sub in ("numeric", "multiarray", "umath", "_multiarray_umath"):
            modname = f"numpy._core.{sub}"
            if modname in sys.modules:
                continue
            try:
                __import__(modname)
            except Exception:
                legacy = f"numpy.core.{sub}"
                try:
                    legacy_mod = __import__(legacy, fromlist=["*"])
                    sys.modules[modname] = legacy_mod
                    if "numpy._core" in sys.modules:
                        setattr(sys.modules["numpy._core"], sub, legacy_mod)
                except Exception:
                    pass
    except Exception:
        pass

    try:
        from numpy.random import MT19937
        import numpy.random._pickle as npick

        orig = npick.__bit_generator_ctor

        def _ctor(bit_generator_name=None):
            if bit_generator_name is None:
                return MT19937()
            if isinstance(bit_generator_name, type) and "MT19937" in getattr(
                bit_generator_name, "__name__", ""
            ):
                return MT19937()
            try:
                return orig(bit_generator_name)
            except Exception:
                return MT19937()

        npick.__bit_generator_ctor = _ctor
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------
class StudyPaths:
    def __init__(self, success: Path):
        self.success = success
        self.mimic_tcf = (
            success
            / "MIMIC"
            / "step11_ml_tcf_sklearn_rscv"
            / "Models"
            / "TCF_sklearn"
        )
        self.eicu_ext = (
            success
            / "eICU"
            / "step11_ml_tcf_sklearn_external"
            / "Models"
            / "TCF_sklearn_external"
        )
        self.fs = success / "MIMIC" / "step10_feature_selection_entropy_stepwise"
        self.fig1_candidates = [
            success / "summary_results" / "Figures" / "pdf" / "Figure 1. Flowchart.pdf",
            success / "Figures" / "pdf" / "Figure 1. Flowchart.pdf",
            success / "MIMIC" / "step13_attrition_flowchart" / "Figures" / "Figure 1. Flowchart.pdf",
            success / "eICU" / "step12_attrition_flowchart" / "Figures" / "Figure 1. Flowchart.pdf",
        ]
        self.summary_fig = success / "summary_results" / "Figures"
        self.root_fig = success / "Figures"


def load_bundle(P: StudyPaths):
    metrics_v = pd.read_csv(P.mimic_tcf / "metrics_valid.csv", index_col=0)
    metrics_e = pd.read_csv(P.eicu_ext / "metrics_external.csv", index_col=0)
    alpha = pd.read_csv(P.mimic_tcf / "topsis_alpha.csv")
    # features.csv: one feature name per line (no header)
    raw = (P.mimic_tcf / "features.csv").read_text(encoding="utf-8").strip().splitlines()
    feat_list = [ln.strip().strip('"') for ln in raw if ln.strip()]

    train = pd.read_csv(P.mimic_tcf / "_csv" / "train.csv")
    valid = pd.read_csv(P.mimic_tcf / "_csv" / "valid.csv")
    external = pd.read_csv(P.eicu_ext / "external.csv")
    # Prefer column order from train if features.csv missing columns
    train_feats = [c for c in train.columns if c != "y"]
    if not feat_list:
        feat_list = train_feats
    else:
        missing = [f for f in feat_list if f not in train.columns]
        if missing:
            raise RuntimeError(f"features.csv names missing in train.csv: {missing}")
        # keep declared order
        feat_list = list(feat_list)

    entropy = pd.read_csv(P.fs / "tcf_entropy_path.csv")
    corr_drops = pd.read_csv(P.fs / "tcf_corr_pair_drops.csv")

    # Wider analytic frames for Fig2 extended entropy path (past k=30)
    train_wide = None
    external_wide = None
    wide_tr = (
        P.success / "MIMIC" / "step07_train_validation" / "Data" / "df_train.csv"
    )
    wide_e = (
        P.success / "eICU" / "step07_train_validation" / "Data" / "df_train.csv"
    )
    if wide_tr.exists() and wide_e.exists():
        train_wide = pd.read_csv(wide_tr)
        external_wide = pd.read_csv(wide_e)
        print(
            f"[info] wide frames for Fig2: train_wide={train_wide.shape} "
            f"external_wide={external_wide.shape}"
        )

    proba_v = {}
    for m in MODEL_ORDER:
        fp = P.mimic_tcf / "proba_valid" / f"{m}.csv"
        if fp.exists():
            proba_v[m] = pd.read_csv(fp)["prob"].to_numpy(dtype=float)

    proba_e = {}
    for m in MODEL_ORDER:
        fp = P.eicu_ext / f"proba_{m}.csv"
        if fp.exists():
            proba_e[m] = pd.read_csv(fp)["prob"].to_numpy(dtype=float)

    y_v = valid["y"].to_numpy(dtype=int)
    y_e = external["y"].to_numpy(dtype=int)
    y_tr = train["y"].to_numpy(dtype=int)

    return {
        "metrics_v": metrics_v,
        "metrics_e": metrics_e,
        "alpha": alpha,
        "features": feat_list,
        "train": train,
        "valid": valid,
        "external": external,
        "train_wide": train_wide,
        "external_wide": external_wide,
        "entropy": entropy,
        "corr_drops": corr_drops,
        "proba_v": proba_v,
        "proba_e": proba_e,
        "y_v": y_v,
        "y_e": y_e,
        "y_tr": y_tr,
    }


# ---------------------------------------------------------------------------
# Figure writers
# ---------------------------------------------------------------------------
FIGURE_SPECS = {
    "fig1": "Figure 1. Flowchart of the SA-AKI study cohorts",
    "fig2": "Figure 2. Entropy stepwise feature count versus AUC",
    "fig3": "Figure 3. Internal validation ROC curves of TCF and seven base models",
    "fig4": "Figure 4. SHAP feature importance of the best base model",
    "fig5": "Figure 5. Comparison of ROC curves for TCF across cohorts",
    "fig6": "Figure 6. Performance of six indices across datasets",
    "s1": "Figure S1. Feature processing flowchart",
    "s2": "Figure S2. Pearson correlation heatmap of final features",
    "s3": "Figure S3. Internal calibration curves of all models",
    "s4": "Figure S4. Decision curve analysis of TCF on the internal validation set",
    "s5": "Figure S5. SHAP summary plot of the best base model",
    "s6": "Figure S6. External calibration curves on the eICU cohort",
    "s7": "Figure S7. Decision curve analysis of TCF on the eICU external cohort",
}


def save_fig(fig, pdf_dir: Path, stem: str):
    pdf_dir.mkdir(parents=True, exist_ok=True)
    out = pdf_dir / f"{stem}.pdf"
    fig.savefig(out, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    return out


def write_md(md_dir: Path, stem: str, body_lines: list[str], meta: dict):
    md_dir.mkdir(parents=True, exist_ok=True)
    n_line = "; ".join(f"{k}={v}" for k, v in meta.get("n_by_db", {}).items())
    if meta.get("n_total"):
        n_line = f"{n_line}；合计 N={meta['n_total']}" if n_line else f"N={meta['n_total']}"
    lines = [
        f"# {stem}",
        "",
        "## 图面说明",
        *body_lines,
        "",
        "## 分析上下文",
        f"- 暴露: {meta.get('exposure', '30 dual-intersect clinical/lab features (ALLVARS)')}",
        f"- 结局: {meta.get('outcome', 'In-hospital death among SA-AKI')}",
        f"- 样本量: {n_line or '未记录'}",
        f"- Grouping: {meta.get('grouping', 'TCF multi-algorithm fusion (TOPSIS alphas frozen)')}",
        f"- 数据库: {', '.join(meta.get('databases', ['MIMIC', 'eICU']))}",
        f"- 是否拼图: {'是' if meta.get('combined') else '否'}",
        "",
    ]
    (md_dir / f"{stem}.md").write_text("\n".join(lines), encoding="utf-8")


def footnote_common() -> list[str]:
    return [
        "脚注口径：SA-AKI 队列在 MIMIC 开发（train/valid），eICU 外验；最终特征为双库可算交集 30 个；"
        "TCF 融合权重（TOPSIS α）在开发集冻结后外验套用；图面 AUC 标注取自 metrics_valid.csv / "
        "metrics_external.csv（roc_auc_score），三位小数。",
    ]


# ---- Fig1 (Wang-style single tree; NO dual-panel; NO figure footnotes) ----
def _fig1_setup_fonts():
    mpl.rcParams.update({
        "font.family": "serif",
        "font.serif": ["Times New Roman", "Times", "Liberation Serif", "DejaVu Serif", "serif"],
        "mathtext.fontset": "stix",
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
    })


def _fig1_box(ax, cx, cy, w, h, lines, *, lw=1.35, fs=9.0, title_fs=10.0, dashed=False):
    """Centered rounded box with multi-line text (Times). Returns (cx, cy, w, h)."""
    x0, y0 = cx - w / 2.0, cy - h / 2.0
    box = FancyBboxPatch(
        (x0, y0),
        w,
        h,
        boxstyle="round,pad=0.012,rounding_size=0.08",
        facecolor="white",
        edgecolor="black",
        lw=lw,
        linestyle=(0, (3.2, 2.0)) if dashed else "solid",
        zorder=3,
    )
    ax.add_patch(box)
    # title bold on first line; remaining regular
    if not lines:
        return cx, cy, w, h
    n = len(lines)
    # vertical packing from top
    top = cy + h / 2.0 - 0.12
    gap = (h - 0.22) / max(n, 1)
    for i, ln in enumerate(lines):
        y = top - i * gap - gap * 0.35
        weight = "bold" if i == 0 else "normal"
        size = title_fs if i == 0 else fs
        ax.text(
            cx, y, ln,
            ha="center", va="center",
            fontsize=size, fontweight=weight,
            fontfamily="serif", zorder=4,
        )
    return cx, cy, w, h


def _fig1_arrow(ax, x1, y1, x2, y2, *, lw=1.15):
    ax.annotate(
        "",
        xy=(x2, y2),
        xytext=(x1, y1),
        arrowprops=dict(arrowstyle="-|>", color="black", lw=lw, mutation_scale=12),
        zorder=2,
    )


def _fig1_vline_label(ax, x, y_top, y_bot, label, *, side="right", fs=8.2, lw=1.15):
    """Full vertical arrow + side label (label must NOT break the shaft)."""
    # Continuous shaft+head (previous mid-gap ate short connectors → floating arrowheads)
    _fig1_arrow(ax, x, y_top, x, y_bot, lw=lw)
    mid = 0.5 * (y_top + y_bot)
    # Keep label clear of the shaft (no white box covering the line)
    dx = 0.28 if side == "right" else -0.28
    ax.text(
        x + dx,
        mid,
        label,
        ha="left" if side == "right" else "right",
        va="center",
        fontsize=fs,
        fontfamily="serif",
        linespacing=1.2,
        zorder=5,
    )


def _fig1_count_deaths(data) -> dict:
    """Death counts from y columns (28-day all-cause)."""
    y_tr = data["y_tr"]
    y_v = data["y_v"]
    y_e = data["y_e"]
    return {
        "n_train": int(len(y_tr)),
        "d_train": int(y_tr.sum()),
        "n_valid": int(len(y_v)),
        "d_valid": int(y_v.sum()),
        "n_analytic": int(len(y_tr) + len(y_v)),
        "d_analytic": int(y_tr.sum() + y_v.sum()),
        "n_external": int(len(y_e)),
        "d_external": int(y_e.sum()),
    }


def draw_wang_style_fig1(data, out_pdf: Path) -> Path:
    """Single-tree Wang 2025-style flowchart; Times New Roman; no footnotes on canvas."""
    _fig1_setup_fonts()
    d = _fig1_count_deaths(data)
    # Fixed attrition numbers (aligned with redraw_fig1_dual_sa_aki.R)
    n_mimic_start, n_mimic_drop = 7767, 1774
    n_eicu_start, n_eicu_drop = 7424, 1207
    assert d["n_analytic"] == 5993, d
    assert d["n_train"] == 4794 and d["n_valid"] == 1199, d
    assert d["n_external"] == 6217, d

    # Taller canvas + longer connectors so arrow shafts stay visible
    fig, ax = plt.subplots(figsize=(8.8, 11.2))
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 13.2)
    ax.axis("off")
    fig.patch.set_facecolor("white")
    ax.set_facecolor("white")

    # ---- Development tree (top → analytic → train/valid) ----
    _fig1_box(
        ax, 5.0, 12.15, 5.6, 1.15,
        [
            "Development cohort (MIMIC-IV)",
            "Adult patients with SA-AKI (Age \u2265 18)",
            f"n = {n_mimic_start:,}",
        ],
        title_fs=10.5, fs=9.0,
    )
    # Longer connector: box bottom ~11.575 → analytic top ~10.05
    _fig1_vline_label(
        ax, 5.0, 11.52, 10.12,
        f"Excluded: no linkable 28-day mortality outcome\n"
        f"for a SA-AKI ICU stay (n = {n_mimic_drop:,})",
        side="right", fs=8.0,
    )

    _fig1_box(
        ax, 5.0, 9.35, 5.6, 1.25,
        [
            "Development analytic cohort",
            f"n = {d['n_analytic']:,}",
            f"{d['d_analytic']:,} death within 28 days",
        ],
        title_fs=10.5, fs=9.0,
    )
    # Longer connector before fork
    _fig1_vline_label(
        ax, 5.0, 8.68, 7.55,
        "Random 80/20 split\n(stratified by outcome)",
        side="right", fs=8.2,
    )

    train_cx, valid_cx = 2.55, 7.45
    fork_y = 7.40
    leaf_top = 6.55
    ax.plot([5.0, 5.0], [7.55, fork_y], color="black", lw=1.15, zorder=2)
    ax.plot([train_cx, valid_cx], [fork_y, fork_y], color="black", lw=1.15, zorder=2)
    _fig1_arrow(ax, train_cx, fork_y, train_cx, leaf_top)
    _fig1_arrow(ax, valid_cx, fork_y, valid_cx, leaf_top)

    _fig1_box(
        ax, train_cx, 5.55, 3.5, 1.45,
        [
            "Training set (80%)",
            f"n = {d['n_train']:,}",
            f"{d['d_train']:,} death within 28 days",
        ],
        title_fs=10.0, fs=8.8,
    )
    _fig1_box(
        ax, valid_cx, 5.55, 3.7, 1.45,
        [
            "Internal validation set (20%)",
            f"n = {d['n_valid']:,}",
            f"{d['d_valid']:,} death within 28 days",
        ],
        title_fs=10.0, fs=8.8,
    )

    # ---- External generalization (dashed enclosure; eICU whole analytic) ----
    ext_cx, ext_cy = 5.0, 2.15
    dash_w, dash_h = 7.4, 3.2
    dash = FancyBboxPatch(
        (ext_cx - dash_w / 2.0, ext_cy - dash_h / 2.0),
        dash_w,
        dash_h,
        boxstyle="round,pad=0.02,rounding_size=0.15",
        facecolor="white",
        edgecolor="black",
        lw=1.25,
        linestyle=(0, (4.5, 2.8)),
        zorder=1,
    )
    ax.add_patch(dash)
    ax.text(
        ext_cx, ext_cy - dash_h / 2.0 + 0.28,
        "external generalization data",
        ha="center", va="center", fontsize=9.5, fontfamily="serif",
        fontstyle="italic", zorder=4,
    )
    _fig1_box(
        ax, ext_cx, ext_cy + 0.22, 6.4, 2.25,
        [
            "eICU external validation cohort",
            "Patients with SA-AKI identified in eICU",
            f"Starting n = {n_eicu_start:,}; excluded not linkable to ICU baseline (n = {n_eicu_drop:,})",
            f"Analytic / external set n = {d['n_external']:,} (entire cohort; no retraining)",
            f"{d['d_external']:,} death within 28 days",
        ],
        title_fs=10.5, fs=8.6,
    )

    out_pdf.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_pdf, bbox_inches="tight", facecolor="white", pad_inches=0.15)
    plt.close(fig)
    return out_pdf


def build_fig1(P: StudyPaths, pdf_dir: Path, md_dir: Path, meta: dict, gaps: list, data=None):
    stem = FIGURE_SPECS["fig1"]
    if data is None:
        gaps.append("Fig1: data bundle required for Wang-style single tree")
        return None
    dst = pdf_dir / f"{stem}.pdf"
    try:
        draw_wang_style_fig1(data, dst)
    except Exception as e:
        gaps.append(f"Fig1 draw failed: {e}")
        return None
    d = _fig1_count_deaths(data)
    write_md(
        md_dir,
        stem,
        [
            "本图为 Wang 2025 npj Digital Medicine Fig.1 风格的**单树层级**纳排流程图（非双栏拼图）。",
            "开发支路（MIMIC-IV）：起始成人 SA-AKI 队列 n=7,767 → 排除无法链接 28 天死亡结局者 n=1,774 → "
            f"分析集 n={d['n_analytic']:,}（其中 {d['d_analytic']:,} death within 28 days）→ "
            f"分层随机 80/20：训练集 n={d['n_train']:,}（{d['d_train']:,} 死亡）/"
            f"内部验证集 n={d['n_valid']:,}（{d['d_valid']:,} 死亡）。",
            "外验支路置于虚线框「external generalization data」：eICU 起始 n=7,424 → "
            "排除无法链接 ICU baseline n=1,207 → "
            f"整库外验分析集 n={d['n_external']:,}（{d['d_external']:,} death within 28 days；不重训）。",
            "图面本身无脚注/注释条；字体 Times New Roman（serif）。框内结局文案对齐 Wang「xxx death within 28 days」。",
            "逐步人数与 redraw_fig1_dual_sa_aki.R 口径一致；死亡数由 train.csv / valid.csv / external.csv 的 y 列实算。",
        ],
        {**meta, "combined": False, "outcome": "28-day all-cause death among SA-AKI"},
    )
    return dst


# ---- Fig2 (Wang 2025 style: pipeline CSV only; star = path argmax) ----
def build_fig2(data, pdf_dir, md_dir, meta, gaps):
    stem = FIGURE_SPECS["fig2"]
    ent = data["entropy"].copy()
    ent.columns = [c.strip().strip('"') for c in ent.columns]
    kcol = [c for c in ent.columns if c.lower() == "k"][0]
    auccol = [c for c in ent.columns if c.lower() == "auc"][0]
    k = ent[kcol].to_numpy(dtype=float)
    auc = ent[auccol].to_numpy(dtype=float)
    best_i = int(np.nanargmax(auc))
    peak_k = int(k[best_i])
    peak_auc = float(auc[best_i])
    model_k = int(len(data.get("features") or []))

    plt.rcParams.update({
        "font.family": "serif",
        "font.serif": ["Times New Roman", "Times", "DejaVu Serif", "serif"],
        "axes.spines.right": False,
        "axes.spines.top": False,
    })
    fig, ax = plt.subplots(figsize=(6.4, 4.4))
    ax.plot(k, auc, color="#1f77b4", lw=1.6, marker="o", ms=4.5, zorder=3)
    ax.axvline(peak_k, color="0.45", ls="--", lw=1.15, zorder=2)
    ax.scatter([peak_k], [peak_auc], marker="*", s=220, color="#1f77b4", zorder=5, edgecolors="none")
    ax.annotate(
        f"({peak_k}, {peak_auc:.4f})",
        xy=(peak_k, peak_auc),
        xytext=(0, 10),
        textcoords="offset points",
        ha="center",
        va="bottom",
        fontsize=10,
    )
    ax.set_xlabel("Number of features", fontsize=12)
    ax.set_ylabel("AUC", fontsize=12)
    # 横轴截到路径最大 k（本课题相关后池=30）；不留空到 50
    k_max = float(np.nanmax(k))
    xmax = max(k_max, float(peak_k))
    pad = 1.0 if xmax <= 35 else 2.0
    ax.set_xlim(0, xmax + pad)
    ax.set_ylim(0.4, 1.0)
    tick_step = 5 if xmax <= 40 else 10
    xticks = list(np.arange(0, np.floor(xmax) + 1e-9, tick_step))
    if abs(xticks[-1] - xmax) > 0.1:
        xticks.append(xmax)
    ax.set_xticks(xticks)
    ax.set_yticks(np.arange(0.4, 1.01, 0.1))
    ax.yaxis.set_major_formatter(mpl.ticker.FormatStrFormatter("%.1f"))
    ax.grid(axis="y", linestyle="--", linewidth=0.6, color="0.75", alpha=0.9)
    ax.grid(axis="x", visible=False)
    fig.tight_layout()
    out = save_fig(fig, pdf_dir, stem)
    write_md(
        md_dir,
        stem,
        [
            "熵权逐步特征选择路径（流水线 tcf_entropy_path.csv）：横轴特征数，纵轴逐步 AUC。",
            f"路径 k={int(np.nanmin(k))}…{int(k_max)}（相关过滤后池；横轴截至路径终点，不延伸至 50）；"
            f"星标=路径 AUC argmax ({peak_k}, {peak_auc:.4f})；入模特征数={model_k}。",
        ],
        {**meta, "combined": False},
    )
    return out


# ---- ROC helpers ----
def plot_roc_panel(ax, y, proba_dict, metrics_df, title, highlight=("TCF",)):
    ax.plot([0, 1], [0, 1], ls="--", color="#bbbbbb", lw=1)
    for m in MODEL_ORDER:
        if m not in proba_dict:
            continue
        fpr, tpr, _ = roc_curve(y, proba_dict[m])
        auc_s = fmt_auc(metrics_df.loc[m, "AUC"]) if m in metrics_df.index else fmt_auc(
            roc_auc_score(y, proba_dict[m])
        )
        lw = 2.4 if m in highlight else 1.3
        ax.plot(
            fpr,
            tpr,
            color=MODEL_COLORS.get(m, "gray"),
            lw=lw,
            label=f"{m} (AUC={auc_s})",
            zorder=5 if m in highlight else 3,
        )
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.set_xlabel("1 − Specificity")
    ax.set_ylabel("Sensitivity")
    ax.set_title(title)
    ax.legend(frameon=False, loc="lower right", fontsize=7)


def build_fig3(data, pdf_dir, md_dir, meta, gaps):
    stem = FIGURE_SPECS["fig3"]
    fig, ax = plt.subplots(figsize=(6.0, 5.2))
    plot_roc_panel(
        ax,
        data["y_v"],
        data["proba_v"],
        data["metrics_v"],
        "Internal validation (MIMIC)",
    )
    out = save_fig(fig, pdf_dir, stem)
    auc_lines = [
        f"- {m}: AUC={fmt_auc(data['metrics_v'].loc[m, 'AUC'])}"
        for m in MODEL_ORDER
        if m in data["metrics_v"].index
    ]
    write_md(
        md_dir,
        stem,
        [
            "本图为 MIMIC 内部验证集 ROC：TCF 与七个子模型（DT/RF/SVM/NB/GBDT/XGB/LGBM）。",
            "横轴 1−特异度，纵轴灵敏度；对角线为无信息参考（AUC=0.5）。TCF 曲线加粗。",
            "图上标注（AUC，与 metrics_valid.csv 三位小数一致）：",
            *auc_lines,
            f"内部验证 n={len(data['y_v'])}（事件 {int(data['y_v'].sum())}）。",
            *footnote_common(),
        ],
        {**meta, "combined": False},
    )
    return out


def _unlink_figure_stem(stem: str, *bases: Path) -> None:
    """Remove PDF/PNG/TIFF/md for a figure stem under each Figures root."""
    for base in bases:
        if base is None:
            continue
        for sub, ext in (
            ("pdf", ".pdf"),
            ("png", ".png"),
            ("tiff", ".tiff"),
            ("image_information", ".md"),
        ):
            fp = base / sub / f"{stem}{ext}"
            if fp.exists():
                fp.unlink()
                print(f"[clean] removed {fp}")
        # flat leftovers under Figures root
        for ext in (".pdf", ".png", ".tiff", ".md"):
            fp = base / f"{stem}{ext}"
            if fp.exists():
                fp.unlink()
                print(f"[clean] removed {fp}")


def _boot_roc_band_and_auc_ci(
    y,
    p,
    n_boot=N_BOOT,
    seed=BOOT_SEED,
    n_grid=101,
):
    """Bootstrap ROC TPR envelope on a common FPR grid + AUC 2.5/97.5% CI.

    Vectorized where possible: interpolate each bootstrap ROC onto ``fpr_grid``.
    """
    y = np.asarray(y, dtype=int)
    p = np.asarray(p, dtype=float)
    fpr_grid = np.linspace(0.0, 1.0, int(n_grid))
    rng = np.random.default_rng(int(seed))
    n = len(y)
    tpr_mat = np.empty((int(n_boot), len(fpr_grid)), dtype=float)
    aucs = np.empty(int(n_boot), dtype=float)
    kept = 0
    for _ in range(int(n_boot)):
        idx = rng.integers(0, n, n)
        yi = y[idx]
        pi = p[idx]
        if yi.min() == yi.max():
            continue
        fpr_b, tpr_b, _ = roc_curve(yi, pi)
        # sklearn ROC is non-decreasing in FPR; enforce endpoints for interp
        tpr_i = np.interp(fpr_grid, fpr_b, tpr_b)
        tpr_i[0] = 0.0
        tpr_i[-1] = 1.0
        tpr_mat[kept] = tpr_i
        aucs[kept] = roc_auc_score(yi, pi)
        kept += 1
    if kept < 10:
        raise RuntimeError(f"ROC bootstrap kept only {kept}/{n_boot} draws")
    tpr_mat = tpr_mat[:kept]
    aucs = aucs[:kept]
    lo = np.percentile(tpr_mat, 2.5, axis=0)
    hi = np.percentile(tpr_mat, 97.5, axis=0)
    auc_lo, auc_hi = np.percentile(aucs, [2.5, 97.5])
    return fpr_grid, lo, hi, float(auc_lo), float(auc_hi)


def _resolve_eicu_unittype_cohorts(P: StudyPaths, data) -> dict:
    """Map eICU external rows to unittype strata (shared by Fig5 / Fig6).

    external.csv has no site columns; eICU step07 df_train is row-aligned on y
    (verified) and carries ``unittype``. Split:
      Cohort 1 = Med-Surg ICU (largest unit type)
      Cohort 2 = all other eICU unit types combined
    Both strata have >>30 events. MIMIC has no careunit/specialty column.
    """
    eicu_meta = (
        P.success / "eICU" / "step07_train_validation" / "Data" / "df_train.csv"
    )
    if not eicu_meta.exists():
        raise FileNotFoundError(f"eICU unittype frame missing: {eicu_meta}")
    meta_df = pd.read_csv(eicu_meta, usecols=["unittype", "fustatus"])
    y_e = np.asarray(data["y_e"], dtype=int)
    if len(meta_df) != len(y_e):
        raise RuntimeError(
            f"eICU meta n={len(meta_df)} != external n={len(y_e)}; cannot align unittype"
        )
    if not np.array_equal(meta_df["fustatus"].to_numpy(dtype=int), y_e):
        raise RuntimeError(
            "eICU df_train fustatus != external y in row order; refuse silent join"
        )
    unit = meta_df["unittype"].astype(str).fillna("Unknown")
    mask_c1 = unit.eq("Med-Surg ICU").to_numpy()
    mask_c2 = ~mask_c1
    other_counts = (
        unit[~mask_c1]
        .value_counts(dropna=False)
        .rename_axis("unittype")
        .reset_index(name="n")
    )
    return {
        "unittype": unit.to_numpy(),
        "mask_c1": mask_c1,
        "mask_c2": mask_c2,
        "c1_label": "Med-Surg ICU",
        "c2_label": "other eICU unit types",
        "c2_unittype_counts": other_counts,
    }


# Back-compat alias (Fig5 historically named)
_fig5_resolve_eicu_unittype_cohorts = _resolve_eicu_unittype_cohorts


def _fig5_curve_payload(y, p, *, seed_offset: int = 0):
    """Point ROC + bootstrap band；图例 AUC CI 与 Table S10 同用 `_boot_metric_cis`。"""
    y = np.asarray(y, dtype=int)
    p = np.asarray(p, dtype=float)
    if y.min() == y.max():
        raise RuntimeError("cohort has a single outcome class; cannot ROC")
    auc_pt = float(roc_auc_score(y, p))
    fpr, tpr, _ = roc_curve(y, p)
    seed = BOOT_SEED + int(seed_offset)
    fpr_g, lo, hi, _auc_lo_band, _auc_hi_band = _boot_roc_band_and_auc_ci(
        y, p, n_boot=N_BOOT, seed=seed
    )
    # 图例 CI 字符串与 S10/Table2-TCF 锁同 seed 的 metric bootstrap（非仅 ROC 带）
    cis = _boot_metric_cis(y, p, n_boot=N_BOOT, seed=seed, threshold=FIG6_THRESHOLD)
    return {
        "y": y,
        "p": p,
        "n": int(len(y)),
        "events": int(y.sum()),
        "auc": auc_pt,
        "auc_s": fmt_auc(auc_pt),
        "auc_lo": float(cis["AUC"]["lo"]),
        "auc_hi": float(cis["AUC"]["hi"]),
        "fpr": fpr,
        "tpr": tpr,
        "fpr_g": fpr_g,
        "lo": lo,
        "hi": hi,
    }


def _fig5_legend_str(name: str, cur: dict) -> str:
    return (
        f"{name} {cur['auc_s']} "
        f"({cur['auc_lo']:.3f}\u2013{cur['auc_hi']:.3f})"
    )


def _fig5_draw_panel(ax, curves: list[tuple[str, dict, str]], *, panel_tag: str):
    """Draw TCF-only ROC curves with CI bands; curves=(legend, payload, color)."""
    ax.set_aspect("equal", adjustable="box")
    ax.plot([0, 1], [0, 1], ls="--", color="#bbbbbb", lw=1.0, zorder=1)
    for legend, cur, color in curves:
        ax.fill_between(
            cur["fpr_g"],
            cur["lo"],
            cur["hi"],
            color=color,
            alpha=0.20,
            linewidth=0,
            zorder=2,
        )
        ax.plot(cur["fpr"], cur["tpr"], color=color, lw=2.0, label=legend, zorder=4)
    ax.set_xlim(0.0, 1.0)
    ax.set_ylim(0.0, 1.0)
    ax.set_xticks(np.linspace(0, 1, 6))
    ax.set_yticks(np.linspace(0, 1, 6))
    ax.set_xlabel("False Positive Rate (1 − Specificity)", fontsize=10)
    ax.set_ylabel("True Positive Rate (Sensitivity)", fontsize=10)
    ax.text(
        -0.12,
        1.05,
        panel_tag,
        transform=ax.transAxes,
        fontsize=12,
        fontweight="bold",
        fontfamily="serif",
        va="bottom",
        ha="left",
    )
    ax.legend(frameon=False, loc="lower right", fontsize=7.5)


def build_fig5(P: StudyPaths, data, pdf_dir, md_dir, meta, gaps):
    """Wang 2025 Fig.5: 1×2 TCF-only ROC panels with cohort legend + CI bands.

    Paper layout: (a)/(b) both overlay Internal validation (red) plus distinct
    external cohorts. No hospital_id in eICU dabiao/analytic; cohorts from
    row-aligned ``unittype``:
      (a) Internal + Cohort 1 (eICU Med-Surg ICU)
      (b) Internal + Cohort 2 (eICU other unit types)
    Keeps CI-band style; NOT 8-model spaghetti.
    """
    stem = FIGURE_SPECS["fig5"]
    old_stems = [
        "Figure 5. Dual-cohort ROC curves for TCF and base models",
        # prior single-panel rebuild title (same stem string — unlink flat leftovers only)
    ]
    fig_roots = []
    if pdf_dir is not None:
        fig_roots.append(pdf_dir.parent)
    for base in fig_roots:
        for old_stem in old_stems:
            _unlink_figure_stem(old_stem, base)

    if "TCF" not in data["proba_v"] or "TCF" not in data["proba_e"]:
        gaps.append("Fig5: missing TCF proba on valid and/or external")
        return None

    try:
        strata = _resolve_eicu_unittype_cohorts(P, data)
    except Exception as e:
        gaps.append(f"Fig5 unittype strata failed: {e}")
        return None

    y_v = data["y_v"]
    p_v = data["proba_v"]["TCF"]
    y_e = data["y_e"]
    p_e = data["proba_e"]["TCF"]

    mask_c1 = strata["mask_c1"]
    mask_c2 = strata["mask_c2"]
    # Prefer metrics CSV for Internal point AUC (string-level lock); strata recompute.
    auc_v_file = fmt_auc(data["metrics_v"].loc["TCF", "AUC"])

    print(
        f"[fig5] dual-panel unittype split: "
        f"C1 Med-Surg n={int(mask_c1.sum())} events={int(y_e[mask_c1].sum())}; "
        f"C2 other n={int(mask_c2.sum())} events={int(y_e[mask_c2].sum())}; "
        f"bootstrap n_boot={N_BOOT} seed={BOOT_SEED}"
    )
    cur_int = _fig5_curve_payload(y_v, p_v, seed_offset=SEED_OFF_INTERNAL)
    # Lock Internal legend AUC to metrics_valid 3dp when recomputed matches
    if cur_int["auc_s"] != auc_v_file:
        gaps.append(
            f"Fig5 Internal AUC recomputed {cur_int['auc_s']} != metrics {auc_v_file}"
        )
    cur_int["auc_s"] = auc_v_file
    cur_c1 = _fig5_curve_payload(y_e[mask_c1], p_e[mask_c1], seed_offset=SEED_OFF_C1)
    cur_c2 = _fig5_curve_payload(y_e[mask_c2], p_e[mask_c2], seed_offset=SEED_OFF_C2)

    color_internal = "#C00000"  # red
    color_c1 = "#7CB342"  # green
    color_c2 = "#00BCD4"  # cyan

    legend_internal = _fig5_legend_str("Internal validation set", cur_int)
    legend_c1 = _fig5_legend_str("Cohort 1", cur_c1)
    legend_c2 = _fig5_legend_str("Cohort 2", cur_c2)

    plt.rcParams.update({
        "font.family": "serif",
        "font.serif": ["Times New Roman", "Times", "DejaVu Serif", "serif"],
        "axes.spines.right": False,
        "axes.spines.top": False,
    })
    fig, axes = plt.subplots(1, 2, figsize=(10.2, 5.0))
    _fig5_draw_panel(
        axes[0],
        [
            (legend_internal, cur_int, color_internal),
            (legend_c1, cur_c1, color_c1),
        ],
        panel_tag="(a)",
    )
    _fig5_draw_panel(
        axes[1],
        [
            (legend_internal, cur_int, color_internal),
            (legend_c2, cur_c2, color_c2),
        ],
        panel_tag="(b)",
    )
    fig.tight_layout()
    out = save_fig(fig, pdf_dir, stem)

    c2_units = ", ".join(
        f"{r.unittype} n={int(r.n)}"
        for r in strata["c2_unittype_counts"].itertuples(index=False)
    )
    write_md(
        md_dir,
        stem,
        [
            "Wang 2025 npj Digit Med Fig.5 风格：**1×2 双面板**，仅绘 TCF 多队列 ROC"
            "（队列图例 + bootstrap 95% CI 阴影带；非八模型并列）。",
            "面板结构（对齐原文 Internal 作红参照、外队列分面）：",
            f"- **(a)** Internal validation set（红）+ Cohort 1（绿）="
            f" eICU `{strata['c1_label']}`"
            f"（n={cur_c1['n']}，事件 {cur_c1['events']}）。",
            f"- **(b)** Internal validation set（红）+ Cohort 2（青）="
            f" eICU `{strata['c2_label']}`"
            f"（n={cur_c2['n']}，事件 {cur_c2['events']}；组成：{c2_units}）。",
            "分层依据：eICU dabiao/analytic **无 hospital_id / hospitalid**；"
            "TCF `external.csv` 亦无站点列。改用与 external 行序对齐的"
            " `eICU/step07_train_validation/Data/df_train.csv` 的 **unittype**"
            "（fustatus 与 external y 逐行一致后切分）。"
            "MIMIC 分析表无 careunit/specialty，故无开发中心专科 Cohort 1-1/1-2。",
            "图例格式：`Name AUC (lo–hi)`；点估计三位小数；"
            f"图例 AUC CI 与 Table S10 / Table 2 TCF 同源 `_boot_metric_cis`"
            f"（n_boot={N_BOOT}, seed_internal={BOOT_SEED}+{SEED_OFF_INTERNAL}, "
            f"C1={BOOT_SEED}+{SEED_OFF_C1}, C2={BOOT_SEED}+{SEED_OFF_C2}）。"
            "阴影带仍为同 seed 的 ROC bootstrap TPR 包络。",
            f"Internal（MIMIC valid）n={cur_int['n']}（事件 {cur_int['events']}）；"
            f"AUC 与 metrics_valid.csv 锁定为 {auc_v_file}。",
            f"图例字符串：(a) {legend_internal}；{legend_c1}；"
            f"(b) {legend_internal}；{legend_c2}。",
            "横轴 False Positive Rate (1−Specificity)，纵轴 True Positive Rate (Sensitivity)；"
            "虚线为无信息参考。训练集表观 AUC≈1 不进入本图（见 Table S10 脚注）。",
            *footnote_common(),
        ],
        {**meta, "combined": True},
    )
    data["_fig5_legend"] = {
        "internal": legend_internal,
        "cohort1": legend_c1,
        "cohort2": legend_c2,
        "panel_a": [legend_internal, legend_c1],
        "panel_b": [legend_internal, legend_c2],
        "cohort1_def": {
            "source": "eICU unittype",
            "rule": "Med-Surg ICU",
            "n": cur_c1["n"],
            "events": cur_c1["events"],
            "auc": cur_c1["auc_s"],
            "auc_ci": (cur_c1["auc_lo"], cur_c1["auc_hi"]),
        },
        "cohort2_def": {
            "source": "eICU unittype",
            "rule": "other unit types combined",
            "n": cur_c2["n"],
            "events": cur_c2["events"],
            "auc": cur_c2["auc_s"],
            "auc_ci": (cur_c2["auc_lo"], cur_c2["auc_hi"]),
            "unittypes": strata["c2_unittype_counts"].to_dict(orient="records"),
        },
        "auc_v": auc_v_file,
        "auc_ci_v": (cur_int["auc_lo"], cur_int["auc_hi"]),
        "hospital_id_available": False,
    }
    return out


# ---- SHAP (prefer shap.TreeExplainer + shap.plots.heatmap; native pred_contrib fallback) ----
def _import_shap():
    """Import shap; disable/stub numba if WSL numba SystemError blocks import."""
    import os
    import types

    os.environ.setdefault("SHAP_DISABLE_NUMBA", "1")
    # Probe real numba; on SystemError (broken llvmlite/_internal) stub before shap.
    try:
        import numba  # noqa: F401
    except Exception:
        for k in list(sys.modules):
            if k == "numba" or k.startswith("numba."):
                del sys.modules[k]

        def _identity_jit(*_a, **_k):
            def deco(f):
                return f

            if _a and callable(_a[0]) and not _k:
                return _a[0]
            return deco

        stub = types.ModuleType("numba")
        stub.njit = _identity_jit
        stub.jit = _identity_jit
        stub.vectorize = _identity_jit
        stub.guvectorize = _identity_jit
        sys.modules["numba"] = stub
        for sub in (
            "numba.core",
            "numba.np",
            "numba.np.ufunc",
            "numba.typed",
            "numba.types",
        ):
            sys.modules.setdefault(sub, types.ModuleType(sub))
        warnings.warn(
            "numba import failed; stubbed so shap can load (SHAP_DISABLE_NUMBA=1)",
            RuntimeWarning,
            stacklevel=2,
        )
    import shap

    return shap


def _positive_class_explanation(explanation):
    """Binary classifiers may return (n, f, 2); keep positive-class slice."""
    vals = np.asarray(explanation.values)
    if vals.ndim == 3:
        # take last class (positive) for binary
        idx = vals.shape[-1] - 1
        return explanation[:, :, idx]
    return explanation


def _hclust_instance_order(shap_vals: np.ndarray) -> np.ndarray:
    """Ward leaf order of instances → vertical red/blue stripes on heatmap.

    Sorting by f(x) alone leaves a long low-risk plateau → solid horizontal bands
    (our previous Fig4). Paper Fig.4 uses hierarchical clustering of instances.
    """
    X = np.asarray(shap_vals, dtype=float)
    n = int(X.shape[0])
    if n < 3:
        return np.arange(n, dtype=int)
    try:
        from scipy.cluster.hierarchy import linkage, leaves_list
        from scipy.spatial.distance import pdist

        # cosine groups similar SHAP *profiles*; euclidean fallback
        try:
            d = pdist(X, metric="cosine")
            if not np.isfinite(d).all():
                raise ValueError("non-finite cosine distances")
            Z = linkage(d, method="average")
        except Exception:
            Z = linkage(pdist(X, metric="euclidean"), method="ward")
        return np.asarray(leaves_list(Z), dtype=int)
    except Exception:
        return np.argsort(X.sum(axis=1))


def compute_tree_shap(
    P: StudyPaths,
    data,
    model_name: str,
    n_sub: int | None = None,
    split: str = "valid",
):
    """Return (X_raw, shap_vals, n, model, explanation_or_None).

    Default: full internal validation set (Wang Fig.4), no train subsample.
    Pass n_sub to cap; split='train'|'valid'.

    SHAP is computed on MinMax-scaled features (same scaler as training).
    Returned X is **raw** clinical units for beeswarm feature-value coloring;
    explanation.data is also raw. Heatmap uses shap values from scaled space.
    """
    patch_numpy_joblib()
    model_path = P.mimic_tcf / f"model_{model_name}.joblib"
    if not model_path.exists():
        raise FileNotFoundError(model_path)
    model = joblib.load(model_path)
    feats = list(data["features"])
    if split not in data:
        raise KeyError(f"data has no split '{split}'")
    X_all = data[split][feats].copy()
    if n_sub is None or int(n_sub) >= len(X_all):
        X_raw = X_all.reset_index(drop=True)
    else:
        rng = np.random.default_rng(SHAP_SEED)
        idx = rng.choice(len(X_all), size=min(int(n_sub), len(X_all)), replace=False)
        X_raw = X_all.iloc[idx].reset_index(drop=True)
    n = int(len(X_raw))
    feat_names = [display_label(f) for f in feats]

    # Models were fit on MinMax-scaled features (see minmax_scaler.joblib).
    # Explaining raw units collapses all patients onto one leaf path → flat SHAP bars.
    scaler_path = P.mimic_tcf / "minmax_scaler.joblib"
    if not scaler_path.exists():
        raise FileNotFoundError(
            f"Missing training MinMax scaler required for SHAP: {scaler_path}"
        )
    scaler = joblib.load(scaler_path)
    X_scaled = pd.DataFrame(
        scaler.transform(X_raw.to_numpy(dtype=float)),
        columns=feats,
        index=X_raw.index,
    )
    X = X_scaled  # model / TreeExplainer input

    def _explanation_with_raw(shap_vals, base_values):
        shap = _import_shap()
        return shap.Explanation(
            values=np.asarray(shap_vals, dtype=float),
            base_values=np.asarray(base_values, dtype=float).reshape(-1),
            data=X_raw.to_numpy(dtype=float),
            feature_names=feat_names,
        )

    # Preferred: official TreeExplainer → Explanation (for shap.plots.heatmap)
    try:
        shap = _import_shap()
        explainer = shap.TreeExplainer(model)
        explanation = _positive_class_explanation(explainer(X))
        shap_vals = np.asarray(explanation.values, dtype=float)
        # Keep SHAP from scaled X; attach raw data + display names for beeswarm
        explanation = _explanation_with_raw(
            shap_vals, np.asarray(explanation.base_values, dtype=float)
        )
        return X_raw, shap_vals, n, model, explanation
    except Exception as te_err:
        warnings.warn(f"TreeExplainer unavailable ({te_err}); falling back to native contrib")

    base_values = None
    if model_name == "LGBM" or type(model).__name__.startswith("LGBM"):
        contrib = model.predict(X, pred_contrib=True)
        contrib = np.asarray(contrib)
        shap_vals = contrib[:, :-1]
        base_values = contrib[:, -1]
    elif model_name == "XGB" or "XGB" in type(model).__name__:
        import xgboost as xgb

        booster = model.get_booster()
        dm = xgb.DMatrix(X)
        contrib = np.asarray(booster.predict(dm, pred_contribs=True))
        shap_vals = contrib[:, :-1]
        base_values = contrib[:, -1]
    elif model_name == "RF" or "GradientBoosting" in type(model).__name__ or model_name == "GBDT":
        try:
            shap = _import_shap()
            explainer = shap.Explainer(model, X)
            explanation = _positive_class_explanation(explainer(X))
            shap_vals = np.asarray(explanation.values, dtype=float)
            explanation = _explanation_with_raw(
                shap_vals, np.asarray(explanation.base_values, dtype=float)
            )
            return X_raw, shap_vals, n, model, explanation
        except Exception:
            shap_vals = _kernel_like_local(model, X, n_bg=50, seed=SHAP_SEED)
            base_values = None
    else:
        raise RuntimeError(f"Unsupported SHAP backend for {model_name}")

    # Build Explanation for heatmap from native values
    try:
        if base_values is None:
            # align base so base + sum(shap) ≈ predict_proba when possible
            try:
                fx = np.asarray(model.predict_proba(X)[:, 1], dtype=float)
                base_values = fx - shap_vals.sum(axis=1)
            except Exception:
                base_values = np.zeros(len(X), dtype=float)
        explanation = _explanation_with_raw(shap_vals, base_values)
    except Exception:
        explanation = None

    return X_raw, shap_vals, n, model, explanation


def _kernel_like_local(model, X: pd.DataFrame, n_bg: int = 50, seed: int = 42):
    """Cheap interventional attribution: E[f|x] - E[f|x_j=bg] approx for trees."""
    rng = np.random.default_rng(seed)
    bg_idx = rng.choice(len(X), size=min(n_bg, len(X)), replace=False)
    bg = X.iloc[bg_idx]
    base = model.predict_proba(X)[:, 1]
    shap_vals = np.zeros_like(X.to_numpy(), dtype=float)
    Xnp = X.to_numpy(dtype=float)
    B = bg.to_numpy(dtype=float)
    for j in range(X.shape[1]):
        Xj = Xnp.copy()
        # replace feature j with background mean
        Xj[:, j] = B[:, j].mean()
        pj = model.predict_proba(Xj)[:, 1]
        shap_vals[:, j] = base - pj
    return shap_vals


def pick_best_tree_model(metrics_v: pd.DataFrame) -> str:
    sub = metrics_v.loc[[m for m in TREE_CANDIDATES if m in metrics_v.index], "AUC"]
    return str(sub.idxmax())


def _shap_order(shap_vals, top_n=20):
    mean_abs = np.abs(shap_vals).mean(axis=0)
    order = np.argsort(mean_abs)[::-1]
    return order[:top_n], mean_abs


def build_fig4(P, data, pdf_dir, md_dir, meta, gaps, shap_cache: dict):
    """Wang 2025 Fig.4: shap.plots.heatmap on FULL internal validation + hclust order."""
    stem = FIGURE_SPECS["fig4"]
    best = pick_best_tree_model(data["metrics_v"])
    try:
        X_raw, shap_vals, n_used, model, explanation = compute_tree_shap(
            P, data, best, n_sub=None, split="valid"
        )
    except Exception as e:
        gaps.append(f"Fig4 SHAP failed for {best}: {e}")
        return None

    if explanation is None:
        gaps.append(f"Fig4: could not build shap.Explanation for {best}")
        return None

    # Force instance hierarchical clustering → vertical stripes (paper look).
    # Do NOT rely on shap default alone: some versions sort by f(x), which yields
    # a long low-risk plateau and solid horizontal color bands.
    inst_order = _hclust_instance_order(shap_vals)
    try:
        explanation = explanation[inst_order]
        shap_vals = np.asarray(explanation.values, dtype=float)
        X_raw = X_raw.iloc[inst_order].reset_index(drop=True)
    except Exception as e:
        gaps.append(f"Fig4 hclust reorder failed: {e}")
        return None

    shap_cache["best"] = best
    shap_cache["X"] = X_raw  # raw units for S5 beeswarm coloring
    shap_cache["shap_vals"] = shap_vals  # from MinMax-scaled model space
    shap_cache["n_used"] = n_used
    shap_cache["model"] = model
    shap_cache["split"] = "valid"
    shap_cache["instance_order"] = "hclust"
    shap_cache["shap_scaled"] = True

    feats = list(data["features"])
    n_feat = shap_vals.shape[1]
    mean_abs = np.abs(shap_vals).mean(axis=0)
    feat_order = np.argsort(mean_abs)[::-1]
    n_show = min(9, n_feat)  # max_display=10 includes Sum-of-other row
    auc_s = fmt_auc(data["metrics_v"].loc[best, "AUC"])

    try:
        shap = _import_shap()
        plt.close("all")
        # identity instance_order: keep our hclust leaf order (vertical stripes)
        shap.plots.heatmap(
            explanation,
            max_display=10,
            instance_order=np.arange(len(explanation)),
            show=False,
        )
        fig = plt.gcf()
        fig.set_size_inches(9.2, 5.8)
        fig.text(
            0.01, 0.995,
            f"{best}  AUC={auc_s}",
            ha="left", va="top", fontsize=8, color="#444444",
            transform=fig.transFigure,
        )
        out = save_fig(fig, pdf_dir, stem)
    except Exception as e:
        gaps.append(f"Fig4 shap.plots.heatmap failed: {e}")
        return None

    top5 = ", ".join(
        f"{display_label(feats[i])} ({mean_abs[i]:.4f})" for i in feat_order[:5]
    )
    write_md(
        md_dir,
        stem,
        [
            f"本图用 **shap.plots.heatmap** 绘制最优树模型（{best}）在 **内部验证集全部样本** "
            f"（n={n_used}）上的 SHAP 热图，对齐 Wang 2025 Fig.4：顶端 f(x)、红蓝竖向簇状热图、"
            f"右侧 mean |SHAP|、底部 Sum of other features；`max_display=10`（顶 {n_show} 特征 + "
            f"Sum of {max(n_feat - n_show, 0)} other）。",
            "SHAP 在训练同款 **MinMaxScaler**（`minmax_scaler.joblib`）变换后的特征空间上计算；"
            "未缩放原始临床单位会导致叶路径塌缩、热图呈水平色带。",
            "实例轴按 SHAP 剖面层次聚类（Ward/average）排序，得到原文那种竖条簇；"
            "特征名经 display_label（禁下划线）。"
            f"内部验证 AUC={auc_s}。",
            f"图上 Top 特征 mean |SHAP|：{top5}。",
            *footnote_common(),
        ],
        {**meta, "combined": False},
    )
    return out


def build_s5(data, pdf_dir, md_dir, meta, gaps, shap_cache: dict):
    stem = FIGURE_SPECS["s5"]
    if "shap_vals" not in shap_cache:
        gaps.append("S5 skipped: no SHAP cache from Fig4")
        return None
    best = shap_cache["best"]
    X = shap_cache["X"]  # raw clinical units for color
    shap_vals = shap_cache["shap_vals"]  # MinMax-scaled SHAP
    n_used = shap_cache["n_used"]
    order, mean_abs = _shap_order(shap_vals, top_n=20)
    # beeswarm
    fig, ax = plt.subplots(figsize=(7.0, 5.8))
    rng = np.random.default_rng(0)
    for row_i, feat_i in enumerate(order[::-1]):
        vals = shap_vals[:, feat_i]
        fvals = X.iloc[:, feat_i].to_numpy(dtype=float)
        # color by feature value rank
        if np.nanstd(fvals) > 0:
            c = (fvals - np.nanmin(fvals)) / (np.nanmax(fvals) - np.nanmin(fvals) + 1e-12)
        else:
            c = np.zeros_like(fvals)
        # subsample points for clarity
        if len(vals) > 300:
            take = rng.choice(len(vals), 300, replace=False)
            vals, c = vals[take], c[take]
        y_jitter = row_i + (rng.random(len(vals)) - 0.5) * 0.35
        sc = ax.scatter(
            vals,
            y_jitter,
            c=c,
            cmap="coolwarm",
            s=8,
            alpha=0.65,
            linewidths=0,
            vmin=0,
            vmax=1,
        )
    ax.set_yticks(range(len(order)))
    ax.set_yticklabels([display_label(data["features"][i]) for i in order[::-1]])
    ax.axvline(0, color="#888888", lw=0.8)
    ax.set_xlabel("SHAP value (impact on model output)")
    ax.set_title(f"SHAP summary — {best}")
    cbar = fig.colorbar(sc, ax=ax, fraction=0.03, pad=0.02)
    cbar.set_label("Feature value (low → high)")
    fig.tight_layout()
    out = save_fig(fig, pdf_dir, stem)
    write_md(
        md_dir,
        stem,
        [
            f"本图为与 Figure 4 同一模型（{best}）的 SHAP beeswarm/summary：每点为内部验证集个体，"
            "横坐标为 MinMax 缩放特征空间上的 SHAP 贡献；颜色按**原始临床单位**特征值高低着色。",
            f"与 Figure 4 同源：内部验证集全部样本 n={n_used}；特征展示名无下划线。",
            f"按 mean |SHAP| 排序的 Top 特征与 Figure 4 一致。",
            *footnote_common(),
        ],
        {**meta, "combined": False},
    )
    return out


# ---- Fig6 Wang-style forest (point + 95% CI across datasets) ----
FIG6_THRESHOLD = 0.5
FIG6_DATASET_COLORS = {
    "Internal Validation set": "#81D4FA",  # light blue
    "Cohort 1": "#81C784",  # green
    "Cohort 2": "#BA68C8",  # purple
}
FIG6_METRICS = [
    ("AUC", "AUC"),
    ("ACC", "ACC"),
    ("SPE", "SPE"),
    ("F1", "F1-score"),
    ("PRE", "PRE"),
    ("SEN", "SEN"),
]


def _confusion_metrics_at_threshold(y, p, threshold=FIG6_THRESHOLD) -> dict:
    """Point estimates: AUC + ACC/SPE/F1/PRE/SEN at fixed probability threshold."""
    y = np.asarray(y, dtype=int)
    p = np.asarray(p, dtype=float)
    pred = (p >= float(threshold)).astype(int)
    tn, fp, fn, tp = confusion_matrix(y, pred, labels=[0, 1]).ravel()
    spe = float(tn / (tn + fp)) if (tn + fp) else float("nan")
    return {
        "AUC": float(roc_auc_score(y, p)),
        "ACC": float(accuracy_score(y, pred)),
        "SPE": spe,
        "F1": float(f1_score(y, pred, zero_division=0)),
        "PRE": float(precision_score(y, pred, zero_division=0)),
        "SEN": float(recall_score(y, pred, zero_division=0)),
    }


def _boot_metrics(y, p, n_boot=N_BOOT, seed=BOOT_SEED, threshold=FIG6_THRESHOLD):
    """Bootstrap metric draws (same keys as point metrics); threshold=0.5."""
    rng = np.random.default_rng(seed)
    rows = []
    n = len(y)
    y = np.asarray(y, dtype=int)
    p = np.asarray(p, dtype=float)
    for _ in range(n_boot):
        idx = rng.integers(0, n, n)
        yi, pi = y[idx], p[idx]
        if len(np.unique(yi)) < 2:
            continue
        rows.append(_confusion_metrics_at_threshold(yi, pi, threshold=threshold))
    return pd.DataFrame(rows)


def _boot_metric_cis(y, p, n_boot=N_BOOT, seed=BOOT_SEED, threshold=FIG6_THRESHOLD):
    """Point estimate + bootstrap 95% CI for each Fig6 metric."""
    point = _confusion_metrics_at_threshold(y, p, threshold=threshold)
    boot = _boot_metrics(y, p, n_boot=n_boot, seed=seed, threshold=threshold)
    out = {}
    for key in ("AUC", "ACC", "SPE", "F1", "PRE", "SEN"):
        arr = boot[key].dropna().to_numpy(dtype=float) if key in boot.columns else np.array([])
        if len(arr) >= 10:
            lo, hi = np.percentile(arr, [2.5, 97.5])
        else:
            lo = hi = float(point[key])
        out[key] = {
            "est": float(point[key]),
            "lo": float(lo),
            "hi": float(hi),
            "n_boot_kept": int(len(arr)),
        }
    return out


def _predict_tcf_proba_on_frame(P: StudyPaths, df: pd.DataFrame, features: list[str]) -> np.ndarray:
    """Score TCF on a feature frame with frozen MIMIC scaler + base models + TOPSIS α.

    Host numpy 1.26 cannot unpickle GBDT BitGenerator state from the Windows
    Anaconda training env; if any alpha-weighted base model fails to load, fall
    back to a numpy2 venv helper (``/tmp/tcf_np2_venv``) when available.
    """
    patch_numpy_joblib()
    md = P.mimic_tcf
    summary = json.loads((md / "tcf_summary.json").read_text(encoding="utf-8"))
    feats = list(summary.get("features") or features)
    missing = [f for f in feats if f not in df.columns]
    if missing:
        raise RuntimeError(f"train/score frame missing TCF features: {missing}")
    alpha = pd.Series(summary["alpha"], dtype=float)
    need = [str(m) for m in alpha.index]
    scaler = joblib.load(md / "minmax_scaler.joblib")
    X = df[feats].astype(float).to_numpy()
    Xs = scaler.transform(X)
    proba = {}
    load_errs = []
    for name in need:
        path = md / f"model_{name}.joblib"
        if not path.exists():
            load_errs.append(f"{name}: missing file")
            continue
        try:
            clf = joblib.load(path)
            proba[name] = clf.predict_proba(Xs)[:, 1]
        except Exception as e:
            load_errs.append(f"{name}: {e}")
    if load_errs or set(proba.keys()) != set(need):
        np2 = Path("/tmp/tcf_np2_venv/bin/python")
        if np2.exists():
            print(
                f"[fig6] local model load incomplete ({'; '.join(load_errs)}); "
                f"retry via {np2}"
            )
            return _predict_tcf_proba_via_np2_venv(P, df, feats)
        raise RuntimeError(
            "Incomplete base-model load for TCF train scoring and no "
            f"/tmp/tcf_np2_venv; errs={load_errs}"
        )
    alpha = alpha.reindex(list(proba.keys())).fillna(0.0)
    alpha = alpha / float(alpha.sum())
    p = np.zeros(len(df), dtype=float)
    for m, a in alpha.items():
        p = p + float(a) * np.asarray(proba[m], dtype=float)
    return p


def _predict_tcf_proba_via_np2_venv(
    P: StudyPaths, df: pd.DataFrame, feats: list[str]
) -> np.ndarray:
    """Score via ephemeral numpy2 venv (GBDT pickle needs numpy._core BitGenerator)."""
    import tempfile

    np2 = Path("/tmp/tcf_np2_venv/bin/python")
    if not np2.exists():
        raise FileNotFoundError(np2)
    with tempfile.TemporaryDirectory(prefix="tcf_train_score_") as td:
        td_p = Path(td)
        csv_in = td_p / "frame.csv"
        csv_out = td_p / "proba.csv"
        df_out = df.loc[:, list(feats)].copy()
        # keep column order identical to training features
        df_out.to_csv(csv_in, index=False)
        helper = td_p / "score.py"
        helper.write_text(
            "\n".join(
                [
                    "import json, sys",
                    "from pathlib import Path",
                    "import joblib, numpy as np, pandas as pd",
                    "md, feats_csv, out_csv = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])",
                    "summary = json.loads((md/'tcf_summary.json').read_text())",
                    "feats = summary['features']",
                    "alpha = pd.Series(summary['alpha'], dtype=float)",
                    "scaler = joblib.load(md/'minmax_scaler.joblib')",
                    "frame = pd.read_csv(feats_csv)",
                    "Xs = scaler.transform(frame[feats].astype(float).to_numpy())",
                    "proba = {}",
                    "for name in alpha.index:",
                    "    clf = joblib.load(md/f'model_{name}.joblib')",
                    "    proba[name] = clf.predict_proba(Xs)[:,1]",
                    "alpha = alpha.reindex(list(proba.keys())).fillna(0.0)",
                    "alpha = alpha / alpha.sum()",
                    "p = np.zeros(len(frame))",
                    "for m,a in alpha.items():",
                    "    p = p + float(a)*proba[m]",
                    "pd.DataFrame({'prob': p}).to_csv(out_csv, index=False)",
                ]
            ),
            encoding="utf-8",
        )
        subprocess.check_call(
            [str(np2), str(helper), str(P.mimic_tcf), str(csv_in), str(csv_out)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return pd.read_csv(csv_out)["prob"].to_numpy(dtype=float)


def _resolve_tcf_train_proba(P: StudyPaths, data) -> np.ndarray:
    """Load proba_train/TCF.csv if present; else predict train with frozen TCF bundle."""
    cached = data.get("proba_tr_tcf")
    if cached is not None:
        return np.asarray(cached, dtype=float)
    candidates = [
        P.mimic_tcf / "proba_train" / "TCF.csv",
        P.mimic_tcf / "proba_train_TCF.csv",
        P.mimic_tcf / "_csv" / "proba_train_TCF.csv",
    ]
    for fp in candidates:
        if fp.exists():
            p = pd.read_csv(fp)["prob"].to_numpy(dtype=float)
            if len(p) != len(data["y_tr"]):
                raise RuntimeError(
                    f"train proba n={len(p)} != train y n={len(data['y_tr'])} ({fp})"
                )
            print(f"[fig6] using cached train TCF proba: {fp}")
            data["proba_tr_tcf"] = p
            return p
    print("[fig6] scoring Training set with frozen TCF models + scaler + α …")
    p = _predict_tcf_proba_on_frame(P, data["train"], data["features"])
    if len(p) != len(data["y_tr"]):
        raise RuntimeError("train TCF predict length mismatch")
    data["proba_tr_tcf"] = p
    return p


def build_fig6(P: StudyPaths, data, pdf_dir, md_dir, meta, gaps):
    """Wang 2025 Fig.6: 2×3 forest panels of TCF metrics across datasets.

    Paper layout (a)–(f): AUC / ACC / SPE / F1-score / PRE / SEN.
    Each panel = dataset rows (point + 95% CI whisker), vertical dashed reference
    at Internal Validation estimate, grey shade to the left (decline vs internal).
    Y-axis: Internal + Cohort 1 + Cohort 2 only（训练集表观 AUC≈1 不进主文 Fig6，
    仅留 Table S10 脚注披露）。
    """
    stem = FIGURE_SPECS["fig6"]
    old_stems = [
        "Figure 6. Bootstrap performance metrics across datasets",
    ]
    fig_roots = []
    if pdf_dir is not None:
        fig_roots.append(pdf_dir.parent)
    if getattr(P, "root_fig", None) is not None:
        fig_roots.append(P.root_fig)
    for base in fig_roots:
        for old_stem in old_stems:
            _unlink_figure_stem(old_stem, base)

    if "TCF" not in data["proba_v"] or "TCF" not in data["proba_e"]:
        gaps.append("Fig6: missing TCF proba on valid and/or external")
        return None

    try:
        strata = _resolve_eicu_unittype_cohorts(P, data)
    except Exception as e:
        gaps.append(f"Fig6 unittype strata failed: {e}")
        return None

    y_v = np.asarray(data["y_v"], dtype=int)
    y_e = np.asarray(data["y_e"], dtype=int)
    p_v = np.asarray(data["proba_v"]["TCF"], dtype=float)
    p_e = np.asarray(data["proba_e"]["TCF"], dtype=float)
    mask_c1 = strata["mask_c1"]
    mask_c2 = strata["mask_c2"]

    dataset_specs = [
        ("Internal Validation set", y_v, p_v, SEED_OFF_INTERNAL),
        ("Cohort 1", y_e[mask_c1], p_e[mask_c1], SEED_OFF_C1),
        ("Cohort 2", y_e[mask_c2], p_e[mask_c2], SEED_OFF_C2),
    ]
    # top → bottom positions
    y_pos = {name: float(len(dataset_specs) - 1 - i) for i, (name, *_rest) in enumerate(dataset_specs)}

    stats = {}
    for name, y, p, seed_off in dataset_specs:
        if len(y) < 5 or y.min() == y.max():
            gaps.append(f"Fig6: dataset {name} has insufficient outcome variation")
            return None
        stats[name] = _boot_metric_cis(
            y, p, n_boot=N_BOOT, seed=BOOT_SEED + int(seed_off), threshold=FIG6_THRESHOLD
        )
        stats[name]["_n"] = int(len(y))
        stats[name]["_events"] = int(y.sum())
        print(
            f"[fig6] {name}: n={stats[name]['_n']} events={stats[name]['_events']} "
            f"AUC={stats[name]['AUC']['est']:.3f} "
            f"({stats[name]['AUC']['lo']:.3f}–{stats[name]['AUC']['hi']:.3f})"
        )

    internal_name = "Internal Validation set"
    panel_order = FIG6_METRICS  # 6 panels → 2 cols × 3 rows row-major
    plt.rcParams.update(
        {
            "font.family": "serif",
            "font.serif": ["Times New Roman", "Times", "DejaVu Serif", "serif"],
            "axes.spines.right": False,
            "axes.spines.top": False,
        }
    )
    fig, axes = plt.subplots(3, 2, figsize=(10.0, 9.0), sharey=True)
    axes_flat = axes.ravel()

    # shared x-limits per column (left metrics often higher)
    col_ranges = {0: [], 1: []}
    for i, (mkey, _mtitle) in enumerate(panel_order):
        col = i % 2
        for name in stats:
            s = stats[name][mkey]
            col_ranges[col].extend([s["lo"], s["hi"], s["est"]])

    def _xlim_for_col(col: int):
        vals = np.asarray(col_ranges[col], dtype=float)
        vals = vals[np.isfinite(vals)]
        if len(vals) == 0:
            return (0.0, 1.05)
        lo = float(np.min(vals))
        hi = float(np.max(vals))
        pad = max(0.03, 0.08 * (hi - lo + 1e-9))
        # paper-like: left column often ~0.5–1 if scores high
        if col == 0 and lo >= 0.45:
            lo = min(lo, 0.50) - pad
            lo = max(0.40, lo)
        else:
            lo = max(0.0, lo - pad)
        hi = min(1.05, hi + max(pad, 0.04))
        if hi <= lo:
            hi = lo + 0.1
        return (lo, hi)

    xlims = {0: _xlim_for_col(0), 1: _xlim_for_col(1)}

    for i, (mkey, mtitle) in enumerate(panel_order):
        ax = axes_flat[i]
        col = i % 2
        panel_tag = f"({chr(ord('a') + i)})"
        ref = float(stats[internal_name][mkey]["est"])
        x0, x1 = xlims[col]
        # grey shade LEFT of internal reference (= scores worse than internal)
        shade_right = min(ref, x1)
        if shade_right > x0:
            ax.axvspan(x0, shade_right, color="#B0B0B0", alpha=0.28, zorder=0, lw=0)
        ax.axvline(ref, color="#666666", ls="--", lw=1.15, zorder=1)

        for name, *_rest in dataset_specs:
            s = stats[name][mkey]
            yp = y_pos[name]
            color = FIG6_DATASET_COLORS[name]
            lo_i, hi_i = float(s["lo"]), float(s["hi"])
            # Near-perfect Training CI collapses to a point; keep a tiny visible whisker
            if abs(hi_i - lo_i) < 0.008:
                mid = float(s["est"])
                lo_i, hi_i = mid - 0.004, mid + 0.004
            ax.hlines(
                yp, lo_i, hi_i, colors=color, lw=2.2, zorder=3, clip_on=False
            )
            ax.plot(
                s["est"],
                yp,
                "o",
                color=color,
                markersize=7.5,
                markeredgecolor="white",
                markeredgewidth=0.6,
                zorder=4,
                clip_on=False,
            )

        ax.set_xlim(x0, x1)
        # keep right-edge markers drawable outside axes box
        ax.set_clip_on(False)
        ax.set_ylim(-0.6, len(dataset_specs) - 0.4)
        ax.set_yticks([y_pos[n] for n, *_ in dataset_specs])
        ax.set_yticklabels([n for n, *_ in dataset_specs], fontsize=8)
        ax.set_title(f"{panel_tag} {mtitle}", fontsize=11, pad=6, loc="left")
        ax.set_xlabel("Evaluation scores (95% CI)", fontsize=9)
        ax.tick_params(axis="x", labelsize=8)
        ax.grid(False)

    fig.tight_layout(h_pad=1.4, w_pad=1.2)
    out = save_fig(fig, pdf_dir, stem)

    # point-estimate table for md + manifest
    table_lines = [
        "| Dataset | n | events | AUC | ACC | SPE | F1 | PRE | SEN |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    point_table = {}
    for name, *_rest in dataset_specs:
        row = {"n": stats[name]["_n"], "events": stats[name]["_events"]}
        cells = [name, str(row["n"]), str(row["events"])]
        for mkey, _ in FIG6_METRICS:
            est = stats[name][mkey]["est"]
            row[mkey] = {
                "est": est,
                "lo": stats[name][mkey]["lo"],
                "hi": stats[name][mkey]["hi"],
            }
            cells.append(f"{est:.3f}")
        point_table[name] = row
        table_lines.append("| " + " | ".join(cells) + " |")

    c2_units = ", ".join(
        f"{r.unittype} n={int(r.n)}"
        for r in strata["c2_unittype_counts"].itertuples(index=False)
    )
    write_md(
        md_dir,
        stem,
        [
            "Wang 2025 npj Digit Med Fig.6 风格：**2 列 × 3 行**森林/点-区间图（非八模型箱线）。",
            "面板顺序（与原文 caption）："
            "**(a) AUC**、**(b) ACC**、**(c) SPE**、**(d) F1-score**、**(e) PRE**、**(f) SEN**。",
            "纵轴数据集（自上而下，**3 行**；故意不绘 Training）："
            "**Internal Validation set**（MIMIC valid）、"
            f"**Cohort 1**（eICU `{strata['c1_label']}`）、"
            f"**Cohort 2**（eICU `{strata['c2_label']}`；组成：{c2_units}）。",
            "训练集融合预测 AUC≈1.000 为样本内表观乐观，**不进入 Figure 6**；"
            "仅在 Table S10 以 “apparent, in-sample” 行披露。",
            "unittype 分层与 Figure 5 共用 `_resolve_eicu_unittype_cohorts`。",
            "每点 = 全样本点估计；水平须 = bootstrap 95% CI"
            f"（n_boot={N_BOOT}; seed Internal={BOOT_SEED}+{SEED_OFF_INTERNAL}, "
            f"C1={BOOT_SEED}+{SEED_OFF_C1}, C2={BOOT_SEED}+{SEED_OFF_C2}；与 Table S10 锁同）。"
            f"分类阈值 **{FIG6_THRESHOLD}**（`prob >= thr`）。",
            "灰色虚线 = 该指标在 Internal Validation set 的点估计；"
            "虚线左侧浅灰阴影 = 相对内部验证下降的一侧。",
            "点估计表（三位小数）：",
            *table_lines,
            *footnote_common(),
        ],
        {**meta, "combined": True},
    )
    data["_fig6_stats"] = {
        "threshold": FIG6_THRESHOLD,
        "n_boot": N_BOOT,
        "seed": BOOT_SEED,
        "datasets": point_table,
        "cohort1_def": strata["c1_label"],
        "cohort2_def": strata["c2_label"],
        "internal_ref": {
            mkey: stats[internal_name][mkey]["est"] for mkey, _ in FIG6_METRICS
        },
    }
    return out


# ---- S1 schematic (Wang 2025 Supp Fig.1 vertical spine + right branches) ----
def build_s1(data, pdf_dir, md_dir, meta, gaps):
    """Vertical Wang-style feature-processing flowchart (our SA-AKI counts).

    Verified from feature_selection_tcf_audit / ALLVARS.log (success run):
      57 → miss>30% drop 2 (FreeCalcium, CRP) → 55
        → dual-DB intersect drop 20 → 35
        → Boolean mode>90% drop 2 (Hepatitis, Stroke) → 33
        → imputation already done upstream (logistic_mi, m=5)
        → |r|≥0.7 drop 3 (Hematocrit, Sodium, HR) → 30
        → entropy stepwise selected k=30 (path peak at end of pool)
    """
    import textwrap

    stem = FIGURE_SPECS["s1"]
    feats = list(data["features"])
    feat_labels = [display_label(f) for f in feats]
    feat_list = ", ".join(feat_labels)
    # wrap for wide final box (~full figure width); keep line count for height
    feat_wrapped = textwrap.fill(feat_list, width=92)
    n_feat_lines = feat_wrapped.count("\n") + 1
    final_text = f"30 variables:\n{feat_wrapped}"

    drops = data.get("corr_drops")
    if drops is not None and len(drops):
        drop_txt = "; ".join(
            f"{display_label(a)} vs {display_label(b)} (drop {display_label(d)})"
            for a, b, d in zip(drops["var_a"], drops["var_b"], drops["dropped"])
        )
    else:
        drop_txt = (
            "Hematocrit vs RBC (drop Hematocrit); "
            "Chloride vs Sodium (drop Sodium); "
            "Shock index vs Heart rate (drop Heart rate)"
        )

    # Main-spine (left) + right branches — Wang Supp Fig.1 pairing
    # Counts from feature_selection_tcf_audit (success ALLVARS).
    spine = [
        "calculation of missing rates for\n57 candidate variables",
        "remaining 35 variables, filtering discrete\nvariables with high mode agreement",
        "remaining 33 variables,\nimputing missing values",
        "calculate the correlation coefficient\nbetween each pair of the 33 variables",
        "3 groups of highly correlated variables,\nremaining 30 variables",
        final_text,
    ]
    branches = [
        (
            "deletion of 2 variables with a missingness\n"
            "rate higher than 30% (Free calcium, CRP);\n"
            "removal of 20 further variables with\n"
            "missingness >30% in either MIMIC or eICU\n"
            "(dual-database intersect → 35)"
        ),
        (
            "removal of 2 Boolean variables with over\n"
            "90% mode agreement (Hepatitis, Stroke)"
        ),
        (
            "multiple imputation by chained equations\n"
            "(logistic MI; m = 5), fitted on the\n"
            "training set"
        ),
        (
            "combinations with |r| ≥ 0.7, retaining the\n"
            "variable with higher univariate AUC;\n"
            "dropped Hematocrit, Sodium, Heart rate"
        ),
        (
            "variables were ranked based on entropy\n"
            "values and sequentially entered into the\n"
            "model; the path selected k = 30 (full pool)"
        ),
        None,  # final feature-list box: no right branch
    ]

    fill = "#d9eef5"
    edge = "#1a5f7a"
    # Taller canvas so final feature-list box sits clear of the entropy branch
    fig_w, fig_h = 7.0, 11.2
    plt.rcParams.update(
        {
            "font.family": "serif",
            "font.serif": ["Times New Roman", "Times", "Liberation Serif", "DejaVu Serif"],
            "mathtext.fontset": "stix",
        }
    )
    _font = {"fontname": "Times New Roman"}
    fig, ax = plt.subplots(figsize=(fig_w, fig_h))
    ax.set_xlim(0, 10.2)
    ax.set_ylim(0, 100)
    ax.axis("off")
    fig.patch.set_facecolor("white")
    ax.set_facecolor("white")

    n_spine = len(spine)
    # Vertical layout: top → bottom; final box lower with a larger preceding gap
    y_top = 97.0
    y_bot = 1.2
    final_h = max(16.0, 4.0 + 2.35 * (n_feat_lines + 1))
    remain = (y_top - y_bot) - final_h
    # Extra gap only before the final box (index n_spine-2 → last)
    n_pre = n_spine - 1
    gap_ratio_pre = 0.42
    gap_ratio_final = 0.95  # push last box further down / clear overlap
    gap_weight = gap_ratio_pre * (n_pre - 1) + gap_ratio_final
    unit = remain / (n_pre + gap_weight)
    heights = [unit] * n_pre + [final_h]
    gaps_y = [unit * gap_ratio_pre] * (n_pre - 1) + [unit * gap_ratio_final]
    centers = []
    y_cursor = y_top
    for i in range(n_spine):
        h = heights[i]
        cy = y_cursor - h / 2.0
        centers.append(cy)
        y_cursor = cy - h / 2.0
        if i < n_spine - 1:
            y_cursor -= gaps_y[i]

    spine_cx = 2.95
    spine_w = 4.35
    branch_cx = 7.95
    branch_w = 3.65
    final_cx = 5.1
    final_w = 9.2

    def _add_box(cx, cy, w, h, text, *, fs=7.2, bold_first=False, lw=1.35):
        x0, y0 = cx - w / 2.0, cy - h / 2.0
        box = FancyBboxPatch(
            (x0, y0),
            w,
            h,
            boxstyle="round,pad=0.012,rounding_size=0.12",
            facecolor=fill,
            edgecolor=edge,
            lw=lw,
            zorder=3,
        )
        ax.add_patch(box)
        if bold_first and "\n" in text:
            # Entire title+list block centered in the box (not stuck to the top)
            ax.text(
                cx,
                cy,
                text,
                ha="center",
                va="center",
                fontsize=fs,
                fontweight="bold",
                color="black",
                linespacing=1.45,
                zorder=4,
                multialignment="center",
                **_font,
            )
        else:
            ax.text(
                cx,
                cy,
                text,
                ha="center",
                va="center",
                fontsize=fs,
                color="black",
                linespacing=1.25,
                zorder=4,
                **_font,
            )

    # Draw spine + vertical arrows + right branches
    for i, (txt, br) in enumerate(zip(spine, branches)):
        h = heights[i]
        cy = centers[i]
        is_final = i == n_spine - 1
        box_cx = final_cx if is_final else spine_cx
        box_w = final_w if is_final else spine_w
        _add_box(
            box_cx,
            cy,
            box_w,
            h * 0.94,
            txt,
            fs=6.5 if is_final else 7.3,
            bold_first=is_final,
            lw=1.55 if is_final else 1.35,
        )
        if i < n_spine - 1:
            y_from = cy - h * 0.47
            next_is_final = i + 1 == n_spine - 1
            y_to = centers[i + 1] + heights[i + 1] * (0.47 if not next_is_final else 0.47)
            # Vertical arrow stays on spine column (even into final)
            ax.annotate(
                "",
                xy=(spine_cx, y_to),
                xytext=(spine_cx, y_from),
                arrowprops=dict(
                    arrowstyle="-|>",
                    color="black",
                    lw=1.15,
                    mutation_scale=12,
                ),
                zorder=2,
            )
            # Horizontal branch from mid of vertical connector
            if br is not None:
                y_mid = (y_from + y_to) / 2.0
                n_br_lines = br.count("\n") + 1
                br_h = max(unit * 0.9, 2.8 + 1.05 * n_br_lines)
                # Cap so adjacent branch boxes do not heavily overlap
                br_h = min(br_h, gaps_y[i] * 0.92 + unit * 0.25)
                _add_box(branch_cx, y_mid, branch_w, br_h, br, fs=6.3)
                ax.annotate(
                    "",
                    xy=(branch_cx - branch_w / 2.0 - 0.05, y_mid),
                    xytext=(spine_cx + spine_w / 2.0 + 0.05, y_mid),
                    arrowprops=dict(
                        arrowstyle="-|>",
                        color="black",
                        lw=1.05,
                        mutation_scale=11,
                    ),
                    zorder=2,
                )

    out = save_fig(fig, pdf_dir, stem)
    write_md(
        md_dir,
        stem,
        [
            "竖向主干 + 右侧分支特征处理流程图（对齐 Wang 2025 Supplementary Fig. 1 版式；数字为本课题）。",
            "主干：57 候选缺失率计算 → 双库缺失对齐后 35 → 布尔众数>90% 后 33 → 插补说明 → "
            "33 变量两两相关 → 3 组高相关后剩余 30 → 最终 30 变量名单。",
            "右侧：缺失>30% 剔除 Free calcium、CRP（2）及双库再剔 20；布尔剔除 Hepatitis、Stroke（2）；"
            "插补为上游 logistic MI（m=5，训练集拟合），非论文「四法择优」；"
            f"|r|≥0.7 成对留高 AUC：{drop_txt}；熵权逐步路径峰在 k=30。",
            f"最终 30 特征（展示名）：{feat_list}。",
            "无独立「连续变量方差过滤」步骤；布尔近常数过滤已单独成框。插补发生在 FS 之前，图上按文献逻辑位置标注方法。",
            *footnote_common(),
        ],
        {**meta, "combined": False},
    )
    return out


# ---- S2 heatmap ----
def build_s2(data, pdf_dir, md_dir, meta, gaps):
    stem = FIGURE_SPECS["s2"]
    feats = data["features"]
    X = data["train"][feats].apply(pd.to_numeric, errors="coerce")
    corr = X.corr(method="pearson")
    labels = [display_label(f) for f in feats]
    fig, ax = plt.subplots(figsize=(9.5, 8.0))
    im = ax.imshow(corr.to_numpy(), cmap="RdBu_r", vmin=-1, vmax=1, aspect="equal")
    ax.set_xticks(range(len(labels)))
    ax.set_yticks(range(len(labels)))
    ax.set_xticklabels(labels, rotation=90, fontsize=6)
    ax.set_yticklabels(labels, fontsize=6)
    cbar = fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    cbar.set_label("Pearson r")
    ax.set_title("Pearson correlation of final 30 features (MIMIC train)")
    fig.tight_layout()
    out = save_fig(fig, pdf_dir, stem)
    write_md(
        md_dir,
        stem,
        [
            "本图为最终 30 个入模特征在 MIMIC 训练集上的 Pearson 相关热图（红正蓝负）。",
            "轴标签为去下划线展示名；数值矩阵来自 train.csv。",
            f"训练集 n={len(data['train'])}。",
            *footnote_common(),
        ],
        {**meta, "combined": False},
    )
    return out


# ---- Calibration ----
def plot_calibration_panel(ax, y, proba_dict, title, n_bins=10):
    ax.plot([0, 1], [0, 1], ls="--", color="#bbbbbb", lw=1, label="Ideal")
    for m in MODEL_ORDER:
        if m not in proba_dict:
            continue
        try:
            pt, pp = calibration_curve(y, proba_dict[m], n_bins=n_bins, strategy="quantile")
        except Exception:
            continue
        ax.plot(
            pp,
            pt,
            marker="o",
            ms=3.5,
            lw=1.4 if m == "TCF" else 1.0,
            color=MODEL_COLORS.get(m, "gray"),
            label=m,
        )
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.set_xlabel("Predicted probability")
    ax.set_ylabel("Observed frequency")
    ax.set_title(title)
    ax.legend(frameon=False, fontsize=7, loc="upper left", ncol=2)


def build_s3(data, pdf_dir, md_dir, meta, gaps):
    stem = FIGURE_SPECS["s3"]
    fig, ax = plt.subplots(figsize=(5.8, 5.2))
    plot_calibration_panel(ax, data["y_v"], data["proba_v"], "Internal calibration (MIMIC valid)")
    out = save_fig(fig, pdf_dir, stem)
    write_md(
        md_dir,
        stem,
        [
            "本图为 MIMIC 内部验证集上全部模型的校准曲线（分位分箱）；对角线为完美校准。",
            "TCF 曲线加粗；概率来自 proba_valid。",
            f"n={len(data['y_v'])}。",
            *footnote_common(),
        ],
        {**meta, "combined": False},
    )
    return out


def build_s6(data, pdf_dir, md_dir, meta, gaps):
    stem = FIGURE_SPECS["s6"]
    fig, ax = plt.subplots(figsize=(5.8, 5.2))
    plot_calibration_panel(ax, data["y_e"], data["proba_e"], "External calibration (eICU)")
    out = save_fig(fig, pdf_dir, stem)
    write_md(
        md_dir,
        stem,
        [
            "本图为 eICU 外验队列上 TCF 及全部可用子模型的校准曲线（分位分箱）。",
            "概率来自 Models/TCF_sklearn_external/proba_*.csv。",
            f"n={len(data['y_e'])}。",
            *footnote_common(),
        ],
        {**meta, "combined": False},
    )
    return out


# ---- DCA ----
def net_benefit(y, p, thresholds):
    y = np.asarray(y).astype(int)
    p = np.asarray(p).astype(float)
    n = len(y)
    out = []
    for t in thresholds:
        pred = (p >= t).astype(int)
        tp = ((pred == 1) & (y == 1)).sum()
        fp = ((pred == 1) & (y == 0)).sum()
        # NB = TP/n - FP/n * t/(1-t)
        if t >= 1:
            out.append(np.nan)
        else:
            out.append(tp / n - fp / n * (t / (1.0 - t)))
    return np.asarray(out)


def plot_dca(ax, y, p, title):
    thresholds = np.linspace(0.01, 0.99, 99)
    nb = net_benefit(y, p, thresholds)
    prevalence = y.mean()
    treat_all = prevalence - (1 - prevalence) * thresholds / (1 - thresholds)
    treat_none = np.zeros_like(thresholds)
    ax.plot(thresholds, nb, color="#000000", lw=2.0, label="TCF")
    ax.plot(thresholds, treat_all, color="#d62728", ls="--", lw=1.2, label="Treat all")
    ax.plot(thresholds, treat_none, color="#7f7f7f", ls=":", lw=1.2, label="Treat none")
    ax.set_xlim(0, 1)
    ymin = min(-0.05, float(np.nanmin(nb)) - 0.02)
    ax.set_ylim(ymin, max(0.35, float(np.nanmax(nb)) + 0.02))
    ax.set_xlabel("Threshold probability")
    ax.set_ylabel("Net benefit")
    ax.set_title(title)
    ax.legend(frameon=False, loc="upper right")


def build_s4(data, pdf_dir, md_dir, meta, gaps):
    stem = FIGURE_SPECS["s4"]
    if "TCF" not in data["proba_v"]:
        gaps.append("S4: missing proba_valid/TCF.csv")
        return None
    fig, ax = plt.subplots(figsize=(5.8, 4.6))
    plot_dca(ax, data["y_v"], data["proba_v"]["TCF"], "Internal DCA — TCF (MIMIC valid)")
    out = save_fig(fig, pdf_dir, stem)
    write_md(
        md_dir,
        stem,
        [
            "本图为 MIMIC 内部验证集上 TCF 的决策曲线：净获益随阈值概率变化；"
            "并对照 Treat all / Treat none。",
            f"TCF 内部 AUC={fmt_auc(data['metrics_v'].loc['TCF','AUC'])}；n={len(data['y_v'])}。",
            *footnote_common(),
        ],
        {**meta, "combined": False},
    )
    return out


def build_s7(data, pdf_dir, md_dir, meta, gaps):
    stem = FIGURE_SPECS["s7"]
    if "TCF" not in data["proba_e"]:
        gaps.append("S7: missing proba_TCF.csv on eICU")
        return None
    fig, ax = plt.subplots(figsize=(5.8, 4.6))
    plot_dca(ax, data["y_e"], data["proba_e"]["TCF"], "External DCA — TCF (eICU)")
    out = save_fig(fig, pdf_dir, stem)
    write_md(
        md_dir,
        stem,
        [
            "本图为 eICU 外验队列上 TCF 的决策曲线（α 冻结自 MIMIC）。",
            f"TCF 外验 AUC={fmt_auc(data['metrics_e'].loc['TCF','AUC'])}；n={len(data['y_e'])}。",
            *footnote_common(),
        ],
        {**meta, "combined": False},
    )
    return out


# ---------------------------------------------------------------------------
# Pub formats via R
# ---------------------------------------------------------------------------
def run_pub_formats(figures_dir: Path, meta: dict) -> None:
    r_code = f"""
suppressPackageStartupMessages({{
  source("{ENGINE_ROOT.as_posix()}/R/utils.R")
  source("{ENGINE_ROOT.as_posix()}/R/pub_figure_export.R")
}})
figures_dir <- "{figures_dir.as_posix()}"
meta <- list(
  exposure = "{meta.get('exposure', '30 dual-intersect features')}",
  outcome = "{meta.get('outcome', 'In-hospital death among SA-AKI')}",
  outcome_column = "y",
  grouping = "TCF multi-algorithm fusion",
  databases = c("MIMIC", "eICU"),
  combined = TRUE,
  n_by_db = c(MIMIC = {meta['n_by_db']['MIMIC']}, eICU = {meta['n_by_db']['eICU']}),
  n_total = {meta['n_total']}
)
cfg <- list(pub_figures = list(dpi = 600L, write_image_information = TRUE))
res <- pub_figure_ensure_formats(figures_dir, meta = meta, config = cfg, purge = TRUE)
st <- pub_figure_formats_status(figures_dir)
cat(sprintf("ok=%s stems=%s bad_dpi=%s missing_png=%s missing_tiff=%s\\n",
            isTRUE(st$ok), length(st$stems),
            length(st$bad_dpi %||% character(0)),
            length(st$missing_png %||% character(0)),
            length(st$missing_tiff %||% character(0))))
if (length(st$bad_dpi %||% character(0))) print(st$bad_dpi)
if (length(st$missing_png %||% character(0))) print(st$missing_png)
"""
    proc = subprocess.run(
        ["Rscript", "-e", r_code],
        capture_output=True,
        text=True,
        cwd=str(ENGINE_ROOT),
    )
    print(proc.stdout)
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        raise RuntimeError(f"pub_figure_ensure_formats failed: rc={proc.returncode}")


def mirror_figures(src: Path, dst: Path):
    if dst.resolve() == src.resolve():
        return
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def verify_auc_strings(data) -> list[str]:
    notes = []
    for m, p in data["proba_v"].items():
        recomputed = roc_auc_score(data["y_v"], p)
        file_v = float(data["metrics_v"].loc[m, "AUC"])
        if abs(recomputed - file_v) > 1e-9:
            notes.append(f"valid {m}: recomputed {recomputed} != file {file_v}")
        # string-level 3dp
        if fmt_auc(recomputed) != fmt_auc(file_v):
            notes.append(f"valid {m}: 3dp mismatch {fmt_auc(recomputed)} vs {fmt_auc(file_v)}")
    for m, p in data["proba_e"].items():
        recomputed = roc_auc_score(data["y_e"], p)
        file_v = float(data["metrics_e"].loc[m, "AUC"])
        if abs(recomputed - file_v) > 1e-9:
            notes.append(f"external {m}: recomputed {recomputed} != file {file_v}")
    return notes


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--success-root", type=Path, default=DEFAULT_SUCCESS)
    ap.add_argument("--skip-r", action="store_true", help="Skip pub_figure_ensure_formats")
    ap.add_argument("--skip-mirror", action="store_true")
    ap.add_argument(
        "--only",
        nargs="+",
        default=None,
        help="Rebuild only these roles (e.g. Fig1). Default: all Fig1–6 + S1–S7.",
    )
    args = ap.parse_args()

    setup_mpl()
    patch_numpy_joblib()
    P = StudyPaths(args.success_root.resolve())
    if not P.mimic_tcf.exists():
        raise SystemExit(f"Missing MIMIC TCF dir: {P.mimic_tcf}")

    print(f"[info] success root: {P.success}")
    data = load_bundle(P)
    print(f"[info] features={len(data['features'])} train={len(data['train'])} "
          f"valid={len(data['valid'])} external={len(data['external'])}")
    print(f"[info] best tree by internal AUC: {pick_best_tree_model(data['metrics_v'])}")

    auc_notes = verify_auc_strings(data)
    if auc_notes:
        print("[warn] AUC mismatches:")
        for n in auc_notes:
            print(" ", n)
    else:
        print("[info] proba AUCs match metrics CSV")

    meta = {
        "exposure": "30 dual-intersect clinical and laboratory features (ALLVARS)",
        "outcome": "28-day all-cause death among sepsis-associated AKI",
        "grouping": "TCF multi-algorithm fusion (TOPSIS alphas frozen from MIMIC)",
        "databases": ["MIMIC", "eICU"],
        "n_by_db": {
            "MIMIC": int(len(data["train"]) + len(data["valid"])),
            "eICU": int(len(data["external"])),
        },
        "n_total": int(len(data["train"]) + len(data["valid"]) + len(data["external"])),
        "combined": False,
    }

    pdf_dir = P.summary_fig / "pdf"
    md_dir = P.summary_fig / "image_information"
    pdf_dir.mkdir(parents=True, exist_ok=True)
    md_dir.mkdir(parents=True, exist_ok=True)

    only = {str(x).strip() for x in (args.only or []) if str(x).strip()}
    # Clear PDFs/md only when full rebuild; --only keeps other figures
    if not only:
        for old in pdf_dir.glob("Figure*.pdf"):
            old.unlink()
        for old in md_dir.glob("Figure*.md"):
            if old.name != "README.md":
                old.unlink()

    gaps: list[str] = []
    shap_cache: dict = {}
    generated = []

    builders = [
        ("Fig1", lambda: build_fig1(P, pdf_dir, md_dir, meta, gaps, data=data)),
        ("Fig2", lambda: build_fig2(data, pdf_dir, md_dir, meta, gaps)),
        ("Fig3", lambda: build_fig3(data, pdf_dir, md_dir, meta, gaps)),
        ("Fig4", lambda: build_fig4(P, data, pdf_dir, md_dir, meta, gaps, shap_cache)),
        ("Fig5", lambda: build_fig5(P, data, pdf_dir, md_dir, meta, gaps)),
        ("Fig6", lambda: build_fig6(P, data, pdf_dir, md_dir, meta, gaps)),
        ("S1", lambda: build_s1(data, pdf_dir, md_dir, meta, gaps)),
        ("S2", lambda: build_s2(data, pdf_dir, md_dir, meta, gaps)),
        ("S3", lambda: build_s3(data, pdf_dir, md_dir, meta, gaps)),
        ("S4", lambda: build_s4(data, pdf_dir, md_dir, meta, gaps)),
        ("S5", lambda: build_s5(data, pdf_dir, md_dir, meta, gaps, shap_cache)),
        ("S6", lambda: build_s6(data, pdf_dir, md_dir, meta, gaps)),
        ("S7", lambda: build_s7(data, pdf_dir, md_dir, meta, gaps)),
    ]
    if only:
        builders = [(n, fn) for n, fn in builders if n in only]
        if not builders:
            raise SystemExit(f"--only matched nothing: {sorted(only)}")

    for name, fn in builders:
        print(f"[build] {name} ...")
        try:
            path = fn()
            if path is not None:
                generated.append(path.name)
                print(f"  -> {path.name}")
            else:
                print(f"  -> SKIPPED")
        except Exception as e:
            gaps.append(f"{name}: {e}")
            print(f"  !! FAIL {e}")

    # Copy flat PDFs to Figures root temporarily for ensure_formats ingest
    for pdf in pdf_dir.glob("Figure*.pdf"):
        shutil.copy2(pdf, P.summary_fig / pdf.name)

    if not args.skip_r:
        print("[pub] running pub_figure_ensure_formats @600dpi ...")
        run_pub_formats(P.summary_fig, meta)
        # Re-write detailed md (ensure_formats preserve_md keeps pre-written; if missing, rewrite)
        # Our md were written before ensure; preserve_md=TRUE keeps them.
        # Remove flat leftovers
        for flat in P.summary_fig.glob("Figure*.pdf"):
            if flat.is_file():
                flat.unlink()

    # Drop legacy dual-panel / engine / renamed Fig5 stems
    legacy_stems = [
        "Figure 1. Flowchart",
        "Figure 1. Flowchart of the study population",
        "Figure 5. Dual-cohort ROC curves for TCF and base models",
        "Figure 6. Bootstrap performance metrics across datasets",
    ]
    for stem0 in legacy_stems:
        _unlink_figure_stem(stem0, P.summary_fig, P.root_fig)

    if not args.skip_mirror:
        print(f"[mirror] {P.summary_fig} -> {P.root_fig}")
        mirror_figures(P.summary_fig, P.root_fig)

    manifest = {
        "generated": generated,
        "gaps": gaps,
        "auc_notes": auc_notes,
        "best_shap_model": shap_cache.get("best"),
        "shap_n": shap_cache.get("n_used"),
        "summary_figures": str(P.summary_fig),
        "n_features": len(data["features"]),
        "metrics_valid_TCF_AUC": fmt_auc(data["metrics_v"].loc["TCF", "AUC"]),
        "metrics_external_TCF_AUC": fmt_auc(data["metrics_e"].loc["TCF", "AUC"]),
        "fig5_legend": data.get("_fig5_legend"),
        "fig6_stats": data.get("_fig6_stats"),
    }
    man_path = P.success / "summary_results" / "Figures" / "_rebuild_wang2025_manifest.json"
    man_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(manifest, indent=2, ensure_ascii=False))
    print(f"[done] figures dir: {P.summary_fig}")
    return 0 if not gaps else 0  # gaps reported but non-fatal for partial


if __name__ == "__main__":
    raise SystemExit(main())
