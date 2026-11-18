#!/usr/bin/env python3
"""Assemble the SOFA-liver>=1 BlendedLoS tree and write 70/15/15 splits.

Rule (frozen eligible_stays.parquet):
  first total bilirubin after ICU admission >= 20 umol/L,
  age >= 18, ICU stay > 0.5 h. Missing bilirubin stays are already excluded.

Amsterdam and MIMIC-IV are split by patient (seed 974, 15% test then 15% val).
eICU and HiRID are held out: every stay goes to test only.
Does not write into the cirrhosis tree.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path("/mnt/sda/BlendedICU/data/liver_dysfunction_sofa1_42151996")
OUT = ROOT / "blendedlos_sofa1"
READY = Path("/mnt/sda/BlendedICU/data/blendedlos_ready")
READY_TS = READY / "preprocessed_timeseries"
READY_LAB = READY / "preprocessed_labels.parquet"
ELIGIBLE = ROOT / "eligible_stays.parquet"
SEED = 974
SPLIT = 0.15
DBS = ("amsterdam", "mimic4", "eicu", "hirid")
HELD_OUT = ("eicu", "hirid")


def _link_stays(db: str, patients: list[str]) -> tuple[int, int]:
    src_dir = READY_TS / db
    dst = OUT / "preprocessed_timeseries" / db
    dst.mkdir(parents=True, exist_ok=True)
    linked = 0
    missing = 0
    for pid in patients:
        src = src_dir / f"{pid}.parquet"
        target = dst / f"{pid}.parquet"
        if not src.exists():
            missing += 1
            continue
        if target.is_symlink() or target.exists():
            linked += 1
            continue
        try:
            os.symlink(src, target)
        except OSError:
            os.link(src, target)
        linked += 1
    return linked, missing


def _write_index(folder: Path) -> int:
    rows = [(p.stem, str(p.resolve())) for p in sorted(folder.glob("*.parquet"))]
    idx = pd.DataFrame(rows, columns=["patient", "ts_pth"]).set_index("patient")
    idx.to_csv(folder / "index.csv", sep=";")
    return len(idx)


def assemble() -> pd.DataFrame:
    elig = pd.read_parquet(ELIGIBLE)
    elig["patient"] = elig["patient"].astype(str)
    counts = {}
    keep_patients = []
    for db in DBS:
        ids = elig.loc[elig["source_dataset"] == db, "patient"].tolist()
        n_link, n_miss = _link_stays(db, ids)
        n_idx = _write_index(OUT / "preprocessed_timeseries" / db)
        counts[db] = {"eligible": len(ids), "linked": n_link, "missing_hourly": n_miss, "index": n_idx}
        present = set(pd.read_csv(
            OUT / "preprocessed_timeseries" / db / "index.csv", sep=";", usecols=["patient"]
        )["patient"].astype(str))
        keep_patients.extend(present)
        print(db, counts[db], flush=True)

    ready = pd.read_parquet(READY_LAB)
    if "patient" not in ready.columns:
        ready = ready.reset_index()
    if "patient" not in ready.columns:
        ready = ready.rename(columns={ready.columns[0]: "patient"})
    ready["patient"] = ready["patient"].astype(str)
    lab = ready[ready["patient"].isin(set(keep_patients))].copy()
    lab = lab.drop_duplicates("patient")

    lab["height_cm"] = pd.to_numeric(lab["raw_height"], errors="coerce")
    lab["weight_kg"] = pd.to_numeric(lab["raw_weight"], errors="coerce")
    lab.loc[lab["height_cm"].isna(), "height_cm"] = pd.to_numeric(lab["height"], errors="coerce")
    lab.loc[lab["weight_kg"].isna(), "weight_kg"] = pd.to_numeric(lab["weight"], errors="coerce")
    h_med = float(lab["height_cm"].median())
    w_med = float(lab["weight_kg"].median())
    lab["height"] = lab["height_cm"].fillna(h_med)
    lab["weight"] = lab["weight_kg"].fillna(w_med)
    lab["age"] = pd.to_numeric(lab["age"], errors="coerce")
    lab["sex"] = pd.to_numeric(lab["sex"], errors="coerce").fillna(0.0)
    lab["uniquepid"] = lab["source_dataset"].astype(str) + ":" + lab["original_uniquepid"].astype(str)
    lab["lengthofstay"] = pd.to_numeric(lab["lengthofstay"], errors="coerce")
    lab["true_lengthofstay"] = pd.to_numeric(lab["true_lengthofstay"], errors="coerce")
    lab["mortality"] = pd.to_numeric(lab["mortality"], errors="coerce").fillna(0).astype(int)
    lab["definition"] = "sofa_liver_ge1_first_bilirubin_20umol"
    lab = lab.set_index("patient")
    lab.index.name = "patient"

    flat = lab[["age", "sex", "height", "weight"]].copy()
    flat.to_parquet(OUT / "preprocessed_flat.parquet")
    keep = [
        "source_dataset", "uniquepid", "original_uniquepid", "age", "sex",
        "height", "weight", "lengthofstay", "true_lengthofstay", "mortality", "definition",
    ]
    lab[keep].to_parquet(OUT / "preprocessed_labels.parquet")
    (OUT / "flat_impute.json").write_text(
        json.dumps({"height_cm_median": h_med, "weight_kg_median": w_med, "files": counts}, indent=2),
        encoding="utf-8",
    )
    print(json.dumps({"labels": int(len(lab)), "height_median": h_med, "weight_median": w_med}, indent=2))
    return lab


def _split_persons(persons: np.ndarray) -> tuple[set, set, set]:
    persons = pd.Index(persons).sort_values()
    n_test = int(len(persons) * SPLIT)
    n_val = int(len(persons) * SPLIT)
    test = set(persons.to_series().sample(n=n_test, random_state=SEED))
    rest = persons.difference(list(test))
    val = set(rest.to_series().sample(n=n_val, random_state=SEED))
    train = set(rest.difference(list(val)))
    return train, val, test


def write_split(lab: pd.DataFrame) -> None:
    parts = {}
    summary = {}
    for db, g in lab.groupby("source_dataset"):
        if db in HELD_OUT:
            parts[db] = {"train": set(), "val": set(), "test": set(g["uniquepid"])}
        else:
            tr, va, te = _split_persons(g["uniquepid"].unique())
            parts[db] = {"train": tr, "val": va, "test": te}
        summary[db] = {
            "persons": {k: len(v) for k, v in parts[db].items()},
            "stays": {},
        }

    stay_part = {}
    for db, g in lab.groupby("source_dataset"):
        stay_part[db] = {}
        for fold, ids in parts[db].items():
            idx = g.index[g["uniquepid"].isin(ids)]
            stay_part[db][fold] = idx
            summary[db]["stays"][fold] = int(len(idx))

    ts_index = []
    for db in DBS:
        idx = pd.read_csv(OUT / "preprocessed_timeseries" / db / "index.csv", sep=";", index_col="patient")
        idx["source_dataset"] = db
        ts_index.append(idx)
    ts_all = pd.concat(ts_index)
    ts_all = ts_all.join(lab[["uniquepid"]], how="left")

    jobs = {
        "train_on_amsterdam": ["amsterdam"],
        "train_on_mimic4": ["mimic4"],
        "train_on_amsterdam_mimic4": ["amsterdam", "mimic4"],
    }
    flat_all = pd.read_parquet(OUT / "preprocessed_flat.parquet")
    for folder, train_on in jobs.items():
        folds = {"train": [], "val": [], "test": []}
        for db in train_on:
            for fold in ("train", "val", "test"):
                folds[fold].append(stay_part[db][fold])
        for db in HELD_OUT:
            folds["test"].append(stay_part[db]["test"])
        for fold, chunks in folds.items():
            stays = pd.Index(np.concatenate([np.asarray(x) for x in chunks if len(x)])).unique()
            dest = OUT / "extraction" / folder / fold
            dest.mkdir(parents=True, exist_ok=True)
            lab.loc[stays].to_parquet(dest / "labels.parquet")
            flat_all.loc[stays].to_parquet(dest / "flat.parquet")
            ts_all.loc[ts_all.index.isin(stays), ["ts_pth", "source_dataset", "uniquepid"]].to_csv(
                dest / "timeseries_pths.csv"
            )
            print(folder, fold, len(stays), flush=True)
    (OUT / "split_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


def main() -> None:
    lab = assemble()
    write_split(lab)


if __name__ == "__main__":
    main()
