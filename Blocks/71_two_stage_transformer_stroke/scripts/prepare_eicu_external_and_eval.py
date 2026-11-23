#!/usr/bin/env python3
"""Prepare eICU external npz (aligned to MIMIC-trained F features) and evaluate Day5.

主分析 = MIMIC；外验 = eICU（文献 Fig8 风格：第二库 ROC + confusion matrix）。
支持 AKI / TBI 等：按 data/eicu/*_eicu_*_hourly_full_*.csv 自动解析。
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from collections import defaultdict
from pathlib import Path

os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

import numpy as np

# 发表图强制 Times New Roman（禁 DejaVuSans → QC Layer A4 / nature-figure P0）
_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))
try:
    from tst_mpl_times import setup_times_roman

    setup_times_roman()
except Exception:
    pass


def _to_path(p: str | Path) -> Path:
    """Prefer existing POSIX /mnt/<drive>/ paths on WSL/Linux; only map to X:/ when needed."""
    s = str(p)
    raw = Path(s)
    if raw.exists():
        return raw
    if s.startswith("/mnt/") and len(s) > 7 and s[6] == "/":
        win = Path(f"{s[5].upper()}:/{s[7:]}".replace("\\", "/"))
        if win.exists():
            return win
        # WSL: keep /mnt/g/... even if mid-flight mkdir target does not exist yet
        return raw
    return raw


def _open_csv(path: Path):
    """utf-8-sig 去 BOM，避免首列变成 \\ufeffpatientunitstayid。"""
    return path.open(newline="", encoding="utf-8-sig", errors="replace")


# eICU raw item → canonical（优先精确匹配；含缺血性卒中序列矩阵列名）
EICU_ALIASES: dict[str, list[str]] = {
    "heart_rate": ["Heart Rate", "heartrate"],
    "heartrate": ["heartrate", "Heart Rate"],
    "respiratory_rate": ["Respiratory Rate", "RR (patient)", "Total RR", "respiration"],
    "respiration": ["respiration", "Respiratory Rate", "RR (patient)"],
    "spo2": ["O2 Sat (%)", "SpO2", "O2 Saturation", "SaO2", "sao2"],
    "sao2": ["sao2", "SaO2", "O2 Sat (%)", "SpO2", "O2 Saturation"],
    # MIMIC train temperature_c 实为 °F；Temperature (F) 直接映射，(C) 在 ingest 里转 °F
    "temperature_c": ["Temperature (C)", "Temperature", "Temperature (F)", "temperature"],
    "temperature": ["temperature", "Temperature (C)", "Temperature", "Temperature (F)"],
    "nibp_systolic": ["NIBP systolic", "Non-Invasive BP Systolic", "noninvasivesystolic"],
    "nibp_diastolic": ["NIBP diastolic", "Non-Invasive BP Diastolic", "noninvasivediastolic"],
    "nibp_mean": ["NIBP mean", "Non-Invasive BP Mean", "noninvasivemean"],
    "noninvasivesystolic": ["noninvasivesystolic", "NIBP systolic", "Non-Invasive BP Systolic"],
    "noninvasivediastolic": ["noninvasivediastolic", "NIBP diastolic", "Non-Invasive BP Diastolic"],
    "noninvasivemean": ["noninvasivemean", "NIBP mean", "Non-Invasive BP Mean"],
    "systemicsystolic": ["systemicsystolic", "Systemic Systolic", "Arterial BP Systolic"],
    "systemicdiastolic": ["systemicdiastolic", "Systemic Diastolic", "Arterial BP Diastolic"],
    "systemicmean": ["systemicmean", "Systemic Mean", "Arterial BP Mean", "Arterial BP mean"],
    # eICU 可有 GCS Total 或 Eyes/Motor/Verbal；Total 在 ingest 里按 E4:M6:V5 拆分
    "gcs_eye": ["GCS Eye Opening", "Eyes", "Eye Opening"],
    "gcs_motor": ["GCS Motor Response", "Motor"],
    "gcs_verbal": ["GCS Verbal Response", "Verbal"],
    "rass": ["Sedation Score", "RASS", "Richmond Agitation-Sedation Scale", "Richmond Agitation Sedation Scale"],
    "creatinine": ["creatinine"],
    "bun": ["BUN", "bun"],
    "sodium": ["sodium"],
    "potassium": ["potassium"],
    "chloride": ["chloride"],
    "bicarbonate": ["bicarbonate", "HCO3"],
    "anion_gap": ["anion gap", "anion_gap"],
    "calcium": ["calcium"],
    "urine_output": ["Urine", "Urine Output (mL)-Urethral Catheter", "URINE CATHETER"],
    "ultrafiltrate": ["Ultrafiltrate Output"],
    "norepinephrine": [
        "Norepinephrine (mcg/kg/min)", "Norepinephrine (mcg/min)",
        "Norepinephrine (ml/hr)", "norepinephrine", "Norepinephrine",
    ],
    "phenylephrine": [
        "Phenylephrine (mcg/min)", "Phenylephrine (mcg/kg/min)", "Phenylephrine (ml/hr)", "phenylephrine",
    ],
    "vasopressin": ["Vasopressin (units/min)", "Vasopressin (ml/hr)", "Vasopressin", "VASOPRESSIN", "vasopressin"],
    "epinephrine": ["Epinephrine (mcg/min)", "Epinephrine (mcg/kg/min)", "Epinephrine (ml/hr)", "Epinephrine drip"],
    "dopamine": ["Dopamine (mcg/kg/min)", "Dopamine (ml/hr)", "Dopamine"],
    "dobutamine": ["Dobutamine (mcg/kg/min)", "Dobutamine", "DOBUTamine"],
    "propofol": ["Propofol (mcg/kg/min)", "Propofol (ml/hr)", "Propofol", "propofol"],
    "fentanyl": ["Fentanyl (mcg/hr)", "Fentanyl (ml/hr)", "Fentanyl", "fentanyl", "Fentanyl IV"],
    "insulin": ["Insulin (units/hr)", "Insulin (ml/hr)", "Insulin", "insulin regular", "INsulin IV"],
    "daily_weight": ["Bodyweight (kg)", "Bodyweight (lb)", "Daily Weight"],
    "cvp": ["CVP", "cvp"],
    "fio2": ["FiO2", "Set Fraction of Inspired Oxygen (FIO2)", "FIO2 (%)", "Inspired O2 Fraction"],
    "peep": ["PEEP", "PEEP/CPAP", "PEEP set"],
    "abp_mean": ["Arterial BP mean", "Invasive BP Mean", "Arterial Blood Pressure mean", "systemicmean"],
    "magnesium": ["magnesium", "Magnesium"],
    "phosphate": ["phosphate"],
    "glucose": ["glucose", "bedside glucose", "Bedside Glucose"],
    "wbc": ["WBC x 1000", "wbc"],
    "hgb": ["Hgb", "hgb"],
    "hct": ["Hct", "hct"],
    "platelets": ["platelets x 1000", "platelets"],
    "rbc": ["RBC"],
    "mcv": ["MCV", "mcv"],
    "mch": ["MCH"],
    "mchc": ["MCHC"],
    "rdw": ["RDW", "rdw"],
    "inr": ["PT - INR", "inr"],
    "pt": ["PT", "pt"],
    "ptt": ["PTT", "ptt"],
    "ph": ["pH", "ph"],
    "lactate": ["lactate"],
    "base_excess": ["Base Excess", "base_excess"],
    "pao2": ["paO2", "pao2"],
    "paco2": ["paCO2", "paco2"],
    "total_co2": ["Total CO2"],
    "albumin": ["albumin"],
    "alt": ["ALT (SGPT)", "alt", "ALT"],
    "ast": ["AST (SGOT)", "ast", "AST"],
    "lymphs": ["-lymphs", "lymphs", "lymphocytes"],
    "polys": ["-polys", "polys", "neutrophils"],
    "total_rr": ["Total RR", "total_rr", "RR (patient)"],
    "lpm_o2": ["LPM O2", "lpm_o2"],
    "peak_insp_pressure": ["Peak Insp. Pressure", "peak_insp_pressure"],
    "plateau_pressure": ["Plateau Pressure", "plateau_pressure"],
    "mean_airway_pressure": ["Mean Airway Pressure", "mean_airway_pressure"],
    "tidal_volume_set": ["Tidal Volume (set)", "tidal_volume_set"],
    "vent_rate": ["Vent Rate", "vent_rate"],
    "exhaled_mv": ["Exhaled MV", "exhaled_mv"],
}

# 宽表序列矩阵列 → MIMIC 特征名（卒中 72 特征矩阵）
SEQ_COL_TO_FEAT: dict[str, str] = {
    "heartrate": "heartrate",
    "respiration": "respiration",
    "temperature": "temperature",
    "systemicmean": "systemicmean",
    "systemicsystolic": "systemicsystolic",
    "systemicdiastolic": "systemicdiastolic",
    "noninvasivemean": "noninvasivemean",
    "noninvasivesystolic": "noninvasivesystolic",
    "noninvasivediastolic": "noninvasivediastolic",
    "sao2": "sao2",
    "SaO2": "sao2",
    "O2 Sat (%)": "sao2",
    "Total RR": "total_rr",
    "RR (patient)": "total_rr",
    "glucose": "glucose",
    "bedside glucose": "glucose",
    "creatinine": "creatinine",
    "BUN": "bun",
    "bicarbonate": "bicarbonate",
    "HCO3": "bicarbonate",
    "anion gap": "anion_gap",
    "calcium": "calcium",
    "sodium": "sodium",
    "potassium": "potassium",
    "chloride": "chloride",
    "magnesium": "magnesium",
    "phosphate": "phosphate",
    "lactate": "lactate",
    "albumin": "albumin",
    "WBC x 1000": "wbc",
    "-lymphs": "lymphs",
    "-polys": "polys",
    "Hgb": "hgb",
    "Hct": "hct",
    "RDW": "rdw",
    "platelets x 1000": "platelets",
    "MCV": "mcv",
    "PT": "pt",
    "PTT": "ptt",
    "PT - INR": "inr",
    "pH": "ph",
    "paCO2": "paco2",
    "paO2": "pao2",
    "Base Excess": "base_excess",
    "FiO2": "fio2",
    "PEEP": "peep",
    "LPM O2": "lpm_o2",
    "Peak Insp. Pressure": "peak_insp_pressure",
    "Plateau Pressure": "plateau_pressure",
    "Mean Airway Pressure": "mean_airway_pressure",
    "Tidal Volume (set)": "tidal_volume_set",
    "Vent Rate": "vent_rate",
    "Exhaled MV": "exhaled_mv",
    "ALT (SGPT)": "alt",
    "AST (SGOT)": "ast",
}


def _resolve_eicu_root(proj: Path) -> Path:
    """Linux 区分大小写：优先 data/eicu，其次 data/eICU / EICU。"""
    for name in ("eicu", "eICU", "EICU", "Eicu"):
        p = proj / "data" / name
        if p.is_dir():
            return p
    raise SystemExit(f"eICU: missing data/eicu under {proj / 'data'}")


def _resolve_eicu_hourly(eicu_root: Path) -> Path | None:
    """Prefer disease hourly extract; fall back to legacy AKI filename.

    若仅有卒中宽表序列矩阵，返回 None（由 prepare_eicu_npz_from_seq 接手）。
    """
    legacy = eicu_root / "374_eicu_aki_hourly_full_10d.csv"
    hits = sorted(eicu_root.glob("*_eicu_*_hourly_full_*.csv"))
    # 物化长表若存在也算
    hits = [p for p in hits if p.is_file()]
    if hits:
        def _rank(p: Path) -> tuple:
            n = p.name.lower()
            pri = 0 if ("tbi" in n or "aki" in n or "stroke" in n) else 1
            return (pri, -p.stat().st_size, p.name)

        return sorted(hits, key=_rank)[0]
    if legacy.is_file():
        return legacy
    return None


def _find_seq_matrix(eicu_root: Path) -> Path | None:
    cands = sorted(eicu_root.glob("序列矩阵*.csv")) + sorted(eicu_root.glob("*seq*matrix*.csv"))
    for p in cands:
        if p.is_file() and p.stat().st_size > 1000:
            return p
    return None


def prepare_eicu_npz_from_seq(
    *,
    seq_csv: Path,
    dabiao: Path,
    prognosis: Path,
    feat_names: list[str],
    out_npz: Path,
    max_day: int = 5,
    n_hours: int = 24,
    static_map: dict[int, dict[str, float]] | None = None,
    source_label: str = "eICU seq-matrix dabiao ∩ prognosis",
    min_age: float | None = 18.0,
) -> dict:
    """宽表序列矩阵直接落 npz（避免物化巨型长表）。"""
    ids = _load_ids(dabiao)
    y_map = _load_outcomes(prognosis)
    keep = sorted(pid for pid in ids if pid in y_map)
    if not keep:
        raise SystemExit("eICU: no overlapping dabiao ∩ prognosis IDs")
    static_map = static_map or {}
    keep, age_meta = _apply_min_age(keep, static_map, min_age=min_age)
    if not keep:
        raise SystemExit("eICU: no IDs left after min_age filter")
    keep_set = set(keep)
    feat_idx = {f: i for i, f in enumerate(feat_names)}
    col_fi: dict[str, int] = {}
    with seq_csv.open(newline="", encoding="utf-8-sig", errors="replace") as f:
        header = next(csv.reader(f))
    for col in header:
        if col.endswith("_mask"):
            continue
        feat = SEQ_COL_TO_FEAT.get(col)
        if feat is None:
            continue
        fi = feat_idx.get(feat)
        if fi is not None:
            col_fi[col] = fi
    if not col_fi:
        raise SystemExit(f"eICU: seq matrix maps 0/{len(feat_names)} features: {seq_csv}")

    # pid -> day,hod,fi -> values
    buckets: dict[int, dict[tuple[int, int, int], list[float]]] = defaultdict(lambda: defaultdict(list))
    n_rows = 0
    n_hit = 0
    with seq_csv.open(newline="", encoding="utf-8-sig", errors="replace") as f:
        for row in csv.DictReader(f):
            n_rows += 1
            try:
                pid = int(float(row["patientunitstayid"]))
                h_abs = int(float(row.get("h") or row.get("hour") or -1))
            except (TypeError, ValueError, KeyError):
                continue
            if pid not in keep_set or h_abs < 0:
                continue
            day = h_abs // n_hours
            hod = h_abs % n_hours
            if day >= max_day:
                continue
            for col, fi in col_fi.items():
                mask_col = f"{col}_mask"
                if mask_col in row:
                    try:
                        if float(row[mask_col] or 0) < 0.5:
                            continue
                    except (TypeError, ValueError):
                        continue
                raw = row.get(col, "")
                if raw is None or str(raw).strip() == "":
                    continue
                try:
                    val = float(raw)
                except (TypeError, ValueError):
                    continue
                if val != val:
                    continue
                buckets[pid][(day, hod, fi)].append(val)
                n_hit += 1

    pids = [pid for pid in keep if pid in buckets] or list(keep)
    n = len(pids)
    F = len(feat_names)
    X = np.full((n, max_day, n_hours, F), np.nan, dtype=np.float32)
    y = np.zeros(n, dtype=np.int64)
    day_mask = np.zeros((n, max_day), dtype=np.float32)
    pid_arr = np.asarray(pids, dtype=np.int64)
    n_static_filled = 0
    for i, pid in enumerate(pids):
        y[i] = int(y_map[pid])
        for (day, hod, fi), vals in buckets.get(pid, {}).items():
            X[i, day, hod, fi] = float(np.nanmean(vals))
        for d in range(max_day):
            if np.isfinite(X[i, d]).any():
                day_mask[i, d] = 1.0
        st = static_map.get(pid) or {}
        if st:
            for d in range(max_day):
                if day_mask[i, d] < 0.5:
                    continue
                for fname, fval in st.items():
                    fi = feat_idx.get(fname)
                    if fi is None:
                        continue
                    X[i, d, :, fi] = float(fval)
                    n_static_filled += 1
        for f in range(F):
            flat = X[i, :, :, f].reshape(-1)
            last = np.nan
            for t in range(flat.size):
                if np.isfinite(flat[t]):
                    last = flat[t]
                elif np.isfinite(last):
                    flat[t] = last
            X[i, :, :, f] = flat.reshape(max_day, n_hours)
        X[i] = np.nan_to_num(X[i], nan=0.0)

    ok = day_mask.sum(1) > 0
    X, y, day_mask, pid_arr = X[ok], y[ok], day_mask[ok], pid_arr[ok]
    out_npz.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        out_npz,
        X=X,
        y=y,
        day_mask=day_mask,
        patient_id=pid_arr,
        feature_names=np.asarray(feat_names, dtype="U64"),
    )
    meta = {
        "n": int(len(y)),
        "n_pos": int(y.sum()),
        "n_neg": int((y == 0).sum()),
        "F": F,
        "D": max_day,
        "H": n_hours,
        "n_rows_scanned": n_rows,
        "n_mapped_hits": n_hit,
        "n_static_patient_fills": int(n_static_filled),
        "n_static_ids": int(len(static_map)),
        "features_with_any_data": int((np.abs(X).sum(axis=(0, 1, 2)) > 0).sum()),
        "mapped_seq_cols": sorted(col_fi.keys()),
        "is_synthetic": False,
        "source": source_label,
        "hourly_csv": seq_csv.name,
        "min_age_filter": age_meta,
        "align_notes": "wide seq-matrix → npz; mask columns honored; static_* broadcast",
    }
    (out_npz.parent / "eicu_external_meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(
        f"[eicu_prep:seq] n={meta['n']} dead={meta['n_pos']} alive={meta['n_neg']} F={F} "
        f"hits={n_hit} mapped_cols={len(col_fi)} static_ids={len(static_map)}"
    )
    print(f"[eicu_prep:seq] wrote {out_npz}")
    return meta


def _ensure_prognosis(eicu_root: Path) -> Path:
    """缺 EICU预后数据-all.csv 时从卒中 DN1 / 样本表生成。"""
    prog = eicu_root / "EICU预后数据-all.csv"
    if prog.is_file():
        return prog
    src = None
    for name in (
        "卒中队列_DN1_1642.csv",
        "eICU-缺血性卒中-样本_200859.csv",
        "dabiao.csv",
    ):
        p = eicu_root / name
        if p.is_file():
            src = p
            break
    if src is None:
        raise SystemExit(f"missing prognosis: {prog} (and no DN1/dabiao fallback)")
    n = 0
    with src.open(newline="", encoding="utf-8-sig", errors="replace") as f, prog.open(
        "w", encoding="utf-8", newline=""
    ) as g:
        r = csv.DictReader(f)
        w = csv.writer(g)
        w.writerow(["patientunitstayid", "hospitaldischargestatus", "unitdischargestatus"])
        for row in r:
            try:
                pid = int(float(row.get("patientunitstayid") or row.get("stay_id") or ""))
            except (TypeError, ValueError):
                continue
            st = str(row.get("hospitaldischargestatus") or row.get("hospdischargestatus") or "").strip()
            if not st or st.lower() in ("nan", "none", "na"):
                continue
            w.writerow([pid, st, ""])
            n += 1
    if n < 20:
        raise SystemExit(f"eICU: prognosis fallback too small n={n} from {src.name}")
    print(f"[eicu_prep] built prognosis n={n} from {src.name} -> {prog.name}")
    return prog


def _ensure_static_features(eicu_root: Path) -> Path:
    """从 静态特征_*.csv 写出 eicu_static_features.csv（static_* 列）。"""
    out = eicu_root / "eicu_static_features.csv"
    if out.is_file() and out.stat().st_size > 100:
        return out
    src = None
    for p in sorted(eicu_root.glob("静态特征*.csv")) + sorted(eicu_root.glob("*static*.csv")):
        if p.name == out.name:
            continue
        if p.is_file():
            src = p
            break
    if src is None:
        print("[eicu_prep] no static feature table; continue without static_*")
        return out
    n = 0
    with src.open(newline="", encoding="utf-8-sig", errors="replace") as f, out.open(
        "w", encoding="utf-8", newline=""
    ) as g:
        r = csv.DictReader(f)
        fields = [
            "patientunitstayid",
            "static_Age",
            "static_Gender",
            "static_Weight",
            "static_GCS",
            "static_eyes",
            "static_motor",
            "static_verbal",
            "static_Ventilation",
            "static_intubated",
            "static_dialysis",
        ]
        w = csv.DictWriter(g, fieldnames=fields)
        w.writeheader()
        for row in r:
            try:
                pid = int(float(row["patientunitstayid"]))
            except (TypeError, ValueError, KeyError):
                continue

            def _f(*keys: str) -> float | None:
                for k in keys:
                    if k in row and str(row[k]).strip() not in ("", "nan", "None", "NA"):
                        try:
                            v = float(row[k])
                        except (TypeError, ValueError):
                            continue
                        if v == v:
                            return v
                return None

            age = _f("age", "Age", "age_num", "static_Age")
            gender = _f("gender", "Gender", "static_Gender")
            weight = _f("admissionweight", "weight", "Weight", "static_Weight")
            eyes = _f("eyes", "static_eyes")
            motor = _f("motor", "static_motor")
            verbal = _f("verbal", "static_verbal")
            gcs = _f("GCS", "gcs", "static_GCS")
            if gcs is None and None not in (eyes, motor, verbal):
                gcs = float(eyes) + float(motor) + float(verbal)
            vent = _f("vent", "Ventilation", "static_Ventilation")
            intu = _f("intubated", "static_intubated")
            dial = _f("dialysis", "static_dialysis")
            rec = {
                "patientunitstayid": pid,
                "static_Age": "" if age is None else age,
                "static_Gender": "" if gender is None else gender,
                "static_Weight": "" if weight is None else weight,
                "static_GCS": "" if gcs is None else gcs,
                "static_eyes": "" if eyes is None else eyes,
                "static_motor": "" if motor is None else motor,
                "static_verbal": "" if verbal is None else verbal,
                "static_Ventilation": "" if vent is None else vent,
                "static_intubated": "" if intu is None else intu,
                "static_dialysis": "" if dial is None else dial,
            }
            w.writerow(rec)
            n += 1
    print(f"[eicu_prep] built static features n={n} from {src.name} -> {out.name}")
    return out


def _ensure_dabiao(eicu_root: Path, hourly: Path | None = None) -> Path:
    dabiao = eicu_root / "dabiao.csv"
    if dabiao.is_file():
        return dabiao
    # 卒中 DN1 优先（首次 ICU 主口径）
    for name in ("卒中队列_DN1_1642.csv",):
        src = eicu_root / name
        if src.is_file():
            ids: set[int] = set()
            with src.open(newline="", encoding="utf-8-sig", errors="replace") as f:
                for row in csv.DictReader(f):
                    try:
                        ids.add(int(float(row["patientunitstayid"])))
                    except (TypeError, ValueError, KeyError):
                        continue
            if ids:
                with dabiao.open("w", encoding="utf-8", newline="") as f:
                    w = csv.writer(f)
                    w.writerow(["patientunitstayid"])
                    for i in sorted(ids):
                        w.writerow([i])
                print(f"[eicu_prep] dabiao from {name} n={len(ids)} -> {dabiao}")
                return dabiao
    ids: set[int] = set()
    src_for_ids = hourly if hourly is not None else _find_seq_matrix(eicu_root)
    if src_for_ids is None:
        raise SystemExit("eICU: cannot build dabiao — no hourly/seq source")
    with src_for_ids.open(newline="", encoding="utf-8-sig", errors="replace") as f:
        for row in csv.DictReader(f):
            try:
                ids.add(int(float(row["patientunitstayid"])))
            except (TypeError, ValueError, KeyError):
                continue
    if not ids:
        raise SystemExit("eICU: cannot build dabiao — no patientunitstayid in source")
    with dabiao.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["patientunitstayid"])
        for i in sorted(ids):
            w.writerow([i])
    print(f"[eicu_prep] auto-built dabiao n={len(ids)} -> {dabiao}")
    return dabiao


def _load_static_features(path: Path) -> dict[int, dict[str, float]]:
    """patientunitstayid -> {static_*: value}."""
    if not path.is_file():
        return {}
    out: dict[int, dict[str, float]] = {}
    with path.open(newline="", encoding="utf-8-sig", errors="replace") as f:
        for row in csv.DictReader(f):
            try:
                pid = int(float(row["patientunitstayid"]))
            except (TypeError, ValueError, KeyError):
                continue
            vals: dict[str, float] = {}
            for k, v in row.items():
                if not k or k == "patientunitstayid" or not str(k).startswith("static_"):
                    continue
                try:
                    fv = float(v)
                except (TypeError, ValueError):
                    continue
                if fv == fv:  # not NaN
                    vals[k] = fv
            if vals:
                out[pid] = vals
    return out


def _build_item_to_feat(feat_names: list[str]) -> dict[str, str]:
    """raw item (exact) -> feature name."""
    out: dict[str, str] = {}
    for feat in feat_names:
        for alias in EICU_ALIASES.get(feat, [feat]):
            if alias not in out:
                out[alias] = feat
    return out


def _split_gcs_total(total: float) -> tuple[float, float, float]:
    """Decompose GCS Total (3–15) into Eye(1–4)/Motor(1–6)/Verbal(1–5) by E4:M6:V5 weights."""
    t = float(np.clip(total, 3.0, 15.0))
    # proportional weights sum to 15
    eye = 1.0 + (t - 3.0) * (3.0 / 12.0)  # 3→1, 15→4
    motor = 1.0 + (t - 3.0) * (5.0 / 12.0)  # 3→1, 15→6
    verbal = 1.0 + (t - 3.0) * (4.0 / 12.0)  # 3→1, 15→5
    return (
        float(np.clip(eye, 1.0, 4.0)),
        float(np.clip(motor, 1.0, 6.0)),
        float(np.clip(verbal, 1.0, 5.0)),
    )


def _to_mimic_temperature_f(val: float) -> float:
    """MIMIC train temperature_c 实为 °F（p50≈98.2）；eICU 多为 °C → 转 °F。"""
    if val < 50.0:  # clearly Celsius
        return val * 1.8 + 32.0
    return val


def _load_ids(dabiao: Path) -> set[int]:
    ids: set[int] = set()
    with dabiao.open(newline="", encoding="utf-8-sig", errors="replace") as f:
        for row in csv.DictReader(f):
            key = row.get("patientunitstayid") or row.get("stay_id") or next(iter(row.values()))
            try:
                ids.add(int(float(key)))
            except (TypeError, ValueError):
                continue
    return ids


def _load_outcomes(prog: Path) -> dict[int, int]:
    """patientunitstayid -> is_hosp_dead (1/0)."""
    out: dict[int, int] = {}
    with prog.open(newline="", encoding="utf-8-sig", errors="replace") as f:
        for row in csv.DictReader(f):
            try:
                pid = int(float(row["patientunitstayid"]))
            except (TypeError, ValueError, KeyError):
                continue
            st = str(
                row.get("hospitaldischargestatus")
                or row.get("hospdischargestatus")
                or ""
            ).strip().lower()
            if st in ("expired", "dead", "death", "1", "true"):
                out[pid] = 1
            elif st in ("alive", "home", "0", "false") or "alive" in st:
                out[pid] = 0
            else:
                # unit status fallback
                ust = str(row.get("unitdischargestatus") or "").strip().lower()
                if ust == "expired":
                    out[pid] = 1
                elif ust == "alive":
                    out[pid] = 0
    return out


def _apply_min_age(
    keep: list[int],
    static_map: dict[int, dict[str, float]],
    *,
    min_age: float | None,
) -> tuple[list[int], dict]:
    """与主库 tst_cohort$min_age 对齐：外验剔除年龄 < min_age（缺年龄也剔除）。"""
    meta = {
        "min_age": min_age,
        "n_before": len(keep),
        "n_after": len(keep),
        "n_dropped_age_lt": 0,
        "n_dropped_age_missing": 0,
    }
    if min_age is None:
        return keep, meta
    out: list[int] = []
    n_lt = 0
    n_miss = 0
    for pid in keep:
        vals = static_map.get(int(pid), {}) or {}
        age = vals.get("static_Age", vals.get("Age", vals.get("age")))
        if age is None or (isinstance(age, float) and age != age):
            n_miss += 1
            continue
        if float(age) < float(min_age):
            n_lt += 1
            continue
        out.append(pid)
    meta["n_after"] = len(out)
    meta["n_dropped_age_lt"] = n_lt
    meta["n_dropped_age_missing"] = n_miss
    print(
        f"[eicu_prep] min_age>={min_age}: {meta['n_before']} → {meta['n_after']} "
        f"(dropped_lt={n_lt}, dropped_missing_age={n_miss})"
    )
    return out, meta


def prepare_eicu_npz(
    *,
    hourly_csv: Path,
    dabiao: Path,
    prognosis: Path,
    feat_names: list[str],
    out_npz: Path,
    max_day: int = 5,
    n_hours: int = 24,
    static_map: dict[int, dict[str, float]] | None = None,
    source_label: str = "eICU dabiao ∩ prognosis",
    min_age: float | None = 18.0,
) -> dict:
    ids = _load_ids(dabiao)
    y_map = _load_outcomes(prognosis)
    keep = sorted(pid for pid in ids if pid in y_map)
    if not keep:
        raise SystemExit("eICU: no overlapping dabiao ∩ prognosis IDs")
    static_map = static_map or {}
    keep, age_meta = _apply_min_age(keep, static_map, min_age=min_age)
    if not keep:
        raise SystemExit("eICU: no IDs left after min_age filter")

    item_map = _build_item_to_feat(feat_names)
    feat_idx = {f: i for i, f in enumerate(feat_names)}
    has_gcs = all(k in feat_idx for k in ("gcs_eye", "gcs_motor", "gcs_verbal"))
    keep_set = set(keep)

    # collect values: pid -> day -> hour -> feat -> list
    # hour from CSV is ICU hour offset; day = hour // 24, hod = hour % 24
    buckets: dict[int, dict[tuple[int, int, int], list[float]]] = defaultdict(lambda: defaultdict(list))
    n_rows = 0
    n_hit = 0
    n_gcs_split = 0
    n_temp_c2f = 0
    n_lb2kg = 0
    with hourly_csv.open(newline="", encoding="utf-8-sig", errors="replace") as f:
        for row in csv.DictReader(f):
            n_rows += 1
            try:
                pid = int(float(row["patientunitstayid"]))
            except (TypeError, ValueError, KeyError):
                continue
            if pid not in keep_set:
                continue
            item = (row.get("item") or "").strip()
            try:
                h_abs = int(float(row["hour"]))
                val = float(row["mean"])
            except (TypeError, ValueError, KeyError):
                continue
            if h_abs < 0 or val != val:
                continue
            day = h_abs // n_hours  # 0-based
            hod = h_abs % n_hours
            if day >= max_day:
                continue

            # GCS Total → split into E/M/V (eICU 无分项时)
            if item.lower() == "gcs total" and has_gcs:
                eye, motor, verbal = _split_gcs_total(val)
                buckets[pid][(day, hod, feat_idx["gcs_eye"])].append(eye)
                buckets[pid][(day, hod, feat_idx["gcs_motor"])].append(motor)
                buckets[pid][(day, hod, feat_idx["gcs_verbal"])].append(verbal)
                n_hit += 3
                n_gcs_split += 1
                continue

            feat = item_map.get(item)
            if feat is None:
                # case-insensitive fallback
                feat = next((item_map[k] for k in item_map if k.lower() == item.lower()), None)
            if feat is None:
                continue
            if feat == "temperature_c":
                # Temperature (F) already °F; (C)/generic convert if clearly Celsius
                if " (f)" in item.lower() or item.lower().endswith("(f)"):
                    pass
                else:
                    new_v = _to_mimic_temperature_f(val)
                    if new_v != val:
                        n_temp_c2f += 1
                    val = new_v
            if feat == "daily_weight" and " (lb)" in item.lower():
                val = val * 0.45359237
                n_lb2kg += 1
            fi = feat_idx[feat]
            buckets[pid][(day, hod, fi)].append(val)
            n_hit += 1

    pids = [pid for pid in keep if pid in buckets]
    if len(pids) < 20:
        # fall back: any with outcome even if sparse
        pids = keep
    n = len(pids)
    F = len(feat_names)
    X = np.full((n, max_day, n_hours, F), np.nan, dtype=np.float32)
    y = np.zeros(n, dtype=np.int64)
    day_mask = np.zeros((n, max_day), dtype=np.float32)
    pid_arr = np.asarray(pids, dtype=np.int64)
    n_static_filled = 0

    for i, pid in enumerate(pids):
        y[i] = int(y_map[pid])
        for (day, hod, fi), vals in buckets.get(pid, {}).items():
            X[i, day, hod, fi] = float(np.nanmean(vals))
        # day_mask 仅按动态特征有值判定（勿因 static 广播把短住院算成 Day5 可用）
        for d in range(max_day):
            if np.isfinite(X[i, d]).any():
                day_mask[i, d] = 1.0
        # broadcast static_* 到有动态观测的 day
        st = static_map.get(pid) or {}
        if st:
            for d in range(max_day):
                if day_mask[i, d] < 0.5:
                    continue
                for fname, fval in st.items():
                    fi = feat_idx.get(fname)
                    if fi is None:
                        continue
                    X[i, d, :, fi] = float(fval)
                    n_static_filled += 1
        # patient-level forward fill across hour then day for each feature
        for f in range(F):
            flat = X[i, :, :, f].reshape(-1)
            last = np.nan
            for t in range(flat.size):
                if np.isfinite(flat[t]):
                    last = flat[t]
                elif np.isfinite(last):
                    flat[t] = last
            X[i, :, :, f] = flat.reshape(max_day, n_hours)
        # remaining nan → 0
        X[i] = np.nan_to_num(X[i], nan=0.0)

    # drop patients with no day mask at all
    ok = day_mask.sum(1) > 0
    X, y, day_mask, pid_arr = X[ok], y[ok], day_mask[ok], pid_arr[ok]

    out_npz.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        out_npz,
        X=X,
        y=y,
        day_mask=day_mask,
        patient_id=pid_arr,
        feature_names=np.asarray(feat_names, dtype="U64"),
    )
    meta = {
        "n": int(len(y)),
        "n_pos": int(y.sum()),
        "n_neg": int((y == 0).sum()),
        "F": F,
        "D": max_day,
        "H": n_hours,
        "n_rows_scanned": n_rows,
        "n_mapped_hits": n_hit,
        "n_gcs_total_split": n_gcs_split,
        "n_temp_c_to_f": n_temp_c2f,
        "n_weight_lb_to_kg": n_lb2kg,
        "n_static_patient_fills": int(n_static_filled),
        "n_static_ids": int(len(static_map)),
        "features_with_any_data": int((np.abs(X).sum(axis=(0, 1, 2)) > 0).sum()),
        "is_synthetic": False,
        "source": source_label,
        "hourly_csv": hourly_csv.name,
        "min_age_filter": age_meta,
        "align_notes": (
            "GCS Total→E/M/V (E4:M6:V5) if needed; Eyes/Motor/Verbal direct; "
            "temperature °C→°F; Bodyweight lb→kg; static_* from eicu_static_features.csv; "
            "min_age synced with MIMIC tst_cohort when set"
        ),
    }
    (out_npz.parent / "eicu_external_meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(
        f"[eicu_prep] n={meta['n']} dead={meta['n_pos']} alive={meta['n_neg']} F={F} "
        f"hits={n_hit} gcs_split={n_gcs_split} temp_c2f={n_temp_c2f} "
        f"static_ids={len(static_map)}"
    )
    print(f"[eicu_prep] wrote {out_npz}")
    return meta


def _rank01(x: np.ndarray) -> np.ndarray:
    """Average-rank → (0,1]; NaN stays NaN."""
    x = np.asarray(x, dtype=float)
    out = np.full_like(x, np.nan, dtype=float)
    m = np.isfinite(x)
    if int(m.sum()) < 2:
        return out
    order = np.argsort(np.argsort(x[m]))
    out[m] = (order + 1.0) / (float(m.sum()) + 1e-9)
    return out


def _load_severity_map(path: Path, score_name: str) -> dict[int, float]:
    if not path.is_file():
        return {}
    out: dict[int, float] = {}
    with path.open(newline="", encoding="utf-8-sig", errors="replace") as f:
        for row in csv.DictReader(f):
            try:
                raw_id = row.get("patientunitstayid") or row.get("stay_id")
                pid = int(float(raw_id))
                val = float(row[score_name])
            except (TypeError, ValueError, KeyError):
                continue
            if val == val:
                out[pid] = val
    return out


def evaluate_and_plot(
    *,
    npz_path: Path,
    model_path: Path,
    out_pdf: Path,
    repo: Path,
    day: int = 5,
    blend_score: str = "",
    tf_weight: float = 0.4,
    severity_csv: Path | None = None,
) -> dict:
    sys.path.insert(0, str(repo))
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    # 图面强制 Times（禁 DejaVuSans P0）
    try:
        from tst_mpl_times import setup_times_roman

        setup_times_roman()
    except Exception:
        matplotlib.rcParams["font.family"] = "serif"
        matplotlib.rcParams["font.serif"] = ["Times New Roman", "Liberation Serif", "Nimbus Roman"]
        matplotlib.rcParams["pdf.fonttype"] = 42
    from sklearn.metrics import roc_auc_score, roc_curve
    import torch
    from torch.utils.data import DataLoader

    from python.two_stage_transformer.dataloader import TSTDataset
    from python.two_stage_transformer.eval import load_model_for_eval, score_all_cutoffs

    ds = TSTDataset(npz_path=str(npz_path))
    D, H, F = ds.n_days, ds.n_hours, ds.n_features
    model = load_model_for_eval(str(model_path), "b", D, H, F)
    dl = DataLoader(ds, batch_size=64, shuffle=False)
    scores = score_all_cutoffs(model, dl, D)
    y = ds.y.astype(int)
    los = ds.day_mask.sum(1).astype(int)
    day = min(day, D)
    sel = los >= day
    yy = y[sel]
    ss_tf = np.asarray(scores[day][sel], dtype=float)
    raw = np.load(npz_path, allow_pickle=True)
    pids = np.asarray(raw["patient_id"], dtype=int)[sel]

    method = "TF_alone"
    tf_alone_auc = float(roc_auc_score(yy, ss_tf)) if len(np.unique(yy)) > 1 else float("nan")
    score_alone_auc = float("nan")
    w_tf = float(tf_weight)
    w_tf = min(max(w_tf, 0.0), 1.0)
    ss = ss_tf
    blend_note = ""

    if blend_score:
        sev_path = None
        # eicu.npz → .../summary_results/by_landmark/L120/eicu_external
        # project root is typically parents[4]
        cands = []
        if severity_csv is not None:
            cands.append(Path(severity_csv))
        for up in range(2, 7):
            if len(npz_path.parents) > up:
                cands.append(npz_path.parents[up] / "data" / "eicu" / "eicu_severity_scores.csv")
        cands.append(npz_path.parent / "eicu_severity_scores.csv")
        for cand in cands:
            if cand is not None and cand.is_file():
                sev_path = cand
                break
        if sev_path is None:
            raise SystemExit(f"eICU: missing eicu_severity_scores.csv (need {blend_score})")
        sev_map = _load_severity_map(sev_path, blend_score)
        clin = np.array([sev_map.get(int(p), np.nan) for p in pids], dtype=float)
        both = np.isfinite(ss_tf) & np.isfinite(clin)
        if int(both.sum()) < 30 or len(np.unique(yy[both])) < 2:
            raise SystemExit(
                f"eICU Day{day}: TF+{blend_score} overlap too small n={int(both.sum())} ({sev_path})"
            )
        yy, ss_tf, clin, pids = yy[both], ss_tf[both], clin[both], pids[both]
        tf_alone_auc = float(roc_auc_score(yy, ss_tf))
        score_alone_auc = float(roc_auc_score(yy, clin))
        ss = w_tf * _rank01(ss_tf) + (1.0 - w_tf) * _rank01(clin)
        method = f"rank_blend_TF_{blend_score}"
        blend_note = (
            f"pre-specified rank blend TF:{blend_score}={w_tf:.1f}:{1.0 - w_tf:.1f}; "
            f"cohort=los>={day} & {blend_score} available"
        )
        print(
            f"[eicu_eval] blend TF:{blend_score} w_tf={w_tf:.1f} "
            f"TF_alone={tf_alone_auc:.4f} {blend_score}_alone={score_alone_auc:.4f} n={len(yy)}"
        )

    if len(yy) < 10 or len(np.unique(yy)) < 2:
        raise SystemExit(f"eICU Day{day}: too few samples n={len(yy)}")

    fpr, tpr, thr = roc_curve(yy, ss)
    auc = float(roc_auc_score(yy, ss))
    opt = float(thr[np.argmax(tpr - fpr)]) if len(thr) else 0.5
    pred = (ss > opt).astype(int)
    tn = int(((yy == 0) & (pred == 0)).sum())
    fp = int(((yy == 0) & (pred == 1)).sum())
    fn = int(((yy == 1) & (pred == 0)).sum())
    tp = int(((yy == 1) & (pred == 1)).sum())
    acc = float((pred == yy).mean())

    legend = f"eICU external (AUC={auc:.3f}; Acc={acc:.3f})"
    if blend_score:
        legend = f"TF+{blend_score} blend (AUC={auc:.3f}; Acc={acc:.3f})"
    # 禁止把 Acc 单独标成 AUC；图注必须同时写出两者且 AUC 来自 roc_auc_score

    fig, axes = plt.subplots(1, 2, figsize=(9.2, 4.6), dpi=160)
    fig.subplots_adjust(left=0.08, right=0.92, top=0.88, bottom=0.14, wspace=0.28)
    fig.patch.set_facecolor("white")
    ax_r, ax_c = axes
    ax_r.plot(fpr, tpr, color="#2e7d32", lw=2.2)
    ax_r.plot([0, 1], [0, 1], "k--", lw=0.9, alpha=0.6)
    ax_r.set_xlim(0, 1)
    ax_r.set_ylim(0, 1.02)
    ax_r.set_xlabel("False Positive Rate", fontsize=9)
    ax_r.set_ylabel("True Positive Rate", fontsize=9)
    ax_r.set_title("Receiver Operating Characteristic (ROC) Curve for eICU", fontsize=9.5, loc="center", pad=10)
    ax_r.legend([legend], loc="lower right", fontsize=8)
    ax_r.grid(True, linestyle=":", alpha=0.4)

    cm = np.array([[tn, fp], [fn, tp]], dtype=float)
    im = ax_c.imshow(cm, cmap="Blues", vmin=0, vmax=max(cm.max(), 1))
    for i in range(2):
        for j in range(2):
            ax_c.text(j, i, f"{int(cm[i, j])}", ha="center", va="center", fontsize=13)
    ax_c.set_xticks([0, 1])
    ax_c.set_yticks([0, 1])
    ax_c.set_xticklabels(["0", "1"])
    ax_c.set_yticklabels(["0", "1"])
    ax_c.set_xlabel("Predicted", fontsize=9)
    ax_c.set_ylabel("True", fontsize=9)
    ax_c.set_title("Confusion Matrix in eICU", fontsize=9.5, loc="center", pad=10)
    fig.colorbar(im, ax=ax_c, fraction=0.046, pad=0.04)
    out_pdf.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_pdf, format="pdf", bbox_inches="tight", pad_inches=0.08)
    plt.close(fig)

    metrics = {
        "panel": "eicu",
        "day": day,
        "arch": "b",
        "auc": round(auc, 4),
        "accuracy": round(acc, 4),
        "n": int(len(yy)),
        "n_pos": int(yy.sum()),
        "n_neg": int((yy == 0).sum()),
        "tn": tn,
        "fp": fp,
        "fn": fn,
        "tp": tp,
        "method": method,
        "tf_weight": round(w_tf, 4) if blend_score else "",
        "score_weight": round(1.0 - w_tf, 4) if blend_score else "",
        "blend_score": blend_score or "",
        "tf_alone_same_cohort": round(tf_alone_auc, 4),
        "score_alone_same_cohort": round(score_alone_auc, 4) if blend_score else "",
        "is_synthetic": "FALSE",
        "note": blend_note or "Transformer alone on eICU dabiao",
        "split_description": (
            f"eICU external validation: rank blend TF+{blend_score}"
            if blend_score
            else "eICU dabiao external validation (MIMIC-trained model)"
        ),
    }
    npz_path.parent.mkdir(parents=True, exist_ok=True)
    path = npz_path.parent / "Table_External_eICU_Metrics.csv"
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(metrics.keys()))
        w.writeheader()
        w.writerow(metrics)
    (npz_path.parent / "Table_External_eICU_Metrics.json").write_text(
        json.dumps(metrics, indent=2), encoding="utf-8"
    )
    print(
        f"[eicu_eval] Day{day} AUC={auc:.4f} Acc={acc:.4f} n={len(yy)} "
        f"(dead={int(yy.sum())}, alive={int((yy==0).sum())}) method={method} -> {out_pdf}"
    )
    return metrics


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-root", required=True)
    ap.add_argument("--landmark", type=int, default=120)
    ap.add_argument("--day", type=int, default=5)
    ap.add_argument("--out", default="")
    ap.add_argument("--repo", default=os.environ.get("MEDICAL_BLOCKS_ROOT", r"E:/01block/01Block-new-Final"))
    ap.add_argument(
        "--blend-score",
        default="",
        help="Optional clinical score for rank blend (e.g. APSIII / SOFA). Empty = TF alone.",
    )
    ap.add_argument(
        "--tf-weight",
        type=float,
        default=0.4,
        help="Rank-blend weight on Transformer (rest on blend-score). Default 0.4 → TF:score=0.4:0.6.",
    )
    ap.add_argument("--skip-prep", action="store_true", help="Reuse existing eicu.npz (eval/plot only).")
    ap.add_argument(
        "--min-age",
        type=float,
        default=18.0,
        help="Exclude age < min-age (default 18; sync with MIMIC tst_cohort$min_age). Use -1 to disable.",
    )
    args = ap.parse_args()

    proj = _to_path(args.project_root)
    repo = _to_path(args.repo)
    if not repo.exists():
        repo = Path(__file__).resolve().parents[3]

    ud = proj / f"by_unit/【success】L{args.landmark}_B_twostage/step09_tst_train_eval/Tables"
    if not ud.exists():
        ud = proj / f"by_unit/L{args.landmark}_B_twostage/step09_tst_train_eval/Tables"
    mimic_npz = ud / "npz" / "test.npz"
    model = ud / "model_b.pth"
    if not mimic_npz.is_file():
        raise SystemExit(f"missing MIMIC feature template: {mimic_npz}")
    if not model.is_file():
        raise SystemExit(f"missing model_b.pth: {model}")
    d = np.load(mimic_npz, allow_pickle=True)
    feat_names = [str(x) for x in d["feature_names"]]

    eicu_root = _resolve_eicu_root(proj)
    out_dir = proj / "summary_results" / "by_landmark" / f"L{args.landmark}" / "eicu_external"
    out_npz = out_dir / "eicu.npz"
    out_dir.mkdir(parents=True, exist_ok=True)

    # MIMIC train feature_norm must sit beside eicu.npz for TSTDataset
    src_norm = ud / "npz" / "feature_norm.json"
    if src_norm.is_file():
        import shutil

        shutil.copy2(src_norm, out_dir / "feature_norm.json")

    if not args.skip_prep or not out_npz.is_file():
        hourly = _resolve_eicu_hourly(eicu_root)
        seq = _find_seq_matrix(eicu_root) if hourly is None else None
        if hourly is None and seq is None:
            raise SystemExit(f"eICU: no hourly CSV or seq matrix under {eicu_root}")
        dabiao = _ensure_dabiao(eicu_root, hourly)
        prognosis = _ensure_prognosis(eicu_root)
        _ensure_static_features(eicu_root)
        static_map = _load_static_features(eicu_root / "eicu_static_features.csv")
        src_name = (hourly.name if hourly is not None else seq.name).lower()
        disease = (
            "TBI" if "tbi" in src_name else
            ("AKI" if "aki" in src_name else
             ("stroke" if ("stroke" in src_name or "ischemic" in src_name or "序列" in (hourly.name if hourly else seq.name)) else "eICU"))
        )
        print(
            f"[eicu_prep] source={hourly.name if hourly else seq.name} "
            f"dabiao={dabiao.name} static_ids={len(static_map)} disease={disease}"
        )
        min_age = None if float(args.min_age) < 0 else float(args.min_age)
        if hourly is not None:
            prepare_eicu_npz(
                hourly_csv=hourly,
                dabiao=dabiao,
                prognosis=prognosis,
                feat_names=feat_names,
                out_npz=out_npz,
                static_map=static_map,
                source_label=f"eICU {disease} dabiao ∩ prognosis",
                min_age=min_age,
            )
        else:
            prepare_eicu_npz_from_seq(
                seq_csv=seq,
                dabiao=dabiao,
                prognosis=prognosis,
                feat_names=feat_names,
                out_npz=out_npz,
                static_map=static_map,
                source_label=f"eICU {disease} seq-matrix dabiao ∩ prognosis",
                min_age=min_age,
            )
        # 纳排说明（外验年龄门控可核）
        note = out_dir / "eICU_外验纳排.txt"
        note.write_text(
            "\n".join(
                [
                    f"project={proj}",
                    f"eicu_root={eicu_root}",
                    f"source={hourly.name if hourly else seq.name}",
                    f"dabiao={dabiao.name}",
                    f"prognosis={prognosis.name}",
                    f"min_age={min_age}",
                    f"model={model}",
                    "policy=MIMIC-trained weights, no retrain; TF alone default",
                ]
            )
            + "\n",
            encoding="utf-8",
        )
    else:
        print(f"[eicu_prep] skip-prep: reuse {out_npz}")

    blend = (args.blend_score or "").strip()
    # TBI default comparator = APSIII if user asked blend but left empty? keep explicit only.
    default_pdf = proj / "summary_results" / "Figures" / "pdf" / "Figure S7-MIMIC-eICU_validation.pdf"
    if not default_pdf.parent.is_dir():
        default_pdf = proj / "summary_results" / "Figures" / "Figure S7-MIMIC-eICU_validation.pdf"
    out_pdf = _to_path(args.out) if args.out else default_pdf
    evaluate_and_plot(
        npz_path=out_npz,
        model_path=model,
        out_pdf=out_pdf,
        repo=repo,
        day=args.day,
        blend_score=blend,
        tf_weight=float(args.tf_weight),
        severity_csv=eicu_root / "eicu_severity_scores.csv",
    )


if __name__ == "__main__":
    main()
