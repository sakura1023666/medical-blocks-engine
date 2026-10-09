# Task 5 Report — Block `diagnostic_vs_fracture`

**Date:** 2026-09-22  
**Engine root:** `/mnt/e/01block/01Block-new-Final`

## Deliverables

| Item | Path |
|------|------|
| Block | `Blocks/75_osteo_dxa_qct/02block_diagnostic_vs_fracture.R` |
| Tests | `tests/test_osteo_dxa_qct_blocks.R`（保留 `helper OK` + `agreement OK` + 新增 `diagnostic OK`） |

## Config（`config$diagnostic_vs_fracture`）

```r
list(
  enable = TRUE,
  fracture = "Vertebral_fracture",
  qct_cat = "QCT_cat",
  dxa_cat = "DXA_cat_min",
  qct_continuous = "QCT_vBMD",
  dxa_continuous = "DXA_T_min",
  op_level = 2L,
  strata = c("Nathan_bin", "AAC", "BMI_bin"),
  strata_supplemental = c("Age_bin"),
  export_roc = TRUE,
  export_sens_bar = TRUE,
  roc_direction = ">"   # pROC: controls > cases（BMD/T 越低越病）
)
```

## Produces

- Table 3 overall（Sens/Spec/PPV/NPV/AUC；脚注含 n / n_frac / op_level）
- Table 4 stratified（Nathan_bin / AAC / BMI_bin：n、n_frac、DXA_sens、QCT_sens、Δsens）
- Figure 4 ROC（DXA T-min + QCT vBMD 双曲线）
- Figure 5 分层 Sens 柱图
- 可选 Figure S3（Age_bin）
- `ctx$results$diagnostic_vs_fracture`

## ROC direction note

Brief 写 `direction="<"` 表示「越低越病」；**pROC** 语义下 controls 高于 cases 时须用 `">"`。Block 默认 `roc_direction = ">"`，否则 BMD/T 的 AUC 会倒置（&lt;0.5）。可通过 config 覆盖。

## TDD

### RED（先扩测、未实现 block）

```
helper OK
agreement OK
Error: file.exists(diag_path) is not TRUE
EXIT:1
```

### GREEN（实现后）

```bash
cd /mnt/e/01block/01Block-new-Final && Rscript tests/test_osteo_dxa_qct_blocks.R
```

```
helper OK
agreement OK
diagnostic OK
EXIT:0
```

## Mini-data assertions

8 行合成数据：fracture 4/8；`op_level=2` → QCT/DXA overall sens 均为 0.5；`table3`/`table4` 非空；block 填 `ctx$results$diagnostic_vs_fracture`。

Internal API：`.dvf75_compute(data, cfg)`。

## Git / pipeline

- **No git commit**（按任务要求）
- **No full pipeline run**；未强制读真实 dabiao
- Catalog 同步留给 Task 7

## Next

Task 6: `03block_modality_discordance_profile.R`
