#!/usr/bin/env python3
"""Stage1 QC: ICUAKI DN=1 extract vs BlendedICU ready labels."""
from __future__ import annotations

import json
from pathlib import Path

import pandas as pd

ROOT = Path("/home/ps/01ResearchPipeline/纳排取数/多数据库融合/ICUAKI_4DB_20261106")
READY = Path("/mnt/sda/BlendedICU/data/blendedlos_ready")
OUT = Path("/mnt/sda/BlendedICU/data/icuaaki_4db_20261106")
OUT_QC = OUT / "reports"
COHORT = OUT / "cohort_source"
OUT_QC.mkdir(parents=True, exist_ok=True)
COHORT.mkdir(parents=True, exist_ok=True)

SAMPLES = {
    "mimic4": ROOT / "out/MIMIC-IV/MIMIC-IV-ICUAKI-sample_29605.csv",
    "eicu": ROOT / "out/eICU/eICU-ICUAKI-sample_29579.csv",
    "hirid": ROOT / "out/HiRID/HiRID-ICUAKI-sample_2259.csv",
    "amsterdam": ROOT / "out/AmsterdamUMCdb/AmsterdamUMCdb-ICUAKI-sample_4006.csv",
}


def main() -> None:
    ready = pd.read_parquet(READY / "preprocessed_labels.parquet")
    if "patient" not in ready.columns:
        ready = ready.reset_index()
    ready["patient"] = ready["patient"].astype(str)
    ready["raw_id"] = ready["patient"].str.split("-", n=1).str[1]
    print("ready source_dataset:", ready["source_dataset"].value_counts().to_dict())

    rows = []
    for db, path in SAMPLES.items():
        df0 = pd.read_csv(path)
        df0.columns = [str(c).lstrip("\ufeff").strip() for c in df0.columns]
        dn = pd.to_numeric(df0["DN"], errors="coerce")
        df = df0.loc[dn == 1].copy()

        ready_ids = set(ready.loc[ready["source_dataset"] == db, "raw_id"].astype(str))
        best_col = None
        best_hit = -1
        for c in df.columns[:12]:
            ids = set(df[c].astype(str))
            hit_n = len(ids & ready_ids)
            if hit_n > best_hit:
                best_hit = hit_n
                best_col = c
        assert best_col is not None
        ids = set(df[best_col].astype(str))
        hit = ids & ready_ids
        miss = ids - ready_ids
        lab = ready[(ready["source_dataset"] == db) & (ready["raw_id"].isin(hit))]
        mort = pd.to_numeric(lab["mortality"], errors="coerce")

        pd.DataFrame(
            {"raw_id": sorted(ids), "patient": [f"{db}-{i}" for i in sorted(ids)]}
        ).to_csv(COHORT / f"dn1_ids_{db}.csv", index=False)
        df.to_csv(COHORT / f"dn1_sample_{db}.csv", index=False)
        if miss:
            pd.Series(sorted(miss), name="missing_id").to_csv(
                OUT_QC / f"stage1_miss_{db}.csv", index=False
            )

        rec = {
            "db": db,
            "n_file_rows": int(len(df0)),
            "n_dn1": int(len(df)),
            "id_col": best_col,
            "matched": int(len(hit)),
            "missing": int(len(miss)),
            "match_rate": round(len(hit) / max(len(ids), 1), 4),
            "mortality": round(float(mort.mean()), 4) if len(lab) else None,
            "deaths": int(mort.fillna(0).sum()) if len(lab) else 0,
            "dn_counts": {str(k): int(v) for k, v in dn.value_counts(dropna=False).items()},
        }
        rows.append(rec)
        print(
            db,
            "dn1",
            rec["n_dn1"],
            "id",
            best_col,
            "match",
            rec["matched"],
            "miss",
            rec["missing"],
            "rate",
            rec["match_rate"],
            "mort",
            rec["mortality"],
            flush=True,
        )

    flat = [{k: v for k, v in r.items() if k != "dn_counts"} for r in rows]
    pd.DataFrame(flat).to_csv(OUT_QC / "stage1_dn1_vs_ready_qc.csv", index=False)
    (OUT_QC / "stage1_dn1_vs_ready_qc.json").write_text(
        json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    ok = all(r["match_rate"] >= 0.95 for r in rows)
    verdict = "PASS" if ok else "FAIL"
    lines = [
        "# ICUAKI_4DB Stage1 QC",
        "",
        f"- source: `{ROOT}`",
        f"- ready: `{READY}`",
        f"- verdict: **{verdict}** (threshold match_rate >= 0.95)",
        "",
        "| db | file_rows | DN1 | id_col | matched | missing | match_rate | mortality | deaths |",
        "|---|---:|---:|---|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        lines.append(
            "| {db} | {n_file_rows} | {n_dn1} | {id_col} | {matched} | {missing} | {match_rate:.1%} | {mortality} | {deaths} |".format(
                **r
            )
        )
    lines += [
        "",
        "## Notes",
        "1. sample CSV filename uses DN1 N, but file is full base pool; filter DN==1.",
        "2. mortality from BlendedICU ready labels (extract has no death).",
        "3. wrote cohort_source/dn1_ids_*.csv for Blended filter.",
        "4. Blended must DROP creatinine + urine_output (inclusion leakage).",
        "",
        f"## Stage1 = {verdict}",
    ]
    (OUT_QC / "stage1_dn1_vs_ready_qc.md").write_text("\n".join(lines), encoding="utf-8")
    print("verdict", verdict)
    print("wrote", OUT_QC / "stage1_dn1_vs_ready_qc.md")


if __name__ == "__main__":
    main()
