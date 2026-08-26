# Review package Task 5
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task5/pub_figure_export.R	2026-08-26 16:31:35.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/R/pub_figure_export.R	2026-08-26 16:37:08.180748500 +0800
@@ -297,6 +297,17 @@
   )
 }
 
+.pub_figure_extract_lrm_anova_p <- function(an) {
+  an <- tryCatch(as.matrix(an), error = function(e) NULL)
+  if (is.null(an) || !nrow(an) || ncol(an) < 3L) {
+    return(list(p_overall = NA_real_, p_nonlinear = NA_real_))
+  }
+  list(
+    p_overall = suppressWarnings(as.numeric(an[nrow(an), 3L]))[1L],
+    p_nonlinear = suppressWarnings(as.numeric(an[min(2L, nrow(an)), 3L]))[1L]
+  )
+}
+
 .pub_figure_rcs_annotation_lines <- function(rcs_findings) {
   if (!length(rcs_findings)) return(character(0))
   out <- character(0)
```
## Block
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task5/02block_rcs_incidence.R	2026-08-26 16:04:50.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/Blocks/15_rcs/02block_rcs_incidence.R	2026-08-26 16:37:08.187257400 +0800
@@ -774,6 +774,29 @@
     NULL
   }
 
+  if (!exists(".pub_figure_extract_lrm_anova_p", mode = "function")) {
+    pf_r <- file.path(ctx$config$project$root %||% getwd(), "R/pub_figure_export.R")
+    if (file.exists(pf_r)) source(pf_r, local = FALSE)
+  }
+  .panel_from_res <- function(res, show_cuts = FALSE) {
+    pe <- .pub_figure_extract_lrm_anova_p(res$an)
+    cuts <- if (isTRUE(show_cuts)) {
+      as.numeric(res$cutoffs$all %||% res$cutoffs$or1 %||% numeric(0))
+    } else {
+      numeric(0)
+    }
+    list(
+      p_overall = pe$p_overall,
+      p_nonlinear = pe$p_nonlinear,
+      cutoffs = cuts[is.finite(cuts)]
+    )
+  }
+  ctx$results$rcs_incidence_panel_stats <- list(
+    Crude  = .panel_from_res(resA, FALSE),
+    Model1 = .panel_from_res(resB, FALSE),
+    Model2 = .panel_from_res(resC, TRUE)
+  )
+
   xlab_disp <- if (exists("pipeline_plot_axis_label", mode = "function")) {
     pipeline_plot_axis_label(Index, cfg)
   } else {
```
