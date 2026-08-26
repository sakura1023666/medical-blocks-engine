###############################################################################
#  trf_literature_validate — Zhong 2025 REACT AUROC 对照
###############################################################################

block_trf_literature_validate <- function(ctx, ...) {
  bl <- ctx$config$transformer_aki %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_validation.R"), local = FALSE)
  targets <- bl$literature_targets %||% list(auroc_internal = 0.93, auroc_external = 0.92, early_hours = 16.35)
  tol <- as.numeric(bl$literature_tol_pct %||% 25)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Transformer", "Table_Transformer_Metrics.csv")
  rows <- list()
  if (file.exists(out)) {
    met <- utils::read.csv(out, stringsAsFactors = FALSE)
    if ("auroc" %in% names(met)) {
      int_hit <- met[grepl("internal|fold", met$split %||% "", ignore.case = TRUE), , drop = FALSE]
      if (!nrow(int_hit)) int_hit <- met
      rows[[1L]] <- literature_compare_metric(mean(int_hit$auroc, na.rm = TRUE), targets$auroc_internal, tol, "Internal AUROC")
      if (any(grepl("external", met$split %||% "", ignore.case = TRUE))) {
        ext <- met[grepl("external", met$split, ignore.case = TRUE), , drop = FALSE]
        rows[[length(rows) + 1L]] <- literature_compare_metric(mean(ext$auroc, na.rm = TRUE), targets$auroc_external, tol, "External AUROC")
      }
    }
  }
  det <- (ctx$results$trf_early_detection %||% list())$table
  if (!is.null(det) && "mean" %in% names(det)) {
    rows[[length(rows) + 1L]] <- literature_compare_metric(det$mean[1L], targets$early_hours, tol, "Early detection hours")
  }
  outv <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Transformer_Literature_Validation.csv")
  tab <- literature_write_validation(rows, outv, meta = list(paper = "Zhong 2025 Lancet Digit Health", tol_pct = tol))
  ctx$results$trf_literature_validate <- list(table = tab, pass = sum(tab$within_tol %in% TRUE, na.rm = TRUE))
  cli::cli_alert_success("Transformer 文献对照完成")
  ctx
}

register_block("trf_literature_validate", block_trf_literature_validate, "Transformer 文献对照")
