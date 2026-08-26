#!/usr/bin/env Rscript
root <- "/mnt/e/01block/01Block-new-Final"
cfg <- "/mnt/g/02block_result/19_Rheumatoid Arthritis/incidence_38341157/Data/config_incidence_mimic_batch.R"
source(file.path(root, "R/utils.R"))
source(cfg)
source(file.path(root, "R/pipeline_extension_guard.R"))

base <- jsonlite::fromJSON(
  file.path(root, "configs/study_interface/baseline_pipelines.json"),
  simplifyVector = FALSE
)
inc <- base$incidence
for (key in names(inc)) {
  live <- get(key)
  live_b <- as.character(live$blocks)
  base_b <- unlist(inc[[key]]$blocks)
  extra <- setdiff(live_b, base_b)
  missing <- setdiff(base_b, live_b)
  cat("\n==", key, "==\n")
  cat("live n=", length(live_b), " base n=", length(base_b), "\n")
  cat("extra:", paste(extra, collapse = ", "), "\n")
  cat("missing:", paste(missing, collapse = ", "), "\n")
}
