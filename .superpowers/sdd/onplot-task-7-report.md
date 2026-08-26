# Task 7 Report: KM 落盘 `logrank_p`

## Status
**DONE**

## Changes

### `Blocks/27_KM/01block_km_binary.R`
- 出图前用与绘图相同的 `Surv(time, event) ~ Group` 公式计算 log-rank P（`survdiff` + `pchisq`）。
- `ctx$results$km_binary` 新增 `logrank_p`（numeric；失败为 `NA_real_`）。

### `Blocks/27_KM/02block_km_strata.R`
- 新增 `.kms02_logrank_p_numeric(formula, data)` 返回 0–1 数值 P。
- `.kms02_safe_logrank_p` 改为调用 numeric 伴侣再格式化（图面 P 与落盘同源）。
- 每张成功保存的单图写入 `logrank_by_strata[[strata_col]]`（named numeric list）。
- `ctx$results$km_strata` 增 `logrank_by_strata`。

### `tests/test_pub_figure_onplot_annotations.R`
- 增 strata KM annotation 断言（`RAR_quartile`, P=0.015）。
- harvest fixture 增 `eICU/km_strata.rds`，断言 `hf$km` 含 strata 条目。

## Tests
```bash
Rscript tests/test_pub_figure_onplot_annotations.R
# test_pub_figure_onplot_annotations: OK
```

## Commits
None（按约束未提交）。

## Concerns
- `km_binary` 与 `km_strata` 各有一份 log-rank 计算路径（binary 内联、strata 经 `.kms02_logrank_p_numeric`）；公式均与各自绘图分组列一致，harvest 已能读 numeric P。
- 仅成功落盘的 strata 图写入 `logrank_by_strata`；跳过/失败分层无条目。
