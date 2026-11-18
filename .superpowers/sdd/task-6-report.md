# Task 6 Report — eICU shared + unit 全链（PE × alteplase IPW）

**Status:** DONE  
**Date:** 2026-10-10  
**Unit:** `by_unit/【success】eICU`（**未**写入 `main` / `【success】main`）  
**Exposure MAIN:** 仅处方（Alteplase n1=70；events=175；分析集 n≈1704）

## Safety

| Check | Result |
|-------|--------|
| MIMIC `by_unit/【success】main` polluted? | **No** — `_batch_status.json` 与跑前快照一致；`db_mode=MIMIC` |
| eICU unit name | `study_batch$units = "eICU"`；命令 `--only-unit eICU` |
| Shared CK isolation | 新增 `shared_ck_base = checkpoints/_shared/eICU`（避免误用 MIMIC `…/_shared/main`） |
| Project `_shared/` | 跑前备份 → `_shared_MIMIC_bak`（shared 输出目录仍共用 `_shared/`） |

## Pipeline

1. 恢复丢失的 `run/ipw_pe_alteplase/{batch,worker,repair_*}.R`（自 Task4/5 transcript）
2. `--shared-only --no-skip` → ck：`checkpoints/_shared/eICU`
3. `--only-unit eICU --workers 1 --no-skip` → `by_unit/eICU` → rename `【success】eICU`（elapsed≈164s）
4. `repair_eicu_pub_keys_jin_order.R`：编号/Diabetes 文案/Jin 表集/四目录；STEPP image_information 加 window note
5. 四目录：`pub_figure_formats_status` → **ok=TRUE**（10 stems）

## 约定清单（对齐 Jin + MIMIC）

### Figures（全部 OK）

| 键 | 文件 |
|----|------|
| Fig1 | Flowchart … IPW alteplase cohort |
| Fig2 | IPW-weighted KM … by Alteplase |
| Fig3 | Subgroup analysis … IPTW-adjusted |
| Fig4 | Forest Plot + Subgroup KM by age（两张同号） |
| Fig5 | STEPP … Alteplase across composite risk（**保留键**；window=400/step=100，未再下调） |
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

1. Auto 编号曾把年龄 KM→Fig5、STEPP→Fig6；已按 step 源图恢复（与 MIMIC Task5 同型）。
2. Repair v1 曾「先 unlink unit Tables 再 copy」导致 Jin 五表 MISSING；已改「只从 step* 取源 → copy → 再清残留」；MIMIC repair 同步修。
3. STEPP 在 n_exposed=70 下已出图，未触发失败；脚注写入 Fig5 `image_information`。
4. Task 7 remirror / 双栏拼图：**未做**（按 brief 优先收口 eICU keys）。
5. `run/ipw_pe_alteplase/` 曾一度缺失；现已恢复。建议后续勿删该目录。

## Paths

- Success eICU: `/mnt/g/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/by_unit/【success】eICU/`
- Success MIMIC (untouched): `…/by_unit/【success】main/`
- Repair: `run/ipw_pe_alteplase/repair_eicu_pub_keys_jin_order.R`
- Logs: `…/logs/task6_eicu_shared_*.log`, `task6_eicu_unit_*.log`, `repair_eicu_pub_keys_v2.log`
