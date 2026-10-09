"""shap_plot.py — 每天 SHAP 可解释性（迁移自 code/shap_5day.py）。

真小时数据（H>1，如 MIMIC AKI expand_hours=FALSE）：热图 Y=Hour、X=Top features（对齐 Yang Fig4）。
日级广播 / H=1：回退样本×特征矩阵，Y=Sample。【场景迁移】标注见输出 footnote。
展示名：step02 column mapping + Baseline 数据字典。
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from .dataloader import TSTDataset
from .model import build_model, day_k_keep_count

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# 文献 Fig4 热图标注（中英对照，写入 Fig2 / S1–S5）
SHAP_HEATMAP_LABELS = {
    "y_hour": "Hour (0–23)",
    "x_features": "Daily activated features",
    "cbar": "Relative strength (Green → Yellow → Red)",
    "interpret": (
        "Which features the model considers more important at which hours on that day "
        "(mean |SHAP| over explained patients; global color scale)."
    ),
    "title_day": "Day-{c} visualization results",
    "title_fig2": "Daily feature visualization heatmaps (SHAP)",
}


def hour_yticks(H: int) -> tuple[list[float], list[str]]:
    """Y 轴刻度：覆盖 0–23（或 H-1）。"""
    if H <= 1:
        return [0.5], ["0"]
    step = 2 if H >= 24 else 1
    ticks = list(range(0, H, step))
    if ticks[-1] != H - 1:
        ticks.append(H - 1)
    return [t + 0.5 for t in ticks], [str(t) for t in ticks]


def normalize_heatmap(show: np.ndarray, *, method: str = "global") -> np.ndarray:
    """Yang Fig4 用**全图统一 0–1 色标**（相对全局 max / P99），非按列 max。

    按列归一化会把「小时内变化小」的特征整列刷红（AKI 真小时 SHAP 常见），
    与文献 patchy 绿–黄–红 观感不符。
    """
    show = np.asarray(show, dtype=np.float64)
    if show.size == 0:
        return show
    if method == "column":
        denom = np.maximum(show.max(axis=0, keepdims=True), 1e-12)
    else:
        vmax = float(np.percentile(show, 99))
        denom = max(vmax, 1e-12)
    return np.clip(show / denom, 0.0, 1.0)


def _resolve_display_names(feat: list[str], project_root: Path | None = None) -> list[str]:
    try:
        repo = Path(__file__).resolve().parents[2]
        scripts = repo / "Blocks" / "71_two_stage_transformer_stroke" / "scripts"
        if str(scripts) not in sys.path:
            sys.path.insert(0, str(scripts))
        from feature_display_names import map_feature_names

        mapping = None
        dict_csv = repo / "Baseline数据字典.csv"
        if project_root is not None:
            cand = Path(project_root) / "_shared/step02_column_mapping/column_mapping_log.csv"
            if cand.exists():
                mapping = cand
        if mapping is None:
            for p in [
                Path("/mnt/g/02block_result/33_AKI/two_stage_transformer_40041421"),
                Path(r"G:/02block_result/33_AKI/two_stage_transformer_40041421"),
                Path("/mnt/g/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
                Path(r"G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
            ]:
                cand = p / "_shared/step02_column_mapping/column_mapping_log.csv"
                if cand.exists():
                    mapping = cand
                    break
        return map_feature_names(feat, mapping, dict_csv if dict_csv.exists() else None)
    except Exception as e:
        print(f"[shap] display-name mapping fallback: {e}")
        return [str(x).replace("_", " ") for x in feat]


class _CutoffWrap(nn.Module):
    def __init__(self, model, cutoff):
        super().__init__()
        self.model = model
        self.cutoff = cutoff

    def forward(self, x):
        return self.model(x, torch.ones(x.shape[0], x.shape[1], device=x.device), self.cutoff)


def run_shap(
    data_dir: str,
    out_dir: str,
    model_path: str,
    arch: str = "b",
    split: str = "test",
    n_background: int = 25,
    n_explain: int = 40,
    project_root: str | None = None,
) -> list[dict]:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    ds = TSTDataset(split, data_dir)
    D, H, F = ds.n_days, ds.n_hours, ds.n_features
    feat = ds.feature_names
    display = _resolve_display_names(feat, Path(project_root) if project_root else None)

    model = build_model(arch, D, H, F).to(device)
    state = torch.load(model_path, map_location=device)
    model.load_state_dict(state)
    model.eval()

    los = ds.day_mask.sum(1).astype(int)
    sel_d = np.where(los >= D)[0]
    if len(sel_d) < 5:
        print(f"[shap:{arch}] los>=D 患者不足({len(sel_d)}),跳过")
        return []
    Xf = torch.tensor(ds.X[sel_d]).float().to(device)
    n_bg = min(n_background, max(1, len(Xf) // 2))
    n_ex = min(n_explain, len(Xf) - n_bg)
    if n_ex <= 0:
        print(f"[shap:{arch}] 样本不足以拆分背景/解释集,跳过")
        return []
    bg, ex = Xf[:n_bg], Xf[n_bg : n_bg + n_ex]

    rows: list[dict] = []
    try:
        import shap
    except ImportError:
        print(f"[shap:{arch}] 未安装 shap,跳过(pip install shap)")
        return []

    heatmaps: dict[str, np.ndarray] = {}
    use_hour_layout = int(H) > 1
    for c in range(1, D + 1):
        try:
            sv = shap.GradientExplainer(_CutoffWrap(model, c), bg).shap_values(ex)
            s = sv[1] if isinstance(sv, list) else (sv[..., -1] if sv.shape[-1] == 2 else sv)
            s = s.reshape(n_ex, D, H, F)
            n_keep = int(day_k_keep_count(c, D))
            s_abs = np.abs(s[:, :n_keep, :, :])
            if use_hour_layout:
                # 文献 Fig4：截止 Day-c 的 ICU 日（末 kept day）× 24h × top features
                mat = s_abs[:, -1, :, :].mean(axis=0)  # (H, F)
                layout = "hour_feature"
            else:
                mat = s_abs.mean(axis=(1, 2))  # (n_ex, F)
                layout = "sample_feature"
            heatmaps[f"day{c}"] = mat.astype(np.float32)

            val_imp = mat.mean(0)
            n_top = min(24 if layout == "hour_feature" else 15, F)
            order = np.argsort(val_imp)[::-1]
            top = order[:n_top]
            for rank, i in enumerate(top):
                rows.append(
                    {
                        "day": c,
                        "rank": rank + 1,
                        "feature": feat[i],
                        "feature_display": display[i],
                        "mean_abs_shap": round(float(val_imp[i]), 6),
                    }
                )
            print(f"[shap:{arch}] Day{c} ({layout}): " + ", ".join(display[i] for i in top[:8]))

            import matplotlib

            matplotlib.use("Agg")
            from matplotlib import pyplot as plt
            import seaborn as sns

            fig, ax = plt.subplots(figsize=(14.0 if layout == "hour_feature" else 11.5, 6.2), dpi=140)
            if layout == "hour_feature":
                show = mat[:, top]
                hour_labels = [str(h) for h in range(H)]
            else:
                show = mat[:, top]
                hour_labels = None
            show_n = normalize_heatmap(show, method="global")
            yticks, yticklabels = hour_yticks(H) if layout == "hour_feature" else ([], [])
            sns.heatmap(
                show_n,
                cmap="RdYlGn_r",
                vmin=0,
                vmax=1,
                xticklabels=[display[i] for i in top],
                yticklabels=yticklabels if layout == "hour_feature" else False,
                linewidths=0.35,
                linecolor="#cccccc",
                cbar_kws={"label": SHAP_HEATMAP_LABELS["cbar"]},
                ax=ax,
            )
            if layout == "hour_feature":
                ax.set_yticks(yticks)
                ax.set_yticklabels(yticklabels, fontsize=8)
                ax.set_ylabel(SHAP_HEATMAP_LABELS["y_hour"], fontsize=9)
                ax.set_xlabel(SHAP_HEATMAP_LABELS["x_features"], fontsize=9)
            else:
                ax.set_ylabel("Sample")
                ax.set_xlabel("")
            ax.set_title(SHAP_HEATMAP_LABELS["title_day"].format(c=c), fontsize=12, loc="center", pad=8)
            if layout == "sample_feature":
                n_s = show_n.shape[0]
                ax.set_yticks(np.linspace(0.5, max(n_s - 0.5, 0.5), min(5, max(n_s, 1))))
                ax.set_yticklabels([str(int(round(x))) for x in np.linspace(1, n_s, min(5, max(n_s, 1)))])
            plt.setp(ax.get_xticklabels(), rotation=35, ha="right", fontsize=8)
            foot = "Prominently activated features: " + ", ".join(display[i] for i in top[:6])
            if layout == "hour_feature":
                foot += "\n" + SHAP_HEATMAP_LABELS["interpret"]
            # 底边加宽：斜标签 + xlabel + 脚注分层，避免叠字
            fig.subplots_adjust(left=0.08, right=0.92, top=0.90, bottom=0.22)
            fig.text(
                0.5,
                0.02,
                foot,
                ha="center",
                va="bottom",
                fontsize=7.5,
                style="italic",
                color="#1a237e",
                wrap=True,
            )
            fig.savefig(out_dir / f"shap_{arch}_day{c}.png", dpi=140)
            plt.close(fig)
        except Exception as e:
            print(f"[shap:{arch}] Day{c} SHAP 失败: {e}")

    path = out_dir / "Table_TST_SHAP_Importance.csv"
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(
            f, fieldnames=["day", "rank", "feature", "feature_display", "mean_abs_shap"]
        )
        w.writeheader()
        w.writerows(rows)
    if heatmaps:
        np.savez(
            out_dir / f"shap_{arch}_heatmaps.npz",
            feature_raw=np.array(feat),
            feature_display=np.array(display),
            heatmap_layout=np.array("hour_feature" if use_hour_layout else "sample_feature"),
            heatmap_norm=np.array("global"),
            n_hours=np.array(int(H)),
            **heatmaps,
        )
    print(f"[shap:{arch}] OK -> {path}")
    return rows
