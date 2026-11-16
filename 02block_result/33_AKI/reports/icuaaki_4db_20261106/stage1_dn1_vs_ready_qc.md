# ICUAKI_4DB Stage1 QC

- source: `/home/ps/01ResearchPipeline/纳排取数/多数据库融合/ICUAKI_4DB_20261106`
- ready: `/mnt/sda/BlendedICU/data/blendedlos_ready`
- verdict: **PASS** (threshold match_rate >= 0.95)

| db | file_rows | DN1 | id_col | matched | missing | match_rate | mortality | deaths |
|---|---:|---:|---|---:|---:|---:|---:|---:|
| mimic4 | 89577 | 29605 | stay_id | 29605 | 0 | 100.0% | 0.1967 | 5823 |
| eicu | 188866 | 29579 | patientunitstayid | 29576 | 3 | 100.0% | 0.1329 | 3932 |
| hirid | 33894 | 2259 | patientid | 2198 | 61 | 97.3% | 0.1711 | 376 |
| amsterdam | 23086 | 4006 | admissionid | 4006 | 0 | 100.0% | 0.2753 | 1103 |

## Notes
1. sample CSV filename uses DN1 N, but file is full base pool; filter DN==1.
2. mortality from BlendedICU ready labels (extract has no death).
3. wrote cohort_source/dn1_ids_*.csv for Blended filter.
4. Blended must DROP creatinine + urine_output (inclusion leakage).

## Stage1 = PASS