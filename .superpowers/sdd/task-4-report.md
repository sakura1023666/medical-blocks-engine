# Task 4 Report: 模板 + 项目 config + runner（PE×alteplase IPW）

**Status:** `DONE`  
**Date:** 2026-10-09  
**Commits:** none（按要求未 git commit）  
**Full pipeline:** 未跑（Task 5+）

## Summary

已落盘双库 IPW 模板、batch/worker、MIMIC/eICU 项目 config；`pipeline_unit` 用 `ipw_alteplase_exposure`；暴露/标签/28d/age65/`disease_vars` 均按锁定决策；`--dry-run` 双库通过且宽表 `exists=TRUE`。

## Deliverables

| 产物 | 路径 |
|------|------|
| 模板 | `configs/templates/config_ipw_pe_alteplase_dual_batch.template.R` |
| Batch | `run/ipw_pe_alteplase/run_ipw_pe_alteplase_batch.R`（含 `--dry-run`） |
| Worker | `run/ipw_pe_alteplase/run_ipw_pe_alteplase_batch_worker.R` |
| MIMIC config | `G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/config_ipw_pe_alteplase_MIMIC.R` |
| eICU config | `…/config_ipw_pe_alteplase_eICU.R` |

## Locked decisions reflected

| 项 | 落地 |
|----|------|
| 暴露 MAIN | `Alteplase` + `prefer_precomputed=TRUE`（宽表处方-only：MIMIC 425 / eICU 70） |
| SA union | 未进默认 pipeline；`Alteplase_union` 仅排除出 UV/VIF |
| Block | `ipw_alteplase_exposure`（非 diabetes） |
| Labels | Diabetes→Alteplase（iptw / KM / STEPP / cox / shim `ipw_diabetes`） |
| Survival | 28d；`surv_time_28d` / `surv_event_28d` |
| age_cutoff | `65L`（注释：成人 ICU PE 默认 65） |
| disease_vars | `c("Ddimer","Fibrinogen","TT")`；`allow_no_index=TRUE` |
| index | `enable=FALSE`；STEPP `composite_risk` |
| 双库 | 分 config；shared ck 分 `checkpoints/_shared/{MIMIC,eICU}` |
| eICU id | `id_column="ID"`（= patientunitstayid） |
| STEPP eICU | window 400 / step 100（暴露稀） |

## Dry-run

```text
MIMIC: rawdata G:/…/D01_analysis_MIMIC.RData exists=TRUE
       shared = data_clean, column_mapping
       unit[2] = ipw_alteplase_exposure；iptw exposure_var=Alteplase
eICU:  rawdata G:/…/D01_analysis_eICU.RData exists=TRUE；同上
exit 0
```

路径解析：项目 config 用 `file.exists(宽表)` 探针优先 `G:/`（避免 Windows R 下 `G:` 与 `/mnt/g` 同时 `dir.exists` 却选错）。

## Notes for Task 5

1. flowchart 块名仍为 `ipw_diabetes_flowchart`（决策树保留）；已 shim `ipw_diabetes$exposure_var=Alteplase` + PE `cohort_label`。  
2. eICU ~17 例 `surv_event_28d=NA` → 完整病例剔除由 flowchart/下游处理。  
3. 勿开 full `--shared-only` / workers，直至 Task 5 授权。
