#!/usr/bin/env python3
"""仅重生成 summary_results/Tables/*.xlsx（SCI 三线表 / Times New Roman）。

用固定相对路径读 CSV（避免 G: 盘 rglob 极慢），不依赖 matplotlib。
"""
from __future__ import annotations

import csv
import shutil
from pathlib import Path

FONT_TNR = "Times New Roman"
DB_NAME = "MIMIC"
PROJ_CANDS = [
    Path(r"G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
    Path("/mnt/g/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
]
LANDMARKS = (24, 48, 72, 96, 120)
ARCH_MAP = {"A1_repo": "a1", "A2_single": "a2", "B_twostage": "b"}
BASELINES = ("logistic", "xgb", "mlp", "lstm")


def lit_tab(n, name, *, supp=False, extra=False) -> str:
    if extra:
        return f"Table Extra-{DB_NAME}-{name}.xlsx"
    if supp:
        return f"Table S{n}-{DB_NAME}-{name}.xlsx"
    return f"Table {n}-{DB_NAME}-{name}.xlsx"


def find_proj(explicit: str | None = None) -> Path:
    if explicit and str(explicit).strip():
        p = Path(str(explicit).strip())
        if not p.exists():
            raise SystemExit(f"project-root 不存在: {p}")
        return p
    for p in PROJ_CANDS:
        if p.exists():
            return p
    raise SystemExit("未找到项目产出根")


def tables_csv(proj: Path, unit: str, filename: str) -> Path | None:
    """直接探测文件（G: 上 is_dir 对已存在目录极慢，禁止先判目录）。"""
    for name in (f"【success】{unit}", unit):
        p = proj / "by_unit" / name / "step09_tst_train_eval" / "Tables" / filename
        if p.is_file():
            return p
    return None


def read_csv(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))

def _cell_str(v) -> str:
    if v is None:
        return ""
    s = str(v).strip()
    if s.lower() in ("nan", "none", "na"):
        return ""
    return s


def rows_to_xlsx(path: Path, rows: list[dict], title: str, *, footnotes=None, max_rows=None) -> None:
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Border, Font, Side
    from openpyxl.utils import get_column_letter

    path = Path(path)
    if path.suffix.lower() != ".xlsx":
        path = path.with_suffix(".xlsx")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
    except OSError:
        pass

    cols = list(dict.fromkeys(k for r in rows for k in r.keys())) if rows else ["Note"]
    show = rows if max_rows is None else rows[:max_rows]
    if not show:
        show = [{"Note": "No rows"}]
        cols = ["Note"]

    thick = Side(style="medium", color="000000")
    thin = Side(style="thin", color="000000")
    border_header = Border(top=thick, bottom=thin)
    border_last = Border(bottom=thick)
    border_foot_top = Border(top=thin)

    font_title = Font(name=FONT_TNR, size=12, bold=True)
    font_hdr = Font(name=FONT_TNR, size=12, bold=True)
    font_body = Font(name=FONT_TNR, size=12)
    align_c = Alignment(horizontal="center", vertical="center", wrap_text=True)
    align_l = Alignment(horizontal="left", vertical="center", wrap_text=True)

    wb = Workbook()
    ws = wb.active
    ws.title = "Table"
    ws.sheet_view.showGridLines = False

    nc = len(cols)
    r0 = 1
    if title and str(title).strip():
        ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=nc)
        c = ws.cell(1, 1, str(title).strip())
        c.font = font_title
        c.alignment = align_c
        r0 = 2

    for j, col in enumerate(cols, start=1):
        cell = ws.cell(r0, j, _cell_str(col).replace("_", " "))
        cell.font = font_hdr
        cell.alignment = align_c
        cell.border = border_header

    for i, row in enumerate(show):
        excel_r = r0 + 1 + i
        is_last = i == len(show) - 1
        for j, col in enumerate(cols, start=1):
            cell = ws.cell(excel_r, j, _cell_str(row.get(col, "")))
            cell.font = font_body
            cell.alignment = align_l if j == 1 else align_c
            if is_last:
                cell.border = border_last

    if footnotes:
        feet = [str(f).strip() for f in footnotes if str(f).strip()]
        last_data = r0 + len(show)
        for k, note in enumerate(feet):
            fr = last_data + 1 + k
            ws.merge_cells(start_row=fr, start_column=1, end_row=fr, end_column=nc)
            cell = ws.cell(fr, 1, note)
            cell.font = font_body
            cell.alignment = align_l
            if k == 0:
                cell.border = border_foot_top

    for j, col in enumerate(cols, start=1):
        maxlen = len(_cell_str(col))
        for row in show:
            maxlen = max(maxlen, min(len(_cell_str(row.get(col, ""))), 48))
        ws.column_dimensions[get_column_letter(j)].width = min(max(maxlen + 2, 10), 42)
    if title:
        ws.row_dimensions[1].height = 22

    wb.save(path)
    print(f"  wrote {path.name}")


def blank_xlsx(path: Path, title: str, note: str = "") -> None:
    rows_to_xlsx(path, [{"Note": note or "Placeholder"}], title)


def csv_file_to_xlsx(csv_path: Path, xlsx: Path, title: str, *, footnotes=None) -> None:
    rows = read_csv(csv_path) if csv_path.exists() else []
    rows_to_xlsx(xlsx, rows, title, footnotes=footnotes)


def regen(project_root: str | None = None, primary_landmark: int = 72) -> Path:
    proj = find_proj(project_root)
    primary_lm = int(primary_landmark)
    out = proj / "summary_results"
    tables = out / "Tables"
    by_lm = out / "by_landmark"
    # mkdir 对已存在 G: 目录可能极慢；仅当写文件失败时再创建
    print(f"[regen tables] project={proj}")

    known_stems = [
        "Table 1-MIMIC-Baseline_characteristics",
        "Table 2-MIMIC-Daily_performance_Transformer",
        "Table 3-MIMIC-Comparative_model_performance",
        "Table S1-MIMIC-Features",
        "Table Extra-MIMIC-Calibration",
        "Table Extra-MIMIC-DCA",
        "Table Extra-MIMIC-Ablation",
    ]
    for stem in known_stems:
        for ext in (".pdf", ".xlsx"):
            p = tables / f"{stem}{ext}"
            if p.is_file():
                try:
                    p.unlink()
                    print(f"  removed {p.name}")
                except OSError as e:
                    print(f"  warn unlink {p.name}: {e}")

    perf_rows: list[dict] = []
    cal_rows: list[dict] = []
    dca_rows: list[dict] = []
    abl_rows: list[dict] = []

    # 仅主 landmark 收集指标（G: I/O 慢；主文表只看 L{primary}）
    landmarks = (primary_lm,)
    for lm in landmarks:
        for suffix, arch in ARCH_MAP.items():
            unit = f"L{lm}_{suffix}"
            metrics = tables_csv(proj, unit, f"Table_TST_Metrics_{arch}.csv")
            if metrics:
                for r in read_csv(metrics):
                    r = dict(r)
                    r["landmark_h"] = str(lm)
                    r["unit"] = unit
                    r["model"] = arch
                    perf_rows.append(r)
            # Extra 表：仅 B 模型校准/DCA，避免扫全单位
            if arch == "b":
                cal = tables_csv(proj, unit, "Table_TST_Calibration.csv")
                if cal:
                    for r in read_csv(cal):
                        r = dict(r)
                        r["landmark_h"] = str(lm)
                        r["unit"] = unit
                        r["model"] = arch
                        cal_rows.append(r)
                dca = tables_csv(proj, unit, "Table_TST_DCA.csv")
                if dca:
                    for r in read_csv(dca):
                        r = dict(r)
                        r["landmark_h"] = str(lm)
                        r["unit"] = unit
                        r["model"] = arch
                        dca_rows.append(r)
                abl = tables_csv(proj, unit, "Table_TST_Ablation.csv")
                if abl:
                    for r in read_csv(abl):
                        r = dict(r)
                        r["landmark_h"] = str(lm)
                        r["unit"] = unit
                        abl_rows.append(r)
        for bl in BASELINES:
            unit = f"L{lm}_{bl}"
            base = tables_csv(proj, unit, "Table_TST_Baselines.csv")
            if base:
                for r in read_csv(base):
                    r = dict(r)
                    r["landmark_h"] = str(lm)
                    r["unit"] = unit
                    r["model"] = bl
                    if "split" not in r:
                        r["split"] = "test"
                    perf_rows.append(r)
            # 基线 metrics 也可能在 Table_TST_Metrics 风格之外；从 baselines 取 AUC 即可


    print(f"  collected perf={len(perf_rows)} cal={len(cal_rows)} dca={len(dca_rows)} abl={len(abl_rows)}")

    t1_src = (
        proj
        / "_shared/step06_baseline_binary/Tables"
        / "Table 1-MIMIC. Baseline characteristics of IschemicStroke TwoStageTransformer.xlsx"
    )
    t1_xlsx = tables / lit_tab(1, "Baseline_characteristics")
    if t1_src.is_file():
        shutil.copy2(t1_src, t1_xlsx)
        print(f"  copied {t1_xlsx.name}")
    else:
        blank_xlsx(t1_xlsx, "Table 1. Baseline characteristics", "Source xlsx missing")

    s6_by_day: dict[str, dict] = {}
    for cand in (
        by_lm / f"L{primary_lm}" / "Tables" / "Table_S6_model_comparison_metrics.csv",
        out / "Table_S6_model_comparison_metrics.csv",
    ):
        if cand.is_file():
            for r in read_csv(cand):
                m = str(r.get("model", "")).strip().lower()
                d = str(r.get("day", "")).strip()
                s6_by_day[f"{m}|{d}"] = r
            print(f"  loaded S6 metrics from {cand}")
            break

    def _s6_metric(model_label: str, day, key: str) -> str:
        r = s6_by_day.get(f"{model_label.lower()}|{day}")
        if not r:
            return ""
        v = r.get(key, "")
        try:
            return f"{float(v):.4f}"
        except (TypeError, ValueError):
            return _cell_str(v)

    t2_rows = []
    for r in perf_rows:
        if (
            str(r.get("landmark_h")) == str(primary_lm)
            and str(r.get("model", "")).lower() == "b"
            and str(r.get("split", "test")).lower() == "test"
        ):
            day = r.get("day")
            t2_rows.append(
                {
                    "Day": day,
                    "Model": "two-stage Transformer",
                    "AUC": r.get("auc") or r.get("auc_test"),
                    "Accuracy": _s6_metric("two-stage transformer", day, "accuracy"),
                    "F1 score": _s6_metric("two-stage transformer", day, "f1"),
                    "Note": "SAPSII comparison in Fig.3 【场景迁移】",
                }
            )
    rows_to_xlsx(
        tables / lit_tab(2, "Daily_performance_Transformer"),
        t2_rows,
        "Table 2. Daily performance of the two-stage Transformer (MIMIC ischemic stroke)",
        footnotes=[
            f"Primary landmark L{primary_lm}; test split.",
            "Accuracy/F1 from Youden threshold on Day1–5 predictions when available.",
            "【场景迁移】Paper comparator APACHE II → here SAPSII (see Fig.3).",
        ],
    )

    def _auc_for(model: str, day: str | int = 5) -> str:
        cands = [
            r
            for r in perf_rows
            if str(r.get("landmark_h")) == str(primary_lm)
            and str(r.get("model", "")).lower() == model.lower()
            and str(r.get("split", "test")).lower() == "test"
            and str(r.get("day")) == str(day)
        ]
        if cands:
            return str(cands[0].get("auc") or cands[0].get("auc_test") or "")
        cands = [
            r
            for r in perf_rows
            if str(r.get("landmark_h")) == str(primary_lm)
            and str(r.get("model", "")).lower() == model.lower()
            and str(r.get("split", "test")).lower() in ("test", "")
        ]
        if not cands:
            return ""
        vals = []
        for r in cands:
            try:
                vals.append(float(r.get("auc") or r.get("auc_test") or r.get("auc_val") or "nan"))
            except ValueError:
                pass
        vals = [v for v in vals if v == v]
        return f"{sum(vals)/len(vals):.4f}" if vals else ""

    t3_models = [
        ("decision_tree", "【证据不足】原文 DT 未跑"),
        ("xgboost", ""),
        ("mlp", ""),
        ("lstm", ""),
        ("two_stage_Transformer", ""),
        ("a1_repo", "【场景迁移】A1"),
        ("a2_single", "【场景迁移】A2"),
        ("logistic", "【场景迁移】额外基线"),
    ]
    model_key = {
        "decision_tree": None,
        "xgboost": "xgb",
        "mlp": "mlp",
        "lstm": "lstm",
        "two_stage_Transformer": "b",
        "a1_repo": "a1",
        "a2_single": "a2",
        "logistic": "logistic",
    }
    s6_name = {
        "decision_tree": "Decision Tree",
        "xgboost": "XGBoost",
        "mlp": "MLP",
        "lstm": "LSTM",
        "two_stage_Transformer": "Two-stage Transformer",
    }
    t3_rows = []
    for name, note in t3_models:
        mk = model_key[name]
        auc = _auc_for(mk, 5) if mk else ""
        s6n = s6_name.get(name, "")
        acc = _s6_metric(s6n, 5, "accuracy") if s6n else ""
        f1 = _s6_metric(s6n, 5, "f1") if s6n else ""
        if not auc and s6n:
            auc = _s6_metric(s6n, 5, "auc")
        t3_rows.append(
            {
                "Model": name.replace("_", " "),
                "Landmark (h)": primary_lm,
                "Day": 5,
                "AUC": auc,
                "Accuracy": acc,
                "F1 score": f1,
                "Note": note or ("" if auc else "缺失"),
            }
        )
    rows_to_xlsx(
        tables / lit_tab(3, "Comparative_model_performance"),
        t3_rows,
        f"Table 3. Comparative model performance (L{primary_lm}, Day 5)",
        footnotes=[
            "Paper models: Decision Tree / XGBoost / MLP / LSTM / Transformer.",
            "A1/A2/logistic are extra baselines 【场景迁移】.",
            "Decision Tree row filled from S6 surrogate when available; else 【证据不足】.",
        ],
    )

    feat_src = proj / "_shared/step04_tst_timeseries/_tst_feature_coverage_audit.csv"
    if feat_src.is_file():
        csv_file_to_xlsx(
            feat_src,
            tables / lit_tab(1, "Features", supp=True),
            "Table S1. Features / coverage audit (MIMIC ischemic stroke)",
            footnotes=["【场景迁移】卒中日级特征审计，非原文 eICU 226 维小时特征表。"],
        )
    else:
        blank_xlsx(tables / lit_tab(1, "Features", supp=True), "Table S1. Features", "Source missing")

    if cal_rows:
        rows_to_xlsx(tables / lit_tab(0, "Calibration", extra=True), cal_rows, "Table Extra. Calibration")
    if dca_rows:
        rows_to_xlsx(tables / lit_tab(0, "DCA", extra=True), dca_rows, "Table Extra. DCA")
    if abl_rows:
        rows_to_xlsx(tables / lit_tab(0, "Ablation", extra=True), abl_rows, "Table Extra. Ablation")
    # Literature_Validation / Batch_summary / Indicator_availability：不再导出

    files = []
    for stem in known_stems:
        p = tables / f"{stem}.xlsx"
        if p.is_file():
            files.append(p)
    print(f"[regen tables] OK -> {tables} ({len(files)} xlsx)")
    for f in files:
        print(f"  {f.name}")
    return tables


if __name__ == "__main__":
    regen()
