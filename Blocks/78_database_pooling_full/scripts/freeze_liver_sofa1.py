"""Freeze SOFA-liver >=1 stays (first bilirubine >=20 umol/L)."""
import duckdb
from pathlib import Path

out = Path("/mnt/sda/BlendedICU/data/liver_dysfunction_sofa1_42151996")
out.mkdir(parents=True, exist_ok=True)
lab = "/mnt/sda/BlendedICU/data/blendedlos_ready/preprocessed_labels.parquet"
files = [
    "/mnt/sda/BlendedICU/data/blended_data/long_timeseries/mimic4.parquet",
    "/mnt/sda/BlendedICU/data/blended_data/long_timeseries/hirid.parquet",
    "/mnt/sda/BlendedICU/data/blended_data/long_timeseries/amsterdam.parquet",
] + [
    f"/mnt/sda/BlendedICU/data/blended_data/long_timeseries/eicu_part{i}.parquet"
    for i in range(8)
]
file_sql = ", ".join(repr(f) for f in files)
q = f"""
WITH bili AS (
  SELECT patient,
         arg_min(value, time) AS first_bili_umol,
         count(*) AS n_bili
  FROM read_parquet([{file_sql}])
  WHERE variable = 'bilirubine' AND time >= 0 AND value IS NOT NULL
  GROUP BY patient
)
SELECT l.source_dataset, l.patient, l.uniquepid, l.original_uniquepid,
       l.raw_age, l.true_lengthofstay, l.mortality,
       b.first_bili_umol, b.n_bili
FROM read_parquet('{lab}') l
JOIN bili b ON l.patient = b.patient
WHERE l.raw_age >= 18
  AND l.true_lengthofstay > 0.5/24.0
  AND b.first_bili_umol >= 20
ORDER BY l.source_dataset, l.patient
"""
c = duckdb.connect()
df = c.execute(q).fetchdf()
df.to_parquet(out / "eligible_stays.parquet", index=False)
(out / "RULE.txt").write_text(
    "rule: first total bilirubin at or after ICU admission, harmonized long table variable bilirubine\n"
    "unit: micromol/L\n"
    "cutoff: >= 20 micromol/L, SOFA liver item >= 1 (Vincent Crit Care Med 1998)\n"
    "also: age >= 18 and ICU stay > 0.5 h\n"
    "missing bilirubin: excluded, not imputed\n"
    "model sensitivity: drop bilirubine feature (inclusion lab)\n"
    "databases: amsterdam, mimic4, eicu, hirid\n",
    encoding="utf-8",
)
print(out)
print(df.groupby("source_dataset").agg(stays=("patient", "size"), patients=("uniquepid", "nunique"), deaths=("mortality", "sum")))
