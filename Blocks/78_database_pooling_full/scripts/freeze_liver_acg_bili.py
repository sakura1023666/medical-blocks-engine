"""Freeze ACG enzyme>=2xULN AND first TBil>=20 umol/L.

Med Intensiva 2024 ACG3-like; persons 732/5373/7241/1796.
"""
import duckdb
from pathlib import Path

out = Path("/mnt/sda/BlendedICU/data/liver_dysfunction_acg_bili_42151996")
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
  SELECT patient, arg_min(value, time) AS first_bili
  FROM read_parquet([{file_sql}])
  WHERE variable = 'bilirubine' AND time >= 0 AND value > 0
  GROUP BY patient
),
alt AS (
  SELECT patient, arg_min(value, time) AS first_alt
  FROM read_parquet([{file_sql}])
  WHERE variable = 'alanine_aminotransferase' AND time >= 0 AND value > 0
  GROUP BY patient
),
ast AS (
  SELECT patient, arg_min(value, time) AS first_ast
  FROM read_parquet([{file_sql}])
  WHERE variable = 'aspartate_aminotransferase' AND time >= 0 AND value > 0
  GROUP BY patient
),
enz AS (
  SELECT COALESCE(a.patient, s.patient) AS patient, a.first_alt, s.first_ast
  FROM alt a
  FULL OUTER JOIN ast s ON a.patient = s.patient
)
SELECT l.source_dataset, l.patient, l.uniquepid, l.original_uniquepid,
       l.raw_age, l.true_lengthofstay, l.mortality,
       b.first_bili, e.first_alt, e.first_ast
FROM read_parquet('{lab}') l
JOIN bili b ON l.patient = b.patient
JOIN enz e ON l.patient = e.patient
WHERE l.raw_age >= 18
  AND l.true_lengthofstay > 0.5/24.0
  AND b.first_bili >= 20
  AND ((e.first_alt >= 80) OR (e.first_ast >= 80))
ORDER BY l.source_dataset, l.patient
"""
c = duckdb.connect()
df = c.execute(q).fetchdf()
df.to_parquet(out / "eligible_stays.parquet", index=False)
(out / "RULE.txt").write_text(
    "rule: ACG enzyme >=2xULN AND first TBil >=20 umol/L\n"
    "predicate: first_bili>=20 AND (first_alt>=80 OR first_ast>=80)\n"
    "variables: bilirubine, alanine_aminotransferase, aspartate_aminotransferase\n"
    "reference: Med Intensiva 2024 ACG3-like; Kwo AJG 2017 enzyme band + SOFA-1.2 bili\n"
    "also: age >= 18 and ICU stay > 0.5 h\n"
    "model: drop inclusion features bilirubine,alanine_aminotransferase,aspartate_aminotransferase\n"
    "databases: amsterdam, mimic4, eicu, hirid\n",
    encoding="utf-8",
)
print(out)
print(df.groupby("source_dataset").agg(stays=("patient", "size"), persons=("uniquepid", "nunique")))
print("persons total", df["uniquepid"].nunique())
