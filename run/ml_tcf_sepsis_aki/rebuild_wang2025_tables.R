#!/usr/bin/env Rscript
# Engine entry: Wang 2025 TCF table rebuild.
# Forwards argv to rebuild_wang2025_tables_core.R (SCI xlsx + Python compute).
#
# Usage:
#   Rscript run/ml_tcf_sepsis_aki/rebuild_wang2025_tables.R \
#     --success-root "/path/to/by_index/【success】ALLVARS"
#   Rscript run/ml_tcf_sepsis_aki/rebuild_wang2025_tables.R --only "Table S10"

args <- commandArgs(trailingOnly = TRUE)

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

core <- file.path(engine_root, "run", "ml_tcf_sepsis_aki", "rebuild_wang2025_tables_core.R")
if (!file.exists(core)) stop("Missing tables core: ", core)

# Ensure engine_root is visible to core even if argv omits --engine-root
if (!any(args == "--engine-root")) {
  args <- c(args, "--engine-root", engine_root)
}

rscript <- file.path(R.home("bin"), "Rscript")
if (!file.exists(rscript)) rscript <- Sys.which("Rscript")
if (!nzchar(rscript)) stop("Rscript not found")

message("[tcf-tables] ", rscript, " ", core)
st <- system2(rscript, args = c(core, args))
if (!identical(as.integer(st), 0L)) stop("Table rebuild failed, status=", st)
