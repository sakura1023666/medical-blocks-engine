# Review package Task 1 (no-git snapshot diff)

## Files changed
- R/pub_figure_export.R
- tests/test_pub_figure_onplot_annotations.R (new)

## Diff: pub_figure_export.R vs pre-task snapshot
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task1/pub_figure_export.R	2026-08-26 16:09:14.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/R/pub_figure_export.R	2026-08-26 16:14:32.704673900 +0800
@@ -276,6 +276,102 @@
   sprintf("%s%sHR=1参考/切点约在 %s", who, what, vals)
 }
 
+.pub_figure_fmt_p_label <- function(label, pv) {
+  label <- as.character(label %||% "P")[1L]
+  pv <- suppressWarnings(as.numeric(pv)[1L])
+  if (!is.finite(pv)) return(paste0(label, " = NA"))
+  if (pv < 0.001) return(paste0(label, " < 0.001"))
+  paste0(label, " = ", formatC(pv, digits = 3, format = "f"))
+}
+
+.pub_figure_rcs_annotation_lines <- function(rcs_findings) {
+  if (!length(rcs_findings)) return(character(0))
+  out <- character(0)
+  for (item in rcs_findings) {
+    db <- as.character(item$db %||% "")[1L]
+    for (pan in item$panels %||% list()) {
+      nm <- as.character(pan$name %||% "Model2")[1L]
+      bits <- c(
+        .pub_figure_fmt_p_label("P-overall", pan$p_overall),
+        .pub_figure_fmt_p_label("P-non-linear", pan$p_nonlinear)
+      )
+      cuts <- suppressWarnings(as.numeric(pan$cutoffs %||% numeric(0)))
+      cuts <- cuts[is.finite(cuts)]
+      if (length(cuts)) {
+        bits <- c(bits, paste0("cutoff = ", paste(signif(cuts, 4), collapse = "、")))
+      }
+      who <- if (nzchar(db)) paste0(db, " ", nm) else nm
+      out <- c(out, sprintf("- %s：%s", who, paste(bits, collapse = "；")))
+    }
+  }
+  out
+}
+
+.pub_figure_km_annotation_lines <- function(km_findings) {
+  if (!length(km_findings)) return(character(0))
+  out <- character(0)
+  for (item in km_findings) {
+    db <- as.character(item$db %||% "库")[1L]
+    strata <- as.character(item$strata %||% "")[1L]
+    who <- if (nzchar(strata)) paste0(db, " ", strata) else db
+    bits <- character(0)
+    if (!is.null(item$logrank_p)) {
+      bits <- c(bits, .pub_figure_fmt_p_label("Log-rank P", item$logrank_p))
+    }
+    cv <- suppressWarnings(as.numeric(item$cutoff %||% NA_real_)[1L])
+    if (is.finite(cv)) bits <- c(bits, sprintf("cutoff = %s", signif(cv, 4)))
+    if (length(bits)) out <- c(out, sprintf("- %s：%s", who, paste(bits, collapse = "；")))
+  }
+  out
+}
+
+.pub_figure_forest_annotation_lines <- function(forest_findings) {
+  if (!length(forest_findings)) return(character(0))
+  out <- character(0)
+  for (item in forest_findings) {
+    db <- as.character(item$db %||% "")[1L]
+    if (nzchar(db)) out <- c(out, paste0("#### ", db), "")
+    df <- item$rows
+    if (!is.data.frame(df) || !nrow(df)) {
+      out <- c(out, "- 未收获：subgroup 表为空", "")
+      next
+    }
+    var_col <- intersect(c("Variable", "Subgroup", "variable"), names(df))[1L]
+    est_col <- intersect(c("Point Estimate", "HR", "OR"), names(df))[1L]
+    lo_col <- intersect(c("Lower", "lower", "CI_low"), names(df))[1L]
+    hi_col <- intersect(c("Upper", "upper", "CI_high"), names(df))[1L]
+    pint_col <- grep("interaction", names(df), ignore.case = TRUE)[1L]
+    if (!length(var_col) || is.na(var_col) || !nzchar(var_col)) {
+      out <- c(out, "- 未收获：subgroup 缺 Variable 列", "")
+      next
+    }
+    for (i in seq_len(nrow(df))) {
+      v <- as.character(df[[var_col]][i])
+      if (!nzchar(v) || grepl("^-+$", v)) next
+      est <- if (!is.na(est_col)) suppressWarnings(as.numeric(df[[est_col]][i])) else NA_real_
+      lo <- if (!is.na(lo_col)) suppressWarnings(as.numeric(df[[lo_col]][i])) else NA_real_
+      hi <- if (!is.na(hi_col)) suppressWarnings(as.numeric(df[[hi_col]][i])) else NA_real_
+      bits <- character(0)
+      if (is.finite(est)) {
+        if (is.finite(lo) && is.finite(hi)) {
+          bits <- c(bits, sprintf("%s (95%%CI %s–%s)",
+                                  formatC(est, digits = 2, format = "f"),
+                                  signif(lo, 4), signif(hi, 4)))
+        } else {
+          bits <- c(bits, as.character(signif(est, 4)))
+        }
+      }
+      if (length(pint_col) && is.finite(pint_col)) {
+        pv <- suppressWarnings(as.numeric(df[[pint_col]][i]))
+        if (is.finite(pv)) bits <- c(bits, .pub_figure_fmt_p_label("P for interaction", pv))
+      }
+      if (length(bits)) out <- c(out, sprintf("- %s：%s", v, paste(bits, collapse = "；")))
+    }
+    out <- c(out, "")
+  }
+  out
+}
+
 #' 从 Figures 旁 Tables/ 与各库 step* cutoff_*.csv / checkpoint 收获可写入正文的结果要点
 pub_figure_harvest_findings <- function(figures_dir, meta = list()) {
   figures_dir <- as.character(figures_dir %||% "")[1L]
```

## New file: tests/test_pub_figure_onplot_annotations.R
```r
# tests/test_pub_figure_onplot_annotations.R
root <- normalizePath(getwd())
if (!file.exists(file.path(root, "R/utils.R"))) {
  cand <- normalizePath(file.path(".."), winslash = "/")
  if (file.exists(file.path(cand, "R/utils.R"))) root <- cand
}
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/pub_figure_export.R"), local = FALSE)

stopifnot(exists(".pub_figure_fmt_p_label", mode = "function"))
stopifnot(identical(.pub_figure_fmt_p_label("P-overall", 0.001), "P-overall = 0.001"))
stopifnot(identical(.pub_figure_fmt_p_label("P-overall", 0.0004), "P-overall < 0.001"))
stopifnot(identical(.pub_figure_fmt_p_label("P-non-linear", NA_real_), "P-non-linear = NA"))

rcs_f <- list(list(
  db = "MIMIC",
  panels = list(
    list(name = "Model2", p_overall = 0.001, p_nonlinear = 0.116, cutoffs = c(0.52))
  )
))
lines <- .pub_figure_rcs_annotation_lines(rcs_f)
stopifnot(any(grepl("P-overall = 0.001", lines)))
stopifnot(any(grepl("P-non-linear = 0.116", lines)))
stopifnot(any(grepl("0\\.52|cutoff", lines, ignore.case = TRUE)))

km_f <- list(list(db = "eICU", logrank_p = 0.023, cutoff = 1.25))
km_lines <- .pub_figure_km_annotation_lines(km_f)
stopifnot(any(grepl("Log-rank", km_lines)), any(grepl("0\\.023", km_lines)))
stopifnot(any(grepl("1\\.25|cutoff", km_lines, ignore.case = TRUE)))

forest_f <- list(list(
  db = "eICU",
  rows = data.frame(
    Variable = c("Overall", "Age < 65", "Age ≥ 65"),
    `Point Estimate` = c(1.20, 1.10, 1.35),
    Lower = c(1.01, 0.90, 1.05),
    Upper = c(1.42, 1.35, 1.74),
    `P for interaction` = c(NA, 0.04, NA),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
))
fo_lines <- .pub_figure_forest_annotation_lines(forest_f)
stopifnot(any(grepl("Overall", fo_lines)), any(grepl("1\\.20", fo_lines)))
stopifnot(any(grepl("interaction|交互", fo_lines, ignore.case = TRUE)))

cat("test_pub_figure_onplot_annotations: OK\n")
```
