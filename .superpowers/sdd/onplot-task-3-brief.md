### Task 3: Harvest 从 checkpoint 收取 rcs / km / forest

**Files:**
- Modify: `R/pub_figure_export.R` → `pub_figure_harvest_findings`
- Modify: `tests/test_pub_figure_onplot_annotations.R`（增加临时目录 fixture）

**Interfaces:**
- Consumes: index_root 下 `<DB>/` 内 `*.rds`（`obj$ctx$results` 或 `obj$results`）
- Produces: `out$rcs`、`out$km`、`out$forest`，结构与 Task 1 helpers 一致

- [ ] **Step 1: Write harvest fixture test**

```r
# 追加到 tests/test_pub_figure_onplot_annotations.R
ix_root <- tempfile("ix_")
dir.create(file.path(ix_root, "Figures"), recursive = TRUE)
dir.create(file.path(ix_root, "MIMIC"), recursive = TRUE)
saveRDS(
  list(results = list(
    rcs_prognosis_panel_stats = list(
      Model2 = list(p_overall = 0.001, p_nonlinear = 0.116, cutoffs = 0.52)
    )
  )),
  file.path(ix_root, "MIMIC", "rcs_prognosis.rds")
)
saveRDS(
  list(results = list(
    km_binary = list(logrank_p = 0.023, cutoff = 1.25),
    subgroup = data.frame(
      Variable = c("Overall", "Age"), `Point Estimate` = c(1.2, 1.1),
      Lower = c(1.0, 0.8), Upper = c(1.4, 1.5),
      `P for interaction` = c(NA, 0.04), check.names = FALSE
    )
  )),
  file.path(ix_root, "MIMIC", "km_binary.rds")
)

hf <- pub_figure_harvest_findings(file.path(ix_root, "Figures"), meta = list(databases = "MIMIC"))
stopifnot(length(hf$rcs) >= 1L)
stopifnot(any(vapply(hf$rcs[[1]]$panels, function(p) {
  isTRUE(abs((p$p_overall %||% NA_real_) - 0.001) < 1e-9)
}, logical(1))))
stopifnot(length(hf$km) >= 1L)
stopifnot(length(hf$forest) >= 1L)
unlink(ix_root, recursive = TRUE)
```

- [ ] **Step 2: Run — expect FAIL until harvest extended**

- [ ] **Step 3: Implement harvest extensions**

`out` 初始化增加 `rcs`、`km`、`forest`。

在已有 `db_dirs` 循环中，对每个 `dd`：

1. `list.files(dd, pattern = "\\.rds$", full.names = TRUE)`（优先名含 `rcs`/`km`/`subgroup`）。
2. `readRDS` → `res <- obj$ctx$results %||% obj$results %||% list()`。
3. **RCS：** 读 `rcs_prognosis_panel_stats` / `rcs_incidence_panel_stats` / `rcs_nhanes_panel_stats` / `rcs_iptw_panel_stats`，规范为  
   `list(db=db_lab, panels=list(list(name=..., p_overall=..., p_nonlinear=..., cutoffs=...)))`。  
   **锁定：** 无 panel_stats 时不合成假 P；P 未收获由 detailed_body 明示。
4. **KM：** `res$km_binary` → `logrank_p`/`cutoff`；`res$km_strata$logrank_by_strata` → 多条（带 `strata`）。
5. **Forest：** `is.data.frame(res$subgroup)` → `list(db=db_lab, rows=res$subgroup)`。

同库每种槽去重（保留首次完整命中）。

- [ ] **Step 4: Run both test files — PASS**

- [ ] **Step 5: Commit（仅当用户要求）**

---

