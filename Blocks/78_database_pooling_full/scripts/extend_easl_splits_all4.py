#!/usr/bin/env python3
"""Add eICU/HiRID trainable splits + four-DB joint extraction for paper Table 2 / S2.

Does not alter existing train_on_amsterdam / mimic4 / amsterdam_mimic4 (held-out
external design for the main four arms). Writes additional extraction jobs:
  - train_on_eicu
  - train_on_hirid
  - train_on_amsterdam_eicu_hirid_mimic4

Usage:
  python extend_easl_splits_all4.py
  python extend_easl_splits_all4.py --blended-out /path/to/blendedlos_*
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

DEFAULT_OUT = Path(
    "/mnt/sda/BlendedICU/data/liver_dysfunction_easl_dili_42151996/blendedlos_easl_dili"
)
SEED = 974
SPLIT = 0.15
DBS = ("amsterdam", "mimic4", "eicu", "hirid")


def _split_persons(persons: np.ndarray) -> tuple[set, set, set]:
    persons = pd.Index(persons).sort_values()
    n_test = int(len(persons) * SPLIT)
    n_val = int(len(persons) * SPLIT)
    test = set(persons.to_series().sample(n=n_test, random_state=SEED))
    rest = persons.difference(list(test))
    val = set(rest.to_series().sample(n=n_val, random_state=SEED))
    train = set(rest.difference(list(val)))
    return train, val, test


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--blended-out", default=str(DEFAULT_OUT))
    args = ap.parse_args()
    OUT = Path(args.blended_out)

    lab = pd.read_parquet(OUT / "preprocessed_labels.parquet")
    if "patient" not in lab.columns:
        lab = lab.reset_index()
    lab = lab.set_index("patient")
    flat_all = pd.read_parquet(OUT / "preprocessed_flat.parquet")

    parts = {}
    summary = {}
    for db, g in lab.groupby("source_dataset"):
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
        "train_on_eicu": ["eicu"],
        "train_on_hirid": ["hirid"],
        # sorted name expected by BlendedICU: amsterdam_eicu_hirid_mimic4
        "train_on_amsterdam_eicu_hirid_mimic4": ["amsterdam", "eicu", "hirid", "mimic4"],
    }
    for folder, train_on in jobs.items():
        folds = {"train": [], "val": [], "test": []}
        for db in train_on:
            for fold in ("train", "val", "test"):
                folds[fold].append(stay_part[db][fold])
        # external = other DBs' test persons (for single-db jobs)
        if len(train_on) == 1:
            for db in DBS:
                if db not in train_on:
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

    (OUT / "split_summary_all4.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    # equal-n hint: min train persons across 4 DBs
    mins = min(summary[db]["persons"]["train"] for db in DBS)
    print(json.dumps({"min_train_persons": mins, "summary": summary}, indent=2))


if __name__ == "__main__":
    main()
