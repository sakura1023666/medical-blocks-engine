#!/usr/bin/env Rscript
root <- "/mnt/e/01block/01Block-new-Final"
cfg <- "/mnt/g/02block_result/19_Rheumatoid Arthritis/incidence_38341157/Data/config_incidence_mimic_batch.R"
setwd(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(cfg)
source(file.path(root, "R/pipeline_extension_guard.R"))
tryCatch({
  pipeline_extension_guard_check(
    routine = "incidence",
    pipelines = list(
      pipeline_nhanes_batch = pipeline_nhanes_batch,
      pipeline_regular_batch = pipeline_regular_batch,
      pipeline_shared_nhanes = pipeline_shared_nhanes,
      pipeline_shared_regular = pipeline_shared_regular
    ),
    study_dir = dirname(cfg),
    root = root
  )
  cat("GUARD OK\n")
}, error = function(e) {
  cat("GUARD FAIL:", conditionMessage(e), "\n")
  base <- .pipeline_guard_load_baseline(root)$incidence
  for (key in c("pipeline_nhanes_batch", "pipeline_regular_batch")) {
    live <- .pipeline_guard_as_chr(get(key))
    basev <- .pipeline_guard_as_chr(base[[key]])
    cat(key, "extra=", paste(setdiff(live, basev), collapse=","),
        " miss=", paste(setdiff(basev, live), collapse=","), "\n")
    cat(" identical=", identical(live, basev), "\n")
  }
})
