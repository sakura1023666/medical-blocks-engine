#!/usr/bin/env python3
"""Cirrhosis stays from original tables, hourly rows from BlendedICU (or NWICU raw).

Runs on Aiya-Linux (192.168.68.29), where BlendedICU and NWICU already sit.
ICD cohorts: MIMIC-IV titles, eICU diagnosis/past history, NWICU 15-code rule.
AmsterdamUMC has no diagnosis table; cohort is lactulose AND rifaximin (proxy).
HiRID has no diagnosis table and no MELD/Child-Pugh variable name; no stay list.
"""
from __future__ import annotations

import json
import os
import shutil
from pathlib import Path

import duckdb
import pandas as pd

ROOT = Path("/mnt/sda/BlendedICU/data")
READY = ROOT / "blendedlos_ready"
OUT = ROOT / "cirrhosis_dzx_42151996"
HOURLY = READY / "preprocessed_timeseries"
MIN_LOS_DAYS = 0.5 / 24.0  # ICU LOS > 0.5 h, same gate as the MIMIC extract

VITAL_MAP = {
    "HR": "heart_rate",
    "SpO2": "O2_arterial_saturation",
    "RR": "respiratory_rate",
    "NBPs": "noninvasive_systolic_blood_pressure",
    "NBPd": "noninvasive_diastolic_blood_pressure",
    "ABPs": "invasive_systolic_blood_pressure",
    "ABPd": "invasive_diastolic_blood_pressure",
    "Temperature": "temperature",
}
LAB_MAP = {
    "Glucose": "blood_glucose",
    "Sodium": "sodium",
    "Potassium": "potassium",
    "Creatinine": "creatinine",
    "Chloride": "chloride",
    "Urea Nitrogen": "blood_urea_nitrogen",
    "Hemoglobin": "hemoglobin",
    "Platelet Count": "platelets",
    "White Blood Cells": "white_blood_cells",
    "Magnesium": "magnesium",
    "Phosphate": "phosphate",
    "Albumin": "albumin",
    "Asparate Aminotransferase (AST)": "aspartate_aminotransferase",
    "Alanine Aminotransferase (ALT)": "alanine_aminotransferase",
    "Bilirubin, Total": "bilirubine",
    "Alkaline Phosphatase": "alkaline_phosphatase",
    "Calcium, Total": "calcium",
    "Total CO2": "bicarbonate",
    "Lactate": "lactate",
    "pH": "pH",
    "pO2": "paO2",
    "pCO2": "paCO2",
    "PTT": "PTT",
}


def _labels() -> pd.DataFrame:
    lab = pd.read_parquet(READY / "preprocessed_labels.parquet")
    lab = lab.reset_index()
    if "patient" not in lab.columns:
        lab = lab.rename(columns={lab.columns[0]: "patient"})
    lab["age_num"] = pd.to_numeric(lab["raw_age"], errors="coerce")
    lab["los_days"] = pd.to_numeric(lab["true_lengthofstay"], errors="coerce")
    lab["eligible"] = (lab["age_num"] >= 18) & (lab["los_days"] > MIN_LOS_DAYS)
    return lab


def _keep(ids: pd.Series, lab: pd.DataFrame, db: str) -> pd.DataFrame:
    want = set(ids.astype(str))
    sub = lab[(lab["source_dataset"] == db) & (lab["patient"].astype(str).isin(want))].copy()
    sub = sub[sub["eligible"]].copy()
    sub["hourly_file"] = [
        str(HOURLY / db / f"{pid}.parquet") for pid in sub["patient"].astype(str)
    ]
    sub["hourly_exists"] = [os.path.isfile(p) for p in sub["hourly_file"]]
    return sub


def _link_hourly(df: pd.DataFrame, dest: Path) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    n = 0
    for pid, src, ok in zip(df["patient"], df["hourly_file"], df["hourly_exists"]):
        if not ok:
            continue
        target = dest / f"{pid}.parquet"
        if target.exists():
            n += 1
            continue
        try:
            os.link(src, target)
        except OSError:
            shutil.copy2(src, target)
        n += 1
    return n


def cohort_mimic(con: duckdb.DuckDBPyConnection, lab: pd.DataFrame) -> pd.DataFrame:
    dx = pd.read_parquet(
        ROOT / "blended_data" / "diagnoses.parquet",
        columns=["patient", "diagnosis_source_value"],
    )
    text = dx["diagnosis_source_value"].fillna("").str.lower()
    hit = text.str.contains("cirrho", regex=False) & ~text.str.contains("non-cirrhotic", regex=False)
    hit &= ~text.str.contains("noncirrhotic", regex=False)
    ids = dx.loc[hit, "patient"].drop_duplicates()
    out = _keep(ids, lab, "mimic4")
    out["definition"] = "icd_title_cirrhosis"
    out["definition_note"] = "BlendedICU diagnoses.source_value contains cirrho, excluding non-cirrhotic"
    print(f"[mimic4] title-hit ids {ids.nunique()} eligible+hourly {int(out.hourly_exists.sum())}/{len(out)}", flush=True)
    return out


def cohort_eicu(con: duckdb.DuckDBPyConnection, lab: pd.DataFrame) -> pd.DataFrame:
    raw = ROOT / "eicu_data" / "raw_parquet"
    ids = con.sql(f"""
        WITH dx AS (
          SELECT DISTINCT patientunitstayid
          FROM read_parquet('{(raw / "diagnosis.parquet").as_posix()}')
          WHERE lower(COALESCE(diagnosisstring, '')) LIKE '%cirrhosis%'
             OR icd9code LIKE '%571.2%' OR icd9code LIKE '%571.5%' OR icd9code LIKE '%571.6%'
             OR upper(icd9code) LIKE '%K70.3%' OR upper(icd9code) LIKE '%K74%'
             OR upper(icd9code) LIKE '%K71.7%'
        ),
        ph AS (
          SELECT DISTINCT patientunitstayid
          FROM read_parquet('{(raw / "pastHistory.parquet").as_posix()}')
          WHERE lower(COALESCE(pasthistorypath, '')) LIKE '%cirrhosis%'
        ),
        u AS (SELECT patientunitstayid FROM dx UNION SELECT patientunitstayid FROM ph)
        SELECT 'eicu-' || CAST(patientunitstayid AS VARCHAR) AS patient FROM u
    """).fetchdf()
    out = _keep(ids["patient"], lab, "eicu")
    out["definition"] = "icd_or_pasthistory"
    out["definition_note"] = "eICU diagnosis string/ICD or pastHistory path contains cirrhosis; same two routes as the 2026-10-12 extract"
    print(f"[eicu] raw stay ids {len(ids)} eligible+hourly {int(out.hourly_exists.sum())}/{len(out)}", flush=True)
    return out


def cohort_amsterdam(con: duckdb.DuckDBPyConnection, lab: pd.DataFrame) -> pd.DataFrame:
    raw = ROOT / "amsterdam_data" / "raw_parquet" / "drugitems.parquet"
    ids = con.sql(f"""
        SELECT 'amsterdam-' || CAST(admissionid AS VARCHAR) AS patient
        FROM read_parquet('{raw.as_posix()}')
        GROUP BY admissionid
        HAVING MAX(lower(item) LIKE '%lactulose%' OR lower(item) LIKE '%duphalac%' OR lower(item) LIKE '%legendal%')
           AND MAX(lower(item) LIKE '%rifaximin%')
    """).fetchdf()
    out = _keep(ids["patient"], lab, "amsterdam")
    out["definition"] = "med_proxy_lactulose_and_rifaximin"
    out["definition_note"] = "AmsterdamUMC raw package has no diagnosis table. Proxy = lactulose AND rifaximin on the same admission. Not ICD."
    print(f"[amsterdam] proxy admissions {len(ids)} eligible+hourly {int(out.hourly_exists.sum())}/{len(out)}", flush=True)
    return out


def cohort_nwicu(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
    con.sql("ATTACH '/mnt/sda/NWICU/db/nwicu.duckdb' (READ_ONLY)")
    rule = (
        "icd_code NOT LIKE 'IMO%' AND (icd_code IN "
        "('K703','K7030','K7031','K717','K74','K743','K744','K745','K746','K7460','K7469','P7881') "
        "OR icd_code LIKE 'K703%' OR icd_code LIKE 'K74%')"
    )
    stays = con.sql(f"""
        WITH hit AS (
          SELECT hadm_id FROM nwicu.main.diagnoses_icd WHERE {rule} GROUP BY hadm_id
        )
        SELECT
          s.stay_id, s.subject_id, s.hadm_id, s.intime, s.outtime,
          p.anchor_age AS age_num, p.gender,
          date_diff('minute', s.intime, s.outtime) / 60.0 AS los_hours,
          CASE WHEN a.discharge_location LIKE 'EXPIRED%' THEN 1 ELSE 0 END AS mortality
        FROM nwicu.main.icustays s
        JOIN nwicu.main.admissions a ON a.hadm_id = s.hadm_id
        JOIN nwicu.main.patients p ON p.subject_id = s.subject_id
        JOIN hit h ON h.hadm_id = s.hadm_id
        WHERE p.anchor_age >= 18
          AND date_diff('minute', s.intime, s.outtime) > 30
    """).fetchdf()
    stays["patient"] = "nwicu-" + stays["stay_id"].astype(str)
    stays["source_dataset"] = "nwicu"
    stays["definition"] = "icd10_15code"
    stays["definition_note"] = "Same frozen 15-code rule as MIMIC-IV/out/cirrhosis_code_rule.csv"
    stays["hourly_exists"] = True
    print(f"[nwicu] eligible stays {len(stays)} patients {stays.subject_id.nunique()}", flush=True)
    return stays


def write_nwicu_hourly(con: duckdb.DuckDBPyConnection, stays: pd.DataFrame, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    con.register("cirr_stays", stays[["stay_id", "hadm_id", "intime", "outtime"]])
    vital_case = " ".join([f"WHEN vital_name = '{k}' THEN '{v}'" for k, v in VITAL_MAP.items()])
    lab_case = " ".join([f"WHEN item_name = '{k}' THEN '{v}'" for k, v in LAB_MAP.items()])
    vitals = con.sql(f"""
        SELECT c.stay_id,
               CAST(date_diff('minute', s.intime, c.charttime) / 60 AS INTEGER) AS hour_index,
               CASE {vital_case} END AS variable,
               avg(c.valuenum) AS value_mean,
               count(*) AS n_obs
        FROM nwicu.main.v_chartevents_clean c
        JOIN cirr_stays s ON s.stay_id = c.stay_id
        WHERE c.charttime >= s.intime AND c.charttime < s.outtime
          AND COALESCE(c.is_plausible, TRUE)
          AND c.vital_name IN ({", ".join(repr(k) for k in VITAL_MAP)})
        GROUP BY 1, 2, 3
    """).fetchdf()
    labs = con.sql(f"""
        SELECT s.stay_id,
               CAST(date_diff('minute', s.intime, l.charttime) / 60 AS INTEGER) AS hour_index,
               CASE {lab_case} END AS variable,
               avg(l.valuenum) AS value_mean,
               count(*) AS n_obs
        FROM nwicu.main.v_labevents_clean l
        JOIN cirr_stays s
          ON s.hadm_id = l.hadm_id
         AND l.charttime >= s.intime AND l.charttime < s.outtime
        WHERE l.item_name IN ({", ".join(repr(k) for k in LAB_MAP)})
          AND l.valuenum IS NOT NULL
        GROUP BY 1, 2, 3
    """).fetchdf()
    hourly = pd.concat([vitals, labs], ignore_index=True)
    hourly = hourly[hourly["variable"].notna() & (hourly["hour_index"] >= 0)]
    hourly.to_parquet(dest / "nwicu_hourly.parquet", index=False)
    print(f"[nwicu] hourly rows {len(hourly)} stays {hourly.stay_id.nunique()} vars {hourly.variable.nunique()}", flush=True)


def write_hirid_status(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "\n".join([
            "# HiRID cirrhosis cohort",
            "",
            "Original HiRID v1.1.1 tables on this server are observation_tables, pharma_records, general_table, and hirid_variable_reference_v1.",
            "general_table has patientid, admissiontime, sex, age, discharge_status only.",
            "hirid_variable_reference_v1 has 0 rows whose text contains cirrho, meld, child, hepatic, or liver.",
            "There is no ICD table, so a cirrhosis stay list cannot be built from the original data or from BlendedICU diagnoses (that file is MIMIC-IV only).",
            "BlendedICU hourly files for the unrestricted HiRID cohort remain in blendedlos_ready/preprocessed_timeseries/hirid. They are not copied here, because they are not a cirrhosis cohort.",
            "",
        ]),
        encoding="utf-8",
    )


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    lab = _labels()
    con = duckdb.connect()
    pieces = {
        "mimic4": cohort_mimic(con, lab),
        "eicu": cohort_eicu(con, lab),
        "amsterdam": cohort_amsterdam(con, lab),
    }
    nwicu = cohort_nwicu(con)
    summary = []
    keep_cols = [
        "patient", "source_dataset", "original_uniquepid", "age_num", "sex",
        "los_days", "mortality", "definition", "definition_note", "hourly_exists",
    ]
    for db, df in pieces.items():
        use = [c for c in keep_cols if c in df.columns]
        df[use].to_parquet(OUT / f"cohort_{db}.parquet", index=False)
        n_link = _link_hourly(df, OUT / "hourly" / db)
        summary.append({
            "database": db,
            "eligible_stays": int(len(df)),
            "hourly_files": int(n_link),
            "definition": df["definition"].iloc[0] if len(df) else "",
        })
    nwicu.to_parquet(OUT / "cohort_nwicu.parquet", index=False)
    write_nwicu_hourly(con, nwicu, OUT / "hourly" / "nwicu")
    summary.append({
        "database": "nwicu",
        "eligible_stays": int(len(nwicu)),
        "hourly_files": 1,
        "definition": "icd10_15code",
        "note": "hourly is one long parquet from original chartevents and labevents; NWICU is not inside BlendedICU",
    })
    write_hirid_status(OUT / "hourly" / "hirid" / "COHORT_STATUS.md")
    summary.append({
        "database": "hirid",
        "eligible_stays": 0,
        "hourly_files": 0,
        "definition": "not_identifiable",
    })
    (OUT / "cohort_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2), flush=True)


if __name__ == "__main__":
    main()
