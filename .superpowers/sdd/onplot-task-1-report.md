# Task 1 Report: P 值格式化 + RCS/KM annotation 行 helper

## Status

**DONE_WITH_CONCERNS**

## Summary

按 TDD 新增 `tests/test_pub_figure_onplot_annotations.R`，并在 `R/pub_figure_export.R` 的 `pub_figure_harvest_findings` 之前加入四个 internal helper：

- `.pub_figure_fmt_p_label`
- `.pub_figure_rcs_annotation_lines`
- `.pub_figure_km_annotation_lines`
- `.pub_figure_forest_annotation_lines`

未改动 `pub_figure_harvest_findings`、`.pub_figure_detailed_body` 或任何 Block / cursor rule。未执行 git commit（工作区非 git 仓库）。

## Files Changed

| File | Action |
|------|--------|
| `tests/test_pub_figure_onplot_annotations.R` | Created |
| `R/pub_figure_export.R` | Modified（L279–373 新增 helpers） |

## TDD Evidence

### Step 1 — 写失败测试

创建 `tests/test_pub_figure_onplot_annotations.R`（内容与 brief Step 1 一致）。

### Step 2 — RED（函数不存在）

```bash
Rscript /mnt/e/01block/01Block-new-Final/tests/test_pub_figure_onplot_annotations.R
```

```
Error: exists(".pub_figure_fmt_p_label", mode = "function") is not TRUE
Execution halted
```

### Step 3 — 实现 helpers

在 `R/pub_figure_export.R` L279（`.pub_figure_cutoff_clause` 之后、`pub_figure_harvest_findings` 之前）插入四个函数。

### Step 3b — 首次 GREEN 尝试失败（brief 与测试不一致）

verbatim brief 中 forest 分支使用 `signif(est, 4)`，对 `1.20` 输出为 `"1.2"`，不满足测试 `grepl("1\\.20", fo_lines)`：

```bash
Rscript /mnt/e/01block/01Block-new-Final/tests/test_pub_figure_onplot_annotations.R
```

```
Error: any(grepl("1\\.20", fo_lines)) is not TRUE
Execution halted
```

调试输出：

```
#### eICU

- Overall：1.2 (95%CI 1.01–1.42)
- Age < 65：1.1 (95%CI 0.9–1.35)；P for interaction = 0.040
- Age ≥ 65：1.35 (95%CI 1.05–1.74)
```

**最小修正**：forest CI 行的点估计改用 `formatC(est, digits = 2, format = "f")` 以保留 `"1.20"` 格式；lo/hi 仍用 `signif(..., 4)`。

### Step 4 — GREEN

```bash
Rscript /mnt/e/01block/01Block-new-Final/tests/test_pub_figure_onplot_annotations.R
```

```
test_pub_figure_onplot_annotations: OK
```

### 回归冒烟

```bash
Rscript /mnt/e/01block/01Block-new-Final/tests/test_pub_figure_export.R
```

```
test_pub_figure_export: OK
```

## Self-Review

| 检查项 | 结果 |
|--------|------|
| helpers 位于 `pub_figure_harvest_findings` 之前 | ✓ L279–373 |
| 未改 harvest / detailed_body | ✓ |
| 未改 blocks / cursor rule | ✓ |
| TDD RED → GREEN | ✓ |
| 测试全通过 | ✓ |
| git commit | 跳过（非 git 仓库） |

## Concerns

1. **Brief 与测试不一致**：brief Step 3 的 forest 实现用 `signif(est, 4)`，但 Step 1 测试期望输出含 `"1.20"`。已用 `formatC(est, digits=2, format="f")` 仅于带 CI 的点估计分支做最小偏离；后续 Task 若统一 brief 应同步修正。

2. **尚未接入 harvest**：本 Task 仅提供格式化 helper；RCS/KM/forest 的 findings 收获与 `image_information` 正文写入留待后续 Task。

## Commits

none（skipped — workspace 非 git repo）
