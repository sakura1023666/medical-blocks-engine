#!/usr/bin/env Rscript
# Engine entry: Wang 2025 TCF figure rebuild (PDF + image_information).
# Prefer this over project scripts/ copies.
#
# Usage:
#   Rscript run/ml_tcf_sepsis_aki/rebuild_wang2025_figures.R \
#     --success-root "/path/to/by_index/【success】ALLVARS"
#   MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
#     Rscript run/ml_tcf_sepsis_aki/rebuild_wang2025_figures.R --success-root ...

args <- commandArgs(trailingOnly = TRUE)
success_root <- NA_character_
i <- 1L
while (i <= length(args)) {
  if (args[[i]] %in% c("--success-root", "--root") && i < length(args)) {
    success_root <- args[[i + 1L]]
    i <- i + 2L
  } else {
    i <- i + 1L
  }
}
if (is.na(success_root) || !nzchar(success_root)) {
  success_root <- "/mnt/g/02block_result/42_AKI_spesis/multi-algorithm fusion_40295871/by_index/【success】ALLVARS"
}

engine_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine_root)) {
  for (cand in c("/mnt/e/01block/01Block-new-Final", "E:/01block/01Block-new-Final")) {
    if (dir.exists(cand)) {
      engine_root <- cand
      break
    }
  }
}
if (!nzchar(engine_root) || !dir.exists(engine_root)) {
  stop("Set MEDICAL_BLOCKS_ROOT to the medical-blocks engine root")
}

py <- file.path(engine_root, "python", "ml_tcf", "pub", "rebuild_wang2025_figures.py")
if (!file.exists(py)) stop("Missing engine figure script: ", py)

py_bin <- Sys.getenv("MEDICAL_BLOCKS_PYTHON", unset = "")
if (!nzchar(py_bin)) {
  for (cand in c("python3", "python")) {
    if (nzchar(Sys.which(cand))) {
      py_bin <- cand
      break
    }
  }
}
if (!nzchar(py_bin)) stop("python3/python not found")

cmd <- sprintf(
  "%s %s --success-root %s",
  shQuote(py_bin),
  shQuote(py),
  shQuote(normalizePath(success_root, winslash = "/", mustWork = TRUE))
)
message("[tcf-fig] ", cmd)
st <- system(cmd)
if (!identical(as.integer(st), 0L)) stop("Figure rebuild failed, status=", st)

# PDF-only ensure (respects config$pub_figures$export_png/tiff if present)
src_pub <- file.path(engine_root, "R", "pub_figure_export.R")
if (file.exists(src_pub)) {
  source(src_pub, local = TRUE)
  figs <- file.path(success_root, "summary_results", "Figures")
  if (dir.exists(figs) && exists("pub_figure_ensure_formats")) {
    cfg <- list(pub_figures = list(export_png = FALSE, export_tiff = FALSE, dpi = 600L))
    try(pub_figure_ensure_formats(figs, config = cfg), silent = TRUE)
  }
}
message("[tcf-fig] OK → ", file.path(success_root, "summary_results", "Figures"))
