#!/usr/bin/env Rscript
# WPR delivery P0: scrub Index_SOFA underscores + ensure PDF geometry + Methods scrub
engine <- "/mnt/e/01block/01Block-new-Final"
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)
source(file.path(engine, "R/utils.R"), local = FALSE)
source(file.path(engine, "R/pub_xlsx_surgical.R"), local = FALSE)
source(file.path(engine, "R/pub_figure_export.R"), local = FALSE)
source(file.path(engine, "R/pub_qc_underscore.R"), local = FALSE)
source(file.path(engine, "R/pub_software_versions.R"), local = FALSE)
source(file.path(engine, "R/pub_delivery_prune.R"), local = FALSE)

sr <- "/mnt/g/02block_result/36_spesis/prediction_41194138/by_index/\u3010success\u3011WPR/summary_results"
stopifnot(dir.exists(sr))
tab <- file.path(sr, "Tables")
fig <- file.path(sr, "Figures")

message("== scrub xlsx ==")
scrub <- pub_xlsx_scrub_underscores_dir(tab, root = engine)
print(vapply(scrub$results, function(x) x$n_edit %||% NA_integer_, integer(1)))

message("== ensure formats max_edge=16 ==")
st1 <- pub_figure_formats_status(
  fig,
  config = list(pub_figures = list(
    formats_dir = TRUE, export_png = FALSE, export_tiff = FALSE,
    max_edge_in = 16, require_vector_pdf = TRUE
  ))
)
message("before ok=", st1$ok, " bad_geom=", length(st1$bad_pdf_geometry %||% character(0)))
pub_figure_ensure_formats(
  fig,
  config = list(pub_figures = list(
    formats_dir = TRUE, export_png = FALSE, export_tiff = FALSE,
    write_image_information = TRUE, max_edge_in = 16, require_vector_pdf = TRUE
  ))
)
st2 <- pub_figure_formats_status(
  fig,
  config = list(pub_figures = list(
    formats_dir = TRUE, export_png = FALSE, export_tiff = FALSE,
    max_edge_in = 16, require_vector_pdf = TRUE
  ))
)
message("after ok=", st2$ok, " bad_geom=", paste(st2$bad_pdf_geometry %||% character(0), collapse = " | "))

message("== Methods scrub underscores ==")
md <- file.path(sr, "Methods_statistical_analysis.md")
txt <- readLines(md, warn = FALSE, encoding = "UTF-8")
txt2 <- gsub("Index_SOFA_Q", "Index\u00d7SOFA Q", txt, fixed = TRUE)
txt2 <- gsub("Index_SOFA", "Index SOFA", txt2, fixed = TRUE)
txt2 <- gsub("Neutrophil_Count", "Neutrophil Count", txt2, fixed = TRUE)
txt2 <- gsub("Bootstrap densitites", "Bootstrap densities", txt2, fixed = TRUE)
## keep file names in Software pointer readable without programming tokens in prose
writeLines(txt2, md, useBytes = FALSE)

message("== software versions refresh ==")
if (exists("pub_write_software_versions", mode = "function")) {
  pub_write_software_versions(sr, project_root = dirname(dirname(sr)), config = list())
}

message("== underscore rescan WPR only ==")
hits <- pub_qc_scan_underscores(dirname(dirname(sr))) ## project root; will scan all success
## filter WPR
if (is.data.frame(hits$hits) && nrow(hits$hits)) {
  w <- hits$hits[grepl("WPR", hits$hits$path), , drop = FALSE]
  message("WPR underscore hits: ", nrow(w))
  if (nrow(w)) print(w)
} else {
  message("WPR underscore hits: 0 (global ok=", hits$ok, " n_bad=", hits$n_bad, ")")
}

message("== prune ==")
pub_prune_delivery_root(sr)
message("DONE")
cat("EXIT:0\n")
