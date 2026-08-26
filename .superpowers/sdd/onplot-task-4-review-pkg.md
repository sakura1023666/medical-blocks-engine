# Review package Task 4
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task4/pub_figure_export.R	2026-08-26 16:25:48.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/R/pub_figure_export.R	2026-08-26 16:31:35.749044700 +0800
@@ -284,6 +284,19 @@
   paste0(label, " = ", formatC(pv, digits = 3, format = "f"))
 }
 
+.pub_figure_extract_cox_rcs_p <- function(p) {
+  list(
+    p_overall = tryCatch(
+      suppressWarnings(as.numeric(p$logtest[3L]))[1L],
+      error = function(e) NA_real_
+    ),
+    p_nonlinear = tryCatch(
+      suppressWarnings(as.numeric(p$coefficients[2L, 5L]))[1L],
+      error = function(e) NA_real_
+    )
+  )
+}
+
 .pub_figure_rcs_annotation_lines <- function(rcs_findings) {
   if (!length(rcs_findings)) return(character(0))
   out <- character(0)
```
## Block diff
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task4/01block_rcs_prognosis.R	2026-08-26 16:07:35.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/Blocks/15_rcs/01block_rcs_prognosis.R	2026-08-26 16:31:37.778125300 +0800
@@ -495,6 +495,28 @@
   show_cut_c <- n_panel < 4L || !isTRUE(m3_sig)
   show_cut_d <- n_panel >= 4L && isTRUE(m3_sig)
 
+  if (!exists(".pub_figure_extract_cox_rcs_p", mode = "function")) {
+    pf_r <- file.path(ctx$config$project$root %||% getwd(), "R/pub_figure_export.R")
+    if (file.exists(pf_r)) source(pf_r, local = FALSE)
+  }
+  .rcp01_panel_stats <- function(res, cuts = numeric(0)) {
+    pe <- .pub_figure_extract_cox_rcs_p(res$p)
+    cuts <- as.numeric(cuts)
+    list(
+      p_overall = pe$p_overall,
+      p_nonlinear = pe$p_nonlinear,
+      cutoffs = cuts[is.finite(cuts)]
+    )
+  }
+  ctx$results$rcs_prognosis_panel_stats <- list(
+    Crude = .rcp01_panel_stats(resA, numeric(0)),
+    Model1 = .rcp01_panel_stats(resB, numeric(0)),
+    Model2 = .rcp01_panel_stats(resC, cut_use$all %||% numeric(0))
+  )
+  if (!is.null(resD) && n_panel >= 4L) {
+    ctx$results$rcs_prognosis_panel_stats$Model3 <- .rcp01_panel_stats(resD, numeric(0))
+  }
+
   lay <- if (exists("pipeline_rcs_layout", mode = "function")) {
     pipeline_rcs_layout(n_panel)
   } else {
```
## Test diff
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task4/test_pub_figure_onplot_annotations.R	2026-08-26 16:24:35.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/tests/test_pub_figure_onplot_annotations.R	2026-08-26 16:31:35.448286800 +0800
@@ -8,6 +8,16 @@
 source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
 
 stopifnot(exists(".pub_figure_fmt_p_label", mode = "function"))
+stopifnot(exists(".pub_figure_extract_cox_rcs_p", mode = "function"))
+
+fake_p <- list(
+  logtest = c(NA, NA, 0.001),
+  coefficients = matrix(c(rep(NA, 5), c(NA, NA, NA, NA, 0.116)), nrow = 2, byrow = TRUE)
+)
+pe <- .pub_figure_extract_cox_rcs_p(fake_p)
+stopifnot(isTRUE(abs(pe$p_overall - 0.001) < 1e-9))
+stopifnot(isTRUE(abs(pe$p_nonlinear - 0.116) < 1e-9))
+
 stopifnot(identical(.pub_figure_fmt_p_label("P-overall", 0.001), "P-overall = 0.001"))
 stopifnot(identical(.pub_figure_fmt_p_label("P-overall", 0.0004), "P-overall < 0.001"))
 stopifnot(identical(.pub_figure_fmt_p_label("P-non-linear", NA_real_), "P-non-linear = NA"))
```
