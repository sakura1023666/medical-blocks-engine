#!/usr/bin/env python3
"""Build SICdb + INSPIRE hourly wide tables for CSA-AKI pooling (龚倩).

Runs on Aiya-Linux 192.168.68.29 (raw SICdb / INSPIRE + BlendedICU).
Urine is intentionally NOT extracted (DBPOOL_DROP_TS=urine_output for all DBs).

Cohort stay lists come from CSAAKI_Pool_20261103 sample CSVs (DN=1 only),
staged under ROOT/cohort_source/.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import numpy as np
import pandas as pd
import polars as pl

ROOT = Path("/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996")
SRC = ROOT / "cohort_source"
SIC_PARQUET = Path("/mnt/sda/SICDB/parquet")
INSPIRE_PARQUET = Path("/mnt/sda/inspire/parquet/inspire")
UPPER_H = 14 * 24
DROP_VARS = ("urine_output",)

# SICdb LaboratoryID / DataID → BlendedICU variable (no urine)
SIC_LAB = {
    367: "creatinine",
    348: "blood_glucose",
    656: "blood_glucose",
    355: "blood_urea_nitrogen",
    289: "hemoglobin",
    658: "hemoglobin",
    301: "white_blood_cells",
    314: "platelets",
    469: "sodium",
    686: "sodium",
    463: "potassium",
    685: "potassium",
    457: "calcium",
    468: "magnesium",
    471: "phosphate",
    287: "albumin",
    333: "bilirubine",
    616: "aspartate_aminotransferase",
    617: "alanine_aminotransferase",
    609: "alkaline_phosphatase",
    657: "lactate",
    666: "bicarbonate",
    683: "chloride",
    687: "paCO2",
    688: "pH",
    689: "paO2",
}
SIC_VITAL = {
    701: "invasive_systolic_blood_pressure",
    702: "invasive_diastolic_blood_pressure",
    703: "invasive_mean_blood_pressure",
    704: "noninvasive_systolic_blood_pressure",
    705: "noninvasive_diastolic_blood_pressure",
    706: "noninvasive_mean_blood_pressure",
    707: "heart_rate",
    708: "heart_rate",
    724: "heart_rate",
    709: "temperature",
    710: "O2_pulseoxymetry_saturation",
    719: "respiratory_rate",
    2274: "respiratory_rate",
}

INSPIRE_LAB = {
    "creatinine": "creatinine",
    "glucose": "blood_glucose",
    "bun": "blood_urea_nitrogen",
    "hb": "hemoglobin",
    "wbc": "white_blood_cells",
    "platelet": "platelets",
    "sodium": "sodium",
    "potassium": "potassium",
    "calcium": "calcium",
    "phosphorus": "phosphate",
    "albumin": "albumin",
    "total_bilirubin": "bilirubine",
    "ast": "aspartate_aminotransferase",
    "alt": "alanine_aminotransferase",
    "alp": "alkaline_phosphatase",
    "lacate": "lactate",  # INSPIRE spelling
    "hco3": "bicarbonate",
    "chloride": "chloride",
    "ph": "pH",
    "pao2": "paO2",
    "paco2": "paCO2",
    "sao2": "O2_arterial_saturation",
}
INSPIRE_VITAL = {
    "hr": "heart_rate",
    "rr": "respiratory_rate",
    "bt": "temperature",
    "spo2": "O2_pulseoxymetry_saturation",
    "nibp_sbp": "noninvasive_systolic_blood_pressure",
    "nibp_dbp": "noninvasive_diastolic_blood_pressure",
    "nibp_mbp": "noninvasive_mean_blood_pressure",
    "art_sbp": "invasive_systolic_blood_pressure",
    "art_dbp": "invasive_diastolic_blood_pressure",
    "art_mbp": "invasive_mean_blood_pressure",
    "gcs_e": "glasgow_coma_score_eye",
    "gcs_m": "glasgow_coma_score_motor",
    "gcs_v": "glasgow_coma_score_verbal",
    # urine intentionally omitted (uo)
}


def _read_dn1(path: Path, id_col: str) -> pd.DataFrame:
    df = pd.read_csv(path)
    df.columns = [str(c).lstrip("\ufeff").strip() for c in df.columns]
    if "DN" in df.columns:
        df = df[df["DN"] == 1].copy()
    if id_col not in df.columns:
        raise SystemExit(f"{path}: missing {id_col}; cols={list(df.columns)[:20]}")
    df[id_col] = pd.to_numeric(df[id_col], errors="coerce")
    df = df.dropna(subset=[id_col])
    df[id_col] = df[id_col].astype(np.int64)
    return df


def _write_wide(long_df: pl.DataFrame, dest: Path, prefix: str) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    n = 0
    for keys, sub in long_df.group_by("stay_id", maintain_order=False):
        sid = keys[0] if isinstance(keys, tuple) else keys
        pid = f"{prefix}-{sid}"
        wide = (
            sub.pivot(values="value", index="time", columns="variable", aggregate_function="first")
            .sort("time")
        )
        for drop in DROP_VARS:
            if drop in wide.columns:
                wide = wide.drop(drop)
        wide.write_parquet(dest / f"{pid}.parquet")
        n += 1
        if n % 200 == 0:
            print(f"  [{prefix}] wide {n}", flush=True)
    return n


def build_sicdb(cohort: pd.DataFrame) -> pd.DataFrame:
    print("[sicdb] load cases", flush=True)
    cases = pd.read_parquet(SIC_PARQUET / "cases.parquet")
    ids = set(cohort["CaseID"].astype(np.int64))
    cases = cases[cases["CaseID"].isin(ids)].copy()
    cases["patient"] = "sicdb-" + cases["CaseID"].astype(str)
    cases["source_dataset"] = "sicdb"
    cases["original_uniquepid"] = cases["PatientID"].astype(str)
    cases["age"] = pd.to_numeric(cases["AgeOnAdmission"], errors="coerce")
    cases["sex"] = (cases["Sex"] == 735).astype(float)  # 1=male (BlendedICU)
    cases["weight"] = pd.to_numeric(cases["WeightOnAdmission"], errors="coerce") / 1000.0  # g→kg
    cases["height"] = pd.to_numeric(cases["HeightOnAdmission"], errors="coerce")
    los_h = pd.to_numeric(cases["TimeOfStay"], errors="coerce") / 3600.0
    cases["true_lengthofstay"] = los_h / 24.0
    cases["lengthofstay"] = cases["true_lengthofstay"].clip(upper=10.0)
    mort = (
        (cases["DischargeState"] == 2215)
        | (cases["HospitalDischargeType"] == 3130)
        | (
            cases["OffsetOfDeath"].notna()
            & (cases["OffsetOfDeath"] <= cases["TimeOfStay"])
        )
    )
    cases["mortality"] = mort.astype(int)
    cases["icu_offset"] = pd.to_numeric(cases["ICUOffset"], errors="coerce").fillna(0.0)

    print("[sicdb] labs", flush=True)
    lab = pl.scan_parquet(str(SIC_PARQUET / "laboratory.parquet")).filter(
        pl.col("CaseID").is_in(list(ids)) & pl.col("LaboratoryID").is_in(list(SIC_LAB))
    ).collect()
    meta = pl.from_pandas(cases[["CaseID", "icu_offset"]])
    lab = lab.join(meta, on="CaseID", how="inner")
    lab = lab.with_columns(
        ((pl.col("Offset") - pl.col("icu_offset")) / 3600.0).floor().cast(pl.Int32).alias("time"),
        pl.col("LaboratoryID").map_dict(SIC_LAB).alias("variable"),
        pl.col("LaboratoryValue").cast(pl.Float64).alias("value"),
        pl.col("CaseID").alias("stay_id"),
    ).filter((pl.col("time") >= 0) & (pl.col("time") < UPPER_H) & pl.col("value").is_not_null() & pl.col("variable").is_not_null())
    lab = lab.group_by(["stay_id", "time", "variable"]).agg(pl.col("value").mean())

    print("[sicdb] vitals data_float_h", flush=True)
    vit = pl.scan_parquet(str(SIC_PARQUET / "data_float_h.parquet")).filter(
        pl.col("CaseID").is_in(list(ids)) & pl.col("DataID").is_in(list(SIC_VITAL))
    ).collect()
    vit = vit.join(meta, on="CaseID", how="inner")
    vit = vit.with_columns(
        ((pl.col("Offset") - pl.col("icu_offset")) / 3600.0).floor().cast(pl.Int32).alias("time"),
        pl.col("DataID").map_dict(SIC_VITAL).alias("variable"),
        pl.col("Val").cast(pl.Float64).alias("value"),
        pl.col("CaseID").alias("stay_id"),
    ).filter((pl.col("time") >= 0) & (pl.col("time") < UPPER_H) & pl.col("value").is_not_null() & pl.col("variable").is_not_null())
    vit = vit.group_by(["stay_id", "time", "variable"]).agg(pl.col("value").mean())

    long = pl.concat([lab.select(["stay_id", "time", "variable", "value"]),
                      vit.select(["stay_id", "time", "variable", "value"])])
    long = long.filter(~pl.col("variable").is_in(list(DROP_VARS)))
    dest = ROOT / "hourly" / "sicdb"
    n = _write_wide(long, dest, "sicdb")
    print(json.dumps({"sicdb_wide": n, "labels": int(len(cases)), "mort": float(cases.mortality.mean())}), flush=True)
    keep = [
        "patient", "source_dataset", "original_uniquepid", "age", "sex",
        "height", "weight", "lengthofstay", "true_lengthofstay", "mortality",
    ]
    out = cases[keep].drop_duplicates("patient").set_index("patient")
    out.to_parquet(ROOT / "cohort_sicdb_labels.parquet")
    return out


def build_inspire(cohort: pd.DataFrame) -> pd.DataFrame:
    print("[inspire] load operations", flush=True)
    ops = pd.read_parquet(INSPIRE_PARQUET / "operations.parquet")
    ids = set(cohort["op_id"].astype(np.int64))
    ops = ops[ops["op_id"].isin(ids)].copy()
    ops = ops[ops["icuin_time"].notna()].copy()
    ops["patient"] = "inspire-" + ops["op_id"].astype(str)
    ops["source_dataset"] = "inspire"
    ops["original_uniquepid"] = ops["subject_id"].astype(str)
    ops["age"] = pd.to_numeric(ops["age"], errors="coerce")
    ops["sex"] = (ops["sex"].astype(str).str.upper().isin(["M", "MALE", "1"])).astype(float)
    ops["weight"] = pd.to_numeric(ops["weight"], errors="coerce")
    ops["height"] = pd.to_numeric(ops["height"], errors="coerce")
    icuin = pd.to_numeric(ops["icuin_time"], errors="coerce")
    icuout = pd.to_numeric(ops["icuout_time"], errors="coerce")
    # fallback LOS from discharge if icuout missing
    disc = pd.to_numeric(ops["discharge_time"], errors="coerce")
    end = icuout.fillna(disc)
    ops["true_lengthofstay"] = ((end - icuin) / (60.0 * 24.0)).clip(lower=0)
    ops["lengthofstay"] = ops["true_lengthofstay"].clip(upper=10.0)
    death = pd.to_numeric(ops["inhosp_death_time"], errors="coerce")
    ops["mortality"] = (
        death.notna() & (death >= icuin) & (death <= end.fillna(death))
    ).astype(int)
    ops = ops[ops["true_lengthofstay"] > (0.5 / 24.0)].copy()
    subject_ids = set(ops["subject_id"].astype(np.int64))
    # map subject chart times → each op's ICU window (one subject may have multiple ops)
    op_meta = ops[["op_id", "subject_id", "icuin_time", "icuout_time", "discharge_time"]].copy()
    op_meta["icuin_time"] = pd.to_numeric(op_meta["icuin_time"], errors="coerce")
    op_meta["end_time"] = pd.to_numeric(op_meta["icuout_time"], errors="coerce")
    op_meta["end_time"] = op_meta["end_time"].fillna(pd.to_numeric(op_meta["discharge_time"], errors="coerce"))

    def _events_to_hourly(events: pd.DataFrame, name_map: dict) -> pl.DataFrame:
        events = events[events["item_name"].isin(name_map)].copy()
        events["variable"] = events["item_name"].map(name_map)
        events = events.merge(op_meta, on="subject_id", how="inner")
        events["chart_time"] = pd.to_numeric(events["chart_time"], errors="coerce")
        events = events[
            (events["chart_time"] >= events["icuin_time"])
            & (events["chart_time"] < events["end_time"])
        ].copy()
        events["time"] = np.floor(
            (events["chart_time"] - events["icuin_time"]) / 60.0
        ).astype(np.int32)
        events = events[(events["time"] >= 0) & (events["time"] < UPPER_H)]
        events["value"] = pd.to_numeric(events["value"], errors="coerce")
        events = events.dropna(subset=["value", "variable"])
        events["stay_id"] = events["op_id"]
        g = (
            events.groupby(["stay_id", "time", "variable"], as_index=False)["value"]
            .mean()
        )
        return pl.from_pandas(g)

    print("[inspire] labs", flush=True)
    labs = pd.read_parquet(INSPIRE_PARQUET / "labs.parquet")
    labs = labs[labs["subject_id"].isin(subject_ids)]
    lab_h = _events_to_hourly(labs, INSPIRE_LAB)

    print("[inspire] ward_vitals (no uo)", flush=True)
    wv = pd.read_parquet(INSPIRE_PARQUET / "ward_vitals.parquet")
    wv = wv[wv["subject_id"].isin(subject_ids)]
    vit_h = _events_to_hourly(wv, INSPIRE_VITAL)

    long = pl.concat([lab_h, vit_h])
    long = long.filter(~pl.col("variable").is_in(list(DROP_VARS)))
    dest = ROOT / "hourly" / "inspire"
    n = _write_wide(long, dest, "inspire")
    print(json.dumps({"inspire_wide": n, "labels": int(len(ops)), "mort": float(ops.mortality.mean())}), flush=True)
    keep = [
        "patient", "source_dataset", "original_uniquepid", "age", "sex",
        "height", "weight", "lengthofstay", "true_lengthofstay", "mortality",
    ]
    out = ops[keep].drop_duplicates("patient").set_index("patient")
    out.to_parquet(ROOT / "cohort_inspire_labels.parquet")
    return out


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    sic_csv = SRC / "SICdb-CardiacPerioperativeAKI-sample_1067.csv"
    insp_csv = SRC / "INSPIRE-CardiacPerioperativeAKI-sample_1055.csv"
    if not sic_csv.exists() or not insp_csv.exists():
        raise SystemExit(f"Missing cohort CSVs under {SRC}")
    sic_cohort = _read_dn1(sic_csv, "CaseID")
    insp_cohort = _read_dn1(insp_csv, "op_id")
    print(json.dumps({"sic_dn1": int(len(sic_cohort)), "inspire_dn1": int(len(insp_cohort))}), flush=True)
    build_sicdb(sic_cohort)
    build_inspire(insp_cohort)
    (ROOT / "RULE.txt").write_text(
        "cohort: cardiac perioperative AKI DN=1 (CSAAKI_Pool_20261103)\n"
        "databases: mimic4, eicu, sicdb, inspire (Amsterdam skipped)\n"
        "model: DROP urine_output on all databases\n"
        "endpoints: ICU mortality + RLoS (cap 10d)\n",
        encoding="utf-8",
    )
    print("[done] SICdb + INSPIRE hourly", flush=True)


if __name__ == "__main__":
    main()
