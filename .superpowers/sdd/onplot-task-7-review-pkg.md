# Review package Task 7
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task7/01block_km_binary.R	2026-08-26 16:05:57.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/Blocks/27_KM/01block_km_binary.R	2026-08-26 16:52:07.819561600 +0800
@@ -166,6 +166,10 @@
   surv_grp_form <- stats::as.formula(paste0(
     "Surv(", time_var, ", ", event_var, ") ~ Group"
   ))
+  .logrank_p <- tryCatch({
+    sd <- survival::survdiff(surv_grp_form, data = data_categorized)
+    stats::pchisq(sd$chisq, length(sd$n) - 1L, lower.tail = FALSE)
+  }, error = function(e) NA_real_)
   fit_surv <- tryCatch(
     survminer::surv_fit(surv_grp_form, data = data_categorized),
     error = function(e) {
@@ -314,7 +318,8 @@
   ctx$results$km_binary <- list(
     index_var = index_var, cutoff = cutoff,
     n = nrow(data_categorized),
-    level_low = lvl_lo, level_high = lvl_hi
+    level_low = lvl_lo, level_high = lvl_hi,
+    logrank_p = .logrank_p
   )
   cli::cli_alert_success("km_binary 完成（cutoff = {round(cutoff, 4)}）。")
   ctx
```
## strata
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task7/02block_km_strata.R	2026-08-26 16:05:47.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/Blocks/27_KM/02block_km_strata.R	2026-08-26 16:52:06.597574000 +0800
@@ -238,15 +238,20 @@
   .kms02_sanitize_legend(trimws(v))
 }
 
-.kms02_safe_logrank_p <- function(formula, data) {
+.kms02_logrank_p_numeric <- function(formula, data) {
   sd <- tryCatch(survival::survdiff(formula, data = data), error = function(e) NULL)
-  if (is.null(sd)) return("Log-rank P = NA")
+  if (is.null(sd)) return(NA_real_)
   ch <- sd$chisq
   df <- length(sd$n) - 1L
-  if (!is.finite(ch) || ch < 0 || df < 1L) return("Log-rank P = NA")
+  if (!is.finite(ch) || ch < 0 || df < 1L) return(NA_real_)
   pv <- stats::pchisq(ch, df = df, lower.tail = FALSE)
+  if (!is.finite(pv)) return(NA_real_)
+  min(max(pv, 0), 1)
+}
+
+.kms02_safe_logrank_p <- function(formula, data) {
+  pv <- .kms02_logrank_p_numeric(formula, data)
   if (!is.finite(pv)) return("Log-rank P = NA")
-  pv <- min(max(pv, 0), 1)
   # 保留 3 位小数；p < 0.001 显示为 P < 0.001
   if (pv < 0.001) return("Log-rank P < 0.001")
   paste0("Log-rank P = ", formatC(pv, digits = 3, format = "f"))
@@ -809,6 +814,7 @@
 
   n_ok <- 0L
   plot_list <- list()
+  logrank_by_strata <- list()
 
   for (strata_col in plot_vars) {
     fac <- .kms02_prepare_strata_column(dat, strata_col, strata_defs, ctx, index_var)
@@ -842,6 +848,7 @@
         out_file, plot_w, plot_h, family = font_family
       )
       n_ok <- n_ok + 1L
+      logrank_by_strata[[strata_col]] <- .kms02_logrank_p_numeric(formula, rt_plot)
       cli::cli_alert_success("KM 已保存: {.file {basename(out_file)}}")
       if (exists("pub_mirror_saved", mode = "function")) {
         pub_mirror_saved(ctx, out_file)
@@ -896,7 +903,8 @@
   ctx$results$km_strata <- list(
     n_plots = n_ok,
     strata_vars = plot_vars,
-    derived_columns = setdiff(derived_cols, c(time_var, event_var, id_col))
+    derived_columns = setdiff(derived_cols, c(time_var, event_var, id_col)),
+    logrank_by_strata = logrank_by_strata
   )
   cli::cli_alert_success(
     "km_strata 完成: {n_ok} 张单图；ctx$data$km_strata_derived 已写入（{ncol(ctx$data$km_strata_derived)} 列）。"
```
