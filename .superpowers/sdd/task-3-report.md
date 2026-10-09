# Task 3 Report: 暴露 Block + 注册 + 决策树（PE×alteplase IPW）

**Status:** `DONE`  
**Date:** 2026-10-09  
**Commits:** none  

## Summary

新增 `ipw_alteplase_exposure`（默认 `prefer_precomputed=TRUE`：校验宽表 `Alteplase∈{0,1}`，确保 28d 结局列），已挂 `pipeline_runner` 与 Blocks catalog；决策树含 mermaid + 用户确认清单，**未写 Task 4 config**。

## Deliverables

| 产物 | 路径 |
|------|------|
| 暴露块 | `Blocks/69_ipw_diabetes_stroke_full/10block_ipw_alteplase_exposure.R` |
| 注册 | `R/pipeline_runner.R` → `ipw_alteplase_exposure` |
| 决策树 | `Decisiontree/decision_tree_ipw_pe_alteplase.md` |
| Catalog | `python3 scripts/update_blocks_catalog.py` → `docs/Blocks_catalog.md`（含新块） |

未写项目 config / 未开 Task 4。

## Locked decisions reflected

- Foundation: 预后 + IPW；放疗→阿替普酶；OS→28d  
- Exposure MAIN: 处方 OR 输液（precomputed）；可选 rx-only 敏感性记在决策树，默认不开  
- disease_vars 草案: `Ddimer`, `Fibrinogen`, `TT`；protect: Alteplase / surv_* / composite_risk  
- 路径 1 + remirror 双栏；STEPP=`composite_risk`；Fig1–5/S1–S4 + Table1/S1–S4 + Sens 清单齐全  

## Test summary

| Check | Result |
|-------|--------|
| `register_block("ipw_alteplase_exposure")` | OK |
| `pipeline_runner.R` map 含 `ipw_alteplase_exposure` | FOUND |
| `update_blocks_catalog.py` | exit 0；481 blocks |
| Smoke MIMIC baseline | n=1621, n_exposed=428, n_event=336；surv_* OK |
| Smoke eICU baseline | n=1721, n_exposed=109, n_event=175；surv_* OK |

## Gate for Task 4

Controller 须向用户展示 `Decisiontree/decision_tree_ipw_pe_alteplase.md` 的 mermaid + §0 确认清单；**用户确认后**再写项目 config。

## Concerns

1. MIMIC 输液列名 CONCERN（Task 2）仍待用户终审；主分析并集已写入树。  
2. eICU 17 例出院状态缺失 → 事件 NA：完整病例/剔除口径留 Task 4。  
3. 决策树尚未用户签字（本 Task 故意停在确认门控）。  
