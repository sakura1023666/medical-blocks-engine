#!/usr/bin/env Rscript
# Thin wrapper: paper-style Fig4 is drawn by matplotlib (Ma et al. geometry)
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", "/mnt/e/01block/01Block-new-Final")
py <- file.path(root, "run/ssd_lpa_network_mediation/redraw_fig4_mediation_matplotlib.py")
status <- system2("python3", py)
if (!identical(as.integer(status), 0L)) stop("fig4 matplotlib redraw failed")
