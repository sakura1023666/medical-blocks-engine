#!/usr/bin/env Rscript
# Thin wrapper: call project Python rebuild for SA-AKI TCF Wang 2025 figure roles,
# then (Python already invokes) pub_figure_ensure_formats.
#
# Usage:
#   Rscript run/ml_tcf_sepsis_aki/rebuild_wang2025_figures.R
#   Rscript run/ml_tcf_sepsis_aki/rebuild_wang2025_figures.R --success-root "/path/to/【success】ALLVARS"

args <- commandArgs(trailingOnly = TRUE)
success_root <- NA_character_
if (length(args)) {
  for (i in seq_along(args)) {
    if (identical(args[[i]], "--success-root") && i < length(args)) {
      success_root <- args[[i + 1L]]
    }
  }
}
if (!nzchar(success_root) || is.na(success_root)) {
  success_root <- "/mnt/g/02block_result/42_AKI_spesis/multi-algorithm fusion_40295871/by_index/\u3010success\u3011ALLVARS"
}

py <- "/mnt/g/02block_result/42_AKI_spesis/multi-algorithm fusion_40295871/scripts/rebuild_wang2025_tcf_figures.py"
if (!file.exists(py)) stop("Missing rebuild script: ", py, call. = FALSE)

cmd <- paste(
  "python3", shQuote(py),
  "--success-root", shQuote(success_root)
)
message("Running: ", cmd)
st <- system(cmd)
quit(status = st)
