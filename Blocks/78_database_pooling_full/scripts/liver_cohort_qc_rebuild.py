#!/usr/bin/env python3
"""QC + rebuild missing/truncated hourly files for a liver BlendedLoS cohort.

Usage:
  python liver_cohort_qc_rebuild.py --root /mnt/sda/.../liver_dysfunction_XXX \
      --out-name blendedlos_XXX [--gate-cols first_alt:200,first_alp:230] [--gate-or]
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import duckdb
import numpy as np
import pandas as pd
import pyarrow.parquet as pq

READY = Path("/mnt/sda/BlendedICU/data/blendedlos_ready/preprocessed_timeseries")
LONG_ROOT = Path("/mnt/sda/BlendedICU/data/blended_data/long_timeseries")
MED_ROOT = Path("/mnt/sda/BlendedICU/data/blended_data/long_medication")
DBS = ("amsterdam", "mimic4", "eicu", "hirid")


def long_files(db: str):
    if db == "eicu":
        return [str(LONG_ROOT / f"eicu_part{i}.parquet") for i in range(8)]
    return [str(LONG_ROOT / f"{db}.parquet")]


def reconstruct(db: str, pid: str) -> pd.DataFrame:
    c = duckdb.connect()
    sql_files = ", ".join(repr(f) for f in long_files(db))
    long = c.execute(
        f"""
        SELECT time / 1000000.0 AS sec, variable, value
        FROM read_parquet([{sql_files}])
        WHERE patient = ? AND time >= 0 AND value IS NOT NULL
        """,
        [pid],
    ).fetchdf()
    if long.empty:
        raise RuntimeError(f"no long rows {pid}")
    long["h"] = np.floor(long["sec"] / 3600.0).astype(int)
    wide = long.pivot_table(index="h", columns="variable", values="value", aggfunc="mean")
    meds = c.execute(
        """
        SELECT start / 1000000.0 AS s0, "end" / 1000000.0 AS s1, variable
        FROM read_parquet(?)
        WHERE patient = ? AND variable IS NOT NULL AND start IS NOT NULL AND "end" IS NOT NULL
        """,
        [str(MED_ROOT / f"{db}.parquet"), pid],
    ).fetchdf()
    h0, h1 = int(wide.index.min()), int(wide.index.max())
    if len(meds):
        meds["h0"] = np.floor(meds["s0"].clip(lower=0) / 3600.0).astype(int)
        meds["h1"] = np.floor(meds["s1"].clip(lower=0) / 3600.0).astype(int)
        h0 = min(h0, int(meds["h0"].min()))
        h1 = max(h1, int(meds["h1"].max()))
    idx = np.arange(h0, h1 + 1)
    wide = wide.reindex(idx)
    for var, g in meds.groupby("variable"):
        mark = pd.Series(np.nan, index=idx, dtype="float64")
        for a, b in zip(g["h0"].tolist(), g["h1"].tolist()):
            if b < a:
                continue
            mark.loc[a:b] = 1.0
        wide[var] = mark
    wide.index.name = "time"
    out = wide.reset_index()
    out["time"] = out["time"].astype("int64")
    return out


def rebuild_missing_and_truncated(root: Path, out: Path, elig: pd.DataFrame) -> dict:
    missing = []
    for db, g in elig.groupby("source_dataset"):
        for pid in g["patient"].astype(str):
            if not (READY / db / f"{pid}.parquet").exists():
                missing.append((db, pid))

    lab = pd.read_parquet(out / "preprocessed_labels.parquet")
    if "patient" not in lab.columns:
        lab = lab.reset_index()
    lab["patient"] = lab["patient"].astype(str)
    lab["los_h"] = pd.to_numeric(lab["true_lengthofstay"], errors="coerce") * 24.0

    shortlist = []
    for db in DBS:
        g = lab.loc[lab.source_dataset == db]
        for sid, los_h in zip(g["patient"].tolist(), g["los_h"].tolist()):
            fp = READY / db / f"{sid}.parquet"
            if not fp.exists():
                continue
            n = pq.ParquetFile(fp).metadata.num_rows
            if los_h >= 6 and n <= max(2, int(los_h * 0.05)):
                shortlist.append((db, sid, n, float(los_h)))

    con = duckdb.connect()
    recoverable, sparse = [], []
    for db in DBS:
        items = [x for x in shortlist if x[0] == db]
        if not items:
            continue
        sql_files = ", ".join(repr(f) for f in long_files(db))
        pids = [x[1] for x in items]
        for i in range(0, len(pids), 200):
            chunk = pids[i : i + 200]
            qmarks = ",".join("?" for _ in chunk)
            df = con.execute(
                f"""
                SELECT patient, count(DISTINCT floor(time/1e6/3600.0)) AS n_h
                FROM read_parquet([{sql_files}])
                WHERE patient IN ({qmarks}) AND time >= 0 AND value IS NOT NULL
                GROUP BY patient
                """,
                chunk,
            ).fetchdf()
            m = {str(r.patient): int(r.n_h) for r in df.itertuples()}
            for db0, sid, n_hly, los_h in items[i : i + 200]:
                n_h = m.get(sid, 0)
                rec = {"db": db0, "patient": sid, "hourly_rows": n_hly, "long_hours": n_h, "los_h": los_h}
                if n_h >= max(5, n_hly * 3) and n_h > n_hly:
                    recoverable.append(rec)
                else:
                    sparse.append(rec)

    todo, seen = [], set()
    for item in missing + [(r["db"], r["patient"]) for r in recoverable]:
        if item not in seen:
            todo.append(item)
            seen.add(item)

    ok, fail, no_long = [], [], []
    for db, pid in todo:
        try:
            df = reconstruct(db, pid)
            path = READY / db / f"{pid}.parquet"
            path.parent.mkdir(parents=True, exist_ok=True)
            df.to_parquet(path, index=False)
            print("wrote", path, "shape", df.shape, flush=True)
            ok.append(pid)
        except RuntimeError as e:
            if "no long rows" in str(e):
                print("NO_LONG", pid, flush=True)
                no_long.append(pid)
            else:
                print("FAIL", pid, e, flush=True)
                fail.append((pid, str(e)))
        except Exception as e:
            print("FAIL", pid, e, flush=True)
            fail.append((pid, str(e)))

    if no_long:
        before = len(elig)
        elig2 = elig[~elig.patient.isin(no_long)].copy()
        elig2.to_parquet(root / "eligible_stays.parquet", index=False)
        print(f"elig dropped no_long {before}->{len(elig2)}", flush=True)
        elig = elig2

    report = {
        "missing": missing,
        "recoverable": recoverable,
        "sparse": sparse,
        "rebuilt_ok": ok,
        "fail": fail,
        "no_long": no_long,
    }
    (root / "hourly_truncation_scan.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("rebuild ok", len(ok), "fail", len(fail), "no_long", len(no_long), "sparse", len(sparse), flush=True)
    return report


def run_qc(root: Path, out: Path, elig: pd.DataFrame, gate_spec: str | None, gate_or: bool) -> list[str]:
    issues, notes = [], []
    lab = pd.read_parquet(out / "preprocessed_labels.parquet")
    if "patient" not in lab.columns:
        lab = lab.reset_index()
    lab["patient"] = lab["patient"].astype(str)
    elig = elig.copy()
    elig["patient"] = elig["patient"].astype(str)
    lab["los_h"] = pd.to_numeric(lab["true_lengthofstay"], errors="coerce") * 24.0

    print("=== 0. cohort ===", flush=True)
    print(lab.source_dataset.value_counts().to_dict(), "total", len(lab), flush=True)

    print("=== 1. hourly coverage ===", flush=True)
    for db in DBS:
        ids = elig.loc[elig.source_dataset == db, "patient"].tolist()
        miss_ready = [p for p in ids if not (READY / db / f"{p}.parquet").exists()]
        miss_out = [p for p in ids if not (out / "preprocessed_timeseries" / db / f"{p}.parquet").exists()]
        print(db, "elig", len(ids), "miss_ready", len(miss_ready), miss_ready[:5], "miss_out", len(miss_out), flush=True)
        if miss_ready or miss_out:
            issues.append(f"{db} missing_hourly ready_n={len(miss_ready)} out_n={len(miss_out)} eg={miss_ready[:5]}")

    print("=== 2. labels vs eligible vs index ===", flush=True)
    for db in DBS:
        e = set(elig.loc[elig.source_dataset == db, "patient"])
        l = set(lab.loc[lab.source_dataset == db, "patient"])
        idx = pd.read_csv(out / "preprocessed_timeseries" / db / "index.csv", sep=";")
        i = set(idx["patient"].astype(str))
        print(db, "elig", len(e), "lab", len(l), "idx", len(i), "elig-idx", len(e - i), flush=True)
        if e - i:
            issues.append(f"{db} eligible not in index n={len(e - i)}")
        if i - l:
            issues.append(f"{db} index not in labels n={len(i - l)}")

    print("=== 3. age/LOS/mortality ===", flush=True)
    for db, g in lab.groupby("source_dataset"):
        age = pd.to_numeric(g["age"], errors="coerce")
        los = pd.to_numeric(g["true_lengthofstay"], errors="coerce")
        mort = pd.to_numeric(g["mortality"], errors="coerce")
        print(
            db, "n", len(g), "age_min", float(age.min()), "age<18", int((age < 18).sum()),
            "los<=0.5h", int((los <= 0.5 / 24).sum()), "mort_nan", int(mort.isna().sum()),
            "mort_rate", round(float(mort.mean()), 3), flush=True,
        )
        if (age < 18).any() or (los <= 0.5 / 24).any() or mort.isna().any():
            issues.append(f"{db} age/los/mort sanity fail")

    def stay_ids(df):
        return set(df["patient"].astype(str)) if "patient" in df.columns else set(pd.Index(df.index).astype(str))

    def person_ids(df):
        for c in ("uniquepid", "original_uniquepid"):
            if c in df.columns:
                return set(df[c].astype(str))
        return stay_ids(df)

    print("=== 4. split leakage ===", flush=True)
    for job in ("train_on_amsterdam", "train_on_mimic4", "train_on_amsterdam_mimic4"):
        folds, pf = {}, {}
        for fold in ("train", "val", "test"):
            df = pd.read_parquet(out / "extraction" / job / fold / "labels.parquet")
            folds[fold] = stay_ids(df)
            pf[fold] = person_ids(df)
        leak_s = (folds["train"] & folds["val"]) | (folds["train"] & folds["test"]) | (folds["val"] & folds["test"])
        leak_p = (pf["train"] & pf["val"]) | (pf["train"] & pf["test"]) | (pf["val"] & pf["test"])
        print(job, {k: len(v) for k, v in folds.items()}, "leak_stay", len(leak_s), "leak_person", len(leak_p), flush=True)
        if leak_s:
            issues.append(f"{job} stay leakage")
        if leak_p:
            issues.append(f"{job} person leakage")
        for fold in ("train", "val"):
            df = pd.read_parquet(out / "extraction" / job / fold / "labels.parquet")
            bad = set(df["source_dataset"]) & {"eicu", "hirid"}
            if bad:
                issues.append(f"{job}/{fold} held-out {bad}")

    print("=== 5. inclusion gate ===", flush=True)
    if gate_spec == "acg_bili":
        # first_bili>=20 AND (first_alt>=80 OR first_ast>=80)
        need = ("first_bili", "first_alt", "first_ast")
        for col in need:
            if col not in elig.columns:
                issues.append(f"elig missing gate col {col}")
        if all(c in elig.columns for c in need):
            for db, g in elig.groupby("source_dataset"):
                bili = pd.to_numeric(g["first_bili"], errors="coerce")
                alt = pd.to_numeric(g["first_alt"], errors="coerce")
                ast = pd.to_numeric(g["first_ast"], errors="coerce")
                enz = (alt >= 80) | (ast >= 80)
                ok = (bili >= 20) & enz
                print(
                    db,
                    "bili>=20", int((bili >= 20).sum()),
                    "enz_ge80", int(enz.sum()),
                    "combo_ok", int(ok.sum()),
                    "fail", int((~ok).sum()),
                    "bili_nan", int(bili.isna().sum()),
                    flush=True,
                )
                if (~ok).any() or bili.isna().any():
                    issues.append(f"{db} acg_bili gate fail n={int((~ok | bili.isna()).sum())}")
    elif gate_spec:
        # e.g. first_alt:200,first_alp:230 with --gate-or
        parts = []
        for tok in gate_spec.split(","):
            col, cut = tok.split(":")
            parts.append((col.strip(), float(cut)))
        for db, g in elig.groupby("source_dataset"):
            masks = []
            for col, cut in parts:
                if col not in g.columns:
                    issues.append(f"elig missing gate col {col}")
                    continue
                x = pd.to_numeric(g[col], errors="coerce")
                masks.append(x >= cut)
                print(db, col, "ge", cut, int((x >= cut).sum()), "nan", int(x.isna().sum()), flush=True)
            if not masks:
                continue
            ok = masks[0]
            for m in masks[1:]:
                ok = (ok | m) if gate_or else (ok & m)
            if (~ok).any():
                issues.append(f"{db} gate fail n={int((~ok).sum())}")
                print(db, "gate_fail", int((~ok).sum()), flush=True)
    else:
        # MARS-style: first_time within 48h already frozen; check hours column if present
        if "first_bili33_hours" in elig.columns:
            for db, g in elig.groupby("source_dataset"):
                h = pd.to_numeric(g["first_bili33_hours"], errors="coerce")
                print(db, "first_bili33_hours max", float(h.max()), "gt48", int((h > 48).sum()), flush=True)
                if (h > 48).any() or h.isna().any():
                    issues.append(f"{db} mars 48h gate fail")
        else:
            notes.append("no gate_spec; skipped numeric gate check")

    print("=== 6. empty hourly ===", flush=True)
    empty = []
    for db in DBS:
        for p in (out / "preprocessed_timeseries" / db).glob("*.parquet"):
            if pq.ParquetFile(p).metadata.num_rows == 0:
                empty.append(p.name)
    print("empty", len(empty), flush=True)
    if empty:
        issues.append(f"empty_hourly n={len(empty)}")

    print("=== 7. flat alignment ===", flush=True)
    flat = pd.read_parquet(out / "preprocessed_flat.parquet")
    if "patient" not in flat.columns:
        flat = flat.reset_index()
    if set(lab.patient) != set(flat.patient.astype(str)):
        issues.append("flat/labels mismatch")
    if lab.patient.duplicated().any():
        issues.append("dup patient")

    # residual truncation after rebuild
    scan = json.loads((root / "hourly_truncation_scan.json").read_text()) if (root / "hourly_truncation_scan.json").exists() else {}
    # re-check recoverable against current READY
    still = []
    for r in scan.get("recoverable", []):
        fp = READY / r["db"] / f"{r['patient']}.parquet"
        n = pq.ParquetFile(fp).metadata.num_rows if fp.exists() else 0
        if n <= r["hourly_rows"]:
            still.append(r["patient"])
    if still:
        issues.append(f"still_truncated_after_rebuild n={len(still)} eg={still[:5]}")
    if scan.get("sparse"):
        notes.append(f"sparse_source n={len(scan['sparse'])}")

    print("=== SUMMARY ===", flush=True)
    if issues:
        print("ISSUES:", flush=True)
        for x in issues:
            print("-", x, flush=True)
    else:
        print("NO_BLOCKING_ISSUES", flush=True)
    if notes:
        print("NOTES:", flush=True)
        for x in notes:
            print("-", x, flush=True)

    (root / "Data_QC.md").write_text(
        "# data QC\n\n## Blocking\n"
        + ("\n".join(f"- {x}" for x in issues) if issues else "- NO_BLOCKING_ISSUES")
        + "\n\n## Notes\n"
        + ("\n".join(f"- {x}" for x in notes) if notes else "- (none)")
        + "\n",
        encoding="utf-8",
    )
    return issues


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--out-name", required=True)
    ap.add_argument("--gate-cols", default="")
    ap.add_argument("--gate-or", action="store_true")
    ap.add_argument("--prepare-script", required=True)
    args = ap.parse_args()

    root = Path(args.root)
    out = root / args.out_name
    elig = pd.read_parquet(root / "eligible_stays.parquet")
    if "patient" not in elig.columns:
        elig = elig.reset_index()
    elig["patient"] = elig["patient"].astype(str)

    # prepare once (may miss files)
    import subprocess, sys
    subprocess.check_call([sys.executable, args.prepare_script])

    # rebuild then re-prepare
    rebuild_missing_and_truncated(root, out, elig)
    import shutil
    if out.exists():
        shutil.rmtree(out)
    subprocess.check_call([sys.executable, args.prepare_script])

    elig = pd.read_parquet(root / "eligible_stays.parquet")
    if "patient" not in elig.columns:
        elig = elig.reset_index()
    issues = run_qc(root, out, elig, args.gate_cols or None, args.gate_or)
    if issues:
        raise SystemExit(2)
    print("QC_PASS", flush=True)


if __name__ == "__main__":
    main()
