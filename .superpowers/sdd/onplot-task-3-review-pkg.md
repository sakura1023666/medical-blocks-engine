# Review package Task 3
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task3/pub_figure_export.R	2026-08-26 16:18:52.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/R/pub_figure_export.R	2026-08-26 16:25:48.027681900 +0800
@@ -372,13 +372,101 @@
   out
 }
 
+.PUB_FIGURE_RCS_PANEL_STATS_KEYS <- c(
+  "rcs_prognosis_panel_stats",
+  "rcs_incidence_panel_stats",
+  "rcs_nhanes_panel_stats",
+  "rcs_iptw_panel_stats"
+)
+
+#' 将 rcs_*_panel_stats 规范为 helpers 所需结构；无 panel_stats 则返回 NULL（不合成假 P）
+.pub_figure_harvest_normalize_rcs <- function(res, db_lab) {
+  if (!is.list(res) || !length(res)) return(NULL)
+  ps <- NULL
+  for (k in .PUB_FIGURE_RCS_PANEL_STATS_KEYS) {
+    cand <- res[[k]]
+    if (is.list(cand) && length(cand)) {
+      ps <- cand
+      break
+    }
+  }
+  if (is.null(ps)) return(NULL)
+  child_is_panel <- function(x) {
+    is.list(x) && (!is.null(x$p_overall) || !is.null(x$p_nonlinear) || !is.null(x$name))
+  }
+  panels <- list()
+  append_panel <- function(nm, pan) {
+    if (!is.list(pan)) return()
+    panels[[length(panels) + 1L]] <<- list(
+      name = as.character(nm %||% pan$name %||% "Model2")[1L],
+      p_overall = suppressWarnings(as.numeric(pan$p_overall %||% NA_real_)[1L]),
+      p_nonlinear = suppressWarnings(as.numeric(pan$p_nonlinear %||% NA_real_)[1L]),
+      cutoffs = pan$cutoffs
+    )
+  }
+  nms <- names(ps)
+  if (any(vapply(ps, child_is_panel, logical(1)))) {
+    for (i in seq_along(ps)) {
+      nm <- if (!is.null(nms) && nzchar(nms[[i]])) nms[[i]] else NULL
+      append_panel(nm, ps[[i]])
+    }
+  } else if (child_is_panel(ps)) {
+    append_panel(ps$name %||% "Model2", ps)
+  }
+  if (!length(panels)) return(NULL)
+  list(db = as.character(db_lab %||% "")[1L], panels = panels)
+}
+
+.pub_figure_harvest_km_items <- function(res, db_lab) {
+  items <- list()
+  if (!is.list(res)) return(items)
+  db_lab <- as.character(db_lab %||% "")[1L]
+  kb <- res$km_binary
+  if (is.list(kb) && !is.data.frame(kb) && (!is.null(kb$logrank_p) || !is.null(kb$cutoff))) {
+    items[[length(items) + 1L]] <- list(
+      db = db_lab, logrank_p = kb$logrank_p, cutoff = kb$cutoff, .slot = "binary"
+    )
+  }
+  lbs <- NULL
+  ks <- res$km_strata
+  if (is.list(ks) && !is.data.frame(ks)) lbs <- ks$logrank_by_strata
+  if (is.null(lbs) || !length(lbs)) return(items)
+  push_strata <- function(st, lp, cu = NULL) {
+    items[[length(items) + 1L]] <<- list(
+      db = db_lab,
+      strata = as.character(st %||% "")[1L],
+      logrank_p = lp,
+      cutoff = cu,
+      .slot = "strata"
+    )
+  }
+  nms <- names(lbs)
+  if (is.numeric(lbs) || is.integer(lbs)) {
+    for (i in seq_along(lbs)) {
+      st <- if (!is.null(nms) && length(nms) >= i && nzchar(nms[[i]])) nms[[i]] else ""
+      push_strata(st, unname(lbs[[i]]))
+    }
+  } else if (is.list(lbs)) {
+    for (i in seq_along(lbs)) {
+      el <- lbs[[i]]
+      st_nm <- if (!is.null(nms) && length(nms) >= i && nzchar(nms[[i]])) nms[[i]] else ""
+      if (is.list(el)) {
+        push_strata(el$strata %||% st_nm, el$logrank_p %||% el[[1L]], el$cutoff)
+      } else if (is.numeric(el) || is.integer(el)) {
+        push_strata(st_nm, unname(el))
+      }
+    }
+  }
+  items
+}
+
 #' 从 Figures 旁 Tables/ 与各库 step* cutoff_*.csv / checkpoint 收获可写入正文的结果要点
 pub_figure_harvest_findings <- function(figures_dir, meta = list()) {
   figures_dir <- as.character(figures_dir %||% "")[1L]
   index_root <- dirname(figures_dir)
   tab_dir <- file.path(index_root, "Tables")
   out <- list(association = list(), cutoffs = list(), attrition = list(), roc = list(),
-              maxstat = list())
+              maxstat = list(), rcs = list(), km = list(), forest = list())
 
   # Table 2：优先无库标签；否则各库一份
   if (dir.exists(tab_dir)) {
@@ -473,12 +561,58 @@
     file.path(ck_root, "eICU"), file.path(ck_root, "MIMIC"),
     file.path(ck_root, "nhanes"), file.path(ck_root, "mimic")
   )
+  seen_rcs <- character(0)
+  seen_km_bin <- character(0)
+  seen_km_str <- character(0)
+  seen_forest <- character(0)
   for (dd in unique(db_dirs)) {
     if (!dir.exists(dd)) next
     db_lab <- basename(dd)
     if (tolower(db_lab) %in% c("nhanes", "eicu")) db_lab <- "eICU"
     if (tolower(db_lab) %in% c("mimic")) db_lab <- "MIMIC"
 
+    rds_files <- list.files(dd, pattern = "\\.rds$", full.names = TRUE)
+    if (length(rds_files)) {
+      bn <- basename(rds_files)
+      prio <- grepl("rcs|km|subgroup", bn, ignore.case = TRUE)
+      rds_files <- c(rds_files[prio], rds_files[!prio])
+      for (rp in rds_files) {
+        obj <- tryCatch(readRDS(rp), error = function(e) NULL)
+        if (is.null(obj)) next
+        res <- obj$ctx$results %||% obj$results %||% list()
+        if (!is.list(res) || !length(res)) next
+
+        if (!(db_lab %in% seen_rcs)) {
+          rcs_item <- .pub_figure_harvest_normalize_rcs(res, db_lab)
+          if (!is.null(rcs_item)) {
+            out$rcs[[length(out$rcs) + 1L]] <- rcs_item
+            seen_rcs <- c(seen_rcs, db_lab)
+          }
+        }
+
+        km_items <- .pub_figure_harvest_km_items(res, db_lab)
+        for (it in km_items) {
+          slot <- as.character(it$.slot %||% "binary")[1L]
+          it$.slot <- NULL
+          if (identical(slot, "binary")) {
+            if (db_lab %in% seen_km_bin) next
+            seen_km_bin <- c(seen_km_bin, db_lab)
+          } else {
+            key <- paste(db_lab, it$strata %||% "", sep = "\t")
+            if (key %in% seen_km_str) next
+            seen_km_str <- c(seen_km_str, key)
+          }
+          out$km[[length(out$km) + 1L]] <- it
+        }
+
+        if (!(db_lab %in% seen_forest) &&
+            is.data.frame(res$subgroup) && nrow(res$subgroup) > 0L) {
+          out$forest[[length(out$forest) + 1L]] <- list(db = db_lab, rows = res$subgroup)
+          seen_forest <- c(seen_forest, db_lab)
+        }
+      }
+    }
+
     roc_p <- file.path(dd, "simple_ROC.rds")
     if (!file.exists(roc_p)) {
       hits <- Sys.glob(file.path(dd, "*simple_ROC*.rds"))
```

## Diff test_pub_figure_onplot_annotations.R
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task3/test_pub_figure_onplot_annotations.R	2026-08-26 16:13:40.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/tests/test_pub_figure_onplot_annotations.R	2026-08-26 16:24:35.125647400 +0800
@@ -44,4 +44,51 @@
 stopifnot(any(grepl("Overall", fo_lines)), any(grepl("1\\.20", fo_lines)))
 stopifnot(any(grepl("interaction|交互", fo_lines, ignore.case = TRUE)))
 
+# Task 3: harvest rcs / km / forest from index_root/<DB>/*.rds
+ix_root <- tempfile("ix_")
+dir.create(file.path(ix_root, "Figures"), recursive = TRUE)
+dir.create(file.path(ix_root, "MIMIC"), recursive = TRUE)
+saveRDS(
+  list(results = list(
+    rcs_prognosis_panel_stats = list(
+      Model2 = list(p_overall = 0.001, p_nonlinear = 0.116, cutoffs = 0.52)
+    )
+  )),
+  file.path(ix_root, "MIMIC", "rcs_prognosis.rds")
+)
+saveRDS(
+  list(results = list(
+    km_binary = list(logrank_p = 0.023, cutoff = 1.25),
+    subgroup = data.frame(
+      Variable = c("Overall", "Age"), `Point Estimate` = c(1.2, 1.1),
+      Lower = c(1.0, 0.8), Upper = c(1.4, 1.5),
+      `P for interaction` = c(NA, 0.04), check.names = FALSE
+    )
+  )),
+  file.path(ix_root, "MIMIC", "km_binary.rds")
+)
+
+hf <- pub_figure_harvest_findings(file.path(ix_root, "Figures"), meta = list(databases = "MIMIC"))
+stopifnot(length(hf$rcs) >= 1L)
+stopifnot(any(vapply(hf$rcs[[1]]$panels, function(p) {
+  isTRUE(abs((p$p_overall %||% NA_real_) - 0.001) < 1e-9)
+}, logical(1))))
+stopifnot(length(hf$km) >= 1L)
+stopifnot(length(hf$forest) >= 1L)
+unlink(ix_root, recursive = TRUE)
+
+# 无 panel_stats 时不得合成假 P
+ix_miss <- tempfile("ixmiss_")
+dir.create(file.path(ix_miss, "Figures"), recursive = TRUE)
+dir.create(file.path(ix_miss, "MIMIC"), recursive = TRUE)
+saveRDS(
+  list(results = list(rcs_prognosis = list(note = "plot only"))),
+  file.path(ix_miss, "MIMIC", "rcs_prognosis.rds")
+)
+hf_miss <- pub_figure_harvest_findings(
+  file.path(ix_miss, "Figures"), meta = list(databases = "MIMIC")
+)
+stopifnot(length(hf_miss$rcs %||% list()) == 0L)
+unlink(ix_miss, recursive = TRUE)
+
 cat("test_pub_figure_onplot_annotations: OK\n")
```
