# Task 3 Report: Harvest 从 checkpoint 收取 rcs / km / forest

**Date:** 2026-08-26  
**Scope:** Extend `pub_figure_harvest_findings()` to fill `out$rcs` / `out$km` / `out$forest` from `index_root/<DB>/*.rds` (`obj$ctx$results` or `obj$results`).  
**Out of scope:** writing `panel_stats` into Blocks (Tasks 4–7), git commits.

---

## Status

**DONE_WITH_CONCERNS**

## Summary

按 TDD 先追加 harvest fixture 测试（确认 RED：`length(hf$rcs) >= 1L`），再扩展 `pub_figure_harvest_findings`：在既有 `db_dirs` 循环中扫描各库 `*.rds`（文件名含 `rcs`/`km`/`subgroup` 优先），从 `rcs_*_panel_stats`、`km_binary` / `km_strata$logrank_by_strata`、`subgroup` 数据框规范出与 Task 1 helpers 一致的结构。无 `panel_stats` 时不合成假 P。未改 Blocks，未执行 git commit。

---

## Files Changed

| File | Action |
|------|--------|
| `tests/test_pub_figure_onplot_annotations.R` | 追加 MIMIC tempfile fixture + 无 panel_stats 锁 |
| `R/pub_figure_export.R` | `pub_figure_harvest_findings` 扩展；新增 `.pub_figure_harvest_normalize_rcs` / `.pub_figure_harvest_km_items` |

---

## TDD Evidence

### Step 1 — 写失败测试

在 `tests/test_pub_figure_onplot_annotations.R` 末尾（`cat("…OK")` 之前）追加 brief 指定 fixture：

- `ix_root/MIMIC/rcs_prognosis.rds`：`results$rcs_prognosis_panel_stats$Model2`（`p_overall=0.001`）
- `ix_root/MIMIC/km_binary.rds`：`km_binary`（`logrank_p=0.023`, `cutoff=1.25`）+ `subgroup` 数据框
- 断言：`length(hf$rcs|km|forest) >= 1`，且 RCS 某 panel 的 `p_overall` 为 `0.001`

另加锁测试：仅有 `rcs_prognosis` 而无 `*_panel_stats` 时 `length(hf$rcs)==0`。

### Step 2 — RED（harvest 尚未填槽）

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript tests/test_pub_figure_onplot_annotations.R
```

```
Error: length(hf$rcs) >= 1L is not TRUE
Execution halted
```

失败点正是缺失功能（`out` 无 `rcs`），不是语法/路径笔误。此时尚未改 `pub_figure_harvest_findings` 生产逻辑。

### Step 3 — 实现 harvest

1. `out` 初始化增加 `rcs`、`km`、`forest`。
2. 在既有 `db_dirs` 循环中：`list.files(dd, pattern="\\.rds$")`，文件名含 `rcs|km|subgroup` 前置。
3. `res <- obj$ctx$results %||% obj$results %||% list()`。
4. **RCS：** 只读 `rcs_prognosis_panel_stats` / `rcs_incidence_panel_stats` / `rcs_nhanes_panel_stats` / `rcs_iptw_panel_stats`，规范为  
   `list(db, panels=list(list(name, p_overall, p_nonlinear, cutoffs)))`。  
   无上述键 → 不收获、不编造 P。
5. **KM：** `res$km_binary` → `logrank_p`/`cutoff`；`res$km_strata$logrank_by_strata`（named numeric 或 list）→ 多条带 `strata`。
6. **Forest：** `is.data.frame(res$subgroup) && nrow>0` → `list(db, rows=...)`。
7. 同库去重：RCS / forest / km_binary 各保留首次完整命中；km_strata 按 `(db, strata)` 去重。

### Step 4 — GREEN

```bash
Rscript tests/test_pub_figure_onplot_annotations.R
# test_pub_figure_onplot_annotations: OK

Rscript tests/test_pub_figure_export.R
# test_pub_figure_export: OK
```

两文件均 exit 0。既有 Task 1 helpers 与 Task 2 「图上标注」断言仍通过。

### Extra check（非测试文件）

`obj$ctx$results` 路径 + `rcs_incidence_panel_stats` + named-numeric `logrank_by_strata` + 第二份 rds 去重：RCS 保留首次 `p_overall=0.02`（不吃后来的 `0.999`）；KM 同时收下 strata 两条 + 后到的 `km_binary`。

---

## Constraints Verified

- [x] 无 git commit
- [x] TDD：fixture → RED → harvest → GREEN
- [x] 未向 Blocks 写入 `panel_stats`（Tasks 4–7）
- [x] 无 panel_stats 时不合成假 P（`hf_miss$rcs` 长度为 0）
- [x] 标签仍为 `P-overall` / `P-non-linear`（helpers 未改）

---

## Concerns / Follow-ups

1. **生产空槽直到 Tasks 4–7：** 现网 `km_binary` 只写 `cutoff`（无 `logrank_p`）；RCS Block 尚未写 `*_panel_stats`。harvest 对真实 checkpoint 的 RCS 仍会空，md 走 Task 2「未收获」。Forest 已可从现有 `res$subgroup` 收获。KM 现在最多能收到 cutoff。
2. **`db_dirs` 仍硬编码** eICU/MIMIC + checkpoints 的 nhanes/mimic，不含 `index_root/NHANES` 或 CHARLS/ELSA/HRS。brief 要求挂在既有循环，未扩名单。
3. **扫全库 `*.rds`：** 大 checkpoint 可能偏慢/占内存；`tryCatch(readRDS)` 可跳过坏文件。ROC/maxstat 仍按原路径再读一次，结果不冲突。
4. **RCS 多键同文件：** 同一 `res` 若同时有 prognosis 与 incidence panel_stats，只取键表中第一个非空（prognosis 优先）。

---

## Commits

None (per task constraint).
