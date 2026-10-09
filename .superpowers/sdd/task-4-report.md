# Task 4 Report — Block `dxa_qct_agreement`

**Date:** 2026-09-22  
**Engine root:** `/mnt/e/01block/01Block-new-Final`

## Deliverables

| Item | Path |
|------|------|
| Block | `Blocks/75_osteo_dxa_qct/01block_dxa_qct_agreement.R` |
| Tests | `tests/test_osteo_dxa_qct_blocks.R`（保留 `helper OK` + 新增 `agreement OK`） |

## Config（`config$dxa_qct_agreement`）

```r
list(
  enable = TRUE,
  qct_cat = "QCT_cat",
  dxa_cat = "DXA_cat_min",
  qct_continuous = "QCT_vBMD",
  dxa_continuous = "DXA_T_min",
  op_level = 2L,
  bland_zscore = TRUE
)
```

## Produces

- Table「DXA-QCT agreement」（`export_sci_table` / openxlsx / CSV fallback）
- Figure「Figure 3. DXA vs QCT agreement.pdf」（左 2×2 OP 交叉热力；右 Bland–Altman，默认 z 化）
- `ctx$results$dxa_qct_agreement`（含 `n`, `kappa_binary`, `agree_3cat`, `cross_*`, `bland`, paths）

## TDD

### RED（先扩测、未实现 block）

Command:

```bash
cd /mnt/e/01block/01Block-new-Final && Rscript tests/test_osteo_dxa_qct_blocks.R
```

Output:

```
helper OK
Error: file.exists(agree_path) is not TRUE
Execution halted
EXIT:1
```

Cause: `01block_dxa_qct_agreement.R` 尚不存在；测试在 `source` 前 `stopifnot(file.exists(agree_path))`。

### GREEN（实现后）

Command:

```bash
cd /mnt/e/01block/01Block-new-Final && Rscript tests/test_osteo_dxa_qct_blocks.R
```

Output:

```
helper OK
agreement OK
EXIT:0
```

## Mini-data assertions

6 行合成数据：`QCT_cat`/`DXA_cat_min`/`QCT_vBMD`/`DXA_T_min`。

| Check | Expected |
|-------|----------|
| `comp$n` | 6 |
| binary OP κ (`op_level=2`) | 1（QCT/DXA OP 向量完全一致） |
| `n_kappa` | 6 |
| 三分类一致率 | 5/6（第 4 行 0 vs 1） |
| `block_dxa_qct_agreement(ctx)` | 填充 `ctx$results$dxa_qct_agreement` |

Internal API：`.dqa75_compute(data, cfg)`。

## Git / pipeline

- **No git commit**（按任务要求）
- **No full pipeline run**；未强制读真实 dabiao

## Next

Task 5: `02block_diagnostic_vs_fracture.R`；catalog 同步见后续 Task。
