### Task 4: `rcs_prognosis` 写 `rcs_prognosis_panel_stats`

**Files:**
- Modify: `Blocks/15_rcs/01block_rcs_prognosis.R`
- Modify: `R/pub_figure_export.R`（`.pub_figure_extract_cox_rcs_p`）
- Modify: `tests/test_pub_figure_onplot_annotations.R`

**Interfaces:**
- Produces: `ctx$results$rcs_prognosis_panel_stats` =  
  `list(Crude=..., Model1=..., Model2=..., Model3?=...)`  
  每项 `list(p_overall, p_nonlinear, cutoffs)`  
- Extractor 与图例同一索引：`logtest[3]`、`coefficients[2,5]`

- [ ] **Step 1: Add shared extractor in `R/pub_figure_export.R`**

```r
.pub_figure_extract_cox_rcs_p <- function(p) {
  list(
    p_overall = tryCatch(suppressWarnings(as.numeric(p$logtest[3L]))[1L], error = function(e) NA_real_),
    p_nonlinear = tryCatch(suppressWarnings(as.numeric(p$coefficients[2L, 5L]))[1L], error = function(e) NA_real_)
  )
}
```

- [ ] **Step 2: Test extractor**

```r
fake_p <- list(
  logtest = c(NA, NA, 0.001),
  coefficients = matrix(c(rep(NA, 5), c(NA, NA, NA, NA, 0.116)), nrow = 2, byrow = TRUE)
)
pe <- .pub_figure_extract_cox_rcs_p(fake_p)
stopifnot(isTRUE(abs(pe$p_overall - 0.001) < 1e-9))
stopifnot(isTRUE(abs(pe$p_nonlinear - 0.116) < 1e-9))
```

- [ ] **Step 3: In prognosis block after fits，写 panel_stats**

```r
.ps <- function(res, cuts = numeric(0)) {
  pe <- .pub_figure_extract_cox_rcs_p(res$p)
  cuts <- as.numeric(cuts)
  list(
    p_overall = pe$p_overall,
    p_nonlinear = pe$p_nonlinear,
    cutoffs = cuts[is.finite(cuts)]
  )
}
# Model2 用图上竖线 cutoffs（cut_use$all）；Crude/M1 通常无竖线 → cutoffs 空
ctx$results$rcs_prognosis_panel_stats <- list(
  Crude  = .ps(resA, numeric(0)),
  Model1 = .ps(resB, numeric(0)),
  Model2 = .ps(resC, cut_use$all %||% numeric(0))
)
if (exists("resD") && !is.null(resD) && n_panel >= 4L) {
  ctx$results$rcs_prognosis_panel_stats$Model3 <- .ps(resD, numeric(0))
}
```

（变量名以文件内实际为准。）

- [ ] **Step 4: Run tests PASS**

- [ ] **Step 5: Commit（仅当用户要求）**

---

