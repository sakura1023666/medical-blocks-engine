# Task 6 Report — Block `modality_discordance_profile`

**Date:** 2026-09-22  
**Engine root:** `/mnt/e/01block/01Block-new-Final`

## Deliverables

| Item | Path |
|------|------|
| Block | `Blocks/75_osteo_dxa_qct/03block_modality_discordance_profile.R` |
| Tests | `tests/test_osteo_dxa_qct_blocks.R`（保留 `helper OK` / `agreement OK` / `diagnostic OK` + 新增 `discordance OK`） |

## Config（`config$modality_discordance_profile`）

```r
list(
  enable = TRUE,
  group_var = "discordance_group",
  exclude_vars = c("SampleID"),
  include_vars = NULL,          # 非空则只保留所列协变量
  fracture = "Vertebral_fracture",
  add_p = TRUE
)
```

## Produces

- **Table S5. Baseline by discordance group**（xlsx；CSV fallback）
- 连续变量 mean±SD；分类 n(%)；优先 `gtsummary::tbl_summary(by=discordance_group)`，否则手写汇总
- 脚注含：总 N、各组 n 之和、**QCT_only_OP n**、**QCT_only fracture events**
- `ctx$results$modality_discordance_profile`（含 `n` / `n_by_group` / `n_qct_only` / `n_qct_only_fracture` / `table` / paths）

默认排除：SampleID、group_var、QCT/DXA OP 与 cat/连续影像列（定义分组）、`Disease`/`Fracture_f`；有 `Nathan_bin` 时去掉原始 `Nathan`。

## TDD

### RED（先扩测、未实现 block）

```
helper OK
agreement OK
diagnostic OK
Error: file.exists(disc_path) is not TRUE
```

### GREEN（实现后）

```bash
cd /mnt/e/01block/01Block-new-Final && Rscript tests/test_osteo_dxa_qct_blocks.R
```

```
helper OK
agreement OK
diagnostic OK
discordance OK
EXIT:0
```

## Real dabiao assertions

路径：`/mnt/g/02block_result/10_osteoporosis/personalized/data/harmonized/D01_osteo_personalized.RData`

- 四组齐全：Both_OP / QCT_only_OP / DXA_only_OP / Neither_OP
- `QCT_only_OP == 40`；`nrow == 208`；`sum(n_by_group) == 208`
- `n_qct_only_fracture` 与 `sum(Vertebral_fracture[QCT_only_OP]==1)` 一致（本库 = 25）

Internal API：`.mdp75_compute(data, cfg)`。

## Git / pipeline

- **No git commit**（按任务要求）
- **No full pipeline run**
- Catalog / `pipeline_block_sources` 同步留给后续任务（同 Task 4/5）

## Next

后续课题 config 挂 `modality_discordance_profile`；catalog 登记留给 Task 7（若计划如此）。
