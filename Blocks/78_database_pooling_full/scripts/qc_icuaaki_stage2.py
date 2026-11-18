#!/usr/bin/env python3
"""Stage2 QC after BlendedICU assemble for ICUAKI DN=1."""
from __future__ import annotations

import json
from pathlib import Path

import pandas as pd

ROOT = Path("/mnt/sda/BlendedICU/data/icuaaki_4db_20261106")
OUT = ROOT / "blendedlos_icuaaki"
QC = ROOT / "reports"
QC.mkdir(parents=True, exist_ok=True)
DBS = ("amsterdam", "mimic4", "eicu", "hirid")
DROP = {"creatinine", "urine_output"}


def main() -> None:
    lab = pd.read_parquet(OUT / "preprocessed_labels.parquet")
    if "patient" not in lab.columns:
        lab = lab.reset_index()
    lab["patient"] = lab["patient"].astype(str)

    rows = []
    for db in DBS:
        g = lab[lab["source_dataset"] == db]
        idx_path = OUT / "preprocessed_timeseries" / db / "index.csv"
        idx = pd.read_csv(idx_path, sep=";")
        # sample one parquet for drop check
        sample = pd.read_parquet(idx.iloc[0]["ts_pth"])
        has_drop = sorted(c for c in sample.columns if c in DROP)
        rows.append(
            {
                "db": db,
                "n_labels": int(len(g)),
                "n_index": int(len(idx)),
                "label_index_equal": bool(len(g) == len(idx)),
                "mortality": round(float(pd.to_numeric(g["mortality"], errors="coerce").mean()), 4),
                "deaths": int(pd.to_numeric(g["mortality"], errors="coerce").fillna(0).sum()),
                "age_median": round(float(pd.to_numeric(g["age"], errors="coerce").median()), 2),
                "los_median": round(float(pd.to_numeric(g["lengthofstay"], errors="coerce").median()), 2),
                "leaked_inclusion_cols": has_drop,
                "n_ts_cols": int(sample.shape[1]),
            }
        )

    # split sanity
    split = json.loads((OUT / "split_summary.json").read_text(encoding="utf-8"))
    assemble = json.loads((OUT / "assemble_counts.json").read_text(encoding="utf-8"))

    # train_on_amsterdam_mimic4 folds
    fold_counts = {}
    base = OUT / "extraction" / "train_on_amsterdam_mimic4"
    for fold in ("train", "val", "test"):
        lp = base / fold / "labels.parquet"
        df = pd.read_parquet(lp)
        if "source_dataset" not in df.columns:
            df = df.reset_index()
        fold_counts[fold] = df["source_dataset"].value_counts().to_dict()

    ok_link = all(r["label_index_equal"] for r in rows)
    ok_drop = all(len(r["leaked_inclusion_cols"]) == 0 for r in rows)
    ok_n = all(r["n_labels"] > 0 for r in rows)
    verdict = "PASS" if (ok_link and ok_drop and ok_n) else "FAIL"

    pd.DataFrame(rows).to_csv(QC / "stage2_blended_qc.csv", index=False)
    payload = {
        "verdict": verdict,
        "by_db": rows,
        "split_summary": split,
        "assemble_counts": assemble,
        "train_on_amsterdam_mimic4_fold_db_counts": fold_counts,
    }
    (QC / "stage2_blended_qc.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    lines = [
        "# ICUAKI_4DB Stage2 QC (after BlendedICU)",
        "",
        f"- blended out: `{OUT}`",
        f"- verdict: **{verdict}**",
        "",
        "| db | n_labels | n_index | equal | mortality | deaths | leaked Cr/UO |",
        "|---|---:|---:|---|---:|---:|---|",
    ]
    for r in rows:
        lines.append(
            f"| {r['db']} | {r['n_labels']} | {r['n_index']} | {r['label_index_equal']} | "
            f"{r['mortality']} | {r['deaths']} | {r['leaked_inclusion_cols']} |"
        )
    lines += [
        "",
        "## train_on_amsterdam_mimic4 fold x db",
        "```json",
        json.dumps(fold_counts, indent=2),
        "```",
        "",
        f"## Stage2 = {verdict}",
        "- PASS gate: labels==index per db; no creatinine/urine_output in hourly; n>0.",
    ]
    (QC / "stage2_blended_qc.md").write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps(payload, indent=2)[:2000])
    print("verdict", verdict)
    print("wrote", QC / "stage2_blended_qc.md")


if __name__ == "__main__":
    main()
