"""shap_plot.py — 每天 SHAP 可解释性（迁移自 code/shap_5day.py）。

日级 + expand_hours 时，小时维无真实变化；热图改为「样本 × 特征」块状纹理
（Yang Fig4 观感），Y 轴为 Sample。【场景迁移】标注：非原文 Hour×Feature。
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


def _resolve_display_names(feat: list[str], project_root: Path | None = None) -> list[str]:
    try:
        repo = Path(__file__).resolve().parents[2]
        if str(repo) not in sys.path:
            sys.path.insert(0, str(repo))
        from run.two_stage_transformer_stroke.feature_display_names import map_feature_names

        mapping = None
        dict_csv = repo / "Baseline数据字典.csv"
        if project_root is not None:
            cand = Path(project_root) / "_shared/step02_column_mapping/column_mapping_log.csv"
            if cand.exists():
                mapping = cand
        if mapping is None:
            for p in [
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
        return list(feat)


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
    for c in range(1, D + 1):
        try:
            sv = shap.GradientExplainer(_CutoffWrap(model, c), bg).shap_values(ex)
            s = sv[1] if isinstance(sv, list) else (sv[..., -1] if sv.shape[-1] == 2 else sv)
            s = s.reshape(n_ex, D, H, F)
            n_keep = int(day_k_keep_count(c, D))
            mat = np.abs(s[:, :n_keep, :, :]).mean(axis=(1, 2))  # (n_ex, F)
            heatmaps[f"day{c}"] = mat.astype(np.float32)

            val_imp = mat.mean(0)
            order = np.argsort(val_imp)[::-1]
            top = order[: min(15, F)]
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
            print(f"[shap:{arch}] Day{c}: " + ", ".join(display[i] for i in top[:8]))

            import matplotlib

            matplotlib.use("Agg")
            from matplotlib import pyplot as plt
            import seaborn as sns

            fig, ax = plt.subplots(figsize=(11.5, 5.8), dpi=140)
            show = mat[:, top]
            col_max = np.maximum(show.max(axis=0, keepdims=True), 1e-12)
            show_n = show / col_max
            sns.heatmap(
                show_n,
                cmap="RdYlGn_r",
                vmin=0,
                vmax=1,
                xticklabels=[display[i] for i in top],
                yticklabels=False,
                cbar_kws={"label": "Relative |SHAP|"},
                ax=ax,
            )
            ax.set_title(f"Day-{c} visualization results", fontsize=12)
            ax.set_xlabel("")
            ax.set_ylabel("Sample")
            n_s = show_n.shape[0]
            ax.set_yticks(np.linspace(0.5, max(n_s - 0.5, 0.5), min(5, max(n_s, 1))))
            ax.set_yticklabels([str(int(round(x))) for x in np.linspace(1, n_s, min(5, max(n_s, 1)))])
            plt.setp(ax.get_xticklabels(), rotation=35, ha="right", fontsize=8)
            fig.text(
                0.5,
                0.02,
                "Prominently activated features: " + ", ".join(display[i] for i in top[:6]),
                ha="center",
                fontsize=8,
                style="italic",
                color="#1a237e",
            )
            fig.tight_layout(rect=[0, 0.06, 1, 1])
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
            **heatmaps,
        )
    print(f"[shap:{arch}] OK -> {path}")
    return rows
