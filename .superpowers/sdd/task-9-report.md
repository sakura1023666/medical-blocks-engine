# Task 9 Report — Table2 Panel 合并脚本

**Status:** Complete  
**Date:** 2026-09-22  
**Commits:** none

## Deliverables

| Path | Note |
|------|------|
| `/mnt/g/02block_result/10_osteoporosis/personalized/scripts/merge_table2_dual_bmd_panels.R` | QCT/DXA Panel 合并 CLI |
| `scripts/_smoke/table2_panels/Table 2. Dual BMD panels (smoke).xlsx` | 冒烟产物（7171 bytes） |

## Script 行为

- **输入：** `--panel-a` / `--panel-b`（csv/xlsx）；缺省时在 `by_index/QCT_vBMD`、`by_index/DXA_T_min` 下搜 `Table*2*`
- **输出：** 单一 Table 2 workbook；`Panel A: QCT-vBMD` + `Panel B: DXA T-score` 行标签
- **脚注：** 两套 n（`--n-a`/`--n-b`）+ 协变量锁 `Age, BMI, bCTX, P1NP, VitD_25OH, PTH`（两轴互不进对方 Model）
- **写出：** `openxlsx`（引擎 `sci_xlsx_single_header_booktabs` 已加载时可走三线表）；无 openxlsx 则 CSV fallback
- **`--smoke`：** 写两张合成 Panel CSV 并合并

## Smoke

```bash
Rscript scripts/merge_table2_dual_bmd_panels.R --smoke
# OK: wrote .../Table 2. Dual BMD panels (smoke).xlsx (7171 bytes); rows=16 cols=3
```

合成路径：`scripts/_smoke/table2_panels/Table2_panel_{A_QCT,B_DXA}_synthetic.csv`

## 未做

- 全 pipeline / 真实 Table2（`by_index` 尚无 MV 表；待 Task 10 授权后跑）
- git commit
