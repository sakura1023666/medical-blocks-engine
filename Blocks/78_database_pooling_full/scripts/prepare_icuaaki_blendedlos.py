#!/usr/bin/env python3
"""Assemble ICU-AKI DN=1 cohort into BlendedLoS tree (Allyn 4 DBs).

Source IDs: /mnt/sda/BlendedICU/data/icuaaki_4db_20261106/cohort_source/dn1_ids_*.csv
Timeseries/labels: blendedlos_ready, filtered to matched DN=1 stays.
Drops creatinine + urine_output (KDIGO inclusion leakage).
Splits: Amsterdam+MIMIC patient-level 70/15/15 (seed 974); eICU/HiRID held-out test.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import numpy as np
import pandas as pd

READY = Path("/mnt/sda/BlendedICU/data/blendedlos_ready")
ROOT = Path("/mnt/sda/BlendedICU/data/icuaaki_4db_20261106")
DEFAULT_OUT = ROOT / "blendedlos_icuaaki"
COHORT = ROOT / "cohort_source"
SEED = 974
SPLIT = 0.15
DBS = ("amsterdam", "mimic4", "eicu", "hirid")
HELD_OUT = ("eicu", "hirid")
DROP_COLS = ("creatinine", "urine_output")


def _drop_copy(src: Path, dst: Path) -> None:
    df = pd.read_parquet(src)
    keep = [c for c in df.columns if c not in DROP_COLS]
    df = df[keep]
    dst.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(dst, index=False)


def _write_index(folder: Path) -> int:
    rows = [(p.stem, str(p.resolve())) for p in sorted(folder.glob("*.parquet"))]
    idx = pd.DataFrame(rows, columns=["patient", "ts_pth"]).set_index("patient")
    idx.to_csv(folder / "index.csv", sep=";")
    return len(idx)


def _link_stays(out: Path, db: str, patients: list[str]) -> dict:
    src_dir = READY / "preprocessed_timeseries" / db
    dst = out / "preprocessed_timeseries" / db
    dst.mkdir(parents=True, exist_ok=True)
    linked = missing = skipped_exists = 0
    for pid in patients:
        src = src_dir / f"{pid}.parquet"
        target = dst / f"{pid}.parquet"
        if not src.exists():
            missing += 1
            continue
        if target.exists():
            skipped_exists += 1
            linked += 1
            continue
        _drop_copy(src, target)
        linked += 1
    n_idx = _write_index(dst)
    return {
        "eligible": len(patients),
        "linked": linked,
        "missing_hourly": missing,
        "already_existed": skipped_exists,
        "index": n_idx,
    }


def _split_persons(persons: np.ndarray) -> tuple[set, set, set]:
    persons = pd.Index(persons).sort_values()
    n_test = int(len(persons) * SPLIT)
    n_val = int(len(persons) * SPLIT)
    test = set(persons.to_series().sample(n=n_test, random_state=SEED))
    rest = persons.difference(list(test))
    val = set(rest.to_series().sample(n=n_val, random_state=SEED))
    train = set(rest.difference(list(val)))
    return train, val, test


def _dn1_patients(db: str) -> list[str]:
    path = COHORT / f"dn1_ids_{db}.csv"
    df = pd.read_csv(path)
    if "patient" in df.columns:
        return df["patient"].astype(str).tolist()
    return [f"{db}-{x}" for x in df["raw_id"].astype(str)]


def assemble(out: Path) -> pd.DataFrame:
    ready = pd.read_parquet(READY / "preprocessed_labels.parquet")
    if "patient" not in ready.columns:
        ready = ready.reset_index()
    ready["patient"] = ready["patient"].astype(str)
    ready = ready[ready["source_dataset"].isin(DBS)].copy()

    counts = {}
    keep = []
    for db in DBS:
        ids = _dn1_patients(db)
        # only keep IDs present in ready labels
        ready_ids = set(ready.loc[ready["source_dataset"] == db, "patient"].astype(str))
        ids = [p for p in ids if p in ready_ids]
        counts[db] = _link_stays(out, db, ids)
        present = set(
            pd.read_csv(
                out / "preprocessed_timeseries" / db / "index.csv",
                sep=";",
                usecols=["patient"],
            )["patient"].astype(str)
        )
        counts[db]["present_after_index"] = len(present)
        keep.extend(present)
        print(db, counts[db], flush=True)

    lab = ready[ready["patient"].isin(set(keep))].drop_duplicates("patient").copy()
    for col_src, col_dst, fill in (
        ("raw_height", "height", True),
        ("raw_weight", "weight", True),
    ):
        if col_src in lab.columns:
            lab[col_dst] = pd.to_numeric(lab[col_src], errors="coerce")
        else:
            lab[col_dst] = pd.to_numeric(lab.get(col_dst), errors="coerce")
        if fill:
            lab[col_dst] = lab[col_dst].fillna(lab[col_dst].median())
    lab["age"] = pd.to_numeric(lab["age"], errors="coerce")
    lab["sex"] = pd.to_numeric(lab["sex"], errors="coerce").fillna(0.0)
    if "original_uniquepid" in lab.columns:
        lab["uniquepid"] = lab["source_dataset"].astype(str) + ":" + lab["original_uniquepid"].astype(str)
    else:
        lab["uniquepid"] = lab["source_dataset"].astype(str) + ":" + lab["patient"].astype(str)
    for c in ("lengthofstay", "true_lengthofstay"):
        lab[c] = pd.to_numeric(lab[c], errors="coerce")
    lab["mortality"] = pd.to_numeric(lab["mortality"], errors="coerce").fillna(0).astype(int)
    lab = lab.set_index("patient")
    lab.to_parquet(out / "preprocessed_labels.parquet")
    flat_cols = [c for c in ("age", "sex", "height", "weight") if c in lab.columns]
    lab[flat_cols].to_parquet(out / "preprocessed_flat.parquet")
    (out / "RULE.txt").write_text(
        "rule: ICU-AKI DN=1 (KDIGO) from ICUAKI_4DB_20261106\n"
        "source: blendedlos_ready filtered by cohort_source/dn1_ids_*.csv\n"
        "DROP_TS: creatinine, urine_output (inclusion leakage)\n"
        "split: amsterdam+mimic4 70/15/15 seed=974; eicu+hirid held-out test\n"
        "preprocess: MOESM1 physio clip at train (DBPOOL_PHYSIO_CLIP=1)\n",
        encoding="utf-8",
    )
    (out / "assemble_counts.json").write_text(json.dumps(counts, indent=2), encoding="utf-8")
    return lab


def write_splits(out: Path, lab: pd.DataFrame) -> None:
    flat_all = pd.read_parquet(out / "preprocessed_flat.parquet")
    parts = {}
    summary = {}
    for db, g in lab.groupby("source_dataset"):
        if db in HELD_OUT:
            persons = g["uniquepid"].unique()
            parts[db] = {"train": set(), "val": set(), "test": set(persons)}
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
            idx = g.index[g["uniquepid"].isin(ids)] if len(ids) else g.index[:0]
            stay_part[db][fold] = idx
            summary[db]["stays"][fold] = int(len(idx))

    ts_index = []
    for db in DBS:
        idx = pd.read_csv(
            out / "preprocessed_timeseries" / db / "index.csv", sep=";", index_col="patient"
        )
        idx["source_dataset"] = db
        ts_index.append(idx)
    ts_all = pd.concat(ts_index).join(lab[["uniquepid"]], how="left")

    jobs = {
        "train_on_amsterdam": ["amsterdam"],
        "train_on_mimic4": ["mimic4"],
        "train_on_amsterdam_mimic4": ["amsterdam", "mimic4"],
    }
    for folder, train_on in jobs.items():
        folds = {"train": [], "val": [], "test": []}
        for db in train_on:
            for fold in ("train", "val", "test"):
                folds[fold].append(stay_part[db][fold])
        for db in DBS:
            if db not in train_on:
                folds["test"].append(stay_part[db]["test"])
        for fold, chunks in folds.items():
            arrs = [np.asarray(x) for x in chunks if len(x)]
            stays = pd.Index(np.concatenate(arrs)).unique() if arrs else pd.Index([])
            dest = out / "extraction" / folder / fold
            dest.mkdir(parents=True, exist_ok=True)
            lab.loc[stays].to_parquet(dest / "labels.parquet")
            flat_all.loc[stays].to_parquet(dest / "flat.parquet")
            ts_all.loc[ts_all.index.isin(stays), ["ts_pth", "source_dataset", "uniquepid"]].to_csv(
                dest / "timeseries_pths.csv"
            )
            print(folder, fold, len(stays), flush=True)

    (out / "split_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    lab = assemble(out)
    write_splits(out, lab)
    print("DONE", out)


if __name__ == "__main__":
    main()
