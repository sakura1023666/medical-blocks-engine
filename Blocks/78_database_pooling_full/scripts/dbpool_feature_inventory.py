#!/usr/bin/env python3
"""Engine: BlendedLoS / dbpool model feature inventory → Table S9.

Reusable across ULN / ICUAKI / EASL packs. Reads the BlendedLoS ``ts_variables.csv``
keep-list, drops respiratory (unless enabled) and cohort-gate labs, then writes a
SCI three-line Table S9 plus returns counts for Methods.

Env:
  DBPOOL_DROP_TS          comma list (default: bilirubine,alanine_aminotransferase,aspartate_aminotransferase)
  DBPOOL_USE_RESP         1/true to keep respiratory channels (default off)
  DBPOOL_TS_VARIABLES     path to ts_variables.csv (optional)
"""
from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Iterable

import pandas as pd
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, Side
from openpyxl.utils import get_column_letter

_SCRIPT = Path(__file__).resolve().parent
_ENGINE = _SCRIPT.parents[2]
_DEFAULT_TS = (
    _SCRIPT.parent / "upstream" / "BlendedLoS" / "ts_variables.csv",
    _ENGINE / "python" / "blended_los_upstream" / "ts_variables.csv",
)

_CAT_LAB = {
    "time": "Time index",
    "vitals": "Vitals (hourly)",
    "laboratory": "Laboratory (hourly)",
    "medication": "Medication (hourly dose>0 indicator)",
    "respiratory": "Respiratory (hourly)",
}

_STATIC = [
    ("age", "Age"),
    ("sex", "Sex"),
    ("height", "Height"),
    ("weight", "Weight"),
]


def _default_drop() -> list[str]:
    raw = os.environ.get(
        "DBPOOL_DROP_TS",
        "bilirubine,alanine_aminotransferase,aspartate_aminotransferase",
    ).strip()
    return [x.strip() for x in raw.split(",") if x.strip()]


def resolve_ts_variables_csv(explicit: Path | None = None) -> Path:
    if explicit is not None and explicit.exists():
        return explicit
    env = os.environ.get("DBPOOL_TS_VARIABLES", "").strip()
    if env and Path(env).exists():
        return Path(env)
    for cand in _DEFAULT_TS:
        if cand.exists():
            return cand
    raise FileNotFoundError(
        "ts_variables.csv not found; set DBPOOL_TS_VARIABLES or place under "
        "Blocks/78_database_pooling_full/upstream/BlendedLoS/"
    )


def build_feature_inventory_df(
    ts_csv: Path | None = None,
    *,
    drop_vars: Iterable[str] | None = None,
    use_resp: bool | None = None,
) -> pd.DataFrame:
    path = resolve_ts_variables_csv(ts_csv)
    tv = pd.read_csv(path, sep=";")
    if "variable" not in tv.columns:
        raise ValueError(f"bad ts_variables schema: {path}")
    if not (tv["variable"].astype(str) == "time").any():
        tv = pd.concat(
            [
                pd.DataFrame(
                    [{"variable": "time", "category": "time", "keep": 1, "printed_name": "time"}]
                ),
                tv,
            ],
            ignore_index=True,
        )
    else:
        tv.loc[tv["variable"].astype(str) == "time", "category"] = (
            tv.loc[tv["variable"].astype(str) == "time", "category"].fillna("time")
        )

    keep = tv[tv["keep"].astype(str).isin(["1", "1.0", "True", "true"])].copy()
    keep["category"] = keep["category"].fillna("time").astype(str)
    drop = {str(x) for x in (drop_vars if drop_vars is not None else _default_drop())}
    if use_resp is None:
        use_resp = os.environ.get("DBPOOL_USE_RESP", "").strip().lower() in (
            "1",
            "true",
            "yes",
        )
    if not use_resp:
        keep = keep[~keep["category"].str.lower().eq("respiratory")]
    keep = keep[~keep["variable"].astype(str).isin(drop)]
    # alias safety: any remaining AST/ALT/bilirubin tokens (alkaline_phosphatase kept)
    vlow = keep["variable"].astype(str).str.lower()
    keep = keep[
        ~vlow.str.contains("aminotransferase", regex=False)
        & ~vlow.str.match(r"bilirubin")
    ]
    rows: list[dict] = []
    order = ["time", "vitals", "laboratory", "medication"] + (
        ["respiratory"] if use_resp else []
    )
    seen: set[str] = set()
    for cat in order:
        sub = keep[keep["category"].str.lower() == cat]
        if cat == "time":
            sub = keep[keep["variable"].astype(str) == "time"]
        for _, r in sub.sort_values("variable").iterrows():
            name = str(r["variable"])
            if name in seen:
                continue
            seen.add(name)
            pn = r.get("printed_name")
            if pd.isna(pn) or not str(pn).strip():
                pn = name.replace("_", " ")
            rows.append(
                {
                    "Role": "Dynamic (hourly tensor)",
                    "Category": _CAT_LAB.get(cat, cat),
                    "Variable": str(pn).replace("_", " "),
                    "Internal name": name.replace("_", " "),
                }
            )
    for internal, lab in _STATIC:
        rows.append(
            {
                "Role": "Static (admission)",
                "Category": "Demographics / anthropometrics",
                "Variable": lab,
                "Internal name": internal,
            }
        )
    return pd.DataFrame(rows)


def feature_counts(df: pd.DataFrame) -> tuple[int, int]:
    n_dyn = int((df["Role"] == "Dynamic (hourly tensor)").sum())
    n_stat = int((df["Role"] == "Static (admission)").sum())
    return n_dyn, n_stat


def write_table_s9(
    tables_dir: Path,
    *,
    ts_csv: Path | None = None,
    drop_vars: Iterable[str] | None = None,
    use_resp: bool | None = None,
    title: str | None = None,
) -> dict:
    """Write ``Table S9. Model feature inventory.xlsx``; return meta dict."""
    tables_dir = Path(tables_dir)
    tables_dir.mkdir(parents=True, exist_ok=True)
    df = build_feature_inventory_df(ts_csv, drop_vars=drop_vars, use_resp=use_resp)
    n_dyn, n_stat = feature_counts(df)
    drop = list(drop_vars if drop_vars is not None else _default_drop())
    drop_lab = ", ".join(x.replace("_", " ") for x in drop) if drop else "(none)"
    title = title or "Table S9. Model feature inventory (hourly tensor and static covariates)"
    footnote = (
        f"Hourly channels n = {n_dyn} (time index + vitals + laboratories + selected medications"
        f"{'' if use_resp else '; respiratory off'}) plus static n = {n_stat} "
        f"(age, sex, height, weight). Inventory follows the published multi-database ICU "
        f"modelling keep-list; cohort-defining laboratories dropped from predictors: {drop_lab}. "
        "Values use observation masks + forward-fill; medications are exposure indicators "
        "(dose > 0). Physiological clip bounds for continuous channels are in Table S1."
    )

    out = tables_dir / "Table S9. Model feature inventory.xlsx"
    wb = Workbook()
    ws = wb.active
    ws.title = "Table"
    ws.sheet_view.showGridLines = False
    cols = list(df.columns)
    nc = len(cols)
    thick = Side(style="medium", color="000000")
    thin = Side(style="thin", color="000000")
    font_title = Font(name="Times New Roman", bold=True, size=12)
    font_h = Font(name="Times New Roman", bold=True, size=12)
    font_b = Font(name="Times New Roman", size=12)
    font_fn = Font(name="Times New Roman", size=10)
    align_c = Alignment(horizontal="center", vertical="center", wrap_text=True)
    align_l = Alignment(horizontal="left", vertical="center", wrap_text=True)

    ws.cell(1, 1, title).font = font_title
    ws.cell(1, 1).alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    if nc > 1:
        ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=nc)
    for j, col in enumerate(cols, 1):
        cell = ws.cell(2, j, col)
        cell.font = font_h
        cell.alignment = align_c
        cell.border = Border(top=thick, bottom=thin)
    for i, row in enumerate(df.itertuples(index=False), 3):
        last = i == 2 + len(df)
        for j, val in enumerate(row, 1):
            cell = ws.cell(i, j, val)
            cell.font = font_b
            cell.alignment = align_l if j == 1 else align_c
            if last:
                cell.border = Border(bottom=thick)
    fr = 2 + len(df) + 2
    cell = ws.cell(fr, 1, footnote)
    cell.font = font_fn
    cell.alignment = align_l
    if nc > 1:
        ws.merge_cells(start_row=fr, start_column=1, end_row=fr, end_column=nc)
    cell.border = Border(top=thin)
    for j in range(1, nc + 1):
        ws.column_dimensions[get_column_letter(j)].width = 30
    wb.save(out)

    methods_snip = (
        f"Model inputs followed prior published multi-database ICU modelling inventories "
        f"(hourly vitals + laboratories + selected medications; "
        f"{'respiratory on' if use_resp else 'respiratory channels off'}; "
        f"static age/sex/height/weight). After dropping laboratories used only to define the "
        f"cohort ({drop_lab}), the hourly tensor used {n_dyn} channels plus {n_stat} static "
        f"covariates (variable-level inventory in Table S9). No additional data-driven feature "
        f"hunting was performed beyond this literature-aligned inventory and the leakage exclusions."
    )
    return {
        "path": str(out),
        "n_dynamic": n_dyn,
        "n_static": n_stat,
        "drop_vars": drop,
        "methods_snip": methods_snip,
    }


def append_training_size_metric_lock(
    md_path: Path,
    *,
    endpoint_auroc: float | None,
    endpoint_mape: float | None,
    table_label: str,
    table_auroc_cell: str,
    table_mape_cell: str,
    warn_spec_cell: str | None = None,
) -> bool:
    """Append a numeric-chain lock paragraph to a training-size image_information md."""
    md_path = Path(md_path)
    if not md_path.exists():
        return False
    text = md_path.read_text(encoding="utf-8")
    if "数字链锁定" in text or "Numeric lock" in text:
        return False
    if endpoint_auroc is None or endpoint_mape is None:
        return False
    warn = ""
    if warn_spec_cell:
        warn = f"；勿与同表 specialization 行 {warn_spec_cell} 混读"
    lock = (
        f"数字链锁定：末点 AUROC {endpoint_auroc:.3f}、MAPE {endpoint_mape:.1f} 与 "
        f"{table_label} Generalization（MIMIC-IV 单训列）Mortality AUROC {table_auroc_cell}、"
        f"MAPE {table_mape_cell} 同源（图面三位小数 vs 表两位）{warn}。\n\n"
    )
    if "## 分析上下文" in text:
        text = text.replace("## 分析上下文", lock + "## 分析上下文", 1)
    else:
        text = text.rstrip() + "\n\n" + lock
    md_path.write_text(text, encoding="utf-8")
    return True


def extract_gen_mimic_cells(xlsx: Path) -> tuple[str | None, str | None, str | None]:
    """Return (auroc_cell, mape_cell, amsterdam_spec_auroc_cell) from a four-strategy table."""
    try:
        from openpyxl import load_workbook
    except ImportError:
        return None, None, None
    if not Path(xlsx).exists():
        return None, None, None
    wb = load_workbook(xlsx, data_only=True)
    ws = wb.active
    rows = [tuple(c.value for c in row) for row in ws.iter_rows(max_col=5)]
    ams_spec = None
    gen_auc = None
    gen_mape = None
    mode = None
    for r in rows:
        lab = str(r[0] or "")
        if lab.startswith("Specialization on Amsterdam"):
            mode = "ams"
            continue
        if lab == "Generalization":
            mode = "gen"
            continue
        if lab.startswith("Mortality") and "AUROC" in lab:
            if mode == "ams" and r[1]:
                ams_spec = str(r[1])
            if mode == "gen" and r[2]:
                gen_auc = str(r[2])
        if lab.startswith("RLoS") and "MAPE" in lab and mode == "gen" and r[2]:
            gen_mape = str(r[2])
    return gen_auc, gen_mape, ams_spec


def endpoint_from_size_md(md_path: Path) -> tuple[float | None, float | None]:
    if not Path(md_path).exists():
        return None, None
    text = Path(md_path).read_text(encoding="utf-8")
    hits = re.findall(
        r"n=\d+:\s*AUROC\s*([0-9.]+),\s*MAPE\s*([0-9.]+)",
        text,
    )
    if not hits:
        return None, None
    a, m = hits[-1]
    try:
        return float(a), float(m)
    except ValueError:
        return None, None


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser(description="Write dbpool Table S9 feature inventory")
    ap.add_argument("--tables", required=True, help="Tables/ directory")
    ap.add_argument("--ts-variables", default="", help="ts_variables.csv path")
    args = ap.parse_args()
    meta = write_table_s9(
        Path(args.tables),
        ts_csv=Path(args.ts_variables) if args.ts_variables else None,
    )
    print(meta)
