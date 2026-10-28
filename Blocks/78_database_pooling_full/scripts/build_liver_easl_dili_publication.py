#!/usr/bin/env python3
"""Summary tables/figures for EASL/DILI liver gate (ALT>=200 or ALP>=230).

Writes the same artifact set as the prior liver/SOFA summary_results pack
(Figure 1–2, Table 1–4, S1–S2, Figure 2 data, 与原文的差别.md).
Point estimates from metrics_multitask.csv (last test epoch).
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
    "/mnt/g/02block_result/50_Cirrhosis/database_pooled_42151996/summary_results",
))
QFILE = Path(os.environ.get("LIVER_QFILE", "/tmp/easl_train_q5q95.json"))

# Last-epoch test metrics (hourly AUROC, survivor MAPE) from Output_noenzyme.
MAIN = {
    "Amsterdam only": {
        "n_patients": 857,
        "amsterdam": (0.662, 109.384),
        "eicu": (0.664, 128.090),
        "hirid": (0.694, 203.877),
    },
    "MIMIC-IV only": {
        "n_patients": 4186,
        "mimic4": (0.802, 83.459),
        "eicu": (0.702, 163.715),
        "hirid": (0.751, 132.690),
    },
    "Transfer": {
        "n_patients": 857,
        "amsterdam": (0.705, 111.896),
        "eicu": (0.704, 127.353),
        "hirid": (0.734, 118.064),
    },
    "Pooling": {
        "n_patients": 5043,
        "amsterdam": (0.711, 114.983),
        "mimic4": (0.787, 87.284),
        "eicu": (0.723, 131.458),
        "hirid": (0.780, 133.577),
    },
}
# No separate all-features arm was trained; S1 documents the primary drop of
# inclusion enzymes (ALT + ALP) with the same numeric grid for pack parity.
SENS = {k: dict(v) for k, v in MAIN.items()}

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
        ("1  EASL / DILI lab gate", "First ALT at least 200 or ALP at least 230 U/L", "#d7e6f5"),
        ("2  Four ICU databases", "AmsterdamUMC, MIMIC-IV, eICU, HiRID", "#dceee4"),
        ("3  Patient-level split", "70 / 15 / 15, seed 974; eICU and HiRID are test only", "#efe6c9"),
        ("4  TPC model", "Hourly death and remaining stay, patience 5", "#f6dfd4"),
        ("5  Four training strategies", "Panel B. Drop ALT and ALP (inclusion labs)", "#e6e4f4"),
        ("6  External test", "Same eICU and HiRID stays for every strategy", "#e6e4f4"),
        ("7  Leakage control", "Inclusion enzymes removed from model inputs", "#f7f3ea"),
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
        (7.35, "1", "AmsterdamUMC alone", [("AmsterdamUMC", 1.15, 2.15)], "Train 857 patients", "Test includes eICU, HiRID"),
        (5.35, "2", "MIMIC-IV alone", [("MIMIC-IV", 1.15, 1.7)], "Train 4,186 patients", "Test includes eICU, HiRID"),
        (3.35, "3", "Transfer: MIMIC-IV, then AmsterdamUMC", [("MIMIC-IV", 1.15, 1.7), ("AmsterdamUMC", 3.55, 2.15)], "Fine-tune 857 patients", "Full-layer fine-tune"),
        (1.05, "4", "Pooling in one training run", [("AmsterdamUMC", 1.15, 2.15), ("MIMIC-IV", 3.5, 1.7)], "Train 5,043 patients", "Test includes eICU, HiRID"),
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
        (axes[0], "AUROC", "Hourly mortality AUROC", (0.55, 0.85)),
        (axes[1], "MAPE", "Survivor remaining-stay MAPE", (90, 220)),
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
    # Stays/patients from eligible; split persons from extraction; age/LOS/mort from labels.
    rows = [
        ("AmsterdamUMC", 1290, 1223, 857, 183, 183, 60.0, 0.616, 3.67, 0.322),
        ("MIMIC-IV", 6866, 5980, 4186, 897, 897, 62.0, 0.577, 2.76, 0.285),
        ("eICU", 8927, 7978, 0, 0, 7978, 63.0, 0.544, 2.67, 0.199),
        ("HiRID", 2060, 2060, 0, 0, 2060, 65.0, 0.647, 1.79, 0.162),
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


def table_s2_scaling() -> pd.DataFrame:
    if not QFILE.exists():
        return pd.DataFrame()
    payload = json.loads(QFILE.read_text(encoding="utf-8"))
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
                    "Clip": payload.get("clip", "-4 to 4"),
                    "Fit sample": payload.get("n_sample"),
                }
            )
    return pd.DataFrame(rows)


def write_notes(out: Path, fig2: pd.DataFrame):
    note = out / "与原文的差别.md"
    lines = [
        "# 和原文的差别",
        "",
        "原文是 Allyn 等，Critical Care 2026，BlendedLoS（全体 ICU 入组）。",
        "这一份交付目录现在放的是 **EASL/DILI 实验室门控** 的早期肝损伤队列（首测 ALT≥200 U/L 或 ALP≥230 U/L），",
        "不是原文全体 ICU，也不是此前 SOFA 肝脏项 / 胆红素≥33 的那一版汇总。",
        "",
        "## 与原文图表一一对应（本包保留的文件）",
        "",
        "| 本包文件 | 对应原文角色 | 本队列怎么处理 |",
        "|---------|-------------|----------------|",
        "| Figure 1. Study pipeline | 原文 Figure 1 流程 + 四策略 | 面板 A 改成 EASL/DILI 入组；面板 B 人数换成本队列 |",
        "| Figure 2. External performance | 原文 Figure 2（训练规模曲线）的**外验对比槽位** | 本队列未做 1k–55k 规模扫描，故用四策略在 eICU/HiRID 的 AUROC 与 MAPE 柱图占位，文件名沿用交付包「Figure 2」 |",
        "| Table 1. Cohort characteristics | 原文各库基线 | 四库 stay/患者/划分/年龄/性别/LOS/病死率为本队列数字 |",
        "| Table 2. Internal and external | 原文内外部落差 | Amsterdam / MIMIC 单库：内部 vs 外验均值 |",
        "| Table 3. Four training strategies | 原文四策略主表 | 主分析：建模时去掉纳入用酶学（ALT、ALP） |",
        "| Table 4. Comparison with the paper | 对照原文结论 | 一行原文摘要 + 一行本队列外验 |",
        "| Table S1. Bilirubin removed | 原文/旧包敏感性（去胆红素） | **角色改写**：本队列主分析已去 ALT+ALP；无另跑「保留全部肝酶」臂，S1 用同名文件给出「纳入酶学已剔除」结果网格（与 Table 3 数值相同），避免交付缺表 |",
        "| Table S2. Scaling | 原文标准化分位 | 合并臂训练集 q5/q95（2000 抽样） |",
        "| Figure 2 data.xlsx | Figure 2 底层数据 | 与柱图一致 |",
        "| 与原文的差别.md | （交付说明） | 本文件 |",
        "",
        "## 队列",
        "",
        "- 入组：入 ICU 后第一次 ALT≥200 U/L（约 5×ULN，ULN=40）**或** 第一次 ALP≥230 U/L（约 2×ULN，ULN=115）；年龄≥18；ICU 停留>0.5 小时。依据 EASL 药物性肝损伤指南 / International DILI Expert Working Group 实验室门槛，移植到 ICU 首次化验。",
        "- AmsterdamUMC 1,290 次停留、1,223 名患者；MIMIC-IV 6,866 / 5,980；eICU 8,927 / 7,978；HiRID 2,060 / 2,060。合计 19,143 次停留、17,241 名患者。",
        "- 患者级划分，种子 974。AmsterdamUMC 训练 857、验证 183、测试 183 名患者。MIMIC-IV 为 4,186 / 897 / 897。eICU 与 HiRID 全部进入测试。",
        "- 评分从入院 5 小时之后开始。预测文件中可评分停留约 eICU 8,826、HiRID 2,042；标签层死亡 eICU 1,777 / HiRID 333。四个策略用同一批外部停留。",
        "- 数据质控：`Data_QC.md` 为 NO_BLOCKING_ISSUES；稀疏源 11 条保留。",
        "",
        "## 模型和特征",
        "",
        "- 只有时间点卷积（TPC）。没有 LSTM、Transformer，也没有原文 Figure 2 那种训练人数扫描。",
        "- 损失、标准化、早停与原文公开代码一致：二元交叉熵 + 20×MSLE；训练集第 5/95 百分位；验证集连续 5 轮不提升即停；轮数上限 200。",
        "- 特征用原文事先点名的名单，呼吸机变量关闭。**主分析去掉纳入用变量 ALT 与 ALP**（防纳入泄漏），其余肝化验（含胆红素）仍保留。",
        "- 迁移：MIMIC-IV 预训练后在 AmsterdamUMC 上全层微调。",
        "- 表内是点估计，没有患者级 bootstrap / DeLong 区间。",
        "",
        "## 主结果（外验）",
        "",
        "外部死亡 AUROC：MIMIC-IV 单源 eICU 0.702、HiRID 0.751；合并 eICU 0.723、HiRID 0.780（相对单源 **+0.021 / +0.029**）。",
        "外部存活者 MAPE：合并 eICU 131.5、HiRID 133.6；MIMIC-IV 单源 163.7 和 132.7（eICU 合并明显更低，HiRID 近持平）。",
        "相对此前 SOFA≥2 / 胆红素门控：本队列是目前各肝门控里 **死亡外验合并优势最清楚** 的一套。",
        "",
        "## 刻意不做 / 与原文不一致处（摘要）",
        "",
        "1. 入组不是全体 ICU，是 EASL/DILI 酶学门控子集。",
        "2. 无训练规模曲线；Figure 2 改为外验四策略柱图（与旧肝功能异常交付包一致）。",
        "3. 无 LSTM / Transformer / 多模型对比。",
        "4. 未另跑「保留 ALT+ALP」对照；S1 文件名沿用旧包「Bilirubin removed」槽位，内容改为纳入酶学剔除说明。",
        "5. 无 10,000 次 bootstrap 与 DeLong。",
        "",
    ]
    note.write_text("\n".join(lines), encoding="utf-8")

    info = out / "Figures" / "image_information"
    info.mkdir(parents=True, exist_ok=True)
    (info / "Figure 1. Study pipeline.md").write_text(
        "# Figure 1\n\n## 图面说明\n\n"
        "A 是本队列流程：EASL/DILI 实验室门控（首测 ALT≥200 或 ALP≥230），四个 ICU 库，"
        "患者级 70/15/15（种子 974），eICU 与 HiRID 只做测试，时间点卷积同时预测死亡与剩余住院时间，"
        "四种训练策略，建模时去掉纳入用 ALT 与 ALP。\n\n"
        "B 是四种训练。AmsterdamUMC 单独训练 857 名患者，MIMIC-IV 单独训练 4,186 名患者，"
        "迁移先用 MIMIC-IV 再在 AmsterdamUMC 的 857 名患者上全层微调，合并训练 5,043 名患者。"
        "图上没有性能数字。\n\n## 分析上下文\n\n"
        "比较的是训练策略，不是单一化验暴露。结局是 ICU 死亡和存活者剩余住院时间。"
        "数据库是 AmsterdamUMC、MIMIC-IV、eICU、HiRID。\n",
        encoding="utf-8",
    )
    bits = []
    for _, r in fig2.iterrows():
        bits.append(f"{r['Training']} on {r['Database']}: AUROC {r['AUROC']:.3f}, MAPE {r['MAPE']:.1f}")
    (info / "Figure 2. External performance.md").write_text(
        "# Figure 2\n\n## 图面说明\n\n"
        "左图是按小时计算的死亡 AUROC，右图是存活者剩余住院时间的 MAPE（越低越好）。"
        "每个策略两根柱，分别是 eICU 和 HiRID，同一批外部停留。\n\n"
        "图上标注：" + "；".join(bits) + "。\n\n## 分析上下文\n\n"
        "主分析已去掉 ALT 与 ALP。队列为 EASL/DILI 酶学门控。"
        "可评分停留约 eICU 8,826、HiRID 2,042。未做训练规模扫描；"
        "此图对应交付包 Figure 2 槽位（原文 Figure 2 为规模曲线）。\n",
        encoding="utf-8",
    )


def main():
    out = OUT_NAME
    # clear prior tables/figures names we own (keep folder)
    for sub in ("Tables", "Figures/pdf", "Figures/png", "Figures/tiff", "Figures/image_information"):
        d = out / sub
        d.mkdir(parents=True, exist_ok=True)

    _save_table(table1(), out / "Tables" / "Table 1. Cohort characteristics")
    _save_table(table2(), out / "Tables" / "Table 2. Internal and external")
    main_long = _long(MAIN, "ALT and ALP removed")
    _save_table(main_long, out / "Tables" / "Table 3. Four training strategies")
    # Keep legacy filename so the pack still has Table S1.*
    sens = _long(SENS, "ALT and ALP removed (primary; no separate all-feature arm)")
    _save_table(sens, out / "Tables" / "Table S1. Bilirubin removed")
    scale = table_s2_scaling()
    if scale.empty:
        raise SystemExit(f"missing scaling file: {QFILE}")
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
                "Study": "This run, EASL/DILI lab gate",
                "Cohort": "First ALT at least 200 or ALP at least 230 U/L; drop ALT and ALP in model",
                "External mortality": "Pooling 0.723 and 0.780 versus MIMIC-IV alone 0.702 and 0.751",
                "External MAPE": "Pooling 131.5 and 133.6 versus MIMIC-IV alone 163.7 and 132.7",
            },
        ]
    )
    _save_table(compare, out / "Tables" / "Table 4. Comparison with the paper")
    make_fig1(out)
    fig2 = make_fig2(out)
    _save_table(fig2, out / "Tables" / "Figure 2 data")
    write_notes(out, fig2)

    # inventory check
    need = [
        out / "Tables" / "Table 1. Cohort characteristics.xlsx",
        out / "Tables" / "Table 2. Internal and external.xlsx",
        out / "Tables" / "Table 3. Four training strategies.xlsx",
        out / "Tables" / "Table 4. Comparison with the paper.xlsx",
        out / "Tables" / "Table S1. Bilirubin removed.xlsx",
        out / "Tables" / "Table S2. Scaling.xlsx",
        out / "Tables" / "Figure 2 data.xlsx",
        out / "Figures" / "pdf" / "Figure 1. Study pipeline.pdf",
        out / "Figures" / "pdf" / "Figure 2. External performance.pdf",
        out / "Figures" / "png" / "Figure 1. Study pipeline.png",
        out / "Figures" / "png" / "Figure 2. External performance.png",
        out / "Figures" / "tiff" / "Figure 1. Study pipeline.tiff",
        out / "Figures" / "tiff" / "Figure 2. External performance.tiff",
        out / "Figures" / "image_information" / "Figure 1. Study pipeline.md",
        out / "Figures" / "image_information" / "Figure 2. External performance.md",
        out / "与原文的差别.md",
    ]
    missing = [str(p) for p in need if not p.exists() or p.stat().st_size == 0]
    if missing:
        raise SystemExit("missing: " + "; ".join(missing))
    print(f"wrote {out}")
    for p in need:
        print("OK", p.name, p.stat().st_size)


if __name__ == "__main__":
    main()
