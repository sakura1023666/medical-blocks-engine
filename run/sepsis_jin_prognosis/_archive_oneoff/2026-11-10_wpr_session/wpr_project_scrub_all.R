#!/usr/bin/env Rscript
engine <- "/mnt/e/01block/01Block-new-Final"
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)
source(file.path(engine, "R/utils.R"), local = FALSE)
source(file.path(engine, "R/pub_xlsx_surgical.R"), local = FALSE)
source(file.path(engine, "R/pub_qc_underscore.R"), local = FALSE)
source(file.path(engine, "R/pub_figure_export.R"), local = FALSE)

proj <- "/mnt/g/02block_result/36_spesis/prediction_41194138"
cfg <- list(pub_figures = list(
  formats_dir = TRUE, export_png = FALSE, export_tiff = FALSE,
  write_image_information = TRUE, max_edge_in = 16, require_vector_pdf = TRUE
))

by <- list.files(file.path(proj, "by_index"), pattern = "^\u3010success\u3011", full.names = TRUE)
message("success n=", length(by))
n_edit_total <- 0L
for (d in by) {
  for (sr_name in c("summary_results", "summary_result")) {
    tab <- file.path(d, sr_name, "Tables")
    if (!dir.exists(tab)) next
    res <- pub_xlsx_scrub_underscores_dir(tab, root = engine)
    edits <- sum(vapply(res$results, function(x) {
      as.integer(x$n_edit %||% 0L)[1L]
    }, integer(1)))
    n_edit_total <- n_edit_total + edits
    if (edits > 0) message(basename(d), "/", sr_name, " edits=", edits)
    fig <- file.path(d, sr_name, "Figures")
    if (dir.exists(fig)) {
      st <- tryCatch(
        pub_figure_formats_status(fig, config = cfg),
        error = function(e) list(ok = FALSE, error = e$message)
      )
      if (!isTRUE(st$ok)) {
        message("ensure formats: ", basename(d))
        tryCatch(
          pub_figure_ensure_formats(fig, config = cfg),
          error = function(e) message("ensure fail: ", e$message)
        )
      }
    }
  }
}
message("total_edits=", n_edit_total)
hits <- pub_qc_scan_underscores(proj)
message("underscore ok=", hits$ok, " n_bad=", hits$n_bad)
if (is.data.frame(hits$hits) && nrow(hits$hits)) {
  utils::write.csv(hits$hits, "/tmp/wpr_uscore_after.csv", row.names = FALSE)
  print(utils::head(hits$hits, 30))
}
cat("EXIT:0\n")
