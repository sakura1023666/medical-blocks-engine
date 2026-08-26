# Task 1 Report — 列审阅 + Prep dabiao

**Status:** DONE  
**Commits:** none (no git / plan skip)

## Implemented
- `_column_review_raw.txt` — 84 列名
- `_column_review.md` — 逐列保留/排除 + disease_vars 建议
- `prep_vitaldb_sodium.R` + `D01_dabiao_VitalDB_sodium.RData`

## Tests
```
nrow=6388 AKI=268
OpDuration_min: min 1.4 median 110
Vasopressor_use: No 2787 / Yes 3601
Disease_Group: No 6120 / AKI 268
```

## disease_vars (for Task 2)
`judge, IntraopUO, icu_days, ICU_Days, death_inhosp, Death_Inhosp, UreaNitrogen, GFR, CreatinineClearance`  
Creatinine 不进 disease_vars（老师强制 Model 2）。

## Concerns
无。
