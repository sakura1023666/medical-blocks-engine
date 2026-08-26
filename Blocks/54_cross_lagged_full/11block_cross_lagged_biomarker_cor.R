###############################################################################
#  cross_lagged_biomarker_cor — 血液标志物与 FI/抑郁/CVD 相关
###############################################################################

block_cross_lagged_biomarker_cor <- function(ctx, ...) {
  bl <- ctx$config$cross_lagged %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("cross_lagged_biomarker_cor: 无数据", call. = FALSE)
  biomarkers <- bl$biomarker_cols %||% grep("_(T1)$", names(data), value = TRUE)
  biomarkers <- biomarkers[grepl("^(CRP|LDL|HDL|Glucose|HbA1c)", biomarkers)]
  targets <- c(bl$fi_var %||% "FI_T1", bl$mediator_var %||% "Depression_T1", bl$event_var %||% "CVD_event")
  targets <- intersect(targets, names(data))
  rows <- list()
  for (bio in biomarkers) {
    for (tg in targets) {
      x <- as.numeric(data[[bio]]); y <- as.numeric(data[[tg]])
      ok <- is.finite(x) & is.finite(y)
      if (sum(ok) < 20L) next
      ct <- stats::cor.test(x[ok], y[ok])
      rows[[length(rows) + 1L]] <- data.frame(
        biomarker = bio, target = tg, r = round(unname(ct$estimate), 3),
        p = signif(ct$p.value, 3), n = sum(ok), stringsAsFactors = FALSE
      )
    }
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "no biomarkers")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Biomarker_Correlation.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$cross_lagged_biomarker <- list(table = tab)
  cli::cli_alert_success("血液标志物相关完成")
  ctx
}

register_block("cross_lagged_biomarker_cor", block_cross_lagged_biomarker_cor, "血液标志物相关")
