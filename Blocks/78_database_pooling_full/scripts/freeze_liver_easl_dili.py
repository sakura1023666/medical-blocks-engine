"""Freeze EASL/DILI lab-gate stays: first ALT>=200 or first ALP>=230.

EASL CPG 2019; International DILI Expert Working Group (ULN ALT40/ALP115).
Pivot persons: 1223 / 5980 / 7978 / 2060 (amsterdam/mimic4/eicu/hirid).
"""
import duckdb
from pathlib import Path

out = Path("/mnt/sda/BlendedICU/data/liver_dysfunction_easl_dili_42151996")
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
WITH alt AS (
  SELECT patient, arg_min(value, time) AS first_alt
  FROM read_parquet([{file_sql}])
  WHERE variable = 'alanine_aminotransferase' AND time >= 0 AND value > 0
  GROUP BY patient
),
alp AS (
  SELECT patient, arg_min(value, time) AS first_alp
  FROM read_parquet([{file_sql}])
  WHERE variable = 'alkaline_phosphatase' AND time >= 0 AND value > 0
  GROUP BY patient
),
enz AS (
  SELECT COALESCE(a.patient, p.patient) AS patient, a.first_alt, p.first_alp
  FROM alt a
  FULL OUTER JOIN alp p ON a.patient = p.patient
)
SELECT l.source_dataset, l.patient, l.uniquepid, l.original_uniquepid,
       l.raw_age, l.true_lengthofstay, l.mortality,
       e.first_alt, e.first_alp
FROM read_parquet('{lab}') l
JOIN enz e ON l.patient = e.patient
WHERE l.raw_age >= 18
  AND l.true_lengthofstay > 0.5/24.0
  AND ((e.first_alt >= 200) OR (e.first_alp >= 230))
ORDER BY l.source_dataset, l.patient
"""
c = duckdb.connect()
df = c.execute(q).fetchdf()
df.to_parquet(out / "eligible_stays.parquet", index=False)
(out / "RULE.txt").write_text(
    "rule: EASL/DILI lab gate: first ALT >=5xULN OR ALP >=2xULN\n"
    "ULN: ALT 40 U/L, ALP 115 U/L; cutoff ALT>=200 or ALP>=230\n"
    "variables: alanine_aminotransferase, alkaline_phosphatase\n"
    "reference: EASL CPG Drug-induced liver injury 2019; International DILI Expert Working Group\n"
    "also: age >= 18 and ICU stay > 0.5 h\n"
    "model: drop inclusion features alanine_aminotransferase,alkaline_phosphatase\n"
    "databases: amsterdam, mimic4, eicu, hirid\n",
    encoding="utf-8",
)
print(out)
print(df.groupby("source_dataset").agg(stays=("patient", "size"), persons=("uniquepid", "nunique")))
print("persons total", df["uniquepid"].nunique())
