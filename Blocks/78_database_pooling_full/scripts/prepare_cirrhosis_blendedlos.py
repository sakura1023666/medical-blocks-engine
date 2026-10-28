#!/usr/bin/env python3
"""Assemble the cirrhosis BlendedLoS tree and write 70/15/15 splits.

MIMIC-IV and NWICU are split by patient (seed 974, 15% val, 15% test).
eICU is held out: every eICU stay goes to test only.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path("/mnt/sda/BlendedICU/data/cirrhosis_dzx_42151996")
OUT = ROOT / "blendedlos_cirrhosis"
READY_LAB = Path("/mnt/sda/BlendedICU/data/blendedlos_ready/preprocessed_labels.parquet")
SEED = 974
SPLIT = 0.15


def _link_tree(src: Path, dst: Path) -> int:
    if dst.is_symlink() or dst.exists():
        if dst.is_symlink() and dst.resolve() == src.resolve():
            return sum(1 for p in src.glob("*.parquet"))
        if dst.is_symlink():
            dst.unlink()
    if not dst.exists():
        dst.symlink_to(src, target_is_directory=True)
        return sum(1 for p in src.glob("*.parquet"))
    # real directory: hardlink any missing files
    n = 0
    for p in src.glob("*.parquet"):
        target = dst / p.name
        if not target.exists():
            try:
                os.link(p, target)
            except OSError:
                os.symlink(p, target)
        n += 1
    return n


def _write_index(folder: Path) -> int:
    rows = []
    for p in sorted(folder.glob("*.parquet")):
        rows.append((p.stem, str(p.resolve())))
    idx = pd.DataFrame(rows, columns=["patient", "ts_pth"]).set_index("patient")
    idx.to_csv(folder / "index.csv", sep=";")
    return len(idx)


def assemble() -> pd.DataFrame:
    ts = OUT / "preprocessed_timeseries"
    ts.mkdir(parents=True, exist_ok=True)
    counts = {
        "mimic4": _link_tree(ROOT / "hourly" / "mimic4", ts / "mimic4"),
        "eicu": _link_tree(ROOT / "hourly" / "eicu", ts / "eicu"),
    }
    nwicu = ts / "nwicu"
    counts["nwicu"] = _write_index(nwicu) if nwicu.exists() else 0
    for db in ("mimic4", "eicu"):
        counts[db + "_index"] = _write_index(ts / db)

    lab = pd.read_parquet(OUT / "preprocessed_labels.parquet")
    if "patient" not in lab.columns:
        lab = lab.reset_index().rename(columns={"index": "patient"})
    ready = pd.read_parquet(READY_LAB).reset_index()
    if "patient" not in ready.columns:
        ready = ready.rename(columns={ready.columns[0]: "patient"})
    anth = ready[["patient", "raw_height", "raw_weight", "height", "weight"]].copy()
    anth["height_cm"] = pd.to_numeric(anth["raw_height"], errors="coerce")
    anth["weight_kg"] = pd.to_numeric(anth["raw_weight"], errors="coerce")
    anth.loc[anth["height_cm"].isna(), "height_cm"] = pd.to_numeric(anth["height"], errors="coerce")
    anth.loc[anth["weight_kg"].isna(), "weight_kg"] = pd.to_numeric(anth["weight"], errors="coerce")
    lab = lab.merge(anth[["patient", "height_cm", "weight_kg"]], on="patient", how="left")
    h_med = float(lab["height_cm"].median())
    w_med = float(lab["weight_kg"].median())
    lab["height"] = lab["height_cm"].fillna(h_med)
    lab["weight"] = lab["weight_kg"].fillna(w_med)
    lab["age"] = pd.to_numeric(lab["age"], errors="coerce")
    lab["sex"] = pd.to_numeric(lab["sex"], errors="coerce").fillna(0.0)
    lab["uniquepid"] = lab["source_dataset"].astype(str) + ":" + lab["original_uniquepid"].astype(str)
    lab["lengthofstay"] = pd.to_numeric(lab["lengthofstay"], errors="coerce")
    lab["true_lengthofstay"] = pd.to_numeric(lab["true_lengthofstay"], errors="coerce")
    lab["mortality"] = pd.to_numeric(lab["mortality"], errors="coerce").astype(int)
    lab = lab.drop_duplicates("patient").set_index("patient")
    lab.index.name = "patient"
    flat_cols = ["age", "sex", "height", "weight"]
    flat = lab[flat_cols].copy()
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
    print(json.dumps({"files": counts, "labels": int(len(lab)), "height_median": h_med, "weight_median": w_med}, indent=2))
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
        if db == "eicu":
            parts[db] = {"train": set(), "val": set(), "test": set(g["uniquepid"])}
        else:
            tr, va, te = _split_persons(g["uniquepid"].unique())
            parts[db] = {"train": tr, "val": va, "test": te}
        summary[db] = {k: len(v) for k, v in parts[db].items()}
    # Stay rows follow the person split.
    stay_part = {}
    for db, g in lab.groupby("source_dataset"):
        stay_part[db] = {}
        for fold, ids in parts[db].items():
            stay_part[db][fold] = g.index[g["uniquepid"].isin(ids)]

    ts_index = []
    for db in ("mimic4", "eicu", "nwicu"):
        idx = pd.read_csv(OUT / "preprocessed_timeseries" / db / "index.csv", sep=";", index_col="patient")
        idx["source_dataset"] = db
        ts_index.append(idx)
    ts_all = pd.concat(ts_index)
    ts_all = ts_all.join(lab[["uniquepid", "true_lengthofstay", "source_dataset"]], rsuffix="_lab")
    if "source_dataset_lab" in ts_all.columns:
        ts_all["source_dataset"] = ts_all["source_dataset"].fillna(ts_all["source_dataset_lab"])

    jobs = {
        "train_on_nwicu": ["nwicu"],
        "train_on_mimic4": ["mimic4"],
        "train_on_mimic4_nwicu": ["mimic4", "nwicu"],
    }
    for folder, train_on in jobs.items():
        folds = {"train": [], "val": [], "test": []}
        for db in train_on:
            for fold in ("train", "val", "test"):
                folds[fold].append(stay_part[db][fold])
        # Held-out eICU is test for every experiment.
        folds["test"].append(stay_part["eicu"]["test"])
        folds = {k: pd.Index(np.concatenate([np.asarray(x) for x in v])) if v else pd.Index([]) for k, v in folds.items()}
        for fold, stays in folds.items():
            stays = pd.Index(stays).unique()
            dest = OUT / "extraction" / folder / fold
            dest.mkdir(parents=True, exist_ok=True)
            lab.loc[stays].to_parquet(dest / "labels.parquet")
            flat = pd.read_parquet(OUT / "preprocessed_flat.parquet")
            flat.loc[stays].to_parquet(dest / "flat.parquet")
            ts_all.loc[ts_all.index.isin(stays), ["ts_pth", "source_dataset", "uniquepid"]].to_csv(
                dest / "timeseries_pths.csv"
            )
    (OUT / "split_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


def main() -> None:
    lab = assemble()
    write_split(lab)


if __name__ == "__main__":
    main()
