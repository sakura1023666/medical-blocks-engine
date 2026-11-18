"""Freeze MARS early hyperbilirubinemia: first time TBil>=33 umol/L within 48 h.

Jager et al. Front Med 2022. Pivot persons: 852 / 6824 / 8435 / 1892.
"""
import duckdb
from pathlib import Path

out = Path("/mnt/sda/BlendedICU/data/liver_dysfunction_mars_42151996")
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
# BlendedICU long time is microseconds; 48h = 48*3600*1e6
q = f"""
WITH bili33 AS (
  SELECT patient,
         min(time) AS first_time_bili33,
         arg_min(value, time) AS first_bili_at_ge33
  FROM read_parquet([{file_sql}])
  WHERE variable = 'bilirubine' AND time >= 0 AND value >= 33
  GROUP BY patient
)
SELECT l.source_dataset, l.patient, l.uniquepid, l.original_uniquepid,
       l.raw_age, l.true_lengthofstay, l.mortality,
       b.first_time_bili33, b.first_bili_at_ge33,
       b.first_time_bili33 / 1e6 / 3600.0 AS first_bili33_hours
FROM read_parquet('{lab}') l
JOIN bili33 b ON l.patient = b.patient
WHERE l.raw_age >= 18
  AND l.true_lengthofstay > 0.5/24.0
  AND b.first_time_bili33 <= 48 * 3600 * 1e6
ORDER BY l.source_dataset, l.patient
"""
c = duckdb.connect()
df = c.execute(q).fetchdf()
df.to_parquet(out / "eligible_stays.parquet", index=False)
(out / "RULE.txt").write_text(
    "rule: MARS early hyperbilirubinemia: TBil >=33 umol/L within first 48 h\n"
    "predicate: first time bilirubine>=33 occurs at time <= 48h after ICU admission\n"
    "variable: bilirubine (umol/L)\n"
    "reference: Jager et al. Front Med 2022\n"
    "also: age >= 18 and ICU stay > 0.5 h\n"
    "model: drop inclusion feature bilirubine\n"
    "databases: amsterdam, mimic4, eicu, hirid\n",
    encoding="utf-8",
)
print(out)
print(df.groupby("source_dataset").agg(stays=("patient", "size"), persons=("uniquepid", "nunique")))
print("persons total", df["uniquepid"].nunique())
