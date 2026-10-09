#!/usr/bin/env python3
"""Prepare MIMIC external npz (aligned to eICU-trained F features) and evaluate Day5.

主分析 = eICU；外验 = MIMIC（不重训）。对称于 prepare_eicu_external_and_eval.py。
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import sys
from collections import defaultdict
from pathlib import Path

os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

import numpy as np

# Reuse eICU eval helpers where possible
_SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPT_DIR))
from prepare_eicu_external_and_eval import (  # noqa: E402
    _to_path,
    evaluate_and_plot,
)


# MIMIC chart/lab item → canonical feat（对齐 aki_mimic / eICU 训练 feature_names）
MIMIC_ALIASES: dict[str, list[str]] = {
    "heart_rate": ["Heart Rate"],
    "respiratory_rate": ["Respiratory Rate"],
    "spo2": ["O2 saturation pulseoxymetry"],
    "temperature_c": ["Temperature Fahrenheit", "Temperature Celsius"],
    "nibp_systolic": ["Non Invasive Blood Pressure systolic"],
    "nibp_diastolic": ["Non Invasive Blood Pressure diastolic"],
    "nibp_mean": ["Non Invasive Blood Pressure mean"],
    "abp_mean": ["Arterial Blood Pressure mean"],
    "cvp": ["Central Venous Pressure"],
    "daily_weight": ["Daily Weight", "Admission Weight (Kg)"],
    "gcs_eye": ["GCS - Eye Opening"],
    "gcs_motor": ["GCS - Motor Response"],
    "gcs_verbal": ["GCS - Verbal Response"],
    "gcs_total": ["GCS Total"],
    "creatinine": ["Creatinine (serum)", "Creatinine"],
    "bun": ["BUN", "Urea Nitrogen"],
    "urine_output": ["Foley", "GU Irrigant/Urine Volume Out", "Urine Volume"],
    "ultrafiltrate": ["Ultrafiltrate Output"],
    "sodium": ["Sodium (serum)", "Sodium"],
    "potassium": ["Potassium (serum)", "Potassium"],
    "chloride": ["Chloride (serum)", "Chloride"],
    "bicarbonate": ["HCO3 (serum)", "Bicarbonate"],
    "anion_gap": ["Anion gap", "Anion Gap"],
    "calcium": ["Calcium non-ionized", "Calcium, Total"],
    "magnesium": ["Magnesium"],
    "phosphate": ["Phosphorous", "Phosphate"],
    "glucose": ["Glucose (serum)", "Glucose"],
    "wbc": ["WBC", "White Blood Cells"],
    "hgb": ["Hemoglobin"],
    "hct": ["Hematocrit (serum)", "Hematocrit"],
    "platelets": ["Platelet Count"],
    "rbc": ["Red Blood Cells"],
    "mcv": ["MCV"],
    "rdw": ["RDW"],
    "inr": ["INR", "INR(PT)"],
    "pt": ["PT", "Prothrombin time"],
    "ptt": ["PTT"],
    "ph": ["pH", "PH (Arterial)"],
    "lactate": ["Lactate", "Lactic Acid"],
    "base_excess": ["Base Excess", "Arterial Base Excess"],
    "pao2": ["pO2", "Arterial O2 pressure"],
    "paco2": ["pCO2", "Arterial CO2 Pressure"],
    "fio2": ["Inspired O2 Fraction"],
    "peep": ["PEEP set", "PEEP"],
    "norepinephrine": ["Norepinephrine"],
    "phenylephrine": ["Phenylephrine", "Phenylephrine (50/250)", "Phenylephrine (200/250)"],
    "vasopressin": ["Vasopressin"],
    "epinephrine": ["Epinephrine"],
    "dopamine": ["Dopamine"],
    "dobutamine": ["Dobutamine"],
    "propofol": ["Propofol"],
    "fentanyl": ["Fentanyl", "Fentanyl (Concentrate)"],
    "insulin": ["Insulin - Regular", "Insulin - Humalog", "Insulin pump"],
    "total_bilirubin": ["Total Bilirubin", "Bilirubin, Total"],
    "ast": ["AST", "Asparate Aminotransferase (AST)"],
    "alt": ["ALT", "Alanine Aminotransferase (ALT)"],
    "albumin": ["Albumin"],
}


def _resolve_mimic_hourly(mimic_root: Path) -> Path:
    legacy = mimic_root / "374_mimic_aki_hourly_full_10d.csv"
    hits = sorted(mimic_root.glob("*_mimic_*_hourly_full_*.csv"))
    if not hits and legacy.is_file():
        return legacy
    if not hits:
        raise SystemExit(f"MIMIC: no hourly CSV under {mimic_root}")

    def _rank(p: Path) -> tuple:
        n = p.name.lower()
        pri = 0 if ("sepsis" in n or "aki" in n or "tbi" in n) else 1
        return (pri, -p.stat().st_size, p.name)

    return sorted(hits, key=_rank)[0]


def _ensure_dabiao(mimic_root: Path, hourly: Path) -> Path:
    dabiao = mimic_root / "dabiao.csv"
    if dabiao.is_file():
        return dabiao
    ids: set[int] = set()
    with hourly.open(newline="", encoding="utf-8", errors="replace") as f:
        for row in csv.DictReader(f):
            try:
                ids.add(int(float(row["stay_id"])))
            except (TypeError, ValueError, KeyError):
                continue
    if not ids:
        raise SystemExit("MIMIC: cannot build dabiao — no stay_id in hourly")
    with dabiao.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["stay_id"])
        for i in sorted(ids):
            w.writerow([i])
    print(f"[mimic_prep] auto-built dabiao n={len(ids)} -> {dabiao}")
    return dabiao


def _load_ids(dabiao: Path) -> set[int]:
    ids: set[int] = set()
    with dabiao.open(newline="", encoding="utf-8", errors="replace") as f:
        for row in csv.DictReader(f):
            key = row.get("stay_id") or row.get("patientunitstayid") or next(iter(row.values()))
            try:
                ids.add(int(float(key)))
            except (TypeError, ValueError):
                continue
    return ids


def _load_outcomes(prog: Path) -> dict[int, int]:
    out: dict[int, int] = {}
    with prog.open(newline="", encoding="utf-8", errors="replace") as f:
        for row in csv.DictReader(f):
            try:
                pid = int(float(row["stay_id"]))
            except (TypeError, ValueError, KeyError):
                continue
            raw = row.get("is_hosp_dead")
            if raw is None or str(raw).strip() == "":
                continue
            try:
                out[pid] = 1 if int(float(raw)) == 1 else 0
            except (TypeError, ValueError):
                continue
    return out


def _load_static(path: Path) -> dict[int, dict[str, float]]:
    if not path.is_file():
        return {}
    out: dict[int, dict[str, float]] = {}
    with path.open(newline="", encoding="utf-8", errors="replace") as f:
        for row in csv.DictReader(f):
            try:
                pid = int(float(row.get("stay_id") or row.get("patientunitstayid")))
            except (TypeError, ValueError, KeyError):
                continue
            vals: dict[str, float] = {}
            for k, v in row.items():
                if not k or k in ("stay_id", "patientunitstayid"):
                    continue
                try:
                    fv = float(v)
                except (TypeError, ValueError):
                    continue
                if fv == fv:
                    vals[k] = fv
                    if not str(k).startswith("static_"):
                        vals[f"static_{k}"] = fv
            if vals:
                out[pid] = vals
    return out


def _apply_min_age(
    keep: list[int],
    static_map: dict[int, dict[str, float]],
    *,
    min_age: float | None,
) -> tuple[list[int], dict]:
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
    n_lt = n_miss = 0
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
        f"[mimic_prep] min_age>={min_age}: {meta['n_before']} → {meta['n_after']} "
        f"(dropped_lt={n_lt}, dropped_missing_age={n_miss})"
    )
    return out, meta


def _build_item_to_feat(feat_names: list[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    for feat in feat_names:
        for alias in MIMIC_ALIASES.get(feat, [feat]):
            if alias not in out:
                out[alias] = feat
    return out


def prepare_mimic_npz(
    *,
    hourly_csv: Path,
    dabiao: Path,
    prognosis: Path,
    feat_names: list[str],
    out_npz: Path,
    max_day: int = 5,
    n_hours: int = 24,
    static_map: dict[int, dict[str, float]] | None = None,
    source_label: str = "MIMIC dabiao ∩ prognosis",
    min_age: float | None = 18.0,
) -> dict:
    ids = _load_ids(dabiao)
    y_map = _load_outcomes(prognosis)
    keep = sorted(pid for pid in ids if pid in y_map)
    if not keep:
        raise SystemExit("MIMIC: no overlapping dabiao ∩ prognosis IDs")
    static_map = static_map or {}
    keep, age_meta = _apply_min_age(keep, static_map, min_age=min_age)
    if not keep:
        raise SystemExit("MIMIC: no IDs left after min_age filter")

    item_map = _build_item_to_feat(feat_names)
    feat_idx = {f: i for i, f in enumerate(feat_names)}
    keep_set = set(keep)
    buckets: dict[int, dict[tuple[int, int, int], list[float]]] = defaultdict(lambda: defaultdict(list))
    n_rows = n_hit = 0

    with hourly_csv.open(newline="", encoding="utf-8", errors="replace") as f:
        for row in csv.DictReader(f):
            n_rows += 1
            try:
                pid = int(float(row["stay_id"]))
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
            day = h_abs // n_hours
            hod = h_abs % n_hours
            if day >= max_day:
                continue
            feat = item_map.get(item)
            if feat is None:
                feat = next((item_map[k] for k in item_map if k.lower() == item.lower()), None)
            if feat is None or feat not in feat_idx:
                continue
            buckets[pid][(day, hod, feat_idx[feat])].append(val)
            n_hit += 1

    pids = [pid for pid in keep if pid in buckets] or keep
    n = len(pids)
    F = len(feat_names)
    X = np.full((n, max_day, n_hours, F), np.nan, dtype=np.float32)
    y = np.zeros(n, dtype=np.int64)
    day_mask = np.zeros((n, max_day), dtype=np.float32)
    pid_arr = np.asarray(pids, dtype=np.int64)

    for i, pid in enumerate(pids):
        y[i] = int(y_map[pid])
        for (day, hod, fi), vals in buckets.get(pid, {}).items():
            X[i, day, hod, fi] = float(np.nanmean(vals))
        for d in range(max_day):
            if np.isfinite(X[i, d]).any():
                day_mask[i, d] = 1.0
        st = static_map.get(pid) or {}
        for fname, fi in feat_idx.items():
            if not fname.startswith("static_"):
                continue
            v = st.get(fname)
            if v is None:
                continue
            for d in range(max_day):
                if day_mask[i, d] > 0:
                    X[i, d, :, fi] = float(v)

    # forward fill within day hours
    for i in range(n):
        for d in range(max_day):
            for fi in range(F):
                last = np.nan
                for h in range(n_hours):
                    v = X[i, d, h, fi]
                    if np.isfinite(v):
                        last = v
                    elif np.isfinite(last):
                        X[i, d, h, fi] = last

    out_npz.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        out_npz,
        X=X,
        y=y,
        day_mask=day_mask,
        patient_id=pid_arr,
        feature_names=np.asarray(feat_names, dtype=object),
    )
    meta = {
        "n": int(n),
        "n_pos": int(y.sum()),
        "n_neg": int(n - int(y.sum())),
        "F": int(F),
        "max_day": int(max_day),
        "n_hours": int(n_hours),
        "n_hourly_rows": int(n_rows),
        "n_item_hits": int(n_hit),
        "source": source_label,
        "min_age_filter": age_meta,
        "note": "MIMIC external vs eICU-trained schema; min_age synced with primary tst_cohort",
    }
    (out_npz.parent / "mimic_external_meta.json").write_text(
        json.dumps(meta, indent=2), encoding="utf-8"
    )
    print(
        f"[mimic_prep] n={meta['n']} dead={meta['n_pos']} alive={meta['n_neg']} F={F} "
        f"hits={n_hit}/{n_rows}"
    )
    print(f"[mimic_prep] wrote {out_npz}")
    return meta


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-root", required=True)
    ap.add_argument("--landmark", type=int, default=120)
    ap.add_argument("--day", type=int, default=5)
    ap.add_argument("--out", default="")
    ap.add_argument("--repo", default=os.environ.get("MEDICAL_BLOCKS_ROOT", r"E:/01block/01Block-new-Final"))
    ap.add_argument("--blend-score", default="")
    ap.add_argument("--tf-weight", type=float, default=0.4)
    ap.add_argument("--skip-prep", action="store_true")
    ap.add_argument(
        "--min-age",
        type=float,
        default=18.0,
        help="Exclude age < min-age (sync with eICU primary tst_cohort$min_age). Use -1 to disable.",
    )
    args = ap.parse_args()

    proj = _to_path(args.project_root)
    repo = _to_path(args.repo)
    if not repo.exists():
        repo = Path(__file__).resolve().parents[3]

    ud = proj / f"by_unit/【success】L{args.landmark}_B_twostage/step09_tst_train_eval/Tables"
    if not ud.exists():
        ud = proj / f"by_unit/L{args.landmark}_B_twostage/step09_tst_train_eval/Tables"
    primary_npz = ud / "npz" / "test.npz"
    model = ud / "model_b.pth"
    if not primary_npz.is_file():
        raise SystemExit(f"missing primary feature template: {primary_npz}")
    if not model.is_file():
        raise SystemExit(f"missing model_b.pth: {model}")
    d = np.load(primary_npz, allow_pickle=True)
    feat_names = [str(x) for x in d["feature_names"]]

    mimic_root = proj / "data" / "mimic"
    out_dir = proj / "summary_results" / "by_landmark" / f"L{args.landmark}" / "mimic_external"
    out_npz = out_dir / "mimic.npz"
    out_dir.mkdir(parents=True, exist_ok=True)

    src_norm = ud / "npz" / "feature_norm.json"
    if src_norm.is_file():
        shutil.copy2(src_norm, out_dir / "feature_norm.json")

    if not args.skip_prep or not out_npz.is_file():
        hourly = _resolve_mimic_hourly(mimic_root)
        dabiao = _ensure_dabiao(mimic_root, hourly)
        prognosis = mimic_root / "mimic预后数据-all.csv"
        if not prognosis.is_file():
            # unicode escape for 预后
            cands = list(mimic_root.glob("*预后*.csv"))
            if not cands:
                raise SystemExit(f"missing MIMIC prognosis under {mimic_root}")
            prognosis = cands[0]
        static_map = _load_static(mimic_root / "mimic_static_features.csv")
        print(f"[mimic_prep] hourly={hourly.name} dabiao={dabiao.name} static_ids={len(static_map)}")
        min_age = None if float(args.min_age) < 0 else float(args.min_age)
        prepare_mimic_npz(
            hourly_csv=hourly,
            dabiao=dabiao,
            prognosis=prognosis,
            feat_names=feat_names,
            out_npz=out_npz,
            static_map=static_map,
            source_label="MIMIC sepsis-AKI dabiao ∩ prognosis",
            min_age=min_age,
        )
    else:
        print(f"[mimic_prep] skip-prep: reuse {out_npz}")

    default_pdf = proj / "summary_results" / "Figures" / "pdf" / "Figure S7-EICU-MIMIC_validation.pdf"
    if not default_pdf.parent.is_dir():
        default_pdf = proj / "summary_results" / "Figures" / "Figure S7-EICU-MIMIC_validation.pdf"
    out_pdf = _to_path(args.out) if args.out else default_pdf

    # evaluate_and_plot labels say eICU; rewrite PDF title after via note in meta —
    # call with blend optional; severity from mimic_severity_scores.csv
    evaluate_and_plot(
        npz_path=out_npz,
        model_path=model,
        out_pdf=out_pdf,
        repo=repo,
        day=args.day,
        blend_score=(args.blend_score or "").strip(),
        tf_weight=float(args.tf_weight),
        severity_csv=mimic_root / "mimic_severity_scores.csv",
    )
    print(f"[mimic_eval] wrote {out_pdf}")


if __name__ == "__main__":
    main()
