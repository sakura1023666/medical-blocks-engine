# Task 2 Report — config_incidence_single.R

**Status:** DONE  
**Commits:** none

## Implemented
- `/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/config_incidence_single.R`
- Forced `.m1` / `.m2` (老师 Model 3 = Model2，含 Creatinine，无 BUN/ICU)
- `analysis_exclusion` + `disease_vars` from Task 1
- `rcs_incidence$nk_range = 4L`
- Pipeline: attrition_flowchart; subgroup_incidence_continuous（连续 Sodium）
- random_search enable=FALSE；write_model_factors=FALSE

## Tests
`Rscript` dry-source → `OK config`

## Note
亚组块用 `subgroup_incidence_continuous`（计划写 subgroup_incidence；连续暴露更合适）。
