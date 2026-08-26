### Task 7: KM 落盘 `logrank_p`

**Files:**
- Modify: `Blocks/27_KM/01block_km_binary.R`
- Modify: `Blocks/27_KM/02block_km_strata.R`
- Modify: `.pub_figure_km_annotation_lines`（已支持 `strata`，Task 1）

**Interfaces:**
- `km_binary` 增 `logrank_p`
- `km_strata` 增 `logrank_by_strata`（named numeric）

- [ ] **Step 1: `km_binary` 在出图前计算数值 log-rank，写入 results**

```r
.logrank_p <- tryCatch({
  sd <- survival::survdiff(fit_formula, data = data_categorized)
  stats::pchisq(sd$chisq, length(sd$n) - 1L, lower.tail = FALSE)
}, error = function(e) NA_real_)

ctx$results$km_binary <- list(
  index_var = index_var, cutoff = cutoff,
  n = nrow(data_categorized),
  level_low = lvl_lo, level_high = lvl_hi,
  logrank_p = .logrank_p
)
```

公式须与绘图分组列一致。

- [ ] **Step 2: `km_strata` 每张成功图记录数值 P 到 `logrank_by_strata[[strata_col]]`**

Harvest：为每个 strata 推一条 `out$km`（含 `strata`）。

- [ ] **Step 3: 扩展测试一条带 `strata` 的 km finding**

- [ ] **Step 4: Run tests PASS**

- [ ] **Step 5: Commit（仅当用户要求）**

---

