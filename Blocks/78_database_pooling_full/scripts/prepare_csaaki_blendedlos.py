#!/usr/bin/env python3
"""Assemble CSA-AKI BlendedLoS tree: MIMIC+eICU from BlendedICU, SICdb+INSPIRE custom.

Drops urine_output from every linked MIMIC/eICU hourly file (rewrite local copy).
Splits: MIMIC + SICdb patient-level 70/15/15 (seed 974); eICU + INSPIRE held out to test.
"""
from __future__ import annotations

import json
import os
import shutil
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path("/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996")
OUT = ROOT / "blendedlos_csaaki"
READY = Path("/mnt/sda/BlendedICU/data/blendedlos_ready")
READY_TS = READY / "preprocessed_timeseries"
READY_LAB = READY / "preprocessed_labels.parquet"
SRC = ROOT / "cohort_source"
SEED = 974
SPLIT = 0.15
DROP_COLS = ("urine_output",)


def _read_dn1_ids(path: Path, col: str) -> list[str]:
    df = pd.read_csv(path)
    df.columns = [str(c).lstrip("\ufeff").strip() for c in df.columns]
    if "DN" in df.columns:
        df = df[df["DN"] == 1]
    return df[col].astype(str).tolist()


def _drop_urine_copy(src: Path, dst: Path) -> None:
    df = pd.read_parquet(src)
    for c in DROP_COLS:
        if c in df.columns:
            df = df.drop(columns=[c])
    dst.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(dst, index=False)


def _write_index(folder: Path) -> int:
    rows = [(p.stem, str(p.resolve())) for p in sorted(folder.glob("*.parquet"))]
    idx = pd.DataFrame(rows, columns=["patient", "ts_pth"]).set_index("patient")
    idx.to_csv(folder / "index.csv", sep=";")
    return len(idx)


def _link_or_copy_drop(db: str, patients: list[str]) -> dict:
    src_dir = READY_TS / db
    dst = OUT / "preprocessed_timeseries" / db
    dst.mkdir(parents=True, exist_ok=True)
    linked = missing = 0
    for raw_id in patients:
        pid = f"{db}-{raw_id}"
        src = src_dir / f"{pid}.parquet"
        target = dst / f"{pid}.parquet"
        if not src.exists():
            missing += 1
            continue
        if target.exists():
            linked += 1
            continue
        _drop_urine_copy(src, target)
        linked += 1
    n_idx = _write_index(dst)
    return {"eligible": len(patients), "linked": linked, "missing": missing, "index": n_idx}


def _link_custom(db: str) -> dict:
    src = ROOT / "hourly" / db
    dst = OUT / "preprocessed_timeseries" / db
    dst.mkdir(parents=True, exist_ok=True)
    n = 0
    for p in src.glob(f"{db}-*.parquet"):
        target = dst / p.name
        if not target.exists():
            try:
                os.link(p, target)
            except OSError:
                shutil.copy2(p, target)
        n += 1
    return {"linked": n, "index": _write_index(dst)}


def _split_persons(persons: np.ndarray) -> tuple[set, set, set]:
    persons = pd.Index(persons).sort_values()
    n_test = int(len(persons) * SPLIT)
    n_val = int(len(persons) * SPLIT)
    test = set(persons.to_series().sample(n=n_test, random_state=SEED))
    rest = persons.difference(list(test))
    val = set(rest.to_series().sample(n=n_val, random_state=SEED))
    train = set(rest.difference(list(val)))
    return train, val, test


def assemble() -> pd.DataFrame:
    OUT.mkdir(parents=True, exist_ok=True)
    mimic_ids = _read_dn1_ids(SRC / "MIMIC-IV-CardiacPerioperativeAKI-sample_6978.csv", "stay_id")
    eicu_ids = _read_dn1_ids(SRC / "eICU-CardiacPerioperativeAKI-sample_2822.csv", "patientunitstayid")
    counts = {
        "mimic4": _link_or_copy_drop("mimic4", mimic_ids),
        "eicu": _link_or_copy_drop("eicu", eicu_ids),
        "sicdb": _link_custom("sicdb"),
        "inspire": _link_custom("inspire"),
    }
    print(json.dumps(counts, indent=2), flush=True)

    ready = pd.read_parquet(READY_LAB)
    if "patient" not in ready.columns:
        ready = ready.reset_index()
    if "patient" not in ready.columns:
        ready = ready.rename(columns={ready.columns[0]: "patient"})
    ready["patient"] = ready["patient"].astype(str)

    mimic_patients = [f"mimic4-{i}" for i in mimic_ids]
    eicu_patients = [f"eicu-{i}" for i in eicu_ids]
    present_m = set(pd.read_csv(OUT / "preprocessed_timeseries/mimic4/index.csv", sep=";")["patient"].astype(str))
    present_e = set(pd.read_csv(OUT / "preprocessed_timeseries/eicu/index.csv", sep=";")["patient"].astype(str))
    lab_me = ready[ready["patient"].isin(present_m | present_e)].copy()

    sic = pd.read_parquet(ROOT / "cohort_sicdb_labels.parquet")
    if "patient" not in sic.columns:
        sic = sic.reset_index()
    insp = pd.read_parquet(ROOT / "cohort_inspire_labels.parquet")
    if "patient" not in insp.columns:
        insp = insp.reset_index()
    present_s = set(pd.read_csv(OUT / "preprocessed_timeseries/sicdb/index.csv", sep=";")["patient"].astype(str))
    present_i = set(pd.read_csv(OUT / "preprocessed_timeseries/inspire/index.csv", sep=";")["patient"].astype(str))
    sic = sic[sic["patient"].astype(str).isin(present_s)].copy()
    insp = insp[insp["patient"].astype(str).isin(present_i)].copy()

    # Harmonize columns
    for df, db in ((lab_me, None), (sic, "sicdb"), (insp, "inspire")):
        df["patient"] = df["patient"].astype(str)
    lab_me["height_cm"] = pd.to_numeric(lab_me.get("raw_height", lab_me.get("height")), errors="coerce")
    lab_me["weight_kg"] = pd.to_numeric(lab_me.get("raw_weight", lab_me.get("weight")), errors="coerce")
    lab_me["age"] = pd.to_numeric(lab_me["age"], errors="coerce")
    lab_me["sex"] = pd.to_numeric(lab_me["sex"], errors="coerce").fillna(0.0)
    lab_me["lengthofstay"] = pd.to_numeric(lab_me["lengthofstay"], errors="coerce")
    lab_me["true_lengthofstay"] = pd.to_numeric(lab_me["true_lengthofstay"], errors="coerce")
    lab_me["mortality"] = pd.to_numeric(lab_me["mortality"], errors="coerce").fillna(0).astype(int)
    lab_me["original_uniquepid"] = lab_me["original_uniquepid"].astype(str)

    def _pack(df: pd.DataFrame) -> pd.DataFrame:
        out = pd.DataFrame({
            "patient": df["patient"].astype(str),
            "source_dataset": df["source_dataset"].astype(str),
            "original_uniquepid": df["original_uniquepid"].astype(str),
            "age": pd.to_numeric(df["age"], errors="coerce"),
            "sex": pd.to_numeric(df["sex"], errors="coerce").fillna(0.0),
            "height": pd.to_numeric(df.get("height", df.get("height_cm")), errors="coerce"),
            "weight": pd.to_numeric(df.get("weight", df.get("weight_kg")), errors="coerce"),
            "lengthofstay": pd.to_numeric(df["lengthofstay"], errors="coerce"),
            "true_lengthofstay": pd.to_numeric(df["true_lengthofstay"], errors="coerce"),
            "mortality": pd.to_numeric(df["mortality"], errors="coerce").fillna(0).astype(int),
        })
        return out

    lab_me_p = _pack(lab_me.assign(height=lab_me["height_cm"], weight=lab_me["weight_kg"]))
    sic_p = _pack(sic)
    insp_p = _pack(insp)
    lab = pd.concat([lab_me_p, sic_p, insp_p], ignore_index=True).drop_duplicates("patient")
    lab["uniquepid"] = lab["source_dataset"] + ":" + lab["original_uniquepid"]
    h_med = float(lab["height"].median(skipna=True))
    w_med = float(lab["weight"].median(skipna=True))
    lab["height"] = lab["height"].fillna(h_med)
    lab["weight"] = lab["weight"].fillna(w_med)
    lab = lab.set_index("patient")
    lab.index.name = "patient"
    flat = lab[["age", "sex", "height", "weight"]].copy()
    flat.to_parquet(OUT / "preprocessed_flat.parquet")
    lab.to_parquet(OUT / "preprocessed_labels.parquet")
    (OUT / "flat_impute.json").write_text(
        json.dumps({"height_median": h_med, "weight_median": w_med, "counts": counts, "drop": list(DROP_COLS)}, indent=2),
        encoding="utf-8",
    )
    print(json.dumps({"labels": int(len(lab)), **{k: int(v) for k, v in lab.source_dataset.value_counts().items()}}, indent=2), flush=True)
    return lab


def write_split(lab: pd.DataFrame) -> None:
    # Main arms: eICU/INSPIRE held out entirely.
    # Dataset-benchmark arms: each DB gets its own 70/15/15 (including eICU/INSPIRE).
    parts_main = {}
    parts_self = {}
    summary = {}
    for db, g in lab.groupby("source_dataset"):
        tr, va, te = _split_persons(g["uniquepid"].unique())
        parts_self[db] = {"train": tr, "val": va, "test": te}
        if db in ("eicu", "inspire"):
            parts_main[db] = {"train": set(), "val": set(), "test": set(g["uniquepid"])}
        else:
            parts_main[db] = {"train": tr, "val": va, "test": te}
        summary[db] = {
            "main": {k: len(v) for k, v in parts_main[db].items()},
            "self": {k: len(v) for k, v in parts_self[db].items()},
        }

    def _stay_map(parts: dict) -> dict:
        out = {}
        for db, g in lab.groupby("source_dataset"):
            out[db] = {}
            for fold, ids in parts[db].items():
                out[db][fold] = g.index[g["uniquepid"].isin(ids)]
        return out

    stay_main = _stay_map(parts_main)
    stay_self = _stay_map(parts_self)

    ts_index = []
    for db in ("mimic4", "eicu", "sicdb", "inspire"):
        idx = pd.read_csv(OUT / "preprocessed_timeseries" / db / "index.csv", sep=";", index_col="patient")
        idx["source_dataset"] = db
        ts_index.append(idx)
    ts_all = pd.concat(ts_index)
    ts_all = ts_all.join(lab[["uniquepid", "true_lengthofstay", "source_dataset"]], rsuffix="_lab")
    if "source_dataset_lab" in ts_all.columns:
        ts_all["source_dataset"] = ts_all["source_dataset"].fillna(ts_all["source_dataset_lab"])

    flat_all = pd.read_parquet(OUT / "preprocessed_flat.parquet")

    def _write_job(folder: str, train_on: list[str], stay_part: dict, holdout_to_test: bool) -> None:
        folds = {"train": [], "val": [], "test": []}
        for db in train_on:
            for fold in ("train", "val", "test"):
                folds[fold].append(stay_part[db][fold])
        if holdout_to_test:
            folds["test"].append(stay_part["eicu"]["test"])
            folds["test"].append(stay_part["inspire"]["test"])
        folds = {
            k: pd.Index(np.concatenate([np.asarray(x) for x in v if len(x)])) if any(len(x) for x in v) else pd.Index([])
            for k, v in folds.items()
        }
        for fold, stays in folds.items():
            stays = pd.Index(stays).unique()
            dest = OUT / "extraction" / folder / fold
            dest.mkdir(parents=True, exist_ok=True)
            lab.loc[stays].to_parquet(dest / "labels.parquet")
            flat_all.loc[stays].to_parquet(dest / "flat.parquet")
            ts_all.loc[ts_all.index.isin(stays), ["ts_pth", "source_dataset", "uniquepid"]].to_csv(
                dest / "timeseries_pths.csv"
            )
            print(folder, fold, len(stays), flush=True)

    # Main Table3 arms (eICU/INSPIRE forced into test)
    _write_job("train_on_sicdb", ["sicdb"], stay_main, True)
    _write_job("train_on_mimic4", ["mimic4"], stay_main, True)
    _write_job("train_on_mimic4_sicdb", ["mimic4", "sicdb"], stay_main, True)
    # Dataset benchmark extras: eICU/INSPIRE need their own train/val (self 70/15/15)
    _write_job("train_on_eicu", ["eicu"], stay_self, False)
    _write_job("train_on_inspire", ["inspire"], stay_self, False)

    (OUT / "split_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2), flush=True)


def main() -> None:
    lab = assemble()
    write_split(lab)
    print("[done] prepare_csaaki_blendedlos", flush=True)


if __name__ == "__main__":
    main()
