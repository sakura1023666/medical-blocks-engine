#!/usr/bin/env Rscript
###############################################################################
#  scripts/export_block_catalog.R
#
#  Export read-only block catalog for programmer search.
#  Usage: Rscript scripts/export_block_catalog.R [--out DIR] [ROOT]
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

args <- commandArgs(trailingOnly = TRUE)
out_dir <- NULL
root <- NULL

i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--out" && i < length(args)) {
    out_dir <- args[[i + 1L]]
    i <- i + 2L
  } else if (startsWith(a, "--")) {
    stop("未知参数: ", a, call. = FALSE)
  } else if (is.null(root)) {
    root <- a
    i <- i + 1L
  } else {
    stop("多余参数: ", a, call. = FALSE)
  }
}

root <- normalizePath(
  root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "."),
  winslash = "/",
  mustWork = TRUE
)
if (is.null(out_dir) || !nzchar(out_dir)) {
  out_dir <- file.path(root, "docs/block_catalog")
}
out_dir <- normalizePath(out_dir, winslash = "/", mustWork = FALSE)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/block_catalog_export.R"))

export_block_catalog(root, out_dir)
cat("Wrote block catalog to", out_dir, "\n")
