#!/usr/bin/env python3
"""CSA-AKI 3-DB scheme: MIMIC+eICU train, INSPIRE external (no SICdb).

Writes / refreshes extraction folders expected by run_dbpool_experiment._split_marker:
  - train_on_eicu
  - train_on_mimic4          (test: mimic holdout + eICU holdout + all INSPIRE)
  - train_on_eicu_mimic4     (sorted name for train_on=[eicu,mimic4])

Does not re-link timeseries; uses existing blendedlos_csaaki preprocessed_*.
Seed 974, 15% test then 15% val (same as prepare_csaaki_blendedlos).
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd

OUT = Path("/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/blendedlos_csaaki")
SEED = 974
SPLIT = 0.15


def _split_persons(persons: np.ndarray) -> tuple[set, set, set]:
    persons = pd.Index(persons).sort_values()
    n_test = int(len(persons) * SPLIT)
    n_val = int(len(persons) * SPLIT)
    test = set(persons.to_series().sample(n=n_test, random_state=SEED))
    rest = persons.difference(list(test))
    val = set(rest.to_series().sample(n=n_val, random_state=SEED))
    train = set(rest.difference(list(val)))
    return train, val, test


def _write_fold(
    dest: Path,
    stays: pd.Index,
    lab: pd.DataFrame,
    flat: pd.DataFrame,
    ts_all: pd.DataFrame,
) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    stays = pd.Index(stays).unique()
    lab.loc[stays].to_parquet(dest / "labels.parquet")
    flat.loc[stays].to_parquet(dest / "flat.parquet")
    ts_all.loc[ts_all.index.isin(stays), ["ts_pth", "source_dataset", "uniquepid"]].to_csv(
        dest / "timeseries_pths.csv"
    )


def main() -> None:
    lab = pd.read_parquet(OUT / "preprocessed_labels.parquet")
    if lab.index.name != "patient":
        if "patient" in lab.columns:
            lab = lab.set_index("patient")
        else:
            lab = lab.copy()
            lab.index.name = "patient"
    lab.index = lab.index.astype(str)
    flat = pd.read_parquet(OUT / "preprocessed_flat.parquet")
    flat.index = flat.index.astype(str)

    parts: dict[str, dict[str, set]] = {}
    summary: dict = {"scheme": "mimic4+eicu train / inspire external / no sicdb", "seed": SEED}
    for db, g in lab.groupby("source_dataset"):
        if db == "inspire":
            parts[db] = {"train": set(), "val": set(), "test": set(g["uniquepid"].astype(str))}
        elif db == "sicdb":
            # Keep person split for legacy folders; not used by csa3 arms.
            tr, va, te = _split_persons(g["uniquepid"].astype(str).unique())
            parts[db] = {"train": tr, "val": va, "test": te}
        else:
            tr, va, te = _split_persons(g["uniquepid"].astype(str).unique())
            parts[db] = {"train": tr, "val": va, "test": te}
        summary[db] = {k: len(v) for k, v in parts[db].items()}

    stay_part: dict[str, dict[str, pd.Index]] = {}
    for db, g in lab.groupby("source_dataset"):
        stay_part[db] = {}
        for fold, ids in parts[db].items():
            stay_part[db][fold] = g.index[g["uniquepid"].astype(str).isin(ids)]

    ts_index = []
    for db in ("mimic4", "eicu", "sicdb", "inspire"):
        idx = pd.read_csv(
            OUT / "preprocessed_timeseries" / db / "index.csv",
            sep=";",
            index_col="patient",
        )
        idx.index = idx.index.astype(str)
        idx["source_dataset"] = db
        ts_index.append(idx)
    ts_all = pd.concat(ts_index)
    ts_all = ts_all.join(lab[["uniquepid", "source_dataset"]], rsuffix="_lab")
    if "source_dataset_lab" in ts_all.columns:
        ts_all["source_dataset"] = ts_all["source_dataset"].fillna(ts_all["source_dataset_lab"])

    # External block shared by all csa3 jobs: full INSPIRE + train-DB holdouts.
    ext_stays = pd.Index(
        np.concatenate(
            [
                np.asarray(stay_part["inspire"]["test"]),
                np.asarray(stay_part["mimic4"]["test"]),
                np.asarray(stay_part["eicu"]["test"]),
            ]
        )
    ).unique()

    jobs = {
        # sorted(mimic4,eicu) => eicu_mimic4  (see run_dbpool_experiment._split_marker)
        "train_on_eicu_mimic4": {
            "train": ["mimic4", "eicu"],
            "val": ["mimic4", "eicu"],
            "test_extra_dbs": (),  # ext_stays already has holdouts+inspire
        },
        "train_on_mimic4": {
            "train": ["mimic4"],
            "val": ["mimic4"],
            "test_extra_dbs": (),
        },
        "train_on_eicu": {
            "train": ["eicu"],
            "val": ["eicu"],
            "test_extra_dbs": (),
        },
    }

    job_summary = {}
    for folder, spec in jobs.items():
        folds = {
            "train": [stay_part[db]["train"] for db in spec["train"]],
            "val": [stay_part[db]["val"] for db in spec["val"]],
            "test": [ext_stays],
        }
        # Also include train-db own test rows inside ext already; done.
        out_folds = {}
        for fold, chunks in folds.items():
            out_folds[fold] = pd.Index(np.concatenate([np.asarray(x) for x in chunks])).unique()
            _write_fold(
                OUT / "extraction" / folder / fold,
                out_folds[fold],
                lab,
                flat,
                ts_all,
            )
        job_summary[folder] = {
            fold: {
                "n": int(len(stays)),
                "by_db": lab.loc[stays].groupby("source_dataset").size().astype(int).to_dict(),
            }
            for fold, stays in out_folds.items()
        }
        print(f"[ok] {folder}", json.dumps(job_summary[folder], ensure_ascii=False), flush=True)

    payload = {"person_split": summary, "jobs": job_summary}
    (OUT / "split_summary_mimic_eicu.json").write_text(
        json.dumps(payload, indent=2), encoding="utf-8"
    )
    print("[done] prepare_csaaki_mimic_eicu_splits", flush=True)


if __name__ == "__main__":
    main()
