# Task 2 Report: 数据组装 + 暴露核对 + 列审阅

**Status:** `DONE_WITH_CONCERNS`  
**Date:** 2026-10-09  
**Commits:** none  
**Project root:** `/mnt/g/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/`

## Summary

PE 双库分析宽表已组装；暴露并集与先验粗算完全一致（MIMIC 428/1621，eICU 109/1721）；列审阅与 `disease_vars` 草案已落盘。MIMIC 输液列名 `dexmedetomidine` 与文件名「阿替普酶」冲突，但剂量/单位/与处方重叠支持按阿替普酶纳入并集——需用户或 itemid 再确认。

## Deliverables

| 产物 | 路径 |
|------|------|
| 目录 | `data/` `reports/` `Data/` `logs/` |
| 暴露报告 | `reports/exposure_definition_2026-10-09.md` |
| MIMIC 宽表 | `data/D01_analysis_MIMIC.RData`（对象 `baseline`，n=1621） |
| eICU 宽表 | `data/D01_analysis_eICU.RData`（对象 `baseline`，n=1721） |
| 列审阅 | `Data/_column_review.md` + `_column_review_raw_*.txt` |
| 组装脚本 | `scripts/assemble_pe_alteplase_analysis.R` |
| 审计 RDS | `logs/assemble_audit.rds` |

未写 IPW config（Task 4）；未跑 full IPW pipeline。

## Exposure (verified)

| DB | n | rx+ | iv+ | union Alteplase=1 | rate |
|----|---|-----|-----|-------------------|------|
| MIMIC | 1621 | 425 (`ymtmd`) | 73 (col=`dexmedetomidine`) | **428** | 26.4% |
| eICU | 1721 | 70 (`gy`) | 41 (`sy`) | **109** | 6.3% |

- 规则：`Alteplase = (rx OR iv)`，已写入宽表。  
- eICU `sy_drugname` 全部为 Alteplase* → **已确认**。  
- MIMIC iv：文件名阿替普酶；列名右美；单位 **mg**、剂量中位 ~30 mg、70/73 与 `ymtmd` 重叠 → **按阿替普酶纳入**，标 CONCERN。

## Outcome

- MIMIC：预后 CSV 合并；`surv_time_28d` / `surv_event_28d`（事件 336；时间 NA=0）。  
- eICU：由 `hospdischargestatus`+`hosplosday` 衍生（事件 175；**17** 例状态空白 → 事件 NA）。

## Column review / disease_vars draft

```r
.disease_exclusion_vars <- c("Ddimer", "Fibrinogen", "TT")
# protect_vars = c("Alteplase", "surv_time_28d", "surv_event_28d", "composite_risk")
```

Troponin/BNP、SOFA/APSIII 等保留作溶栓混杂候选。年龄切点建议默认 **65**。

## Acceptance (Step 5)

```text
MIMIC: Alteplase ∈ {0,1} PASS; surv_time_28d + surv_event_28d PASS
eICU:  Alteplase ∈ {0,1} PASS; surv_time_28d + surv_event_28d PASS
union vs prior: MIMIC 0% / eICU 0% deviation
```

## Concerns / questions for user

1. **MIMIC 输液列**：是否接受并集主分析，并加「仅 `ymtmd`」敏感性？能否用 inputevents itemid 终审？  
2. **eICU 17** 例出院状态缺失：Task 4 剔除还是完整病例门控？  
3. **disease_vars** 是否确认 `Ddimer`+`Fibrinogen`+`TT`？  
4. 年龄切点是否锁定 65？

## Test summary

- `assemble_pe_alteplase_analysis.R` exit 0  
- stopifnot Alteplase 0/1 + surv cols：双库通过  
- 暴露并集 = 先验 428 / 109  
