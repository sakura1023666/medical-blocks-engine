# Final review package — on-plot annotations

## Progress ledger
# SDD Progress Ledger

Plan: docs/superpowers/plans/2026-08-26-pub-figure-onplot-annotations.md
Workspace: in-place (no git repo; commits skipped)

Task 1: complete (no-git, review Approved; Minor: forest formatC vs signif; brief Step3 should sync formatC)
Task 2: complete (review Approved; Minor: KM/Forest empty-state tests optional)
Task 3: complete (review Approved; Minor: fixture depth, db_dirs hardcode)
Task 4: complete (review Approved)
Task 5: complete (review Approved)
Task 6: complete (review Approved; Minor: nhanes→eICU pre-existing)
Task 7: complete (review Approved)
Task 8: complete (rule Approved by controller spot-check)

## Minor rollups from task reviews
- Task1: forest formatC vs signif inconsistency (partially fixed with formatC for CI branch)
- Task2: KM/Forest empty-state tests optional
- Task3: fixture depth; db_dirs hardcode eICU/MIMIC; nhanes→eICU label
- Task4-5: no full block Cox/lrm fixtures
- Task6: nhanes→eICU pre-existing; Model2 cutoffs vs incidence
- Task7: binary inline logrank vs strata helper

## Changed files summary
- R/pub_figure_export.R
- Blocks/15_rcs/01-04 (prognosis, incidence, nhanes, iptw)
- Blocks/27_KM/01-02
- .cursor/rules/pub_figure_image_information.mdc
- tests/test_pub_figure_export.R, tests/test_pub_figure_onplot_annotations.R (new)
- docs specs/plans

## Diff vs pre-Task1 snapshot (pub_figure_export.R only — large)
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task1/pub_figure_export.R	2026-08-26 16:09:14.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/R/pub_figure_export.R	2026-08-26 16:37:08.180748500 +0800
@@ -276,13 +276,221 @@
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
@@ -377,12 +585,58 @@
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
@@ -605,7 +859,7 @@
     if (nzchar(panel_note)) lines <- c(lines, panel_note, "")
     ms <- find$maxstat %||% list()
     if (length(ms)) {
-      lines <- c(lines, "各库切点：")
+      lines <- c(lines, "图上标注：", "", "各库切点：")
       seen_ms <- character(0)
       for (m in ms) {
         db <- as.character(m$db %||% "库")[1L]
@@ -643,6 +897,13 @@
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
 
@@ -660,6 +921,13 @@
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
 
@@ -693,6 +961,13 @@
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
 
@@ -710,7 +985,7 @@
     # 去重同库
     seen <- character(0)
     if (length(rocs)) {
-      lines <- c(lines, "各库判别指标：")
+      lines <- c(lines, "图上标注：", "", "各库判别指标：")
       for (r in rocs) {
         db <- as.character(r$db %||% "")[1L]
         if (db %in% seen) next
... (truncated if long) ...
```

## Rule diff
```diff
--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task8/pub_figure_image_information.mdc	2026-08-21 09:42:52.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/.cursor/rules/pub_figure_image_information.mdc	2026-08-26 16:55:54.324379200 +0800
@@ -18,6 +18,14 @@
 4. **纳排图（Figure 1 Flowchart）必须逐步人数**：从 `Tables/Flowchart_attrition*.csv` 按库列出每步保留 n，并写「本步排除 X 人」（相邻步差额）。缺 CSV 须明示，不得空话带过。
 5. **数字来源**：只写可收获证据（attrition CSV、Table 2、cutoff CSV、`simple_ROC.rds` / `plot_cutoff.rds`、`_batch_status.json`）。禁止编造 HR/AUC/N。
 6. **Grouping** 与主文闸门一致（logistic/Cox gate）；预后结局字段如 `fustatus` 在上下文中写可读名（如「住院死亡」）并可附原字段名。
+7. **图面标注必录**：图上可见的关键数字/标注必须写入 `## 图面说明`（建议小标题「图上标注」），包括但不限于：
+   - RCS：`P-overall` / `P for overall`、`P-non-linear` / `P for nonlinear`、竖线 cutoff
+   - KM：Log-rank P、二分 cutoff
+   - Forest：Overall 与各亚组效应量(95%CI)、P for interaction
+   - ROC：AUC、CI、Youden、灵敏度/特异度（图上有则写）
+   - maxstat：图上切点
+   - Flowchart：逐步 n 与排除人数
+   数字只来自可收获产物；缺则写「未收获」；**禁止编造**。其它图种若图上有数字，同理。
 
 ## 实现入口
 
@@ -34,9 +42,13 @@
 - [ ] md 含 `## 图面说明`，**不含** `## 标识` / `## 技术`
 - [ ] Figure 1 若存在，逐步纳排人数与排除人数已写出
 - [ ] 样本量不是无故「未记录」（有 `_batch_status.json` 时应写入分库 N）
+- [ ] RCS 图 md 含 P-overall / P-non-linear 与 cutoff（图上有则写，缺则「未收获」）
+- [ ] KM 图 md 含 Log-rank P 与 cutoff（图上有则写）
+- [ ] Forest 图 md 含 Overall 与各亚组效应量(95%CI)、P for interaction（图上有则写）
 
 ## 反例（禁止）
 
 - 只有一句「Flowchart展示…逐步筛选过程」且无逐步 n
+- RCS 图上有 P-overall / P-non-linear / cutoff，md 却只有「展示非线性关系」等空话
 - 仍保留「图号 / 文件路径 / DPI / TIFF 压缩」两段
 - 课题私自再写一套 image_information 模板绕过公共函数
```
