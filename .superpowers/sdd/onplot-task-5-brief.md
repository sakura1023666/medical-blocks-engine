### Task 5: `rcs_incidence` 写 `rcs_incidence_panel_stats`

**Files:**
- Modify: `Blocks/15_rcs/02block_rcs_incidence.R`
- Modify: `R/pub_figure_export.R`（`.pub_figure_extract_lrm_anova_p`）
- Modify: `tests/test_pub_figure_onplot_annotations.R`

**Interfaces:**
- Produces: `ctx$results$rcs_incidence_panel_stats`  
- P 与图注同源：`p_overall = an[nrow(an), 3]`，`p_nonlinear = an[2, 3]`

- [ ] **Step 1: Add extractor**

```r
.pub_figure_extract_lrm_anova_p <- function(an) {
  an <- tryCatch(as.matrix(an), error = function(e) NULL)
  if (is.null(an) || !nrow(an) || ncol(an) < 3L) {
    return(list(p_overall = NA_real_, p_nonlinear = NA_real_))
  }
  list(
    p_overall = suppressWarnings(as.numeric(an[nrow(an), 3L]))[1L],
    p_nonlinear = suppressWarnings(as.numeric(an[min(2L, nrow(an)), 3L]))[1L]
  )
}
```

- [ ] **Step 2: After fits in `block_rcs_incidence`**

```r
.panel_from_res <- function(res, show_cuts = FALSE) {
  pe <- .pub_figure_extract_lrm_anova_p(res$an)
  cuts <- if (isTRUE(show_cuts)) {
    as.numeric(res$cutoffs$all %||% res$cutoffs$or1 %||% numeric(0))
  } else numeric(0)
  list(
    p_overall = pe$p_overall,
    p_nonlinear = pe$p_nonlinear,
    cutoffs = cuts[is.finite(cuts)]
  )
}
ctx$results$rcs_incidence_panel_stats <- list(
  Crude  = .panel_from_res(resA, FALSE),
  Model1 = .panel_from_res(resB, FALSE),
  Model2 = .panel_from_res(resC, TRUE)
)
```

- [ ] **Step 3: Fixture test for anova extractor + incidence panel_stats harvest key**

- [ ] **Step 4: Run tests PASS**

- [ ] **Step 5: Commit（仅当用户要求）**

---

