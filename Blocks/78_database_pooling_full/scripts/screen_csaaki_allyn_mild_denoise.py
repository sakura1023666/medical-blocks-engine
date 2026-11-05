#!/usr/bin/env python3
"""Mild denoise of Allyn full pool (CSA-AKI).

Unlike aggressive crossdb (ext cov + SMD + LASSO → only ~9 vars, hurt AUROC),
this keeps almost all physiological signal and only removes clear DB-fingerprint noise.

Train-only rules (outcomes unused except for report diagnostics):
  1) Always drop creatinine, urine_output
  2) Drop medication if NOT present in BOTH train DBs at cov>=min_cov_med
     (default 0.05) — removes MIMIC-only drug shortcuts
  3) Drop ANY variable with asymmetric train presence:
       max(cov_mimic,cov_sicdb)>=0.50 and min<0.05
  4) Keep all remaining Allyn keep=1 vars (vitals/lab/resp/meds that pass)

No UV/VIF/LASSO, no external coverage hard gate, no SMD hard gate.
"""
from __future__ import annotations

import argparse
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import numpy as np
import pandas as pd

DROP_ALWAYS = {"creatinine", "urine_output", "time", "hour"}


def _has_any(path: Path, col: str) -> bool:
    try:
        df = pd.read_parquet(path, columns=[col])
    except Exception:
        return False
    if col not in df.columns:
        return False
    s = pd.to_numeric(df[col], errors="coerce")
    return bool(s.notna().any())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--blended-out",
        default="/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/blendedlos_csaaki",
    )
    ap.add_argument(
        "--ts-variables",
        default="/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/Output_database_pooling/csa_expD_pooled_mimic_sicdb/ts_variables.csv",
    )
    ap.add_argument(
        "--out-dir",
        default="/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/feature_screen_allyn_mild",
    )
    ap.add_argument("--min-cov-med", type=float, default=0.05)
    ap.add_argument("--seed", type=int, default=974)
    args = ap.parse_args()

    blended = Path(args.blended_out)
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    ts = pd.read_csv(args.ts_variables, sep=";")
    cat = ts.set_index("variable")["category"].to_dict()
    cand = [
        r.variable
        for r in ts.itertuples(index=False)
        if int(r.keep) == 1 and r.variable not in DROP_ALWAYS
    ]

    train = blended / "extraction" / "train_on_mimic4_sicdb" / "train"
    pths = pd.read_csv(train / "timeseries_pths.csv")
    df = pths.copy()
    if "source_dataset" not in df.columns or df["source_dataset"].isna().all():
        df["source_dataset"] = df["patient"].astype(str).str.split("-").str[0]

    paths = [Path(p) for p in df["ts_pth"].tolist()]
    dbs = df["source_dataset"].astype(str).to_numpy()
    print(f"[mild] train={len(df)} candidates={len(cand)}", flush=True)

    def cov_for(col: str) -> dict:
        hits = np.array([_has_any(p, col) for p in paths], dtype=bool)
        out = {}
        for db in ("mimic4", "sicdb"):
            m = dbs == db
            out[db] = float(hits[m].mean()) if m.any() else 0.0
        out["any"] = float(hits.mean())
        return out

    rows = []
    keep = []
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = {ex.submit(cov_for, c): c for c in cand}
        for fut in as_completed(futs):
            c = futs[fut]
            cov = fut.result()
            category = cat.get(c, "")
            asym = (max(cov["mimic4"], cov["sicdb"]) >= 0.50) and (
                min(cov["mimic4"], cov["sicdb"]) < 0.05
            )
            med_fail = False
            if category == "medication":
                med_fail = not (
                    cov["mimic4"] >= args.min_cov_med and cov["sicdb"] >= args.min_cov_med
                )
            drop_flag = asym or med_fail
            reason = []
            if asym:
                reason.append("asymmetric_train")
            if med_fail:
                reason.append("med_not_in_both_train_dbs")
            rec = {
                "variable": c,
                "category": category,
                "cov_mimic4": round(cov["mimic4"], 4),
                "cov_sicdb": round(cov["sicdb"], 4),
                "drop_flag": drop_flag,
                "reason": ",".join(reason) if reason else "",
                "kept": not drop_flag,
            }
            rows.append(rec)
            if not drop_flag:
                keep.append(c)
            print(
                f"  {c}: M={cov['mimic4']:.3f} S={cov['sicdb']:.3f} "
                f"keep={not drop_flag} {rec['reason']}",
                flush=True,
            )

    keep = sorted(keep, key=lambda v: (cat.get(v, ""), v))
    rep = pd.DataFrame(rows).sort_values(["kept", "category", "variable"], ascending=[False, True, True])
    rep.to_csv(out / "FEATURE_MILD_DENOISE.csv", index=False)
    (out / "csaaki_allyn_mild_keep_vars.txt").write_text("\n".join(keep) + "\n", encoding="utf-8")
    md = [
        "# Allyn mild denoise (CSA-AKI)",
        "",
        "- Base: Allyn keep=1",
        "- Always drop: creatinine, urine_output",
        f"- Drop medications unless cov>= {args.min_cov_med} in BOTH mimic4 & sicdb train",
        "- Drop asymmetric train presence (max>=0.50 & min<0.05)",
        "- No UV/VIF/LASSO; no external/SMD hard gates (those over-pruned before)",
        f"- kept {len(keep)} / {len(cand)}",
        "",
        "## KEEP",
        "",
    ]
    for v in keep:
        r = rep.loc[rep.variable == v].iloc[0]
        md.append(f"- `{v}` ({r.category}): mimic={r.cov_mimic4}, sicdb={r.cov_sicdb}")
    dropped = rep.loc[rep["drop_flag"]]
    md += ["", "## DROPPED", ""]
    for _, r in dropped.iterrows():
        md.append(f"- `{r.variable}` ({r.category}): {r.reason} (M={r.cov_mimic4}, S={r.cov_sicdb})")
    (out / "FEATURE_SCREEN_REPORT.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    (out / "FEATURE_SCREEN_META.json").write_text(
        json.dumps({"n_keep": len(keep), "n_cand": len(cand), "keep": keep}, indent=2),
        encoding="utf-8",
    )
    print(f"[mild] kept {len(keep)}/{len(cand)}", keep, flush=True)
    print("[done]", out, flush=True)


if __name__ == "__main__":
    main()
