# tests/test_cross_lagged_export_summary_figures.R
# Regression: cross-lagged summary_result/figure mosaic + pub export phase script

root <- normalizePath(getwd())
if (!file.exists(file.path(root, "R/utils.R"))) {
  cand <- normalizePath(file.path(".."), winslash = "/")
  if (file.exists(file.path(cand, "R/utils.R"))) root <- cand
}
source(file.path(root, "R/utils.R"), local = FALSE)

make_min_pdf <- function(path) {
  grDevices::pdf(path, width = 3, height = 2, onefile = TRUE)
  plot.new()
  title(basename(path))
  grDevices::dev.off()
}

study_root <- tempfile("cl_export_test_")
fig <- file.path(study_root, "summary_result", "figure")
dir.create(fig, recursive = TRUE)

make_min_pdf(file.path(fig, "Figure 2-CHARLS. RCS plot.pdf"))
make_min_pdf(file.path(fig, "Figure 2-ELSA. RCS plot.pdf"))
make_min_pdf(file.path(fig, "Figure 2-HRS. RCS plot.pdf"))

writeLines(
  "main_grouping=quartile",
  file.path(study_root, "phase3_relock_acceptance.txt")
)

phase_script <- file.path(
  root, "Blocks/54_cross_lagged_full/phases/export_summary_figures.R"
)
stopifnot(file.exists(phase_script))

on.exit(unlink(study_root, recursive = TRUE), add = TRUE)

old_mb <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = NA_character_)
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)
on.exit({
  if (is.na(old_mb)) Sys.unsetenv("MEDICAL_BLOCKS_ROOT") else Sys.setenv(MEDICAL_BLOCKS_ROOT = old_mb)
}, add = TRUE)

run_out <- system2(
  "Rscript",
  c(phase_script, study_root),
  stdout = TRUE,
  stderr = TRUE
)
if (!is.null(attr(run_out, "status")) && attr(run_out, "status") != 0L) {
  stop(
    "export_summary_figures.R failed:\n",
    paste(run_out, collapse = "\n"),
    call. = FALSE
  )
}

combined_stem <- "Figure 2. RCS plot"
stopifnot(file.exists(file.path(fig, "pdf", paste0(combined_stem, ".pdf"))))
stopifnot(file.exists(file.path(fig, "png", paste0(combined_stem, ".png"))))
stopifnot(file.exists(file.path(fig, "tiff", paste0(combined_stem, ".tiff"))))
stopifnot(file.exists(file.path(fig, "image_information", paste0(combined_stem, ".md"))))

loose <- list.files(fig, pattern = "\\.pdf$", ignore.case = TRUE)
stopifnot(length(loose) == 0L)

stopifnot(!file.exists(file.path(fig, "Figure 2-CHARLS. RCS plot.pdf")))
stopifnot(!file.exists(file.path(fig, "pdf", "Figure 2-CHARLS. RCS plot.pdf")))
stopifnot(!file.exists(file.path(fig, "Figure 2-ELSA. RCS plot.pdf")))
stopifnot(!file.exists(file.path(fig, "Figure 2-HRS. RCS plot.pdf")))

cat("test_cross_lagged_export_summary_figures: OK\n")
