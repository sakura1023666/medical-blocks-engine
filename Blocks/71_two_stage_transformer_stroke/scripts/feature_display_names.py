#!/usr/bin/env python3
"""特征 raw 名 → mapping 后展示名（step02 + Baseline 数据字典）。"""
from __future__ import annotations

import csv
from pathlib import Path


def load_column_mapping(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    out: dict[str, str] = {}
    with path.open(encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            o = (row.get("original_name") or "").strip()
            s = (row.get("standard_name") or "").strip()
            if o and s:
                out[o.lower()] = s
                out[o.lower().replace("_", "")] = s
    return out


def load_dict_names(path: Path) -> dict[str, str]:
    """Baseline数据字典：处理后指标名（第1列）。"""
    if not path.exists():
        return {}
    out: dict[str, str] = {}
    with path.open(encoding="utf-8-sig", newline="") as f:
        r = csv.reader(f)
        next(r, None)
        for row in r:
            if not row:
                continue
            name = row[0].strip()
            if not name:
                continue
            out[name.lower()] = name
            out[name.lower().replace("_", "")] = name
            # first_labwbc 等：从 MIMIC 列提示反推
            if len(row) > 3 and row[3]:
                mim = row[3].split("[")[0].strip().lower()
                if mim.startswith("first_lab"):
                    out[mim.replace("first_", "")] = name  # labwbc
                    out[mim.replace("first_lab", "")] = name  # wbc
                if mim.startswith("first_"):
                    out[mim.replace("first_", "")] = name
    return out


def pretty_display(standard: str) -> str:
    """Platelet_Count / CalciumTotal → 可读标签。"""
    s = standard.replace("_", " ")
    # CamelCase split for AnionGap, CalciumTotal
    out = []
    for i, ch in enumerate(s):
        if i > 0 and ch.isupper() and s[i - 1].islower():
            out.append(" ")
        out.append(ch)
    return "".join(out).replace("  ", " ").strip()


def map_feature_names(
    raw_names: list[str],
    mapping_csv: Path | None = None,
    dict_csv: Path | None = None,
) -> list[str]:
    colmap = load_column_mapping(mapping_csv) if mapping_csv else {}
    dnames = load_dict_names(dict_csv) if dict_csv else {}

    mapped: list[str] = []
    for raw in raw_names:
        r = str(raw).strip()
        rl = r.lower()
        key = rl[3:] if rl.startswith("lab") else rl
        key_nos = key.replace("_", "")

        # 1) column mapping（优先）
        std = None
        for cand in (r, rl, key, key_nos, key.title().replace(" ", ""), key.capitalize()):
            # UreaNitrogen special
            pass
        # labureanitrogen -> ureanitrogen -> UreaNitrogen in dict -> BUN via colmap
        dict_hit = dnames.get(rl) or dnames.get(key) or dnames.get(key_nos) or dnames.get("lab" + key)
        if dict_hit:
            std = colmap.get(dict_hit.lower()) or colmap.get(dict_hit.lower().replace("_", "")) or dict_hit
        if std is None:
            # try colmap on stripped forms
            for cand in (key, key_nos, "urea" + "nitrogen" if key == "ureanitrogen" else key):
                # PlateletCount style
                camel = key
                std = colmap.get(camel) or colmap.get(key_nos)
                if std:
                    break
        if std is None:
            # hardcoded fallbacks for this cohort
            hard = {
                "wbc": "WBC",
                "rbc": "RBC",
                "plateletcount": "Platelet_Count",
                "hemoglobin": "Hemoglobin",
                "rdw": "RDW",
                "hematocrit": "Hematocrit",
                "sodium": "Sodium",
                "potassium": "Potassium",
                "calciumtotal": "CalciumTotal",
                "chloride": "Chloride",
                "glucose": "Glucose",
                "aniongap": "AnionGap",
                "pt": "PT",
                "ptt": "PTT",
                "inr": "INR",
                "ureanitrogen": "BUN",
                "creatinine": "Creatinine",
            }
            std = hard.get(key_nos, r)
        # BUN from UreaNitrogen mapping
        if std.lower() in ("ureanitrogen", "urea_nitrogen"):
            std = colmap.get("ureanitrogen", colmap.get("ureanitrogen".replace("_", ""), "BUN"))
            if std.lower().startswith("urea"):
                std = "BUN"
        mapped.append(pretty_display(std))
    return mapped


if __name__ == "__main__":
    repo = Path(__file__).resolve().parents[3]
    raw = [
        "labwbc",
        "labrbc",
        "labplateletcount",
        "labhemoglobin",
        "labrdw",
        "labhematocrit",
        "labsodium",
        "labpotassium",
        "labcalciumtotal",
        "labchloride",
        "labglucose",
        "labaniongap",
        "labpt",
        "labptt",
        "labinr",
        "labureanitrogen",
        "labcreatinine",
    ]
    print(
        map_feature_names(
            raw,
            Path(
                "/mnt/g/02block_result/11_ischemic stroke/two_stage_transformer_40041421/"
                "_shared/step02_column_mapping/column_mapping_log.csv"
            ),
            repo / "Baseline数据字典.csv",
        )
    )
