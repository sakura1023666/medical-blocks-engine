#!/usr/bin/env python3
"""Adapt RealExtraction_4DB delivery/hourly → BlendedLoS-compatible extraction layout.

RealExtraction schemas (2026-10-09):
  02_stays.parquet: stay_key, source_dataset, source_patient_id, mortality_icu, icu_los_hours_uncapped, …
  04_static_features.parquet: patient_key, stay_id, sex_raw, age_model, height_cm_raw, weight_kg_raw, …
  hourly/*_hourly.parquet: LONG format (hour_index, variable_standard, value_mean/last/…)
  hourly/*_hourly_meds.parquet: LONG med exposure (hour_index, variable_standard) → binary 1

Output (under --out):
  preprocessed_labels.parquet / preprocessed_flat.parquet
  preprocessed_timeseries/<source>/<stay_id>.parquet  (wide: time + variables)
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

DB_MAP = {
    "AmsterdamUMCdb": "amsterdam",
    "amsterdam": "amsterdam",
    "amumc": "amsterdam",
    "MIMIC-IV": "mimic4",
    "mimic4": "mimic4",
    "mimic": "mimic4",
    "eICU": "eicu",
    "eicu": "eicu",
    "HiRID": "hirid",
    "hirid": "hirid",
}

HOURLY_FILES = {
    "amsterdam": "amumc_hourly.parquet",
    "eicu": "eicu_hourly.parquet",
    "hirid": "hirid_hourly.parquet",
    "mimic4": "mimic_hourly.parquet",
}

MEDS_FILES = {
    "amsterdam": "amumc_hourly_meds.parquet",
    "eicu": "eicu_hourly_meds.parquet",
    "hirid": "hirid_hourly_pharma_typeid.parquet",
    "mimic4": "mimic_hourly_meds.parquet",
}

# Align RealExtraction names → BlendedLoS ts_variables keep=1 names
VAR_RENAME = {
    "O2_pulseoxymetry_saturation": "O2_arterial_saturation",
}

# BlendedLoS keep=1 variables (time first). Filled with NaN when absent per stay.
def _load_keep_vars() -> list[str]:
    cand = [
        Path(__file__).resolve().parents[1] / "upstream" / "BlendedLoS" / "ts_variables.csv",
        Path(__file__).resolve().parents[3] / "Blocks/78_database_pooling_full/upstream/BlendedLoS/ts_variables.csv",
    ]
    for p in cand:
        if p.exists():
            tsv = pd.read_csv(p, sep=";")
            vars_ = tsv.loc[(tsv["keep"] == 1) & (tsv["variable"].astype(str) != "time"), "variable"].astype(str)
            return ["time"] + vars_.tolist()
    return ["time"]


KEEP_VARS = None  # lazy


def _norm_db(x: str) -> str:
    return DB_MAP.get(str(x).strip(), str(x).strip().lower())


def _read_parquet(path: Path, columns=None) -> pd.DataFrame:
    return pd.read_parquet(path, columns=columns)


def _decategorize_blendedicu(series: pd.Series) -> pd.Series:
    """BlendedICU v0.3.2 Ams_FLProcessor._decategorize: left edge of '60-69' / '80+'."""

    def _dec(x):
        if pd.isna(x):
            return np.nan
        token = str(x).replace("-", " ").replace("+", " ").split()
        return token[0] if token else np.nan

    num = pd.to_numeric(series, errors="coerce")
    raw = series.map(_dec)
    dec = pd.to_numeric(raw, errors="coerce")
    return num.where(num.notna(), dec)


def _amsterdam_los_hours(data_root: Path, stays: pd.DataFrame) -> pd.Series:
    """BlendedICU v0.3.2 treats admissions.lengthofstay as hours, then /24 → days.

    RealExtraction linux29_t2.py divided that field by 60. The mapping file keeps
    the undivided value in icu_los_min_raw (median ~26, i.e. hours).
    """
    los_h = pd.to_numeric(stays.get("icu_los_hours_uncapped"), errors="coerce")
    mapping = data_root / "out" / "29_T2" / "amumc_stay_mapping_outcomes_static.parquet"
    if not mapping.exists():
        return los_h
    mp = pd.read_parquet(mapping, columns=["source_icu_stay_id", "icu_los_min_raw"])
    mp["sid"] = mp["source_icu_stay_id"].map(_stay_id_norm)
    mp["los_hours_v032"] = pd.to_numeric(mp["icu_los_min_raw"], errors="coerce")
    sid = stays["source_icu_stay_id"].map(_stay_id_norm)
    lookup = mp.drop_duplicates("sid").set_index("sid")["los_hours_v032"]
    am = stays["source_dataset"].astype(str).isin(["amsterdam", "AmsterdamUMCdb"])
    corrected = sid.map(lookup)
    los_h = los_h.copy()
    los_h.loc[am & corrected.notna()] = corrected.loc[am & corrected.notna()]
    return los_h


def _stay_id_norm(x: str) -> str:
    s = str(x).strip()
    if s.endswith(".0") and s[:-2].isdigit():
        s = s[:-2]
    return s


def _load_selected_stay_keys(data_root: Path) -> set[tuple[str, str]] | None:
    """Prefer RealExtraction cohort index is_selected_original==1 (~19,573/DB)."""
    cand = [
        data_root / "out" / "01_cohort_index_real.csv",
        data_root / "01_cohort_index_real.csv",
    ]
    path = next((p for p in cand if p.exists()), None)
    if path is None:
        return None
    idx = pd.read_csv(path, usecols=["db", "index_stay_id", "is_selected_original"], dtype=str)
    idx = idx[idx["is_selected_original"].isin(["1", "True", "true"])]
    return set(zip(idx["db"].astype(str), idx["index_stay_id"].map(_stay_id_norm)))


def build_labels_flat(
    delivery: Path,
    out: Path,
    selected_pairs: set[tuple[str, str]] | None = None,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    stays = _read_parquet(delivery / "02_stays.parquet")
    static = _read_parquet(delivery / "04_static_features.parquet")

    stays = stays.copy()
    if selected_pairs is not None:
        raw_db = stays["source_dataset"].astype(str)
        raw_sid = stays["source_icu_stay_id"].map(_stay_id_norm)
        m = [((d, s) in selected_pairs) for d, s in zip(raw_db, raw_sid)]
        stays = stays.loc[m].copy()
        print(f"selected filter: kept {len(stays)} stays from cohort index")
        if len(stays) == 0:
            raise SystemExit(
                "selected filter kept 0 stays; check db/index_stay_id vs "
                "source_dataset/source_icu_stay_id alignment"
            )

    stays["source_dataset"] = stays["source_dataset"].map(_norm_db)
    # BlendedLoS DataSplitter groups by uniquepid globally — must be cross-DB unique
    stays["uniquepid"] = stays["source_dataset"].astype(str) + ":" + stays["source_patient_id"].astype(str)
    stays["stay_id"] = stays["stay_key"].astype(str)
    stays["mortality"] = pd.to_numeric(stays.get("mortality_icu"), errors="coerce").fillna(0).astype(int)

    # BlendedICU v0.3.2: lengthofstay unit = hour → days; clip upper_los later in BlendedLoS (10 d).
    data_root = delivery.parent.parent if delivery.name == "delivery" else delivery.parent
    los_h = _amsterdam_los_hours(data_root, stays)
    stays["true_lengthofstay"] = los_h / 24.0
    stays["lengthofstay"] = stays["true_lengthofstay"].clip(upper=10.0)

    labels = stays.set_index("stay_id")[
        ["uniquepid", "source_dataset", "mortality", "lengthofstay", "true_lengthofstay"]
    ].copy()

    flat_src = static.copy()
    flat_src["source_dataset_norm"] = flat_src["source_dataset"].map(_norm_db)
    flat_src["raw_stay"] = flat_src["stay_id"].astype(str)
    map_df = stays[["stay_id", "source_dataset", "source_icu_stay_id"]].copy()
    map_df["source_icu_stay_id"] = map_df["source_icu_stay_id"].map(_stay_id_norm)
    flat_src = flat_src.merge(
        map_df,
        left_on=["source_dataset_norm", "raw_stay"],
        right_on=["source_dataset", "source_icu_stay_id"],
        how="inner",
        suffixes=("", "_lab"),
    )
    age_model = pd.to_numeric(flat_src.get("age_model"), errors="coerce")
    age_anchor = _decategorize_blendedicu(flat_src.get("age_raw_anchor"))
    flat_src["age"] = age_model.where(age_model.notna(), age_anchor)
    sex = flat_src.get("sex_raw")
    if sex is not None:
        flat_src["sex"] = sex.map(
            lambda x: 1
            if str(x).lower() in ("m", "male", "1", "man")
            else (
                0
                if str(x).lower() in ("f", "female", "0", "woman", "vrouw")
                else (0.5 if str(x).lower() in ("unknown", "other", "nan") else np.nan)
            )
        )
    else:
        flat_src["sex"] = np.nan
    flat_src["height"] = _decategorize_blendedicu(flat_src.get("height_cm_raw"))
    flat_src["weight"] = _decategorize_blendedicu(flat_src.get("weight_kg_raw"))
    # merge keeps static stay_id and renames the BlendedLoS stay key to stay_id_lab
    key = "stay_id_lab" if "stay_id_lab" in flat_src.columns else "stay_id"
    flat_src = flat_src.drop_duplicates(subset=[key], keep="first")
    flat = flat_src.set_index(key)[["age", "sex", "height", "weight"]]
    flat.index.name = "stay_id"
    flat = flat.reindex(labels.index)

    labels.to_parquet(out / "preprocessed_labels.parquet")
    flat.to_parquet(out / "preprocessed_flat.parquet")
    return labels, flat


def _attach_stay_id(df: pd.DataFrame, stays_sub: pd.DataFrame) -> pd.DataFrame:
    """Map hourly source_icu_stay_id → BlendedLoS stay_id (= stay_key)."""
    df = df.copy()
    if "stay_key" in df.columns:
        df["stay_id"] = df["stay_key"].astype(str)
        return df
    if "source_icu_stay_id" not in df.columns:
        raise SystemExit(f"hourly missing stay id cols: {list(df.columns)[:20]}")
    df["source_icu_stay_id"] = df["source_icu_stay_id"].map(_stay_id_norm)
    sub = stays_sub[["stay_id", "source_icu_stay_id"]].copy()
    sub["source_icu_stay_id"] = sub["source_icu_stay_id"].map(_stay_id_norm)
    return df.merge(sub, on="source_icu_stay_id", how="inner")


def _pivot_vitals_labs(df: pd.DataFrame) -> dict[str, pd.DataFrame]:
    if "hour_index" not in df.columns or "variable_standard" not in df.columns:
        raise SystemExit(f"hourly expected long schema, got {list(df.columns)[:20]}")
    val_col = "value_mean" if "value_mean" in df.columns else ("value_last" if "value_last" in df.columns else None)
    if val_col is None:
        raise SystemExit("hourly missing value_mean/value_last")
    df = df.copy()
    df["variable_standard"] = df["variable_standard"].astype(str).replace(VAR_RENAME)
    out: dict[str, pd.DataFrame] = {}
    for stay_id, g in df.groupby("stay_id", sort=False):
        wide = g.pivot_table(
            index="hour_index",
            columns="variable_standard",
            values=val_col,
            aggfunc="last",
        )
        wide = wide.sort_index().reset_index().rename(columns={"hour_index": "time"})
        wide.columns = [str(c) for c in wide.columns]
        out[str(stay_id)] = wide
    return out


def _pivot_meds_binary(df: pd.DataFrame) -> dict[str, pd.DataFrame]:
    """Medication long rows → binary presence (1.0) by hour."""
    if df is None or len(df) == 0:
        return {}
    df = df.copy()
    # HiRID pharma typeids are not BlendedLoS names — skip if not alphabetic-ish
    vs = df["variable_standard"].astype(str)
    ok = vs.str.match(r"^[A-Za-z]", na=False)
    df = df.loc[ok]
    if len(df) == 0:
        return {}
    df["value"] = 1.0
    out: dict[str, pd.DataFrame] = {}
    for stay_id, g in df.groupby("stay_id", sort=False):
        wide = g.pivot_table(
            index="hour_index",
            columns="variable_standard",
            values="value",
            aggfunc="max",
        )
        wide = wide.sort_index().reset_index().rename(columns={"hour_index": "time"})
        wide.columns = [str(c) for c in wide.columns]
        out[str(stay_id)] = wide
    return out


def _merge_wide(vitals: pd.DataFrame, meds: pd.DataFrame | None) -> pd.DataFrame:
    global KEEP_VARS
    if KEEP_VARS is None:
        KEEP_VARS = _load_keep_vars()
    if meds is None or len(meds) == 0:
        out = vitals
    else:
        out = vitals.merge(meds, on="time", how="outer", suffixes=("", "_med"))
        drop_cols = [c for c in out.columns if c.endswith("_med")]
        if drop_cols:
            out = out.drop(columns=drop_cols)
    out = out.sort_values("time").reset_index(drop=True)
    # full schema required: pyarrow column projection fails on missing fields
    for c in KEEP_VARS:
        if c not in out.columns:
            out[c] = np.nan
    return out.reindex(columns=KEEP_VARS)


def export_timeseries(
    hourly_dir: Path,
    labels: pd.DataFrame,
    stays: pd.DataFrame,
    out_ts: Path,
    max_stays_per_db: int | None = None,
):
    out_ts.mkdir(parents=True, exist_ok=True)
    stays = stays.copy()
    stays["source_dataset_norm"] = stays["source_dataset"].map(_norm_db)
    stays["stay_id"] = stays["stay_key"].astype(str)
    stays["source_icu_stay_id"] = stays["source_icu_stay_id"].map(_stay_id_norm)

    summary = []
    written_ids: list[str] = []
    for db, fname in HOURLY_FILES.items():
        fp = hourly_dir / fname
        if not fp.exists():
            summary.append({"source_dataset": db, "status": "missing", "path": str(fp)})
            continue
        keep_ids = labels.index[labels["source_dataset"] == db].tolist()
        if max_stays_per_db is not None:
            keep_ids = keep_ids[: int(max_stays_per_db)]
        keep_set = set(keep_ids)
        if not keep_set:
            summary.append({"source_dataset": db, "status": "no_labels", "n_stays": 0})
            continue

        stays_sub = stays.loc[stays["source_dataset_norm"] == db]
        # Prefer mapping only for keep_set stays
        stays_sub = stays_sub.loc[stays_sub["stay_id"].isin(keep_set)]

        df = _attach_stay_id(_read_parquet(fp), stays_sub)
        df = df[df["stay_id"].isin(keep_set)]
        if len(df) == 0:
            summary.append(
                {
                    "source_dataset": db,
                    "status": "no_hourly_overlap",
                    "n_labels": len(keep_set),
                    "n_stays": 0,
                }
            )
            continue

        wide_map = _pivot_vitals_labs(df)

        med_fp = hourly_dir / MEDS_FILES.get(db, "")
        if med_fp.exists():
            med = _attach_stay_id(_read_parquet(med_fp), stays_sub)
            med = med[med["stay_id"].isin(keep_set)]
            med_map = _pivot_meds_binary(med)
        else:
            med_map = {}

        db_dir = out_ts / db
        db_dir.mkdir(parents=True, exist_ok=True)
        # clear old parquet from prior smoke runs in same dir
        for old in db_dir.glob("*.parquet"):
            old.unlink()

        n = 0
        for stay_id, wide in wide_map.items():
            wide = _merge_wide(wide, med_map.get(stay_id))
            # BlendedLoS-safe filename: stay_key may contain '/' — already stay_key
            safe = str(stay_id).replace("/", "_")
            # BlendedLoS pad_sequences groups by index level 'patient'
            wide = wide.copy()
            wide.index = pd.Index([str(stay_id)] * len(wide), name="patient")
            wide.to_parquet(db_dir / f"{safe}.parquet", index=True)
            written_ids.append(str(stay_id))
            n += 1

        idx = pd.DataFrame(
            {
                "patient": [p.stem for p in sorted(db_dir.glob("*.parquet"))],
                "ts_pth": [str(p.resolve()) for p in sorted(db_dir.glob("*.parquet"))],
            }
        ).set_index("patient")
        idx.to_csv(db_dir / "index.csv", sep=";")
        summary.append(
            {
                "source_dataset": db,
                "status": "ok",
                "n_labels": len(keep_set),
                "n_stays": int(n),
                "n_with_meds": int(sum(1 for s in wide_map if s in med_map)),
                "path": str(db_dir),
            }
        )
        print(f"[adapter] {db}: labels={len(keep_set)} timeseries={n}")
    pd.DataFrame(summary).to_csv(out_ts.parent / "adapter_timeseries_summary.csv", index=False)
    return summary, written_ids


def _prune_to_timeseries(labels: pd.DataFrame, flat: pd.DataFrame, written_ids: list[str], out: Path):
    keep = set(written_ids)
    before = len(labels)
    labels = labels.loc[labels.index.isin(keep)].copy()
    flat = flat.reindex(labels.index)
    labels.to_parquet(out / "preprocessed_labels.parquet")
    flat.to_parquet(out / "preprocessed_flat.parquet")
    print(f"[adapter] prune labels to timeseries: {before} → {len(labels)}")
    return labels, flat


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-root", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-stays-per-db", type=int, default=None)
    ap.add_argument(
        "--selected-only",
        action="store_true",
        default=True,
        help="Only selected RealExtraction cohort (~19,573/db). Default ON.",
    )
    ap.add_argument("--all-stays", action="store_true", help="Disable selected-only filter.")
    ap.add_argument(
        "--labels-flat-only",
        action="store_true",
        help="Refresh labels/flat with BlendedICU v0.3.2 LOS and bin rules; keep existing hourly parquets.",
    )
    args = ap.parse_args()

    root = Path(args.data_root)
    delivery = root / "out" / "delivery"
    hourly = root / "out" / "hourly"
    if not delivery.exists():
        if (root / "delivery").exists():
            delivery = root / "delivery"
            hourly = root / "hourly"
        else:
            raise SystemExit(f"delivery not found under {root}")

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "extraction").mkdir(exist_ok=True)

    stays_raw = _read_parquet(delivery / "02_stays.parquet")
    selected_pairs = None
    if args.selected_only and not args.all_stays:
        selected_pairs = _load_selected_stay_keys(root)
        n_pairs = 0 if selected_pairs is None else len(selected_pairs)
        print(f"[adapter] selected_only: {n_pairs} stay pairs from cohort index")
        if selected_pairs is None:
            raise SystemExit("selected-only requested but 01_cohort_index_real.csv not found")

    labels, flat = build_labels_flat(delivery, out, selected_pairs=selected_pairs)
    if args.max_stays_per_db is not None:
        parts = []
        for _, g in labels.groupby("source_dataset"):
            parts.append(g.head(int(args.max_stays_per_db)))
        labels = pd.concat(parts)
        labels.to_parquet(out / "preprocessed_labels.parquet")
        flat = flat.reindex(labels.index)
        flat.to_parquet(out / "preprocessed_flat.parquet")

    if args.labels_flat_only and (out / "preprocessed_timeseries").exists():
        written_ids = {p.stem for p in (out / "preprocessed_timeseries").rglob("*.parquet")}
        summary = {"mode": "labels_flat_only", "existing_parquet": len(written_ids)}
        print(f"[adapter] labels-flat-only, keep {len(written_ids)} timeseries files")
    else:
        summary, written_ids = export_timeseries(
            hourly, labels, stays_raw, out / "preprocessed_timeseries", args.max_stays_per_db
        )
    labels, flat = _prune_to_timeseries(labels, flat, written_ids, out)

    paths = {"blendedICU": str(out.resolve()) + "/"}
    (out / "paths.json").write_text(json.dumps(paths, indent=2), encoding="utf-8")
    meta = {
        "adapter": "adapt_realextraction_to_blendedlos.py",
        "n_labels": int(len(labels)),
        "by_db": labels["source_dataset"].value_counts().to_dict(),
        "timeseries": summary,
        "note": "Labels pruned to stays with hourly timeseries; AMUMC hourly coverage < selected 19573",
    }
    (out / "adapter_meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
