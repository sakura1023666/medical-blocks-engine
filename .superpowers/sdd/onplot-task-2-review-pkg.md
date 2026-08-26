# Review package Task 2
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task2/pub_figure_export.R	2026-08-26 16:14:32.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/R/pub_figure_export.R	2026-08-26 16:18:52.024158200 +0800
@@ -701,7 +701,7 @@
     if (nzchar(panel_note)) lines <- c(lines, panel_note, "")
     ms <- find$maxstat %||% list()
     if (length(ms)) {
-      lines <- c(lines, "各库切点：")
+      lines <- c(lines, "图上标注：", "", "各库切点：")
       seen_ms <- character(0)
       for (m in ms) {
         db <- as.character(m$db %||% "库")[1L]
@@ -739,6 +739,13 @@
     } else {
       lines <- c(lines, "具体组间效应量见同目录 Table 2；图本身主要展示累积风险曲线形态。", "")
     }
+    lines <- c(lines, "图上标注：", "")
+    km_ann <- .pub_figure_km_annotation_lines(find$km %||% list())
+    if (length(km_ann)) {
+      lines <- c(lines, km_ann, "")
+    } else {
+      lines <- c(lines, "- 未收获：Log-rank P（及 binary cutoff）", "")
+    }
     return(lines)
   }
 
@@ -756,6 +763,13 @@
     if (nzchar(rcs_find)) {
       lines <- c(lines, paste0("切点与连续变量效应要点：", rcs_find, "。"), "")
     }
+    lines <- c(lines, "图上标注（与面板一致）：", "")
+    rcs_ann <- .pub_figure_rcs_annotation_lines(find$rcs %||% list())
+    if (length(rcs_ann)) {
+      lines <- c(lines, rcs_ann, "")
+    } else {
+      lines <- c(lines, "- 未收获：各库 RCS panel_stats / P-overall / P-non-linear / cutoff", "")
+    }
     return(lines)
   }
 
@@ -789,6 +803,13 @@
     if (nzchar(fo)) {
       lines <- c(lines, paste0("与主分析 Table 2 对照：", fo, "。"), "")
     }
+    lines <- c(lines, "图上标注（按图面行摘录）：", "")
+    fo_ann <- .pub_figure_forest_annotation_lines(find$forest %||% list())
+    if (length(fo_ann)) {
+      lines <- c(lines, fo_ann, "")
+    } else {
+      lines <- c(lines, "- 未收获：subgroup 结果表", "")
+    }
     return(lines)
   }
 
@@ -806,7 +827,7 @@
     # 去重同库
     seen <- character(0)
     if (length(rocs)) {
-      lines <- c(lines, "各库判别指标：")
+      lines <- c(lines, "图上标注：", "", "各库判别指标：")
       for (r in rocs) {
         db <- as.character(r$db %||% "")[1L]
         if (db %in% seen) next
```

## Diff tests/test_pub_figure_export.R
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task2/test_pub_figure_export.R	2026-08-21 09:33:30.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/tests/test_pub_figure_export.R	2026-08-26 16:17:59.758684600 +0800
@@ -77,6 +77,62 @@
 stopifnot(grepl("图面说明", fc_txt), !grepl("## 标识", fc_txt))
 unlink(fc_md)
 
+# RCS：注入 findings$rcs 后必须出现「图上标注」与 P-overall
+meta_rcs <- meta
+meta_rcs$findings <- list(
+  rcs = list(list(
+    db = "MIMIC",
+    panels = list(list(
+      name = "Model2", p_overall = 0.001, p_nonlinear = 0.116, cutoffs = 0.52
+    ))
+  ))
+)
+rcs_md <- tempfile("rcs_md_")
+pub_figure_write_image_md(rcs_md, "Figure 2. RCS plot", meta = meta_rcs, raster_ok = TRUE)
+rcs_txt <- paste(readLines(rcs_md, warn = FALSE), collapse = "\n")
+stopifnot(grepl("图上标注", rcs_txt))
+stopifnot(grepl("P-overall = 0.001", rcs_txt))
+stopifnot(grepl("P-non-linear = 0.116", rcs_txt))
+stopifnot(grepl("0\\.52", rcs_txt))
+unlink(rcs_md)
+
+# RCS：无 findings$rcs → 明示未收获
+meta_rcs_empty <- meta
+meta_rcs_empty$findings <- list()
+rcs_md2 <- tempfile("rcs_md2_")
+pub_figure_write_image_md(rcs_md2, "Figure 2. RCS plot", meta = meta_rcs_empty, raster_ok = TRUE)
+rcs_txt2 <- paste(readLines(rcs_md2, warn = FALSE), collapse = "\n")
+stopifnot(grepl("图上标注", rcs_txt2))
+stopifnot(grepl("未收获", rcs_txt2))
+unlink(rcs_md2)
+
+# KM
+meta_km <- meta
+meta_km$findings <- list(km = list(list(db = "eICU", logrank_p = 0.023, cutoff = 1.25)))
+km_md <- tempfile("km_md_")
+pub_figure_write_image_md(km_md, "Figure 3. KM curve", meta = meta_km, raster_ok = TRUE)
+km_txt <- paste(readLines(km_md, warn = FALSE), collapse = "\n")
+stopifnot(grepl("图上标注", km_txt), grepl("Log-rank", km_txt), grepl("0\\.023", km_txt))
+unlink(km_md)
+
+# Forest
+meta_fo <- meta
+meta_fo$findings <- list(forest = list(list(
+  db = "eICU",
+  rows = data.frame(
+    Variable = c("Overall", "Sex: Male"),
+    `Point Estimate` = c(1.2, 1.3),
+    Lower = c(1.0, 0.9), Upper = c(1.4, 1.8),
+    `P for interaction` = c(NA, 0.12),
+    check.names = FALSE, stringsAsFactors = FALSE
+  )
+)))
+fo_md <- tempfile("fo_md_")
+pub_figure_write_image_md(fo_md, "Figure 4. Subgroup forest plot", meta = meta_fo, raster_ok = TRUE)
+fo_txt <- paste(readLines(fo_md, warn = FALSE), collapse = "\n")
+stopifnot(grepl("图上标注", fo_txt), grepl("Overall", fo_txt), grepl("1\\.2", fo_txt))
+unlink(fo_md)
+
 # KM：有 Table 2 数字时应写进正文一句话
 meta_find <- meta
 meta_find$findings <- list(
```
