#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""老师汇报 PDF：S10–S14（Model1 RCS 切点）。左对齐；无课题代码/粗率提示/结论节/数据来源。

切点模式：环境变量 PV2_RCS_CUT_MODE=model1_min（默认）| model1_hr1
"""
from __future__ import annotations

import os
from pathlib import Path

import pandas as pd
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

OUT_ROOT = Path(
    "/mnt/g/02block_result/49_Dyslipidemia/prognosis_v2_mainval_41904528（00）/summary_results"
)
OUTS = [
    OUT_ROOT / "RCS切点补充分析汇报_S10_S12_S13_S14.pdf",
    Path("/mnt/e/01block/01Block-new-Final/workspace/RCS切点补充分析汇报_S10_S12_S13_S14.pdf"),
]
WIN_PATH = r"G:\02block_result\49_Dyslipidemia\prognosis_v2_mainval_41904528（00）\summary_results\RCS切点补充分析汇报_S10_S12_S13_S14.pdf"
CUT_MODE = os.environ.get("PV2_RCS_CUT_MODE", "model1_min").strip().lower() or "model1_min"


def find_ckpt() -> Path:
    # Prefer live summary_results/checkpoints (Model1-cut reruns write here).
    # delivery_workspace stamps are fallback only — do not shadow newer live CSVs.
    cands = [OUT_ROOT / "checkpoints"]
    ws = Path(str(OUT_ROOT) + "_delivery_workspace")
    if ws.exists():
        stamps = sorted(
            [p for p in ws.iterdir() if p.is_dir()],
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        for s in stamps:
            for c in (s / "checkpoints", s):
                if (c / "Table S10. RCS cutoffs.csv").exists():
                    cands.append(c)
    for c in cands:
        if (c / "Table S10. RCS cutoffs.csv").exists() and (
            c / "Table S12. RCS cutoff Cox PAR.csv"
        ).exists():
            return c
    raise FileNotFoundError("checkpoint CSVs not found")


def register_font() -> str:
    paths = [
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
        "/usr/share/fonts/truetype/arphic/uming.ttc",
        "C:/Windows/Fonts/msyh.ttc",
        "C:/Windows/Fonts/simhei.ttf",
    ]
    for fp in paths:
        if not os.path.exists(fp):
            continue
        for idx in (0, None):
            try:
                if idx is None:
                    pdfmetrics.registerFont(TTFont("CJK", fp))
                else:
                    pdfmetrics.registerFont(TTFont("CJK", fp, subfontIndex=idx))
                return "CJK"
            except Exception:
                continue
    return "Helvetica"


def fmt_p(p) -> str:
    try:
        p = float(p)
    except Exception:
        return ""
    if p < 0.001:
        return "<0.001"
    return f"{p:.3f}"


def sty(fname: str):
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "t", parent=base["Title"], fontName=fname, fontSize=13, leading=18, alignment=TA_CENTER, spaceAfter=10
        ),
        "h": ParagraphStyle(
            "h", parent=base["Heading2"], fontName=fname, fontSize=11, leading=15, alignment=TA_LEFT, spaceBefore=8, spaceAfter=4
        ),
        "b": ParagraphStyle(
            "b", parent=base["BodyText"], fontName=fname, fontSize=9.5, leading=14, alignment=TA_LEFT, spaceAfter=4
        ),
        "small": ParagraphStyle(
            "s", parent=base["BodyText"], fontName=fname, fontSize=8.5, leading=12, alignment=TA_LEFT, spaceAfter=3
        ),
    }


def tab(rows, widths, fname):
    t = Table(rows, colWidths=widths)
    t.setStyle(
        TableStyle(
            [
                ("FONTNAME", (0, 0), (-1, -1), fname),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
                ("BACKGROUND", (0, 0), (-1, 0), colors.Color(0.92, 0.92, 0.92)),
                ("GRID", (0, 0), (-1, -1), 0.4, colors.grey),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 3),
                ("RIGHTPADDING", (0, 0), (-1, -1), 3),
                ("TOPPADDING", (0, 0), (-1, -1), 2),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
            ]
        )
    )
    return t


def build(path: Path, cut, s10, s12, s13, s14, fname: str, cut_mode: str = "model1_min"):
    path.parent.mkdir(parents=True, exist_ok=True)
    s = sty(fname)
    story = []
    hr1 = cut_mode == "model1_hr1"
    if hr1:
        title = "血脂异常人群睡眠时长与全因死亡：RCS HR=1交叉切点补充分析（Table S10–S14）"
        lead = (
            "切点=Model1 RCS上最靠近7.5 h的HR=1交叉点（非最低风险点）。"
            "既往固定临床切点465 min（7.75 h）已弃用。"
            "本补充分析用各库Table S10 <b>Model 1（未调整）</b>nearest HR=1小时对睡眠时长做二分"
            "（&lt;切点 vs ≥切点），报告二元Cox、PAR、诊断增益与分层粗死亡率；"
            "不能替代主分析五分组（&lt;5 / 5–6 / 6–7 / 7–&lt;9 / ≥9 h）。"
            "Model 3切点仅在S10列出供对照，不用于定义二分暴露。"
            f" Windows路径：{WIN_PATH}"
        )
        cut_col = "Model1 HR=1交叉(h)"
        bin_note = "二元Cox（暴露：睡眠&lt;Model1 nearest HR=1切点）"
        h1 = "1. Table S10：RCS HR=1交叉切点与二元Cox"
    else:
        title = "血脂异常人群睡眠时长与全因死亡：RCS最低风险切点补充分析（Table S10–S14）"
        lead = (
            "既往固定临床切点465 min（7.75 h）已弃用。"
            "本补充分析改用各库Table S10 <b>Model 1（未调整）</b>RCS最低风险切点对睡眠时长做二分"
            "（&lt;切点 vs ≥切点），报告二元Cox、PAR、诊断增益与分层粗死亡率；"
            "不能替代主分析五分组（&lt;5 / 5–6 / 6–7 / 7–&lt;9 / ≥9 h）。"
            "Model 3切点仅在S10列出供对照，不用于定义二分暴露。"
            f" Windows路径：{WIN_PATH}"
        )
        cut_col = "Model1最低风险(h)"
        bin_note = "二元Cox（暴露：睡眠&lt;Model1最低风险切点）"
        h1 = "1. Table S10：RCS最低风险切点与二元Cox"

    story.append(Paragraph(title, s["title"]))
    story.append(Paragraph(lead, s["b"]))

    story.append(Paragraph(h1, s["h"]))
    m1_min = cut[cut["model"] == "Model 1"].set_index("database")["min_risk_hours"].to_dict()
    m1_hr1 = cut[cut["model"] == "Model 1"].set_index("database")["nearest_HR1_hours"].to_dict()
    m3 = cut[cut["model"] == "Model 3"].set_index("database")["min_risk_hours"].to_dict()
    role = {"NHANES": "主库", "SHHS": "主库", "CHARLS": "外验"}
    rows = [["队列", "角色", cut_col, "Model3最低风险(h，对照)", "二分所用"]]
    for db in ["NHANES", "SHHS", "CHARLS"]:
        if hr1:
            v = m1_hr1.get(db)
            if pd.isna(v):
                used = f"{m1_min[db]:.3f}（回退min-risk）"
            else:
                used = f"{float(v):.3f}"
        else:
            used = f"{m1_min[db]:.3f}"
        rows.append([db, role[db], used, f"{m3[db]:.3f}", "Model1"])
    story.append(tab(rows, [70, 50, 110, 120, 55], fname))
    story.append(Spacer(1, 6))
    story.append(Paragraph(bin_note, s["small"]))
    rows = [["队列", "模型", "N(死亡)", "HR (95% CI)", "P"]]
    for db in ["NHANES", "SHHS", "CHARLS"]:
        sub = s10[s10["database"] == db].reset_index(drop=True)
        for i, r in sub.iterrows():
            rows.append(
                [
                    db if i == 0 else "",
                    r["model"],
                    f"{int(r['n'])} ({int(r['deaths'])})",
                    str(r["HR (95% CI)"]),
                    fmt_p(r["P"]),
                ]
            )
    story.append(tab(rows, [70, 55, 85, 160, 50], fname))

    story.append(Paragraph("2. Table S12：同一切点下的患病率与PAR", s["h"]))
    rows = [["队列", "模型", "HR (95% CI)", "P", "暴露患病率", "PAR"]]
    for db in ["NHANES", "SHHS", "CHARLS"]:
        sub = s12[s12["database"] == db].reset_index(drop=True)
        for i, r in sub.iterrows():
            prev = f"{100 * float(r['expos_prev']):.1f}%" if pd.notna(r.get("expos_prev")) else ""
            par = f"{100 * float(r['PAR']):.1f}%" if pd.notna(r.get("PAR")) else ""
            rows.append([db if i == 0 else "", r["model"], str(r["HR (95% CI)"]), fmt_p(r["P"]), prev, par])
    story.append(tab(rows, [55, 50, 145, 45, 70, 45], fname))
    story.append(Paragraph("患病率三行相同为预期；PAR随各模型HR变化。主解读看Model 3。", s["small"]))

    story.append(Paragraph("3. Table S13：诊断增益（非筛查主张）", s["h"]))
    rows = [["队列", "切点(h)", "Sens", "Spec", "AUC", "额外检出死亡"]]
    for _, r in s13.iterrows():
        rows.append(
            [
                r["database"],
                f"{float(r['cutoff_hours']):.3f}",
                f"{float(r['sens']):.3f}",
                f"{float(r['spec']):.3f}",
                f"{float(r['AUC']):.3f}",
                f"{int(r['extra_deaths_by_short_sleep'])} ({100 * float(r['extra_rate_among_deaths']):.1f}%)",
            ]
        )
    story.append(tab(rows, [60, 60, 50, 50, 50, 120], fname))

    story.append(Paragraph("4. Table S14：年龄分层粗死亡率（摘录）", s["h"]))
    rows = [["队列", "分层", "睡眠", "N", "死亡", "率/万PY"]]
    for db in ["NHANES", "SHHS", "CHARLS"]:
        sub = s14[(s14["database"] == db) & (s14["stratum_var"] == "Age_Group")].reset_index(drop=True)
        for i, r in sub.iterrows():
            rows.append(
                [
                    db if i == 0 else "",
                    f"Age={r['stratum']}",
                    r["sleep"],
                    int(r["n"]),
                    int(r["deaths"]),
                    f"{float(r['rate_per_10000py']):.1f}",
                ]
            )
    story.append(tab(rows, [55, 70, 70, 45, 40, 55], fname))
    story.append(Spacer(1, 8))
    story.append(Paragraph("说明：NHANES/SHHS为主库，CHARLS为外验；补充分析不可替代主文五分组。", s["small"]))

    doc = SimpleDocTemplate(
        str(path), pagesize=A4, leftMargin=48, rightMargin=48, topMargin=42, bottomMargin=42
    )
    doc.build(story)
    print(f"wrote {path} ({path.stat().st_size} bytes)")


def expected_cut(cut: pd.DataFrame, db: str, cut_mode: str) -> float:
    row = cut[(cut["model"] == "Model 1") & (cut["database"] == db)].iloc[0]
    if cut_mode == "model1_hr1":
        v = row["nearest_HR1_hours"]
        if pd.notna(v) and float(v) == float(v):
            return float(v)
        return float(row["min_risk_hours"])
    return float(row["min_risk_hours"])


def main():
    ckpt = find_ckpt()
    print("ckpt:", ckpt)
    print("PV2_RCS_CUT_MODE:", CUT_MODE)
    cut = pd.read_csv(ckpt / "Table S10. RCS cutoffs.csv")
    s10 = pd.read_csv(ckpt / "Table S10. RCS cutoff Cox.csv")
    s12 = pd.read_csv(ckpt / "Table S12. RCS cutoff Cox PAR.csv")
    s13 = pd.read_csv(ckpt / "Table S13. RCS cutoff diagnostic.csv")
    s14 = pd.read_csv(ckpt / "Table S14. RCS cutoff joint strata.csv")
    # sanity: binary cut matches selected Model1 mode
    for db, h in s10.groupby("database")["cutoff_hours"].first().items():
        exp = expected_cut(cut, db, CUT_MODE)
        assert abs(float(h) - exp) < 1e-6, (db, h, exp, CUT_MODE)
    fname = register_font()
    for p in OUTS:
        build(p, cut, s10, s12, s13, s14, fname, cut_mode=CUT_MODE)


if __name__ == "__main__":
    main()
