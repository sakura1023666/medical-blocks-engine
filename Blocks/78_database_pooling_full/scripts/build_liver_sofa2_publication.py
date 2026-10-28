#!/usr/bin/env python3
"""Summary tables and figures for the early liver-dysfunction pooling run.

Main model keeps Allyn's feature list. A second arm drops total bilirubin only.
The seven-lab deletion is not included. Point estimates from the full test pass.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.patches import FancyBboxPatch

OUT_NAME = Path(os.environ.get(
    "LIVER_PUB_OUT",
    "/mnt/g/02block_result/48_ICU/database_pooled_liver_sofa2_42151996/summary_results",
))
QFILE = Path(os.environ.get("LIVER_QFILE", "/tmp/liver_train_q5q95.json"))

# Test metrics recomputed from test_predictions.csv (hourly AUROC, survivor MAPE).
MAIN = {
    "Amsterdam only": {
        "n_patients": 477,
        "amsterdam": (0.588, 111.841),
        "eicu": (0.506, 161.336),
        "hirid": (0.504, 196.914),
    },
    "MIMIC-IV only": {
        "n_patients": 4344,
        "mimic4": (0.805, 83.378),
        "eicu": (0.735, 178.890),
        "hirid": (0.815, 232.307),
    },
    "Transfer": {
        "n_patients": 477,
        "amsterdam": (0.731, 107.255),
        "eicu": (0.730, 132.804),
        "hirid": (0.671, 118.188),
    },
    "Pooling": {
        "n_patients": 4821,
        "amsterdam": (0.753, 102.133),
        "mimic4": (0.801, 82.215),
        "eicu": (0.732, 126.174),
        "hirid": (0.802, 144.678),
    },
}
NOBILI = {
    "Amsterdam only": {
        "n_patients": 477,
        "amsterdam": (0.601, 106.539),
        "eicu": (0.517, 145.374),
        "hirid": (0.512, 170.775),
    },
    "MIMIC-IV only": {
        "n_patients": 4344,
        "mimic4": (0.785, 80.637),
        "eicu": (0.728, 190.100),
        "hirid": (0.786, 211.487),
    },
    "Transfer": {
        "n_patients": 477,
        "amsterdam": (0.694, 104.350),
        "eicu": (0.692, 123.068),
        "hirid": (0.617, 100.968),
    },
    "Pooling": {
        "n_patients": 4821,
        "amsterdam": (0.760, 100.787),
        "mimic4": (0.778, 78.790),
        "eicu": (0.727, 130.690),
        "hirid": (0.779, 128.115),
    },
}
DB = {
    "amsterdam": "AmsterdamUMC",
    "mimic4": "MIMIC-IV",
    "eicu": "eICU",
    "hirid": "HiRID",
}


def _save_table(df: pd.DataFrame, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_excel(Path(str(path) + ".xlsx"), index=False)


def _write_fig(fig, out_root: Path, name: str):
    for kind, ext in (("pdf", "pdf"), ("png", "png"), ("tiff", "tiff")):
        d = out_root / "Figures" / kind
        d.mkdir(parents=True, exist_ok=True)
        target = d / f"{name}.{ext}"
        if ext == "pdf":
            fig.savefig(target, bbox_inches="tight")
        else:
            fig.savefig(target, dpi=600, bbox_inches="tight")
    plt.close(fig)


def _flow_box(ax, x, y, w, h, title, subtitle, face):
    ax.add_patch(
        FancyBboxPatch(
            (x, y), w, h,
            boxstyle="round,pad=0.012,rounding_size=0.08",
            facecolor=face, edgecolor="#243040", linewidth=0.7,
            mutation_aspect=0.6,
        )
    )
    ax.text(x + w / 2, y + h * 0.62, title, ha="center", va="center", fontsize=8.0, color="#1b2430")
    ax.text(x + w / 2, y + h * 0.28, subtitle, ha="center", va="center", fontsize=6.4, color="#3d4a5c")


def _arrow(ax, x, y0, y1):
    ax.annotate(
        "", xy=(x, y1), xytext=(x, y0),
        arrowprops=dict(arrowstyle="-|>", color="#243040", lw=0.8, mutation_scale=8),
    )


def _chip(ax, x, y, w, h, text, face):
    ax.add_patch(
        FancyBboxPatch(
            (x, y), w, h,
            boxstyle="round,pad=0.01,rounding_size=0.06",
            facecolor=face, edgecolor="#243040", linewidth=0.6,
        )
    )
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=7, color="#1b2430")


def make_fig1(out: Path):
    fig, axes = plt.subplots(1, 2, figsize=(11.6, 6.6), gridspec_kw={"width_ratios": [1.08, 1.15]})
    ink = "#1b2430"
    db = {"AmsterdamUMC": "#d7e6f5", "MIMIC-IV": "#f6dfd4", "eICU": "#dceee4", "HiRID": "#efe6c9"}
    ax = axes[0]
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis("off")
    ax.text(0.15, 9.65, "A", fontsize=13, fontweight="bold", color=ink)
    ax.text(0.7, 9.65, "Study pipeline", fontsize=11, color=ink)
    steps = [
        ("1  Early liver dysfunction", "First bilirubin at least 33 umol/L, age at least 18", "#d7e6f5"),
        ("2  Four ICU databases", "AmsterdamUMC, MIMIC-IV, eICU, HiRID", "#dceee4"),
        ("3  Patient-level split", "70 / 15 / 15, seed 974; eICU and HiRID are test only", "#efe6c9"),
        ("4  TPC model", "Hourly death and remaining stay, patience 5", "#f6dfd4"),
        ("5  Four training strategies", "Panel B. Full feature list, respiration off", "#e6e4f4"),
        ("6  External test", "Same eICU and HiRID stays for every strategy", "#e6e4f4"),
        ("7  Sensitivity", "Repeat after removing total bilirubin only", "#f7f3ea"),
    ]
    box_w, box_h = 8.7, 0.95
    x0, top, gap = 0.65, 8.85, 0.22
    for i, (title, sub, face) in enumerate(steps):
        y = top - i * (box_h + gap)
        _flow_box(ax, x0, y, box_w, box_h, title, sub, face)
        if i < len(steps) - 1:
            _arrow(ax, x0 + box_w / 2, y, y - gap + 0.02)

    ax = axes[1]
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis("off")
    ax.text(0.15, 9.65, "B", fontsize=13, fontweight="bold", color=ink)
    ax.text(0.7, 9.65, "Four training strategies", fontsize=11, color=ink)
    rows = [
        (7.35, "1", "AmsterdamUMC alone", [("AmsterdamUMC", 1.15, 2.15)], "Train 477 patients", "Test includes eICU, HiRID"),
        (5.35, "2", "MIMIC-IV alone", [("MIMIC-IV", 1.15, 1.7)], "Train 4,344 patients", "Test includes eICU, HiRID"),
        (3.35, "3", "Transfer: MIMIC-IV, then AmsterdamUMC", [("MIMIC-IV", 1.15, 1.7), ("AmsterdamUMC", 3.55, 2.15)], "Fine-tune 477 patients", "Full-layer fine-tune"),
        (1.05, "4", "Pooling in one training run", [("AmsterdamUMC", 1.15, 2.15), ("MIMIC-IV", 3.5, 1.7)], "Train 4,821 patients", "Test includes eICU, HiRID"),
    ]
    for y, num, name, chips, line1, line2 in rows:
        ax.add_patch(plt.Circle((0.48, y + 0.78), 0.26, facecolor="#243040", edgecolor="none"))
        ax.text(0.48, y + 0.78, num, ha="center", va="center", fontsize=8, color="white")
        ax.text(1.05, y + 1.28, name, ha="left", va="center", fontsize=8.4, color=ink)
        for src, cx, cw in chips:
            _chip(ax, cx, y + 0.48, cw, 0.4, src, db[src])
        if num == "3":
            ax.annotate(
                "", xy=(3.48, y + 0.68), xytext=(2.95, y + 0.68),
                arrowprops=dict(arrowstyle="-|>", color="#243040", lw=0.7, mutation_scale=7),
            )
        ax.text(1.05, y + 0.16, f"{line1}; {line2}", ha="left", va="center", fontsize=7, color="#3d4a5c")
    fig.tight_layout(pad=0.4)
    _write_fig(fig, out, "Figure 1. Study pipeline")


def make_fig2(out: Path) -> pd.DataFrame:
    order = ["Amsterdam only", "MIMIC-IV only", "Transfer", "Pooling"]
    sites = [("eicu", "eICU"), ("hirid", "HiRID")]
    rows = []
    for arm in order:
        for key, lab in sites:
            auc, mape = MAIN[arm][key]
            rows.append({"Training": arm, "Database": lab, "AUROC": auc, "MAPE": mape})
    tab = pd.DataFrame(rows)
    fig, axes = plt.subplots(1, 2, figsize=(9.2, 4.2))
    x = np.arange(len(order))
    width = 0.36
    colors = {"eICU": "#3d6b8c", "HiRID": "#c47b4a"}
    for ax, metric, title, ylim in (
        (axes[0], "AUROC", "Hourly mortality AUROC", (0.45, 0.90)),
        (axes[1], "MAPE", "Survivor remaining-stay MAPE", (80, 260)),
    ):
        for i, (lab, color) in enumerate(colors.items()):
            vals = [float(tab[(tab.Training == a) & (tab.Database == lab)][metric].iloc[0]) for a in order]
            ax.bar(x + (i - 0.5) * width, vals, width, label=lab, color=color)
        ax.set_xticks(x)
        ax.set_xticklabels(["Amsterdam\nalone", "MIMIC-IV\nalone", "Transfer", "Pooling"])
        ax.set_ylabel(title)
        ax.set_ylim(*ylim)
        ax.legend(frameon=False)
        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)
    fig.tight_layout()
    _write_fig(fig, out, "Figure 2. External performance")
    return tab


def table1() -> pd.DataFrame:
    rows = [
        ("AmsterdamUMC", 721, 681, 477, 102, 102, 60.0, 0.624, 4.38, 0.279),
        ("MIMIC-IV", 7771, 6204, 4344, 930, 930, 59.0, 0.625, 2.76, 0.280),
        ("eICU", 9286, 7881, 0, 0, 7881, 60.0, 0.627, 2.77, 0.159),
        ("HiRID", 1752, 1752, 0, 0, 1752, 65.0, 0.701, 1.95, 0.139),
    ]
    return pd.DataFrame(
        rows,
        columns=[
            "Database",
            "Stays",
            "Patients",
            "Train patients",
            "Validation patients",
            "Test patients",
            "Age median",
            "Sex code 1 proportion",
            "LOS days median",
            "ICU mortality",
        ],
    )


def _long(store: dict, analysis: str) -> pd.DataFrame:
    rows = []
    for arm, spec in store.items():
        for key, val in spec.items():
            if key == "n_patients":
                continue
            auc, mape = val
            kind = "External" if key in ("eicu", "hirid") else "Internal"
            rows.append(
                {
                    "Analysis": analysis,
                    "Training": arm,
                    "Train patients": spec["n_patients"],
                    "Evaluation": DB[key],
                    "Role": kind,
                    "Hourly mortality AUROC": round(auc, 3),
                    "Survivor MAPE": round(mape, 1),
                }
            )
    return pd.DataFrame(rows)


def table2() -> pd.DataFrame:
    rows = []
    for arm, train_db in (("Amsterdam only", "amsterdam"), ("MIMIC-IV only", "mimic4")):
        spec = MAIN[arm]
        ia, im = spec[train_db]
        ea = np.mean([spec["eicu"][0], spec["hirid"][0]])
        em = np.mean([spec["eicu"][1], spec["hirid"][1]])
        rows.append(
            {
                "Training": arm,
                "Task": "Mortality AUROC",
                "Internal": round(ia, 3),
                "External mean of eICU and HiRID": round(float(ea), 3),
                "Relative change percent": round((ea - ia) / ia * 100, 1),
                "Train patients": spec["n_patients"],
            }
        )
        rows.append(
            {
                "Training": arm,
                "Task": "Survivor MAPE",
                "Internal": round(im, 1),
                "External mean of eICU and HiRID": round(float(em), 1),
                "Relative change percent": round((em - im) / im * 100, 1),
                "Train patients": spec["n_patients"],
            }
        )
    return pd.DataFrame(rows)


def table_s1() -> pd.DataFrame:
    if not QFILE.exists():
        return pd.DataFrame()
    payload = json.loads(QFILE.read_text())
    rows = []
    for block, prefix in (("q5", "Time series"), ("flat_q5", "Static")):
        for name, lo in payload.get(block, {}).items():
            hi_key = "q95" if block == "q5" else "flat_q95"
            rows.append(
                {
                    "Block": prefix,
                    "Variable": name.replace("_", " "),
                    "Train q5": lo,
                    "Train q95": payload.get(hi_key, {}).get(name),
                    "Clip": "-4 to 4",
                    "Fit sample": payload.get("n_sample"),
                }
            )
    return pd.DataFrame(rows)


def write_notes(out: Path, fig2: pd.DataFrame):
    note = out / "与原文的差别.md"
    lines = [
        "# 和原文的差别",
        "",
        "原文是 Allyn 等，Critical Care 2026，BlendedLoS。这一份是早期肝功能异常队列，不是原文的全体 ICU，也不是 2026-10-15 那个每库最多 640 次住院的缩小样本。",
        "",
        "## 队列",
        "",
        "- 入组：入 ICU 后第一次总胆红素至少 33 umol/L（SOFA 肝脏项至少 2），年龄至少 18 岁，ICU 停留长于 0.5 小时。缺失胆红素的停留排除，不用停留期间的最高值。",
        "- AmsterdamUMC 721 次停留、681 名患者；MIMIC-IV 7,771 / 6,204；eICU 9,286 / 7,881；HiRID 1,752 / 1,752。",
        "- 患者级划分，种子 974。AmsterdamUMC 训练 477、验证 102、测试 102 名患者。MIMIC-IV 为 4,344 / 930 / 930。eICU 和 HiRID 全部进入测试。",
        "- 评分从入院 5 小时之后开始。eICU 实际评分 9,210 次停留、1,444 例死亡；HiRID 1,746 次停留、240 例死亡。四个策略用的是同一批外部停留。",
        "",
        "## 模型和特征",
        "",
        "- 只有时间点卷积。没有 LSTM、Transformer，也没有训练规模扫描，所以没有原文 Figure 2 那种人数曲线。",
        "- 损失、标准化、早停和原文公开代码一致：二元交叉熵加 20 倍 MSLE；训练集第 5 和第 95 百分位；验证集连续 5 轮不提升即停；轮数上限 200。",
        "- 特征用原文事先点名的名单，呼吸机变量关闭。主分析保留总胆红素。敏感性分析只去掉总胆红素，其余肝化验仍在。",
        "- 迁移是 MIMIC-IV 预训练后在 AmsterdamUMC 上全层微调。",
        "- 表内是点估计，没有患者级 bootstrap 区间。",
        "",
        "## 主结果",
        "",
        "外部死亡 AUROC：MIMIC-IV 单源 eICU 0.735、HiRID 0.815；合并 eICU 0.732、HiRID 0.802。两条外部库上都没有拉开。",
        "外部存活者 MAPE：合并 eICU 126.2、HiRID 144.7；MIMIC-IV 单源 178.9 和 232.3。合并的住院时间误差更低。",
        "只去掉总胆红素后，eICU 合并 0.727 对 MIMIC-IV 单源 0.728，HiRID 0.779 对 0.786，结论不变，绝对判别略降。",
        "",
    ]
    note.write_text("\n".join(lines), encoding="utf-8")
    info = out / "Figures" / "image_information"
    info.mkdir(parents=True, exist_ok=True)
    (info / "Figure 1. Study pipeline.md").write_text(
        "# Figure 1\n\n## 图面说明\n\n"
        "A 是本队列的流程：第一次总胆红素至少 33 umol/L 定义早期肝功能异常，四个库，患者级 70/15/15，"
        "eICU 和 HiRID 只做测试，时间点卷积预测死亡和剩余住院时间，四种训练策略，最后一格是只去掉总胆红素的敏感性分析。\n\n"
        "B 是四种训练。AmsterdamUMC 单独训练 477 名患者，MIMIC-IV 单独训练 4,344 名患者，"
        "迁移先用 MIMIC-IV 再在 AmsterdamUMC 的 477 名患者上全层微调，合并训练 4,821 名患者。"
        "图上没有性能数字。\n\n## 分析上下文\n\n"
        "暴露不是一个化验指标，比较的是训练策略。结局是 ICU 死亡和存活者剩余住院时间。"
        "数据库是 AmsterdamUMC、MIMIC-IV、eICU、HiRID。这张图不是拼图。\n",
        encoding="utf-8",
    )
    bits = []
    for _, r in fig2.iterrows():
        bits.append(f"{r['Training']} on {r['Database']}: AUROC {r['AUROC']:.3f}, MAPE {r['MAPE']:.1f}")
    (info / "Figure 2. External performance.md").write_text(
        "# Figure 2\n\n## 图面说明\n\n"
        "左图是按小时计算的死亡 AUROC，右图是存活者剩余住院时间的 MAPE，越低越好。"
        "每个策略两根柱，分别是 eICU 和 HiRID，用的是同一批外部停留。\n\n"
        "图上标注：" + "；".join(bits) + "。\n\n## 分析上下文\n\n"
        "主分析保留全部特征，包括总胆红素。队列是早期肝功能异常。"
        "eICU 评分 9,210 次停留，HiRID 评分 1,746 次停留。没有做训练规模扫描。\n",
        encoding="utf-8",
    )


def main():
    out = OUT_NAME
    (out / "Tables").mkdir(parents=True, exist_ok=True)
    _save_table(table1(), out / "Tables" / "Table 1. Cohort characteristics")
    _save_table(table2(), out / "Tables" / "Table 2. Internal and external")
    main_long = _long(MAIN, "All features")
    _save_table(main_long, out / "Tables" / "Table 3. Four training strategies")
    sens = _long(NOBILI, "Bilirubin removed")
    _save_table(sens, out / "Tables" / "Table S1. Bilirubin removed")
    scale = table_s1()
    if not scale.empty:
        _save_table(scale, out / "Tables" / "Table S2. Scaling")
    compare = pd.DataFrame(
        [
            {
                "Study": "Allyn 2026, all-comer ICU",
                "Cohort": "About 19,573 stays in each database",
                "External mortality": "Pooling AUROC about 0.82 versus MIMIC-IV alone about 0.80",
                "External MAPE": "Pooling lower than MIMIC-IV alone",
            },
            {
                "Study": "This run, early liver dysfunction",
                "Cohort": "First bilirubin at least 33 umol/L",
                "External mortality": "Pooling 0.732 and 0.802 versus MIMIC-IV alone 0.735 and 0.815",
                "External MAPE": "Pooling 126.2 and 144.7 versus MIMIC-IV alone 178.9 and 232.3",
            },
        ]
    )
    _save_table(compare, out / "Tables" / "Table 4. Comparison with the paper")
    make_fig1(out)
    fig2 = make_fig2(out)
    _save_table(fig2, out / "Tables" / "Figure 2 data")
    write_notes(out, fig2)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
