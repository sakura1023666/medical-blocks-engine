# Review package Task 6
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task6/03block_rcs_nhanes.R	2026-08-19 11:20:34.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/Blocks/15_rcs/03block_rcs_nhanes.R	2026-08-26 16:45:20.346673300 +0800
@@ -663,6 +663,23 @@
   ctx$results$rcs_nhanes_model2_factors <- M2_vars
   ctx$results$rcs_nhanes_model3_factors <- M3_vars
 
+  .rcn01_panel_stats <- function(res, cuts = numeric(0)) {
+    cuts <- as.numeric(cuts)
+    list(
+      p_overall = if (is.null(res)) NA_real_ else suppressWarnings(as.numeric(res$p_overall)[1L]),
+      p_nonlinear = if (is.null(res)) NA_real_ else suppressWarnings(as.numeric(res$p_nonlin)[1L]),
+      cutoffs = cuts[is.finite(cuts)]
+    )
+  }
+  ctx$results$rcs_nhanes_panel_stats <- list(
+    Crude  = .rcn01_panel_stats(resA, numeric(0)),
+    Model1 = .rcn01_panel_stats(resB, numeric(0)),
+    Model2 = .rcn01_panel_stats(resC, cut_use$all %||% numeric(0))
+  )
+  if (length(M3_vars) && !is.null(resD)) {
+    ctx$results$rcs_nhanes_panel_stats$Model3 <- .rcn01_panel_stats(resD, numeric(0))
+  }
+
   cutoff_vals <- c(cut_use$or1, cut_use$peak)
   cutoff_types <- c(
     rep("or1", length(cut_use$or1)),
```
## IPTW
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task6/04block_rcs_iptw_weighted.R	2026-08-17 17:33:38.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/Blocks/15_rcs/04block_rcs_iptw_weighted.R	2026-08-26 16:45:24.607675300 +0800
@@ -536,6 +536,24 @@
   ctx$results$rcs_iptw_model1_factors <- M1_vars
   ctx$results$rcs_iptw_model2_factors <- M2_vars
   ctx$results$rcs_iptw_model3_factors <- M3_vars
+
+  .riw04_panel_stats <- function(res, cuts = numeric(0)) {
+    cuts <- as.numeric(cuts)
+    list(
+      p_overall = if (is.null(res)) NA_real_ else suppressWarnings(as.numeric(res$p_overall)[1L]),
+      p_nonlinear = if (is.null(res)) NA_real_ else suppressWarnings(as.numeric(res$p_nonlin)[1L]),
+      cutoffs = cuts[is.finite(cuts)]
+    )
+  }
+  ctx$results$rcs_iptw_panel_stats <- list(
+    Crude  = .riw04_panel_stats(resA, numeric(0)),
+    Model1 = .riw04_panel_stats(resB, numeric(0)),
+    Model2 = .riw04_panel_stats(resC, cut_use$all %||% numeric(0))
+  )
+  if (length(M3_vars) && !is.null(resD)) {
+    ctx$results$rcs_iptw_panel_stats$Model3 <- .riw04_panel_stats(resD, numeric(0))
+  }
+
   ctx$results$rcs_cutoff <- primary_cutoff
   ctx$results$rcs_cutoff_index <- index_var
   ctx$results$rcs_cutoff_or1 <- cut_use$or1
```
## Test
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task6/test_pub_figure_onplot_annotations.R	2026-08-26 16:38:14.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/tests/test_pub_figure_onplot_annotations.R	2026-08-26 16:45:26.109465300 +0800
@@ -132,4 +132,31 @@
 stopifnot(length(hf_miss$rcs %||% list()) == 0L)
 unlink(ix_miss, recursive = TRUE)
 
+# Task 6: NHANES rcs_nhanes_panel_stats harvest (checkpoints/nhanes path)
+parent_nh <- tempfile("study_nh_")
+ix_name_nh <- "IdxNH"
+ix_root_nh <- file.path(parent_nh, "by_index", ix_name_nh)
+dir.create(file.path(ix_root_nh, "Figures"), recursive = TRUE)
+ck_nhanes <- file.path(parent_nh, "checkpoints", "by_index", ix_name_nh, "nhanes")
+dir.create(ck_nhanes, recursive = TRUE)
+saveRDS(
+  list(results = list(
+    rcs_nhanes_panel_stats = list(
+      Model2 = list(p_overall = 0.003, p_nonlinear = 0.045, cutoffs = 2.1)
+    )
+  )),
+  file.path(ck_nhanes, "rcs_nhanes.rds")
+)
+hf_nh <- pub_figure_harvest_findings(
+  file.path(ix_root_nh, "Figures"),
+  meta = list(databases = "NHANES")
+)
+stopifnot(length(hf_nh$rcs) >= 1L)
+stopifnot(any(vapply(hf_nh$rcs, function(item) {
+  any(vapply(item$panels, function(p) {
+    isTRUE(abs((p$p_overall %||% NA_real_) - 0.003) < 1e-9)
+  }, logical(1)))
+}, logical(1))))
+unlink(parent_nh, recursive = TRUE)
+
 cat("test_pub_figure_onplot_annotations: OK\n")
```
