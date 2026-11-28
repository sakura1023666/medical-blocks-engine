#!/usr/bin/env python3
"""Build BlendedLoS per-stay hourly parquets from BlendedICU long tables.

The long tables on Aiya-Linux were produced by USM-CHU-FGuyon/BlendedICU from
the official raw databases. BlendedLoS reads one wide parquet per stay, time
in hours. Numeric variables are the mean inside each hour. A drug column is 1
on the administration hour and the next hour (drug_exposure_time = 2 hours).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd
import polars as pl

# Defaults: Aiya-Linux 192.168.68.29, already harmonized by BlendedICU.
BASE = Path("/mnt/sda/BlendedICU/data/blended_data")
OUT = Path("/mnt/sda/BlendedICU/data/blendedlos_ready")
TS_SRC = BASE / "long_timeseries"
MED_SRC = BASE / "long_medication"
UPPER_H = 14 * 24

DB_TS = {
    "amsterdam": ["amsterdam.parquet"],
    "hirid": ["hirid.parquet"],
    "mimic4": ["mimic4.parquet"],
    "eicu": [f"eicu_part{i}.parquet" for i in range(8)],
}


def _hours(col: str) -> pl.Expr:
    return pl.col(col).dt.total_microseconds() / 3_600_000_000


def write_labels() -> None:
    lab = pd.read_parquet(BASE / "preprocessed_labels.parquet")
    flat = pd.read_parquet(BASE / "preprocessed_flat.parquet")
    los = lab["lengthofstay"]
    if str(los.dtype).startswith("timedelta"):
        days = los.dt.total_seconds() / 86400.0
    else:
        days = pd.to_numeric(los, errors="coerce")
    lab = lab.copy()
    lab["true_lengthofstay"] = days
    lab["lengthofstay"] = days.clip(upper=10.0)
    OUT.mkdir(parents=True, exist_ok=True)
    lab.to_parquet(OUT / "preprocessed_labels.parquet")
    flat.to_parquet(OUT / "preprocessed_flat.parquet")
    med_h = lab.groupby("source_dataset").true_lengthofstay.median().mul(24).round(1)
    print(f"[labels] n={len(lab)} median_hours={med_h.to_dict()}", flush=True)


def _write_wide(df: pl.DataFrame, dest: Path) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    n = 0
    for keys, sub in df.group_by("patient", maintain_order=False):
        pid = keys[0] if isinstance(keys, tuple) else keys
        wide = (
            sub.pivot(values="value", index="time", columns="variable", aggregate_function="first")
            .sort("time")
        )
        wide.write_parquet(dest / f"{pid}.parquet")
        n += 1
        if n % 2000 == 0:
            print(f"  {dest.name} {n}", flush=True)
    return n


def build_db(db: str) -> None:
    paths = [TS_SRC / name for name in DB_TS[db]]
    missing = [p for p in paths if not p.exists()]
    if missing:
        raise SystemExit(f"missing {missing}")
    print(f"[ts] {db} reading {len(paths)} files", flush=True)
    lf = (
        pl.scan_parquet([str(p) for p in paths])
        .with_columns(_hours("time").alias("hour_f"))
        .filter((pl.col("hour_f") >= 0) & (pl.col("hour_f") < UPPER_H))
        .with_columns(pl.col("hour_f").floor().cast(pl.Int32).alias("time"))
        .group_by(["patient", "time", "variable"])
        .agg(pl.col("value").mean())
    )
    ts = lf.collect(streaming=True)
    print(f"[ts] {db} hourly rows {ts.height}", flush=True)
    med_path = MED_SRC / f"{db}.parquet"
    if med_path.exists():
        med = (
            pl.scan_parquet(str(med_path))
            .with_columns(_hours("start").alias("hour_f"))
            .filter((pl.col("hour_f") >= 0) & (pl.col("hour_f") < UPPER_H))
            .with_columns(pl.col("hour_f").floor().cast(pl.Int32).alias("h0"))
            .select(
                "patient",
                "variable",
                pl.concat_list([pl.col("h0"), pl.col("h0") + 1]).alias("time"),
            )
            .explode("time")
            .filter((pl.col("time") >= 0) & (pl.col("time") < UPPER_H))
            .group_by(["patient", "time", "variable"])
            .agg(pl.lit(1.0).alias("value"))
            .collect(streaming=True)
        )
        print(f"[med] {db} rows {med.height}", flush=True)
        ts = pl.concat([ts, med], how="diagonal_relaxed")
    n = _write_wide(ts, OUT / "preprocessed_timeseries" / db)
    print(f"[done] {db} files {n}", flush=True)


def write_index() -> None:
    rows = []
    root = OUT / "preprocessed_timeseries"
    for p in root.rglob("*.parquet"):
        rows.append((p.stem, str(p.resolve())))
    idx = pd.DataFrame(rows, columns=["patient", "ts_pth"]).set_index("patient")
    idx.to_csv(root / "index.csv", sep=";")
    print(f"[index] {len(idx)}", flush=True)


def main() -> None:
    global BASE, OUT, TS_SRC, MED_SRC
    ap = argparse.ArgumentParser(description="BlendedICU long tables → per-stay hourly parquets")
    ap.add_argument("--base", default=str(BASE), help="blended_data directory (labels + long_timeseries)")
    ap.add_argument("--out", default=str(OUT), help="BlendedLoS-ready output directory")
    ap.add_argument(
        "--dbs",
        default="amsterdam,hirid,mimic4,eicu",
        help="Comma-separated source databases to materialize",
    )
    args = ap.parse_args()
    BASE = Path(args.base)
    OUT = Path(args.out)
    TS_SRC = BASE / "long_timeseries"
    MED_SRC = BASE / "long_medication"
    write_labels()
    for db in [x.strip() for x in args.dbs.split(",") if x.strip()]:
        build_db(db)
    write_index()
    (OUT / "paths.json").write_text(
        json.dumps({"blendedICU": str(OUT.resolve()) + "/"}, indent=2),
        encoding="utf-8",
    )
    print("[blendedlos_ready] OK", flush=True)


if __name__ == "__main__":
    main()
