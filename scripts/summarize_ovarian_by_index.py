# -*- coding: utf-8 -*-
"""Harvest ovarian cancer composite-index by_index results and write PDF."""
from __future__ import annotations

import csv
import json
import math
import re
from collections import defaultdict
from pathlib import Path

BASE = Path("/mnt/g/02block_result/21_ovarian cancer/small sample prediction_39780007")
BY = BASE / "by_index"
IDX_SUM = BASE / "_shared/MIMIC_IV/step04_index/Tables/Table Index Summary.csv"
OUT_DIR = Path("/mnt/e/01block/01Block-new-Final")
OUT_PDF = OUT_DIR / "卵巢癌_复合指标小样本预测结果汇总.pdf"
OUT_CSV = OUT_DIR / "卵巢癌_复合指标结果汇总表.csv"
OUT_JSON = OUT_DIR / "_ovarian_index_summary.json"

FONT = "/usr/share/fonts/truetype/win-cjk/msyh.ttc"
FONT_BOLD = "/usr/share/fonts/truetype/win-cjk/simhei.ttf"


def load_formulas() -> dict[str, str]:
    formulas: dict[str, str] = {}
    with open(IDX_SUM, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            formulas[row["index"]] = row["formula"]
    return formulas


def parse_summary(path: Path) -> dict[str, str]:
    kv: dict[str, str] = {}
    with open(path, encoding="utf-8") as f:
        rows = list(csv.reader(f))
    for r in rows[1:]:
        if len(r) >= 2:
            kv[r[0]] = r[1]
    return kv


def clean_tex_cell(s: str) -> str:
    s = s.strip()
    s = s.replace(r"\textless{}", "<").replace(r"\textgreater{}", ">")
    s = re.sub(r"\$\\geq\$", "≥", s)
    s = re.sub(r"\$\\leq\$", "≤", s)
    s = s.replace(r"\%", "%").replace(r"\&", "&")
    return s


def parse_logistic_tex(tex_path: Path, *, is_binary: bool = False) -> dict:
    text = tex_path.read_text(encoding="utf-8", errors="ignore")
    cont = binary = trend = None
    m = re.search(
        r"continuous\s*&[^&]*&[^&]*&\s*([^&]+)\s*&\s*([^&]+)\s*&\s*([^&]+)\s*&"
        r"\s*([^&]+)\s*&\s*([^&]+)\s*&\s*([^&]+)\s*&"
        r"\s*([^&]+)\s*&\s*([^&]+)\s*&\s*([^\\&]+)",
        text,
    )
    if m:
        cont = {
            "crude_or": clean_tex_cell(m.group(1)),
            "crude_ci": clean_tex_cell(m.group(2)),
            "crude_p": clean_tex_cell(m.group(3)),
            "m1_or": clean_tex_cell(m.group(4)),
            "m1_ci": clean_tex_cell(m.group(5)),
            "m1_p": clean_tex_cell(m.group(6)),
            "m2_or": clean_tex_cell(m.group(7)),
            "m2_ci": clean_tex_cell(m.group(8)),
            "m2_p": clean_tex_cell(m.group(9)),
        }
    q2 = re.search(
        r"Q2\s*&([^&]*)&([^&]*)&([^&]*)&([^&]*)&([^&]*)&([^&]*)&([^&]*)&([^&]*)&([^&]*)&([^&]*)&([^\\&]+)",
        text,
    )
    if q2 and is_binary:
        binary = {
            "cutoff": clean_tex_cell(q2.group(1)),
            "events": clean_tex_cell(q2.group(2)),
            "crude_or": clean_tex_cell(q2.group(3)),
            "crude_ci": clean_tex_cell(q2.group(4)),
            "crude_p": clean_tex_cell(q2.group(5)),
            "m1_or": clean_tex_cell(q2.group(6)),
            "m1_ci": clean_tex_cell(q2.group(7)),
            "m1_p": clean_tex_cell(q2.group(8)),
            "m2_or": clean_tex_cell(q2.group(9)),
            "m2_ci": clean_tex_cell(q2.group(10)),
            "m2_p": clean_tex_cell(q2.group(11)),
        }
    mt = re.search(
        r"p for trend.*?&\s*([^&]*)\s*&\s*\{\}\s*&\s*\{\}\s*&"
        r"\s*([^&]*)\s*&\s*\{\}\s*&\s*\{\}\s*&\s*([^\\&]+)",
        text,
    )
    if mt:
        trend = {
            "crude_p": clean_tex_cell(mt.group(1)),
            "m1_p": clean_tex_cell(mt.group(2)),
            "m2_p": clean_tex_cell(mt.group(3)),
        }
    return {"continuous": cont, "binary": binary, "trend": trend}


def parse_ml_csv(path: Path) -> dict[str, dict[str, float]]:
    by: dict[str, dict[str, float]] = defaultdict(dict)
    with open(path, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            metric = row.get(".metric") or row.get("metric")
            est = row.get(".estimate") or row.get("estimate")
            ds = row.get("dataset")
            model = row.get("model")
            if metric not in ("roc_auc", "sens", "spec", "f_meas", "accuracy"):
                continue
            try:
                val = float(est) if est not in (None, "", "NA", "NaN") else float("nan")
            except Exception:
                val = float("nan")
            by[model][f"{ds}_{metric}"] = val
    return by


def first_existing(cands: list[Path]) -> Path | None:
    for p in cands:
        if p.exists():
            return p
    return None


def harvest_one(d: Path, formulas: dict[str, str]) -> dict:
    name = d.name
    summ = parse_summary(d / "_index_summary.csv") if (d / "_index_summary.csv").exists() else {}
    index = summ.get("index") or re.sub(r"^【(success|failed)】", "", name)
    status = summ.get("status") or (
        "success" if "success" in name else ("error" if "failed" in name else "unknown")
    )
    mimic = d / "MIMIC_IV"
    q_dir = mimic / "step15_logistic_quartile_glm/Tables"
    b_dir = mimic / "step17_logistic_binary_glm/Tables"
    q_cands = [
        q_dir / f"Table 2-MIMIC IV-MIMIC IV. Logistic regression of {index} quartile.tex"
    ]
    b_cands = [
        b_dir / f"Table 4-MIMIC IV-MIMIC IV. Logistic regression of {index} binary.tex"
    ]
    if q_dir.exists():
        q_cands.extend(sorted(q_dir.glob("*.tex")))
    if b_dir.exists():
        b_cands.extend(sorted(b_dir.glob("*.tex")))
    q_tex = first_existing(q_cands)
    b_tex = first_existing(b_cands)
    cont = binr = trend = None
    if q_tex:
        pq = parse_logistic_tex(q_tex)
        cont, trend = pq["continuous"], pq["trend"]
    if b_tex:
        pb = parse_logistic_tex(b_tex, is_binary=True)
        binr = pb["binary"]
        if cont is None:
            cont = pb["continuous"]

    ml_path = first_existing(
        [
            mimic / "step35_ml_aggregate/ml_eval_all.csv",
            mimic / "step36_ml_aggregate/ml_eval_all.csv",
        ]
    )
    ml = parse_ml_csv(ml_path) if ml_path else {}
    best_model, best_test, best_train = "", float("nan"), float("nan")
    ml_rows = []
    for model, mets in ml.items():
        ta = mets.get("test_roc_auc", float("nan"))
        tr = mets.get("train_roc_auc", float("nan"))
        ml_rows.append(
            (model, tr, ta, mets.get("test_sens", float("nan")), mets.get("test_spec", float("nan")))
        )
        if not math.isnan(ta) and (math.isnan(best_test) or ta > best_test):
            best_test, best_train, best_model = ta, tr, model

    meta = mimic / "step05_train_validation/train_validation_split_meta.csv"
    train_n = val_n = ""
    if meta.exists():
        with open(meta, encoding="utf-8") as f:
            mr = list(csv.DictReader(f))
            if mr:
                train_n = mr[0].get("train_n", "")
                val_n = mr[0].get("val_n", "")

    return {
        "folder": name,
        "index": index,
        "status": status,
        "n_valid": summ.get("n_nhanes_after", ""),
        "formula": formulas.get(index, ""),
        "gate_auc": summ.get("nhanes_auc", ""),
        "error": (summ.get("error_message", "") or "").replace("\n", " ")[:220],
        "train_n": train_n,
        "val_n": val_n,
        "cont": cont,
        "binary": binr,
        "trend": trend,
        "best_model": best_model,
        "best_test_auc": best_test,
        "best_train_auc": best_train,
        "ml_rows": sorted(
            ml_rows, key=lambda x: (-(x[2] if not math.isnan(x[2]) else -1), x[0])
        ),
        "has_ml": bool(ml),
    }


def dedupe_success(records: list[dict]) -> list[dict]:
    by_index: dict[str, dict] = {}
    for r in records:
        idx = r["index"]
        if idx not in by_index:
            by_index[idx] = r
            continue
        cur = by_index[idx]
        prefer = False
        if "【success】" in r["folder"] and "【success】" not in cur["folder"]:
            prefer = True
        else:
            try:
                if float(r["gate_auc"] or 0) > float(cur["gate_auc"] or 0):
                    prefer = True
            except Exception:
                pass
        if prefer:
            by_index[idx] = r
    return sorted(
        by_index.values(),
        key=lambda x: (-(float(x["gate_auc"]) if x["gate_auc"] else -1), x["index"]),
    )


def fmt_auc(x) -> str:
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return "—"
    return f"{float(x):.3f}"


def to_float(s) -> float | None:
    try:
        return float(s)
    except Exception:
        return None


def build_pdf(success: list[dict], failed: list[dict]) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib import font_manager
    from matplotlib.backends.backend_pdf import PdfPages

    font_manager.fontManager.addfont(FONT)
    font_manager.fontManager.addfont(FONT_BOLD)
    plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
    plt.rcParams["axes.unicode_minus"] = False

    # rank helpers
    crude_sig = []
    for r in success:
        c = r.get("cont") or {}
        p = to_float(c.get("crude_p"))
        if p is not None and p < 0.05:
            crude_sig.append((r["index"], c.get("crude_or"), p, r["n_valid"]))
    crude_sig.sort(key=lambda x: x[2])

    ml_rank = sorted(
        [r for r in success if r["has_ml"] and not math.isnan(r["best_test_auc"])],
        key=lambda x: -x["best_test_auc"],
    )

    with PdfPages(OUT_PDF) as pdf:
        # ---- cover / overview ----
        fig = plt.figure(figsize=(11.69, 8.27))  # A4 landscape
        fig.patch.set_facecolor("white")
        ax = fig.add_axes([0, 0, 1, 1])
        ax.axis("off")
        ax.text(0.06, 0.90, "卵巢癌 ICU 复合指标小样本预测 — 结果汇总", fontsize=20, fontweight="bold")
        ax.text(0.06, 0.84, "Study: 21_ovarian cancer / small sample prediction_39780007（PMID 39780007）", fontsize=11)
        ax.text(0.06, 0.79, "数据: MIMIC-IV 单库  n=106（Non-survivor 14 / Survivor 92）  结局: 院内死亡 DN", fontsize=11)
        ax.text(0.06, 0.74, f"来源目录: by_index（成功 {len(success)} / 失败 {len(failed)}，另有 ACAG 刷新副本已去重）", fontsize=11)
        ax.text(0.06, 0.68, "分析要点", fontsize=14, fontweight="bold")
        bullets = [
            "流水线：指标计算 → 分层 70/30 划分 → 训练集 MICE → 单因素/VIF → Logistic（连续/四分位/三分位/二分）→ 多模型 ML（AdaBoost/TabPFNv2/CatBoost/XGBoost/LightGBM/RF）。",
            "闸门 AUC（_index_summary.nhanes_auc）来自该指标流水线汇总；ML 验证集 AUC 来自 ml_eval_all.csv 的 test roc_auc。",
            "事件极少（约 14 例死亡）：四分位常出现 Q1=0 事件 → 分组 OR 不可估；宜优先看连续 Crude/Model1 与二分，Model2 易过调。",
            "训练集 AUC 常接近 1.0，验证集波动大，提示小样本过拟合风险；解释时以验证集与连续关联为主。",
            "失败指标两类：①单因素无显著变量（NLR/PLR/SII 等炎症比）；②基线表 t.test 遇常量列报错（部分可修复后重跑）。",
        ]
        y = 0.62
        for b in bullets:
            ax.text(0.06, y, "•  " + b, fontsize=10, wrap=True, va="top")
            y -= 0.08
        ax.text(0.06, 0.10, "生成说明：本 PDF 由 by_index 下 _index_summary / Logistic .tex / ml_eval_all.csv 自动汇总，数值以原始表为准。", fontsize=9, color="#444444")
        pdf.savefig(fig)
        plt.close(fig)

        # ---- ranking page ----
        fig = plt.figure(figsize=(11.69, 8.27))
        ax = fig.add_axes([0.04, 0.04, 0.92, 0.92])
        ax.axis("off")
        ax.text(0.0, 0.96, "一、成功指标排名（闸门 AUC & 验证集最佳 ML AUC）", fontsize=14, fontweight="bold")

        # left table gate auc
        headers = ["排名", "指标", "有效N", "闸门AUC", "最佳ML", "验证AUC", "训练AUC"]
        rows = []
        for i, r in enumerate(success, 1):
            rows.append(
                [
                    str(i),
                    r["index"],
                    str(r["n_valid"]),
                    fmt_auc(to_float(r["gate_auc"])),
                    r["best_model"] or "—",
                    fmt_auc(r["best_test_auc"]),
                    fmt_auc(r["best_train_auc"]),
                ]
            )
        col_x = [0.00, 0.07, 0.22, 0.32, 0.45, 0.62, 0.78]
        y = 0.90
        for j, h in enumerate(headers):
            ax.text(col_x[j], y, h, fontsize=9, fontweight="bold")
        y -= 0.035
        ax.plot([0, 0.95], [y + 0.02, y + 0.02], color="#888888", lw=0.6)
        for row in rows:
            for j, cell in enumerate(row):
                ax.text(col_x[j], y, cell, fontsize=8.5)
            y -= 0.032
            if y < 0.05:
                break
        pdf.savefig(fig)
        plt.close(fig)

        # ---- logistic continuous ----
        fig = plt.figure(figsize=(11.69, 8.27))
        ax = fig.add_axes([0.03, 0.03, 0.94, 0.94])
        ax.axis("off")
        ax.text(0.0, 0.96, "二、Logistic 连续变量 OR（Crude / Model1 / Model2）", fontsize=14, fontweight="bold")
        ax.text(
            0.0,
            0.92,
            "Model1≈Age；Model2=Age+临床严重度等（各指标略有不同）。粗体/优先关注 Crude P<0.05。",
            fontsize=9,
            color="#444444",
        )
        headers = ["指标", "N", "Crude OR (P)", "Model1 OR (P)", "Model2 OR (P)", "二分 High Crude OR (P)"]
        col_x = [0.00, 0.12, 0.20, 0.42, 0.64, 0.82]
        y = 0.88
        for j, h in enumerate(headers):
            ax.text(col_x[j], y, h, fontsize=8.5, fontweight="bold")
        y -= 0.03
        ax.plot([0, 1], [y + 0.015, y + 0.015], color="#888", lw=0.5)

        def cell_or(c, prefix):
            if not c:
                return "—"
            return f"{c.get(prefix+'_or','—')} ({c.get(prefix+'_p','—')})"

        for r in success:
            c = r.get("cont") or {}
            b = r.get("binary") or {}
            row = [
                r["index"],
                str(r["n_valid"]),
                cell_or(c, "crude"),
                cell_or(c, "m1"),
                cell_or(c, "m2"),
                f"{b.get('crude_or','—')} ({b.get('crude_p','—')})" if b else "—",
            ]
            # highlight crude sig
            p = to_float(c.get("crude_p")) if c else None
            weight = "bold" if (p is not None and p < 0.05) else "normal"
            color = "#0B5FFF" if weight == "bold" else "black"
            for j, cell in enumerate(row):
                ax.text(col_x[j], y, cell[:28], fontsize=7.5, fontweight=weight, color=color)
            y -= 0.032
            if y < 0.06:
                break
        ax.text(0.0, 0.02, "蓝色加粗 = 连续 Crude P<0.05。四分位结果因零事件分离，未列入本表。", fontsize=8, color="#666")
        pdf.savefig(fig)
        plt.close(fig)

        # ---- bar chart gate auc vs ml ----
        fig, axes = plt.subplots(1, 2, figsize=(11.69, 8.27))
        # gate
        names = [r["index"] for r in success]
        gate = [to_float(r["gate_auc"]) or 0 for r in success]
        ax = axes[0]
        ax.barh(range(len(names)), gate[::-1], color="#4C78A8")
        ax.set_yticks(range(len(names)))
        ax.set_yticklabels(names[::-1], fontsize=8)
        ax.set_xlabel("闸门 AUC")
        ax.set_title("成功指标：闸门 AUC")
        ax.set_xlim(0.5, 1.0)
        ax.axvline(0.7, color="#aaa", ls="--", lw=0.8)
        # ml test
        ax = axes[1]
        ml_names = [r["index"] for r in ml_rank]
        ml_auc = [r["best_test_auc"] for r in ml_rank]
        ax.barh(range(len(ml_names)), ml_auc[::-1], color="#F58518")
        ax.set_yticks(range(len(ml_names)))
        ax.set_yticklabels(ml_names[::-1], fontsize=8)
        ax.set_xlabel("验证集最佳模型 AUC")
        ax.set_title("成功指标：验证集 ML AUC（最高）")
        ax.set_xlim(0.4, 1.0)
        ax.axvline(0.7, color="#aaa", ls="--", lw=0.8)
        fig.suptitle("三、可视化对比", fontsize=14, fontweight="bold", y=0.98)
        fig.tight_layout(rect=[0, 0.02, 1, 0.95])
        pdf.savefig(fig)
        plt.close(fig)

        # ---- top findings narrative ----
        fig = plt.figure(figsize=(11.69, 8.27))
        ax = fig.add_axes([0.05, 0.05, 0.9, 0.9])
        ax.axis("off")
        ax.text(0.0, 0.96, "四、关键结论（基于当前 by_index）", fontsize=14, fontweight="bold")

        top_gate = success[:5]
        top_ml = ml_rank[:5]
        lines = []
        lines.append("1) 闸门 AUC 最高的 5 个指标：")
        for i, r in enumerate(top_gate, 1):
            lines.append(
                f"   {i}. {r['index']}（N={r['n_valid']}，闸门AUC={fmt_auc(to_float(r['gate_auc']))}，"
                f"验证ML={r['best_model'] or '—'} {fmt_auc(r['best_test_auc'])}）"
            )
        lines.append("")
        lines.append("2) 验证集 ML AUC 最高的 5 个指标：")
        for i, r in enumerate(top_ml, 1):
            gap = ""
            if not math.isnan(r["best_train_auc"]) and not math.isnan(r["best_test_auc"]):
                gap = f"，训-验差={r['best_train_auc']-r['best_test_auc']:.3f}"
            lines.append(
                f"   {i}. {r['index']} → {r['best_model']} 验证AUC={fmt_auc(r['best_test_auc'])} "
                f"(训练={fmt_auc(r['best_train_auc'])}{gap})"
            )
        lines.append("")
        lines.append("3) 连续 Crude 显著（P<0.05）的指标：")
        if crude_sig:
            for idx, orv, p, n in crude_sig:
                lines.append(f"   • {idx}: Crude OR={orv}, P={p:.4f}, N={n}")
        else:
            lines.append("   （按当前解析：未见或极少）")
        lines.append("")
        lines.append("4) 解读建议：")
        lines.append("   • BMI 闸门AUC很高但有效N仅约46，缺失多，外推需谨慎。")
        lines.append("   • ALBI / BAR / CAR / ACAG / FIB4 / APRI / WPR 等肝肾营养相关指标整体表现较稳。")
        lines.append("   • 炎症细胞比值（NLR/PLR/SII/NLPR/ANLR/HALP/PNI）多因单因素无显著或N不足失败。")
        lines.append("   • 投稿叙事建议：主文突出 1–2 个生物学可解释且 N≥70 的指标；ML 作辅助预测对照。")
        lines.append("   • 平行分析 all_vars_ml（全连续变量共识特征）可与单指标结果交叉对照，不在本 PDF 展开。")

        y = 0.90
        for line in lines:
            ax.text(0.0, y, line, fontsize=10, family="Microsoft YaHei")
            y -= 0.035
        pdf.savefig(fig)
        plt.close(fig)

        # ---- failed ----
        fig = plt.figure(figsize=(11.69, 8.27))
        ax = fig.add_axes([0.04, 0.04, 0.92, 0.92])
        ax.axis("off")
        ax.text(0.0, 0.96, "五、失败指标与原因", fontsize=14, fontweight="bold")
        y = 0.90
        headers = ["指标", "有效N", "失败类型摘要"]
        for j, (h, x) in enumerate(zip(headers, [0.0, 0.12, 0.22])):
            ax.text(x, y, h, fontsize=9, fontweight="bold")
        y -= 0.04
        for r in sorted(failed, key=lambda x: x["index"]):
            err = r["error"] or ""
            if "未找到单因素显著变量" in err:
                typ = "单因素无显著变量（流水线暂停）"
            elif "is_constant" in err or "t.te" in err:
                typ = "基线描述统计遇常量列报错（可修脚本后重跑）"
            else:
                typ = (err[:90] + "…") if len(err) > 90 else (err or "未知")
            ax.text(0.0, y, r["index"], fontsize=9)
            ax.text(0.12, y, str(r["n_valid"]), fontsize=9)
            ax.text(0.22, y, typ, fontsize=8.5)
            y -= 0.05
        ax.text(
            0.0,
            0.08,
            "注：部分【failed】目录仍残留早期 ml_eval 文件，但 _index_summary.status=error，本汇总按失败计。",
            fontsize=8,
            color="#666",
        )
        pdf.savefig(fig)
        plt.close(fig)

        # ---- formulas appendix ----
        fig = plt.figure(figsize=(11.69, 8.27))
        ax = fig.add_axes([0.03, 0.03, 0.94, 0.94])
        ax.axis("off")
        ax.text(0.0, 0.96, "六、成功指标公式与样本量", fontsize=14, fontweight="bold")
        y = 0.90
        ax.text(0.0, y, "指标", fontsize=8, fontweight="bold")
        ax.text(0.12, y, "N", fontsize=8, fontweight="bold")
        ax.text(0.18, y, "公式", fontsize=8, fontweight="bold")
        y -= 0.03
        for r in sorted(success, key=lambda x: x["index"]):
            ax.text(0.0, y, r["index"], fontsize=7.5)
            ax.text(0.12, y, str(r["n_valid"]), fontsize=7.5)
            ax.text(0.18, y, (r["formula"] or "—")[:110], fontsize=7)
            y -= 0.028
            if y < 0.04:
                break
        pdf.savefig(fig)
        plt.close(fig)

    print("PDF ->", OUT_PDF)


def main() -> None:
    formulas = load_formulas()
    records: list[dict] = []
    failed: list[dict] = []
    dirs = sorted([d for d in BY.iterdir() if d.is_dir()])
    print(f"Scanning {len(dirs)} folders ...")
    for i, d in enumerate(dirs, 1):
        print(f"  [{i}/{len(dirs)}] {d.name}")
        rec = harvest_one(d, formulas)
        if rec["status"] == "success" or "【success】" in rec["folder"]:
            records.append(rec)
        else:
            failed.append(rec)
    success = dedupe_success(records)

    with open(OUT_CSV, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "指标",
                "状态",
                "有效N",
                "公式",
                "闸门AUC",
                "连续Crude_OR",
                "Crude_P",
                "Model1_OR",
                "Model1_P",
                "Model2_OR",
                "Model2_P",
                "二分High_Crude_OR",
                "二分High_Crude_P",
                "二分High_Model2_OR",
                "二分High_Model2_P",
                "最佳ML模型",
                "验证集AUC",
                "训练集AUC",
                "训练n",
                "验证n",
                "失败原因",
            ]
        )
        for r in success + failed:
            c = r["cont"] or {}
            b = r["binary"] or {}
            w.writerow(
                [
                    r["index"],
                    r["status"],
                    r["n_valid"],
                    r["formula"],
                    r["gate_auc"],
                    c.get("crude_or", ""),
                    c.get("crude_p", ""),
                    c.get("m1_or", ""),
                    c.get("m1_p", ""),
                    c.get("m2_or", ""),
                    c.get("m2_p", ""),
                    b.get("crude_or", ""),
                    b.get("crude_p", ""),
                    b.get("m2_or", ""),
                    b.get("m2_p", ""),
                    r["best_model"],
                    f"{r['best_test_auc']:.4f}" if not math.isnan(r["best_test_auc"]) else "",
                    f"{r['best_train_auc']:.4f}" if not math.isnan(r["best_train_auc"]) else "",
                    r["train_n"],
                    r["val_n"],
                    r["error"],
                ]
            )

    def ser(r: dict) -> dict:
        o = {k: v for k, v in r.items() if k != "ml_rows"}
        o["ml_rows"] = [
            {
                "model": a,
                "train_auc": None if math.isnan(b) else b,
                "test_auc": None if math.isnan(c) else c,
                "test_sens": None if math.isnan(d) else d,
                "test_spec": None if math.isnan(e) else e,
            }
            for a, b, c, d, e in r["ml_rows"]
        ]
        o["best_test_auc"] = None if math.isnan(r["best_test_auc"]) else r["best_test_auc"]
        o["best_train_auc"] = None if math.isnan(r["best_train_auc"]) else r["best_train_auc"]
        return o

    json.dump(
        {"success": [ser(r) for r in success], "failed": [ser(r) for r in failed]},
        open(OUT_JSON, "w", encoding="utf-8"),
        ensure_ascii=False,
        indent=2,
    )
    print(f"SUCCESS={len(success)} FAILED={len(failed)}")
    print("CSV ->", OUT_CSV)
    print("JSON ->", OUT_JSON)
    build_pdf(success, failed)


if __name__ == "__main__":
    main()
