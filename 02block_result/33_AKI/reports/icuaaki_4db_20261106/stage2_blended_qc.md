# ICUAKI_4DB Stage2 QC (after BlendedICU)

- blended out: `/mnt/sda/BlendedICU/data/icuaaki_4db_20261106/blendedlos_icuaaki`
- verdict: **PASS**

| db | n_labels | n_index | equal | mortality | deaths | leaked Cr/UO |
|---|---:|---:|---|---:|---:|---|
| amsterdam | 4002 | 4002 | True | 0.2754 | 1102 | [] |
| mimic4 | 29602 | 29602 | True | 0.1967 | 5822 | [] |
| eicu | 29544 | 29544 | True | 0.1331 | 3932 | [] |
| hirid | 2198 | 2198 | True | 0.1711 | 376 | [] |

## train_on_amsterdam_mimic4 fold x db
```json
{
  "train": {
    "mimic4": 20800,
    "amsterdam": 2804
  },
  "val": {
    "mimic4": 4420,
    "amsterdam": 596
  },
  "test": {
    "eicu": 29544,
    "mimic4": 4382,
    "hirid": 2198,
    "amsterdam": 602
  }
}
```

## Stage2 = PASS
- PASS gate: labels==index per db; no creatinine/urine_output in hourly; n>0.