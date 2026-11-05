#!/usr/bin/env python3
"""Freeze four ULN-gate liver cohorts (user ULN 2026-11-05).

ULN: AST 38 U/L, ALT 41 U/L, total bilirubin 1.3 mg/dL (=22.23 umol/L).
Shared: age >= 18, ICU stay > 0.5 h; first post-admission lab (time>=0, value>0).

Cohorts:
  uln_ast   — first AST >= 38
  uln_alt   — first ALT >= 41
  uln_bili  — first TBil >= 22.23 umol/L
  uln_all3  — AST and ALT and TBil all above ULN
"""
from __future__ import annotations

import duckdb
from pathlib import Path

AST_ULN = 38.0
ALT_ULN = 41.0
BILI_ULN_UMOL = 1.3 * 17.1  # 22.23

LAB = "/mnt/sda/BlendedICU/data/blendedlos_ready/preprocessed_labels.parquet"
FILES = [
    "/mnt/sda/BlendedICU/data/blended_data/long_timeseries/mimic4.parquet",
    "/mnt/sda/BlendedICU/data/blended_data/long_timeseries/hirid.parquet",
    "/mnt/sda/BlendedICU/data/blended_data/long_timeseries/amsterdam.parquet",
] + [
    f"/mnt/sda/BlendedICU/data/blended_data/long_timeseries/eicu_part{i}.parquet"
    for i in range(8)
]
FILE_SQL = ", ".join(repr(f) for f in FILES)

COHORTS = {
    "uln_ast": {
        "dir": "liver_dysfunction_uln_ast_42151996",
        "where": f"e.first_ast >= {AST_ULN}",
        "rule": (
            f"rule: first AST >= {AST_ULN:g} U/L (ULN)\n"
            "variable: aspartate_aminotransferase\n"
            "also: age >= 18 and ICU stay > 0.5 h\n"
            "model: drop inclusion feature aspartate_aminotransferase\n"
            "databases: amsterdam, mimic4, eicu, hirid\n"
        ),
    },
    "uln_alt": {
        "dir": "liver_dysfunction_uln_alt_42151996",
        "where": f"e.first_alt >= {ALT_ULN}",
        "rule": (
            f"rule: first ALT >= {ALT_ULN:g} U/L (ULN)\n"
            "variable: alanine_aminotransferase\n"
            "also: age >= 18 and ICU stay > 0.5 h\n"
            "model: drop inclusion feature alanine_aminotransferase\n"
            "databases: amsterdam, mimic4, eicu, hirid\n"
        ),
    },
    "uln_bili": {
        "dir": "liver_dysfunction_uln_bili_42151996",
        "where": f"e.first_bili >= {BILI_ULN_UMOL}",
        "rule": (
            f"rule: first TBil >= {BILI_ULN_UMOL:.2f} umol/L (ULN 1.3 mg/dL)\n"
            "variable: bilirubine\n"
            "also: age >= 18 and ICU stay > 0.5 h\n"
            "model: drop inclusion feature bilirubine\n"
            "databases: amsterdam, mimic4, eicu, hirid\n"
        ),
    },
    "uln_all3": {
        "dir": "liver_dysfunction_uln_all3_42151996",
        "where": (
            f"e.first_ast >= {AST_ULN} AND e.first_alt >= {ALT_ULN} "
            f"AND e.first_bili >= {BILI_ULN_UMOL}"
        ),
        "rule": (
            f"rule: first AST>={AST_ULN:g} AND ALT>={ALT_ULN:g} "
            f"AND TBil>={BILI_ULN_UMOL:.2f} umol/L (all above ULN)\n"
            "variables: aspartate_aminotransferase, alanine_aminotransferase, bilirubine\n"
            "also: age >= 18 and ICU stay > 0.5 h\n"
            "model: drop aspartate_aminotransferase,alanine_aminotransferase,bilirubine\n"
            "databases: amsterdam, mimic4, eicu, hirid\n"
        ),
    },
}


def main() -> None:
    c = duckdb.connect()
    c.execute(
        f"""
        CREATE OR REPLACE TEMP TABLE enz AS
        WITH alt AS (
          SELECT patient, arg_min(value, time) AS first_alt
          FROM read_parquet([{FILE_SQL}])
          WHERE variable = 'alanine_aminotransferase' AND time >= 0 AND value > 0
          GROUP BY patient
        ),
        ast AS (
          SELECT patient, arg_min(value, time) AS first_ast
          FROM read_parquet([{FILE_SQL}])
          WHERE variable = 'aspartate_aminotransferase' AND time >= 0 AND value > 0
          GROUP BY patient
        ),
        bili AS (
          SELECT patient, arg_min(value, time) AS first_bili
          FROM read_parquet([{FILE_SQL}])
          WHERE variable = 'bilirubine' AND time >= 0 AND value > 0
          GROUP BY patient
        )
        SELECT COALESCE(a.patient, s.patient, b.patient) AS patient,
               a.first_alt, s.first_ast, b.first_bili
        FROM alt a
        FULL OUTER JOIN ast s ON a.patient = s.patient
        FULL OUTER JOIN bili b ON COALESCE(a.patient, s.patient) = b.patient
        """
    )
    base = Path("/mnt/sda/BlendedICU/data")
    for key, meta in COHORTS.items():
        out = base / meta["dir"]
        out.mkdir(parents=True, exist_ok=True)
        q = f"""
        SELECT l.source_dataset, l.patient, l.uniquepid, l.original_uniquepid,
               l.raw_age, l.true_lengthofstay, l.mortality,
               e.first_alt, e.first_ast, e.first_bili
        FROM read_parquet('{LAB}') l
        JOIN enz e ON l.patient = e.patient
        WHERE l.raw_age >= 18
          AND l.true_lengthofstay > 0.5/24.0
          AND ({meta["where"]})
        ORDER BY l.source_dataset, l.patient
        """
        df = c.execute(q).fetchdf()
        df.to_parquet(out / "eligible_stays.parquet", index=False)
        (out / "RULE.txt").write_text(meta["rule"], encoding="utf-8")
        print("====", key, out)
        print(df.groupby("source_dataset").agg(stays=("patient", "size"), persons=("uniquepid", "nunique")))
        print("persons total", df["uniquepid"].nunique())


if __name__ == "__main__":
    main()
