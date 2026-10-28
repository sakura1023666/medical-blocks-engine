"""Freeze ACG enzyme >=2xULN stays (first ALT or AST >=80 U/L; ULN=40).

Kwo et al. Am J Gastroenterol 2017. Matches reports/liver_rule_patients_pivot.csv
rule acg_enzyme_ge2uln (pivot counts are persons; this freezes stays).
"""
import duckdb
from pathlib import Path

out = Path("/mnt/sda/BlendedICU/data/liver_dysfunction_acg_42151996")
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
ast AS (
  SELECT patient, arg_min(value, time) AS first_ast
  FROM read_parquet([{file_sql}])
  WHERE variable = 'aspartate_aminotransferase' AND time >= 0 AND value > 0
  GROUP BY patient
),
enz AS (
  SELECT COALESCE(a.patient, s.patient) AS patient,
         a.first_alt, s.first_ast
  FROM alt a
  FULL OUTER JOIN ast s ON a.patient = s.patient
)
SELECT l.source_dataset, l.patient, l.uniquepid, l.original_uniquepid,
       l.raw_age, l.true_lengthofstay, l.mortality,
       e.first_alt, e.first_ast
FROM read_parquet('{lab}') l
JOIN enz e ON l.patient = e.patient
WHERE l.raw_age >= 18
  AND l.true_lengthofstay > 0.5/24.0
  AND (e.first_alt IS NOT NULL OR e.first_ast IS NOT NULL)
  AND ((e.first_alt >= 80) OR (e.first_ast >= 80))
ORDER BY l.source_dataset, l.patient
"""
c = duckdb.connect()
df = c.execute(q).fetchdf()
df.to_parquet(out / "eligible_stays.parquet", index=False)
(out / "RULE.txt").write_text(
    "rule: ACG-style enzyme elevation: first ALT or AST >= 2xULN\n"
    "ULN: 40 U/L (operationalized); cutoff ALT>=80 or AST>=80\n"
    "variables: alanine_aminotransferase, aspartate_aminotransferase\n"
    "reference: Kwo et al. Am J Gastroenterol 2017\n"
    "also: age >= 18 and ICU stay > 0.5 h\n"
    "missing ALT and AST: excluded, not imputed\n"
    "model: drop inclusion features alanine_aminotransferase,aspartate_aminotransferase\n"
    "databases: amsterdam, mimic4, eicu, hirid\n",
    encoding="utf-8",
)
print(out)
print("stays:")
print(df.groupby("source_dataset").agg(stays=("patient", "size"), persons=("uniquepid", "nunique"), deaths=("mortality", "sum")))
print("persons total", df["uniquepid"].nunique())
