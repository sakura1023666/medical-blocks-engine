###############################################################################
#  tst_pub_export — 发表级交付物汇总（仅 step 子目录，不 mirror 根目录）
#
#  依据: docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md §7
#
#  config$tst_pub_export（可选）:
#    deliverables_dirname = "TST_pub_deliverables"
#    checklist_filename = "Pub_deliverables_checklist.csv"
#    manifest_filename = "00_Literature_Output_Manifest.csv"
#
#  核对并 copy/rename 至本 block step 下 TST_pub_deliverables/{Tables,Figures}:
#    flowchart, Table1, performance, ROC, calibration, DCA, SHAP, ablation,
#    synthetic external（标注 synthetic）
#
#  硬约束: config$project$mirror_pub_outputs_to_root=FALSE 时不得调用
#    mirror_pub_output_to_root / sync_all_block_pub_outputs_to_root
###############################################################################

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && !nzchar(a))) b else a

.tst71_root <- function(ctx) ctx$config$project$root %||% getwd()

.tst71_pub_search_roots <- function(ctx) {
  roots <- character(0)
  bod <- ctx$log$block_output_dirs %||% list()
  for (d in bod) {
    if (is.character(d) && nzchar(d)) roots <- c(roots, d)
  }
  out <- ctx$output_dir %||% NULL
  if (!is.null(out) && nzchar(out)) roots <- c(roots, out)
  root <- .tst71_root(ctx)
  roots <- c(
    roots,
    Sys.glob(file.path(root, "Output", "_smoke*", "*")),
    Sys.glob(file.path(root, "Output", "TwoStage_Transformer_Stroke", "*"))
  )
  unique(roots[dir.exists(roots)])
}

.tst71_pub_first_hit <- function(roots, patterns, subdir = c("Tables", "Figures", "")) {
  for (r in roots) {
    for (sd in subdir) {
      base <- if (nzchar(sd)) file.path(r, sd) else r
      if (!dir.exists(base)) next
      for (pat in patterns) {
        hits <- Sys.glob(file.path(base, pat))
        hits <- hits[file.exists(hits) & !dir.exists(hits)]
        if (length(hits)) return(hits[[1L]])
      }
      hits <- list.files(base, pattern = paste0("(", paste(patterns, collapse = ")|("), ")"),
                         full.names = TRUE, ignore.case = TRUE, recursive = TRUE)
      hits <- hits[file.exists(hits) & !dir.exists(hits)]
      if (length(hits)) return(hits[[1L]])
    }
  }
  NA_character_
}

.tst71_pub_default_items <- function() {
  list(
    list(
      key = "Flowchart",
      category = "flowchart",
      dst = "Tables/Table_Flowchart-TST_cohort_counts.csv",
      patterns = c("_tst_cohort_flowchart.csv", "*flowchart*.csv")
    ),
    list(
      key = "Table1_Baseline",
      category = "Table1",
      dst = "Tables/Table1-TST-MIMIC_baseline_hosp_death.xlsx",
      patterns = c("Table 1-MIMIC*.xlsx", "Table 1-MIMIC*.tex", "Table1*baseline*.xlsx")
    ),
    list(
      key = "Performance_Metrics",
      category = "performance",
      dst = "Tables/Table_TST_Performance_Metrics.csv",
      patterns = c("Table_TST_Metrics_*.csv", "Table_TST_Baselines.csv")
    ),
    list(
      key = "ROC",
      category = "ROC",
      dst = "Figures/Figure_TST_ROC.pdf",
      patterns = c("*ROC*.pdf", "*ROC*.png", "Figure*ROC*")
    ),
    list(
      key = "Calibration_Table",
      category = "calibration",
      dst = "Tables/Table_TST_Calibration.csv",
      patterns = c("Table_TST_Calibration.csv")
    ),
    list(
      key = "Calibration_Figure",
      category = "calibration",
      dst = "Figures/Figure_TST_Calibration.pdf",
      patterns = c("*Calibration*.pdf", "*Calibration*.png", "*calibration*")
    ),
    list(
      key = "DCA_Table",
      category = "DCA",
      dst = "Tables/Table_TST_DCA.csv",
      patterns = c("Table_TST_DCA.csv")
    ),
    list(
      key = "DCA_Figure",
      category = "DCA",
      dst = "Figures/Figure_TST_DCA.pdf",
      patterns = c("*DCA*.pdf", "*DCA*.png", "*decision*curve*")
    ),
    list(
      key = "SHAP_Table",
      category = "SHAP",
      dst = "Tables/Table_TST_SHAP_Importance.csv",
      patterns = c("Table_TST_SHAP*.csv", "*SHAP*importance*.csv")
    ),
    list(
      key = "SHAP_Figure",
      category = "SHAP",
      dst = "Figures/Figure_TST_SHAP_heatmap.png",
      patterns = c("*SHAP*.png", "*SHAP*.pdf", "*shap*")
    ),
    list(
      key = "Ablation",
      category = "ablation",
      dst = "Tables/Table_TST_Ablation.csv",
      patterns = c("Table_TST_Ablation.csv")
    ),
    list(
      key = "External_Synthetic",
      category = "synthetic_external",
      dst = "Tables/Table_External_Synthetic_Metrics_LABELED.csv",
      patterns = c("Table_External_Synthetic_Metrics.csv", "_tst_external_stamp.csv")
    )
  )
}

.tst71_pub_copy_item <- function(src, dst) {
  dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
  if (identical(normalizePath(src, winslash = "/", mustWork = FALSE),
                normalizePath(dst, winslash = "/", mustWork = FALSE))) {
    return(TRUE)
  }
  file.copy(src, dst, overwrite = TRUE)
}

.tst71_pub_label_synthetic <- function(src, dst) {
  if (!grepl("\\.csv$", src, ignore.case = TRUE)) {
    return(.tst71_pub_copy_item(src, dst))
  }
  df <- tryCatch(
    utils::read.csv(src, stringsAsFactors = FALSE),
    error = function(e) NULL
  )
  if (is.null(df) || !nrow(df)) return(.tst71_pub_copy_item(src, dst))
  if (!"is_synthetic" %in% names(df)) df$is_synthetic <- TRUE
  if (!"synthetic_label" %in% names(df)) {
    df$synthetic_label <- "SYNTHETIC — not for primary manuscript conclusions"
  }
  utils::write.csv(df, dst, row.names = FALSE)
  TRUE
}

block_tst_pub_export <- function(ctx, ...) {
  suppressPackageStartupMessages(library(cli))
  cfg <- ctx$config
  bl <- cfg$tst_pub_export %||% list()
  prj <- cfg$project %||% list()
  mirror_on <- isTRUE(prj$mirror_pub_outputs_to_root %||% FALSE)

  deliv_name <- as.character(bl$deliverables_dirname %||% "TST_pub_deliverables")[1L]
  step_dir <- ctx$output_dir %||% file.path(prj$output_dir %||% "Output", "step_tst_pub_export")
  deliv <- file.path(step_dir, deliv_name)
  if (dir.exists(deliv)) unlink(deliv, recursive = TRUE, force = TRUE)
  dir.create(file.path(deliv, "Tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(deliv, "Figures"), recursive = TRUE, showWarnings = FALSE)

  items <- bl$checklist %||% bl$items %||% .tst71_pub_default_items()
  if (is.data.frame(items)) {
    items <- lapply(seq_len(nrow(items)), function(i) {
      list(
        key = as.character(items$key[i]),
        category = as.character(items$category[i] %||% items$key[i]),
        dst = as.character(items$dst[i]),
        patterns = strsplit(as.character(items$patterns[i]), "\\|")[[1L]]
      )
    })
  }

  search_roots <- .tst71_pub_search_roots(ctx)
  rows <- vector("list", length(items))

  for (i in seq_along(items)) {
    it <- items[[i]]
    pats <- it$patterns %||% character(0)
    src <- .tst71_pub_first_hit(search_roots, pats)
    dst_rel <- as.character(it$dst)[1L]
    dst <- file.path(deliv, dst_rel)
    found <- !is.na(src) && file.exists(src)
    copied <- FALSE
    if (found) {
      copied <- if (identical(it$category, "synthetic_external") ||
                     grepl("Synthetic", basename(src), ignore.case = TRUE)) {
        .tst71_pub_label_synthetic(src, dst)
      } else {
        .tst71_pub_copy_item(src, dst)
      }
    }
    rows[[i]] <- data.frame(
      key = as.character(it$key),
      category = as.character(it$category %||% it$key),
      expected = dst_rel,
      found = found,
      source_path = if (found) src else NA_character_,
      dest_path = if (copied) dst else NA_character_,
      status = if (copied) "PASS" else "MISSING",
      stringsAsFactors = FALSE
    )
  }
  checklist <- do.call(rbind, rows)
  n_pass <- sum(checklist$status == "PASS")

  chk_fn <- as.character(bl$checklist_filename %||% "Pub_deliverables_checklist.csv")[1L]
  chk_path <- file.path(deliv, chk_fn)
  utils::write.csv(checklist, chk_path, row.names = FALSE)

  manifest_rows <- checklist[checklist$status == "PASS", c("category", "expected", "dest_path"), drop = FALSE]
  manifest_rows$type <- ifelse(grepl("^Figures/", manifest_rows$expected), "Figure", "Table")
  manifest <- manifest_rows[, c("type", "expected", "dest_path")]
  manifest_fn <- as.character(bl$manifest_filename %||% "00_Literature_Output_Manifest.csv")[1L]
  manifest_path <- file.path(deliv, manifest_fn)
  utils::write.csv(manifest, manifest_path, row.names = FALSE)

  writeLines(
    c(
      "# TST_pub_deliverables",
      "",
      "由 block `tst_pub_export` 自上游 step 子目录 copy/rename 生成。",
      sprintf("mirror_pub_outputs_to_root=%s（本块不镜像 Output 根目录）。", mirror_on),
      "合成外推表含 synthetic_label 列；不得写入正式主文结论。",
      sprintf("PASS %d / %d 项。", n_pass, nrow(checklist))
    ),
    file.path(deliv, "README.md")
  )

  if (mirror_on) {
    cli::cli_alert_info(
      "tst_pub_export: mirror_pub_outputs_to_root=TRUE，但本套路默认不镜像；已跳过 mirror_pub_output_to_root。"
    )
  } else {
    cli::cli_alert_info("tst_pub_export: mirror_pub_outputs_to_root=FALSE，未调用 mirror_pub_output_to_root。")
  }

  ctx$results$tst_pub_export <- list(
    deliverables_dir = deliv,
    checklist = checklist,
    checklist_path = chk_path,
    manifest_path = manifest_path,
    n_pass = n_pass,
    n_total = nrow(checklist),
    mirrored = FALSE,
    mirror_skipped_reason = if (mirror_on) "tst_stroke_policy_no_root_mirror" else "mirror_pub_outputs_to_root=FALSE"
  )
  cli::cli_alert_success(
    "tst_pub_export: {n_pass}/{nrow(checklist)} 项 @ {deliv}"
  )
  ctx
}

register_block(
  "tst_pub_export",
  block_tst_pub_export,
  "两阶段 Transformer 卒中：发表交付物汇总（step 子目录 only）"
)
