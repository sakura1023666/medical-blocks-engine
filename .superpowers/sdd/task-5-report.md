# Task 5 Report — MIMIC shared + unit 全链（PE × alteplase IPW）

**Status:** DONE  
**Date:** 2026-10-10  
**Unit:** `by_unit/【success】main`  
**Exposure MAIN:** 仅处方（Alteplase n1=425/1621）

## Pipeline

- shared + `--only-unit main --no-skip` 已完成（进程已退出）
- 后处理：`repair_mimic_pub_keys_jin_order.R` + 手工补拷 Jin 五表；`export_missing_fig=TRUE` 已写入 MIMIC/eICU config
- 四目录：`pub_figure_formats_status` → **ok=TRUE**（10 stems，png/tiff 无缺）

## 约定清单（对齐 Jin + 卒中）

### Figures（全部 OK）

| 键 | 文件 |
|----|------|
| Fig1 | Flowchart … IPW alteplase cohort |
| Fig2 | IPW-weighted KM … by Alteplase |
| Fig3 | Subgroup analysis … IPTW-adjusted |
| Fig4 | Forest Plot + Subgroup KM by age（两张同号，对齐卒中） |
| Fig5 | STEPP … Alteplase across composite risk |
| S1 | Missing value overview |
| S2 | PS + SMD |
| S3 | Unweighted KM … by Alteplase |
| S4 | Calibration + ROC @28d |

### Tables（全部 OK）

| 键 | 文件 |
|----|------|
| Table 1 | sIPTW 基线 |
| Table S1 | Uno C-index @28d |
| Table S2 | 多重插补前后基线 |
| Table S3 | 单因素 |
| Table S4 | VIF |
| Sens | Multivariable Cox；Overlap Weights |

## Concerns / follow-ups

1. 曾因 `export_missing_fig` 默认 FALSE 未出 S1，已补图并改 config。  
2. 自动编号曾把 STEPP 挤成 Fig6、S1 错位；已按 step 源图恢复。  
3. eICU（Task 6）尚未跑。

## Paths

- Success: `/mnt/g/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/by_unit/【success】main/`
- Root Tables mirror: `…/Medication_regimen_model_alteplase_ipw/Tables/`
